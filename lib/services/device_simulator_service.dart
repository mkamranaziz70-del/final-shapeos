// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'device_profile_service.dart';

/// =========================================================
/// DEVICE SIMULATOR
/// =========================================================
/// While the ESP32 hardware isn't physically connected (e.g.
/// during a panel demo), the live readings in `/appliances/`
/// would all sit at zero. This service writes realistic,
/// gently-fluctuating values — 12.0 V ± 0.25 V for a 12 V DC
/// fan, 220 V ± 1.6 V for a 220 V AC bulb, etc. — every two
/// seconds so the energy / readings UI looks alive.
///
/// It also exposes [simulateSurge] and [simulateLeakage] so
/// the Voltage Surge / Leakage demo screens can briefly push
/// values out of band, which the anomaly detector sees and
/// auto-cuts.
///
/// When real hardware is connected later, the ESP32's writes
/// will arrive at higher frequency and effectively override
/// these synthetic ones.
class DeviceSimulatorService {
  DeviceSimulatorService._();

  static final Random _rng = Random();
  static Timer? _ticker;
  static bool _enabled = false;

  /// Active overrides — when an entry is present and not yet
  /// expired, the simulator writes the override values instead
  /// of the nominal jittered ones.
  static final Map<String, _Override> _overrides = {};

  /// Energy accumulator (kWh) in app memory. We add to this
  /// each tick proportionally to the instantaneous power so
  /// the energy reading also climbs realistically.
  static final Map<String, double> _energyKWh = {};

  static const Duration _tickEvery = Duration(seconds: 2);

  static bool get isRunning => _enabled;

