// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../models/device_model.dart';
import '../widgets/overview_tab.dart';
import '../widgets/control_tab.dart';
import '../widgets/energy_tab.dart';
import '../widgets/security_tab.dart';
import '../widgets/logs_tab.dart';
import '../widgets/voice_tab.dart';
import '../widgets/ai_monitor_tab.dart';

import '../services/device_monitor_service.dart';
import '../services/voice_service.dart';
class InitialSetupDialog extends StatefulWidget {

  const InitialSetupDialog({super.key});

  @override
  State<InitialSetupDialog> createState() =>
      _InitialSetupDialogState();
      
}

class _InitialSetupDialogState extends State<InitialSetupDialog> {

  List<String> rooms = [];
  List<String> selectedDeviceIds = [];
List<DeviceModel> devices = [];
bool loadingDevices = true;
  final TextEditingController roomController =
      TextEditingController();

  bool roomError = false;
  bool deviceError = false;
@override
void initState() {
  super.initState();
  _loadDevices();
}

Future<void> _loadDevices() async {
  final snapshot = await FirebaseDatabase.instance
      .ref("appliances")
      .get();

  final rawData = snapshot.value;
  final List<DeviceModel> temp = [];

  if (rawData is List) {
    for (int i = 0; i < rawData.length; i++) {
      final value = rawData[i];
      if (value is Map) {
        temp.add(DeviceModel.fromMap(value, i.toString()));
      }
    }
  } else if (rawData is Map) {
    rawData.forEach((key, value) {
      if (value is Map) {
        temp.add(DeviceModel.fromMap(value, key));
      }
    });
  }

  if (!mounted) return;

  setState(() {
    devices = temp;
    loadingDevices = false;
  });
}
  void _addRoom() {
    if (roomController.text.trim().isEmpty) return;

    if (rooms.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Maximum 5 rooms allowed"),
        ),
      );
      return;
    }

    setState(() {
      rooms.add(roomController.text.trim());
      roomController.clear();
      roomError = false;
    });
  }

  Future<void> _submit() async {
    setState(() {
      roomError = rooms.isEmpty;
      deviceError = selectedDeviceIds.isEmpty;
    });

    if (rooms.isEmpty || selectedDeviceIds.isEmpty) return;

    final uid =
        FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .update({
      "rooms": rooms,
      "selectedDevices": selectedDeviceIds,
      "firstLoginCompleted": true,
    });

    if (!mounted) return;
    Navigator.pop(context);
  }

@override
Widget build(BuildContext context) {
  return Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(12),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            Color(0xFF154F73),
            Color(0xFF0E2E45),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 30,
            spreadRadius: 2,
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// HEADER
              const Text(
                "Initial Smart Setup",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                "Configure your environment to continue",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                ),
              ),

              const SizedBox(height: 28),

              /// ROOM SECTION
              const Text(
                "Rooms (Max 5)",
                style: TextStyle(
                    color: Colors.white70),
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: roomController,
                      style:
                          const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Add room name",
                        hintStyle: TextStyle(
                            color:
                                Colors.white54),
                        filled: true,
                        fillColor:
                            Colors.white.withOpacity(0.08),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                          borderSide:
                              BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Colors.white,
                      foregroundColor:
                          Color(0xFF154F73),
                    ),
                    onPressed: _addRoom,
                    child: const Text("Add"),
                  )
                ],
              ),

              const SizedBox(height: 12),

           Wrap(
  spacing: 8,
  children: rooms.map((r) {
    return Chip(
      backgroundColor: Colors.white,
      label: Text(
        r,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w600,
        ),
      ),
      deleteIconColor: Colors.black,
      onDeleted: () {
        setState(() {
          rooms.remove(r);
        });
      },
    );
  }).toList(),
),

              if (roomError)
                const Padding(
                  padding:
                      EdgeInsets.only(top: 6),
                  child: Text(
                    "Add at least one room",
                    style:
                        TextStyle(color: Colors.redAccent),
                  ),
                ),

              const SizedBox(height: 30),

            /// DEVICES SECTION
const Text(
  "Select Devices",
  style: TextStyle(color: Colors.white70),
),

const SizedBox(height: 12),

