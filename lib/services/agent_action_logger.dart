import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/agent_message.dart';

/// =========================================================
/// AGENT ACTION LOGGER
/// =========================================================
/// Persists every action the agent takes on the home so the
/// agent can answer questions like "why did you turn off the
/// bulb?" by reading recent history back.
///
/// Storage layout:
///   /users/{uid}/agent_actions/{auto-id}
///     deviceId, deviceName, action, reason, trigger,
///     timestamp (ISO), epoch (ms)
class AgentActionLogger {
  AgentActionLogger._();

  static CollectionReference<Map<String, dynamic>>? _col() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("agent_actions");
  }

  /// Record one agent action.
  static Future<void> log({
    required String deviceId,
    required String deviceName,
    required String action,
    required String reason,
    required String trigger,
  }) async {
    final col = _col();
    if (col == null) return;
    try {
      await col.add({
        "deviceId": deviceId,
        "deviceName": deviceName,
        "action": action,
        "reason": reason,
        "trigger": trigger,
        "timestamp": DateTime.now().toIso8601String(),
        "epoch": DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint("AgentActionLogger failed: $e");
    }
  }

  /// Most recent N actions, newest first.
  static Future<List<AgentAction>> recent({int limit = 25}) async {
    final col = _col();
    if (col == null) return [];
    try {
      final snap = await col
          .orderBy("epoch", descending: true)
          .limit(limit)
          .get();
      return snap.docs
          .map((d) => AgentAction.fromMap(d.id, d.data()))
          .toList();
    } catch (e) {
      debugPrint("AgentActionLogger.recent failed: $e");
      return [];
    }
  }

  /// Real-time stream for the agent timeline screen.
  static Stream<List<AgentAction>> stream({int limit = 50}) {
    final col = _col();
    if (col == null) return const Stream.empty();
    return col
        .orderBy("epoch", descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map((d) => AgentAction.fromMap(d.id, d.data()))
            .toList());
  }
}
