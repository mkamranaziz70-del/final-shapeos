class DeviceModel {
  final String id;
  final String name;
  final String type;
  final bool isOn;

  final double power;
  final double voltage;
  final double current;
  final double currentLeakage;
  final double voltageLeakage;
  final double energy;

  const DeviceModel({
    required this.id,
    required this.name,
    required this.type,
    required this.isOn,
    required this.power,
    required this.voltage,
    required this.current,
    required this.currentLeakage,
    required this.voltageLeakage,
    required this.energy,
  });

  // =========================================================
  // 🔹 COPY WITH (IMMUTABLE UPDATE)
  // =========================================================
  DeviceModel copyWith({
    bool? isOn,
    double? power,
    double? voltage,
    double? current,
    double? currentLeakage,
    double? voltageLeakage,
    double? energy,
  }) {
    return DeviceModel(
      id: id,
      name: name,
      type: type,
      isOn: isOn ?? this.isOn,
      power: power ?? this.power,
      voltage: voltage ?? this.voltage,
      current: current ?? this.current,
      currentLeakage: currentLeakage ?? this.currentLeakage,
      voltageLeakage: voltageLeakage ?? this.voltageLeakage,
      energy: energy ?? this.energy,
    );
  }

  // =========================================================
  // 🔹 FIREBASE SERIALIZATION
  // =========================================================
  Map<String, dynamic> toMap() => {
        "name": name,
        "type": type,
        "isOn": isOn,
        "power": power,
        "voltage": voltage,
        "current": current,
        "currentLeakage": currentLeakage,
        "voltageLeakage": voltageLeakage,
        "energy": energy,
      };

  // =========================================================
  // 🔹 FIREBASE DESERIALIZATION
  // =========================================================
  factory DeviceModel.fromMap(Map<dynamic, dynamic> map, String id) {
    // 🚫 Ignore invalid nodes
    if (!map.containsKey('name') || !map.containsKey('type')) {
      throw Exception("Not a device node");
    }

    return DeviceModel(
      id: id,
      name: map['name']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      isOn: map['isOn'] == true,
      power: _toDouble(map['power']),
      voltage: _toDouble(map['voltage']),
      current: _toDouble(map['current']),
      currentLeakage: _toDouble(map['currentLeakage']),
      voltageLeakage: _toDouble(map['voltageLeakage']),
      energy: _toDouble(map['energy']),
    );
  }

  // =========================================================
  // 🔹 SAFE DOUBLE PARSER
  // =========================================================
  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}
