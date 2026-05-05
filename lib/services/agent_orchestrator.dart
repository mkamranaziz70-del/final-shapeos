import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/device_model.dart';
import 'agent_action_logger.dart';
import 'agent_background_service.dart';
import 'agent_mode_service.dart';
import 'location_service.dart';
import 'voice_service.dart';
import 'wake_word_service.dart';
import 'weather_service.dart';

/// =========================================================
/// AGENT ORCHESTRATOR
/// =========================================================
/// The autonomous part of the agent. While the user is in the
/// app or it's running in the foreground, this:
///   • watches /alerts/ for sensor changes (smoke, flame, gas,
///     motion) and SPEAKS A REASON before flipping any device,
///   • implements the bulb-motion rule: if the bulb is ON and
///     no PIR is seen for the configured grace, it turns the
///     bulb OFF and logs the reason,
///   • re-fetches weather whenever location changes or every
///     20 minutes, so the chat brain has fresh data,
///   • records every autonomous action via [AgentActionLogger].
///
/// Public surface is intentionally tiny — call [start] once
/// after login and [stop] on logout.
class AgentOrchestrator {
  AgentOrchestrator._();

  static StreamSubscription<DatabaseEvent>? _alertsSub;
  static StreamSubscription<DatabaseEvent>? _appliancesSub;
  static Timer? _bulbMotionTimer;
  static Timer? _weatherTimer;
  static VoidCallback? _locationListener;

  static Map<String, bool> _lastAlerts = const {};
  static List<DeviceModel> _devices = const [];
  static DateTime? _lastMotionAt;
  static DateTime? _bulbOnSince;

  /// Most recent motion timestamp the orchestrator has observed.
  /// Used by [AgentAutomationEngine] for occupancy decisions.
  static DateTime? get lastMotionAt => _lastMotionAt;

  /// Snapshot of the latest device list parsed from RTDB. Used by
  /// the automation engine so it doesn't have to re-fetch.
  static List<DeviceModel> get devices => List.unmodifiable(_devices);

  /// Grace period without motion before the bulb is auto-cut.
  static const Duration bulbMotionGrace = Duration(minutes: 2);

  /// How often to refresh weather even when location is steady.
  static const Duration weatherRefreshEvery = Duration(minutes: 20);

  static bool get isRunning => _alertsSub != null;

