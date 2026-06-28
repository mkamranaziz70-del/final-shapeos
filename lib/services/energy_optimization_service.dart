// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/room_model.dart';
import 'agent_action_logger.dart';
import 'agent_memory_service.dart';
import 'room_device_state_service.dart';
import 'room_service.dart';
import 'voice_service.dart';

/// =========================================================
/// PREDICTIVE ENERGY OPTIMIZATION
/// =========================================================
/// The differentiating brain on top of the home automation
/// stack. It does what a generic "auto-off after 5 min" timer
/// cannot — it learns from past usage, identifies recurring
/// peak-hour waste, predicts tomorrow's likely overspend, and
/// commits enforceable rules that the agent then carries out.
///
/// Public surface:
///   • generateReport()             — produce a fresh AI-style
///                                    summary + recommendations
///   • activeRules()                — currently committed rules
///   • commitRule(rule)             — turn a recommendation into
///                                    an enforceable peak-hour
///                                    auto-off
///   • shouldOptimizeNow(deviceId)  — engine asks this on each
///                                    tick to decide whether to
///                                    cut a peak-hour standby
///   • runDemoCycle()               — collapses the day-1 / day-2
///                                    observation → optimization
///                                    sequence into ~30 seconds
///                                    so a panel can see it live
///
/// Storage:
///   /users/{uid}/optimizations/{auto-id}     — committed rules
///   /users/{uid}/optimization_reports/{auto} — historical reports
class EnergyOptimizationService {
  EnergyOptimizationService._();

  /// Pakistan tariff bands. Peak hours are evening when the grid
  /// is most stressed; off-peak is the rest of the day.
  static const int peakStartHour = 18; // 6 PM
  static const int peakEndHour = 23;   // 11 PM (exclusive)
  static const double offPeakRate = 55.0; // ₨/kWh
  static const double peakRate = 70.0;    // ₨/kWh — typical TOU multiplier

  static String? _uidOrNull() =>
      FirebaseAuth.instance.currentUser?.uid;

  static CollectionReference<Map<String, dynamic>>? _optsCol() {
    final uid = _uidOrNull();
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("optimizations");
  }

  static CollectionReference<Map<String, dynamic>>? _reportsCol() {
    final uid = _uidOrNull();
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("optimization_reports");
  }

  /// True when the device is on AND the current hour falls
  /// inside the peak-hour band — used by [AgentAutomationEngine]
  /// to decide whether to commit an auto-off.
  static bool isPeakHourNow() {
    final h = DateTime.now().hour;
    return h >= peakStartHour && h < peakEndHour;
  }

  // =========================================================
  // REPORT GENERATION
  // =========================================================

