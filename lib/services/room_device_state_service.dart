// ignore_for_file: avoid_print

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// =========================================================
/// ROOM DEVICE STATE SERVICE
/// =========================================================
/// Per-room virtual device state. Lets the demo show "Kamran's
/// fan is on, Ali's fan is off" even though both rooms point at
/// the same physical device id (1=Fan).
///
/// Schema: `/room_states/{roomId}/{deviceId}/isOn` (Firebase RTDB).
///
/// Toggling a device inside a specific room only flips that
/// room's logical state; the global `/appliances/{deviceId}`
/// node is updated to the OR of every room's state, because the
/// physical hardware is shared. This way the simulator can keep
/// emitting realistic readings while the UI shows independent
/// per-room toggles.
class RoomDeviceStateService {
  RoomDeviceStateService._();

  static final FirebaseDatabase _db = FirebaseDatabase.instance;

  /// Live stream of one room's view of one device. Returns
  /// `false` when no per-room state exists yet.
  static Stream<bool> stream(String roomId, String deviceId) {
    return _db
        .ref("room_states/$roomId/$deviceId/isOn")
        .onValue
        .map((e) => e.snapshot.value == true);
  }

  static Future<bool> get(String roomId, String deviceId) async {
    try {
      final snap =
          await _db.ref("room_states/$roomId/$deviceId/isOn").get();
      return snap.value == true;
    } catch (_) {
      return false;
    }
  }

  /// Set this room's logical state for the device. Updates the
  /// shared physical node `/appliances/{deviceId}` to the OR of
  /// all rooms with that device assigned, so the simulator and
  /// readings UI stay consistent.
  static Future<void> set({
    required String roomId,
    required String deviceId,
    required bool isOn,
    required List<String> roomsWithDevice,
  }) async {
    try {
      await _db
          .ref("room_states/$roomId/$deviceId/isOn")
          .set(isOn);

      // Re-evaluate the physical state by ORing every other
      // room's view of this device.
      bool anyOn = isOn;
      if (!isOn) {
        for (final otherRoomId in roomsWithDevice) {
          if (otherRoomId == roomId) continue;
          final otherOn = await get(otherRoomId, deviceId);
          if (otherOn) {
            anyOn = true;
            break;
          }
        }
      }
      await _db
          .ref("appliances/$deviceId/isOn")
          .set(anyOn);
    } catch (e) {
      debugPrint("RoomDeviceStateService.set failed: $e");
    }
  }

  /// Used by the optimization engine when a peak-hour rule
  /// fires — we cut the device for that *one* room only, not
  /// the others that may also have it on.
  static Future<void> cutInRoom({
    required String roomId,
    required String deviceId,
    required List<String> roomsWithDevice,
  }) async {
    await set(
      roomId: roomId,
      deviceId: deviceId,
      isOn: false,
      roomsWithDevice: roomsWithDevice,
    );
  }
}
