import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Email & Password Sign-In
  static Future<UserCredential> signInWithEmail(
    String email,
    String password,
  ) async {
    // Exceptions ko throw kare login screen par handle karne ke liye
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Email & Password Sign-Up
  static Future<UserCredential> signUpWithEmail(
    String email,
    String password,
  ) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Google Sign-In
  static Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      GoogleAuthProvider googleProvider = GoogleAuthProvider();
      return await _auth.signInWithPopup(googleProvider);
    } else {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    }
  }

  /// Sign-Out
  static Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb) await GoogleSignIn().signOut();
  }

  /// Get Current User
  static User? getCurrentUser() {
    return _auth.currentUser;
  }
}
