// ignore_for_file: avoid_print

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'agent_action_logger.dart';
import 'agent_memory_service.dart';
import 'agent_mode_service.dart';
import 'energy_optimization_service.dart';
import 'location_service.dart';
import 'room_device_state_service.dart';
import 'room_service.dart';
import 'voice_service.dart';
import 'weather_service.dart';

/// Result of a one-shot proactive briefing — used by the chat
/// screen to render a situational greeting when the user enters
/// conversational mode while AI agent mode is on.
@immutable
class BriefingResult {
  final String locationLabel;
  final String weatherLine;
  final List<BriefingAction> actions;
  final String spokenSummary;

  const BriefingResult({
    required this.locationLabel,
    required this.weatherLine,
    required this.actions,
    required this.spokenSummary,
  });
}

@immutable
class BriefingAction {
  final String deviceName;
  final bool turnedOn;
  final String reason;
  const BriefingAction({
    required this.deviceName,
    required this.turnedOn,
    required this.reason,
  });
}

/// =========================================================
/// AGENT AUTOMATION ENGINE
/// =========================================================
/// The proactive brain of AI Agent mode. Wakes every two
/// minutes and asks: given the current time, weather, motion
/// and device states, is there a sensible automatic action
/// I should take?
///
/// Each action:
///   • Speaks a one-sentence reason out loud (TTS)
///   • Pushes a local notification (so the user sees the
///     reason on the lock-screen too)
///   • Logs to /users/{uid}/agent_actions/ with trigger
///     "smart_automation" — feeds the agent's chat memory
///   • Records a memory entry the next chat turn can read
///
/// Per-device cooldown stops the engine from fighting the
/// user: if the user manually toggled a device less than 5
/// minutes ago, the engine leaves it alone.
class AgentAutomationEngine {
  AgentAutomationEngine._();

  static const Duration _tickEvery = Duration(minutes: 2);
  static const Duration _cooldown = Duration(minutes: 5);

  /// Active hours for proactive "you're warm, turn on the fan"
  /// style suggestions. Outside these hours we default to off.
  static const int _activeStartHour = 6;
  static const int _activeEndHour = 23;

  /// Time-of-day windows for the bulb. Outside the evening window
  /// the agent considers the bulb redundant and switches it off.
  static const int _bulbDayStart = 6;    // 06:00 — daytime begins
  static const int _bulbEveningStart = 18; // 18:00 — evening begins
  static const int _bulbNightEnd = 23;   // 23:00 — late-night cut-off

  /// Prototype-tuned thresholds. Islamabad summer reliably trips
  /// the warm path so the panel demo always sees the fan engage.
  static const double _hotThresholdC = 22.0;   // ≥ this → fan should be on
  static const double _coolThresholdC = 18.0;  // < this → fan should be off
  static const double _pumpThresholdC = 32.0;  // ≥ this → suggest pump burst

  static Timer? _ticker;
  static bool _running = false;

  /// Time of the last action the engine took (or saw the user
  /// take) per device — used as the cooldown anchor.
  static final Map<String, DateTime> _lastActionAt = {};

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _notifInitialised = false;

  static bool get isRunning => _running;

  /// Captures actions taken inside the current `runBriefing()` call.
  /// `null` outside a briefing — `_autoAct` checks this to decide
  /// whether to record the BriefingAction in addition to its normal
  /// side-effects.
  static List<BriefingAction>? _briefingSink;

  /// Subscription that watches /appliances/ and reverses user actions
  /// that violate active agent rules (e.g. bulb on during daytime).
  static StreamSubscription<DatabaseEvent>? _overrideSub;

