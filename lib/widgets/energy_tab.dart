// ignore_for_file: deprecated_member_use

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/dashboard_nav_service.dart';

class EnergyTab extends StatelessWidget {
  const EnergyTab({super.key});

  static const Color themeBlue = Color(0xFF185B86);

  @override
  Widget build(BuildContext context) {
    final todayId = _todayId();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("energy_daily")
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        QueryDocumentSnapshot? todayDoc;
        final List<QueryDocumentSnapshot> historyDocs = [];

        for (final doc in snapshot.data!.docs) {
          if (doc.id == todayId) {
            todayDoc = doc;
          } else {
            historyDocs.add(doc);
          }
        }

        historyDocs.sort((a, b) => b.id.compareTo(a.id));

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          children: [
            /// FIXED TOP OFFSET (CRITICAL)
            SizedBox(height: MediaQuery.of(context).padding.top),

            /// ================= AI OPTIMIZATION CTA =================
            _AiReportCta(),

            const SizedBox(height: 16),

            /// ================= TODAY =================
            const Text(
              "Today",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),

            _TodaySection(todayDoc: todayDoc),

            const SizedBox(height: 28),

            /// ================= HISTORY BUTTON =================
            GestureDetector(
              onTap: historyDocs.isEmpty
                  ? null
                  : () => _openHistory(context, historyDocs),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: themeBlue,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: themeBlue.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.history, color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      "View Energy History",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// ================= HISTORY MODAL =================
  void _openHistory(
    BuildContext context,
    List<QueryDocumentSnapshot> historyDocs,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Energy History",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: historyDocs.length,
                  itemBuilder: (context, index) {
                    final doc = historyDocs[index];
                    final raw = doc.data() as Map<String, dynamic>;
                    final total =
                        (raw["totalEnergy"] ?? 0.0).toDouble();

                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                _HistoryDetailPage(doc: doc),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: themeBlue.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: themeBlue.withOpacity(0.15),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: themeBlue,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.calendar_today,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${raw["day"]} • ${raw["date"]}",
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Total usage: ${total.toStringAsFixed(2)} kWh",
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 🔑 TODAY ID
  static String _todayId() {
    final now = DateTime.now();
    return "${now.year}-${_pad(now.month)}-${_pad(now.day)}";
  }

  static String _pad(int v) => v.toString().padLeft(2, '0');
}

////////////////////////////////////////////////////////////
/// TODAY SECTION
////////////////////////////////////////////////////////////

class _TodaySection extends StatelessWidget {
  final QueryDocumentSnapshot? todayDoc;

  const _TodaySection({required this.todayDoc});

  @override
  Widget build(BuildContext context) {
    final raw = todayDoc?.data() as Map<String, dynamic>?;

    final now = DateTime.now();
    final dayNames = [
      "Sunday",
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday"
    ];

    final String day =
        raw?["day"] ?? dayNames[now.weekday % 7];
    final String date =
        raw?["date"] ??
        "${now.day.toString().padLeft(2, '0')}-"
        "${now.month.toString().padLeft(2, '0')}-"
        "${now.year}";

    final hourly =
        raw != null && raw.containsKey("hourlyUsage")
            ? Map<String, double>.from(
                (raw["hourlyUsage"] as Map)
                    .map((k, v) => MapEntry(k, (v ?? 0).toDouble())),
              )
            : <String, double>{};

    final deviceUsage =
        raw != null && raw.containsKey("deviceUsage")
            ? Map<String, double>.from(
                (raw["deviceUsage"] as Map)
                    .map((k, v) => MapEntry(k, (v ?? 0).toDouble())),
              )
            : <String, double>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: EnergyTab.themeBlue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            "$day • $date",
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: EnergyTab.themeBlue,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SummaryCard(raw: raw),
        const SizedBox(height: 16),
        _HourlyChart(hourly: hourly),
        const SizedBox(height: 16),
        const Text(
          "Device Usage Today",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (deviceUsage.isNotEmpty)
          ...deviceUsage.entries.map(
            (e) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(e.key,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600)),
                  Text(
                    "${e.value.toStringAsFixed(2)} kWh",
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: EnergyTab.themeBlue,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          const Text(
            "No device usage data yet",
            style: TextStyle(color: Colors.grey),
          ),
      ],
    );
  }
}

////////////////////////////////////////////////////////////
/// SUMMARY CARD
////////////////////////////////////////////////////////////

class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic>? raw;

  const _SummaryCard({required this.raw});

  @override
  Widget build(BuildContext context) {
    final total = (raw?["totalEnergy"] ?? 0.0).toDouble();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EnergyTab.themeBlue,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's Energy",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          _row("Total Usage", "${total.toStringAsFixed(2)} kWh"),
          _row("Peak Hour", raw?["peakHour"]?.toString() ?? "—"),
          _row("Most Used Device",
              raw?["mostUsedDevice"]?.toString() ?? "—"),
        ],
      ),
    );
  }

  Widget _row(String l, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l, style: const TextStyle(color: Colors.white70)),
          Text(v,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

////////////////////////////////////////////////////////////
/// HOURLY CHART
////////////////////////////////////////////////////////////

class _HourlyChart extends StatelessWidget {
  final Map<String, double> hourly;

  const _HourlyChart({required this.hourly});

  @override
  Widget build(BuildContext context) {
    final spots = hourly.entries
        .map((e) => FlSpot(double.parse(e.key), e.value))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));

    return _ChartContainer(
      title: "Hourly Usage",
      chart: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots.isEmpty ? [const FlSpot(0, 0)] : spots,
              isCurved: true,
              barWidth: 3,
              color: Colors.blue,
              belowBarData: BarAreaData(
                show: true,
                color: Colors.blue.withOpacity(0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

////////////////////////////////////////////////////////////
/// HISTORY DETAIL PAGE
////////////////////////////////////////////////////////////

class _HistoryDetailPage extends StatelessWidget {
  final QueryDocumentSnapshot doc;

  const _HistoryDetailPage({required this.doc});

  @override
  Widget build(BuildContext context) {
    final raw = doc.data() as Map<String, dynamic>;

    final hourly =
        raw.containsKey("hourlyUsage")
            ? Map<String, double>.from(
                (raw["hourlyUsage"] as Map)
                    .map((k, v) => MapEntry(k, (v ?? 0).toDouble())),
              )
            : <String, double>{};

    return Scaffold(
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text("${raw["day"]} • ${raw["date"]}",style: TextStyle(color: Colors.white),),
        backgroundColor: EnergyTab.themeBlue,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryCard(raw: raw),
          const SizedBox(height: 16),
          _HourlyChart(hourly: hourly),
        ],
      ),
    );
  }
}

////////////////////////////////////////////////////////////
/// CHART CONTAINER
////////////////////////////////////////////////////////////

class _ChartContainer extends StatelessWidget {
  final String title;
  final Widget chart;

  const _ChartContainer({
    required this.title,
    required this.chart,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          SizedBox(height: 220, child: chart),
        ],
      ),
    );
  }
}


/// =========================================================
/// AI OPTIMIZATION REPORT CTA
/// =========================================================
/// Top-of-screen banner that pushes the user from raw energy
/// data into the predictive optimization journey. Tapping it
/// jumps to the Optimization tab via DashboardNavService.
class _AiReportCta extends StatelessWidget {
  static const _green = Color(0xFF24E0A0);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => DashboardNavService.switchTo(DashboardTab.optimization),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0E7C5C), Color(0xFF065244)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _green.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_graph_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "View AI Optimization Report",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "See which devices waste energy in peak hours and let the agent optimize them.",
                    style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

