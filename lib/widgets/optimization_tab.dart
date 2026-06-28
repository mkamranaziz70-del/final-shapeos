// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/room_report_screen.dart';
import '../services/demo_seeder_service.dart';
import '../services/energy_optimization_service.dart';

/// =========================================================
/// OPTIMIZATION TAB — room-aware AI report
/// =========================================================
/// Three-column user journey:
///   1. SEE the AI report header (total projected savings).
///   2. PICK a room → drill into per-device peak-hour usage.
///   3. COMMIT a recommendation → triggers an immediate live
///      simulation (turn the device on, auto-cut, narrate),
///      and from then on the agent enforces the rule whenever
///      the device is on during 6 – 11 PM.
class OptimizationTab extends StatefulWidget {
  const OptimizationTab({super.key});

  @override
  State<OptimizationTab> createState() => _OptimizationTabState();
}

class _OptimizationTabState extends State<OptimizationTab> {
  static const Color _blue = Color(0xFF154F73);
  static const Color _green = Color(0xFF24E0A0);
  static const Color _amber = Color(0xFFE0A458);
  static const Color _deep = Color(0xFF065244);

  Future<_OptimizationData>? _future;
  bool _seeding = false;
  String _committingDeviceId = "";

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_OptimizationData> _load() async {
    final report = await EnergyOptimizationService.generateReport();
    final rooms =
        await EnergyOptimizationService.generateRoomReports();
    return _OptimizationData(report: report, rooms: rooms);
  }

