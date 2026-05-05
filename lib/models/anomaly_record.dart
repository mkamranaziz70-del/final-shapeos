import 'package:cloud_firestore/cloud_firestore.dart';

/// =========================================================
/// ANOMALY RECORD
/// =========================================================
/// Persisted version of [AnomalyEvent] — what the Anomalies
/// tab streams from Firestore.
class AnomalyRecord {
  final String id;
  final String deviceId;
  final String deviceName;
  final String deviceType;
  final String severity;
  final String title;
  final String detail;
  final Map<String, double> metrics;
  final String trigger;
  final DateTime detectedAt;
  final DateTime? resolvedAt;

  const AnomalyRecord({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.severity,
    required this.title,
    required this.detail,
    required this.metrics,
    required this.trigger,
    required this.detectedAt,
    this.resolvedAt,
  });

  bool get isResolved => resolvedAt != null;

  Map<String, dynamic> toMap() => {
        "deviceId": deviceId,
        "deviceName": deviceName,
        "deviceType": deviceType,
        "severity": severity,
        "title": title,
        "detail": detail,
        "metrics": metrics,
        "trigger": trigger,
        "detectedAt": Timestamp.fromDate(detectedAt),
        "resolvedAt":
            resolvedAt == null ? null : Timestamp.fromDate(resolvedAt!),
        "epoch": detectedAt.millisecondsSinceEpoch,
      };

  factory AnomalyRecord.fromDoc(
      String id, Map<String, dynamic> d) {
    final detected = d["detectedAt"];
    final resolved = d["resolvedAt"];
    return AnomalyRecord(
      id: id,
      deviceId: d["deviceId"]?.toString() ?? "",
      deviceName: d["deviceName"]?.toString() ?? "",
      deviceType: d["deviceType"]?.toString() ?? "",
      severity: d["severity"]?.toString() ?? "info",
      title: d["title"]?.toString() ?? "",
      detail: d["detail"]?.toString() ?? "",
      metrics: (d["metrics"] is Map)
          ? (d["metrics"] as Map).map(
              (k, v) =>
                  MapEntry(k.toString(), (v is num) ? v.toDouble() : 0.0))
          : <String, double>{},
      trigger: d["trigger"]?.toString() ?? "",
      detectedAt: detected is Timestamp
          ? detected.toDate()
          : DateTime.tryParse(detected?.toString() ?? "") ??
              DateTime.now(),
      resolvedAt: resolved is Timestamp
          ? resolved.toDate()
          : (resolved == null
              ? null
              : DateTime.tryParse(resolved.toString())),
    );
  }
}
