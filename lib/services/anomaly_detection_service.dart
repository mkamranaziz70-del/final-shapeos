import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/anomaly_record.dart';
import '../models/device_model.dart';
import 'agent_action_logger.dart';
import 'device_profile_service.dart';
import 'device_simulator_service.dart';
import 'device_threshold_service.dart';
import 'voice_service.dart';

/// =========================================================
/// ANOMALY DETECTION SERVICE
/// =========================================================
/// Real-time, rolling heuristics over the live device list:
///   • voltage out-of-band (any device, not just bulb)
///   • current spike vs. nameplate
///   • abnormal current leakage
///   • device left ON for too long while no motion is seen
///
/// Stateful per device — each detection is announced once
/// per condition and re-armed when the condition clears.
class AnomalyEvent {
  final String deviceId;
  final String deviceName;
  final String severity;
  final String message;
  final DateTime detectedAt;

  const AnomalyEvent({
    required this.deviceId,
    required this.deviceName,
    required this.severity,
    required this.message,
    required this.detectedAt,
  });
}

class AnomalyDetectionService {
  AnomalyDetectionService._();

  static const double _voltMin = 200.0;
  static const double _voltMax = 240.0;
  static const double _currentMaxFan = 1.5;
  static const double _currentMaxBulb = 0.8;
  static const double _currentMaxPump = 6.0;
  static const double _leakageMax = 0.05;
  static const Duration _idleWithMotionGrace = Duration(minutes: 30);

  /// Per-device fingerprint of the most recently announced
  /// anomaly so we don't spam the user.
  static final Map<String, String> _lastFingerprint = {};
  static final Map<String, DateTime> _onSince = {};

  /// Run one detection pass over the current device snapshot.
  /// Returns the set of fresh anomalies.
  ///
  /// Reads any user-configured per-device thresholds from
  /// [DeviceThresholdService]; falls back to the safe global
  /// constants above when the user hasn't customised.
  ///
  /// Skips voltage / current checks when the live reading is
  /// effectively zero — that means the ESP32 hasn't pushed a
  /// reading yet, NOT that the device is unsafe.
  static Future<List<AnomalyEvent>> evaluate({
    required List<DeviceModel> devices,
    required bool motionRecent,
  }) async {
    final out = <AnomalyEvent>[];
    final now = DateTime.now();

    // Pull the per-device threshold map once per pass.
    final userThresholds = <String, DeviceThreshold>{
      for (final t in await DeviceThresholdService.all()) t.deviceId: t,
    };

    for (final d in devices) {
      // Track on-since for idle detection.
      if (d.isOn) {
        _onSince.putIfAbsent(d.id, () => now);
      } else {
        _onSince.remove(d.id);
      }

      final issues = <String>[];
      final profile = DeviceProfileService.of(d.id);

      // Auto-cut decisions ALWAYS use the profile band (real-world
      // tolerance for that AC/DC class), never the user-set threshold.
      // Otherwise an over-tight user threshold would flag normal
      // jitter as an anomaly and shut the device off — exactly the
      // bug the user was hitting.
      // (User thresholds are still stored & visible to the agent
      // for advisory purposes — see DeviceThresholdService.)
      final vMin = profile?.safeVoltageMin ?? _voltMin;
      final vMax = profile?.safeVoltageMax ?? _voltMax;
      // We keep the user threshold reference around in case future
      // logic wants to flag *advisory* issues without auto-cutting.
      // ignore: unused_local_variable
      final advisoryUserT = userThresholds[d.id];

      // Floor for "is this even a real reading?" — scales with the
      // device. A 12 V DC fan reading 5 V means trouble, but 5 V
      // on a 220 V AC bulb just means the ESP32 hasn't pushed yet.
      final realReadingFloor =
          (profile?.nominalVoltage ?? 220) * 0.4;

      // Voltage check — only when device is on AND the reading
      // looks like a real one (above the floor). The simulator
      // clamps normal jitter strictly inside [vMin+0.2, vMax-0.2],
      // so the only path to firing this is the surge button.
      if (d.isOn &&
          d.voltage > realReadingFloor &&
          (d.voltage < vMin || d.voltage > vMax)) {
        issues.add(
          "voltage ${d.voltage.toStringAsFixed(1)} V is outside the "
          "safe ${vMin.toStringAsFixed(0)}–${vMax.toStringAsFixed(0)} V "
          "band for this ${profile?.currentType ?? 'AC'} device",
        );
      }

      // Current check — gated on a non-zero reading and uses the
      // profile cap, not a user override.
      final currentLimit =
          profile?.safeCurrentMax ?? _currentLimitFor(d.type);
      if (d.isOn && d.current > 0.02 && d.current > currentLimit) {
        issues.add(
          "current draw ${d.current.toStringAsFixed(2)} A exceeds the "
          "${currentLimit.toStringAsFixed(2)} A limit",
        );
      }

      // Leakage check — must be gated on isOn so a stale leakage
      // value left in Firebase from a previous Simulate Leakage
      // run can never auto-cut a freshly-turned-on device.
      if (d.isOn && d.currentLeakage > _leakageMax) {
        issues.add(
          "current leakage ${d.currentLeakage.toStringAsFixed(3)} A — possible insulation fault",
        );
      }

      if (d.isOn) {
        final since = _onSince[d.id];
        if (since != null &&
            !motionRecent &&
            now.difference(since) > _idleWithMotionGrace) {
          issues.add(
            "${d.name} has been on for ${now.difference(since).inMinutes} minutes with no motion in the room",
          );
        }
      }

      if (issues.isEmpty) {
        // Re-arm if previous fingerprint is gone.
        _lastFingerprint.remove(d.id);
        continue;
      }

      final fingerprint = issues.join("|");
      if (_lastFingerprint[d.id] == fingerprint) continue;
      _lastFingerprint[d.id] = fingerprint;

      final severity = _severityOf(issues);
      final msg =
          "${d.name}: ${issues.join('; ')}.";
      out.add(AnomalyEvent(
        deviceId: d.id,
        deviceName: d.name,
        severity: severity,
        message: msg,
        detectedAt: now,
      ));

      // 🔌 AUTO-CUT — the safety module that ties surge + leakage
      // detection to actually turning the device OFF. We treat any
      // voltage-out-of-band or leakage-fault issue as critical and
      // immediately cut power on the ESP32 side.
      final shouldAutoCut = d.isOn &&
          (msg.toLowerCase().contains("voltage ") ||
              msg.toLowerCase().contains("leakage"));
      if (shouldAutoCut) {
        try {
          await FirebaseDatabase.instance
              .ref("appliances/${d.id}")
              .update({"isOn": false});
          DeviceSimulatorService.clearOverride(d.id);
          await VoiceService.speak(
            "Auto-cut engaged on the ${d.name}. Power has been removed for safety.",
          );
          await AgentActionLogger.log(
            deviceId: d.id,
            deviceName: d.name,
            action: "auto_cut",
            reason: msg,
            trigger: "auto_cut_module",
          );
        } catch (e) {
          debugPrint("Auto-cut on ${d.name} failed: $e");
        }
      }

      try {
        await VoiceService.speakAnomaly(
          deviceName: d.name,
          reason: issues.first,
        );
        await AgentActionLogger.log(
          deviceId: d.id,
          deviceName: d.name,
          action: "anomaly_$severity",
          reason: msg,
          trigger: "anomaly_detector",
        );
        await _persist(
          deviceId: d.id,
          deviceName: d.name,
          deviceType: d.type,
          severity: severity,
          title: _titleFor(issues),
          detail: msg,
          metrics: _metricsOf(d),
        );
      } catch (e) {
        debugPrint("AnomalyDetectionService announce failed: $e");
      }
    }

    return out;
  }

