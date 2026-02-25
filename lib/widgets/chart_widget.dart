import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/device_model.dart';

class ChartWidget extends StatelessWidget {
  final DeviceModel device;

  const ChartWidget({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        borderData: FlBorderData(show: true),
        titlesData: FlTitlesData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              10,
              (index) => FlSpot(index.toDouble(), (device.power / 2) + index),
            ),
            isCurved: true,
            color: Colors.blueAccent,
            barWidth: 3,
            dotData: FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
