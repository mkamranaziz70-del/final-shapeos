// ignore_for_file: unnecessary_string_interpolations

import 'package:flutter_tts/flutter_tts.dart';

/// =========================================================
/// 🔊 VOICE SERVICE (INTELLIGENT NARRATOR)
/// =========================================================
///
/// RESPONSIBILITIES:
/// - Speak daily energy analysis
/// - Announce peak hours
/// - Read bill summaries
/// - Speak AI anomalies & suggestions
/// - Warn about device overuse
/// - Confirm auto shut-downs
/// - Works globally (any tab / background)
///
class VoiceService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;

  /// =========================================================
  /// 🔹 INITIALIZATION (CALL ON APP START)
  /// =========================================================
  static Future<void> init() async {
    if (_initialized) return;

    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.05);
    await _tts.setVolume(1.0);

    await _tts.awaitSpeakCompletion(true);

    _initialized = true;
  }

  /// =========================================================
  /// 🔹 CORE SPEAK METHOD
  /// =========================================================
  static Future<void> speak(String message) async {
    await init();
    if (message.trim().isEmpty) return;

    await _tts.stop();
    await _tts.speak(message);
  }

  /// =========================================================
  /// 🔹 DAILY ENERGY ANALYSIS (MODULE 7)
  /// =========================================================
  static Future<void> speakDailySummary({
    required String date,
    required double totalEnergy,
    required int peakHour,
    required List<int> topPeakHours,
    required double estimatedBill,
  }) async {
    final peakHoursText = topPeakHours
        .map((h) => "${_hourLabel(h)}")
        .join(", ");

    final message = """
Daily energy summary for $date.
Total energy consumed today is ${totalEnergy.toStringAsFixed(2)} kilowatt hours.
Peak energy usage was recorded around ${_hourLabel(peakHour)}.
Other high usage hours include $peakHoursText.
Your estimated electricity bill so far is rupees ${estimatedBill.toStringAsFixed(0)}.
""";

    await speak(message);
  }

  /// =========================================================
  /// 🔹 AI ANOMALY ANNOUNCEMENT (MODULE 8)
  /// =========================================================
  static Future<void> speakAnomaly({
    required String deviceName,
    required String reason,
  }) async {
    final message = """
Attention.
Anomaly detected.
$deviceName $reason.
Please review your device usage.
""";

    await speak(message);
  }

  /// =========================================================
  /// 🔹 AI ENERGY SAVING SUGGESTION
  /// =========================================================
  static Future<void> speakSuggestion(String suggestion) async {
    final message = """
Energy saving suggestion.
$suggestion.
""";

    await speak(message);
  }

  /// =========================================================
  /// 🔹 DEVICE UPTIME WARNING
  /// =========================================================
  static Future<void> speakUptimeWarning({
    required String deviceName,
    required int minutes,
  }) async {
    final message = """
Warning.
$deviceName has been running for $minutes minutes.
Would you like to turn it off?
""";

    await speak(message);
  }

  /// =========================================================
  /// 🔹 FINAL WARNING BEFORE AUTO OFF
  /// =========================================================
  static Future<void> speakFinalWarning(String deviceName) async {
    final message = """
Final warning.
$deviceName is still running.
It will be turned off automatically to save energy.
""";

    await speak(message);
  }

  /// =========================================================
  /// 🔹 AUTO OFF CONFIRMATION
  /// =========================================================
  static Future<void> speakAutoOff(String deviceName) async {
    final message = """
$deviceName has exceeded safe usage time.
Turning it off now.
""";

    await speak(message);
  }

  /// =========================================================
  /// 🔹 BILL ALERT
  /// =========================================================
  static Future<void> speakBudgetAlert({
    required double bill,
    required double budget,
  }) async {
    final percent = ((bill / budget) * 100).toStringAsFixed(0);

    final message = """
Budget alert.
You have used $percent percent of your monthly energy budget.
Please reduce energy usage to avoid high bills.
""";

    await speak(message);
  }

  /// =========================================================
  /// 🔹 SYSTEM ANNOUNCEMENTS
  /// =========================================================
  static Future<void> speakSystem(String message) async {
    await speak("System notification. $message");
  }

  /// =========================================================
  /// 🔹 HELPERS
  /// =========================================================
  static String _hourLabel(int hour) {
    if (hour == 0) return "12 AM";
    if (hour < 12) return "$hour AM";
    if (hour == 12) return "12 PM";
    return "${hour - 12} PM";
  }

  /// =========================================================
  /// 🔹 STOP VOICE
  /// =========================================================
  static Future<void> stop() async {
    await _tts.stop();
  }
}
