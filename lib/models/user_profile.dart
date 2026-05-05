/// =========================================================
/// USER PROFILE
/// =========================================================
/// Rich personal context the agent uses to personalise
/// suggestions, automations and conversation.
class UserProfile {
  final String uid;
  final String fullName;
  final int age;
  final String occupation;
  final String room;
  final String sleepStart;
  final String sleepEnd;
  final String climateSensitivity;
  final List<String> healthFlags;
  final String preferredTone;
  final List<String> ownedDeviceIds;
  final String homeAddressHint;
  final String createdAt;

  const UserProfile({
    required this.uid,
    required this.fullName,
    required this.age,
    required this.occupation,
    required this.room,
    required this.sleepStart,
    required this.sleepEnd,
    required this.climateSensitivity,
    required this.healthFlags,
    required this.preferredTone,
    required this.ownedDeviceIds,
    required this.homeAddressHint,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        "uid": uid,
        "fullName": fullName,
        "age": age,
        "occupation": occupation,
        "room": room,
        "sleepStart": sleepStart,
        "sleepEnd": sleepEnd,
        "climateSensitivity": climateSensitivity,
        "healthFlags": healthFlags,
        "preferredTone": preferredTone,
        "ownedDeviceIds": ownedDeviceIds,
        "homeAddressHint": homeAddressHint,
        "createdAt": createdAt,
      };

  factory UserProfile.fromMap(Map<String, dynamic> m) => UserProfile(
        uid: m["uid"]?.toString() ?? "",
        fullName: m["fullName"]?.toString() ?? "",
        age: (m["age"] is num) ? (m["age"] as num).toInt() : 0,
        occupation: m["occupation"]?.toString() ?? "",
        room: m["room"]?.toString() ?? "",
        sleepStart: m["sleepStart"]?.toString() ?? "23:00",
        sleepEnd: m["sleepEnd"]?.toString() ?? "07:00",
        climateSensitivity: m["climateSensitivity"]?.toString() ?? "normal",
        healthFlags: (m["healthFlags"] is List)
            ? List<String>.from(m["healthFlags"])
            : <String>[],
        preferredTone:
            m["preferredTone"]?.toString() ?? "professional",
        ownedDeviceIds: (m["ownedDeviceIds"] is List)
            ? List<String>.from(m["ownedDeviceIds"])
            : <String>[],
        homeAddressHint: m["homeAddressHint"]?.toString() ?? "",
        createdAt: m["createdAt"]?.toString() ?? "",
      );

  /// One-line context string shown in the agent system prompt.
  String toAgentDescriptor() {
    final flags = healthFlags.isEmpty ? "none" : healthFlags.join(", ");
    return "User: $fullName, age $age, $occupation. "
        "Lives in '$room'. "
        "Sleeps $sleepStart-$sleepEnd. "
        "Climate sensitivity: $climateSensitivity. "
        "Health considerations: $flags. "
        "Owns devices: ${ownedDeviceIds.join(', ')}. "
        "Preferred tone: $preferredTone.";
  }
}
