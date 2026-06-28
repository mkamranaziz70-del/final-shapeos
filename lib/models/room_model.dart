import 'package:cloud_firestore/cloud_firestore.dart';

/// =========================================================
/// ROOM MODEL
/// =========================================================
/// In the admin-managed home model, the unit of organisation
/// is a **room** (not a user). The admin creates rooms with a
/// name, an occupant label, and the set of devices that live
/// inside it. Bill splitting, optimization recommendations and
/// device controls all key off this model.
class RoomModel {
  final String id;
  final String name;
  final String occupant;
  final List<String> deviceIds;
  final DateTime? createdAt;

  const RoomModel({
    required this.id,
    required this.name,
    required this.occupant,
    required this.deviceIds,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        "name": name,
        "occupant": occupant,
        "deviceIds": deviceIds,
        "createdAt":
            createdAt == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(createdAt!),
      };

  factory RoomModel.fromDoc(String id, Map<String, dynamic> m) {
    final ts = m["createdAt"];
    return RoomModel(
      id: id,
      name: m["name"]?.toString() ?? "Room",
      occupant: m["occupant"]?.toString() ?? "",
      deviceIds: (m["deviceIds"] is List)
          ? List<String>.from(m["deviceIds"])
          : <String>[],
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  RoomModel copyWith({
    String? name,
    String? occupant,
    List<String>? deviceIds,
  }) =>
      RoomModel(
        id: id,
        name: name ?? this.name,
        occupant: occupant ?? this.occupant,
        deviceIds: deviceIds ?? this.deviceIds,
        createdAt: createdAt,
      );
}
