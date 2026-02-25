// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  static const Color themeBlue = Color(0xFF185B86);
  static const Color darkBg = Color(0xFF0F1E2B);

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  void _showSnackBar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : themeBlue,
      ),
    );
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter password';
    if (value.length < 8) return 'At least 8 characters required';
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Include one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Include one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Include one number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'Include one special character';
    }
    return null;
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
    final userCredential = await AuthService.signUpWithEmail(
  _emailController.text.trim(),
  _passwordController.text.trim(),
);

final user = userCredential.user;

if (user != null) {

  // 🔥 CREATE FIRESTORE USER DOCUMENT
  await FirebaseFirestore.instance
      .collection("users")
      .doc(user.uid)
      .set({
    "email": user.email,
    "firstLoginCompleted": false,
    "createdAt": FieldValue.serverTimestamp(),
  });

  await user.sendEmailVerification();

  _showSnackBar(
    "Verification email sent. Please verify and login.",
    isError: false,
  );

  context.go('/login');
}
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          _showSnackBar("Email already registered");
          break;
        case 'invalid-email':
          _showSnackBar("Invalid email format");
          break;
        case 'weak-password':
          _showSnackBar("Weak password");
          break;
        default:
          _showSnackBar(e.message ?? "Signup failed");
      }
  } catch (e) {
  // ignore: avoid_print
  print("FULL ERROR: $e");
  _showSnackBar("Error: $e");
}

    setState(() => _isLoading = false);
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
                colors: [darkBg, Color(0xFF142E42)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // 🔷 LOGO
                 // 🔷 LOGO (PERFECT CIRCLE FIT)
Container(
  width: 110,
  height: 110,
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    color: themeBlue.withOpacity(0.18),
    boxShadow: [
      BoxShadow(
        color: themeBlue.withOpacity(0.45),
        blurRadius: 30,
        spreadRadius: 4,
      ),
    ],
  ),
  child: Center(
    child: ClipOval(
      child: Image.asset(
        'assets/images/logo.png',
        width: 110,
        height: 110,
        fit: BoxFit.cover, // ✅ fills circle perfectly
      ),
    ),
  ),
),


                    const SizedBox(height: 20),

                    // 🔤 TITLE
                    const Text(
                      "Create Account",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Sign up to get started",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // 🪟 GLASS CARD
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter:
                            ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                _inputField(
                                  controller: _emailController,
                                  label: "Email",
                                  icon: Icons.email_outlined,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return "Enter email";
                                    }
                                    final regex = RegExp(
                                      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                    );
                                    if (!regex.hasMatch(v)) {
                                      return "Invalid email";
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 16),

                                _inputField(
                                  controller: _passwordController,
                                  label: "Password",
                                  icon: Icons.lock_outline,
                                  obscure: _obscurePassword,
                                  validator: _validatePassword,
                                  suffix: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.white70,
                                    ),
                                    onPressed: () => setState(
                                      () => _obscurePassword =
                                          !_obscurePassword,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 16),

                                _inputField(
                                  controller:
                                      _confirmPasswordController,
                                  label: "Confirm Password",
                                  icon: Icons.lock_reset_outlined,
                                  obscure: _obscurePassword,
                                   suffix: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.white70,
                                    ),
                                    onPressed: () => setState(
                                      () => _obscurePassword =
                                          !_obscurePassword,
                                    ),
                                  ),
                                  validator: (v) =>
                                      v != _passwordController.text
                                          ? "Passwords do not match"
                                          : null,
                                ),

                                const SizedBox(height: 22),

                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _handleSignUp,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: themeBlue,
                                      shape:
                                          RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(
                                                16),
                                      ),
                                    ),
                                    child: _isLoading
                                        ? const CircularProgressIndicator(
                                            color: Colors.white,
                                          )
                                        : const Text(
                                            "Sign Up",
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight:
                                                  FontWeight.w600,
                                                  color: Colors.white
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text(
                        "Already have an account? Login",
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= INPUT FIELD =================

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white70),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
