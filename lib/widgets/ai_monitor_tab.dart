// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:ui';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/device_model.dart';
import 'package:flutter_tts/flutter_tts.dart';

class AIMonitorTab extends StatefulWidget {
  final List<DeviceModel> appliances;
  const AIMonitorTab({super.key, required this.appliances});

  @override
  State<AIMonitorTab> createState() => _AIMonitorTabState();
}

class _AIMonitorTabState extends State<AIMonitorTab> {
  static const Color primaryBlue = Color(0xFF154F73);


  final CollectionReference _rulesRef =
      FirebaseFirestore.instance.collection('monitoring_rules');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _rulesRef.snapshots(),
      builder: (context, snapshot) {
        final rules = snapshot.data?.docs ?? [];

        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
              children: [
                const Text(
                  "AI Device Monitor",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Smart usage rules & automated protection",
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),

                if (rules.isEmpty)
                  _EmptyState(onAdd: _openAddRuleDialog),

                ...rules.map(
                  (doc) => _RuleDeviceCard(
                    docId: doc.id,
                    data: doc.data() as Map<String, dynamic>,
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),

            Positioned(
              right: 16,
              bottom: 20,
              child: FloatingActionButton.extended(
                backgroundColor: primaryBlue,
                onPressed: _openAddRuleDialog,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  "Add Rule",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ================= ADD RULE =================
  void _openAddRuleDialog() {
    DeviceModel? selected;
    int time = 10;
    String unit = "minutes";

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Add AI Monitoring Rule"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<DeviceModel>(
                  hint: const Text("Select Device"),
                  value: selected,
                  items: widget.appliances.map((d) {
                    return DropdownMenuItem(
                      value: d,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundImage: AssetImage(_imageFor(d.type)),
                          ),
                          const SizedBox(width: 10),
                          Text(d.name),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => selected = v),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: "Time"),
                        onChanged: (v) =>
                            time = int.tryParse(v) ?? time,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: unit,
                        items: const [
                          DropdownMenuItem(
                              value: "seconds", child: Text("Seconds")),
                          DropdownMenuItem(
                              value: "minutes", child: Text("Minutes")),
                          DropdownMenuItem(
                              value: "hours", child: Text("Hours")),
                        ],
                        onChanged: (v) => unit = v!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: selected == null
                    ? null
                    : () async {
                        await _rulesRef.add({
                          "deviceId": selected!.id,
                          "deviceName": selected!.name,
                          "deviceType":
                              selected!.type.toLowerCase().trim(),
                          "maxTime": time,
                          "unit": unit,
                          "createdAt": FieldValue.serverTimestamp(),
                          "lastActive": null,
                        });
                        Navigator.pop(context);
                      },
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }

  String _imageFor(String type) {
    switch (type.toLowerCase().trim()) {
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

// ================= RULE CARD (LIVE TIMER) =================
class _RuleDeviceCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;

  const _RuleDeviceCard({
    required this.data,
    required this.docId,
  });

  @override
  State<_RuleDeviceCard> createState() => _RuleDeviceCardState();
}

class _RuleDeviceCardState extends State<_RuleDeviceCard> {
  static const Color primaryBlue = Color(0xFF154F73);

  Timer? _timer;
  Duration _elapsed = Duration.zero;

  final FlutterTts _tts = FlutterTts();

  int _alertCount = 0;
  DateTime? _lastAlertTime;
  bool _autoShutdownDone = false;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage("en-US");
    _tts.setSpeechRate(0.45);
    _tts.setPitch(1.0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ================= TIMER =================
  void _startTicker(Timestamp? lastActive) {
    _timer?.cancel();

    if (lastActive == null) {
      setState(() {
        _elapsed = Duration.zero;
        _alertCount = 0;
        _autoShutdownDone = false;
      });
      return;
    }

    final start = lastActive.toDate();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        final diff = DateTime.now().difference(start);
        _elapsed = diff.isNegative ? Duration.zero : diff;
      });
    });
  }

  // ================= AI EXCEEDED =================
  Future<void> _handleExceeded(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    if (_autoShutdownDone) return;

    final now = DateTime.now();

    if (_lastAlertTime != null &&
        now.difference(_lastAlertTime!) < const Duration(seconds: 10)) {
      return;
    }

    _lastAlertTime = now;

    if (_alertCount >= 3) {
      _autoShutdownDone = true;
      await _forceShutdown(data);
      return;
    }

    _alertCount++;

    final deviceName = data["deviceName"];
    await _tts.speak("$deviceName has exceeded its usage time");

    if (!mounted) return;

    bool closed = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Timer(const Duration(seconds: 10), () {
          if (!closed && Navigator.canPop(ctx)) {
            closed = true;
            Navigator.pop(ctx);
          }
        });

        return AlertDialog(
          title: const Text("Usage Limit Exceeded"),
          content: Text("$deviceName is running too long."),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                if (closed) return;
                closed = true;
                Navigator.pop(ctx);
                _autoShutdownDone = true;
                await _forceShutdown(data);
              },
              child: const Text("Turn Off"),
            ),
          ],
        );
      },
    );
  }

