// ignore_for_file: avoid_print

import '../models/device_model.dart';

/// =========================================================
/// 🤖 AI ANOMALY SERVICE
/// Rule-based AI for device usage monitoring & energy anomalies
/// =========================================================
///
/// FEATURES:
/// - Tracks device ON duration
/// - Detects uptime threshold violations
/// - Generates human-readable anomaly messages
/// - Supports staged warnings (2 min → 5 min → auto-off)
/// - Designed for IoT + FYP + Industry demo
///
class AIAnomalyService {
  /// ===============================
  /// 🔹 INTERNAL STATE (IN-MEMORY)
  /// ===============================

  /// When device was turned ON
  static final Map<String, DateTime> _deviceOnSince = {};

  /// User-defined max allowed uptime (in minutes)
  static final Map<String, int> _deviceMaxMinutes = {};

  /// Track last warning stage sent
  /// 0 = none, 1 = first warning, 2 = final warning
  static final Map<String, int> _warningStage = {};

  /// ===============================
  /// 🔹 PUBLIC CONFIGURATION API
  /// ===============================

  /// Register / update monitoring rule for a device
  /// Example: Fan → 2 minutes
  static void registerDeviceRule({
    required String deviceId,
    required int maxMinutes,
  }) {
    _deviceMaxMinutes[deviceId] = maxMinutes;
    _warningStage[deviceId] = 0;
  }

  /// Call this when device is turned ON
  static void onDeviceTurnedOn(String deviceId) {
    _deviceOnSince[deviceId] = DateTime.now();
    _warningStage[deviceId] = 0;
  }

  /// Call this when device is turned OFF
  static void onDeviceTurnedOff(String deviceId) {
    _deviceOnSince.remove(deviceId);
    _warningStage.remove(deviceId);
  }

  /// ===============================
  /// 🔹 CORE AI ANALYSIS FUNCTION
  /// ===============================

  /// Analyze device state and return anomaly result
  static AIAnomalyResult analyze(DeviceModel device) {
    final id = device.id;

    // Device OFF → no anomaly
    if (!device.isOn) {
      onDeviceTurnedOff(id);
      return AIAnomalyResult.none();
    }

    // Device ON but no tracking yet
    if (!_deviceOnSince.containsKey(id)) {
      onDeviceTurnedOn(id);
      return AIAnomalyResult.none();
    }

    final maxMinutes = _deviceMaxMinutes[id] ?? 0;
    if (maxMinutes == 0) return AIAnomalyResult.none();

    final minutesOn = DateTime.now()
        .difference(_deviceOnSince[id]!)
        .inMinutes;

    final stage = _warningStage[id] ?? 0;

    /// ===============================
    /// 🟡 STAGE 1 — SOFT WARNING
    /// ===============================
    if (minutesOn >= maxMinutes && stage == 0) {
      _warningStage[id] = 1;

      return AIAnomalyResult.warning(
        message:
            "${device.name} has been ON for $minutesOn minutes. Would you like to turn it off?",
        deviceId: id,
        autoOff: false,
      );
    }

    /// ===============================
    /// 🟠 STAGE 2 — FINAL WARNING
    /// ===============================
    if (minutesOn >= maxMinutes + 2 && stage == 1) {
      _warningStage[id] = 2;

      return AIAnomalyResult.warning(
        message:
            "${device.name} is still ON after extended usage. It will be turned off automatically.",
        deviceId: id,
        autoOff: false,
      );
    }

    /// ===============================
    /// 🔴 STAGE 3 — AUTO SHUTDOWN
    /// ===============================
    if (minutesOn >= maxMinutes + 4 && stage == 2) {
      _warningStage[id] = 3;

      return AIAnomalyResult.critical(
        message:
            "${device.name} exceeded safe usage time. Turning it OFF to save energy.",
        deviceId: id,
        autoOff: true,
      );
    }

    return AIAnomalyResult.none();
  }
}

/// =========================================================
/// 🔹 AI ANOMALY RESULT MODEL
/// =========================================================

class AIAnomalyResult {
  final bool hasIssue;
  final bool autoOff;
  final String message;
  final String? deviceId;

  const AIAnomalyResult({
    required this.hasIssue,
    required this.autoOff,
    required this.message,
    this.deviceId,
  });

  factory AIAnomalyResult.none() {
    return const AIAnomalyResult(
      hasIssue: false,
      autoOff: false,
      message: "",
    );
  }

  factory AIAnomalyResult.warning({
    required String message,
    required String deviceId,
    required bool autoOff,
  }) {
    return AIAnomalyResult(
      hasIssue: true,
      autoOff: autoOff,
      message: message,
      deviceId: deviceId,
    );
  }

  factory AIAnomalyResult.critical({
    required String message,
    required String deviceId,
    required bool autoOff,
  }) {
    return AIAnomalyResult(
      hasIssue: true,
      autoOff: autoOff,
      message: message,
      deviceId: deviceId,
    );
  }
}
