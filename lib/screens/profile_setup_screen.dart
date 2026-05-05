// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/device_model.dart';
import '../models/user_profile.dart';
import '../services/user_profile_service.dart';

/// =========================================================
/// PROFILE SETUP SCREEN
/// =========================================================
/// Collects the rich personal context the agent uses. Shown
/// once, after signup or first dashboard load when no
/// profile exists yet.
class ProfileSetupScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const ProfileSetupScreen({super.key, required this.onComplete});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  static const Color _blue = Color(0xFF154F73);

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _occupation = TextEditingController();
  final _addressHint = TextEditingController();

  String _room = "";
  String _sleepStart = "23:00";
  String _sleepEnd = "07:00";
  String _climate = "normal";
  String _tone = "professional";
  final Set<String> _healthFlags = {};
  final Set<String> _ownedDeviceIds = {};

  List<DeviceModel> _devices = [];
  bool _loadingDevices = true;
  bool _saving = false;

  static const _climateOptions = [
    "very heat-sensitive",
    "normal",
    "cold-sensitive",
  ];
  static const _toneOptions = ["professional", "friendly", "concise"];
  static const _healthOptions = [
    "asthma",
    "allergy to dust",
    "heart condition",
    "elderly",
    "infant in home",
  ];

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final snap = await FirebaseDatabase.instance.ref("appliances").get();
    final raw = snap.value;
    final out = <DeviceModel>[];
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final v = raw[i];
        if (v is Map) {
          try {
            out.add(DeviceModel.fromMap(v, i.toString()));
          } catch (_) {}
        }
      }
    } else if (raw is Map) {
      raw.forEach((k, v) {
        if (v is Map) {
          try {
            out.add(DeviceModel.fromMap(v, k.toString()));
          } catch (_) {}
        }
      });
    }
    if (!mounted) return;
    setState(() {
      _devices = out;
      _loadingDevices = false;
    });
  }

  Future<void> _pickTime(bool start) async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: now,
    );
    if (picked == null) return;
    final s =
        "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
    setState(() {
      if (start) {
        _sleepStart = s;
      } else {
        _sleepEnd = s;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_room.trim().isEmpty) {
      _toast("Pick a room you live in.");
      return;
    }
    if (_ownedDeviceIds.isEmpty) {
      _toast("Select at least one device the agent should manage.");
      return;
    }

    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final profile = UserProfile(
      uid: uid,
      fullName: _name.text.trim(),
      age: int.tryParse(_age.text.trim()) ?? 0,
      occupation: _occupation.text.trim(),
      room: _room.trim(),
      sleepStart: _sleepStart,
      sleepEnd: _sleepEnd,
      climateSensitivity: _climate,
      healthFlags: _healthFlags.toList(),
      preferredTone: _tone,
      ownedDeviceIds: _ownedDeviceIds.toList(),
      homeAddressHint: _addressHint.text.trim(),
      createdAt: DateTime.now().toIso8601String(),
    );

    try {
      await UserProfileService.save(profile);
    } catch (e) {
      _toast("Save failed: $e");
      setState(() => _saving = false);
      return;
    }

    if (!mounted) return;
    widget.onComplete();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFF154F73), Color(0xFF0E2E45)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Tell SHAPEOS about you",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "The agent uses this to personalise every action it takes.",
                  style: TextStyle(color: Colors.white.withOpacity(0.75)),
                ),
                const SizedBox(height: 20),
                _txt(_name, "Full name",
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? "Required" : null),
                _txt(_age, "Age",
                    keyboard: TextInputType.number,
                    validator: (v) => (int.tryParse(v ?? "") == null)
                        ? "Number"
                        : null),
                _txt(_occupation, "Occupation"),
                _txt(_addressHint,
                    "Address hint (optional, helps the agent)"),
                const SizedBox(height: 12),
                _label("Room you live in"),
                _roomPicker(),
                const SizedBox(height: 16),
                _label("Devices the agent manages for you"),
                _deviceList(),
                const SizedBox(height: 16),
                _label("Sleep schedule"),
                Row(
                  children: [
                    Expanded(
                      child: _timeButton("Sleep at $_sleepStart",
                          () => _pickTime(true)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _timeButton("Wake at $_sleepEnd",
                          () => _pickTime(false)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _label("Climate sensitivity"),
                _chipPicker(_climateOptions, _climate, (v) {
                  setState(() => _climate = v);
                }),
                const SizedBox(height: 16),
                _label("Health considerations"),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _healthOptions.map((h) {
                    final on = _healthFlags.contains(h);
                    return FilterChip(
                      backgroundColor: Colors.white.withOpacity(0.1),
                      selectedColor: Colors.white,
                      label: Text(h,
                          style: TextStyle(
                              color: on ? _blue : Colors.white)),
                      selected: on,
                      onSelected: (v) => setState(
                          () => v ? _healthFlags.add(h) : _healthFlags.remove(h)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                _label("How should the agent talk to you?"),
                _chipPicker(_toneOptions, _tone, (v) {
                  setState(() => _tone = v);
                }),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _blue,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text("Activate Agent",
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- UI helpers ----------
  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontWeight: FontWeight.w600)),
      );

  Widget _txt(TextEditingController c, String hint,
      {TextInputType? keyboard,
      String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
          filled: true,
          fillColor: Colors.white.withOpacity(0.08),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _timeButton(String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.1),
        foregroundColor: Colors.white,
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label),
    );
  }

  Widget _chipPicker(List<String> options, String selected,
      void Function(String) onPick) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: options.map((o) {
        final on = o == selected;
        return ChoiceChip(
          label: Text(o, style: TextStyle(color: on ? _blue : Colors.white)),
          selected: on,
          backgroundColor: Colors.white.withOpacity(0.1),
          selectedColor: Colors.white,
          onSelected: (_) => onPick(o),
        );
      }).toList(),
    );
  }

  Widget _roomPicker() {
    final preset = const ["Bedroom", "Living Room", "Kitchen", "Lounge", "Office"];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: preset.map((r) {
        final on = r == _room;
        return ChoiceChip(
          label: Text(r, style: TextStyle(color: on ? _blue : Colors.white)),
          selected: on,
          backgroundColor: Colors.white.withOpacity(0.1),
          selectedColor: Colors.white,
          onSelected: (_) => setState(() => _room = r),
        );
      }).toList(),
    );
  }

  Widget _deviceList() {
    if (_loadingDevices) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
            child:
                CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
      );
    }
    if (_devices.isEmpty) {
      return Text("No devices found in Firebase.",
          style: TextStyle(color: Colors.white.withOpacity(0.7)));
    }
    return Column(
      children: _devices.map((d) {
        final on = _ownedDeviceIds.contains(d.id);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: on
                ? Colors.white.withOpacity(0.18)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: CheckboxListTile(
            value: on,
            activeColor: Colors.white,
            checkColor: _blue,
            title: Text(d.name,
                style: const TextStyle(color: Colors.white)),
            subtitle: Text(d.type,
                style: TextStyle(color: Colors.white.withOpacity(0.6))),
            onChanged: (v) => setState(() {
              if (v == true) {
                _ownedDeviceIds.add(d.id);
              } else {
                _ownedDeviceIds.remove(d.id);
              }
            }),
          ),
        );
      }).toList(),
    );
  }
}
