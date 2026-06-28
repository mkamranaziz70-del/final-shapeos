// ignore_for_file: deprecated_member_use

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/room_model.dart';
import '../services/energy_optimization_service.dart';

/// =========================================================
/// ROOM HISTORY SCREEN
/// =========================================================
/// 14-day energy footprint of a single room. Shows:
///   • a hero card with totals + projected monthly savings
///   • a per-day bar chart of the room's kWh
///   • per-device totals + each device's peak-hour share
///   • a recent timeline of the room's day-by-day numbers
///
/// Opened by tapping a room card in [RoomsTab]. The data is
/// pulled fresh from Firestore each time.
class RoomHistoryScreen extends StatefulWidget {
  final RoomModel room;
  const RoomHistoryScreen({super.key, required this.room});

  @override
  State<RoomHistoryScreen> createState() => _RoomHistoryScreenState();
}

class _RoomHistoryScreenState extends State<RoomHistoryScreen> {
  static const Color _blue = Color(0xFF154F73);
  static const Color _green = Color(0xFF24E0A0);
  static const Color _amber = Color(0xFFE0A458);

  Future<_RoomHistoryData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RoomHistoryData> _load() async {
    final fs = FirebaseFirestore.instance;
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 13));
    final daysSnap =
        await fs.collection("energy_daily").get();

    // 1) Aggregate per-day kWh for THIS room only.
    final dailyKWh = <String, double>{};
    final perDeviceTotal = <String, double>{};
    final perDeviceName = <String, String>{};
    final ourDevices = widget.room.deviceIds.toSet();
    int daysScanned = 0;

    for (final doc in daysSnap.docs) {
      final id = doc.id;
      final docDate = DateTime.tryParse(id);
      if (docDate == null) continue;
      if (docDate.isBefore(start) || docDate.isAfter(now)) continue;
      daysScanned++;
      final devices = doc.data()["devices"];
      if (devices is! Map) {
        dailyKWh[id] = 0;
        continue;
      }
      double dayTotal = 0;
      devices.forEach((k, v) {
        if (v is! Map) return;
        if (!ourDevices.contains(k.toString())) return;
        final e = (v["energy"] as num?)?.toDouble() ?? 0;
        dayTotal += e;
        perDeviceTotal.update(k.toString(), (p) => p + e,
            ifAbsent: () => e);
        perDeviceName[k.toString()] =
            (v["name"]?.toString() ?? "Device ${k.toString()}");
      });
      dailyKWh[id] = dayTotal;
    }

    // 2) Pull the room's slice of the latest peak analysis so we
    //    can show "in peak" vs "outside peak" on the same screen.
    final roomReports =
        await EnergyOptimizationService.generateRoomReports();
    final mine = roomReports.firstWhere(
      (r) => r.room.id == widget.room.id,
      orElse: () => RoomEnergyReport(
        room: widget.room,
        devices: const [],
        roomPeakKWh: 0,
        roomTotalKWh: 0,
        peakSharePercent: 0,
        projectedMonthlySavingsPKR: 0,
      ),
    );

    return _RoomHistoryData(
      daysScanned: daysScanned,
      dailyKWh: dailyKWh,
      perDeviceTotal: perDeviceTotal,
      perDeviceName: perDeviceName,
      analysis: mine,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.room.name),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<_RoomHistoryData>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data;
          if (data == null) {
            return const Center(child: Text("Could not load history."));
          }
          final empty = data.daysScanned == 0 ||
              data.dailyKWh.values.every((v) => v == 0);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _hero(data),
              const SizedBox(height: 14),
              if (empty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: _cardDeco(),
                  child: const Text(
                    "No usage recorded for this room in the last 14 days. "
                    "Seed demo data from the Optimization or Anomalies tab.",
                  ),
                )
              else ...[
                _dailyChart(data),
                const SizedBox(height: 14),
                _devicesCard(data),
                const SizedBox(height: 14),
                _peakAnalysisCard(data),
                const SizedBox(height: 14),
                _timelineCard(data),
              ],
            ],
          );
        },
      ),
    );
  }

  // =========================================================
  // HERO
  // =========================================================
  Widget _hero(_RoomHistoryData data) {
    final r = widget.room;
    final total = data.perDeviceTotal.values.fold<double>(0, (s, v) => s + v);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF154F73), Color(0xFF0E2E45)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white.withOpacity(0.18),
                child: Text(
                  _initials(r.occupant.isEmpty ? r.name : r.occupant),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800),
                    ),
                    Text(
                      r.occupant.isEmpty
                          ? "no occupant assigned"
                          : "occupant: ${r.occupant}",
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _stat(
                  label: "TOTAL kWh",
                  value: total.toStringAsFixed(2),
                  caption: "${data.daysScanned} days analyzed",
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _stat(
                  label: "PEAK kWh",
                  value:
                      data.analysis.roomPeakKWh.toStringAsFixed(2),
                  caption:
                      "${data.analysis.peakSharePercent.toStringAsFixed(0)}% of total",
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _stat(
                  label: "SAVE / MONTH",
                  value:
                      "₨ ${data.analysis.projectedMonthlySavingsPKR.toStringAsFixed(0)}",
                  caption: "if peak rules committed",
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required String label,
    required String value,
    required String caption,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 9.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800)),
          Text(caption,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 10)),
        ],
      ),
    );
  }

  // =========================================================
  // DAILY CHART
  // =========================================================
  Widget _dailyChart(_RoomHistoryData data) {
    final entries = data.dailyKWh.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < entries.length; i++) {
      final v = entries[i].value;
      groups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: v,
            color: _green,
            width: 12,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Daily kWh — last 14 days",
            style:
                TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                barGroups: groups,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (v, _) => Text(
                        v.toStringAsFixed(2),
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 9),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= entries.length) {
                          return const SizedBox.shrink();
                        }
                        if (i % 2 != 0 &&
                            i != entries.length - 1) {
                          return const SizedBox.shrink();
                        }
                        final id = entries[i].key;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            id.split("-").last,
                            style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // PER-DEVICE
  // =========================================================
  Widget _devicesCard(_RoomHistoryData data) {
    final entries = data.perDeviceTotal.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Devices in this room",
            style:
                TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 8),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(_iconFor(data.perDeviceName[e.key] ?? ""),
                      color: _blue, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data.perDeviceName[e.key] ?? "Device ${e.key}",
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5),
                    ),
                  ),
                  Text(
                    "${e.value.toStringAsFixed(2)} kWh",
                    style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                "No tracked usage for this room's devices.",
                style: TextStyle(
                    color: Colors.grey.shade700, fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }

  // =========================================================
  // PEAK ANALYSIS
  // =========================================================
  Widget _peakAnalysisCard(_RoomHistoryData data) {
    final usages = data.analysis.devices;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.bolt_rounded, color: _amber, size: 18),
              SizedBox(width: 6),
              Text(
                "Peak-hour share per device",
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Peak hours = ${EnergyOptimizationService.peakStartHour}:00 to "
            "${EnergyOptimizationService.peakEndHour}:00 "
            "(₨ ${EnergyOptimizationService.peakRate.toStringAsFixed(0)}/kWh "
            "vs ₨ ${EnergyOptimizationService.offPeakRate.toStringAsFixed(0)}/kWh).",
            style: TextStyle(
                color: Colors.grey.shade700, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final u in usages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          u.deviceName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        ),
                      ),
                      Text(
                        "${(u.peakShare * 100).toStringAsFixed(0)}%",
                        style: const TextStyle(
                            color: _amber,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: u.peakShare.clamp(0, 1).toDouble(),
                      minHeight: 5,
                      backgroundColor: _amber.withOpacity(0.12),
                      color: _amber,
                    ),
                  ),
                ],
              ),
            ),
          if (usages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                "No peak-hour usage tracked yet.",
                style: TextStyle(
                    color: Colors.grey.shade700, fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }

  // =========================================================
  // TIMELINE
  // =========================================================
  Widget _timelineCard(_RoomHistoryData data) {
    final entries = data.dailyKWh.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Day-by-day",
            style:
                TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 6),
          for (final e in entries.take(14))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _blue.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      e.key.split("-").last,
                      style: const TextStyle(
                          color: _blue,
                          fontWeight: FontWeight.w800,
                          fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _dayLabel(e.key),
                      style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12.5),
                    ),
                  ),
                  Text(
                    "${e.value.toStringAsFixed(2)} kWh",
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // =========================================================
  // HELPERS
  // =========================================================
  BoxDecoration _cardDeco() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      );

  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains("fan")) return Icons.air_rounded;
    if (n.contains("bulb")) return Icons.lightbulb_rounded;
    if (n.contains("pump")) return Icons.water_rounded;
    if (n.contains("bell")) return Icons.notifications_active_rounded;
    return Icons.power_rounded;
  }

  String _initials(String s) {
    if (s.isEmpty) return "?";
    final parts = s.trim().split(RegExp(r"\s+"));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String _dayLabel(String yyyymmdd) {
    final d = DateTime.tryParse(yyyymmdd);
    if (d == null) return yyyymmdd;
    return DateFormat("EEEE, MMM d").format(d);
  }
}

class _RoomHistoryData {
  final int daysScanned;
  final Map<String, double> dailyKWh;
  final Map<String, double> perDeviceTotal;
  final Map<String, String> perDeviceName;
  final RoomEnergyReport analysis;

  const _RoomHistoryData({
    required this.daysScanned,
    required this.dailyKWh,
    required this.perDeviceTotal,
    required this.perDeviceName,
    required this.analysis,
  });
}
