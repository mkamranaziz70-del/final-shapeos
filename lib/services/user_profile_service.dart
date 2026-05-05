import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';

/// =========================================================
/// USER PROFILE SERVICE
/// =========================================================
/// Stores the rich profile collected by [ProfileSetupScreen]
/// at /users/{uid}/profile/main.  Exposes a [ValueListenable]
/// of the cached profile so the agent and UI can react.
class UserProfileService {
  UserProfileService._();

  static final ValueNotifier<UserProfile?> current =
      ValueNotifier<UserProfile?>(null);

  static DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .collection("profile")
          .doc("main");

  /// Persist or update the profile.
  static Future<void> save(UserProfile p) async {
    await _ref(p.uid).set(p.toMap(), SetOptions(merge: true));
    // Mirror "agentProfileCompleted" flag on the user doc so the
    // splash flow knows whether to show the setup wizard.
    await FirebaseFirestore.instance
        .collection("users")
        .doc(p.uid)
        .set({
      "agentProfileCompleted": true,
      "fullName": p.fullName,
      "room": p.room,
    }, SetOptions(merge: true));
    current.value = p;
  }

  /// Load profile for the current user (if any).
  static Future<UserProfile?> load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final snap = await _ref(uid).get();
      if (!snap.exists) return null;
      final p = UserProfile.fromMap({...snap.data()!, "uid": uid});
      current.value = p;
      return p;
    } catch (e) {
      debugPrint("UserProfileService.load failed: $e");
      return null;
    }
  }

  /// Real-time stream so multiple devices stay in sync.
  static Stream<UserProfile?> stream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _ref(uid).snapshots().map((s) {
      if (!s.exists) return null;
      final p = UserProfile.fromMap({...s.data()!, "uid": uid});
      current.value = p;
      return p;
    });
  }

  /// Quick check used by the dashboard to decide whether to
  /// open the agent profile wizard.
  static Future<bool> isProfileComplete() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    try {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .get();
      return (doc.data()?["agentProfileCompleted"] ?? false) == true;
    } catch (_) {
      return false;
    }
  }
}
