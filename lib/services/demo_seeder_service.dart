// ignore_for_file: avoid_print

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// =========================================================
/// DEMO SEEDER SERVICE
/// =========================================================
/// One-tap population of Firebase with realistic-looking data
/// so the AI Anomalies and Bill Splitting tabs render with
/// production-grade depth right after install.
///
/// Seeds:
///   • 30 days of `/energy_daily/{YYYY-MM-DD}` docs with
///     hour-by-hour usage and per-device kWh
///   • 3 fake roommates as `/users/{demo_*}` documents with
///     room + selectedDevices, so the bill splits 4 ways
///   • 15 `/users/{currentUid}/anomalies/{auto}` records
///     spanning 7 days at varied severities
///   • 8 `/users/{currentUid}/agent_actions/{auto}` records
///   • 6 months of `/billing_history/{YYYY-MM}` aggregate docs
///
/// The seeder is idempotent — re-running overwrites the same
/// document IDs rather than duplicating.
class DemoSeederService {
  DemoSeederService._();

  static final _fs = FirebaseFirestore.instance;
  static final _rng = Random(42);

  static Future<SeedReport> seedAll() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("DemoSeeder requires a logged-in user.");
    }

    final report = SeedReport();

    await _seedFakeRoommates(report);
    await _seedEnergyHistory(report);
    await _seedAnomalies(uid, report);
    await _seedAgentActions(uid, report);
    await _seedBillingHistory(report);
    await _ensureCurrentUserHasRoom(uid, report);

    return report;
  }

  static Future<void> wipeDemoData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Fake users (only those prefixed with demo_)
    final fakeUsers = await _fs
        .collection("users")
        .where(FieldPath.documentId,
            whereIn: _demoUids().take(10).toList())
        .get();
    for (final d in fakeUsers.docs) {
      await d.reference.delete();
    }

    // Energy daily of last 30 days.
    for (var i = 0; i < 35; i++) {
      final day = DateTime.now().subtract(Duration(days: i));
      final id = _yyyymmdd(day);
      await _fs.collection("energy_daily").doc(id).delete();
    }

    // Anomalies for current user.
    final anoms = await _fs
        .collection("users")
        .doc(uid)
        .collection("anomalies")
        .get();
    for (final d in anoms.docs) {
      await d.reference.delete();
    }

    final billing = await _fs.collection("billing_history").get();
    for (final d in billing.docs) {
      await d.reference.delete();
    }
  }

  // =========================================================
  // FAKE ROOMMATES
  // =========================================================
  static List<String> _demoUids() => const [
        "demo_ali_hassan",
        "demo_zara_khan",
        "demo_bilal_ahmed",
      ];

  static Future<void> _seedFakeRoommates(SeedReport r) async {
    final mates = [
      {
        "uid": "demo_ali_hassan",
        "fullName": "Ali Hassan",
        "email": "ali.hassan@demo.shapeos",
        "room": "Bedroom",
        "selectedDevices": ["1", "2"],
        "agentProfileCompleted": true,
        "firstLoginCompleted": true,
        "isDemoUser": true,
        "avatarColor": "0xFF1F8AC0",
      },
      {
        "uid": "demo_zara_khan",
        "fullName": "Zara Khan",
        "email": "zara.khan@demo.shapeos",
        "room": "Living Room",
        "selectedDevices": ["1", "4"],
        "agentProfileCompleted": true,
        "firstLoginCompleted": true,
        "isDemoUser": true,
        "avatarColor": "0xFFE07A5F",
      },
      {
        "uid": "demo_bilal_ahmed",
        "fullName": "Bilal Ahmed",
        "email": "bilal.ahmed@demo.shapeos",
        "room": "Kitchen",
        "selectedDevices": ["3"],
        "agentProfileCompleted": true,
        "firstLoginCompleted": true,
        "isDemoUser": true,
        "avatarColor": "0xFF81B29A",
      },
    ];
    for (final m in mates) {
      final uid = m["uid"] as String;
      await _fs.collection("users").doc(uid).set(m, SetOptions(merge: true));
      r.fakeRoommates++;
    }
  }

  // =========================================================
  // CURRENT USER HOUSEKEEPING
  // =========================================================
  static Future<void> _ensureCurrentUserHasRoom(
      String uid, SeedReport r) async {
    final me = await _fs.collection("users").doc(uid).get();
    final data = me.data() ?? {};
    final patch = <String, dynamic>{};
    if ((data["room"] ?? "").toString().isEmpty) {
      patch["room"] = "Lounge";
    }
    final selected = (data["selectedDevices"] is List)
        ? List<String>.from(data["selectedDevices"])
        : <String>[];
    if (selected.isEmpty) {
      patch["selectedDevices"] = ["1", "2", "3", "4"];
    }
    if ((data["fullName"] ?? "").toString().isEmpty) {
      final email = FirebaseAuth.instance.currentUser?.email ?? "";
      patch["fullName"] = email.isEmpty ? "You" : email.split("@").first;
    }
    if (patch.isNotEmpty) {
      await _fs
          .collection("users")
          .doc(uid)
          .set(patch, SetOptions(merge: true));
      r.currentUserPatched = true;
    }
  }

  // =========================================================
  // ENERGY HISTORY (30 days, hour-by-hour, per device)
  // =========================================================
  static Future<void> _seedEnergyHistory(SeedReport r) async {
    const tariff = 55.0;
    final now = DateTime.now();

    for (var dayOffset = 0; dayOffset < 30; dayOffset++) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: dayOffset));
      final id = _yyyymmdd(day);
      final isWeekend = day.weekday >= 6;

      final hourly = <String, double>{};
      final perDevice = <String, Map<String, dynamic>>{
        "1": {"name": "Fan", "energy": 0.0, "type": "fan"},
        "2": {"name": "Bulb", "energy": 0.0, "type": "bulb"},
        "3": {"name": "Pump", "energy": 0.0, "type": "pump"},
        "4": {"name": "Bell", "energy": 0.0, "type": "bell"},
      };

      double total = 0;
      var peakHour = 0;
      double peakValue = 0;

      for (var h = 0; h < 24; h++) {
        final fanLoad = _fanLoadFor(h, isWeekend);
        final bulbLoad = _bulbLoadFor(h);
        final pumpLoad = _pumpLoadFor(h);
        final bellLoad = _rng.nextDouble() < 0.04 ? 0.005 : 0.0;
        final hourTotal =
            fanLoad + bulbLoad + pumpLoad + bellLoad;
        hourly[h.toString().padLeft(2, '0')] =
            double.parse(hourTotal.toStringAsFixed(3));
        total += hourTotal;

        (perDevice["1"]!["energy"] as double);
        perDevice["1"]!["energy"] =
            (perDevice["1"]!["energy"] as double) + fanLoad;
        perDevice["2"]!["energy"] =
            (perDevice["2"]!["energy"] as double) + bulbLoad;
        perDevice["3"]!["energy"] =
            (perDevice["3"]!["energy"] as double) + pumpLoad;
        perDevice["4"]!["energy"] =
            (perDevice["4"]!["energy"] as double) + bellLoad;

        if (hourTotal > peakValue) {
          peakValue = hourTotal;
          peakHour = h;
        }
      }

      // Round per-device kWh
      for (final v in perDevice.values) {
        v["energy"] = double.parse(
            (v["energy"] as double).toStringAsFixed(3));
      }

      final billEstimate = total * tariff;

      await _fs.collection("energy_daily").doc(id).set({
        "date": id,
        "day": _dayName(day.weekday),
        "hourlyUsage": hourly,
        "devices": perDevice,
        "totalEnergy": double.parse(total.toStringAsFixed(3)),
        "peakHour": peakHour,
        "billEstimate": double.parse(billEstimate.toStringAsFixed(2)),
        "tariffPerKWh": tariff,
        "suggestions": _suggestionsFor(peakHour, total),
        "isDemoSeed": true,
        "createdAt": FieldValue.serverTimestamp(),
      });

      r.energyDays++;
    }
  }

  // ---------------------------------------------------------
  // Per-hour energy in kWh, calibrated to a deliberately low
  // ceiling so the demo monthly bill never crosses 15 000 PKR
  // even with several active members. Wattages match the
  // updated DeviceProfileService entries:
  //   Fan  = 12 V × 0.45 A      ≈   5.4 W   (DC test fan)
  //   Bulb = 220 V × 0.18 A     ≈  40   W   (LED household bulb)
  //   Pump = 12 V × 3   A       ≈  36   W   (DC pump in bursts)
  //   Bell = 220 V × 0.20 A × .95 ≈ 42   W   (rings briefly)
  //
  // Worst-case daily total at these duty cycles ≈ 0.5 kWh,
  // i.e. ≈ 28 PKR/day, ≈ 850 PKR/month per single member.
  // Across the 4 demo roommates that lands around 3 000–4 000
  // PKR/month, well inside the 15 000 PKR cap.
  // ---------------------------------------------------------

  static double _fanLoadFor(int hour, bool weekend) {
    const fanKW = 0.0054; // 5.4 W
    if (hour < 11 || hour > 19) return 0.0;
    final spike = (hour >= 13 && hour <= 16) ? fanKW * 0.3 : 0.0;
    final weekendBoost = weekend ? fanKW * 0.15 : 0.0;
    final jitter = _rng.nextDouble() * fanKW * 0.08;
    return fanKW + spike + weekendBoost + jitter;
  }

  static double _bulbLoadFor(int hour) {
    const bulbKW = 0.040; // 40 W LED
    if (hour >= 5 && hour <= 6) {
      return bulbKW + _rng.nextDouble() * bulbKW * 0.05;
    }
    if (hour >= 18 && hour <= 22) {
      return bulbKW + _rng.nextDouble() * bulbKW * 0.08;
    }
    return 0.0;
  }

  static double _pumpLoadFor(int hour) {
    const pumpKW = 0.036; // 36 W
    if (hour == 5) return pumpKW + _rng.nextDouble() * pumpKW * 0.05;
    if (hour == 18) {
      return pumpKW * 0.7 + _rng.nextDouble() * pumpKW * 0.05;
    }
    return 0.0;
  }

  static List<String> _suggestionsFor(int peakHour, double total) {
    final out = <String>[];
    if (peakHour >= 18 && peakHour <= 22) {
      out.add(
          "Evening lighting is the daily peak. A 9 W LED bulb instead of the 94 W incandescent would cut bulb energy ~90%.");
    } else if (peakHour >= 13 && peakHour <= 16) {
      out.add(
          "Peak load lands inside the 1pm–4pm hot window. Pre-cooling the room earlier when the grid is cheaper would help.");
    }
    if (total > 1.2) {
      out.add(
          "Daily consumption above 1.2 kWh — slightly elevated for this kit.");
    } else if (total < 0.4) {
      out.add(
          "Quiet day — under 0.4 kWh consumed by the kit.");
    }
    out.add(
        "Pump runtime is concentrated in two short bursts — efficient and on schedule.");
    return out;
  }

  // =========================================================
  // ANOMALIES (15 over 7 days)
  // =========================================================
  static Future<void> _seedAnomalies(String uid, SeedReport r) async {
    final col = _fs
        .collection("users")
        .doc(uid)
        .collection("anomalies");

    final templates = <_AnomalyTemplate>[
      _AnomalyTemplate(
        deviceId: "2",
        deviceName: "Bulb",
        deviceType: "bulb",
        severity: "critical",
        title: "Voltage out of band",
        detail:
            "Voltage 247.3 V is outside the safe 215–225 V band for this AC device — auto-cut engaged for 90 seconds.",
        metrics: {"voltage": 247.3, "current": 0.51},
        hoursAgo: 4,
      ),
      _AnomalyTemplate(
        deviceId: "1",
        deviceName: "Fan",
        deviceType: "fan",
        severity: "warning",
        title: "Idle device wasting energy",
        detail:
            "Fan ran for 47 minutes after the room PIR went quiet. Estimated waste: 0.14 kWh.",
        metrics: {"idleMinutes": 47, "wastedKWh": 0.14},
        hoursAgo: 11,
      ),
      _AnomalyTemplate(
        deviceId: "2",
        deviceName: "Bulb",
        deviceType: "bulb",
        severity: "warning",
        title: "Insulation / leakage fault",
        detail:
            "Current leakage 0.062 A (limit 0.050 A) for 8 minutes — possible insulation degradation.",
        metrics: {"leakage": 0.062},
        hoursAgo: 18,
      ),
      _AnomalyTemplate(
        deviceId: "3",
        deviceName: "Pump",
        deviceType: "pump",
        severity: "info",
        title: "Pump runtime above 7 minutes",
        detail:
            "Pump ran for 9 minutes 12 seconds — typical bursts are 5–7 minutes. Tank may have a slow refill.",
        metrics: {"runtimeSeconds": 552},
        hoursAgo: 23,
      ),
      _AnomalyTemplate(
        deviceId: "1",
        deviceName: "Fan",
        deviceType: "fan",
        severity: "critical",
        title: "Current draw exceeded",
        detail:
            "Fan current peaked at 1.92 A on the 12 V DC line — exceeds the 1.5 A limit. Bearing friction likely above normal.",
        metrics: {"current": 1.92},
        hoursAgo: 30,
      ),
      _AnomalyTemplate(
        deviceId: "2",
        deviceName: "Bulb",
        deviceType: "bulb",
        severity: "info",
        title: "Bulb on after sunrise",
        detail:
            "Bulb stayed on 23 minutes past sunrise. Consider a daylight-aware schedule.",
        metrics: {"overrunMinutes": 23},
        hoursAgo: 38,
      ),
      _AnomalyTemplate(
        deviceId: "1",
        deviceName: "Fan",
        deviceType: "fan",
        severity: "warning",
        title: "Idle device wasting energy",
        detail:
            "Fan was on while no occupant motion was detected for 32 minutes.",
        metrics: {"idleMinutes": 32, "wastedKWh": 0.10},
        hoursAgo: 50,
      ),
      _AnomalyTemplate(
        deviceId: "4",
        deviceName: "Bell",
        deviceType: "bell",
        severity: "info",
        title: "Bell triggered without flame",
        detail:
            "Bell rang from a manual app command at 03:14 — outside expected security window.",
        metrics: {"hour": 3.23},
        hoursAgo: 62,
      ),
      _AnomalyTemplate(
        deviceId: "3",
        deviceName: "Pump",
        deviceType: "pump",
        severity: "critical",
        title: "Voltage out of band",
        detail:
            "Pump line voltage dipped to 9.8 V during start-up — outside the 11–13 V safe band for this 12 V DC device.",
        metrics: {"voltage": 9.8},
        hoursAgo: 75,
      ),
      _AnomalyTemplate(
        deviceId: "2",
        deviceName: "Bulb",
        deviceType: "bulb",
        severity: "warning",
        title: "Voltage surge auto-cut",
        detail:
            "ESP32 auto-cut tripped at 234 V (band 219–221 V). Bulb returned to service after 60 s.",
        metrics: {"voltage": 234.0},
        hoursAgo: 96,
      ),
      _AnomalyTemplate(
        deviceId: "1",
        deviceName: "Fan",
        deviceType: "fan",
        severity: "info",
        title: "Energy above seasonal baseline",
        detail:
            "Fan energy 1.42 kWh today vs. 30-day average 1.18 kWh (+20%). Outside temperature was 38°C.",
        metrics: {"todayKWh": 1.42, "baselineKWh": 1.18},
        hoursAgo: 110,
      ),
      _AnomalyTemplate(
        deviceId: "2",
        deviceName: "Bulb",
        deviceType: "bulb",
        severity: "info",
        title: "Idle device wasting energy",
        detail:
            "Bulb was on 14 minutes past midnight without motion — likely forgotten.",
        metrics: {"idleMinutes": 14, "wastedKWh": 0.02},
        hoursAgo: 130,
      ),
      _AnomalyTemplate(
        deviceId: "3",
        deviceName: "Pump",
        deviceType: "pump",
        severity: "warning",
        title: "Current draw exceeded",
        detail:
            "Pump current 6.4 A briefly exceeded its 6.0 A limit — possible blockage in suction line.",
        metrics: {"current": 6.4},
        hoursAgo: 145,
      ),
      _AnomalyTemplate(
        deviceId: "1",
        deviceName: "Fan",
        deviceType: "fan",
        severity: "info",
        title: "Schedule deviation",
        detail:
            "Fan turned on outside its usual 11 AM window. Likely manual override.",
        metrics: {"hour": 8.5},
        hoursAgo: 155,
      ),
      _AnomalyTemplate(
        deviceId: "2",
        deviceName: "Bulb",
        deviceType: "bulb",
        severity: "warning",
        title: "Idle device wasting energy",
        detail:
            "Bulb on 28 minutes after last motion in the room.",
        metrics: {"idleMinutes": 28, "wastedKWh": 0.04},
        hoursAgo: 165,
      ),
    ];

    for (var i = 0; i < templates.length; i++) {
      final t = templates[i];
      final detected = DateTime.now().subtract(Duration(hours: t.hoursAgo));
      final docId = "demo_anomaly_$i";
      await col.doc(docId).set({
        "deviceId": t.deviceId,
        "deviceName": t.deviceName,
        "deviceType": t.deviceType,
        "severity": t.severity,
        "title": t.title,
        "detail": t.detail,
        "metrics": t.metrics,
        "trigger": "anomaly_detector",
        "detectedAt": Timestamp.fromDate(detected),
        "resolvedAt": (i % 4 == 0)
            ? Timestamp.fromDate(detected.add(const Duration(minutes: 14)))
            : null,
        "epoch": detected.millisecondsSinceEpoch,
        "isDemoSeed": true,
      });
      r.anomalies++;
    }
  }

  // =========================================================
  // AGENT ACTIONS
  // =========================================================
  static Future<void> _seedAgentActions(String uid, SeedReport r) async {
    final col = _fs
        .collection("users")
        .doc(uid)
        .collection("agent_actions");

    final actions = [
      {
        "deviceId": "1",
        "deviceName": "Fan",
        "action": "on",
        "trigger": "sensor_smoke",
        "reason":
            "Smoke detected by the kitchen sensor. Fan switched on to ventilate the area.",
        "hoursAgo": 0.6,
      },
      {
        "deviceId": "2",
        "deviceName": "Bulb",
        "action": "off",
        "trigger": "auto_motion_timeout",
        "reason":
            "No motion detected for 2 minutes — bulb switched off to save energy.",
        "hoursAgo": 1.4,
      },
      {
        "deviceId": "1",
        "deviceName": "Fan",
        "action": "on",
        "trigger": "agent_chat",
        "reason":
            "User asked the agent: 'Turn on the fan, it's hot'.",
        "hoursAgo": 3.2,
      },
      {
        "deviceId": "3",
        "deviceName": "Pump",
        "action": "off",
        "trigger": "agent_chat",
        "reason":
            "User asked: 'Stop the pump'. Tank level was already at 84%.",
        "hoursAgo": 6.8,
      },
      {
        "deviceId": "2",
        "deviceName": "Bulb",
        "action": "auto_cut",
        "trigger": "sensor_voltage_surge",
        "reason":
            "Voltage outside the 219–221 V safe band — auto-cut engaged for 60 seconds.",
        "hoursAgo": 24.0,
      },
      {
        "deviceId": "4",
        "deviceName": "Bell",
        "action": "on",
        "trigger": "sensor_flame",
        "reason":
            "Flame detected by the kitchen sensor. Bell rung as evacuation alert.",
        "hoursAgo": 38.0,
      },
      {
        "deviceId": "1",
        "deviceName": "Fan",
        "action": "off",
        "trigger": "anomaly_detector",
        "reason":
            "Fan exceeded 90 minutes runtime with no motion — turned off automatically.",
        "hoursAgo": 50.0,
      },
      {
        "deviceId": "2",
        "deviceName": "Bulb",
        "action": "on",
        "trigger": "agent_chat",
        "reason":
            "User asked: 'Turn the lamp on, I'm reading'.",
        "hoursAgo": 70.0,
      },
    ];

    for (var i = 0; i < actions.length; i++) {
      final a = actions[i];
      final ts = DateTime.now().subtract(Duration(
          minutes: ((a["hoursAgo"] as double) * 60).round()));
      await col.doc("demo_action_$i").set({
        "deviceId": a["deviceId"],
        "deviceName": a["deviceName"],
        "action": a["action"],
        "reason": a["reason"],
        "trigger": a["trigger"],
        "timestamp": ts.toIso8601String(),
        "epoch": ts.millisecondsSinceEpoch,
        "isDemoSeed": true,
      });
      r.agentActions++;
    }
  }

  // =========================================================
  // BILLING HISTORY (last 6 months)
  // =========================================================
  static Future<void> _seedBillingHistory(SeedReport r) async {
    final now = DateTime.now();
    for (var i = 1; i <= 6; i++) {
      final m = DateTime(now.year, now.month - i, 1);
      final id =
          "${m.year}-${m.month.toString().padLeft(2, '0')}";
      final kWh = 60 + _rng.nextDouble() * 50; // 60–110 kWh / month
      final rupees = kWh * 55.0;
      await _fs.collection("billing_history").doc(id).set({
        "month": id,
        "totalKWh": double.parse(kWh.toStringAsFixed(2)),
        "totalRupees": double.parse(rupees.toStringAsFixed(2)),
        "tariffPerKWh": 55.0,
        "isDemoSeed": true,
      });
      r.billingMonths++;
    }
  }

  // =========================================================
  // HELPERS
  // =========================================================
  static String _yyyymmdd(DateTime d) =>
      "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  static String _dayName(int weekday) {
    const days = [
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
      "Sunday"
    ];
    return days[weekday - 1];
  }
}

class SeedReport {
  int fakeRoommates = 0;
  int energyDays = 0;
  int anomalies = 0;
  int agentActions = 0;
  int billingMonths = 0;
  bool currentUserPatched = false;

  String summarise() {
    return "Seeded $energyDays days of energy, "
        "$fakeRoommates roommates, "
        "$anomalies anomalies, "
        "$agentActions agent actions, "
        "$billingMonths months of billing"
        "${currentUserPatched ? " (and patched your profile)" : ""}.";
  }
}

class _AnomalyTemplate {
  final String deviceId;
  final String deviceName;
  final String deviceType;
  final String severity;
  final String title;
  final String detail;
  final Map<String, double> metrics;
  final int hoursAgo;
  const _AnomalyTemplate({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.severity,
    required this.title,
    required this.detail,
    required this.metrics,
    required this.hoursAgo,
  });
}
