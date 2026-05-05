// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'agent_automation_engine.dart';
import 'voice_service.dart';
import 'wake_word_service.dart';

/// =========================================================
/// AGENT MODE SERVICE
/// =========================================================
/// Two operating modes for the smart home:
///
///   • NORMAL  — the user controls everything manually (toggle
///               switches in the Control tab, etc). The agent
///               is dormant; the wake-word loop is off.
///
///   • AI      — the agent owns the home. Manual toggles are
///               disabled, the wake word is auto-armed and the
///               autonomous orchestrator (smoke→fan, motion→
///               bulb, etc.) reacts to sensors.
///
/// The mode is persisted to Firestore at `users/{uid}.agentMode`
/// and exposed as a [ValueListenable] so any widget can react
/// without a full StreamBuilder.
class AgentModeService {
  AgentModeService._();

  static const String _kField = "agentMode";

  /// `true` = AI agent mode, `false` = normal manual mode.
  static final ValueNotifier<bool> isAiMode =
      ValueNotifier<bool>(false);

  static bool _booted = false;

  /// Idempotent. Reads the persisted preference for the current
  /// user and applies it to the runtime services (wake word).
  static Future<void> boot() async {
    if (_booted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .get();
      final stored = snap.data()?[_kField];
      final on = stored == true;
      isAiMode.value = on;
      if (on) {
        // Re-arm the wake word + automation engine on app launch
        // if the user previously chose AI mode.
        await WakeWordService.enable();
        await AgentAutomationEngine.start();
      }
      _booted = true;
    } catch (e) {
      debugPrint("AgentModeService.boot failed: $e");
    }
  }

  /// Switch on AI mode. Auto-arms the wake word and announces.
  /// Returns false if anything failed (eg. mic permission denied).
  static Future<bool> enableAiMode() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final ok = await WakeWordService.enable();
    if (!ok) {
      // The wake-word service already surfaced the reason via
      // its phase notifier — just leave the mode toggled off.
      return false;
    }

    isAiMode.value = true;
    await _persist(uid, true);
    await AgentAutomationEngine.start();
    await VoiceService.speak(
      "AI agent mode activated. I will watch the time, weather and "
      "motion and act for you. Just say, hey shape o s, anytime.",
    );
    return true;
  }

  /// Switch back to manual control. Disarms the wake word + engine.
  static Future<void> disableAiMode() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    isAiMode.value = false;
    await WakeWordService.disable();
    await AgentAutomationEngine.stop();
    if (uid != null) {
      await _persist(uid, false);
    }
    await VoiceService.speak(
      "Switching to manual mode. You are in control.",
    );
  }

  /// Convenience flip used by the AppBar toggle.
  static Future<bool> toggle() async {
    if (isAiMode.value) {
      await disableAiMode();
      return false;
    }
    return enableAiMode();
  }

  static Future<void> _persist(String uid, bool value) async {
    try {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .set({_kField: value}, SetOptions(merge: true));
    } catch (e) {
      debugPrint("AgentModeService persist failed: $e");
    }
  }
}