  static Future<void> start() async {
    if (isRunning) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Each subsystem is wrapped so a single failure (no GPS,
    // permission denied, etc.) does not bring the whole app down.
    try {
      _wireAlerts();
    } catch (e) {
      debugPrint("AgentOrchestrator alerts boot failed: $e");
    }
    try {
      _wireAppliances();
    } catch (e) {
      debugPrint("AgentOrchestrator appliances boot failed: $e");
    }
    try {
      _wireBulbMotionLoop();
    } catch (e) {
      debugPrint("AgentOrchestrator bulb-motion boot failed: $e");
    }
    try {
      _wireWeatherRefresh();
    } catch (e) {
      debugPrint("AgentOrchestrator weather boot failed: $e");
    }

    // NOTE: Wake word + background service are NOT started here
    // anymore. Android 14+ kills the app with a SecurityException
    // if a "microphone" foreground service starts before runtime
    // RECORD_AUDIO is granted. The user enables the listener
    // explicitly via the toggle in AgentChatScreen, which then
    // requests permission first.
  }

  static Future<void> stop() async {
    await _alertsSub?.cancel();
    _alertsSub = null;
    await _appliancesSub?.cancel();
    _appliancesSub = null;
    _bulbMotionTimer?.cancel();
    _bulbMotionTimer = null;
    _weatherTimer?.cancel();
    _weatherTimer = null;
    if (_locationListener != null) {
      LocationService.current.removeListener(_locationListener!);
      _locationListener = null;
    }
    await WakeWordService.disable();
    await AgentBackgroundService.stop();
  }

  // =========================================================
  // ALERT LISTENER
  // =========================================================
  static void _wireAlerts() {
    _alertsSub = FirebaseDatabase.instance
        .ref("alerts")
        .onValue
        .listen((event) async {
      final raw = event.snapshot.value;
      final next = <String, bool>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          next[k.toString()] = v == true;
        });
      }

      // Detect rising edges (clear -> active) and act/speak.
      for (final entry in next.entries) {
        final wasActive = _lastAlerts[entry.key] == true;
        if (entry.value && !wasActive) {
          await _onAlertRose(entry.key);
        }
      }

      // Track motion timestamps for bulb logic.
      if (next["motion"] == true) {
        _lastMotionAt = DateTime.now();
      }

      _lastAlerts = next;
    });
  }

  static Future<void> _onAlertRose(String alertKey) async {
    switch (alertKey) {
      case "smoke":
        await _speakAndAct(
          spoken:
              "Smoke detected inside. I am switching the fan on to ventilate the area.",
          deviceId: "1",
          newState: true,
          reason: "Smoke detected by the kitchen sensor.",
          trigger: "sensor_smoke",
        );
        break;
      case "flame":
        await _speakAndAct(
          spoken:
              "Flame detected. Sounding the alarm bell and please evacuate the area.",
          deviceId: "4",
          newState: true,
          reason: "Flame detected by the flame sensor.",
          trigger: "sensor_flame",
        );
        break;
      case "gas":
        await _speakAndAct(
          spoken:
              "Gas leak detected. Turning the fan on and please open a window.",
          deviceId: "1",
          newState: true,
          reason: "Gas concentration above safe threshold.",
          trigger: "sensor_gas",
        );
        break;
      case "motion":
        // Motion is informational only; bulb logic handles it.
        await VoiceService.speak("Motion detected at the entrance.");
        break;
      case "bulb_voltage_surge":
        await VoiceService.speak(
          "Voltage surge on the bulb circuit. Auto-cut already engaged for safety.",
        );
        await AgentActionLogger.log(
          deviceId: "2",
          deviceName: "Bulb",
          action: "auto_cut",
          reason: "Voltage outside the 219-221 V safe band.",
          trigger: "sensor_voltage_surge",
        );
        break;
      default:
        break;
    }
  }

  static Future<void> _speakAndAct({
    required String spoken,
    required String deviceId,
    required bool newState,
    required String reason,
    required String trigger,
  }) async {
    // Always announce the alert so the user hears it.
    await VoiceService.speak(spoken);

    // Only flip devices automatically when AI Agent mode is on.
    // In manual mode the user expects to be in control, so we
    // log the recommendation but do not toggle anything.
    if (!AgentModeService.isAiMode.value) {
      await AgentActionLogger.log(
        deviceId: deviceId,
        deviceName: _nameFor(deviceId),
        action: "advice_${newState ? "on" : "off"}",
        reason: "Manual mode — agent suggested but did not act: $reason",
        trigger: trigger,
      );
      return;
    }

    try {
      await FirebaseDatabase.instance
          .ref("appliances/$deviceId")
          .update({"isOn": newState});
      await AgentActionLogger.log(
        deviceId: deviceId,
        deviceName: _nameFor(deviceId),
        action: newState ? "on" : "off",
        reason: reason,
        trigger: trigger,
      );
    } catch (e) {
      debugPrint("AgentOrchestrator action failed: $e");
    }
  }

  // =========================================================
  // APPLIANCES LISTENER (for bulb motion logic)
  // =========================================================
  static void _wireAppliances() {
    _appliancesSub = FirebaseDatabase.instance
        .ref("appliances")
        .onValue
        .listen((event) {
      final raw = event.snapshot.value;
      final out = <DeviceModel>[];
      try {
        if (raw is List) {
          for (var i = 0; i < raw.length; i++) {
            final v = raw[i];
            if (v is Map) {
              try {
                out.add(DeviceModel.fromMap(v, i.toString()));
              } catch (_) {}
            }
          }
        } else if (raw is Map) {
          raw.forEach((k, v) {
            if (v is Map) {
              try {
                out.add(DeviceModel.fromMap(v, k.toString()));
              } catch (_) {}
            }
          });
        }
      } catch (e) {
        debugPrint("Orchestrator parse failed: $e");
      }
      _devices = out;

      // Track when the bulb most recently transitioned to ON.
      final bulb = _devices.firstWhere(
        (d) => d.id == "2",
        orElse: () => _bulbPlaceholder(),
      );
      if (bulb.isOn && _bulbOnSince == null) {
        _bulbOnSince = DateTime.now();
      } else if (!bulb.isOn) {
        _bulbOnSince = null;
      }
    });
  }

  // =========================================================
  // BULB MOTION RULE
  // =========================================================
  static void _wireBulbMotionLoop() {
    _bulbMotionTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      // Bulb auto-cut is an autonomous action — only run it when
      // the user has explicitly given the AI agent control.
      if (!AgentModeService.isAiMode.value) return;

      final bulb = _devices.firstWhere(
        (d) => d.id == "2",
        orElse: () => _bulbPlaceholder(),
      );
      if (!bulb.isOn) return;

      // If we never observed motion since the bulb came on,
      // anchor "since when" to the bulb-on moment so we don't
      // shut it off instantly at startup.
      final reference = _lastMotionAt ?? _bulbOnSince ?? DateTime.now();
      final idle = DateTime.now().difference(reference);
      if (idle < bulbMotionGrace) return;

      await _speakAndAct(
        spoken:
            "Switching the bulb off — I have not detected anyone in the room for ${idle.inMinutes} minutes.",
        deviceId: "2",
        newState: false,
        reason:
            "No motion detected for ${idle.inMinutes} minutes after bulb was on.",
        trigger: "auto_motion_timeout",
      );
      _bulbOnSince = null;
    });
  }

  // =========================================================
  // WEATHER REFRESH
  // =========================================================
  static void _wireWeatherRefresh() {
    Future<void> refresh() async {
      final loc = LocationService.current.value;
      if (loc == null || !loc.isReal) return;
      await WeatherService.fetch(lat: loc.latitude, lon: loc.longitude);
    }

    // Refresh whenever location changes meaningfully.
    _locationListener = () {
      refresh();
    };
    LocationService.current.addListener(_locationListener!);

    _weatherTimer = Timer.periodic(weatherRefreshEvery, (_) => refresh());
    refresh();
  }

  // =========================================================
  // HELPERS
  // =========================================================
  static String _nameFor(String id) {
    switch (id) {
      case "1":
        return "Fan";
      case "2":
        return "Bulb";
      case "3":
        return "Pump";
      case "4":
        return "Bell";
      default:
        return "Device $id";
    }
  }

  static DeviceModel _bulbPlaceholder() => const DeviceModel(
        id: "2",
        name: "Bulb",
        type: "bulb",
        isOn: false,
        power: 0,
        voltage: 0,
        current: 0,
        currentLeakage: 0,
        voltageLeakage: 0,
        energy: 0,
      );
}