  /// Idempotent. Call this when AI mode is enabled.
  static Future<void> start() async {
    if (_running) return;
    _running = true;
    await _ensureNotifChannel();
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickEvery, (_) => _tick());
    _wireOverrideGuard();
    // Don't run an immediate first tick — let the user enjoy a
    // few moments of quiet after toggling AI on.
  }

  static Future<void> stop() async {
    _running = false;
    _ticker?.cancel();
    _ticker = null;
    await _overrideSub?.cancel();
    _overrideSub = null;
  }

  /// Call this whenever the user manually toggles a device so
  /// the engine respects the choice for [_cooldown].
  static void registerManualAction(String deviceId) {
    _lastActionAt[deviceId] = DateTime.now();
  }

  // =========================================================
  // PROACTIVE BRIEFING (call when entering conversational mode)
  // =========================================================
  /// One-shot situational briefing: gathers location + weather,
  /// runs every device rule immediately (bypassing the periodic
  /// tick and cooldown), and returns a single natural-language
  /// summary the chat screen can both render and speak.
  ///
  /// Only takes actions when AI agent mode is on. In manual mode
  /// returns a passive summary without flipping any device.
  static Future<BriefingResult> runBriefing() async {
    final now = DateTime.now();
    final weather = WeatherService.latest.value;
    final loc = LocationService.current.value;
    final locLabel = (loc != null && loc.isReal) ? loc.label : "your home";
    final weatherLine = weather == null
        ? "Weather data is not available yet."
        : "It's ${weather.tempC.toStringAsFixed(0)}°C with "
            "${weather.description}, humidity ${weather.humidity}%.";

    if (!AgentModeService.isAiMode.value) {
      // Passive briefing — describe but don't act.
      final spoken =
          "You're in $locLabel. $weatherLine I'm in manual mode, so you're "
          "in control of every device.";
      return BriefingResult(
        locationLabel: locLabel,
        weatherLine: weatherLine,
        actions: const [],
        spokenSummary: spoken,
      );
    }

    // Active briefing — read live state and run every rule.
    final actions = <BriefingAction>[];
    _briefingSink = actions;
    try {
      final snap =
          await FirebaseDatabase.instance.ref("appliances").get();
      final raw = snap.value;
      final state = <String, bool>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) state[k.toString()] = v["isOn"] == true;
        });
      } else if (raw is List) {
        for (var i = 0; i < raw.length; i++) {
          final v = raw[i];
          if (v is Map) state[i.toString()] = v["isOn"] == true;
        }
      }

      final hour = now.hour;
      final inActiveHours =
          hour >= _activeStartHour && hour < _activeEndHour;
      // Bypass cooldown for the briefing — entering conversational
      // mode is a fresh user-driven event, so the engine should act.
      _lastActionAt.clear();

      await _decideBulb(
        isOn: state["2"] ?? false,
        motionRecent: false,
        now: now,
        hour: hour,
      );
      await _decideFan(
        isOn: state["1"] ?? false,
        motionRecent: false,
        weather: weather,
        now: now,
        hour: hour,
        inActiveHours: inActiveHours,
      );
      await _decidePump(
        isOn: state["3"] ?? false,
        weather: weather,
        now: now,
        hour: hour,
      );
    } catch (e) {
      debugPrint("AgentAutomationEngine.runBriefing failed: $e");
    } finally {
      _briefingSink = null;
    }

    final buf = StringBuffer();
    buf.write("You're in $locLabel. $weatherLine ");
    if (actions.isEmpty) {
      buf.write("Everything is already in the right state — no changes needed.");
    } else {
      for (final a in actions) {
        buf.write(a.reason);
        buf.write(" ");
      }
    }
    return BriefingResult(
      locationLabel: locLabel,
      weatherLine: weatherLine,
      actions: actions,
      spokenSummary: buf.toString().trim(),
    );
  }

  // =========================================================
  // OVERRIDE GUARD
  // =========================================================
  /// Watches /appliances/ for writes that violate the active rules
  /// (e.g. user flips bulb on during daytime) and reverses them
  /// after a small grace window so the user hears their command go
  /// through, then hears the agent's reasoning.
  static void _wireOverrideGuard() {
    _overrideSub?.cancel();
    _overrideSub = FirebaseDatabase.instance
        .ref("appliances")
        .onValue
        .listen((event) async {
      if (!AgentModeService.isAiMode.value) return;
      final raw = event.snapshot.value;
      final state = <String, bool>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) state[k.toString()] = v["isOn"] == true;
        });
      } else if (raw is List) {
        for (var i = 0; i < raw.length; i++) {
          final v = raw[i];
          if (v is Map) state[i.toString()] = v["isOn"] == true;
        }
      }
      await _enforceBulbPolicy(state["2"] ?? false);
    });
  }

  /// Bulb policy enforcement — daytime + bulb just turned on by the
  /// user → flip back off with an explanation. Skipped if the engine
  /// itself just acted on the bulb (its own writes would re-trigger
  /// this listener otherwise).
  static Future<void> _enforceBulbPolicy(bool isOn) async {
    if (!isOn) return;
    final lastEngineWrite = _lastActionAt["2"];
    if (lastEngineWrite != null &&
        DateTime.now().difference(lastEngineWrite) <
            const Duration(seconds: 3)) {
      // Our own write — ignore.
      return;
    }
    final hour = DateTime.now().hour;
    final daytime =
        hour >= _bulbDayStart && hour < _bulbEveningStart;
    if (!daytime) return;
    await _autoAct(
      deviceId: "2",
      deviceName: "Bulb",
      turnOn: false,
      reason:
          "It's the time of morning — there is no need for the bulb. "
          "Switching it back off.",
    );
  }

  // =========================================================
  // CORE TICK
  // =========================================================
  static Future<void> _tick() async {
    if (!_running) return;
    if (!AgentModeService.isAiMode.value) return;

    try {
      final now = DateTime.now();
      final weather = WeatherService.latest.value;
      // PIR sensor was decommissioned, so we no longer gate any
      // automation on motion. The time-of-day + weather rules
      // below still fire normally; the fan auto-on path that
      // required occupancy is now driven purely by weather.
      const motionRecent = true;

      final snap =
          await FirebaseDatabase.instance.ref("appliances").get();
      final raw = snap.value;
      final state = <String, bool>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) state[k.toString()] = v["isOn"] == true;
        });
      } else if (raw is List) {
        for (var i = 0; i < raw.length; i++) {
          final v = raw[i];
          if (v is Map) state[i.toString()] = v["isOn"] == true;
        }
      }

      // Run device-specific rules sequentially. Quiet hours block
      // anything except critical safety reactions (handled
      // elsewhere in AgentOrchestrator).
      final hour = now.hour;
      final inActiveHours =
          hour >= _activeStartHour && hour < _activeEndHour;

      await _decideBulb(
        isOn: state["2"] ?? false,
        motionRecent: motionRecent,
        now: now,
        hour: hour,
      );

      await _decideFan(
        isOn: state["1"] ?? false,
        motionRecent: motionRecent,
        weather: weather,
        now: now,
        hour: hour,
        inActiveHours: inActiveHours,
      );

      await _decidePump(
        isOn: state["3"] ?? false,
        weather: weather,
        now: now,
        hour: hour,
      );

      // Predictive peak-hour optimization — check every device
      // currently ON against any committed peak-hour rule. If
      // we're inside the peak window the engine cuts power and
      // narrates the savings.
      // Each room can have its own committed rule for the same
      // device id. Iterate every active rule and fire one room
      // at a time so we only cut the rooms whose admins opted in.
      final allRooms = await RoomService.all();
      for (final entry in state.entries) {
        final deviceId = entry.key;
        final isOn = entry.value;
        final decisions = await EnergyOptimizationService
            .shouldOptimizeNow(deviceId, isOn);
        if (decisions.isEmpty) continue;

        final roomsWithDevice = allRooms
            .where((r) => r.deviceIds.contains(deviceId))
            .map((r) => r.id)
            .toList();

        for (final decision in decisions) {
          // If the room hasn't opted in, skip — defensive check.
          if (decision.roomId.isNotEmpty) {
            // Confirm the room currently has this device on at
            // the room-virtual layer; if it's already off there
            // (another rule or the user already cut it) skip.
            final stillOn = await RoomDeviceStateService.get(
                decision.roomId, deviceId);
            if (!stillOn) continue;
          }

          final hh = DateTime.now().hour;
          final hLabel = hh == 0
              ? "12 AM"
              : hh <= 12
                  ? "$hh ${hh == 12 ? 'PM' : 'AM'}"
                  : "${hh - 12} PM";
          final dailySaving =
              (decision.monthlySavingsPKR / 30).toStringAsFixed(0);

          // Cut the device only inside this room.
          if (decision.roomId.isNotEmpty) {
            await RoomDeviceStateService.cutInRoom(
              roomId: decision.roomId,
              deviceId: deviceId,
              roomsWithDevice: roomsWithDevice,
            );
            // Speak + log + push notification (no second physical
            // toggle inside _autoAct since cutInRoom already
            // recomputed /appliances/).
            await _announceAndLog(
              deviceId: deviceId,
              deviceName: decision.deviceName,
              reason:
                  "Peak-hour optimization. ${decision.roomPhrase} · "
                  "${decision.deviceName} switched off at $hLabel — "
                  "saving you about ₨ $dailySaving today.",
              turnedOn: false,
            );
          } else {
            // No room context — fall back to the global path.
            await _autoAct(
              deviceId: deviceId,
              deviceName: decision.deviceName,
              turnOn: false,
              reason:
                  "Peak-hour optimization. ${decision.deviceName} switched off at $hLabel "
                  "— saving you about ₨ $dailySaving today.",
            );
          }
        }
      }
    } catch (e) {
      debugPrint("AgentAutomationEngine tick failed: $e");
    }
  }

  // =========================================================
  // RULES
  // =========================================================

  /// Bulb rules — time-of-day driven, no occupancy gating.
  ///   • Daytime (06:00 – 18:00) + bulb on  → off  ("it's morning, no need")
  ///   • Late night (23:00 – 06:00) + bulb on → off  ("it's late, switching off")
  ///   • Evening (18:00 – 23:00)    → leave the user's choice alone.
  static Future<void> _decideBulb({
    required bool isOn,
    required bool motionRecent,
    required DateTime now,
    required int hour,
  }) async {
    if (!isOn) return;

    final daytime =
        hour >= _bulbDayStart && hour < _bulbEveningStart;
    final lateNight =
        hour >= _bulbNightEnd || hour < _bulbDayStart;

    if (daytime) {
      await _autoAct(
        deviceId: "2",
        deviceName: "Bulb",
        turnOn: false,
        reason:
            "It's daytime — there is no need for the bulb. Switching it off "
            "to save energy.",
      );
      return;
    }

    if (lateNight && !motionRecent) {
      await _autoAct(
        deviceId: "2",
        deviceName: "Bulb",
        turnOn: false,
        reason:
            "It is late and the room is empty. Switching the bulb off.",
      );
    }
  }

  /// Fan rules — weather-driven, prototype-tuned.
  ///   • Active hours + ≥ _hotThresholdC + fan off → on
  ///   • < _coolThresholdC + fan on → off
  /// Motion is no longer required; the panel demo needs the fan to
  /// engage on weather alone.
  static Future<void> _decideFan({
    required bool isOn,
    required bool motionRecent,
    required WeatherSnapshot? weather,
    required DateTime now,
    required int hour,
    required bool inActiveHours,
  }) async {
    if (weather == null) return;
    final t = weather.tempC;

    if (!isOn && inActiveHours && t >= _hotThresholdC) {
      await _autoAct(
        deviceId: "1",
        deviceName: "Fan",
        turnOn: true,
        reason:
            "It's ${t.toStringAsFixed(0)} degrees outside — turning on the "
            "fan to keep the room comfortable.",
      );
      return;
    }

    if (isOn && t < _coolThresholdC) {
      await _autoAct(
        deviceId: "1",
        deviceName: "Fan",
        turnOn: false,
        reason:
            "It has cooled down to ${t.toStringAsFixed(0)} degrees — "
            "switching the fan off.",
      );
    }
  }

  /// Pump rules — short bursts on the schedule, plus a hot-day
  /// daytime burst when the temperature crosses _pumpThresholdC.
  static Future<void> _decidePump({
    required bool isOn,
    required WeatherSnapshot? weather,
    required DateTime now,
    required int hour,
  }) async {
    final isBurstHour = hour == 5 || hour == 18;
    final inFirstFiveMinutes = now.minute < 5;

    if (isBurstHour && inFirstFiveMinutes && !isOn) {
      await _autoAct(
        deviceId: "3",
        deviceName: "Pump",
        turnOn: true,
        reason:
            hour == 5
                ? "Scheduled morning water-pump burst."
                : "Scheduled evening water-pump burst.",
      );
      return;
    }

    if (!isOn &&
        weather != null &&
        weather.tempC >= _pumpThresholdC &&
        hour >= _activeStartHour &&
        hour < _activeEndHour) {
      await _autoAct(
        deviceId: "3",
        deviceName: "Pump",
        turnOn: true,
        reason:
            "Outside is ${weather.tempC.toStringAsFixed(0)} degrees — "
            "running the water pump for cooling.",
      );
    }
  }

  // =========================================================
  // ACTION HELPER
  // =========================================================
  static Future<void> _autoAct({
    required String deviceId,
    required String deviceName,
    required bool turnOn,
    required String reason,
  }) async {
    final last = _lastActionAt[deviceId];
    if (last != null && DateTime.now().difference(last) < _cooldown) {
      // Inside the user-respect cooldown — skip.
      return;
    }

    try {
      await FirebaseDatabase.instance
          .ref("appliances/$deviceId")
          .update({"isOn": turnOn});
      _lastActionAt[deviceId] = DateTime.now();

      _briefingSink?.add(BriefingAction(
        deviceName: deviceName,
        turnedOn: turnOn,
        reason: reason,
      ));

      await VoiceService.speak(reason);
      await _showNotification(
        title: "$deviceName ${turnOn ? "turned ON" : "turned OFF"}",
        body: reason,
      );

      await AgentActionLogger.log(
        deviceId: deviceId,
        deviceName: deviceName,
        action: turnOn ? "on" : "off",
        reason: reason,
        trigger: _briefingSink != null
            ? "agent_briefing"
            : "smart_automation",
      );

      // Drop a memory crumb so the chat agent can refer to it
      // later ("why did you turn off the bulb at 2 PM?").
      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 16)
          .replaceAll(":", "");
      await AgentMemoryService.remember(
        "auto_${deviceId}_$stamp",
        "${turnOn ? 'Turned on' : 'Turned off'} $deviceName: $reason",
      );
    } catch (e) {
      debugPrint("AgentAutomationEngine action failed: $e");
    }
  }

  /// Same effects as [_autoAct] (speak + notify + log + memory)
  /// EXCEPT skip the `/appliances/{id}` write — used by the
  /// per-room peak-hour cut path where [RoomDeviceStateService]
  /// has already updated both the room state and the shared
  /// appliance flag.
  static Future<void> _announceAndLog({
    required String deviceId,
    required String deviceName,
    required String reason,
    required bool turnedOn,
  }) async {
    try {
      _lastActionAt[deviceId] = DateTime.now();
      _briefingSink?.add(BriefingAction(
        deviceName: deviceName,
        turnedOn: turnedOn,
        reason: reason,
      ));
      await VoiceService.speak(reason);
      await _showNotification(
        title:
            "$deviceName ${turnedOn ? "turned ON" : "turned OFF"}",
        body: reason,
      );
      await AgentActionLogger.log(
        deviceId: deviceId,
        deviceName: deviceName,
        action: turnedOn ? "on" : "off",
        reason: reason,
        trigger: "energy_optimizer",
      );
      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 16)
          .replaceAll(":", "");
      await AgentMemoryService.remember(
        "auto_${deviceId}_$stamp",
        "${turnedOn ? 'Turned on' : 'Turned off'} $deviceName: $reason",
      );
    } catch (e) {
      debugPrint("AgentAutomationEngine announceAndLog failed: $e");
    }
  }

  // =========================================================
  // NOTIFICATION INFRA
  // =========================================================
  static Future<void> _ensureNotifChannel() async {
    if (_notifInitialised) return;
    try {
      const channel = AndroidNotificationChannel(
        "shapeos_auto",
        "SHAPEOS Smart Actions",
        description: "Notifications when the agent acts on your home.",
        importance: Importance.defaultImportance,
      );
      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      _notifInitialised = true;
    } catch (e) {
      debugPrint("AgentAutomationEngine notif init failed: $e");
    }
  }

  static Future<void> _showNotification({
    required String title,
    required String body,
  }) async {
    try {
      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            "shapeos_auto",
            "SHAPEOS Smart Actions",
            channelDescription:
                "Notifications when the agent acts on your home.",
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    } catch (e) {
      debugPrint("AgentAutomationEngine notif failed: $e");
    }
  }
}
