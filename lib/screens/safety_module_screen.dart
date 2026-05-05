// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../services/anomaly_detection_service.dart';
import '../services/device_profile_service.dart';
import '../services/device_simulator_service.dart';

enum SafetyMode { surge, leakage }

/// =========================================================
/// SAFETY MODULE SCREEN
/// =========================================================
/// Interactive demo for the Voltage Surge and Voltage Leakage
/// modules. The user:
///   1. Picks a device.
///   2. Turns it on (if it isn't already) — readings start
///      flickering live.
///   3. Taps "Simulate `<surge|leakage>`" — values spike out of
///      band, the anomaly detector fires, the auto-cut module
///      flips the device OFF for safety, voice narrates the
///      whole thing.
///
/// The same logic is reused by [VoltageSurgeScreen] and
/// [VoltageLeakageScreen].
class SafetyModuleScreen extends StatefulWidget {
  final SafetyMode mode;
  const SafetyModuleScreen({super.key, required this.mode});

  @override
  State<SafetyModuleScreen> createState() => _SafetyModuleScreenState();
}

class _SafetyModuleScreenState extends State<SafetyModuleScreen>
    with SingleTickerProviderStateMixin {
  static const Color _blue = Color(0xFF154F73);
  static const Color _danger = Color(0xFFDB3A34);
  static const Color _green = Color(0xFF24E0A0);

  String _selectedId = "1";
  bool _simulating = false;
  String? _statusLine;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String get _title => widget.mode == SafetyMode.surge
      ? "Voltage Surge Module"
      : "Voltage Leakage Module";

  String get _description => widget.mode == SafetyMode.surge
      ? "When the line voltage spikes outside a device's safe band, "
        "the auto-cut module immediately removes power. Pick a "
        "device, turn it on, then trigger a surge to demonstrate."
      : "When current leaks past insulation, the auto-cut module "
        "removes power before damage occurs. Pick a device, turn "
        "it on, then trigger a leakage event to demonstrate.";

  IconData get _icon => widget.mode == SafetyMode.surge
      ? Icons.bolt_rounded
      : Icons.water_drop_rounded;

  Future<void> _toggleDevice(bool turnOn) async {
    await FirebaseDatabase.instance
        .ref("appliances/$_selectedId")
        .update({"isOn": turnOn});
    setState(() {
      _statusLine =
          turnOn ? "Device turned ON. Readings are streaming." : null;
    });
  }

  Future<void> _trigger() async {
    if (_simulating) return;
    final profile = DeviceProfileService.of(_selectedId);
    if (profile == null) return;

    setState(() {
      _simulating = true;
      _statusLine = widget.mode == SafetyMode.surge
          ? "Voltage surge in progress — values climbing past the safe band…"
          : "Leakage current rising — insulation looks compromised…";
    });

    // Override lasts longer than we need so we never have a
    // case where the simulator returns to normal jitter before
    // the detector has run. The detector itself will clear the
    // override after the auto-cut.
    if (widget.mode == SafetyMode.surge) {
      DeviceSimulatorService.simulateSurge(
        _selectedId,
        duration: const Duration(seconds: 12),
      );
    } else {
      DeviceSimulatorService.simulateLeakage(
        _selectedId,
        duration: const Duration(seconds: 12),
      );
    }

    // Give the simulator two ticks to actually push the spiked
    // values into RTDB before we evaluate. Without this delay the
    // detector might read the pre-spike values and not trip.
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    // Run the detector directly against this single device, so the
    // auto-cut is deterministic — no waiting for the global 10 s
    // dashboard sweep, no risk of the override expiring first.
    await AnomalyDetectionService.evaluateById(_selectedId);

    // Confirm: poll for the device to flip OFF.
    for (var i = 0; i < 5; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      final snap = await FirebaseDatabase.instance
          .ref("appliances/$_selectedId/isOn")
          .get();
      if (snap.value != true) {
        setState(() {
          _statusLine =
              "Auto-cut engaged. ${profile.name} is now OFF — power removed for safety.";
          _simulating = false;
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _statusLine =
          "Detector ran but the device didn't cut — please send the logs and we'll diagnose.";
      _simulating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = DeviceProfileService.of(_selectedId);
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _hero(),
          const SizedBox(height: 16),
          _devicePicker(),
          const SizedBox(height: 16),
          _liveCard(profile),
          const SizedBox(height: 16),
          _actionButtons(profile),
          if (_statusLine != null) ...[
            const SizedBox(height: 16),
            _statusBox(_statusLine!),
          ],
          const SizedBox(height: 24),
          _howItWorks(),
        ],
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF154F73), Color(0xFF0E2E45)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.25),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(_icon, color: Colors.white, size: 38),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  "Auto-cut linked",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _description,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _devicePicker() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Step 1 — pick a device",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: DeviceProfileService.all().map((p) {
              final on = p.id == _selectedId;
              return ChoiceChip(
                label: Text(
                  "${p.name} (${p.currentType})",
                  style: TextStyle(
                    color: on ? Colors.white : _blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                selected: on,
                backgroundColor: _blue.withOpacity(0.08),
                selectedColor: _blue,
                onSelected: (_) {
                  if (_simulating) return;
                  setState(() {
                    _selectedId = p.id;
                    _statusLine = null;
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _liveCard(DeviceProfile? profile) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance
            .ref("appliances/$_selectedId")
            .onValue,
        builder: (ctx, snap) {
          final m = (snap.data?.snapshot.value as Map?) ?? const {};
          final isOn = m["isOn"] == true;
          final v = _toD(m["voltage"]);
          final i = _toD(m["current"]);
          final p = _toD(m["power"]);
          final l = _toD(m["currentLeakage"]);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (ctx, _) => Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: isOn
                            ? _green.withOpacity(0.5 + 0.5 * _pulse.value)
                            : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOn ? "LIVE READINGS" : "DEVICE OFF",
                    style: TextStyle(
                      color: isOn ? _green : Colors.grey.shade600,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  if (profile != null)
                    Text(
                      "${profile.currentType} · ${profile.nominalVoltage.toStringAsFixed(0)} V nominal",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _bigTile("VOLTAGE", v.toStringAsFixed(2), "V")),
                  const SizedBox(width: 8),
                  Expanded(child: _bigTile("CURRENT", i.toStringAsFixed(3), "A")),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _bigTile("POWER", p.toStringAsFixed(1), "W")),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _bigTile(
                      "LEAKAGE",
                      l.toStringAsFixed(3),
                      "A",
                      highlight:
                          (profile != null && l > profile.safeLeakageMax),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _actionButtons(DeviceProfile? profile) {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance
          .ref("appliances/$_selectedId/isOn")
          .onValue,
      builder: (ctx, snap) {
        final isOn = snap.data?.snapshot.value == true;
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: _cardDeco(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Step 2 — control",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isOn ? _blue : _green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _simulating
                          ? null
                          : () => _toggleDevice(!isOn),
                      icon: Icon(
                        isOn ? Icons.power_off_rounded : Icons.power_rounded,
                      ),
                      label: Text(isOn ? "Turn OFF" : "Turn ON"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _danger,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: (!isOn || _simulating) ? null : _trigger,
                      icon: Icon(
                        widget.mode == SafetyMode.surge
                            ? Icons.flash_on_rounded
                            : Icons.water_drop_rounded,
                      ),
                      label: Text(_simulating
                          ? "Simulating…"
                          : widget.mode == SafetyMode.surge
                              ? "Simulate Surge"
                              : "Simulate Leakage"),
                    ),
                  ),
                ],
              ),
              if (profile != null) ...[
                const SizedBox(height: 10),
                Text(
                  "Safe band: ${profile.safeVoltageMin.toStringAsFixed(0)}–${profile.safeVoltageMax.toStringAsFixed(0)} V"
                  " · max current ${profile.safeCurrentMax.toStringAsFixed(2)} A"
                  " · max leakage ${profile.safeLeakageMax.toStringAsFixed(2)} A",
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 11.5),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statusBox(String text) {
    final isCut = text.toLowerCase().contains("auto-cut");
    final color = isCut ? _green : _danger;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(
            isCut
                ? Icons.shield_rounded
                : Icons.warning_amber_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _howItWorks() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "How this module works",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            "Voltage spikes and insulation leakage cannot be reproduced "
            "safely on real hardware — they are natural electrical "
            "events. This screen drives the firmware into the same "
            "out-of-band state through Firebase, so the auto-cut "
            "module reacts identically to how it would on a real "
            "fault: detect → announce → kill power.",
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigTile(String label, String value, String unit,
      {bool highlight = false}) {
    final color = highlight ? _danger : _blue;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Container(
        key: ValueKey(value),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 10.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    color: color.withOpacity(0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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

  static double _toD(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
