// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/room_model.dart';
import '../services/energy_optimization_service.dart';

/// =========================================================
/// ROOM AI REPORT SCREEN
/// =========================================================
/// Per-room AI-generated optimization report. Opened from the
/// "Generate AI Report" button on each room card.
///
/// Sections:
///   1. Executive summary (AI-style narrative)
///   2. Key insights (kWh, peak share, projected savings)
///   3. Peak-hour breakdown by device
///   4. Recommended actions — each with a Commit button that
///      writes the rule into the Optimization tab's active list
///   5. Run live demo for the top recommended device
class RoomReportScreen extends StatefulWidget {
  final RoomModel room;
  const RoomReportScreen({super.key, required this.room});

  @override
  State<RoomReportScreen> createState() => _RoomReportScreenState();
}

class _RoomReportScreenState extends State<RoomReportScreen> {
  static const Color _ink = Color(0xFF0E2E45);
  static const Color _blue = Color(0xFF154F73);
  static const Color _green = Color(0xFF24E0A0);
  static const Color _deep = Color(0xFF065244);
  static const Color _amber = Color(0xFFE0A458);

  Future<_ReportData>? _future;
  String _committingDeviceId = "";
  bool _runningDemo = false;
  late final DateTime _generatedAt;

  @override
  void initState() {
    super.initState();
    _generatedAt = DateTime.now();
    _future = _load();
  }

