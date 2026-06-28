// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/room_model.dart';
import '../screens/room_history_screen.dart';
import '../services/agent_automation_engine.dart';
import '../services/device_profile_service.dart';
import '../services/room_device_state_service.dart';
import '../services/room_service.dart';

/// =========================================================
/// ROOMS TAB (admin)
/// =========================================================
/// Single-admin home view: the admin creates rooms (each with
/// a name, an occupant, and the devices that live inside),
/// sees the live state of every device per room and can
/// toggle them. Bill splitting and optimization downstream
/// both key off this room model.
class RoomsTab extends StatefulWidget {
  const RoomsTab({super.key});

  @override
  State<RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<RoomsTab> {
  static const Color _blue = Color(0xFF154F73);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: StreamBuilder<List<RoomModel>>(
        stream: RoomService.stream(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rooms = snap.data ?? const <RoomModel>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              _hero(rooms.length),
              const SizedBox(height: 14),
              if (rooms.isEmpty)
                _emptyState()
              else
                for (final r in rooms) _roomCard(r),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editRoom(null),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text("Add room"),
      ),
    );
  }

  Widget _hero(int roomCount) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF154F73), Color(0xFF0E2E45)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.admin_panel_settings_rounded,
              color: Colors.white, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "ADMIN VIEW",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    letterSpacing: 1.4,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "$roomCount room${roomCount == 1 ? '' : 's'}",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800),
                ),
                Text(
                  "Add rooms, assign occupants, manage devices and "
                  "see live status of every appliance.",
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12.5,
                      height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.all(24),
      decoration: _cardDeco(),
      child: Column(
        children: [
          const Icon(Icons.meeting_room_rounded, size: 56, color: _blue),
          const SizedBox(height: 10),
          const Text(
            "No rooms yet",
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 18, color: _blue),
          ),
          const SizedBox(height: 6),
          Text(
            "Tap the Add Room button to create your first room — for "
            "example: 'Kamran's Bedroom' with the bulb and fan.",
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _roomCard(RoomModel room) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDeco(),
      child: Column(
        children: [
          // Header — tap opens the room's energy history.
          InkWell(
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16)),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RoomHistoryScreen(room: room),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: _blue,
                    child: Text(
                      _initials(room.occupant.isEmpty
                          ? room.name
                          : room.occupant),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                room.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: _blue, size: 20),
                          ],
                        ),
                        Text(
                          room.occupant.isEmpty
                              ? "no occupant set · tap for history"
                              : "occupant: ${room.occupant} · tap for history",
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    iconSize: 18,
                    tooltip: "Edit",
                    onPressed: () => _editRoom(room),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton(
                    iconSize: 18,
                    tooltip: "Delete",
                    onPressed: () => _confirmDelete(room),
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.red),
                  ),
                ],
              ),
            ),
          ),
          if (room.deviceIds.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Text(
                "No devices assigned to this room.",
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 12.5),
              ),
            )
          else
            for (final id in room.deviceIds) _deviceRow(id, room),
        ],
      ),
    );
  }

  Widget _deviceRow(String deviceId, RoomModel room) {
    // Per-room virtual on/off, so toggling Kamran's fan doesn't
    // visually flip Ali's fan even though they share the same
    // physical device id.
    return StreamBuilder<bool>(
      stream:
          RoomDeviceStateService.stream(room.id, deviceId),
      builder: (ctx, roomStateSnap) {
        final isOn = roomStateSnap.data == true;
        return StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance
              .ref("appliances/$deviceId")
              .onValue,
          builder: (ctx2, applianceSnap) {
            final m = (applianceSnap.data?.snapshot.value as Map?) ??
                const {};
            // Readings come from the shared physical node since
            // the simulator only writes there.
            final v = _toD(m["voltage"]);
            final p = _toD(m["power"]);
            final profile = DeviceProfileService.of(deviceId);
            final name = (m["name"]?.toString() ??
                profile?.name ??
                "Device $deviceId");
            return _renderRow(
              roomId: room.id,
              deviceId: deviceId,
              name: name,
              profileName: profile?.name,
              isOn: isOn,
              voltage: isOn ? v : 0,
              power: isOn ? p : 0,
            );
          },
        );
      },
    );
  }

  Widget _renderRow({
    required String roomId,
    required String deviceId,
    required String name,
    required String? profileName,
    required bool isOn,
    required double voltage,
    required double power,
  }) {
    return Container(
      margin:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isOn
            ? const Color(0xFF24E0A0).withOpacity(0.06)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOn
              ? const Color(0xFF24E0A0).withOpacity(0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _iconFor(profileName ?? name),
            color: isOn ? const Color(0xFF065244) : Colors.grey,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                Text(
                  isOn
                      ? "${voltage.toStringAsFixed(1)} V · ${power.toStringAsFixed(1)} W"
                      : "off",
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isOn,
            activeColor: const Color(0xFF065244),
            onChanged: (v) async {
              // Look up which other rooms own this device so the
              // OR rollup that writes /appliances/{id} can be
              // computed correctly.
              final all = await RoomService.all();
              final roomsWithDevice = all
                  .where((r) => r.deviceIds.contains(deviceId))
                  .map((r) => r.id)
                  .toList();
              await RoomDeviceStateService.set(
                roomId: roomId,
                deviceId: deviceId,
                isOn: v,
                roomsWithDevice: roomsWithDevice,
              );
              AgentAutomationEngine.registerManualAction(deviceId);
            },
          ),
        ],
      ),
    );
  }

  // =========================================================
  // ADD / EDIT
  // =========================================================
  Future<void> _editRoom(RoomModel? existing) async {
    final nameCtrl =
        TextEditingController(text: existing?.name ?? "");
    final occupantCtrl =
        TextEditingController(text: existing?.occupant ?? "");
    final selected = <String>{...?existing?.deviceIds};

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSt) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null
                        ? "Add a new room"
                        : "Edit ${existing.name}",
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: _blue),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Room name",
                      hintText: "e.g. Kamran's Bedroom",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: occupantCtrl,
                    decoration: const InputDecoration(
                      labelText: "Occupant",
                      hintText: "e.g. Kamran",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    "Devices in this room",
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  for (final p in DeviceProfileService.all())
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        "${p.name}  (${p.currentType})",
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      value: selected.contains(p.id),
                      activeColor: _blue,
                      onChanged: (v) => setSt(() {
                        if (v == true) {
                          selected.add(p.id);
                        } else {
                          selected.remove(p.id);
                        }
                      }),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        if (nameCtrl.text.trim().isEmpty) return;
                        if (existing == null) {
                          await RoomService.create(
                            name: nameCtrl.text.trim(),
                            occupant: occupantCtrl.text.trim(),
                            deviceIds: selected.toList(),
                          );
                        } else {
                          await RoomService.update(
                            existing.copyWith(
                              name: nameCtrl.text.trim(),
                              occupant: occupantCtrl.text.trim(),
                              deviceIds: selected.toList(),
                            ),
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      },
                      child: Text(
                        existing == null
                            ? "Create room"
                            : "Save changes",
                        style: const TextStyle(
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null
              ? "Room created."
              : "Room updated."),
        ),
      );
    }
  }

  Future<void> _confirmDelete(RoomModel room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Delete ${room.name}?"),
        content: const Text(
          "This removes the room from the dashboard. Devices "
          "themselves are unaffected.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await RoomService.delete(room.id);
  }

  // =========================================================
  // HELPERS
  // =========================================================
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

  String _initials(String s) {
    if (s.isEmpty) return "?";
    final parts = s.trim().split(RegExp(r"\s+"));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains("fan")) return Icons.air_rounded;
    if (n.contains("bulb")) return Icons.lightbulb_rounded;
    if (n.contains("pump")) return Icons.water_rounded;
    if (n.contains("bell")) return Icons.notifications_active_rounded;
    return Icons.power_rounded;
  }

  static double _toD(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
