import 'package:cloud_firestore/cloud_firestore.dart';

class EnergyLogger {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// ⚙️ CONFIG
  static const double unitPricePKR = 55.0; // PKR per kWh

  /// ⏱ Call this EVERY MINUTE for each ACTIVE device
  static Future<void> logEnergy({
    required String deviceId,
    required String deviceName,
    required double power, // watts
  }) async {
    final now = DateTime.now();

    final dateId =
        "${now.year}-${_pad(now.month)}-${_pad(now.day)}";
    final hourKey = _pad(now.hour);

    final ref = _db.collection("energy_daily").doc(dateId);

    final double energyIncrement =
        (power / 1000) / 60; // kWh per minute

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};

      // ───────────── Hourly Usage ─────────────
      final Map<String, double> hourlyUsage =
          Map<String, double>.from(
        (data["hourlyUsage"] ?? {}),
      );

      hourlyUsage[hourKey] =
          (hourlyUsage[hourKey] ?? 0) + energyIncrement;

      // ───────────── Device Usage ─────────────
      final Map<String, dynamic> devices =
          Map<String, dynamic>.from(
        (data["devices"] ?? {}),
      );

      final deviceData =
          Map<String, dynamic>.from(devices[deviceId] ?? {});

      deviceData["name"] = deviceName;
      deviceData["energy"] =
          (deviceData["energy"] ?? 0.0) + energyIncrement;

      devices[deviceId] = deviceData;

      // ───────────── Total Energy ─────────────
      final double totalEnergy =
          (data["totalEnergy"] ?? 0.0) + energyIncrement;

      // ───────────── Peak Hour ─────────────
      final peak = _findPeakHour(hourlyUsage);

      // ───────────── Most Used Device ─────────────
      final mostUsed = _mostUsedDevice(devices);

      // ───────────── Suggestions ─────────────
      final suggestions =
          _generateSuggestions(peak["energy"] ?? 0.0);

      // ───────────── Bill Estimation ─────────────
      final billEstimate = totalEnergy * unitPricePKR;

      tx.set(
        ref,
        {
          "date": dateId,
          "day": _dayName(now.weekday),
          "hourlyUsage": hourlyUsage,
          "devices": devices,
          "totalEnergy": totalEnergy,
          "peakHour": peak["hour"],
          "peakEnergy": peak["energy"],
          "mostUsedDevice": mostUsed,
          "suggestions": suggestions,
          "billEstimate": billEstimate,
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  // ───────────────── HELPERS ─────────────────

  static Map<String, dynamic> _findPeakHour(
      Map<String, double> hourly) {
    if (hourly.isEmpty) {
      return {"hour": null, "energy": 0.0};
    }

    final peak = hourly.entries.reduce(
      (a, b) => a.value > b.value ? a : b,
    );

    return {
      "hour": "${peak.key}:00 - ${peak.key}:59",
      "energy": peak.value,
    };
  }

  static String _mostUsedDevice(
      Map<String, dynamic> devices) {
    if (devices.isEmpty) return "None";

    final entry = devices.entries.reduce((a, b) {
      final ea = a.value["energy"] ?? 0.0;
      final eb = b.value["energy"] ?? 0.0;
      return ea > eb ? a : b;
    });

    return entry.value["name"] ?? entry.key;
  }

  static List<String> _generateSuggestions(double peakEnergy) {
    final List<String> tips = [];

    if (peakEnergy > 0.5) {
      tips.add(
          "High energy usage detected during peak hours. Consider reducing load.");
    }
    if (peakEnergy > 1.0) {
      tips.add(
          "Multiple devices running together. Stagger device usage.");
    }
    if (tips.isEmpty) {
      tips.add("Energy usage is optimal today. Good job!");
    }

    return tips;
  }

  static String _dayName(int d) {
    const days = [
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
      "Sunday"
    ];
    return days[d - 1];
  }

  static String _pad(int v) =>
      v.toString().padLeft(2, '0');
}