Future<void> _forceShutdown(Map<String, dynamic> data) async {
  final deviceId = data["deviceId"];
  final deviceName = data["deviceName"];

  // 🔊 Voice
  await _tts.speak("$deviceName turned off");

  // 🔥 TURN OFF REAL DEVICE (RTDB)
  await FirebaseDatabase.instance
      .ref("appliances/$deviceId")
      .update({"isOn": false});

  // 🔁 RESET AI STATE
  await FirebaseFirestore.instance
      .collection("monitoring_rules")
      .doc(widget.docId)
      .update({
        "lastActive": null,
        "forceOff": false,
      });
}

  // ================= HELPERS =================
  Duration _maxDuration(int value, String unit) {
    switch (unit) {
      case "seconds":
        return Duration(seconds: value);
      case "hours":
        return Duration(hours: value);
      default:
        return Duration(minutes: value);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  String _imageFor(String type) {
    switch (type.toLowerCase().trim()) {
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

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("monitoring_rules")
          .doc(widget.docId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        final data = snapshot.data!.data() as Map<String, dynamic>;

        final deviceName = data["deviceName"] ?? "Unknown";
        final deviceType = data["deviceType"] ?? "default";
        final unit = data["unit"] ?? "minutes";
        final maxTime = data["maxTime"] ?? 0;
        final Timestamp? lastActive = data["lastActive"];

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startTicker(lastActive);
        });

        final maxDuration = _maxDuration(maxTime, unit);
        final exceeded =
            lastActive != null && _elapsed >= maxDuration;

        if (exceeded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handleExceeded(context, data);
          });
        }

        final timerText = lastActive == null
            ? "Idle"
            : exceeded
                ? "Exceeded ${_fmt(_elapsed)}"
                : "Left ${_fmt(maxDuration - _elapsed)}";

        final timerIcon =
            exceeded ? Icons.warning : Icons.timer;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryBlue.withOpacity(0.92),
                      primaryBlue.withOpacity(0.65),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white24),
                ),
           child: Stack(
  children: [
    Row(
      children: [
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.15),
            border: Border.all(color: Colors.white24),
          ),
          child: ClipOval(
            child: Image.asset(
              _imageFor(deviceType),
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                deviceName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      timerIcon,
                      size: 14,
                      color: exceeded
                          ? Colors.redAccent
                          : Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      timerText,
                      style: TextStyle(
                        color: exceeded
                            ? Colors.redAccent
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),

    // ✏️ EDIT BUTTON
    Positioned(
      top: -6,
      right: 36,
      child: IconButton(
        icon: const Icon(Icons.edit, size: 18),
        color: Colors.white70,
        onPressed: () => _openEditRuleDialog(context, data),
      ),
    ),

    // 🗑 DELETE BUTTON
    Positioned(
      top: -6,
      right: -6,
      child: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        color: Colors.redAccent,
        onPressed: () => _deleteRule(context),
      ),
    ),
  ],
),

              ),
            ),
          ),
        );
      },
    );
  }

void _openEditRuleDialog(
  BuildContext context,
  Map<String, dynamic> data,
) {
  int time = data["maxTime"];
  String unit = data["unit"];

  showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: const Text("Edit AI Rule"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data["deviceName"],
                style: const TextStyle(
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: "Time"),
                controller: TextEditingController(
                  text: time.toString(),
                ),
                onChanged: (v) =>
                    time = int.tryParse(v) ?? time,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: unit,
                items: const [
                  DropdownMenuItem(
                      value: "seconds",
                      child: Text("Seconds")),
                  DropdownMenuItem(
                      value: "minutes",
                      child: Text("Minutes")),
                  DropdownMenuItem(
                      value: "hours",
                      child: Text("Hours")),
                ],
                onChanged: (v) => unit = v!,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection("monitoring_rules")
                    .doc(widget.docId)
                    .update({
                  "maxTime": time,
                  "unit": unit,
                });
                Navigator.pop(context);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    ),
  );
}
Future<void> _deleteRule(BuildContext context) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Delete Rule"),
      content: const Text(
          "Are you sure you want to delete this AI rule?"),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, false),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red),
          onPressed: () =>
              Navigator.pop(context, true),
          child: const Text("Delete"),
        ),
      ],
    ),
  );

  if (confirm == true) {
    await FirebaseFirestore.instance
        .collection("monitoring_rules")
        .doc(widget.docId)
        .delete();
  }
}

}

// ================= EMPTY =================
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 60),
        const Icon(Icons.psychology,
            size: 70, color: Colors.white54),
        const SizedBox(height: 14),
        const Text(
          "No AI rules configured",
          style: TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text("Add Device Rule"),
        ),
      ],
    );
  }
}
