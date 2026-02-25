// ignore_for_file: unnecessary_underscores, deprecated_member_use

import 'package:flutter/material.dart';
import '../models/device_model.dart';

class OverviewTab extends StatelessWidget {
  final List<DeviceModel> appliances;
  final void Function(DeviceModel) onDeviceTap;

  static const Color primaryBlue = Color(0xFF154F73);

  const OverviewTab({
    super.key,
    required this.appliances,
    required this.onDeviceTap,
  });

  @override
  Widget build(BuildContext context) {
    if (appliances.isEmpty) {
      return const Center(
        child: Text(
          "No devices found",
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: appliances.length,
      itemBuilder: (context, index) {
        final device = appliances[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _OverviewSummaryCard(
            device: device,
            image: _imageFor(device.type),
            onTap: () => onDeviceTap(device),
          ),
        );
      },
    );
  }

  String _imageFor(String type) {
    switch (type.toLowerCase()) {
      case "fan":
        return "assets/devices/fan.jpg";
      case "bulb":
        return "assets/devices/bulb.jpg";
      case "pump":
        return "assets/devices/pump.jpg";
      case "bell":
        return "assets/devices/bell.jpg";
      default:
        return "assets/devices/default.png";
    }
  }
}

////////////////////////////////////////////////////////////
/// 🧩 OVERVIEW SUMMARY CARD (LIGHT & DISTINCT)
////////////////////////////////////////////////////////////

class _OverviewSummaryCard extends StatelessWidget {
  final DeviceModel device;
  final String image;
  final VoidCallback onTap;

  static const Color primaryBlue = Color(0xFF154F73);

  const _OverviewSummaryCard({
    required this.device,
    required this.image,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOn = device.isOn;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 92,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isOn
              ? primaryBlue.withOpacity(0.10)
              : Colors.grey.withOpacity(0.10),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            // 🔹 IMAGE AS SOFT ACCENT
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 64,
                height: 64,
                child: Image.asset(
                  image,
                  fit: BoxFit.cover,
                ),
              ),
            ),

            const SizedBox(width: 14),

            // 🔹 NAME + STATE
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name.isNotEmpty
                        ? device.name
                        : "Unnamed Device",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isOn ? "Currently Active" : "Currently Off",
                    style: TextStyle(
                      fontSize: 13,
                      color: isOn
                          ? primaryBlue
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            // 🔹 STATUS DOT (NOT PILL → DIFFERENCE!)
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOn ? primaryBlue : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
