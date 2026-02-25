import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  initialLocation: '/',

  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;

    final location = state.matchedLocation;

    final goingToLogin = location == '/login';
    final goingToSignup = location == '/signup';
    final goingToWelcome = location == '/welcome';
    final goingToSplash = location == '/';

    // 🚫 If not logged in
    if (user == null) {
      if (goingToLogin || goingToSignup || goingToWelcome || goingToSplash) {
        return null;
      }
      return '/login';
    }

    // ✅ If logged in
    if (goingToLogin || goingToSignup || goingToWelcome) {
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