  Future<void> _regenerate() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _seedAndRegenerate() async {
    setState(() => _seeding = true);
    try {
      final r = await DemoSeederService.seedAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.summarise())),
      );
      await _regenerate();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Seed failed: $e")));
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  /// Commit the rule AND immediately run the live simulation
  /// for that device — this is what the user asked for: tap
  /// commit → see the agent take action right now.
  Future<void> _commitAndSimulate(
    OptimizationRecommendation rec, {
    required RoomEnergyReport scopedRoom,
  }) async {
    setState(() => _committingDeviceId =
        "${scopedRoom.room.id}_${rec.deviceId}");
    try {
      // Persist the rule scoped to THIS room so it doesn't
      // collide with other rooms that share the same device id.
      await EnergyOptimizationService.commitRule(
        rec,
        scopedRoom: scopedRoom.room,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
              "Rule committed for ${scopedRoom.room.name} — running live demo now…"),
        ),
      );
      // Then run the demo cycle (announce → commit → fire),
      // also scoped so only this room's virtual device toggles.
      final dailyPeakKWh =
          rec.peakKWh / 14.0; // averaged over the analysis window
      await EnergyOptimizationService.runDemoCycle(
        deviceId: rec.deviceId,
        dailyPeakKWh: dailyPeakKWh,
        scopedRoom: scopedRoom.room,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(
              "${rec.deviceName} auto-cut complete. The agent will "
              "now enforce this rule every peak hour."),
        ),
      );
      await _regenerate();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Commit failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _committingDeviceId = "");
    }
  }

  // =========================================================
  // BUILD
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _regenerate,
      child: FutureBuilder<_OptimizationData>(
        future: _future,
        builder: (ctx, snap) {
          final loading =
              snap.connectionState == ConnectionState.waiting;
          final data = snap.data;
          final isEmpty = data == null ||
              data.report.daysAnalyzed == 0 ||
              data.report.totalKWh <= 0;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (isEmpty)
                _emptyState()
              else ...[
                _hero(data.report),
                const SizedBox(height: 14),
                _liveStatusStrip(data.rooms),
                const SizedBox(height: 14),
                _activeRules(),
                const SizedBox(height: 14),
                ..._roomCards(data.rooms),
                const SizedBox(height: 12),
                _aiReport(data),
              ],
            ],
          );
        },
      ),
    );
  }

  // =========================================================
  // EMPTY STATE
  // =========================================================
  Widget _emptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(24),
      decoration: _cardDeco(),
      child: Column(
        children: [
          const Icon(Icons.auto_graph_rounded, size: 56, color: _green),
          const SizedBox(height: 10),
          const Text(
            "No usage data yet",
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 18, color: _blue),
          ),
          const SizedBox(height: 6),
          Text(
            "The optimizer needs at least a couple of days of energy "
            "history. Tap below to load 14 days of demo usage so the "
            "report can populate per room.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: _deep,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _seeding ? null : _seedAndRegenerate,
            icon: _seeding
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _deep),
                  )
                : const Icon(Icons.bolt_rounded, size: 18),
            label: Text(_seeding ? "Seeding…" : "Load 14 days of demo data"),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // HERO
  // =========================================================
  Widget _hero(OptimizationReport r) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E7C5C), Color(0xFF065244)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _green.withOpacity(0.25),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "ROOM-LEVEL PEAK-HOUR ANALYSIS",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: "Regenerate report",
                onPressed: _regenerate,
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "₨ ${r.projectedMonthlySavingsPKR.toStringAsFixed(0)}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "projected monthly savings if every recommendation below "
            "is committed.",
            style: TextStyle(
                color: Colors.white.withOpacity(0.85), fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: _statTile(
                      label: "DAYS ANALYZED",
                      value: "${r.daysAnalyzed}")),
              const SizedBox(width: 10),
              Expanded(
                  child: _statTile(
                      label: "PEAK SHARE",
                      value:
                          "${r.peakSharePercent.toStringAsFixed(0)}%")),
              const SizedBox(width: 10),
              Expanded(
                  child: _statTile(
                      label: "TOTAL kWh",
                      value: r.totalKWh.toStringAsFixed(1))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile({required String label, required String value}) {
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
        ],
      ),
    );
  }

  // =========================================================
  // LIVE STATUS STRIP — quick "we found these wasteful rooms"
  // =========================================================
  Widget _liveStatusStrip(List<RoomEnergyReport> rooms) {
    final loud = rooms.where((r) => r.roomPeakKWh > 0).toList();
    if (loud.isEmpty) return const SizedBox.shrink();
    final headline = loud
        .take(3)
        .map((r) =>
            "${r.room.name} (${r.roomPeakKWh.toStringAsFixed(2)} kWh)")
        .join(", ");
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _amber.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _amber.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_rounded, color: _amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Top peak-hour rooms: $headline",
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // ROOM CARDS
  // =========================================================
  List<Widget> _roomCards(List<RoomEnergyReport> rooms) {
    if (rooms.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: _cardDeco(),
          child: Text(
            "No rooms defined yet. Add rooms in the Rooms tab so the "
            "agent knows who owns which device.",
            style:
                TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ),
      ];
    }

    final cards = <Widget>[];
    for (var i = 0; i < rooms.length; i++) {
      cards.add(_roomCard(rooms[i]));
      if (i != rooms.length - 1) {
        cards.add(const SizedBox(height: 12));
      }
    }
    return cards;
  }

  Widget _roomCard(RoomEnergyReport rep) {
    final r = rep.room;
    final hasUsage = rep.devices.isNotEmpty;
    return Container(
      decoration: _cardDeco(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _blue,
                child: Text(
                  _initials(r.occupant.isEmpty ? r.name : r.occupant),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Text(
                      r.occupant.isEmpty
                          ? "no occupant"
                          : "occupant: ${r.occupant}",
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _green.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "save ₨ ${rep.projectedMonthlySavingsPKR.toStringAsFixed(0)}/mo",
                  style: const TextStyle(
                    color: _deep,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasUsage)
            Text(
              "No tracked devices in this room.",
              style: TextStyle(
                  color: Colors.grey.shade700, fontSize: 12.5),
            )
          else ...[
            // Room totals
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _chip("peak ${rep.roomPeakKWh.toStringAsFixed(2)} kWh"),
                _chip("total ${rep.roomTotalKWh.toStringAsFixed(2)} kWh"),
                _chip(
                    "peak share ${rep.peakSharePercent.toStringAsFixed(0)}%"),
              ],
            ),
            const SizedBox(height: 10),

            // ⭐ Generate AI Report — opens a full-screen
            //   professional report scoped to THIS room. Inside
            //   the report the admin can commit each
            //   recommendation; commits stream back into the
            //   Active rules section above.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _deep,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          RoomReportScreen(room: rep.room),
                    ),
                  );
                },
                icon: const Icon(Icons.description_rounded, size: 18),
                label: Text(
                  "Generate AI Report · ${rep.room.name}",
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Per-device list (quick-commit path; the full
            // report screen above gives the in-depth one)
            for (final d in rep.devices) _deviceRow(d, rep),
          ],
        ],
      ),
    );
  }

  Widget _deviceRow(DeviceUsage d, RoomEnergyReport scopedRoom) {
    return StreamBuilder<List<CommittedRule>>(
      stream: EnergyOptimizationService.activeRules(),
      builder: (ctx, snap) {
        final rules = snap.data ?? const <CommittedRule>[];
        // Committed status is per (room, device): a rule for
        // Kamran's fan must NOT light up Ali's fan card too.
        final committed = rules.any((r) =>
            r.deviceId == d.deviceId &&
            r.roomId == scopedRoom.room.id &&
            r.active);
        final isBusy = _committingDeviceId ==
            "${scopedRoom.room.id}_${d.deviceId}";
        final accent = committed ? _green : _amber;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_iconFor(d.deviceName),
                      color: accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      d.deviceName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                  ),
                  if (committed)
                    const _Badge(
                      text: "COMMITTED",
                      color: _deep,
                      bg: Color(0x3324E0A0),
                    )
                  else if (d.wastefulPeak)
                    _Badge(
                      text: "WASTEFUL",
                      color: const Color(0xFF8A4B00),
                      bg: _amber.withOpacity(0.18),
                    )
                  else
                    _Badge(
                      text: "LEAN",
                      color: _deep,
                      bg: _green.withOpacity(0.10),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _chip(
                      "${d.peakKWh.toStringAsFixed(2)} kWh in peak hours"),
                  _chip("peak hour ${_hourLabel(d.peakHour)}"),
                  _chip(
                      "${(d.peakShare * 100).toStringAsFixed(0)}% peak share"),
                  if (d.projectedMonthlySavingsPKR > 0)
                    _chip(
                        "save ₨ ${d.projectedMonthlySavingsPKR.toStringAsFixed(0)}/mo"),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: committed
                    ? OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _green,
                          side: BorderSide(color: _green.withOpacity(0.5)),
                        ),
                        onPressed: () {
                          // Disable only THIS room's rule, leaving
                          // other rooms with the same device id
                          // alone.
                          final hit = rules.firstWhere(
                            (r) =>
                                r.deviceId == d.deviceId &&
                                r.roomId == scopedRoom.room.id,
                            orElse: () => rules.firstWhere(
                                (r) => r.deviceId == d.deviceId),
                          );
                          EnergyOptimizationService.deactivateRule(hit.id);
                        },
                        icon: const Icon(Icons.toggle_on_rounded,
                            size: 16),
                        label: const Text("Disable rule"),
                      )
                    : ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: isBusy
                            ? null
                            : () => _commitAndSimulate(
                                  _toRecommendation(d),
                                  scopedRoom: scopedRoom,
                                ),
                        icon: isBusy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Icon(Icons.bolt_rounded, size: 14),
                        label: Text(isBusy
                            ? "Committing & demoing…"
                            : "Commit & simulate"),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================
  // ACTIVE RULES (kept high-up so the panel sees commitments)
  // =========================================================
  Widget _activeRules() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: _cardDeco(),
      child: StreamBuilder<List<CommittedRule>>(
        stream: EnergyOptimizationService.activeRules(),
        builder: (ctx, snap) {
          final rules = snap.data ?? const <CommittedRule>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Active optimization rules",
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "${rules.length} active",
                      style: const TextStyle(
                          color: _deep,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (rules.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    "Tap Commit & simulate on any room device below to "
                    "enforce + demo it now.",
                    style: TextStyle(
                        color: Colors.grey.shade700, fontSize: 12.5),
                  ),
                )
              else
                for (final rule in rules) _ruleRow(rule),
            ],
          );
        },
      ),
    );
  }

  Widget _ruleRow(CommittedRule rule) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: _green.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_rounded, color: _green, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${rule.displayLabel} · peak-hour auto-off",
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Text(
                  "saves ~₨ ${rule.monthlySavingsPKR.toStringAsFixed(0)} / month "
                  "· committed ${_relTime(rule.committedAt)}",
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: "Disable",
            iconSize: 18,
            onPressed: () =>
                EnergyOptimizationService.deactivateRule(rule.id),
            icon: const Icon(Icons.toggle_on, color: _green),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // RAW REPORT
  // =========================================================
  Widget _aiReport(_OptimizationData data) {
    final r = data.report;
    final rooms = data.rooms.where((x) => x.roomPeakKWh > 0).toList();
    final loudestRoom = rooms.isEmpty ? null : rooms.first;
    final loudestDevice = loudestRoom?.topPeakDevice;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_rounded,
                  color: _blue, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  "Generated report",
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              Text(
                DateFormat("MMM d, h:mm a").format(r.generatedAt),
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _reportBody(r, loudestRoom, loudestDevice),
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  String _reportBody(
    OptimizationReport r,
    RoomEnergyReport? loudestRoom,
    DeviceUsage? loudestDevice,
  ) {
    final base =
        "Across the last ${r.daysAnalyzed} days, the home consumed "
        "${r.totalKWh.toStringAsFixed(2)} kWh. "
        "${r.totalPeakKWh.toStringAsFixed(2)} kWh "
        "(${r.peakSharePercent.toStringAsFixed(0)}%) fell inside the "
        "${EnergyOptimizationService.peakStartHour}:00 – "
        "${EnergyOptimizationService.peakEndHour}:00 peak window where "
        "tariff is ₨ ${EnergyOptimizationService.peakRate.toStringAsFixed(0)} "
        "vs ₨ ${EnergyOptimizationService.offPeakRate.toStringAsFixed(0)} "
        "off-peak. ";
    if (loudestRoom == null || loudestDevice == null) {
      return "${base}Committing every recommendation projects to save "
          "₨ ${r.projectedMonthlySavingsPKR.toStringAsFixed(0)} next month.";
    }
    return "${base}Top peak-hour consumer: "
        "${loudestRoom.room.name} — its ${loudestDevice.deviceName} burned "
        "${loudestDevice.peakKWh.toStringAsFixed(2)} kWh during peak across "
        "${r.daysAnalyzed} days, ${(loudestDevice.peakShare * 100).toStringAsFixed(0)}% "
        "of its energy. Auto-cutting it during peak projects ~₨ "
        "${loudestDevice.projectedMonthlySavingsPKR.toStringAsFixed(0)}/month "
        "back to your wallet. Committing every rule projects to save "
        "₨ ${r.projectedMonthlySavingsPKR.toStringAsFixed(0)} next month.";
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

  Widget _chip(String text) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

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

  String _relTime(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return "just now";
    if (diff.inHours < 1) return "${diff.inMinutes}m ago";
    if (diff.inDays < 1) return "${diff.inHours}h ago";
    return "${diff.inDays}d ago";
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

  OptimizationRecommendation _toRecommendation(DeviceUsage d) {
    return OptimizationRecommendation(
      deviceId: d.deviceId,
      deviceName: d.deviceName,
      twoWeekKWh: d.twoWeekKWh,
      peakKWh: d.peakKWh,
      peakShare: d.peakShare,
      peakHour: d.peakHour,
      recommendation:
          "Auto-off ${d.deviceName} during 6 PM – 11 PM peak hours.",
      projectedMonthlySavingsPKR:
          d.projectedMonthlySavingsPKR > 0
              ? d.projectedMonthlySavingsPKR
              : d.peakKWh * EnergyOptimizationService.peakRate * 2,
      wastefulPeak: true,
    );
  }
}

class _OptimizationData {
  final OptimizationReport report;
  final List<RoomEnergyReport> rooms;
  const _OptimizationData({required this.report, required this.rooms});
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;
  const _Badge({required this.text, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
