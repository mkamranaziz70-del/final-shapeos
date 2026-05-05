import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// =========================================================
/// LIVE LOCATION FIX
/// =========================================================
@immutable
class LiveLocation {
  final double latitude;
  final double longitude;
  final String city;
  final String country;
  final String label;
  final DateTime updatedAt;

  const LiveLocation({
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.country,
    required this.label,
    required this.updatedAt,
  });

  factory LiveLocation.placeholder(String label) => LiveLocation(
        latitude: 0,
        longitude: 0,
        city: "",
        country: "",
        label: label,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  bool get isReal => updatedAt.millisecondsSinceEpoch > 0;
}

/// =========================================================
/// LOCATION SERVICE
/// =========================================================
/// Streams GPS fixes, reverse-geocodes them, and exposes the
/// latest fix as a [ValueListenable] so any widget can pin a
/// live "city" pill.
class LocationService {
  LocationService._();

  static final ValueNotifier<LiveLocation?> current =
      ValueNotifier<LiveLocation?>(null);

  static StreamSubscription<Position>? _sub;
  static bool _starting = false;

  /// Idempotent. Call once after auth.
  static Future<void> start() async {
    if (_sub != null || _starting) return;
    _starting = true;
    try {
      final ok = await _ensurePermission();
      if (!ok) {
        current.value =
            LiveLocation.placeholder("Location permission denied");
        return;
      }

      try {
        final p = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        await _publish(p);
      } catch (e) {
        debugPrint("LocationService initial fix failed: $e");
      }

      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        ),
      ).listen(_publish, onError: (e) {
        debugPrint("LocationService stream error: $e");
      });
    } finally {
      _starting = false;
    }
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  static Future<void> refreshNow() async {
    if (!await _ensurePermission()) return;
    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _publish(p);
    } catch (e) {
      debugPrint("LocationService refresh failed: $e");
    }
  }

  static Future<void> _publish(Position p) async {
    String city = "";
    String country = "";
    try {
      final placemarks = await placemarkFromCoordinates(
        p.latitude,
        p.longitude,
      );
      if (placemarks.isNotEmpty) {
        final m = placemarks.first;
        city = (m.locality?.isNotEmpty ?? false)
            ? m.locality!
            : (m.subAdministrativeArea ?? m.administrativeArea ?? "");
        country = m.country ?? "";
      }
    } catch (e) {
      debugPrint("Reverse geocode failed: $e");
    }

    final label = city.isEmpty
        ? "${p.latitude.toStringAsFixed(2)}, ${p.longitude.toStringAsFixed(2)}"
        : (country.isEmpty ? city : "$city, $country");

    current.value = LiveLocation(
      latitude: p.latitude,
      longitude: p.longitude,
      city: city,
      country: country,
      label: label,
      updatedAt: DateTime.now(),
    );
  }

  static Future<bool> _ensurePermission() async {
    final servicesEnabled =
        await Geolocator.isLocationServiceEnabled();
    if (!servicesEnabled) return false;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }
}
