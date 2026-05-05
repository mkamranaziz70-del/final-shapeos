// ignore_for_file: unnecessary_underscores, deprecated_member_use

import 'package:flutter/material.dart';
import '../models/device_model.dart';
import '../screens/auto_cut_screen.dart';
import '../screens/voltage_leakage_screen.dart';
import '../screens/voltage_surge_screen.dart';

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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _safetyModulesSection(context),
        const SizedBox(height: 18),
        _devicesHeader(),
        const SizedBox(height: 8),
        if (appliances.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                "No devices selected yet.",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ),
          )
        else
          for (final d in appliances)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _OverviewSummaryCard(
                device: d,
                image: _imageFor(d.type),
                onTap: () => onDeviceTap(d),
              ),
            ),
      ],
    );
  }

  Widget _devicesHeader() => const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Text(
          "Your devices",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: primaryBlue,
            letterSpacing: 0.3,
          ),
        ),
      );

  Widget _safetyModulesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            "Safety modules",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: primaryBlue,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _ModuleCard(
                title: "Voltage\nSurge",
                icon: Icons.bolt_rounded,
                accent: const Color(0xFFE07A5F),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const VoltageSurgeScreen()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModuleCard(
                title: "Voltage\nLeakage",
                icon: Icons.water_drop_rounded,
                accent: const Color(0xFF1F8AC0),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const VoltageLeakageScreen()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModuleCard(
                title: "Auto\nCut",
                icon: Icons.shield_rounded,
                accent: const Color(0xFF24E0A0),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AutoCutScreen()),
                ),
              ),
            ),
          ],
        ),
      ],
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
/// 🛡️ SAFETY MODULE CARD (compact, tappable)
////////////////////////////////////////////////////////////

class _ModuleCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.10),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade900,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  "Open",
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.arrow_forward_rounded, color: accent, size: 14),
              ],
            ),
          ],
        ),
      ),
    );
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
