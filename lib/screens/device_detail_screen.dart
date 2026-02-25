// ignore_for_file: unnecessary_cast, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:go_router/go_router.dart';
import '../models/device_model.dart';

class DeviceDetailScreen extends StatefulWidget {
  final DeviceModel device;

  const DeviceDetailScreen({super.key, required this.device});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  static const Color themeBlue = Color(0xFF185B86);

  late DeviceModel device;
  late DatabaseReference _deviceRef;

  @override
  void initState() {
    super.initState();
    device = widget.device;

    _deviceRef =
        FirebaseDatabase.instance.ref("appliances/${widget.device.id}");

    _deviceRef.onValue.listen((event) {
      final data = event.snapshot.value;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data as Map);
        if (!mounted) return;
        setState(() {
          device = DeviceModel(
            id: widget.device.id,
            name: map['name']?.toString() ?? device.name,
            type: map['type']?.toString() ?? device.type,
            isOn: map['isOn'] == true,
            voltage: (map['voltage'] ?? 0).toDouble(),
            current: (map['current'] ?? 0).toDouble(),
            power: (map['power'] ?? 0).toDouble(),
            energy: (map['energy'] ?? 0).toDouble(),
            currentLeakage: (map['currentLeakage'] ?? 0).toDouble(),
            voltageLeakage: (map['voltageLeakage'] ?? 0).toDouble(),
          );
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      
      onWillPop: () async {
        context.pop();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        
        appBar: AppBar(
          iconTheme: const IconThemeData(color: Colors.white),
          backgroundColor: themeBlue,
          elevation: 0,
          title: Text(
            device.name,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => context.pop(),
          ),
        ),
        body: Column(
          children: [
            // 🔹 HEADER STATUS
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              color: themeBlue,
              child: Column(
                children: [
                  Icon(
                    device.isOn
                        ? Icons.power_rounded
                        : Icons.power_off_rounded,
                    size: 44,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    device.isOn ? "Device Active" : "Device Inactive",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),

            // 🔹 STATS GRID
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  children: [
                    _StatTile(
                      label: "Voltage",
                      value: "${device.voltage.toStringAsFixed(2)} V",
                      icon: Icons.flash_on_rounded,
                    ),
                    _StatTile(
                      label: "Current",
                      value: "${device.current.toStringAsFixed(2)} A",
                      icon: Icons.bolt_rounded,
                    ),
                    _StatTile(
                      label: "Power",
                      value: "${device.power.toStringAsFixed(2)} W",
                      icon: Icons.power_rounded,
                    ),
                    _StatTile(
                      label: "Energy",
                      value: "${device.energy.toStringAsFixed(2)} kWh",
                      icon: Icons.energy_savings_leaf_rounded,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

////////////////////////////////////////////////////////////
/// 🔹 CLEAN STAT TILE (NO GRADIENTS)
////////////////////////////////////////////////////////////

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  static const Color themeBlue = Color(0xFF185B86);

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 34, color: themeBlue),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
