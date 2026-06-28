// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/room_model.dart';

/// =========================================================
/// ROOM SERVICE
/// =========================================================
/// Admin-only CRUD over `/rooms/{roomId}`. The home is single-
/// admin so we don't scope to a user; every device in the
/// dashboard is reachable from any room the admin defines.
class RoomService {
  RoomService._();

  static CollectionReference<Map<String, dynamic>> _col() =>
      FirebaseFirestore.instance.collection("rooms");

  static Stream<List<RoomModel>> stream() => _col()
      .orderBy("createdAt")
      .snapshots()
      .map((s) =>
          s.docs.map((d) => RoomModel.fromDoc(d.id, d.data())).toList());

  static Future<RoomModel> create({
    required String name,
    required String occupant,
    required List<String> deviceIds,
  }) async {
    final ref = await _col().add({
      "name": name,
      "occupant": occupant,
      "deviceIds": deviceIds,
      "createdAt": FieldValue.serverTimestamp(),
    });
    return RoomModel(
      id: ref.id,
      name: name,
      occupant: occupant,
      deviceIds: deviceIds,
      createdAt: DateTime.now(),
    );
  }

  static Future<void> update(RoomModel room) async {
    await _col().doc(room.id).set({
      "name": room.name,
      "occupant": room.occupant,
      "deviceIds": room.deviceIds,
    }, SetOptions(merge: true));
  }

  static Future<void> delete(String roomId) async {
    try {
      await _col().doc(roomId).delete();
    } catch (e) {
      debugPrint("RoomService.delete failed: $e");
    }
  }

  /// One-shot read for use by services that don't need a stream
  /// (BillSplittingService, EnergyOptimizationService).
  static Future<List<RoomModel>> all() async {
    try {
      final snap = await _col().get();
      return snap.docs
          .map((d) => RoomModel.fromDoc(d.id, d.data()))
          .toList();
    } catch (e) {
      debugPrint("RoomService.all failed: $e");
      return const [];
    }
  }
}
