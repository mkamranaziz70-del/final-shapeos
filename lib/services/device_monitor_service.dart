// ignore_for_file: avoid_print

/// =========================================================
/// ⏱️ DEVICE MONITOR SERVICE
/// Tracks device uptime and enforces user-defined limits
/// =========================================================
///
/// FLOW:
/// Device ON
/// → reaches maxMinutes
/// → soft warning
/// → wait 2 minutes
/// → final warning
/// → wait 2 minutes
/// → auto OFF
///
class DeviceMonitorService {
  /// ===============================
  /// 🔹 INTERNAL STATE
  /// ===============================

  /// Device ON timestamp
  static final Map<String, DateTime> _onSince = {};

  /// User-defined max uptime (minutes)
  static final Map<String, int> _maxMinutes = {};

  /// Warning stage per device
  /// 0 = none
  /// 1 = first warning
  /// 2 = final warning
  /// 3 = auto-off executed
  static final Map<String, int> _warningStage = {};

  /// ===============================
  /// 🔹 CONFIGURATION API
  /// ===============================

  /// Register or update monitoring rule
  static void registerDevice({
    required String deviceId,
    required int maxMinutes,
  }) {
    _maxMinutes[deviceId] = maxMinutes;
    _warningStage[deviceId] = 0;
  }

  /// Remove monitoring rule
  static void unregisterDevice(String deviceId) {
    _maxMinutes.remove(deviceId);
    _warningStage.remove(deviceId);
    _onSince.remove(deviceId);
  }

  /// ===============================
  /// 🔹 DEVICE STATE EVENTS
  /// ===============================

  /// Call when device turns ON
  static void deviceTurnedOn(String deviceId) {
    _onSince[deviceId] = DateTime.now();
    _warningStage[deviceId] = 0;
  }

  /// Call when device turns OFF
  static void deviceTurnedOff(String deviceId) {
    _onSince.remove(deviceId);
    _warningStage.remove(deviceId);
  }

  /// ===============================
  /// 🔹 CORE LOGIC
  /// ===============================

  /// Check device status and return monitoring result
  static DeviceMonitorResult check(String deviceId) {
    if (!_onSince.containsKey(deviceId)) {
      return DeviceMonitorResult.none();
    }

    final maxAllowed = _maxMinutes[deviceId];
    if (maxAllowed == null || maxAllowed <= 0) {
      return DeviceMonitorResult.none();
    }

    final minutesOn = DateTime.now()
        .difference(_onSince[deviceId]!)
        .inMinutes;

    final stage = _warningStage[deviceId] ?? 0;

    /// 🟡 FIRST WARNING
    if (minutesOn >= maxAllowed && stage == 0) {
      _warningStage[deviceId] = 1;

      return DeviceMonitorResult.warning(
        message:
            "Device has reached maximum allowed time ($maxAllowed min). Do you want to turn it off?",
        waitMinutes: 2,
        autoOff: false,
      );
    }

    /// 🟠 FINAL WARNING
    if (minutesOn >= maxAllowed + 2 && stage == 1) {
      _warningStage[deviceId] = 2;

      return DeviceMonitorResult.warning(
        message:
            "Device is still running. It will be turned off automatically if no response.",
        waitMinutes: 2,
        autoOff: false,
      );
    }

    /// 🔴 AUTO SHUTDOWN
    if (minutesOn >= maxAllowed + 4 && stage == 2) {
      _warningStage[deviceId] = 3;

      return DeviceMonitorResult.critical(
        message:
            "Maximum safe usage exceeded. Turning device OFF automatically.",
        autoOff: true,
      );
    }

    return DeviceMonitorResult.none();
  }

  /// ===============================
  /// 🔹 HELPER
  /// ===============================

  /// Get live uptime (minutes)
  static int currentUptime(String deviceId) {
    if (!_onSince.containsKey(deviceId)) return 0;
    return DateTime.now()
        .difference(_onSince[deviceId]!)
        .inMinutes;
  }
}

/// =========================================================
/// 🔹 DEVICE MONITOR RESULT MODEL
/// =========================================================

class DeviceMonitorResult {
  final bool hasAlert;
  final bool autoOff;
  final String message;
  final int waitMinutes;

  const DeviceMonitorResult({
    required this.hasAlert,
    required this.autoOff,
    required this.message,
    required this.waitMinutes,
  });

  factory DeviceMonitorResult.none() {
    return const DeviceMonitorResult(
      hasAlert: false,
      autoOff: false,
      message: "",
      waitMinutes: 0,
    );
  }

  factory DeviceMonitorResult.warning({
    required String message,
    required int waitMinutes,
    required bool autoOff,
  }) {
    return DeviceMonitorResult(
      hasAlert: true,
      autoOff: autoOff,
      message: message,
      waitMinutes: waitMinutes,
    );
  }

  factory DeviceMonitorResult.critical({
    required String message,
    required bool autoOff,
  }) {
    return DeviceMonitorResult(
      hasAlert: true,
      autoOff: autoOff,
      message: message,
      waitMinutes: 0,
    );
  }
}
