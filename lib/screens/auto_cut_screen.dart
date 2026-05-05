// ignore_for_file: deprecated_member_use

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// =========================================================
/// AUTO-CUT MODULE
/// =========================================================
/// The auto-cut module is automatic — it doesn't have a
/// "trigger" the user can press. Instead it lives in
/// [AnomalyDetectionService] and fires whenever a voltage
/// surge or insulation-leakage anomaly is detected. This
/// screen exposes its status: armed indicator + a live
/// timeline of every cut it has performed.
class AutoCutScreen extends StatelessWidget {
  const AutoCutScreen({super.key});

  static const Color _blue = Color(0xFF154F73);
  static const Color _green = Color(0xFF24E0A0);

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("agent_actions")
        .where("trigger",
            whereIn: ["auto_cut_module", "sensor_voltage_surge"])
        .orderBy("epoch", descending: true)
        .limit(50)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Auto-Cut Module"),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _statusCard(),
          const SizedBox(height: 16),
          const Text(
            "Recent auto-cut events",
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = snap.data?.docs ?? const [];
              if (docs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: _cardDeco(),
                  child: Text(
                    "No auto-cut events yet. Trigger one from the Voltage Surge "
                    "or Voltage Leakage module to see it appear here in real time.",
                    style:
                        TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                );
              }
              return Column(
                children: docs.map((d) {
                  final m = d.data();
                  final ts = m["epoch"] is int
                      ? DateTime.fromMillisecondsSinceEpoch(m["epoch"] as int)
                      : DateTime.now();
                  return _eventCard(
                    deviceName: m["deviceName"]?.toString() ?? "Device",
                    reason: m["reason"]?.toString() ?? "",
                    when: ts,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF154F73), Color(0xFF0E2E45)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.25),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _green.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: _green, width: 1.5),
            ),
            child: const Icon(Icons.shield_rounded, color: _green),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "AUTO-CUT MODULE",
                  style: TextStyle(
                    color: Colors.white70,
                    letterSpacing: 1.4,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Armed",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Linked to Voltage Surge and Voltage Leakage detection. "
                  "Will cut power on the next out-of-band event.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventCard({
    required String deviceName,
    required String reason,
    required DateTime when,
  }) {
    final ago = _ago(when);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _cardDeco().copyWith(
        border: Border(left: BorderSide(color: _green, width: 4)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.power_off_rounded, color: _green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "$deviceName cut for safety",
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              Text(
                ago,
                style:
                    TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reason,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return "just now";
    if (d.inMinutes < 60) return "${d.inMinutes}m ago";
    if (d.inHours < 24) return "${d.inHours}h ago";
    if (d.inDays < 7) return "${d.inDays}d ago";
    return DateFormat("MMM d").format(dt);
  }

  static BoxDecoration _cardDeco() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      );
}
