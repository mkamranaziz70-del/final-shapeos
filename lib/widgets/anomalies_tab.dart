// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../models/anomaly_record.dart';
import '../services/anomaly_detection_service.dart';
import '../services/demo_seeder_service.dart';

/// =========================================================
/// ANOMALIES TAB
/// =========================================================
/// Streams `/users/{uid}/anomalies/` from Firestore. Includes:
///   • hero card with 7-day total + severity donut
///   • severity filter chips (All / Critical / Warning / Info)
///   • anomaly cards with metrics, time-ago, resolve action
///   • empty-state CTA that seeds demo data
class AnomaliesTab extends StatefulWidget {
  const AnomaliesTab({super.key});

  @override
  State<AnomaliesTab> createState() => _AnomaliesTabState();
}

class _AnomaliesTabState extends State<AnomaliesTab> {
  static const Color _blue = Color(0xFF154F73);
  static const Color _critical = Color(0xFFDB3A34);
  static const Color _warning = Color(0xFFF2A65A);
  static const Color _info = Color(0xFF1F8AC0);

  String _filter = "all";
  bool _seeding = false;

  Color _colorFor(String severity) {
    switch (severity) {
      case "critical":
        return _critical;
      case "warning":
        return _warning;
      default:
        return _info;
    }
  }

  IconData _iconFor(String severity) {
    switch (severity) {
      case "critical":
        return Icons.error_rounded;
      case "warning":
        return Icons.warning_amber_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  Future<void> _seed() async {
    setState(() => _seeding = true);
    try {
      final report = await DemoSeederService.seedAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(report.summarise())),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Seed failed: $e")));
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _wipe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Reset demo data?"),
        content: const Text(
          "Removes the seeded fake roommates, energy days, anomalies and "
          "agent-action records. Your real data is untouched.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDB3A34),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Wipe demo"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _seeding = true);
    try {
      await DemoSeederService.wipeDemoData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Demo data wiped.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Wipe failed: $e")));
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AnomalyRecord>>(
      stream: AnomalyDetectionService.stream(limit: 200),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snap.data ?? const <AnomalyRecord>[];

        if (all.isEmpty) return _emptyState();

        final filtered = _filter == "all"
            ? all
            : all.where((a) => a.severity == _filter).toList();

        final last7 = all
            .where((a) => DateTime.now()
                .difference(a.detectedAt)
                .inDays
                <= 7)
            .toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            _heroCard(last7),
            const SizedBox(height: 16),
            _filterRow(all),
            const SizedBox(height: 12),
            _topOffender(last7),
            const SizedBox(height: 12),
            ...filtered.map(_anomalyCard),
          ],
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_moon_outlined,
                size: 72, color: _blue),
            const SizedBox(height: 14),
            const Text(
              "No anomalies yet",
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, color: _blue),
            ),
            const SizedBox(height: 8),
            Text(
              "The agent has not detected anything unusual. "
              "Seed demo data to see what a populated month looks like.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _seeding ? null : _seed,
              icon: _seeding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.science_rounded),
              label: Text(_seeding ? "Seeding…" : "Seed demo data"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroCard(List<AnomalyRecord> last7) {
    final crit = last7.where((a) => a.severity == "critical").length;
    final warn = last7.where((a) => a.severity == "warning").length;
    final info = last7.where((a) => a.severity == "info").length;
    final unresolved = last7.where((a) => !a.isResolved).length;

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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "AI Anomaly Detection",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "${last7.length}",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  "events detected · last 7 days",
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _legendDot(_critical, "$crit critical"),
                      const SizedBox(width: 12),
                      _legendDot(_warning, "$warn warning"),
                      const SizedBox(width: 12),
                      _legendDot(_info, "$info info"),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  unresolved == 0
                      ? "All anomalies resolved."
                      : "$unresolved still need attention.",
                  style: TextStyle(
                    color: unresolved == 0
                        ? Colors.greenAccent
                        : Colors.amberAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            height: 110,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 32,
                sections: [
                  if (crit > 0)
                    PieChartSectionData(
                      value: crit.toDouble(),
                      color: _critical,
                      radius: 22,
                      title: "",
                    ),
                  if (warn > 0)
                    PieChartSectionData(
                      value: warn.toDouble(),
                      color: _warning,
                      radius: 22,
                      title: "",
                    ),
                  if (info > 0)
                    PieChartSectionData(
                      value: info.toDouble(),
                      color: _info,
                      radius: 22,
                      title: "",
                    ),
                  if (last7.isEmpty)
                    PieChartSectionData(
                      value: 1,
                      color: Colors.white24,
                      radius: 22,
                      title: "",
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
                color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      );

  Widget _filterRow(List<AnomalyRecord> all) {
    final crit = all.where((a) => a.severity == "critical").length;
    final warn = all.where((a) => a.severity == "warning").length;
    final info = all.where((a) => a.severity == "info").length;

    Widget chip(String key, String label, int count, Color color) {
      final on = _filter == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text("$label · $count"),
          selected: on,
          backgroundColor: color.withOpacity(0.12),
          selectedColor: color,
          labelStyle: TextStyle(
            color: on ? Colors.white : color,
            fontWeight: FontWeight.w600,
          ),
          onSelected: (_) => setState(() => _filter = key),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: color.withOpacity(0.4)),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip("all", "All", all.length, _blue),
                chip("critical", "Critical", crit, _critical),
                chip("warning", "Warning", warn, _warning),
                chip("info", "Info", info, _info),
              ],
            ),
          ),
        ),
        TextButton.icon(
          onPressed: _seeding ? null : _wipe,
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text(
            "Reset demo",
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _topOffender(List<AnomalyRecord> last7) {
    if (last7.isEmpty) return const SizedBox.shrink();
    final counts = <String, int>{};
    for (final a in last7) {
      counts.update(a.deviceName, (v) => v + 1, ifAbsent: () => 1);
    }
    final top = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final winner = top.first;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_circle_rounded,
              color: Color(0xFFB76E00), size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Top offender: ${winner.key} — ${winner.value} anomalies in 7 days",
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: Color(0xFF7A4A00)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _anomalyCard(AnomalyRecord a) {
    final color = _colorFor(a.severity);
    final ago = _timeAgo(a.detectedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border(
          left: BorderSide(color: color, width: 4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(a.severity), color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    a.severity.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.devices_other_rounded,
                    size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    a.deviceName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.access_time_rounded,
                    size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    ago,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.grey.shade700, fontSize: 12.5),
                  ),
                ),
                const Spacer(),
                if (a.isResolved)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 14, color: Colors.green),
                      const SizedBox(width: 3),
                      Text("resolved",
                          style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(a.detail,
                style: TextStyle(
                    color: Colors.grey.shade800, fontSize: 13.5, height: 1.4)),
            if (a.metrics.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: a.metrics.entries
                    .map((e) => _metricChip(e.key, e.value, color))
                    .toList(),
              ),
            ],
            if (!a.isResolved) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      AnomalyDetectionService.resolve(a.id),
                  child: const Text("Mark resolved"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metricChip(String label, double value, Color color) {
    String fmt = value.toStringAsFixed(2);
    if (value > 100) fmt = value.toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        "$label: $fmt",
        style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return "just now";
    if (d.inMinutes < 60) return "${d.inMinutes}m ago";
    if (d.inHours < 24) return "${d.inHours}h ago";
    if (d.inDays < 7) return "${d.inDays}d ago";
    return DateFormat("MMM d").format(dt);
  }
}
