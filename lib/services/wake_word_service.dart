// ignore_for_file: avoid_print

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/api_keys.dart';
import '../models/device_model.dart';
import 'agent_background_service.dart';
import 'agent_brain_service.dart';
import 'voice_service.dart';

enum WakeWordPhase {
  /// Service is off.
  idle,

  /// Mic is open, scanning partial results for the wake word.
  listening,

  /// Continuous conversation — every utterance is treated as a
  /// command. Entered after the user says the wake word once,
  /// exited by saying "stop", "sleep mode", "exit", etc.
  conversation,

  /// Legacy single-shot mode: heard wake word, taking exactly
  /// one command, then back to listening.
  awaitingCommand,

  /// We have a command and Gemini is thinking / TTS is speaking.
  processing,
}

/// =========================================================
/// WAKE WORD SERVICE
/// =========================================================
/// Continuously listens via [stt.SpeechToText] and watches the
/// rolling transcript for the wake word. On match it pauses,
/// prompts the user, captures the next utterance and pipes it
/// through [AgentBrainService] just like the chat screen.
///
/// The service also keeps the screen awake while it's running
/// so the OS doesn't shut the mic down. For surviving the app
/// going to the background a separate foreground-service is
/// configured in `agent_background_service.dart`.
class WakeWordService {
  WakeWordService._();

  static final stt.SpeechToText _stt = stt.SpeechToText();

  /// UI-observable state.
  static final ValueNotifier<WakeWordPhase> phase =
      ValueNotifier<WakeWordPhase>(WakeWordPhase.idle);

  /// Last partial transcript heard — useful as a debug overlay.
  static final ValueNotifier<String> lastHeard = ValueNotifier<String>("");

  /// Last reason the service stopped or failed. Empty string when
  /// healthy. Updated on every error path so the UI can show it.
  static final ValueNotifier<String> lastStatus =
      ValueNotifier<String>("");

  static bool _enabled = false;
  static bool _restartScheduled = false;
  static String _commandBuffer = "";

  /// Phonetic variants for the wake word so STT mishearings still
  /// trigger. The first item is the canonical configured wake word.
  static List<String> get wakeWords => [
        ApiKeys.wakeWord.toLowerCase(),
        "shape os",
        "shape o s",
        "shapus",
        "shapos",
        "shape oh s",
        "ship oz",
        "ship os",
        "hey shape",
        "hey ${ApiKeys.wakeWord.toLowerCase()}",
        "hey agent",
        "ok agent",
      ];

  static bool get isEnabled => _enabled;

