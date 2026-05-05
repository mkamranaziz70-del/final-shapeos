// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../config/api_keys.dart';
import '../models/agent_message.dart';
import '../models/device_model.dart';
import '../services/agent_automation_engine.dart';
import '../services/agent_brain_service.dart';
import '../services/agent_mode_service.dart';
import '../services/live_readings_service.dart';
import '../services/location_service.dart';
import '../services/voice_service.dart';
import '../services/wake_word_service.dart';
import '../services/weather_service.dart';
import '../widgets/live_readings_card.dart';

/// =========================================================
/// AGENT CHAT SCREEN
/// =========================================================
/// Conversational entry point to the agent.
///   • text input + tap-to-talk (uses speech_to_text)
///   • streams replies, speaks them via flutter_tts
///   • shows a live header with location + weather so the
///     user can see the context the agent is reasoning over
class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({super.key});

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  static const Color _blue = Color(0xFF154F73);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _stt = stt.SpeechToText();

  bool _listening = false;
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    if (AgentBrainService.history.isEmpty) {
      _seedGreeting();
    }
  }

  void _seedGreeting() {
    AgentBrainService.history; // warm
    Future.microtask(() async {
      const hello =
          "Hello, I am SHAPEOS. I can manage your home, explain my decisions and answer general questions. How can I help?";
      // We push it directly into the history-mirror without an API
      // round-trip so the screen feels immediate.
      // ignore: invalid_use_of_protected_member
      AgentBrainService.history; // no-op (kept for parity)
      _pushAssistant(hello);
      await VoiceService.speak(hello);
    });
  }

  void _pushAssistant(String text) {
    setState(() {});
    // Reach into the brain's history list via clearConversation/ask
    // is not appropriate; we just speak + render via local mirror.
    _localMirror.add(AgentMessage.assistant(text));
    _scrollToBottom();
  }

  // Local mirror of messages we render. We keep it synced with the
  // brain's history after each ask().
  final List<AgentMessage> _localMirror = [];

  Future<void> _send() async {
    final raw = _input.text.trim();
    if (raw.isEmpty || _thinking) return;
    _input.clear();

    setState(() {
      _localMirror.add(AgentMessage.user(raw));
      _thinking = true;
    });
    _scrollToBottom();

    // Snapshot the live home state to feed the brain.
    final devices = await _readDevices();
    final alerts = await _readAlerts();

    final reply = await AgentBrainService.ask(
      userMessage: raw,
      devices: devices,
      alerts: alerts,
    );

    if (!mounted) return;
    setState(() {
      _localMirror.add(AgentMessage.assistant(reply));
      _thinking = false;
    });
    _scrollToBottom();

    await VoiceService.speak(reply);
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _stt.initialize();
    if (!ok) return;
    setState(() => _listening = true);
    _stt.listen(
      onResult: (r) {
        _input.text = r.recognizedWords;
        if (r.finalResult) {
          _stt.stop();
          setState(() => _listening = false);
          _send();
        }
      },
    );
  }

  Future<List<DeviceModel>> _readDevices() async {
    try {
      final snap = await FirebaseDatabase.instance.ref("appliances").get();
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

  Future<Map<String, bool>> _readAlerts() async {
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _contextHeader(),
        // The agent can pop up a live-readings card via its
        // `show_live_readings` tool. We listen for the active
        // device id and slide the card in/out above the chat.
        ValueListenableBuilder<String?>(
          valueListenable: LiveReadingsService.active,
          builder: (ctx, deviceId, _) {
            if (deviceId == null) return const SizedBox.shrink();
            return LiveReadingsCard(deviceId: deviceId);
          },
        ),
        Expanded(
          child: _localMirror.isEmpty
              ? const Center(
                  child: Text("Say or type something to begin."))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
                  itemCount: _localMirror.length + (_thinking ? 1 : 0),
                  itemBuilder: (c, i) {
                    if (_thinking && i == _localMirror.length) {
                      return const _ThinkingBubble();
                    }
                    final m = _localMirror[i];
                    return _Bubble(message: m);
                  },
                ),
        ),
        _composer(),
      ],
    );
  }

  Widget _contextHeader() {
    return Column(
      children: [
        ValueListenableBuilder<LiveLocation?>(
          valueListenable: LocationService.current,
          builder: (ctx1, loc, _) => ValueListenableBuilder<WeatherSnapshot?>(
            valueListenable: WeatherService.latest,
            builder: (ctx2, weather, _) {
              final locText = loc?.label ?? "Locating…";
              final weatherText = weather == null
                  ? "Weather: pending"
                  : "${weather.tempC.toStringAsFixed(1)}°C · ${weather.description}";
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                color: _blue.withOpacity(0.08),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        size: 16, color: _blue),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        locText,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _blue, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.cloud_outlined,
                        size: 16, color: _blue),
                    const SizedBox(width: 4),
                    Text(weatherText,
                        style: const TextStyle(
                            color: _blue, fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            },
          ),
        ),
        _wakeWordBar(),
      ],
    );
  }

  Widget _wakeWordBar() {
    return ValueListenableBuilder<WakeWordPhase>(
      valueListenable: WakeWordService.phase,
      builder: (ctx, phase, _) {
        final on = phase != WakeWordPhase.idle;
        Color dot;
        String status;
        switch (phase) {
          case WakeWordPhase.idle:
            dot = Colors.grey;
            status = "Wake word: off";
            break;
          case WakeWordPhase.listening:
            dot = Colors.green;
            status =
                'Listening for "${ApiKeys.wakeWord}"…';
            break;
          case WakeWordPhase.conversation:
            dot = const Color(0xFF24E0A0);
            status = "Conversation mode — just talk.";
            break;
          case WakeWordPhase.awaitingCommand:
            dot = Colors.amber;
            status = "Yes? — say your command";
            break;
          case WakeWordPhase.processing:
            dot = Colors.blueAccent;
            status = "Thinking…";
            break;
        }
        return InkWell(
          onTap: () async {
            final now = await WakeWordService.toggle();
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 2),
                content: Text(now
                    ? 'Wake word ON — say "${ApiKeys.wakeWord}".'
                    : "Wake word OFF."),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            color: Colors.white,
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: on,
                  activeColor: _blue,
                  onChanged: (_) => WakeWordService.toggle(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _composer() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _toggleListen,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _listening ? _blue : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _blue, width: 1.5),
                ),
                child: Icon(
                  _listening ? Icons.mic : Icons.mic_none_rounded,
                  color: _listening ? Colors.white : _blue,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: _listening
                      ? "Listening…"
                      : "Ask the agent anything…",
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _thinking ? null : _send,
              icon: const Icon(Icons.send_rounded, color: _blue),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final AgentMessage message;
  const _Bubble({required this.message});

  static const _blue = Color(0xFF154F73);

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AgentRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? _blue : Colors.grey.shade200,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(
          message.content,
          style: TextStyle(
              color: isUser ? Colors.white : Colors.black87,
              fontSize: 14.5,
              height: 1.35),
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text("Thinking…"),
          ],
        ),
      ),
    );
  }
}