  /// Produce a fresh predictive-optimization report based on the
  /// most recent two weeks of seeded + lived energy data.
  static Future<OptimizationReport> generateReport() async {
    final fs = FirebaseFirestore.instance;
    final now = DateTime.now();
    final twoWeeksAgo = now.subtract(const Duration(days: 14));

    // 1) Pull energy_daily docs from the last 14 days.
    final daysSnap = await fs.collection("energy_daily").get();
    final perDeviceTotalKWh = <String, double>{};
    final perDevicePeakKWh = <String, double>{};
    final perDeviceHourly = <String, Map<int, double>>{};
    final daysScanned = <String>{};

    for (final doc in daysSnap.docs) {
      final id = doc.id;
      final docDate = DateTime.tryParse(id);
      if (docDate == null) continue;
      if (docDate.isBefore(twoWeeksAgo)) continue;
      daysScanned.add(id);

      final hourly = doc.data()["hourlyUsage"];
      final devicesField = doc.data()["devices"];

      // Per-device totals.
      if (devicesField is Map) {
        devicesField.forEach((k, v) {
          if (v is! Map) return;
          final e = _toD(v["energy"]);
          if (e <= 0) return;
          perDeviceTotalKWh.update(k.toString(), (p) => p + e,
              ifAbsent: () => e);
        });
      }

      // Hourly distribution — split per device proportionally.
      if (hourly is Map && devicesField is Map) {
        for (final hourKey in hourly.keys) {
          final hour = int.tryParse(hourKey.toString());
          if (hour == null) continue;
          final hourTotal = _toD(hourly[hourKey]);
          if (hourTotal <= 0) continue;
          final dayDeviceTotal = devicesField.values.fold<double>(
            0,
            (acc, v) => v is Map ? acc + _toD(v["energy"]) : acc,
          );
          if (dayDeviceTotal <= 0) continue;
          devicesField.forEach((k, v) {
            if (v is! Map) return;
            final share = _toD(v["energy"]) / dayDeviceTotal;
            final inc = hourTotal * share;
            perDeviceHourly
                .putIfAbsent(k.toString(), () => <int, double>{})
                .update(hour, (p) => p + inc, ifAbsent: () => inc);
            if (hour >= peakStartHour && hour < peakEndHour) {
              perDevicePeakKWh.update(k.toString(), (p) => p + inc,
                  ifAbsent: () => inc);
            }
          });
        }
      }
    }

    // 2) Build recommendations per device.
    final recs = <OptimizationRecommendation>[];
    final names = await _readDeviceNames();
    for (final entry in perDeviceTotalKWh.entries) {
      final id = entry.key;
      final totalKWh = entry.value;
      final peakKWh = perDevicePeakKWh[id] ?? 0;
      if (totalKWh <= 0) continue;
      final peakShare = peakKWh / totalKWh;
      final hourly = perDeviceHourly[id] ?? const {};
      final peakHourEntry = _argmax(hourly);
      // Permissive thresholds — even modest peak-hour usage (≥10
      // Wh and ≥5% of the device's daily energy) gets flagged so
      // the recommendations list is never empty when there's data.
      final wastefulPeak = peakKWh > 0.01 && peakShare >= 0.05;
      // Project savings if we cut peak-hour standby.
      final projectedMonthlyPeakKWh = peakKWh * (30.0 / daysScanned.length.clamp(1, 30));
      final projectedSavings = projectedMonthlyPeakKWh * peakRate;
      recs.add(OptimizationRecommendation(
        deviceId: id,
        deviceName: names[id] ?? "Device $id",
        twoWeekKWh: totalKWh,
        peakKWh: peakKWh,
        peakShare: peakShare,
        peakHour: peakHourEntry?.key ?? peakStartHour,
        recommendation: wastefulPeak
            ? "Auto-off ${names[id] ?? "Device $id"} during 6 PM – 11 PM peak hours when no occupancy is detected."
            : "Usage of ${names[id] ?? "Device $id"} is already lean. No action needed.",
        projectedMonthlySavingsPKR: wastefulPeak ? projectedSavings : 0,
        wastefulPeak: wastefulPeak,
      ));
    }

    // 3) Aggregate totals.
    final totalKWh =
        perDeviceTotalKWh.values.fold<double>(0, (s, v) => s + v);
    final totalPeakKWh =
        perDevicePeakKWh.values.fold<double>(0, (s, v) => s + v);
    final monthlyProjectedSavings = recs
        .where((r) => r.wastefulPeak)
        .fold<double>(0, (s, r) => s + r.projectedMonthlySavingsPKR);

    final report = OptimizationReport(
      generatedAt: now,
      daysAnalyzed: daysScanned.length,
      totalKWh: totalKWh,
      totalPeakKWh: totalPeakKWh,
      peakSharePercent:
          totalKWh > 0 ? (totalPeakKWh / totalKWh) * 100 : 0,
      projectedMonthlySavingsPKR: monthlyProjectedSavings,
      recommendations: recs,
    );

    // 4) Persist.
    try {
      await _reportsCol()?.add(report.toMap());
    } catch (e) {
      debugPrint("Optimization report persist failed: $e");
    }

    return report;
  }