  Future<_ReportData> _load() async {
    final reports =
        await EnergyOptimizationService.generateRoomReports();
    final mine = reports.firstWhere(
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
    final base = await EnergyOptimizationService.generateReport();
    return _ReportData(
      room: mine,
      daysAnalyzed: base.daysAnalyzed,
      tariffPeak: EnergyOptimizationService.peakRate,
      tariffOff: EnergyOptimizationService.offPeakRate,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _commit(DeviceUsage d) async {
    setState(() => _committingDeviceId = d.deviceId);
    try {
      final rec = OptimizationRecommendation(
        deviceId: d.deviceId,
        deviceName: d.deviceName,
        twoWeekKWh: d.twoWeekKWh,
        peakKWh: d.peakKWh,
        peakShare: d.peakShare,
        peakHour: d.peakHour,
        recommendation:
            "Auto-off ${d.deviceName} during 6 PM – 11 PM peak hours.",
        projectedMonthlySavingsPKR: d.projectedMonthlySavingsPKR > 0
            ? d.projectedMonthlySavingsPKR
            : d.peakKWh * EnergyOptimizationService.peakRate * 2,
        wastefulPeak: true,
      );
      await EnergyOptimizationService.commitRule(
        rec,
        scopedRoom: widget.room,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(
            "${d.deviceName} rule committed for ${widget.room.name}. "
            "Visible now in the Optimization tab.",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Commit failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _committingDeviceId = "");
    }
  }

  Future<void> _runDemo(DeviceUsage d) async {
    setState(() => _runningDemo = true);
    try {
      final rec = OptimizationRecommendation(
        deviceId: d.deviceId,
        deviceName: d.deviceName,
        twoWeekKWh: d.twoWeekKWh,
        peakKWh: d.peakKWh,
        peakShare: d.peakShare,
        peakHour: d.peakHour,
        recommendation: "",
        projectedMonthlySavingsPKR: d.projectedMonthlySavingsPKR,
        wastefulPeak: true,
      );
      await EnergyOptimizationService.commitRule(
        rec,
        scopedRoom: widget.room,
      );
      await EnergyOptimizationService.runDemoCycle(
        deviceId: d.deviceId,
        dailyPeakKWh: d.peakKWh / 14.0,
        scopedRoom: widget.room,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "${d.deviceName} demo complete. Rule is now active."),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Demo failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _runningDemo = false);
    }
  }

  // =========================================================
  // BUILD
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: const Text("AI Optimization Report"),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: "Regenerate",
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<_ReportData>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data;
          if (data == null) {
            return const Center(
                child: Text("Could not generate report."));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _reportHeader(data),
              const SizedBox(height: 14),
              _executiveSummary(data),
              const SizedBox(height: 14),
              _keyInsights(data),
              const SizedBox(height: 14),
              _peakHourAnalysis(data),
              const SizedBox(height: 14),
              _deviceBreakdown(data),
              const SizedBox(height: 14),
              _recommendations(data),
              const SizedBox(height: 14),
              _liveDemoCard(data),
              const SizedBox(height: 18),
              _footer(data),
            ],
          );
        },
      ),
    );
  }

  // =========================================================
  // REPORT HEADER (looks like a document)
  // =========================================================
  Widget _reportHeader(_ReportData data) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _blue.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _blue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "SHAPEOS · CONFIDENTIAL",
                  style: TextStyle(
                    color: _blue,
                    fontSize: 9.5,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                "Report ID #${_reportId(data.room.room.id)}",
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            "AI Energy Optimization Report",
            style: TextStyle(
                color: _ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1.15),
          ),
          const SizedBox(height: 6),
          Text(
            "${data.room.room.name}"
            "${data.room.room.occupant.isEmpty ? '' : ' · ${data.room.room.occupant}'}",
            style: TextStyle(
              color: _blue,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Analysis window: last ${data.daysAnalyzed} days · "
            "Generated ${DateFormat("MMM d, yyyy · h:mm a").format(_generatedAt)}",
            style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: Colors.grey.shade200,
          ),
          const SizedBox(height: 12),
          Text(
            "Tariff schedule applied: ₨ ${data.tariffPeak.toStringAsFixed(0)} per kWh during peak (6 PM–11 PM); "
            "₨ ${data.tariffOff.toStringAsFixed(0)} per kWh otherwise.",
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // EXECUTIVE SUMMARY
  // =========================================================
  Widget _executiveSummary(_ReportData data) {
    final r = data.room;
    final loud = r.devices.isEmpty ? null : r.devices.first;
    final summary = _composeSummary(data, loud);

    return _section(
      title: "Executive summary",
      icon: Icons.notes_rounded,
      child: Text(
        summary,
        style: const TextStyle(
          color: _ink,
          fontSize: 13.5,
          height: 1.55,
        ),
      ),
    );
  }

  String _composeSummary(_ReportData data, DeviceUsage? loud) {
    final r = data.room;
    if (r.roomTotalKWh <= 0) {
      return "No measurable activity has been recorded for "
          "${r.room.name} during the analysis window. "
          "Once the room's devices accumulate usage, the agent "
          "will revise this report and surface concrete savings "
          "opportunities.";
    }
    final loudPart = loud == null
        ? ""
        : " The dominant peak-hour consumer is the ${loud.deviceName}, "
            "responsible for ${(loud.peakShare * 100).toStringAsFixed(0)}% "
            "of its energy during the 6 PM – 11 PM window — "
            "${loud.peakKWh.toStringAsFixed(2)} kWh over the analysis "
            "period.";
    final savings = r.projectedMonthlySavingsPKR <= 0
        ? "Current peak-hour exposure is minimal; no committed rule is recommended."
        : "Committing the recommended peak-hour auto-off rule projects "
            "₨ ${r.projectedMonthlySavingsPKR.toStringAsFixed(0)} of monthly savings "
            "back to the household.";

    return "Across the past ${data.daysAnalyzed} days, ${r.room.name} "
        "consumed ${r.roomTotalKWh.toStringAsFixed(2)} kWh, of which "
        "${r.roomPeakKWh.toStringAsFixed(2)} kWh "
        "(${r.peakSharePercent.toStringAsFixed(0)}%) occurred during "
        "peak hours.$loudPart $savings";
  }

  // =========================================================
  // KEY INSIGHTS — 3 stat tiles
  // =========================================================
  Widget _keyInsights(_ReportData data) {
    final r = data.room;
    return _section(
      title: "Key insights",
      icon: Icons.insights_rounded,
      child: Row(
        children: [
          Expanded(
            child: _statTile(
              label: "TOTAL ENERGY",
              value: "${r.roomTotalKWh.toStringAsFixed(2)} kWh",
              caption: "in last ${data.daysAnalyzed} days",
              accent: _blue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statTile(
              label: "PEAK-HOUR SHARE",
              value: "${r.peakSharePercent.toStringAsFixed(0)}%",
              caption: "of room's total energy",
              accent: _amber,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statTile(
              label: "SAVE / MONTH",
              value: "₨ ${r.projectedMonthlySavingsPKR.toStringAsFixed(0)}",
              caption: "after committing rules",
              accent: _green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required String label,
    required String value,
    required String caption,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
                color: accent,
                fontSize: 9.5,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style:
                TextStyle(color: Colors.grey.shade700, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // PEAK-HOUR ANALYSIS — list with progress bars
  // =========================================================
  Widget _peakHourAnalysis(_ReportData data) {
    final usages = data.room.devices;
    return _section(
      title: "Peak-hour distribution",
      icon: Icons.bolt_rounded,
      child: usages.isEmpty
          ? Text(
              "No peak-hour activity tracked for this room.",
              style: TextStyle(
                  color: Colors.grey.shade700, fontSize: 12.5),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in usages) _peakBar(d),
              ],
            ),
    );
  }

  Widget _peakBar(DeviceUsage d) {
    final share = d.peakShare.clamp(0.0, 1.0);
    final color = d.wastefulPeak ? _amber : _green;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(d.deviceName), color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  d.deviceName,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                "${(share * 100).toStringAsFixed(0)}% peak · "
                "peak hour ${_hourLabel(d.peakHour)}",
                style: TextStyle(
                    color: Colors.grey.shade700, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 6,
              backgroundColor: color.withOpacity(0.12),
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // DEVICE BREAKDOWN — table
  // =========================================================
  Widget _deviceBreakdown(_ReportData data) {
    final usages = data.room.devices;
    return _section(
      title: "Device breakdown",
      icon: Icons.devices_other_rounded,
      child: usages.isEmpty
          ? Text(
              "No tracked devices in this room yet.",
              style: TextStyle(
                  color: Colors.grey.shade700, fontSize: 12.5),
            )
          : Column(
              children: [
                _tableHeader(),
                for (var i = 0; i < usages.length; i++)
                  _tableRow(usages[i], i.isEven),
              ],
            ),
    );
  }

  Widget _tableHeader() {
    TextStyle h() => TextStyle(
          color: Colors.grey.shade700,
          fontSize: 10.5,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w800,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text("DEVICE", style: h())),
          Expanded(flex: 3, child: Text("14-DAY kWh", style: h())),
          Expanded(flex: 3, child: Text("PEAK kWh", style: h())),
          Expanded(flex: 2, child: Text("STATUS", style: h())),
        ],
      ),
    );
  }

  Widget _tableRow(DeviceUsage d, bool zebra) {
    final color = d.wastefulPeak ? _amber : _green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: zebra ? Colors.grey.shade50 : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Icon(_iconFor(d.deviceName), size: 16, color: _blue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    d.deviceName,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              d.twoWeekKWh.toStringAsFixed(2),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              d.peakKWh.toStringAsFixed(2),
              style: TextStyle(
                color: d.peakKWh > 0 ? color : Colors.grey.shade600,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.13),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                d.wastefulPeak ? "FIX" : "LEAN",
                style: TextStyle(
                  color: d.wastefulPeak
                      ? const Color(0xFF8A4B00)
                      : _deep,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // RECOMMENDATIONS — with Commit buttons
  // =========================================================
  Widget _recommendations(_ReportData data) {
    final wasteful =
        data.room.devices.where((d) => d.wastefulPeak).toList();
    return _section(
      title: "Recommended actions",
      icon: Icons.task_alt_rounded,
      child: wasteful.isEmpty
          ? Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _green.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _green.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: _green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "No wasteful peak-hour patterns. ${data.room.room.name} "
                      "is already operating efficiently.",
                      style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 12.5,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < wasteful.length; i++)
                  _recCard(wasteful[i], i + 1),
              ],
            ),
    );
  }

  Widget _recCard(DeviceUsage d, int n) {
    return StreamBuilder<List<CommittedRule>>(
      stream: EnergyOptimizationService.activeRules(),
      builder: (ctx, snap) {
        final rules = snap.data ?? const <CommittedRule>[];
        // Per-room committed check: only THIS room's rule lights
        // up the badge, never another room's rule on the same id.
        final committed = rules.any((r) =>
            r.deviceId == d.deviceId &&
            r.roomId == widget.room.id &&
            r.active);
        final isBusy = _committingDeviceId == d.deviceId;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border(
              left: BorderSide(
                color: committed ? _green : _amber,
                width: 4,
              ),
              top: BorderSide(color: Colors.grey.shade200),
              right: BorderSide(color: Colors.grey.shade200),
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: committed ? _green : _amber,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      "$n",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Auto-off ${d.deviceName} during 6 PM – 11 PM peak hours",
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (committed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _green.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        "COMMITTED ✓",
                        style: TextStyle(
                          color: _deep,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "Rationale: ${d.deviceName} accounts for "
                "${(d.peakShare * 100).toStringAsFixed(0)}% of its energy during peak hours, "
                "concentrated around ${_hourLabel(d.peakHour)}. "
                "Auto-cutting it during 6 PM – 11 PM is projected to save "
                "₨ ${d.projectedMonthlySavingsPKR.toStringAsFixed(0)} per month.",
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          (committed || isBusy) ? null : () => _commit(d),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: isBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline,
                              size: 16),
                      label: Text(committed
                          ? "Already committed"
                          : isBusy
                              ? "Committing…"
                              : "Commit recommendation"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _runningDemo ? null : () => _runDemo(d),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _amber,
                      side: BorderSide(color: _amber.withOpacity(0.6)),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: Text(_runningDemo ? "Running…" : "Demo"),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================
  // LIVE DEMO CALL-TO-ACTION
  // =========================================================
  Widget _liveDemoCard(_ReportData data) {
    final loud = data.room.devices.firstWhere(
      (d) => d.wastefulPeak,
      orElse: () => data.room.devices.isEmpty
          ? const DeviceUsage(
              deviceId: "",
              deviceName: "",
              twoWeekKWh: 0,
              peakKWh: 0,
              peakHour: 18,
              peakShare: 0,
              wastefulPeak: false,
              projectedMonthlySavingsPKR: 0,
            )
          : data.room.devices.first,
    );
    if (loud.deviceId.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: _amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _amber.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_filled, color: _amber, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Live demo",
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
                Text(
                  "Watch the agent narrate, commit, and auto-cut "
                  "${loud.deviceName} in ${data.room.room.name} live.",
                  style: TextStyle(
                      color: Colors.grey.shade800, fontSize: 12),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _runningDemo ? null : () => _runDemo(loud),
            style: ElevatedButton.styleFrom(
              backgroundColor: _amber,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _runningDemo
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text("Run"),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // FOOTER
  // =========================================================
  Widget _footer(_ReportData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          "Report generated by SHAPEOS · Predictive Energy Optimization v1.0\n"
          "Once committed, rules are enforced automatically by the in-home agent during peak hours.",
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 10.5,
              height: 1.5),
        ),
      ),
    );
  }

  // =========================================================
  // SECTION CARD HELPER
  // =========================================================
  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _blue, size: 18),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: _blue,
                  fontSize: 11.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  // =========================================================
  // HELPERS
  // =========================================================
  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains("fan")) return Icons.air_rounded;
    if (n.contains("bulb")) return Icons.lightbulb_rounded;
    if (n.contains("pump")) return Icons.water_rounded;
    if (n.contains("bell")) return Icons.notifications_active_rounded;
    return Icons.power_rounded;
  }

  String _hourLabel(int h) {
    if (h == 0) return "12 AM";
    if (h < 12) return "$h AM";
    if (h == 12) return "12 PM";
    return "${h - 12} PM";
  }

  String _reportId(String roomId) {
    final stamp = _generatedAt.millisecondsSinceEpoch
        .toString()
        .substring(7);
    final shortRoom = roomId.length > 4
        ? roomId.substring(roomId.length - 4)
        : roomId;
    return "${shortRoom.toUpperCase()}-$stamp";
  }
}

class _ReportData {
  final RoomEnergyReport room;
  final int daysAnalyzed;
  final double tariffPeak;
  final double tariffOff;
  const _ReportData({
    required this.room,
    required this.daysAnalyzed,
    required this.tariffPeak,
    required this.tariffOff,
  });
}