StreamBuilder<DatabaseEvent>(
  stream: FirebaseDatabase.instance
.ref("appliances").onValue,
  builder: (context, snapshot) {

    // 🔄 Loading
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    // ❌ No Data
    if (!snapshot.hasData ||
        snapshot.data!.snapshot.value == null) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          "No devices found",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

   final rawData = snapshot.data!.snapshot.value;

List<DeviceModel> devices = [];

if (rawData is List) {
  for (int i = 0; i < rawData.length; i++) {
    final value = rawData[i];
    if (value is Map) {
      devices.add(DeviceModel.fromMap(value, i.toString()));
    }
  }
} 
else if (rawData is Map) {
  rawData.forEach((key, value) {
    if (value is Map) {
      devices.add(DeviceModel.fromMap(value, key));
    }
  });
}

    if (devices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          "No valid devices available",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return Column(
      children: devices.map((d) {

        final selected =
            selectedDeviceIds.contains(d.id);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? Colors.white.withOpacity(0.15)
                : Colors.white.withOpacity(0.05),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage:
                  AssetImage(_imageFor(d.type)),
            ),
            title: Text(
              d.name,
              style: const TextStyle(
                color: Colors.white,
              ),
            ),
            trailing: Checkbox(
              value: selected,
              activeColor: Colors.white,
              checkColor: const Color(0xFF154F73),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    selectedDeviceIds.add(d.id);
                  } else {
                    selectedDeviceIds.remove(d.id);
                  }
                  deviceError = false;
                });
              },
            ),
          ),
        );
      }).toList(),
    );
  },
),

if (deviceError)
  const Padding(
    padding: EdgeInsets.only(top: 8),
    child: Text(
      "Select at least one device",
      style: TextStyle(color: Colors.redAccent),
    ),
  ),

const SizedBox(height: 30),

/// BUTTON
SizedBox(
  width: double.infinity,
  height: 52,
  child: ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF154F73),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    onPressed: _submit,
    child: const Text(
      "Complete Setup",
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
),

            ],
          ),
        ),
      ),
    ),
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
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

late DatabaseReference _dbRef;
  List<DeviceModel> appliancesList = [];

  final List<String> _titles = [
    "Home",
    "Control",
    "AI Monitor",
    "Energy Analytics",
    "Security",
    "Logs",
    "Voice Control",
  ];

  @override
void initState() {
  super.initState();

  final uid = FirebaseAuth.instance.currentUser!.uid;

_dbRef = FirebaseDatabase.instance
    .ref("appliances");

  _listenToRealtimeDB();
  _ensureTodayEnergyDoc();
  _startGlobalMonitoring();
    _checkFirstLogin();

}


Future<void> _checkFirstLogin() async {
  final uid = FirebaseAuth.instance.currentUser!.uid;

  final doc = await FirebaseFirestore.instance
      .collection("users")
      .doc(uid)
      .get();

  final firstDone =
      doc.data()?['firstLoginCompleted'] ?? false;

  if (!firstDone) {
    Future.delayed(Duration.zero, () {
_showSetupPopup();  });
  }
}
void _showSetupPopup() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const InitialSetupDialog(),
  );
}


  // ───────────────── ENERGY DOC INIT ─────────────────

  Future<void> _ensureTodayEnergyDoc() async {
    try {
      final now = DateTime.now();
      final dateId =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      final ref = FirebaseFirestore.instance
          .collection("energy_daily")
          .doc(dateId);

      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set({
          "date": dateId,
          "day": _dayName(now.weekday),
          "hourlyUsage": {},
          "devices": {},
          "totalEnergy": 0.0,
          "suggestions": ["Energy data collection started"],
          "createdAt": FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint("Energy init failed: $e");
    }
  }

  String _dayName(int d) {
    const days = [
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
      "Sunday"
    ];
    return days[d - 1];
  }

  // ───────────────── GLOBAL AI MONITOR ─────────────────

  void _startGlobalMonitoring() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 10));

      if (!mounted) return false;

      for (final d in appliancesList) {
        final result = DeviceMonitorService.check(d.id);

        if (result.hasAlert) {
          VoiceService.speak(result.message);
          _showMonitorPopup(d, result.message);

          if (result.autoOff) {
            _toggleDevice(d, source: "AI Monitor");
          }
        }
      }
      return mounted;
    });
  }

  void _showMonitorPopup(DeviceModel d, String msg) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        });

        return AlertDialog(
          title: const Text("Device Alert"),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Ignore"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _toggleDevice(d, source: "AI Monitor");
              },
              child: const Text("Turn OFF"),
            ),
          ],
        );
      },
    );
  }

  // ───────────────── RTDB LISTENER ─────────────────
