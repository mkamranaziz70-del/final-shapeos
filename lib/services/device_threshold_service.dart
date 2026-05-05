// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// =========================================================
/// DEVICE THRESHOLDS
/// =========================================================
/// Per-device safe-operating ranges that the agent (or the user
/// via the agent) can tune at runtime.
///
/// Stored at `users/{uid}/device_thresholds/{deviceId}`:
///   {
///     voltageMin, voltageMax,
///     currentMin, currentMax,
///     powerMin,   powerMax,
///     updatedAt
///   }
///
/// `AnomalyDetectionService` reads these to decide whether a
/// reading is out-of-band. Defaults fall back to safe global
/// constants if the user hasn't set anything.
class DeviceThreshold {
  final String deviceId;
  final double? voltageMin;
  final double? voltageMax;
  final double? currentMin;
  final double? currentMax;
  final double? powerMin;
  final double? powerMax;
  final DateTime? updatedAt;

  const DeviceThreshold({
    required this.deviceId,
    this.voltageMin,
    this.voltageMax,
    this.currentMin,
    this.currentMax,
    this.powerMin,
    this.powerMax,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        if (voltageMin != null) "voltageMin": voltageMin,
        if (voltageMax != null) "voltageMax": voltageMax,
        if (currentMin != null) "currentMin": currentMin,
        if (currentMax != null) "currentMax": currentMax,
        if (powerMin != null) "powerMin": powerMin,
        if (powerMax != null) "powerMax": powerMax,
        "updatedAt": Timestamp.now(),
      };

  factory DeviceThreshold.fromDoc(
      String id, Map<String, dynamic> d) {
    double? read(String k) {
      final v = d[k];
      if (v is num) return v.toDouble();
      return null;
    }

    final ts = d["updatedAt"];
    return DeviceThreshold(
      deviceId: id,
      voltageMin: read("voltageMin"),
      voltageMax: read("voltageMax"),
      currentMin: read("currentMin"),
      currentMax: read("currentMax"),
      powerMin: read("powerMin"),
      powerMax: read("powerMax"),
      updatedAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  String summary() {
    final parts = <String>[];
    if (voltageMin != null || voltageMax != null) {
      parts.add(
          "V ${voltageMin?.toStringAsFixed(0) ?? '–'}–${voltageMax?.toStringAsFixed(0) ?? '–'}");
    }
    if (currentMin != null || currentMax != null) {
      parts.add(
          "I ${currentMin?.toStringAsFixed(2) ?? '–'}–${currentMax?.toStringAsFixed(2) ?? '–'} A");
    }
    if (powerMin != null || powerMax != null) {
      parts.add(
          "P ${powerMin?.toStringAsFixed(0) ?? '–'}–${powerMax?.toStringAsFixed(0) ?? '–'} W");
    }
    return parts.isEmpty ? "no thresholds set" : parts.join("; ");
  }
}

class DeviceThresholdService {
  DeviceThresholdService._();

  static CollectionReference<Map<String, dynamic>>? _col() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("device_thresholds");
  }

  static Future<DeviceThreshold?> get(String deviceId) async {
    final col = _col();
    if (col == null) return null;
    try {
      final doc = await col.doc(deviceId).get();
      if (!doc.exists) return null;
      return DeviceThreshold.fromDoc(deviceId, doc.data()!);
    } catch (e) {
      debugPrint("DeviceThresholdService.get failed: $e");
      return null;
    }
  }

  /// Merge-write — only the supplied fields are overwritten.
  static Future<void> set({
    required String deviceId,
    double? voltageMin,
    double? voltageMax,
    double? currentMin,
    double? currentMax,
    double? powerMin,
    double? powerMax,
  }) async {
    final col = _col();
    if (col == null) return;
    final patch = <String, dynamic>{
      "deviceId": deviceId,
      "updatedAt": Timestamp.now(),
    };
    if (voltageMin != null) patch["voltageMin"] = voltageMin;
    if (voltageMax != null) patch["voltageMax"] = voltageMax;
    if (currentMin != null) patch["currentMin"] = currentMin;
    if (currentMax != null) patch["currentMax"] = currentMax;
    if (powerMin != null) patch["powerMin"] = powerMin;
    if (powerMax != null) patch["powerMax"] = powerMax;
    try {
      await col.doc(deviceId).set(patch, SetOptions(merge: true));
    } catch (e) {
      debugPrint("DeviceThresholdService.set failed: $e");
    }
  }

  static Future<List<DeviceThreshold>> all() async {
    final col = _col();
    if (col == null) return const [];
    try {
      final snap = await col.get();
      return snap.docs
          .map((d) => DeviceThreshold.fromDoc(d.id, d.data()))
          .toList();
    } catch (e) {
      debugPrint("DeviceThresholdService.all failed: $e");
      return const [];
    }
  }
}
