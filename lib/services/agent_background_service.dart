// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// =========================================================
/// AGENT BACKGROUND SERVICE
/// =========================================================
/// Promotes the app to a foreground service so the OS does not
/// kill the wake-word loop when the user navigates away from
/// the app. Shows a sticky notification ("SHAPEOS is listening").
///
/// IMPORTANT — two implementation gotchas this file addresses:
///
///   1. The background isolate entry point MUST be a top-level
///      function annotated with `@pragma('vm:entry-point')`,
///      otherwise the AOT compiler strips it and the native
///      side fails with "must be annotated".
///
///   2. On Android 13+, posting a foreground-service notification
///      requires the notification channel to already exist with
///      at least IMPORTANCE_LOW. Some OEMs (Realme, Xiaomi…) do
///      not auto-create it from the plugin config, so we create
///      it explicitly via flutter_local_notifications.
class AgentBackgroundService {
  AgentBackgroundService._();

  static const String _channelId = "shapeos_agent_listening";
  static const String _channelName = "SHAPEOS Agent";
  static const String _channelDesc =
      "SHAPEOS keeps listening for the wake word in the background.";
  static const int _notificationId = 7421;

  static bool _configured = false;

  /// Configure once at app startup. Idempotent.
  static Future<void> configure() async {
    if (_configured) return;
    if (kIsWeb) return;

    // 1) Create the notification channel BEFORE the service tries
    //    to post a foreground notification on it.
    try {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.low,
        showBadge: false,
      );
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    } catch (e) {
      debugPrint("AgentBackgroundService channel create failed: $e");
    }

    // 2) Wire up the background service.
    final service = FlutterBackgroundService();
    try {
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: agentBackgroundOnStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: _channelId,
          initialNotificationTitle: "SHAPEOS Agent",
          initialNotificationContent: "Listening for the wake word…",
          foregroundServiceNotificationId: _notificationId,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: agentBackgroundOnStart,
        ),
      );
    } catch (e) {
      debugPrint("AgentBackgroundService configure failed: $e");
      return;
    }

    _configured = true;
  }

  /// Start the foreground service. Soft-fails — if the device
  /// rejects the notification or the plugin is unavailable, the
  /// wake word still works while the app is foregrounded.
  static Future<void> start() async {
    if (kIsWeb) return;
    try {
      await configure();
      final service = FlutterBackgroundService();
      final running = await service.isRunning();
      if (!running) {
        await service.startService();
      }
    } catch (e) {
      debugPrint("AgentBackgroundService.start failed: $e");
    }
  }

  /// Stop the foreground service. Soft-fails.
  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      final service = FlutterBackgroundService();
      final running = await service.isRunning();
      if (running) {
        service.invoke("stop");
      }
    } catch (e) {
      debugPrint("AgentBackgroundService.stop failed: $e");
    }
  }
}

/// Top-level background isolate entry point.
///
/// MUST live at the file scope and carry the `vm:entry-point`
/// pragma so the AOT compiler keeps it. The actual wake-word
/// listener runs in the *main* isolate; this isolate just keeps
/// the foreground notification alive so the OS does not kill
/// the process.
@pragma('vm:entry-point')
void agentBackgroundOnStart(ServiceInstance service) {
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }

  service.on("stop").listen((_) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(minutes: 5), (_) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "SHAPEOS Agent",
        content: "Listening for the wake word…",
      );
    }
  });
}
