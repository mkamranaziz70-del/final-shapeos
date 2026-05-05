import 'package:flutter/foundation.dart';

/// =========================================================
/// LIVE READINGS SERVICE
/// =========================================================
/// Tiny pub-sub the agent uses to ask the UI to surface a
/// real-time-streaming readings card for a specific device.
///
/// When the agent's `show_live_readings(device_id)` tool fires,
/// we just push the device id into [active] and the Agent
/// chat screen renders a `LiveReadingsCard` listening to
/// `/appliances/{id}` in Firebase RTDB until the user dismisses.
class LiveReadingsService {
  LiveReadingsService._();

  /// `null` => nothing being shown. Otherwise the device id.
  static final ValueNotifier<String?> active =
      ValueNotifier<String?>(null);

  static void show(String deviceId) {
    active.value = deviceId;
  }

  static void dismiss() {
    active.value = null;
  }
}
