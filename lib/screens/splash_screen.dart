// ignore_for_file: library_private_types_in_public_api, deprecated_member_use, unnecessary_underscores

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Color themeBlue = Color(0xFF185B86);
  static const Color darkBg = Color(0xFF0F1E2B);

  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _scale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    Timer(const Duration(seconds: 3), () {
      if (mounted) context.go('/welcome');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 🌑 BACKGROUND
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  darkBg,
                  Color(0xFF122A3E),
                  Color(0xFF185B86),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // 🌫️ SUBTLE GLASS BLUR
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(color: Colors.transparent),
            ),
          ),

      // 🌟 PERFECTLY FITTED CENTER LOGO (BALANCED SIZE)
Center(
  child: AnimatedBuilder(
    animation: _controller,
    builder: (_, __) {
      return Opacity(
        opacity: _fade.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Container(
            width: 140, // ✅ reduced from 180
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: themeBlue.withOpacity(0.22),
              boxShadow: [
                BoxShadow(
                  color: themeBlue.withOpacity(0.55),
                  blurRadius: 45, // ✅ tighter glow
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 135,  // ✅ perfectly proportioned
                  height: 135,
                  fit: BoxFit.cover, // ❗ no corners ever
                ),
              ),
            ),
          ),
        ),
      );
    },
  ),
),


          // 🔤 APP NAME
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 90),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, __) {
                  return Opacity(
                    opacity: _fade.value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - _fade.value) * 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            "ShapeOS",
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.8,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            "Smart Home Operating System",
                            style: TextStyle(
                              fontSize: 13,
                              letterSpacing: 0.8,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
