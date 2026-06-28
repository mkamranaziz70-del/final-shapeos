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
import '../widgets/anomalies_tab.dart';
import '../widgets/bills_tab.dart';
import '../widgets/optimization_tab.dart';
import '../widgets/rooms_tab.dart';

import '../services/device_monitor_service.dart';
import '../services/voice_service.dart';
import '../services/location_service.dart';
import '../services/user_profile_service.dart';
import '../services/anomaly_detection_service.dart';
import '../services/agent_automation_engine.dart';
import '../services/agent_mode_service.dart';
import '../services/agent_orchestrator.dart';
import '../services/dashboard_nav_service.dart';
import 'agent_chat_screen.dart';
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
    "Rooms",
    "Optimization",
    "Control",
    "AI Anomalies",
    "Energy Analytics",
    "Bill Splitting",
    "Security",
    "Logs",
    "Voice Control",
    "Agent",
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
  _bootAgent();
  _wireDashboardNav();
}

Future<void> _bootAgent() async {
  // Idempotent — safe to call on every dashboard open.
  await UserProfileService.load();
  await LocationService.start();
  await AgentOrchestrator.start();
  await AgentModeService.boot();
}

/// Listen for cross-tab navigation requests (eg. Energy tab's
/// "View AI Optimization Report" CTA). When a tab is requested
/// we switch and clear the request so it doesn't fire twice.
void _wireDashboardNav() {
  DashboardNavService.requestedTab.addListener(() {
    final idx = DashboardNavService.requestedTab.value;
    if (idx == null) return;
    if (!mounted) return;
    setState(() => _currentIndex = idx);
    DashboardNavService.clear();
  });
}

/// Wraps any tab so it becomes non-interactive while AI mode is
/// on. A small banner explains why and offers a quick switch back.
Widget _aiGuard(Widget child) {
  return ValueListenableBuilder<bool>(
    valueListenable: AgentModeService.isAiMode,
    builder: (ctx, ai, _) {
      if (!ai) return child;
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Opacity(opacity: 0.45, child: child),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 12,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF154F73), Color(0xFF0E2E45)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.smart_toy_rounded,
                        color: Color(0xFF24E0A0)),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "AI Agent is in control. Manual toggles are disabled — talk to the agent or switch back to Manual.",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                            height: 1.3),
                      ),
                    ),
                    TextButton(
                      onPressed: AgentModeService.disableAiMode,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF24E0A0),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text(
                        "MANUAL",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// AppBar toggle: NORMAL  ⇄  AI AGENT.
/// Persists to Firestore + arms/disarms the wake word.
Widget _buildModeToggle() {
  return ValueListenableBuilder<bool>(
    valueListenable: AgentModeService.isAiMode,
    builder: (ctx, ai, _) {
      final color = ai ? const Color(0xFF24E0A0) : Colors.white70;
      final fg = ai ? const Color(0xFF0E2E45) : Colors.white;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () async {
            final nowOn = await AgentModeService.toggle();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 3),
                content: Text(
                  nowOn
                      ? 'AI Agent mode ON — say "hey shapeos" anywhere.'
                      : "Switched to manual control.",
                ),
              ),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: ai ? color : Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: ai ? color : Colors.white.withOpacity(0.4),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ai
                      ? Icons.smart_toy_rounded
                      : Icons.toggle_on_outlined,
                  size: 18,
                  color: fg,
                ),
                const SizedBox(width: 6),
                Text(
                  ai ? "AI" : "Manual",
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}


Future<void> _checkFirstLogin() async {
  // Admin-mode app — no per-user onboarding. The room model
  // (managed in the Rooms tab) replaces user profile + initial
  // device selection. We just preload the profile if it exists
  // for backwards compatibility with the chat agent.
  UserProfileService.load();
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

      // Run the smarter, multi-signal anomaly pass too.
      try {
        await AnomalyDetectionService.evaluate(
          devices: appliancesList,
          motionRecent: true,
        );
      } catch (_) {}

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

    // Tell the smart automation engine that the user (or the
    // app, or AI Monitor) just touched this device, so it
    // honours the 5-minute cooldown and doesn't immediately
    // fight the choice.
    AgentAutomationEngine.registerManualAction(device.id);

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
      const RoomsTab(),
      const OptimizationTab(),
      _aiGuard(
        ControlTab(
          appliances: appliancesList,
          onToggle: (d) => _toggleDevice(d, source: "App"),
        ),
      ),
      const AnomaliesTab(),
      const EnergyTab(),
      const BillsTab(),
      SecurityTab(),
      const LogsTab(),
      _aiGuard(
        VoiceTab(
          appliances: appliancesList,
          onToggle: (d) => _toggleDevice(d, source: "Voice"),
        ),
      ),
      const AgentChatScreen(),
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
        ValueListenableBuilder<LiveLocation?>(
          valueListenable: LocationService.current,
          builder: (ctx, loc, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on_rounded,
                  size: 12, color: Colors.white70),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  loc?.label ?? "Locating…",
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    actions: [
      _buildModeToggle(),
      Padding(
        padding: const EdgeInsets.only(right: 8),
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
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _navItem(icon: Icons.home_rounded, label: "Home", index: 0),
              _navItem(
                  icon: Icons.meeting_room_rounded,
                  label: "Rooms",
                  index: 1),
              _navItem(
                  icon: Icons.auto_graph_rounded,
                  label: "Optimize",
                  index: 2),
              _navItem(
                  icon: Icons.settings_rounded, label: "Control", index: 3),
              _navItem(
                  icon: Icons.shield_moon_rounded,
                  label: "Anomalies",
                  index: 4),
              _navItem(
                  icon: Icons.show_chart_rounded, label: "Energy", index: 5),
              _navItem(
                  icon: Icons.receipt_long_rounded,
                  label: "Bills",
                  index: 6),
              _navItem(
                  icon: Icons.security_rounded, label: "Security", index: 7),
              _navItem(
                  icon: Icons.history_rounded, label: "Logs", index: 8),
              _navItem(icon: Icons.mic_rounded, label: "Voice", index: 9),
              _navItem(
                  icon: Icons.smart_toy_rounded, label: "Agent", index: 10),
            ],
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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

