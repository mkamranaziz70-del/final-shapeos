import 'dart:math';
import '../models/device_model.dart';
import 'device_monitor_service.dart';
import 'ai_anomaly_service.dart';

/// =========================================================
/// 🔌 DEVICE SERVICE (IMMUTABLE MODEL SAFE)
/// =========================================================
///
/// - Works with final fields in DeviceModel
/// - Uses copyWith-style updates
/// - AI + Monitoring compatible
///
class DeviceService {
  static final Random _rand = Random();

  /// ===============================
  /// 🔹 INTERNAL DEVICE STORE
  /// ===============================

  static final List<DeviceModel> _devices = List.generate(6, (index) {
    return DeviceModel(
      id: index.toString(),
      name: _deviceName(index),
      type: _deviceType(index),
      isOn: false,
      power: 0,
      voltage: 220,
      current: 0,
      currentLeakage: 0,
      voltageLeakage: 0,
      energy: 0,
    );
  });

  /// ===============================
  /// 🔹 PUBLIC API
  /// ===============================

  static List<DeviceModel> getDevices() {
    _simulateRealtimeData();
    return List.unmodifiable(_devices);
  }

  static DeviceModel getDeviceById(String id) {
    _simulateRealtimeData();
    return _devices.firstWhere((d) => d.id == id);
  }

  /// Toggle device ON / OFF
  static void toggleDevice(String deviceId, bool newState) {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index == -1) return;

    final old = _devices[index];

    final updated = old.copyWith(isOn: newState);

    _devices[index] = updated;

    if (newState) {
      DeviceMonitorService.deviceTurnedOn(deviceId);

      DeviceMonitorService.registerDevice(
        deviceId: deviceId,
        maxMinutes: 2, // default demo value
      );
    } else {
      DeviceMonitorService.deviceTurnedOff(deviceId);
    }
  }

  /// ===============================
  /// 🔹 REALTIME SIMULATION
  /// ===============================

  static void _simulateRealtimeData() {
    for (int i = 0; i < _devices.length; i++) {
      final d = _devices[i];

      if (!d.isOn) {
        _devices[i] = d.copyWith(
          power: 0,
          current: 0,
        );
        continue;
      }

      final power = _randomPower(d.type);
      final voltage = 215 + _rand.nextDouble() * 10;
      final current = power / voltage;

      final energyIncrement = (power / 1000) / 60; // 1 min step
      final newEnergy = d.energy + energyIncrement;

      final updated = d.copyWith(
        power: power,
        voltage: voltage,
        current: current,
        currentLeakage: _rand.nextDouble() * 0.02,
        voltageLeakage: _rand.nextDouble() * 0.5,
        energy: newEnergy,
      );

      _devices[i] = updated;

      /// 🔹 MONITOR + AI CHECK
      final monitor = DeviceMonitorService.check(updated.id);
      // ignore: unused_local_variable
      final aiResult = AIAnomalyService.analyze(updated);

      if (monitor.autoOff) {
        _devices[i] = updated.copyWith(isOn: false);
        DeviceMonitorService.deviceTurnedOff(updated.id);
      }

      // You can forward:
      // monitor.message
      // aiResult.message
      // to UI / voice / Firebase
    }
  }

  /// ===============================
  /// 🔹 HELPERS
  /// ===============================

  static String _deviceName(int index) {
    switch (index) {
      case 0:
        return "Living Room Light";
      case 1:
        return "Ceiling Fan";
      case 2:
        return "Water Pump";
      case 3:
        return "Room Heater";
      case 4:
        return "Kitchen Light";
      default:
        return "Spare Device";
    }
  }

  static String _deviceType(int index) {
    switch (index) {
      case 1:
        return "Fan";
      case 3:
        return "Heater";
      case 2:
        return "Pump";
      default:
        return "Bulb";
    }
  }

  static double _randomPower(String type) {
    switch (type) {
      case "Fan":
        return 70 + _rand.nextDouble() * 40;
      case "Heater":
        return 800 + _rand.nextDouble() * 400;
      case "Pump":
        return 300 + _rand.nextDouble() * 200;
      default:
        return 20 + _rand.nextDouble() * 40;
    }
  }
}