  // =========================================================
  // RULE COMMITMENT
  // =========================================================
  /// Commit a peak-hour auto-off rule. If [scopedRoom] is given
  /// the rule is scoped to that specific room — two rooms that
  /// share the same physical device id (e.g. Kamran's Bedroom and
  /// Ali's Lounge both having a fan) can each commit their own
  /// independent rule, and the engine will fire each rule only
  /// for its own room.
  static Future<void> commitRule(
    OptimizationRecommendation r, {
    RoomModel? scopedRoom,
  }) async {
    final col = _optsCol();
    if (col == null) return;
    final now = DateTime.now();
    final room = scopedRoom ?? await roomForDevice(r.deviceId);
    // Composite doc id: per (room, device) so rules don't collide
    // when multiple rooms share the same physical appliance.
    final docId = room == null
        ? "peak_${r.deviceId}"
        : "peak_${room.id}_${r.deviceId}";
    await col.doc(docId).set({
      "deviceId": r.deviceId,
      "deviceName": r.deviceName,
      "roomId": room?.id ?? "",
      "roomName": room?.name ?? "",
      "occupant": room?.occupant ?? "",
      "kind": "peak_hour_auto_off",
      "peakHour": r.peakHour,
      "monthlySavingsPKR": r.projectedMonthlySavingsPKR,
      "active": true,
      "committedAt": Timestamp.fromDate(now),
    });
    await AgentActionLogger.log(
      deviceId: r.deviceId,
      deviceName: r.deviceName,
      action: "optimize_commit",
      reason:
          "Peak-hour optimization committed — ${r.deviceName} will auto-off "
          "during 6 PM – 11 PM when nobody is in the room. "
          "Estimated saving ₨ ${r.projectedMonthlySavingsPKR.toStringAsFixed(0)}/month.",
      trigger: "energy_optimizer",
    );
    await AgentMemoryService.remember(
      "opt_peak_${r.deviceId}",
      "${r.deviceName} peak-hour auto-off rule active "
      "(saves ~₨ ${r.projectedMonthlySavingsPKR.toStringAsFixed(0)}/month).",
    );
  }