void _listenToRealtimeDB() {
  final uid = FirebaseAuth.instance.currentUser!.uid;

  // 🔥 Listen Firestore selectedDevices changes
  FirebaseFirestore.instance
      .collection("users")
      .doc(uid)
      .snapshots()
      .listen((userSnap) {

    final selectedIds =
        List<String>.from(userSnap.data()?['selectedDevices'] ?? []);

    // 🔥 Listen RTDB appliances
    _dbRef.onValue.listen((event) {
      final snapshot = event.snapshot.value;
      final List<DeviceModel> allDevices = [];

      if (snapshot is List) {
        for (int i = 0; i < snapshot.length; i++) {
          final value = snapshot[i];
          if (value is Map) {
            allDevices.add(
              DeviceModel.fromMap(value, i.toString()),
            );
          }
        }
      } else if (snapshot is Map) {
        snapshot.forEach((key, value) {
          if (value is Map) {
            allDevices.add(
              DeviceModel.fromMap(value, key),
            );
          }
        });
      }

      final filtered = allDevices
          .where((d) => selectedIds.contains(d.id))
          .toList();

      if (!mounted) return;

      setState(() {
        appliancesList = filtered;
      });
    });
  });
}

  // ───────────────── DEVICE TOGGLE ─────────────────

  Future<void> _toggleDevice(
    DeviceModel device, {
    required String source,
  }) async {
    final newState = !device.isOn;

    await _dbRef.child(device.id).update({
      'isOn': newState,
    });

   final uid = FirebaseAuth.instance.currentUser!.uid;

FirebaseDatabase.instance
    .ref("users/$uid/logs")
    .push()
    .set({
      "event":
          "${device.name} turned ${newState ? "ON" : "OFF"} via $source",
      "time": DateTime.now().toString(),
    });
  }

  // ───────────────── SIGN OUT ─────────────────

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Sign Out"),
        content:
            const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Logout"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      context.go('/login');
    }
  }

  // ───────────────── UI ─────────────────

  @override
  Widget build(BuildContext context) {
    final tabs = [
      OverviewTab(
        appliances: appliancesList,
        onDeviceTap: (d) =>
            context.push('/dashboard/device-detail', extra: d),
      ),
      ControlTab(
        appliances: appliancesList,
        onToggle: (d) => _toggleDevice(d, source: "App"),
      ),
      AIMonitorTab(appliances: appliancesList),
      const EnergyTab(), // ✅ CORRECT
      SecurityTab(),
      const LogsTab(),
      VoiceTab(
        appliances: appliancesList,
        onToggle: (d) => _toggleDevice(d, source: "Voice"),
      ),
    ];

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
   appBar: PreferredSize(
  preferredSize: const Size.fromHeight(64),
  child: AppBar(
    elevation: 0,
    backgroundColor: const Color(0xFF154F73),
    centerTitle: false,
    titleSpacing: 20,
    automaticallyImplyLeading: false,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _titles[_currentIndex],
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          "Smart Home Dashboard",
          style: TextStyle(
            fontSize: 12,
            color: Colors.white70,
            letterSpacing: 0.2,
          ),
        ),
      ],
    ),
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: IconButton(
          tooltip: "Logout",
          icon: const Icon(Icons.logout_rounded),
          color: Colors.white,
          onPressed: _signOut,
        ),
      ),
    ],
  ),
),

        body: tabs[_currentIndex],
        bottomNavigationBar: TelenorBottomNav(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
        ),
      ),
    );
  }
}

////////////////////////////////////////////////////////////////
/// 🔥 TELENOR STYLE CUSTOM BOTTOM NAV BAR
////////////////////////////////////////////////////////////////

class TelenorBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  static const Color primaryBlue = Color(0xFF154F73);

  const TelenorBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });
@override
Widget build(BuildContext context) {
  return SafeArea(
    top: false,
    child: SizedBox(
      height: 78,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 18,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _navItem(icon: Icons.home_rounded, label: "Home", index: 0),
            _navItem(icon: Icons.settings_rounded, label: "Control", index: 1),
            _navItem(icon: Icons.psychology_rounded, label: "AI", index: 2),
            _navItem(icon: Icons.show_chart_rounded, label: "Energy", index: 3),
            _navItem(icon: Icons.security_rounded, label: "Security", index: 4),
            _navItem(icon: Icons.history_rounded, label: "Logs", index: 5),
            _navItem(icon: Icons.mic_rounded, label: "Voice", index: 6),
          ],
        ),
      ),
    ),
  );
}


  // 🔹 PROFESSIONAL NAV ITEM
  Widget _navItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final bool active = currentIndex == index;

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: active ? 24 : 22,
              color: active
                  ? primaryBlue
                  : Colors.grey.withOpacity(0.55),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.2,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.w400,
                color: active
                    ? primaryBlue
                    : Colors.grey.withOpacity(0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

