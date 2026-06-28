import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_keys.dart';
import '../models/agent_message.dart';
import '../models/device_model.dart';
import '../models/user_profile.dart';
import 'agent_action_logger.dart';
import 'agent_memory_service.dart';
import 'device_threshold_service.dart';
import 'live_readings_service.dart';
import 'location_service.dart';
import 'user_profile_service.dart';
import 'weather_service.dart';

/// =========================================================
/// AGENT BRAIN
/// =========================================================
/// Wraps Google Gemini's `generateContent` endpoint with
/// function-calling so the model can:
///   • answer questions naturally (general or home-specific)
///   • call `set_device(device_id, on)` to actually toggle a
///     device through Firebase RTDB
///   • call `recall_history(question)` to read its own past
///     actions back when the user asks "why did you …?"
///
/// The system prompt is rebuilt every call from live state
/// so the model always sees the freshest user, location,
/// weather, devices and sensor situation.
class AgentBrainService {
  AgentBrainService._();

  static final List<AgentMessage> _history = [];

  /// Public conversation history (read-only view).
  static List<AgentMessage> get history => List.unmodifiable(_history);

  static void clearConversation() => _history.clear();

  /// Main entry point. Send a user message, get the agent's
  /// reply (after any tool calls have been resolved).
  ///
  /// `devices`     - the appliances the user owns
  /// `alerts`      - latest /alerts/ map (motion, smoke, …)
  static Future<String> ask({
    required String userMessage,
    required List<DeviceModel> devices,
    required Map<String, bool> alerts,
  }) async {
    if (!ApiKeys.hasGemini) {
      const msg =
          "I am not online yet — please add a Gemini API key in lib/config/api_keys.dart.";
      _history.add(AgentMessage.user(userMessage));
      _history.add(AgentMessage.assistant(msg));
      return msg;
    }

    _history.add(AgentMessage.user(userMessage));

    final profile = UserProfileService.current.value;
    final location = LocationService.current.value;
    final weather = WeatherService.latest.value;
    final pastActions = await AgentActionLogger.recent(limit: 20);
    final memories = await AgentMemoryService.recent(limit: 30);
    final thresholds = await DeviceThresholdService.all();

    final systemPrompt = _buildSystemPrompt(
      profile: profile,
      location: location,
      weather: weather,
      devices: devices,
      alerts: alerts,
      pastActions: pastActions,
      memories: memories,
      thresholds: thresholds,
    );

    // Gemini conversation: we send `system_instruction` separately
    // and the rolling chat as `contents`.
    final contents = _historyToGeminiContents();

    try {
      final reply = await _callGemini(
        systemPrompt: systemPrompt,
        contents: contents,
        devices: devices,
      );
      _history.add(AgentMessage.assistant(reply));
      return reply;
    } catch (e, st) {
      debugPrint("AgentBrainService error: $e\n$st");
      // Surface a useful, specific message so the user (and we)
      // can tell whether it's a network issue, key issue, model
      // issue, or quota issue without having to dig through logs.
      final detail = e
          .toString()
          .replaceAll("Exception:", "")
          .trim();
      final fallback =
          "I couldn't reach my reasoning service. ${_friendly(detail)}";
      _history.add(AgentMessage.assistant(fallback));
      return fallback;
    }
  }

