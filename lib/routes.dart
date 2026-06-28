import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'models/device_model.dart';
import 'screens/dashboard_screen.dart';
import 'screens/device_detail_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'main.dart';
final _rootNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/dashboard',

  // Single-admin mode — no auth screens. main.dart silently
  // signs in anonymously so FirebaseAuth.currentUser is always
  // populated by the time routes are evaluated. We deliberately
  // route any legacy login/signup/welcome path back to the
  // dashboard so older deep links don't show empty pages.
  redirect: (context, state) {
    final loc = state.matchedLocation;
    if (loc == '/' ||
        loc == '/login' ||
        loc == '/signup' ||
        loc == '/welcome' ||
        loc == '/forgot-password') {
      return '/dashboard';
    }
    return null;
  },

  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),

    GoRoute(
      path: '/welcome',
      builder: (context, state) => const WelcomeScreen(),
    ),

    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),

    GoRoute(
      path: '/signup',
      builder: (context, state) => const SignUpScreen(),
    ),

    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),

    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
      routes: [
        GoRoute(
          path: 'device-detail',
          builder: (context, state) {
            final extra = state.extra;
            if (extra is DeviceModel) {
              return DeviceDetailScreen(device: extra);
            } else {
              return Scaffold(
                appBar: AppBar(title: const Text("Error")),
                body: const Center(
                  child: Text(
                    "Device data not found",
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              );
            }
          },
        ),
      ],
    ),
    GoRoute(
  path: '/emergency',
  builder: (context, state) {
    final type = state.extra as String? ?? "Alert";
    return EmergencyScreen(type: type);
  },
),
  ],
);
