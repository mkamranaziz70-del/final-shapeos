import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_keys.dart';

/// =========================================================
/// WEATHER SNAPSHOT
/// =========================================================
@immutable
class WeatherSnapshot {
  final double tempC;
  final double feelsLikeC;
  final int humidity;
  final double windKph;
  final String condition;
  final String description;
  final String iconCode;
  final DateTime fetchedAt;

  const WeatherSnapshot({
    required this.tempC,
    required this.feelsLikeC,
    required this.humidity,
    required this.windKph,
    required this.condition,
    required this.description,
    required this.iconCode,
    required this.fetchedAt,
  });

  String toAgentDescriptor() =>
      "Outside: ${tempC.toStringAsFixed(1)}°C "
      "(feels ${feelsLikeC.toStringAsFixed(1)}°C), "
      "$description, humidity $humidity%, "
      "wind ${windKph.toStringAsFixed(0)} km/h.";
}

/// =========================================================
/// WEATHER SERVICE
/// =========================================================
/// OpenWeatherMap fetcher with a 15-minute in-memory cache,
/// keyed by lat/lon rounded to 0.05°. Safe to call frequently.
class WeatherService {
  WeatherService._();

  static final ValueNotifier<WeatherSnapshot?> latest =
      ValueNotifier<WeatherSnapshot?>(null);

  static final Map<String, _CachedSnap> _cache = {};
  static const Duration _ttl = Duration(minutes: 15);

  static Future<WeatherSnapshot?> fetch({
    required double lat,
    required double lon,
  }) async {
    if (!ApiKeys.hasWeather) {
      debugPrint("WeatherService: no API key configured.");
      return null;
    }

    final key = "${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}";
    final hit = _cache[key];
    if (hit != null &&
        DateTime.now().difference(hit.snap.fetchedAt) < _ttl) {
      latest.value = hit.snap;
      return hit.snap;
    }

    final uri = Uri.parse(
      "https://api.openweathermap.org/data/2.5/weather"
      "?lat=$lat&lon=$lon"
      "&units=${ApiKeys.weatherUnits}"
      "&appid=${ApiKeys.openWeatherApiKey}",
    );

    try {
      final res = await http
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        debugPrint(
          "WeatherService HTTP ${res.statusCode}: ${res.body}",
        );
        return null;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;

      final main = json["main"] as Map<String, dynamic>? ?? {};
      final wind = json["wind"] as Map<String, dynamic>? ?? {};
      final weatherList = (json["weather"] as List?) ?? const [];
      final w = weatherList.isNotEmpty
          ? weatherList.first as Map<String, dynamic>
          : <String, dynamic>{};

      final snap = WeatherSnapshot(
        tempC: _d(main["temp"]),
        feelsLikeC: _d(main["feels_like"]),
        humidity: (_d(main["humidity"])).round(),
        windKph: _d(wind["speed"]) * 3.6,
        condition: w["main"]?.toString() ?? "Unknown",
        description: w["description"]?.toString() ?? "",
        iconCode: w["icon"]?.toString() ?? "",
        fetchedAt: DateTime.now(),
      );

      _cache[key] = _CachedSnap(snap);
      latest.value = snap;
      return snap;
    } catch (e) {
      debugPrint("WeatherService error: $e");
      return null;
    }
  }

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

class _CachedSnap {
  final WeatherSnapshot snap;
  _CachedSnap(this.snap);
}
