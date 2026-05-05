// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/bill_splitting_service.dart';
import '../services/demo_seeder_service.dart';

/// =========================================================
/// BILLS TAB
/// =========================================================
/// Bill split for any date range, filtered down to members who
/// actually used devices in that window. Default range is
/// month-to-date (1st of current month → today).
class BillsTab extends StatefulWidget {
  const BillsTab({super.key});

  @override
  State<BillsTab> createState() => _BillsTabState();
}

enum _RangePreset { week, monthToDate, lastMonth, custom }

class _BillsTabState extends State<BillsTab> {
  static const Color _blue = Color(0xFF154F73);
  static const List<Color> _palette = [
    Color(0xFF1F8AC0),
    Color(0xFFE07A5F),
    Color(0xFF81B29A),
    Color(0xFFF2CC8F),
    Color(0xFF6A4C93),
    Color(0xFF3D5A80),
  ];

  Future<BillBreakdown>? _future;
  _RangePreset _preset = _RangePreset.monthToDate;
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _seeding = false;

  @override
  void initState() {
    super.initState();
    _future = _loadForCurrentPreset();
  }

  // =========================================================
  // RANGE RESOLUTION
  // =========================================================
  ({DateTime start, DateTime end}) _resolveRange() {
    final now = DateTime.now();
    switch (_preset) {
      case _RangePreset.week:
        return (
          start: now.subtract(const Duration(days: 6)),
          end: now,
        );
      case _RangePreset.monthToDate:
        return (start: DateTime(now.year, now.month, 1), end: now);
      case _RangePreset.lastMonth:
        final firstOfThis = DateTime(now.year, now.month, 1);
        final lastOfPrev =
            firstOfThis.subtract(const Duration(days: 1));
        return (
          start: DateTime(lastOfPrev.year, lastOfPrev.month, 1),
          end: lastOfPrev,
        );
      case _RangePreset.custom:
        return (
          start: _customStart ?? DateTime(now.year, now.month, 1),
          end: _customEnd ?? now,
        );
    }
  }