  /// Turn the wake-word loop on.
  ///
  /// Requests RECORD_AUDIO at runtime first — Android 14+ will
  /// kill the app with a SecurityException if a microphone
  /// foreground service starts without that permission granted.
  /// Returns false if permission is denied or STT init failed.
  static Future<bool> enable() async {
    if (_enabled) return true;

    // Step 1 — runtime permission.
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        lastStatus.value =
            "Microphone permission denied. Open settings → grant mic access.";
        debugPrint("WakeWord: RECORD_AUDIO permission denied.");
        return false;
      }
    } catch (e) {
      lastStatus.value = "Could not request mic permission: $e";
      debugPrint("WakeWord permission request failed: $e");
      return false;
    }

    // Step 2 — speech_to_text init.
    final ok = await _stt.initialize(
      onStatus: _onStatus,
      onError: (err) {
        debugPrint("WakeWord STT error: ${err.errorMsg}");
        lastStatus.value = "STT: ${err.errorMsg}";
        _scheduleRestart();
      },
      debugLogging: false,
    );
    if (!ok) {
      lastStatus.value =
          "Speech recognition is unavailable on this device.";
      debugPrint("WakeWord STT init failed.");
      return false;
    }
    lastStatus.value = "";

    _enabled = true;

    // Step 3 — keep the screen awake.
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    // Step 4 — start the foreground service so the mic survives
    //          the user backgrounding the app.
    try {
      await AgentBackgroundService.start();
    } catch (e) {
      debugPrint("WakeWord background-service start failed: $e");
    }

    _startListening();
    return true;
  }

  /// Turn the wake-word loop off completely.
  static Future<void> disable() async {
    _enabled = false;
    try {
      await _stt.stop();
    } catch (_) {}
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    try {
      await AgentBackgroundService.stop();
    } catch (_) {}
    phase.value = WakeWordPhase.idle;
  }

  /// Hot-toggle helper for UI.
  static Future<bool> toggle() async {
    if (_enabled) {
      await disable();
      return false;
    }
    return enable();
  }

  // =========================================================
  // CORE LOOP
  // =========================================================
  static void _startListening() {
    if (!_enabled) return;
    if (_stt.isListening) return;

    phase.value = WakeWordPhase.listening;
    _stt.listen(
      onResult: _onPartial,
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 8),
      partialResults: true,
      cancelOnError: false,
      listenMode: stt.ListenMode.dictation,
    );
  }

  static void _onStatus(String status) {
    debugPrint("WakeWord STT status: $status");
    // Android often emits "notListening" or "done" after a brief
    // silence — we restart so the loop keeps running.
    if (status == "notListening" || status == "done") {
      if (_enabled && phase.value == WakeWordPhase.listening) {
        _scheduleRestart();
      }
    }
  }

  static void _scheduleRestart() {
    if (_restartScheduled) return;
    _restartScheduled = true;
    Future.delayed(const Duration(milliseconds: 200), () {
      _restartScheduled = false;
      if (!_enabled || _stt.isListening) return;
      switch (phase.value) {
        case WakeWordPhase.conversation:
          _startConversationListen();
          break;
        case WakeWordPhase.listening:
        case WakeWordPhase.idle:
          _startListening();
          break;
        default:
          break;
      }
    });
  }

  /// Phrases that take the user out of conversation mode and
  /// back to wake-word standby. Match is `contains` so partial
  /// hits work too.
  static const List<String> _exitPhrases = [
    "stop listening",
    "sleep mode",
    "go to sleep",
    "shut up",
    "stop talking",
    "exit conversation",
    "be quiet",
  ];

  static void _onPartial(SpeechRecognitionResult r) {
    final text = r.recognizedWords.toLowerCase().trim();
    lastHeard.value = text;

    switch (phase.value) {
      case WakeWordPhase.listening:
        // Wake-word phase. If the user spoke a command in the same
        // breath ("hey shapeos turn on the fan"), use the tail as
        // the first command and enter conversation mode.
        for (final w in wakeWords) {
          if (text.contains(w)) {
            final after = text.split(w).last.trim();
            if (after.length > 3) {
              _enterConversationMode(seedCommand: after);
            } else {
              _enterConversationMode();
            }
            return;
          }
        }
        break;

      case WakeWordPhase.conversation:
        // Continuous mode — wait for finalResult, then route the
        // utterance to the brain (or honour an exit phrase).
        if (!r.finalResult) break;
        if (text.isEmpty) {
          _restartTight();
          return;
        }
        if (_isExitPhrase(text)) {
          _exitConversation();
          return;
        }
        _processCommandThenContinue(r.recognizedWords);
        break;

      case WakeWordPhase.awaitingCommand:
        _commandBuffer = r.recognizedWords;
        if (r.finalResult) {
          final cmd = _commandBuffer.trim();
          _commandBuffer = "";
          _processCommand(cmd);
        }
        break;

      default:
        break;
    }
  }

  static bool _isExitPhrase(String text) {
    for (final p in _exitPhrases) {
      if (text.contains(p)) return true;
    }
    return false;
  }

  // =========================================================
  // CONVERSATION MODE
  // =========================================================
  /// Switch into continuous conversation. The user keeps talking
  /// freely, every utterance goes to the agent, until they say
  /// an exit phrase or AI mode is toggled off.
  ///
  /// If `seedCommand` is supplied the user spoke the command in
  /// the same breath as the wake word ("shapeos turn on the fan");
  /// we send that to the brain immediately, then carry on listening.
  static Future<void> _enterConversationMode({String? seedCommand}) async {
    if (!_enabled) return;
    try {
      await _stt.stop();
    } catch (_) {}

    phase.value = WakeWordPhase.conversation;

    if (seedCommand != null && seedCommand.trim().length > 3) {
      // Skip the "Yes, I'm listening" announcement when there's
      // already a command — go straight to acting on it.
      await _processCommandThenContinue(seedCommand);
      return;
    }

    await VoiceService.speak(
      "Yes, I'm in conversation mode now. Just speak — I'm listening.",
    );
    await Future.delayed(const Duration(milliseconds: 200));
    if (_enabled) _startConversationListen();
  }

  /// Leave conversation mode and go back to wake-word standby.
  static Future<void> _exitConversation() async {
    try {
      await _stt.stop();
    } catch (_) {}
    await VoiceService.speak(
      "Going back to standby. Say hey shapeos when you need me.",
    );
    phase.value = WakeWordPhase.listening;
    await Future.delayed(const Duration(milliseconds: 200));
    if (_enabled) _startListening();
  }

  /// Send the command to the brain, speak the reply, then return
  /// to conversation listening (NOT wake-word listening).
  static Future<void> _processCommandThenContinue(String command) async {
    if (!_enabled) return;
    final cmd = command.trim();
    if (cmd.isEmpty) {
      _restartTight();
      return;
    }

    phase.value = WakeWordPhase.processing;
    try {
      await _stt.stop();
    } catch (_) {}

    try {
      final devices = await _readDevices();
      final alerts = await _readAlerts();
      final reply = await AgentBrainService.ask(
        userMessage: cmd,
        devices: devices,
        alerts: alerts,
      );
      await VoiceService.speak(reply);
    } catch (e) {
      debugPrint("WakeWord conversation step failed: $e");
      await VoiceService.speak("Sorry, I had a problem with that one.");
    }

    if (!_enabled) return;
    phase.value = WakeWordPhase.conversation;
    _restartTight();
  }

  /// Tight restart — minimal gap between sessions so the user
  /// experiences continuous listening rather than a 3-second
  /// dead window.
  static void _restartTight() {
    if (!_enabled) return;
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!_enabled) return;
      if (_stt.isListening) return;
      if (phase.value == WakeWordPhase.conversation) {
        _startConversationListen();
      } else if (phase.value == WakeWordPhase.listening) {
        _startListening();
      }
    });
  }

  /// Start a long, lenient STT session for conversation mode.
  static void _startConversationListen() {
    if (!_enabled) return;
    if (_stt.isListening) return;
    try {
      _stt.listen(
        onResult: _onPartial,
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
      );
    } catch (e) {
      debugPrint("WakeWord conversation listen failed: $e");
      _restartTight();
    }
  }

  /// Legacy: process a single command then return to wake-word
  /// standby. Kept for backwards compatibility — not used in the
  /// continuous-conversation flow.
  static Future<void> _processCommand(String command) async {
    if (!_enabled) return;
    if (command.trim().isEmpty) {
      await VoiceService.speak("I didn't catch that.");
      _returnToListening();
      return;
    }

    phase.value = WakeWordPhase.processing;
    try {
      await _stt.stop();
    } catch (_) {}

    try {
      final devices = await _readDevices();
      final alerts = await _readAlerts();
      final reply = await AgentBrainService.ask(
        userMessage: command,
        devices: devices,
        alerts: alerts,
      );
      await VoiceService.speak(reply);
    } catch (e) {
      debugPrint("WakeWord processCommand failed: $e");
      await VoiceService.speak(
        "Sorry, I had a problem reaching my reasoning service.",
      );
    }

    _returnToListening();
  }

  static Future<void> _returnToListening() async {
    phase.value = WakeWordPhase.listening;
    await Future.delayed(const Duration(milliseconds: 200));
    if (_enabled) _startListening();
  }

  // =========================================================
  // STATE READS (live home)
  // =========================================================
  static Future<List<DeviceModel>> _readDevices() async {
    try {
      final snap =
          await FirebaseDatabase.instance.ref("appliances").get();
      final raw = snap.value;
      final out = <DeviceModel>[];
      if (raw is List) {
        for (var i = 0; i < raw.length; i++) {
          final v = raw[i];
          if (v is Map) {
            try {
              out.add(DeviceModel.fromMap(v, i.toString()));
            } catch (_) {}
          }
        }
      } else if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) {
            try {
              out.add(DeviceModel.fromMap(v, k.toString()));
            } catch (_) {}
          }
        });
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, bool>> _readAlerts() async {
    try {
      final snap = await FirebaseDatabase.instance.ref("alerts").get();
      final raw = snap.value;
      final out = <String, bool>{};
      if (raw is Map) {
        raw.forEach((k, v) => out[k.toString()] = v == true);
      }
      return out;
    } catch (_) {
      return {};
    }
  }
}
