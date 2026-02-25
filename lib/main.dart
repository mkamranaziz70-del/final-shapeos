// ignore_for_file: avoid_print, use_build_context_synchronously

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'routes.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();
Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message) async {
  await Firebase.initializeApp();
  print("🔔 Background message: ${message.notification?.title}");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ CREATE DEFAULT APP (NO NAME!)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform.copyWith(
      databaseURL:
          'https://shapeos-smarthome-default-rtdb.firebaseio.com/',
    ),
  );

  // 🔥 Background handler
  FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler);

  // ⚠ Import this
  // import 'package:flutter/foundation.dart';

  if (!kIsWeb) {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidInit);

    await localNotifications.initialize(initSettings);

    const AndroidNotificationChannel channel =
        AndroidNotificationChannel(
      'default_channel_id',
      'Emergency Alerts',
      description: 'Used for emergency notifications.',
      importance: Importance.max,
    );

    await localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 🔐 Permission
  await FirebaseMessaging.instance.requestPermission();

  /// 📱 FCM Token
  String? token = await FirebaseMessaging.instance.getToken();
  print("📱 FCM TOKEN: $token");

  final user = FirebaseAuth.instance.currentUser;

  if (user != null && token != null) {
    await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .set({
      "fcmToken": token,
    }, SetOptions(merge: true));
  }

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {

    final title = message.notification?.title ?? "Alert";
    final body = message.notification?.body ?? "";

    if (!kIsWeb) {
      await localNotifications.show(
        0,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel_id',
            'Emergency Alerts',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
          ),
        ),
      );
    }

    router.push(
      '/emergency',
      extra: message.data["type"] ?? title,
    );
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    router.push(
      '/emergency',
      extra: message.data["type"] ??
          message.notification?.title ??
          "Alert",
    );
  });

  runApp(const ProviderScope(child: ShapeOSApp()));
}

class ShapeOSApp extends StatelessWidget {
  const ShapeOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ShapeOS',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.deepPurple,
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}

////////////////////////////////////////////////////////////
/// 🚨 FULL SCREEN EMERGENCY SCREEN
////////////////////////////////////////////////////////////

class EmergencyScreen extends StatefulWidget {
  final String type;

  const EmergencyScreen({super.key, required this.type});

  @override
  State<EmergencyScreen> createState() =>
      _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {

  final AudioPlayer _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _activateEmergencyMode();
  }

  Future<void> _activateEmergencyMode() async {

    /// 🔴 Immersive full screen
    SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky);

    /// 🔊 Loop siren
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(
      AssetSource("sounds/alert.wav"),
      volume: 1.0,
    );
  }

  Future<void> _dismiss() async {
    await _player.stop();
    SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge);

    router.pop(); // ✅ GoRouter safe pop
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade900,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            const Icon(
              Icons.warning_amber_rounded,
              size: 130,
              color: Colors.white,
            ),

            const SizedBox(height: 40),

            Text(
              "🚨 ${widget.type.toUpperCase()} DETECTED",
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 60),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(
                    horizontal: 40, vertical: 16),
              ),
              onPressed: _dismiss,
              child: const Text(
                "DISMISS",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            )
          ],
        ),
      ),
    );
  }
}