  /// Evaluate a SINGLE device immediately, reading its current
  /// state directly from Firebase RTDB. Bypasses the fingerprint
  /// dedup cache so repeated user-triggered simulations always
  /// fire. Used by [SafetyModuleScreen] when the user taps the
  /// Simulate Surge / Simulate Leakage button so the auto-cut is
  /// deterministic instead of waiting for the next 10-second
  /// dashboard sweep.
  static Future<List<AnomalyEvent>> evaluateById(String deviceId) async {
    try {
      final snap = await FirebaseDatabase.instance
          .ref("appliances/$deviceId")
          .get();
      final raw = snap.value;
      if (raw is! Map) return const [];
      final device = DeviceModel.fromMap(raw, deviceId);
      // Clear the dedup cache for this device so the same fault
      // signature can fire again when the user re-runs the demo.
      _lastFingerprint.remove(deviceId);
      return evaluate(devices: [device], motionRecent: true);
    } catch (e) {
      debugPrint("AnomalyDetectionService.evaluateById failed: $e");
      return const [];
    }
  }

  /// Stream of anomalies for the current user, newest first.
  static Stream<List<AnomalyRecord>> stream({int limit = 100}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("anomalies")
        .orderBy("epoch", descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map((d) => AnomalyRecord.fromDoc(d.id, d.data()))
            .toList());
  }

  /// Mark an anomaly as resolved.
  static Future<void> resolve(String id) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("anomalies")
        .doc(id)
        .update({
      "resolvedAt": Timestamp.now(),
    });
  }

  static Future<void> _persist({
    required String deviceId,
    required String deviceName,
    required String deviceType,
    required String severity,
    required String title,
    required String detail,
    required Map<String, double> metrics,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final now = DateTime.now();
    await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("anomalies")
        .add({
      "deviceId": deviceId,
      "deviceName": deviceName,
      "deviceType": deviceType,
      "severity": severity,
      "title": title,
      "detail": detail,
      "metrics": metrics,
      "trigger": "anomaly_detector",
      "detectedAt": Timestamp.fromDate(now),
      "resolvedAt": null,
      "epoch": now.millisecondsSinceEpoch,
    });
  }

  static String _titleFor(List<String> issues) {
    final j = issues.first.toLowerCase();
    if (j.contains("voltage")) return "Voltage out of band";
    if (j.contains("current draw")) return "Current draw exceeded";
    if (j.contains("leakage")) return "Insulation / leakage fault";
    if (j.contains("no motion")) return "Idle device wasting energy";
    return "Device anomaly";
  }

  static Map<String, double> _metricsOf(DeviceModel d) => {
        "voltage": d.voltage,
        "current": d.current,
        "power": d.power,
        "leakage": d.currentLeakage,
        "energy": d.energy,
      };

  static double _currentLimitFor(String type) {
    switch (type.toLowerCase()) {
      case "fan":
        return _currentMaxFan;
      case "bulb":
        return _currentMaxBulb;
      case "pump":
        return _currentMaxPump;
      default:
        return 5.0;
    }
  }

  static String _severityOf(List<String> issues) {
    final joined = issues.join(" ").toLowerCase();
    if (joined.contains("leakage") || joined.contains("voltage")) {
      return "critical";
    }
    if (joined.contains("current draw")) return "warning";
    return "info";
  }
}
