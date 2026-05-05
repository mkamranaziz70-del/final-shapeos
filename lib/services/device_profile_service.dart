/// =========================================================
/// DEVICE PROFILE
/// =========================================================
/// Static spec for each appliance — current type (AC/DC),
/// nominal operating values, jitter ranges (used by the live
/// simulator so the readings flicker realistically) and the
/// safe band used by [AnomalyDetectionService].
///
/// Add or edit entries here when new devices come online.
class DeviceProfile {
  final String id;
  final String name;
  final String currentType; // "AC" or "DC"
  final double nominalVoltage;
  final double voltageJitter;
  final double nominalCurrent;
  final double currentJitter;
  final double safeVoltageMin;
  final double safeVoltageMax;
  final double safeCurrentMax;
  final double safeLeakageMax;

  /// Voltage written when a surge is simulated. Always above
  /// [safeVoltageMax] so the anomaly detector trips.
  final double surgeVoltage;

  /// Leakage current written when a leakage is simulated.
  /// Always above [safeLeakageMax].
  final double leakageCurrent;

  const DeviceProfile({
    required this.id,
    required this.name,
    required this.currentType,
    required this.nominalVoltage,
    required this.voltageJitter,
    required this.nominalCurrent,
    required this.currentJitter,
    required this.safeVoltageMin,
    required this.safeVoltageMax,
    required this.safeCurrentMax,
    required this.safeLeakageMax,
    required this.surgeVoltage,
    required this.leakageCurrent,
  });
}

class DeviceProfileService {
  DeviceProfileService._();

  /// Canonical device list. Keep IDs in sync with the ESP32
  /// firmware (`/appliances/{id}/isOn`).
  ///
  /// Safe bands chosen against real-world spec:
  ///   • 12 V DC equipment is rated for roughly ±15% (10.2–13.8 V).
  ///     We allow 10.5–14.0 V so transient brown-outs and small
  ///     overvoltage spikes don't auto-cut.
  ///   • Pakistani mains is 220 V AC ±10% (198–242 V) per the
  ///     national grid spec; outside that range the bulb/bell
  ///     should genuinely trip.
  static const Map<String, DeviceProfile> profiles = {
    "1": DeviceProfile(
      id: "1",
      name: "Fan",
      currentType: "DC",
      nominalVoltage: 12.0,
      voltageJitter: 0.20,
      nominalCurrent: 0.45,
      currentJitter: 0.03,
      safeVoltageMin: 10.5,
      safeVoltageMax: 14.0,
      safeCurrentMax: 1.5,
      safeLeakageMax: 0.05,
      surgeVoltage: 17.5,
      leakageCurrent: 0.10,
    ),
    "2": DeviceProfile(
      id: "2",
      name: "Bulb",
      currentType: "AC",
      nominalVoltage: 220.0,
      voltageJitter: 1.4,
      // 0.18 A draw at 220 V ≈ 40 W — a typical LED bulb in a
      // Pakistani household. Was 0.45 A (94 W) which dominated
      // the monthly bill calculation unrealistically.
      nominalCurrent: 0.18,
      currentJitter: 0.015,
      safeVoltageMin: 198.0,
      safeVoltageMax: 242.0,
      safeCurrentMax: 0.5,
      safeLeakageMax: 0.05,
      surgeVoltage: 258.0,
      leakageCurrent: 0.08,
    ),
    "3": DeviceProfile(
      id: "3",
      name: "Pump",
      currentType: "DC",
      nominalVoltage: 12.0,
      voltageJitter: 0.30,
      nominalCurrent: 3.0,
      currentJitter: 0.15,
      safeVoltageMin: 10.5,
      safeVoltageMax: 14.0,
      safeCurrentMax: 6.0,
      safeLeakageMax: 0.05,
      surgeVoltage: 17.8,
      leakageCurrent: 0.12,
    ),
    "4": DeviceProfile(
      id: "4",
      name: "Bell",
      currentType: "AC",
      nominalVoltage: 220.0,
      voltageJitter: 2.0,
      nominalCurrent: 0.20,
      currentJitter: 0.015,
      safeVoltageMin: 198.0,
      safeVoltageMax: 242.0,
      safeCurrentMax: 0.5,
      safeLeakageMax: 0.05,
      surgeVoltage: 256.0,
      leakageCurrent: 0.09,
    ),
  };

  static DeviceProfile? of(String id) => profiles[id];

  static List<DeviceProfile> all() => profiles.values.toList();

  static String labelFor(String id) =>
      "${profiles[id]?.name ?? "Device $id"} (${profiles[id]?.currentType ?? "?"})";
}