  Future<BillBreakdown> _loadForCurrentPreset() {
    final r = _resolveRange();
    return BillSplittingService.compute(
      startDate: r.start,
      endDate: r.end,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadForCurrentPreset();
    });
    await _future;
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initialStart = _customStart ?? DateTime(now.year, now.month, 1);
    final initialEnd = _customEnd ?? now;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year, now.month + 1, 0),
      initialDateRange: DateTimeRange(
        start: initialStart,
        end: initialEnd,
      ),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _blue,
            onPrimary: Colors.white,
            onSurface: Color(0xFF0E2E45),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _preset = _RangePreset.custom;
      _customStart = picked.start;
      _customEnd = picked.end;
      _future = _loadForCurrentPreset();
    });
  }

  Future<void> _seed() async {
    setState(() => _seeding = true);
    try {
      final r = await DemoSeederService.seedAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.summarise())),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Seed failed: $e")));
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  // =========================================================
  // BUILD
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<BillBreakdown>(
        future: _future,
        builder: (ctx, snap) {
          final loading = snap.connectionState == ConnectionState.waiting;
          final b = snap.data;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              _filterRow(),
              const SizedBox(height: 12),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (b == null ||
                  b.shares.isEmpty ||
                  b.totalKWh <= 0)
                _emptyForRange()
              else ...[
                _heroCard(b),
                const SizedBox(height: 16),
                _splitChart(b),
                const SizedBox(height: 16),
                _shareList(b),
                const SizedBox(height: 16),
                _trendCard(),
                const SizedBox(height: 16),
                _tariffCard(b),
              ],
            ],
          );
        },
      ),
    );
  }

  // =========================================================
  // FILTER ROW
  // =========================================================
  Widget _filterRow() {
    Widget chip(_RangePreset preset, String label, IconData icon) {
      final on = _preset == preset;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: on ? Colors.white : _blue),
              const SizedBox(width: 4),
              Text(label),
            ],
          ),
          selected: on,
          backgroundColor: _blue.withOpacity(0.08),
          selectedColor: _blue,
          labelStyle: TextStyle(
            color: on ? Colors.white : _blue,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: _blue.withOpacity(0.25)),
          ),
          onSelected: (_) {
            if (preset == _RangePreset.custom) {
              _pickCustomRange();
              return;
            }
            setState(() {
              _preset = preset;
              _future = _loadForCurrentPreset();
            });
          },
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(_RangePreset.week, "Last 7 days",
              Icons.calendar_view_week_rounded),
          chip(_RangePreset.monthToDate, "Month to date",
              Icons.calendar_today_rounded),
          chip(_RangePreset.lastMonth, "Last month",
              Icons.history_rounded),
          chip(_RangePreset.custom, "Custom range",
              Icons.date_range_rounded),
        ],
      ),
    );
  }

  // =========================================================
  // EMPTY STATES
  // =========================================================
  Widget _emptyForRange() {
    final r = _resolveRange();
    final label = _formatRange(r.start, r.end);
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: _cardDeco(),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_rounded,
              size: 56, color: _blue),
          const SizedBox(height: 10),
          const Text(
            "No usage in this window",
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: _blue),
          ),
          const SizedBox(height: 4),
          Text(
            "Nobody used a device between $label.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _blue,
                  side: BorderSide(color: _blue.withOpacity(0.5)),
                ),
                onPressed: () => setState(() {
                  _preset = _RangePreset.monthToDate;
                  _future = _loadForCurrentPreset();
                }),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text("Reset to this month"),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: _seeding ? null : _seed,
                icon: _seeding
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.science_rounded, size: 16),
                label: Text(_seeding ? "Seeding…" : "Seed demo data"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================
  // HERO
  // =========================================================
  Widget _heroCard(BillBreakdown b) {
    final daysInRange =
        b.endDate.difference(b.startDate).inDays + 1;
    final perDay =
        daysInRange > 0 ? b.totalRupees / daysInRange : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF154F73), Color(0xFF0E2E45)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.25),
            blurRadius: 22,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            b.label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              letterSpacing: 1.2,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "₨ ${_money(b.totalRupees)}",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                        height: 1),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  "in this range",
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "${b.totalKWh.toStringAsFixed(2)} kWh used across "
            "${b.shares.length} active member${b.shares.length == 1 ? '' : 's'}.",
            style: TextStyle(
                color: Colors.white.withOpacity(0.85), fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  label: "Days in range",
                  value: "$daysInRange",
                  caption: "with usage on ${b.totalActiveDays}",
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  label: "Per-day average",
                  value: "₨ ${_money(perDay)}",
                  caption: "across the household",
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required String label,
    required String value,
    required String caption,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10.5,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          Text(caption,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 10.5,
                  height: 1.25)),
        ],
      ),
    );
  }

  // =========================================================
  // PER-USER SPLIT BAR CHART
  // =========================================================
  Widget _splitChart(BillBreakdown b) {
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < b.shares.length; i++) {
      final s = b.shares[i];
      final color = _palette[i % _palette.length];
      groups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: s.rupees,
            color: color,
            width: 22,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      ));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Bill split",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            "Members who used a device in this range, sorted by consumption.",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 200,
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
                      reservedSize: 38,
                      getTitlesWidget: (v, _) => Text(
                        "₨${v.toInt()}",
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= b.shares.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _firstName(b.shares[i].name),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => _blue,
                    getTooltipItem: (group, idx, rod, rodIdx) {
                      final s = b.shares[group.x];
                      return BarTooltipItem(
                        "${s.name}\n₨ ${_money(rod.toY)}",
                        const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700),
                      );
                    },
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
  // PER-USER SHARES LIST
  // =========================================================
  Widget _shareList(BillBreakdown b) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Active members",
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              Text(
                "${b.shares.length} of ${b.shares.length}",
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < b.shares.length; i++)
            _memberRow(
              s: b.shares[i],
              color: _palette[i % _palette.length],
              isTop: i == 0,
            ),
        ],
      ),
    );
  }

  Widget _memberRow({
    required UserBillShare s,
    required Color color,
    required bool isTop,
  }) {
    final pct = (s.percent.isFinite ? s.percent : 0).clamp(0, 100).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color,
            child: Text(
              _initials(s.name),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.name.isEmpty ? "User" : s.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    if (isTop)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "TOP",
                          style: TextStyle(
                              color: Colors.amber.shade900,
                              fontSize: 9,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  "${s.room.isEmpty ? "—" : s.room} · "
                  "${s.kWh.toStringAsFixed(2)} kWh · "
                  "${s.activeDays} active day${s.activeDays == 1 ? '' : 's'}",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 11.5),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    minHeight: 6,
                    backgroundColor: color.withOpacity(0.12),
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("₨ ${_money(s.rupees)}",
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              Text("${pct.toStringAsFixed(1)}%",
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================
  // 6-MONTH TREND
  // =========================================================
  Widget _trendCard() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection("billing_history")
          .orderBy("month")
          .snapshots(),
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();

        final months = docs.map((d) => d.id).toList();
        final values = docs
            .map((d) =>
                (d.data()["totalRupees"] as num?)?.toDouble() ?? 0)
            .toList();

        final spots = <FlSpot>[];
        for (var i = 0; i < values.length; i++) {
          spots.add(FlSpot(i.toDouble(), values[i]));
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: _cardDeco(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Last 6 months",
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: LineChart(
                  LineChartData(
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
                          reservedSize: 44,
                          getTitlesWidget: (v, _) => Text(
                            "₨${v.toInt()}",
                            style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 10),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= months.length) {
                              return const SizedBox.shrink();
                            }
                            final mm = months[i].split("-").last;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(mm,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600)),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: _blue,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: _blue.withOpacity(0.10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================
  // TARIFF CARD
  // =========================================================
  Widget _tariffCard(BillBreakdown b) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, color: _blue, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Tariff in use",
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  "₨ ${BillSplittingService.tariffPerKWh.toStringAsFixed(0)} per kWh — Pakistan reference",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.grey.shade700, fontSize: 12.5),
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
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      );

  String _initials(String name) {
    if (name.isEmpty) return "?";
    final parts = name.trim().split(RegExp(r"\s+"));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String _firstName(String name) {
    if (name.isEmpty) return "—";
    return name.trim().split(RegExp(r"\s+")).first;
  }

  String _money(double v) =>
      NumberFormat.decimalPattern("en_US").format(v.round());

  String _formatRange(DateTime s, DateTime e) {
    final df = DateFormat("MMM d");
    if (s.year == e.year && s.month == e.month) {
      return "${df.format(s)} – ${DateFormat("d, yyyy").format(e)}";
    }
    return "${DateFormat("MMM d, yyyy").format(s)} – ${DateFormat("MMM d, yyyy").format(e)}";
  }
}
