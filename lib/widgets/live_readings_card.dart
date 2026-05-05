// ignore_for_file: deprecated_member_use

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../services/live_readings_service.dart';

/// =========================================================
/// LIVE READINGS CARD
/// =========================================================
/// Floating card that streams `/appliances/{id}` from Firebase
/// RTDB and renders V / I / P / E with a pulsing LIVE dot. Meant
/// to be stacked on top of the Agent chat screen.
class LiveReadingsCard extends StatefulWidget {
  final String deviceId;
  const LiveReadingsCard({super.key, required this.deviceId});

  @override
  State<LiveReadingsCard> createState() => _LiveReadingsCardState();
}

class _LiveReadingsCardState extends State<LiveReadingsCard>
    with SingleTickerProviderStateMixin {
  static const _blue = Color(0xFF154F73);
  static const _green = Color(0xFF24E0A0);

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  static String _nameFor(String id) {
    switch (id) {
      case "1":
        return "Fan";
      case "2":
        return "Bulb";
      case "3":
        return "Pump";
      case "4":
        return "Bell";
      default:
        return "Device $id";
    }
  }

  static double _toD(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance
            .ref("appliances/${widget.deviceId}")
            .onValue,
        builder: (ctx, snap) {
          final m = (snap.data?.snapshot.value as Map?) ?? const {};
          final isOn = m["isOn"] == true;
          final v = _toD(m["voltage"]);
          final i = _toD(m["current"]);
          final p = _toD(m["power"]);
          final e = _toD(m["energy"]);

          return Container(
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0E2E45), Color(0xFF154F73)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _blue.withOpacity(0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (ctx, _) => Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: isOn
                              ? _green.withOpacity(
                                  0.5 + 0.5 * _pulse.value)
                              : Colors.grey,
                          shape: BoxShape.circle,
                          boxShadow: isOn
                              ? [
                                  BoxShadow(
                                    color: _green
                                        .withOpacity(0.6 * _pulse.value),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "LIVE",
                      style: TextStyle(
                        color: isOn ? _green : Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "${_nameFor(widget.deviceId)} · readings",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      tooltip: "Close",
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70),
                      onPressed: LiveReadingsService.dismiss,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isOn ? "Powered ON" : "Powered OFF — readings will be 0",
                  style: TextStyle(
                    color: isOn ? _green : Colors.white54,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                // Big readings grid
                Row(
                  children: [
                    Expanded(
                      child: _Tile(
                        label: "VOLTAGE",
                        value: v.toStringAsFixed(1),
                        unit: "V",
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Tile(
                        label: "CURRENT",
                        value: i.toStringAsFixed(2),
                        unit: "A",
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _Tile(
                        label: "POWER",
                        value: p.toStringAsFixed(1),
                        unit: "W",
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Tile(
                        label: "ENERGY",
                        value: e.toStringAsFixed(4),
                        unit: "kWh",
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _Tile({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Container(
        key: ValueKey(value),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