  /// Idempotent. Call once at app launch.
  static Future<void> start() async {
    if (_enabled) return;
    _enabled = true;
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickEvery, (_) => _tick());
    // Run an immediate first tick so the UI doesn't sit on zeros
    // for two seconds after launch.
    unawaited(_tick());
  }

  static Future<void> stop() async {
    _enabled = false;
    _ticker?.cancel();
    _ticker = null;
  }

  /// Drive the device into a voltage-surge state for [duration].
  /// The detector will trip and the device will be auto-cut.
  static void simulateSurge(
    String deviceId, {
    Duration duration = const Duration(seconds: 5),
  }) {
    final profile = DeviceProfileService.of(deviceId);
    if (profile == null) return;
    _overrides[deviceId] = _Override(
      voltage: profile.surgeVoltage,
      current: profile.nominalCurrent * 1.4,
      expiresAt: DateTime.now().add(duration),
    );
  }

  /// Drive the device into a leakage-fault state for [duration].
  static void simulateLeakage(
    String deviceId, {
    Duration duration = const Duration(seconds: 5),
  }) {
    final profile = DeviceProfileService.of(deviceId);
    if (profile == null) return;
    _overrides[deviceId] = _Override(
      voltage: profile.nominalVoltage,
      current: profile.nominalCurrent,
      leakage: profile.leakageCurrent,
      expiresAt: DateTime.now().add(duration),
    );
  }

  /// Drop any active override for a device — used after auto-cut.
  static void clearOverride(String deviceId) {
    _overrides.remove(deviceId);
  }

  // =========================================================
  // CORE TICK
  // =========================================================
  static Future<void> _tick() async {
    if (!_enabled) return;
    try {
      final ref = FirebaseDatabase.instance.ref("appliances");
      final snap = await ref.get();
      final raw = snap.value;
      if (raw is! Map && raw is! List) return;

      final entries = <MapEntry<String, dynamic>>[];
      if (raw is Map) {
        raw.forEach((k, v) {
          entries.add(MapEntry(k.toString(), v));
        });
      } else if (raw is List) {
        for (var i = 0; i < raw.length; i++) {
          entries.add(MapEntry(i.toString(), raw[i]));
        }
      }

      for (final entry in entries) {
        final id = entry.key;
        final data = entry.value;
        if (data is! Map) continue;
        final profile = DeviceProfileService.of(id);
        if (profile == null) continue;

        final isOn = data["isOn"] == true;
        final patch = _computePatch(
          id: id,
          isOn: isOn,
          profile: profile,
        );
        await ref.child(id).update(patch);
      }
    } catch (e) {
      debugPrint("DeviceSimulatorService tick failed: $e");
    }
  }

  /// Seed the energy accumulator with a realistic "already used
  /// X kWh today" value the first time we ever see a device, so
  /// the energy column doesn't sit on 0.000 for the first 30
  /// minutes of the demo.
  static void _ensureEnergySeeded(String id, DeviceProfile profile) {
    if (_energyKWh.containsKey(id)) return;
    final now = DateTime.now();
    // Hours since 6 AM today (clamped to 0..16 — covers most demo windows).
    final hoursActive =
        ((now.hour + now.minute / 60.0) - 6.0).clamp(0.0, 16.0);
    final kw = profile.nominalVoltage * profile.nominalCurrent / 1000.0;
    // Assume ~30% duty cycle over the day.
    _energyKWh[id] = kw * hoursActive * 0.30;
  }

  static Map<String, dynamic> _computePatch({
    required String id,
    required bool isOn,
    required DeviceProfile profile,
  }) {
    _ensureEnergySeeded(id, profile);

    if (!isOn) {
      return {
        "voltage": 0.0,
        "current": 0.0,
        "power": 0.0,
        "currentLeakage": 0.0,
        // Energy is a running daily total — keep showing it even
        // when the device is off so the dashboards stay populated.
        "energy": double.parse(_energyKWh[id]!.toStringAsFixed(4)),
      };
    }

    final ov = _overrides[id];
    final overrideActive =
        ov != null && DateTime.now().isBefore(ov.expiresAt);

    double voltage;
    double current;
    double leakage = 0.0;

    if (overrideActive) {
      // Surge / leakage path — values intentionally outside the
      // safe band so the detector trips and the auto-cut module
      // engages.
      voltage = ov.voltage ?? profile.nominalVoltage;
      current = ov.current ?? profile.nominalCurrent;
      leakage = ov.leakage ?? 0.0;
    } else {
      if (ov != null) _overrides.remove(id);

      // Normal operation. Compute jitter, then HARD-CLAMP inside
      // the safe band with a 0.2 V / 0.05 A margin so natural
      // fluctuation can never trip the anomaly detector. Anomalies
      // must come exclusively from the surge / leakage simulate
      // buttons.
      final rawV = profile.nominalVoltage +
          (_rng.nextDouble() - 0.5) * 2 * profile.voltageJitter;
      voltage = rawV.clamp(
        profile.safeVoltageMin + 0.2,
        profile.safeVoltageMax - 0.2,
      );

      final rawI = profile.nominalCurrent +
          (_rng.nextDouble() - 0.5) * 2 * profile.currentJitter;
      current = rawI.clamp(
        profile.nominalCurrent * 0.5,
        profile.safeCurrentMax * 0.85,
      );

      // Tiny natural leakage noise, far below the safe limit.
      leakage = _rng.nextDouble() * 0.005;
    }

    final power = (profile.currentType == "AC")
        ? voltage * current * 0.95 // power factor ~0.95
        : voltage * current;

    // Accumulate energy (kWh) over this tick.
    final hours = _tickEvery.inMilliseconds / 3600000.0;
    final inc = (power / 1000.0) * hours;
    _energyKWh[id] = (_energyKWh[id] ?? 0) + inc;

    return {
      "voltage": double.parse(voltage.toStringAsFixed(2)),
      "current": double.parse(current.toStringAsFixed(3)),
      "power": double.parse(power.toStringAsFixed(2)),
      "currentLeakage": double.parse(leakage.toStringAsFixed(4)),
      "energy": double.parse(_energyKWh[id]!.toStringAsFixed(4)),
    };
  }
}

class _Override {
  final double? voltage;
  final double? current;
  final double? leakage;
  final DateTime expiresAt;
  const _Override({
    this.voltage,
    this.current,
    this.leakage,
    required this.expiresAt,
  });
}