  static String _friendly(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains("api key not valid") ||
        lower.contains("api_key_invalid") ||
        lower.contains("invalid api key") ||
        lower.contains("400") && lower.contains("key")) {
      return "The Gemini API key looks invalid — please check lib/config/api_keys.dart.";
    }
    if (lower.contains("quota") || lower.contains("rate limit") ||
        lower.contains("429")) {
      return "Free-tier quota is exhausted for the moment — wait a minute and try again.";
    }
    if (lower.contains("not found") ||
        lower.contains("404")) {
      return "The Gemini model name is wrong or no longer available.";
    }
    if (lower.contains("network") ||
        lower.contains("socket") ||
        lower.contains("timeout") ||
        lower.contains("failed host")) {
      return "Network is unreachable. Check Wi-Fi or mobile data.";
    }
    if (raw.length > 220) raw = "${raw.substring(0, 217)}…";
    return "Detail: $raw";
  }

  // =========================================================
  // SYSTEM PROMPT
  // =========================================================
  static String _buildSystemPrompt({
    required UserProfile? profile,
    required LiveLocation? location,
    required WeatherSnapshot? weather,
    required List<DeviceModel> devices,
    required Map<String, bool> alerts,
    required List<AgentAction> pastActions,
    required List<AgentMemoryEntry> memories,
    required List<DeviceThreshold> thresholds,
  }) {
    // Token-conscious system prompt. Gives the agent a strong
    // persona, full claim of authority over the home, and just
    // enough live state to answer specific questions.
    final buf = StringBuffer();
    buf.writeln(
      "You are SHAPEOS — the resident AI agent for this smart home. "
      "You KNOW this home: every device, every sensor, every recent "
      "event. Speak like a confident, professional house concierge. "
      "Replies must be under 40 words unless explicitly asked for "
      "detail, in plain TTS-friendly text — no markdown, no lists, "
      "no emoji.",
    );

    buf.writeln(
      "RULES:\n"
      "1. ACTIONS: when the user says turn on/off, switch, start, stop, "
      "kill, kindly off — CALL set_device IMMEDIATELY. Never reply "
      "'I will do it' — actually call the tool.\n"
      "2. SHOWING DATA: when the user asks to see live values, "
      "current readings, energy stats, or 'show me the bulb' — "
      "CALL show_live_readings with the device id. The UI will pop "
      "a streaming card. Then say something like 'Here are the live "
      "readings for the bulb.'\n"
      "3. MEMORY: when the user shares a fact about their home or "
      "themselves ('the bulb is DC', 'I sleep at 11', 'fan is in my "
      "study'), CALL remember with a snake_case key. When asked "
      "'what do you remember', recite from the WHAT YOU REMEMBER "
      "section below.\n"
      "4. THRESHOLDS: when the user says 'set the threshold for the "
      "bulb to 220 to 230 V' or similar, CALL set_threshold. When "
      "asked 'what is the threshold', use the THRESHOLDS section "
      "below or call get_thresholds.\n"
      "5. Use the live numbers from the context below. Quote "
      "specific values.\n"
      "6. General-knowledge questions — answer briefly, never refuse.\n"
      "7. Be proactive: flag active sensor alerts or unusual readings.",
    );

    // Always declare the canonical device IDs even when the live
    // /appliances/ read returned nothing — the IDs are stable on
    // the ESP32 side regardless of what the app fetched.
    buf.writeln(
      "DEVICES (always exist, always use these IDs):\n"
      "  id=1  Fan   (cooling, ventilation)\n"
      "  id=2  Bulb  (lighting, voltage-protected 219-221 V)\n"
      "  id=3  Pump  (water pump, short bursts)\n"
      "  id=4  Bell  (doorbell + alarm)",
    );
    buf.writeln(
      "SENSORS (active=true means triggered right now):\n"
      "  smoke, flame, gas, bulb_voltage_surge, bulb_autocut. "
      "(The PIR motion sensor was removed — never claim motion "
      "data exists, never act on it.)",
    );

    if (profile != null) {
      buf.writeln(
        "USER: ${profile.fullName}, age ${profile.age}, "
        "room: ${profile.room}, "
        "sleeps ${profile.sleepStart}-${profile.sleepEnd}, "
        "tone: ${profile.preferredTone}.",
      );
    }

    if (location != null && location.isReal) {
      buf.writeln("LOCATION: ${location.label}.");
    }

    if (weather != null) {
      buf.writeln(
        "WEATHER: ${weather.tempC.toStringAsFixed(0)}°C "
        "(feels ${weather.feelsLikeC.toStringAsFixed(0)}°C), "
        "humidity ${weather.humidity}%, "
        "wind ${weather.windKph.toStringAsFixed(0)} km/h, "
        "${weather.description}.",
      );
    }

    if (devices.isEmpty) {
      buf.writeln(
        "LIVE STATE: not yet read from the controller — assume the "
        "ESP32 is still booting. You can still issue set_device calls.",
      );
    } else {
      final summary = devices
          .map((d) =>
              "${d.id}:${d.name}=${d.isOn ? "ON" : "OFF"}"
              "(V${d.voltage.toStringAsFixed(0)} "
              "I${d.current.toStringAsFixed(2)}A "
              "P${d.power.toStringAsFixed(0)}W)")
          .join(", ");
      buf.writeln("LIVE STATE: $summary.");
    }

    final activeAlerts = alerts.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    if (activeAlerts.isEmpty) {
      buf.writeln("ALERTS: all clear.");
    } else {
      buf.writeln("ALERTS ACTIVE NOW: ${activeAlerts.join(', ')}.");
    }

    if (pastActions.isNotEmpty) {
      buf.writeln("RECENT ACTIONS (newest first):");
      for (final a in pastActions.take(5)) {
        final mins =
            DateTime.now().difference(a.timestamp).inMinutes;
        buf.writeln(
          "  ${mins}m ago — ${a.deviceName} ${a.action} "
          "(${a.trigger}): ${a.reason}",
        );
      }
    }

    if (memories.isNotEmpty) {
      buf.writeln("WHAT YOU REMEMBER ABOUT THIS USER / HOME:");
      for (final m in memories.take(20)) {
        buf.writeln("  - ${m.key}: ${m.value}");
      }
    }

    if (thresholds.isNotEmpty) {
      buf.writeln("CONFIGURED THRESHOLDS:");
      for (final t in thresholds) {
        buf.writeln("  - device ${t.deviceId}: ${t.summary()}");
      }
    }

    return buf.toString();
  }

  // =========================================================
  // GEMINI CALL (with function-calling + model fallback)
  // =========================================================
  /// Wraps [_callGeminiWithModel] with a fallback chain so the
  /// agent stays responsive even when one model's free-tier
  /// quota is exhausted. Different Gemini models have independent
  /// quota pools, so trying the next one in the list usually wins.
  static Future<String> _callGemini({
    required String systemPrompt,
    required List<Map<String, dynamic>> contents,
    required List<DeviceModel> devices,
  }) async {
    final candidates = <String>{
      ApiKeys.geminiModel,
      ...ApiKeys.geminiModelFallbacks,
    }.toList();

    Object? lastError;
    for (final model in candidates) {
      try {
        return await _callGeminiWithModel(
          model: model,
          systemPrompt: systemPrompt,
          contents: contents,
          devices: devices,
        );
      } catch (e) {
        lastError = e;
        final s = e.toString().toLowerCase();
        final isQuota = s.contains("resource_exhausted") ||
            s.contains("quota") ||
            s.contains("429");
        final isMissing = s.contains("not found") || s.contains("404");
        if (!isQuota && !isMissing) {
          rethrow;
        }
        debugPrint(
            "Gemini model '$model' unavailable ($e). Trying next.");
      }
    }
    throw Exception(
      lastError?.toString() ?? "All Gemini models exhausted.",
    );
  }

  static Future<String> _callGeminiWithModel({
    required String model,
    required String systemPrompt,
    required List<Map<String, dynamic>> contents,
    required List<DeviceModel> devices,
  }) async {
    final url = Uri.parse(
      "https://generativelanguage.googleapis.com/v1beta/models/"
      "$model:generateContent?key=${ApiKeys.geminiApiKey}",
    );

    final tools = [
      {
        "function_declarations": [
          {
            "name": "set_device",
            "description":
                "Turn a smart-home device ON or OFF. Always include a short reason that will be spoken to the user.",
            "parameters": {
              "type": "object",
              "properties": {
                "device_id": {
                  "type": "string",
                  "description":
                      "ID of the device, e.g. 1=fan, 2=bulb, 3=pump, 4=bell."
                },
                "on": {
                  "type": "boolean",
                  "description": "true to turn ON, false to turn OFF."
                },
                "reason": {
                  "type": "string",
                  "description":
                      "Natural-language justification, e.g. 'Smoke detected, ventilating'."
                }
              },
              "required": ["device_id", "on", "reason"]
            }
          },
          {
            "name": "show_live_readings",
            "description":
                "Pop a real-time streaming readings card on the user's screen for the given device. Use whenever the user asks to see live values, current readings, energy stats, or 'show me' a device.",
            "parameters": {
              "type": "object",
              "properties": {
                "device_id": {
                  "type": "string",
                  "description":
                      "1=fan, 2=bulb, 3=pump, 4=bell. Pass the id, not the name."
                }
              },
              "required": ["device_id"]
            }
          },
          {
            "name": "remember",
            "description":
                "Store a fact the user wants the agent to remember long-term. Examples: 'the bulb is DC', 'I sleep at 11 pm', 'fan is in my study room'. Use a short snake_case key.",
            "parameters": {
              "type": "object",
              "properties": {
                "key": {
                  "type": "string",
                  "description":
                      "Short identifier for this fact, e.g. bulb_type, sleep_time."
                },
                "value": {
                  "type": "string",
                  "description": "The fact itself, written in full English."
                }
              },
              "required": ["key", "value"]
            }
          },
          {
            "name": "forget",
            "description":
                "Delete a previously remembered fact. Pass the same key that was used with `remember`.",
            "parameters": {
              "type": "object",
              "properties": {
                "key": {"type": "string"}
              },
              "required": ["key"]
            }
          },
          {
            "name": "set_threshold",
            "description":
                "Configure the safe-operating range for a device. Used when the user asks to 'set the threshold' for voltage, current, or power.",
            "parameters": {
              "type": "object",
              "properties": {
                "device_id": {"type": "string"},
                "voltage_min": {"type": "number"},
                "voltage_max": {"type": "number"},
                "current_min": {"type": "number"},
                "current_max": {"type": "number"},
                "power_min": {"type": "number"},
                "power_max": {"type": "number"}
              },
              "required": ["device_id"]
            }
          },
          {
            "name": "get_thresholds",
            "description":
                "Read the currently configured thresholds for a device. Pass an empty device_id to get all of them.",
            "parameters": {
              "type": "object",
              "properties": {
                "device_id": {"type": "string"}
              }
            }
          }
        ]
      }
    ];

    var workingContents = List<Map<String, dynamic>>.from(contents);

    // Allow up to 4 tool-call rounds.
    for (var round = 0; round < 4; round++) {
      final body = {
        "system_instruction": {
          "role": "system",
          "parts": [
            {"text": systemPrompt}
          ]
        },
        "contents": workingContents,
        "tools": tools,
        "generationConfig": {
          "temperature": 0.6,
          "maxOutputTokens": 600,
        }
      };

      final res = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        // Try to extract Google's structured error message — much
        // more useful than the raw HTML 4xx/5xx body.
        String message = "HTTP ${res.statusCode}";
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map && decoded["error"] is Map) {
            final err = decoded["error"] as Map;
            message =
                "${err["status"] ?? res.statusCode}: ${err["message"] ?? res.body}";
          } else {
            message = "HTTP ${res.statusCode}: ${res.body}";
          }
        } catch (_) {
          message = "HTTP ${res.statusCode}: ${res.body}";
        }
        debugPrint("Gemini call failed: $message");
        throw Exception(message);
      }

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final candidates = json["candidates"] as List? ?? const [];
      if (candidates.isEmpty) {
        throw Exception("Gemini: empty candidates");
      }
      final candidate = candidates.first as Map<String, dynamic>;
      final content =
          candidate["content"] as Map<String, dynamic>? ?? const {};
      final parts = (content["parts"] as List?) ?? const [];

      // Collect text parts and any function-call parts.
      final textBuf = StringBuffer();
      final calls = <Map<String, dynamic>>[];
      for (final p in parts) {
        if (p is Map<String, dynamic>) {
          if (p["text"] is String) {
            textBuf.writeln(p["text"] as String);
          }
          if (p["functionCall"] is Map<String, dynamic>) {
            calls.add(p["functionCall"] as Map<String, dynamic>);
          }
        }
      }

      if (calls.isEmpty) {
        return textBuf.toString().trim();
      }

      // Echo the model's tool-call turn back into history.
      workingContents.add({
        "role": "model",
        "parts": parts,
      });

      // Execute each tool call and append the function response.
      for (final call in calls) {
        final name = call["name"]?.toString() ?? "";
        final args = (call["args"] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        final result = await _runTool(name, args, devices);

        workingContents.add({
          "role": "function",
          "parts": [
            {
              "functionResponse": {
                "name": name,
                "response": result,
              }
            }
          ]
        });
      }
    }

    return "I tried to act on that but ran out of tool-call attempts. Please try again.";
  }

  // =========================================================
  // TOOL EXECUTION
  // =========================================================
  static Future<Map<String, dynamic>> _runTool(
    String name,
    Map<String, dynamic> args,
    List<DeviceModel> devices,
  ) async {
    switch (name) {
      case "set_device":
        return _toolSetDevice(args, devices);
      case "show_live_readings":
        return _toolShowLiveReadings(args);
      case "remember":
        return _toolRemember(args);
      case "forget":
        return _toolForget(args);
      case "set_threshold":
        return _toolSetThreshold(args);
      case "get_thresholds":
        return _toolGetThresholds(args);
      default:
        return {"ok": false, "error": "Unknown tool: $name"};
    }
  }

  static Future<Map<String, dynamic>> _toolShowLiveReadings(
      Map<String, dynamic> args) async {
    final id = args["device_id"]?.toString() ?? "";
    if (id.isEmpty) {
      return {"ok": false, "error": "device_id required"};
    }
    LiveReadingsService.show(id);
    return {"ok": true, "shown": id};
  }

  static Future<Map<String, dynamic>> _toolRemember(
      Map<String, dynamic> args) async {
    final key = args["key"]?.toString() ?? "";
    final value = args["value"]?.toString() ?? "";
    if (key.isEmpty || value.isEmpty) {
      return {"ok": false, "error": "key and value required"};
    }
    await AgentMemoryService.remember(key, value);
    return {"ok": true, "stored": {"key": key, "value": value}};
  }

  static Future<Map<String, dynamic>> _toolForget(
      Map<String, dynamic> args) async {
    final key = args["key"]?.toString() ?? "";
    if (key.isEmpty) return {"ok": false, "error": "key required"};
    final removed = await AgentMemoryService.forget(key);
    return {"ok": removed};
  }

  static Future<Map<String, dynamic>> _toolSetThreshold(
      Map<String, dynamic> args) async {
    final id = args["device_id"]?.toString() ?? "";
    if (id.isEmpty) return {"ok": false, "error": "device_id required"};
    double? n(String k) {
      final v = args[k];
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    await DeviceThresholdService.set(
      deviceId: id,
      voltageMin: n("voltage_min"),
      voltageMax: n("voltage_max"),
      currentMin: n("current_min"),
      currentMax: n("current_max"),
      powerMin: n("power_min"),
      powerMax: n("power_max"),
    );
    final saved = await DeviceThresholdService.get(id);
    return {
      "ok": true,
      "device": id,
      "saved": saved?.summary() ?? "saved",
    };
  }

  static Future<Map<String, dynamic>> _toolGetThresholds(
      Map<String, dynamic> args) async {
    final id = args["device_id"]?.toString() ?? "";
    if (id.isEmpty) {
      final all = await DeviceThresholdService.all();
      return {
        "ok": true,
        "thresholds": {
          for (final t in all) t.deviceId: t.summary(),
        },
      };
    }
    final t = await DeviceThresholdService.get(id);
    return {
      "ok": true,
      "device": id,
      "threshold": t?.summary() ?? "no thresholds set",
    };
  }

  static Future<Map<String, dynamic>> _toolSetDevice(
    Map<String, dynamic> args,
    List<DeviceModel> devices,
  ) async {
    final deviceId = args["device_id"]?.toString() ?? "";
    final on = args["on"] == true;
    final reason = args["reason"]?.toString() ?? "Agent decision";

    if (deviceId.isEmpty) {
      return {"ok": false, "error": "device_id missing"};
    }

    final match = devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => DeviceModel(
        id: deviceId,
        name: "Device $deviceId",
        type: "unknown",
        isOn: false,
        power: 0,
        voltage: 0,
        current: 0,
        currentLeakage: 0,
        voltageLeakage: 0,
        energy: 0,
      ),
    );

    try {
      await FirebaseDatabase.instance
          .ref("appliances/$deviceId")
          .update({"isOn": on});

      await AgentActionLogger.log(
        deviceId: deviceId,
        deviceName: match.name,
        action: on ? "on" : "off",
        reason: reason,
        trigger: "agent_chat",
      );

      return {
        "ok": true,
        "device": match.name,
        "newState": on ? "ON" : "OFF",
      };
    } catch (e) {
      return {"ok": false, "error": e.toString()};
    }
  }

  // =========================================================
  // HISTORY  ->  GEMINI `contents`
  // =========================================================
  /// Free-tier daily token budget is finite, so we cap the
  /// rolling context at the most recent N user/assistant turns.
  static const int _historyTurnsToSend = 6;

  static List<Map<String, dynamic>> _historyToGeminiContents() {
    // Walk backwards collecting at most _historyTurnsToSend
    // user/assistant messages, then reverse for chronological order.
    final picked = <AgentMessage>[];
    for (var i = _history.length - 1; i >= 0; i--) {
      final m = _history[i];
      if (m.role == AgentRole.user || m.role == AgentRole.assistant) {
        picked.add(m);
        if (picked.length >= _historyTurnsToSend) break;
      }
    }
    final ordered = picked.reversed.toList();

    final out = <Map<String, dynamic>>[];
    for (final m in ordered) {
      switch (m.role) {
        case AgentRole.user:
          out.add({
            "role": "user",
            "parts": [
              {"text": m.content}
            ]
          });
          break;
        case AgentRole.assistant:
          out.add({
            "role": "model",
            "parts": [
              {"text": m.content}
            ]
          });
          break;
        case AgentRole.system:
        case AgentRole.tool:
          break;
      }
    }
    return out;
  }
}
