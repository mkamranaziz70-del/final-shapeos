// ignore_for_file: unused_field, deprecated_member_use

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../models/device_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/energy_logger.dart';
class ControlTab extends StatefulWidget {
  final List<DeviceModel> appliances;
  final void Function(DeviceModel device) onToggle;

  const ControlTab({
    super.key,
    required this.appliances,
    required this.onToggle,
  });

  @override
  State<ControlTab> createState() => _ControlTabState();
}

class _ControlTabState extends State<ControlTab>
    with AutomaticKeepAliveClientMixin {
  static const Color primaryBlue = Color(0xFF154F73);

  late Map<String, bool> _states;
  late stt.SpeechToText _speech;
  final FlutterTts _tts = FlutterTts();
  bool _listening = false;
StreamSubscription? _applianceSub;
Timer? _energyTimer;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
_states = {
  for (var d in widget.appliances) d.id: d.isOn
};

_applianceSub = FirebaseFirestore.instance
    .collection("appliances")
    .snapshots()
    .listen((snapshot) {
  for (final doc in snapshot.docs) {
    final id = doc.id;
    final isOn = doc["isOn"] as bool;

    if (_states[id] != isOn) {
      setState(() {
        _states[id] = isOn;
      });
    }
  }
});

    _tts.setLanguage("en-US");
    _tts.setVolume(1.0);
    _tts.setSpeechRate(0.42);
    _tts.setPitch(1.1);
    _energyTimer = Timer.periodic(const Duration(minutes: 1), (_) {
  for (final d in widget.appliances) {
    final isOn = _states[d.id] ?? d.isOn;

    if (isOn && d.power > 0) {
      EnergyLogger.logEnergy(
        deviceId: d.id,
        deviceName: d.name,
        power: d.power,
      );
    }
  }
});

  }

Future<void> _syncAiTimer(DeviceModel device, bool isOn) async {
  final rules = await FirebaseFirestore.instance
      .collection('monitoring_rules')
      .where('deviceId', isEqualTo: device.id)
      .get();

  for (final doc in rules.docs) {
    await doc.reference.update({
"lastActive": isOn ? Timestamp.now() : null,
    });
  }
}




 @override
void didUpdateWidget(covariant ControlTab oldWidget) {
  super.didUpdateWidget(oldWidget);

  // ONLY update state for devices that are NEW
  for (final d in widget.appliances) {
    _states.putIfAbsent(d.id, () => d.isOn);
  }
}


  @override
  bool get wantKeepAlive => true;

Future<void> _toggle(DeviceModel d, bool v) async {
  if (!mounted) return;

  // 1️⃣ Update UI immediately
  setState(() {
    _states[d.id] = v;
  });

  // 2️⃣ Update REAL device source (Realtime Database via parent)
  widget.onToggle(d);

  // 3️⃣ Sync AI timer (start / stop)
  await _syncAiTimer(d, v);


  // 4️⃣ Voice feedback
  final name = d.name.isNotEmpty ? d.name : d.type;
  await _tts.speak(v ? "$name turned on" : "$name turned off");
}




@override
void dispose() {
  _energyTimer?.cancel();
  _applianceSub?.cancel();
  super.dispose();
}



  Future<void> _listen(DeviceModel d) async {
    if (!await _speech.initialize()) return;

    setState(() => _listening = true);

    _speech.listen(onResult: (r) {
      final cmd = r.recognizedWords.toLowerCase();
      final isOn = _states[d.id] ?? d.isOn;

      if (cmd.contains(d.name.toLowerCase())) {
        if (cmd.contains("on") && !isOn) _toggle(d, true);
        if (cmd.contains("off") && isOn) _toggle(d, false);
      }

      _speech.stop();
      setState(() => _listening = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.appliances.isEmpty) {
      return const Center(child: Text("No devices"));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: widget.appliances.length,
      itemBuilder: (context, i) {
        final d = widget.appliances[i];
        final on = _states[d.id] ?? d.isOn;

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: _AppleStyleDeviceCard(
            device: d,
            isOn: on,
            image: _imageFor(d.type),
            listening: _listening,
            onToggle: (v) => _toggle(d, v),
            onVoice: () => _listen(d),
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
/// 🍎 APPLE-STYLE LARGE DEVICE CARD (JPG-SAFE)
////////////////////////////////////////////////////////////

class _AppleStyleDeviceCard extends StatelessWidget {
  final DeviceModel device;
  final bool isOn;
  final String image;
  final bool listening;
  final ValueChanged<bool> onToggle;
  final VoidCallback onVoice;

  static const Color primaryBlue = Color(0xFF154F73);

  const _AppleStyleDeviceCard({
    required this.device,
    required this.isOn,
    required this.image,
    required this.listening,
    required this.onToggle,
    required this.onVoice,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 180,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isOn
                  ? [
                      primaryBlue.withOpacity(0.92),
                      primaryBlue.withOpacity(0.65),
                    ]
                  : [
                      Colors.black.withOpacity(0.45),
                      Colors.black.withOpacity(0.25),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            children: [
              // 🔥 IMAGE MASKING FIX (JPG SAFE)
              ClipOval(
                child: Container(
                  width: 130,
                  height: 130,
                  color: Colors.transparent,
                  child: Image.asset(
                    image,
                    fit: BoxFit.cover, // 🔥 removes white spacing
                  ),
                ),
              ),

              const SizedBox(width: 22),

              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name.isNotEmpty ? device.name : device.type,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            listening ? Icons.mic : Icons.mic_none,
                            color: Colors.white,
                          ),
                          onPressed: onVoice,
                        ),
                        const SizedBox(width: 12),
                        Switch(
                          value: isOn,
                          onChanged: onToggle,
                          activeColor: Colors.white,
                          inactiveThumbColor: Colors.white70,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