  /// Stream of currently committed rules — used by the
  /// Optimization tab to render the active list.
  static Stream<List<CommittedRule>> activeRules() {
    final col = _optsCol();
    if (col == null) return const Stream.empty();
    return col
        .where("active", isEqualTo: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => CommittedRule.fromMap(d.id, d.data()))
            .toList());
  }

  static Future<void> deactivateRule(String ruleId) async {
    final col = _optsCol();
    if (col == null) return;
    await col.doc(ruleId).update({"active": false});
  }

  /// Engine hook: returns one decision per active peak-hour
  /// rule matching this device id. Multiple decisions can be
  /// returned when several rooms have committed independent
  /// rules for the same shared device — the engine fires each
  /// of them with its own room context.
  static Future<List<PeakHourDecision>> shouldOptimizeNow(
      String deviceId, bool isOn) async {
    if (!isOn) return const [];
    if (!isPeakHourNow()) return const [];
    final col = _optsCol();
    if (col == null) return const [];
    final hits = await col
        .where("deviceId", isEqualTo: deviceId)
        .where("active", isEqualTo: true)
        .get();
    return hits.docs.map((d) {
      final data = d.data();
      return PeakHourDecision(
        deviceId: deviceId,
        deviceName: data["deviceName"]?.toString() ?? "Device",
        roomId: data["roomId"]?.toString() ?? "",
        roomName: data["roomName"]?.toString() ?? "",
        occupant: data["occupant"]?.toString() ?? "",
        monthlySavingsPKR:
            (data["monthlySavingsPKR"] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  // =========================================================
  // PANEL DEMO CYCLE
  // =========================================================
  /// Compresses the "yesterday observed → today optimized" cycle
  /// into a 30-second visible sequence so a panel can watch the
  /// agent learn and act in real time.
  ///
  /// Step 1 (immediate): announce yesterday's peak-hour overspend.
  /// Step 2 (~5 s):      generate + commit the optimization rule.
  /// Step 3 (~10 s):     turn the chosen device ON so the panel
  ///                     can see the rule fire on a real toggle.
  /// Step 4 (~15 s):     auto-off, narrate savings, log.
  static Future<void> runDemoCycle({
    String deviceId = "2",
    required double dailyPeakKWh,
    RoomModel? scopedRoom,
  }) async {
    final names = await _readDeviceNames();
    final name = names[deviceId] ?? "Device $deviceId";
    final room = scopedRoom ?? await roomForDevice(deviceId);
    final roomPhrase =
        room == null ? "the home" : room.name;
    final yesterdayCost = dailyPeakKWh * peakRate;
    final monthlySaving = yesterdayCost * 30 * 0.7;

    // Pre-compute the list of every room that owns this device
    // so per-room state writes can correctly recompute the
    // shared physical /appliances/{id} flag.
    final allRooms = await RoomService.all();
    final roomsWithDevice = allRooms
        .where((r) => r.deviceIds.contains(deviceId))
        .map((r) => r.id)
        .toList();

    // Step 1 — observation phase.
    await VoiceService.speak(
      "Heads up. I noticed the $name in $roomPhrase was on between 6 PM "
      "and 10 PM during peak hours yesterday, costing about "
      "${yesterdayCost.toStringAsFixed(0)} rupees. From now on, I will "
      "auto-off the $name in $roomPhrase during peak hours.",
    );
    await AgentActionLogger.log(
      deviceId: deviceId,
      deviceName: name,
      action: "optimize_observation",
      reason:
          "$name was on 6 PM – 10 PM yesterday during peak. "
          "Wasted ₨ ${yesterdayCost.toStringAsFixed(0)}.",
      trigger: "energy_optimizer",
    );

    // Step 2 — commit the rule (scoped to this room so it can
    // coexist with other rooms' rules on the same device).
    await Future.delayed(const Duration(seconds: 4));
    final rec = OptimizationRecommendation(
      deviceId: deviceId,
      deviceName: name,
      twoWeekKWh: dailyPeakKWh * 14,
      peakKWh: dailyPeakKWh * 14,
      peakShare: 1.0,
      peakHour: peakStartHour + 1,
      recommendation:
          "Auto-off $name in $roomPhrase during 6 PM – 11 PM peak hours.",
      projectedMonthlySavingsPKR: monthlySaving,
      wastefulPeak: true,
    );
    await commitRule(rec, scopedRoom: room);
    await VoiceService.speak(
      "Optimization rule committed for $roomPhrase. Estimated monthly saving: "
      "${monthlySaving.toStringAsFixed(0)} rupees.",
    );

    // Step 3 — turn the device on inside THIS room only (per-room
    // virtual state). Other rooms with the same device id are
    // untouched.
    await Future.delayed(const Duration(seconds: 3));
    if (room != null) {
      await RoomDeviceStateService.set(
        roomId: room.id,
        deviceId: deviceId,
        isOn: true,
        roomsWithDevice: roomsWithDevice,
      );
    } else {
      await FirebaseDatabase.instance
          .ref("appliances/$deviceId")
          .update({"isOn": true});
    }
    await VoiceService.speak(
      "Simulating $name in $roomPhrase turning on during the peak window.",
    );

    // Step 4 — auto-off, scoped to THIS room only.
    await Future.delayed(const Duration(seconds: 6));
    if (room != null) {
      await RoomDeviceStateService.cutInRoom(
        roomId: room.id,
        deviceId: deviceId,
        roomsWithDevice: roomsWithDevice,
      );
    } else {
      await FirebaseDatabase.instance
          .ref("appliances/$deviceId")
          .update({"isOn": false});
    }
    final savedNow = (dailyPeakKWh / 4) * peakRate;
    await VoiceService.speak(
      "$name in $roomPhrase auto-cut. Peak-hour optimization engaged. "
      "Saved about ${savedNow.toStringAsFixed(0)} rupees on this run.",
    );
    await AgentActionLogger.log(
      deviceId: deviceId,
      deviceName: name,
      action: "off",
      reason:
          "Peak-hour auto-off — $roomPhrase · $name. "
          "$peakStartHour:00–$peakEndHour:00 window. "
          "Saved ₨ ${savedNow.toStringAsFixed(2)} on this run.",
      trigger: "energy_optimizer",
    );
  }

  // =========================================================
  // HELPERS
  // =========================================================
  static Future<Map<String, String>> _readDeviceNames() async {
    final out = <String, String>{};
    try {
      final snap =
          await FirebaseDatabase.instance.ref("appliances").get();
      final raw = snap.value;
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map && v["name"] != null) {
            out[k.toString()] = v["name"].toString();
          }
        });
      } else if (raw is List) {
        for (var i = 0; i < raw.length; i++) {
          final v = raw[i];
          if (v is Map && v["name"] != null) {
            out[i.toString()] = v["name"].toString();
          }
        }
      }
    } catch (_) {}
    // Hard-coded fallback for the canonical four devices.
    out.putIfAbsent("1", () => "Fan");
    out.putIfAbsent("2", () => "Bulb");
    out.putIfAbsent("3", () => "Pump");
    out.putIfAbsent("4", () => "Bell");
    return out;
  }

  static MapEntry<int, double>? _argmax(Map<int, double> m) {
    if (m.isEmpty) return null;
    return m.entries.reduce((a, b) => a.value >= b.value ? a : b);
  }

  static double _toD(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  // =========================================================
  // PER-ROOM ANALYSIS
  // =========================================================
  /// Build a per-room report from the latest [generateReport]
  /// run. Pairs each room with the recommendations whose device
  /// belongs to it, then totals + ranks the top peak consumer.
  ///
  /// This is what powers the "Kamran's Bedroom · Bulb wasted X kWh
  /// in peak hours" cards on the optimization tab and the spoken
  /// auto-cut announcements that name the room.
  static Future<List<RoomEnergyReport>> generateRoomReports() async {
    final base = await generateReport();
    final rooms = await RoomService.all();
    final out = <RoomEnergyReport>[];
    final byDevice = {
      for (final r in base.recommendations) r.deviceId: r,
    };
    for (final room in rooms) {
      final usages = <DeviceUsage>[];
      double roomPeak = 0;
      double roomTotal = 0;
      double roomSaving = 0;
      for (final id in room.deviceIds) {
        final rec = byDevice[id];
        if (rec == null) continue;
        roomPeak += rec.peakKWh;
        roomTotal += rec.twoWeekKWh;
        roomSaving += rec.projectedMonthlySavingsPKR;
        usages.add(DeviceUsage(
          deviceId: rec.deviceId,
          deviceName: rec.deviceName,
          twoWeekKWh: rec.twoWeekKWh,
          peakKWh: rec.peakKWh,
          peakHour: rec.peakHour,
          peakShare: rec.peakShare,
          wastefulPeak: rec.wastefulPeak,
          projectedMonthlySavingsPKR: rec.projectedMonthlySavingsPKR,
        ));
      }
      usages.sort((a, b) => b.peakKWh.compareTo(a.peakKWh));
      out.add(RoomEnergyReport(
        room: room,
        devices: usages,
        roomPeakKWh: roomPeak,
        roomTotalKWh: roomTotal,
        peakSharePercent:
            roomTotal > 0 ? (roomPeak / roomTotal) * 100 : 0,
        projectedMonthlySavingsPKR: roomSaving,
      ));
    }
    // Loudest room first.
    out.sort((a, b) => b.roomPeakKWh.compareTo(a.roomPeakKWh));
    return out;
  }

  /// Find the room a device lives in (if any). Used by the
  /// engine to attach room context to spoken / notified
  /// auto-cut events.
  static Future<RoomModel?> roomForDevice(String deviceId) async {
    final rooms = await RoomService.all();
    for (final r in rooms) {
      if (r.deviceIds.contains(deviceId)) return r;
    }
    return null;
  }
}

/// =========================================================
/// PER-ROOM REPORT TYPES
/// =========================================================
@immutable
class DeviceUsage {
  final String deviceId;
  final String deviceName;
  final double twoWeekKWh;
  final double peakKWh;
  final int peakHour;
  final double peakShare;
  final bool wastefulPeak;
  final double projectedMonthlySavingsPKR;

  const DeviceUsage({
    required this.deviceId,
    required this.deviceName,
    required this.twoWeekKWh,
    required this.peakKWh,
    required this.peakHour,
    required this.peakShare,
    required this.wastefulPeak,
    required this.projectedMonthlySavingsPKR,
  });
}

@immutable
class RoomEnergyReport {
  final RoomModel room;
  final List<DeviceUsage> devices;
  final double roomPeakKWh;
  final double roomTotalKWh;
  final double peakSharePercent;
  final double projectedMonthlySavingsPKR;

  const RoomEnergyReport({
    required this.room,
    required this.devices,
    required this.roomPeakKWh,
    required this.roomTotalKWh,
    required this.peakSharePercent,
    required this.projectedMonthlySavingsPKR,
  });

  DeviceUsage? get topPeakDevice =>
      devices.isEmpty ? null : devices.first;
}

@immutable
class OptimizationRecommendation {
  final String deviceId;
  final String deviceName;
  final double twoWeekKWh;
  final double peakKWh;
  final double peakShare; // 0..1
  final int peakHour;
  final String recommendation;
  final double projectedMonthlySavingsPKR;
  final bool wastefulPeak;

  const OptimizationRecommendation({
    required this.deviceId,
    required this.deviceName,
    required this.twoWeekKWh,
    required this.peakKWh,
    required this.peakShare,
    required this.peakHour,
    required this.recommendation,
    required this.projectedMonthlySavingsPKR,
    required this.wastefulPeak,
  });
}

@immutable
class OptimizationReport {
  final DateTime generatedAt;
  final int daysAnalyzed;
  final double totalKWh;
  final double totalPeakKWh;
  final double peakSharePercent;
  final double projectedMonthlySavingsPKR;
  final List<OptimizationRecommendation> recommendations;

  const OptimizationReport({
    required this.generatedAt,
    required this.daysAnalyzed,
    required this.totalKWh,
    required this.totalPeakKWh,
    required this.peakSharePercent,
    required this.projectedMonthlySavingsPKR,
    required this.recommendations,
  });

  Map<String, dynamic> toMap() => {
        "generatedAt": Timestamp.fromDate(generatedAt),
        "daysAnalyzed": daysAnalyzed,
        "totalKWh": totalKWh,
        "totalPeakKWh": totalPeakKWh,
        "peakSharePercent": peakSharePercent,
        "projectedMonthlySavingsPKR": projectedMonthlySavingsPKR,
        "recommendations": recommendations
            .map((r) => {
                  "deviceId": r.deviceId,
                  "deviceName": r.deviceName,
                  "twoWeekKWh": r.twoWeekKWh,
                  "peakKWh": r.peakKWh,
                  "peakShare": r.peakShare,
                  "peakHour": r.peakHour,
                  "recommendation": r.recommendation,
                  "projectedMonthlySavingsPKR":
                      r.projectedMonthlySavingsPKR,
                  "wastefulPeak": r.wastefulPeak,
                })
            .toList(),
      };
}

@immutable
class CommittedRule {
  final String id;
  final String deviceId;
  final String deviceName;
  final String roomId;
  final String roomName;
  final String occupant;
  final String kind;
  final int peakHour;
  final double monthlySavingsPKR;
  final DateTime committedAt;
  final bool active;

  const CommittedRule({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.roomId,
    required this.roomName,
    required this.occupant,
    required this.kind,
    required this.peakHour,
    required this.monthlySavingsPKR,
    required this.committedAt,
    required this.active,
  });

  factory CommittedRule.fromMap(String id, Map<String, dynamic> m) {
    final ts = m["committedAt"];
    return CommittedRule(
      id: id,
      deviceId: m["deviceId"]?.toString() ?? "",
      deviceName: m["deviceName"]?.toString() ?? "",
      roomId: m["roomId"]?.toString() ?? "",
      roomName: m["roomName"]?.toString() ?? "",
      occupant: m["occupant"]?.toString() ?? "",
      kind: m["kind"]?.toString() ?? "",
      peakHour: (m["peakHour"] as num?)?.toInt() ?? 18,
      monthlySavingsPKR:
          (m["monthlySavingsPKR"] as num?)?.toDouble() ?? 0,
      committedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      active: m["active"] == true,
    );
  }

  /// Display label for the active-rules card: "Kamran's Bedroom · Fan"
  String get displayLabel =>
      roomName.isEmpty ? deviceName : "$roomName · $deviceName";
}

@immutable
class PeakHourDecision {
  final String deviceId;
  final String deviceName;
  final String roomId;
  final String roomName;
  final String occupant;
  final double monthlySavingsPKR;

  const PeakHourDecision({
    required this.deviceId,
    required this.deviceName,
    required this.roomId,
    required this.roomName,
    required this.occupant,
    required this.monthlySavingsPKR,
  });

  /// Natural-language room phrase used in spoken / pushed
  /// announcements: "Kamran's Bedroom" or just "the home" if the
  /// device hasn't been assigned to a room.
  String get roomPhrase {
    if (roomName.isEmpty) return "the home";
    if (occupant.isEmpty) return roomName;
    return roomName;
  }
}
