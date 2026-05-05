// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// =========================================================
/// AGENT MEMORY
/// =========================================================
/// Long-term knowledge the user has handed to the agent. Lives
/// at `users/{uid}/agent_memory/{auto-id}`. Each entry is just
/// `{ key, value, updatedAt, epoch }`.
///
/// The agent reads the most recent ~30 memories into its system
/// prompt every turn so it can use them when answering. New
/// memories are added via the `remember` tool.
class AgentMemoryEntry {
  final String id;
  final String key;
  final String value;
  final DateTime updatedAt;

  const AgentMemoryEntry({
    required this.id,
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        "key": key,
        "value": value,
        "updatedAt": Timestamp.fromDate(updatedAt),
        "epoch": updatedAt.millisecondsSinceEpoch,
      };

  factory AgentMemoryEntry.fromDoc(String id, Map<String, dynamic> d) {
    final updated = d["updatedAt"];
    return AgentMemoryEntry(
      id: id,
      key: d["key"]?.toString() ?? "",
      value: d["value"]?.toString() ?? "",
      updatedAt: updated is Timestamp
          ? updated.toDate()
          : DateTime.tryParse(updated?.toString() ?? "") ??
              DateTime.now(),
    );
  }
}

class AgentMemoryService {
  AgentMemoryService._();

  static CollectionReference<Map<String, dynamic>>? _col() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("agent_memory");
  }

  /// Store a new fact. If a memory with the same key already
  /// exists, the value is overwritten and timestamp refreshed.
  static Future<void> remember(String key, String value) async {
    final col = _col();
    if (col == null) return;
    final cleaned = key.trim().toLowerCase();
    if (cleaned.isEmpty) return;
    final now = DateTime.now();
    try {
      final existing = await col
          .where("key", isEqualTo: cleaned)
          .limit(1)
          .get();
      final payload = {
        "key": cleaned,
        "value": value.trim(),
        "updatedAt": Timestamp.fromDate(now),
        "epoch": now.millisecondsSinceEpoch,
      };
      if (existing.docs.isEmpty) {
        await col.add(payload);
      } else {
        await existing.docs.first.reference.update(payload);
      }
    } catch (e) {
      debugPrint("AgentMemoryService.remember failed: $e");
    }
  }

  /// Forget a memory by key (tolerant of case/whitespace).
  static Future<bool> forget(String key) async {
    final col = _col();
    if (col == null) return false;
    final cleaned = key.trim().toLowerCase();
    try {
      final hit = await col.where("key", isEqualTo: cleaned).get();
      if (hit.docs.isEmpty) return false;
      for (final d in hit.docs) {
        await d.reference.delete();
      }
      return true;
    } catch (e) {
      debugPrint("AgentMemoryService.forget failed: $e");
      return false;
    }
  }

  /// Recall the most recent N memories, newest first.
  static Future<List<AgentMemoryEntry>> recent({int limit = 30}) async {
    final col = _col();
    if (col == null) return const [];
    try {
      final snap = await col
          .orderBy("epoch", descending: true)
          .limit(limit)
          .get();
      return snap.docs
          .map((d) => AgentMemoryEntry.fromDoc(d.id, d.data()))
          .toList();
    } catch (e) {
      debugPrint("AgentMemoryService.recent failed: $e");
      return const [];
    }
  }

  /// Live stream — used by an upcoming "memory" tab if needed.
  static Stream<List<AgentMemoryEntry>> stream({int limit = 100}) {
    final col = _col();
    if (col == null) return const Stream.empty();
    return col
        .orderBy("epoch", descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map((d) => AgentMemoryEntry.fromDoc(d.id, d.data()))
            .toList());
  }
}
