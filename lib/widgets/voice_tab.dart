// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/device_model.dart';

class VoiceTab extends StatefulWidget {
  final List<DeviceModel> appliances;
  final void Function(DeviceModel device) onToggle;

  const VoiceTab({
    super.key,
    required this.appliances,
    required this.onToggle,
  });

  @override
  State<VoiceTab> createState() => _VoiceTabState();
}

class _VoiceTabState extends State<VoiceTab> {
  static const Color themeBlue = Color(0xFF185B86);

  late stt.SpeechToText _speech;
  late FlutterTts _tts;
  late FlutterLocalNotificationsPlugin _notifications;

  bool _isListening = false;
  String _recognizedText = "Tap the microphone to start";

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _tts = FlutterTts();
    _initTts();
    _initNotifications();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.1);
    await _tts.setVolume(1.0);
  }

  Future<void> _initNotifications() async {
    _notifications = FlutterLocalNotificationsPlugin();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(initSettings);
  }

  Future<void> _showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'voice_control',
      'Voice Control',
      channelDescription: 'Voice control actions',
      importance: Importance.max,
      priority: Priority.high,
    );

    await _notifications.show(
      0,
      title,
      body,
      const NotificationDetails(android: androidDetails),
    );
  }

  // ================= VOICE LOGIC =================

  Future<void> _startListening() async {
    final available = await _speech.initialize();
    if (!available) return;

    setState(() {
      _isListening = true;
      _recognizedText = "Listening...";
    });

    _speech.listen(
      onResult: (result) {
        final text = result.recognizedWords.toLowerCase();
        _handleCommand(text);
      },
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  Future<void> _handleCommand(String command) async {
    final bool turnOn = command.contains("on");
    final bool turnOff = command.contains("off");

    for (final device in widget.appliances) {
      if (command.contains(device.name.toLowerCase())) {
        final bool newState =
            turnOn ? true : turnOff ? false : device.isOn;

        if (newState != device.isOn) {
          // 🔹 UI FEEDBACK
          setState(() {
            _recognizedText =
                "Turning ${device.name} ${newState ? "ON" : "OFF"}...";
          });

          // 🔹 EXECUTE
          widget.onToggle(device);

          await Future.delayed(const Duration(milliseconds: 400));

          final message =
              "${device.name} is now ${newState ? "ON" : "OFF"}";

          // 🔹 UI UPDATE
          setState(() {
            _recognizedText = message;
          });

          // 🔊 SPEAK IT
          await _tts.speak(message);

          // 🔔 NOTIFICATION
          _showNotification(
            "Voice Command Executed",
            message,
          );
        }
        break;
      }
    }

    await Future.delayed(const Duration(milliseconds: 800));
    _stopListening();
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 130),
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          const Text(
            "Voice Control",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Control your smart home naturally",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),

          const SizedBox(height: 28),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 26,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap:
                      _isListening ? _stopListening : _startListening,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 84,
                    width: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          _isListening ? themeBlue : Colors.white,
                      border: Border.all(
                        color: themeBlue,
                        width: 2,
                      ),
                      boxShadow: [
                        if (_isListening)
                          BoxShadow(
                            color: themeBlue.withOpacity(0.45),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                      ],
                    ),
                    child: Icon(
                      _isListening
                          ? Icons.mic_rounded
                          : Icons.mic_none_rounded,
                      color: _isListening
                          ? Colors.white
                          : themeBlue,
                      size: 38,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _recognizedText,
                    key: ValueKey(_recognizedText),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _isListening
                          ? themeBlue
                          : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 26),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Example commands",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          const SizedBox(height: 10),

          _CommandHint(text: "Turn on fan"),
          _CommandHint(text: "Turn off bulb"),
          _CommandHint(text: "Switch on pump"),
        ],
      ),
    );
  }
}

////////////////////////////////////////////////////////////
/// 🔹 COMMAND HINT
////////////////////////////////////////////////////////////

class _CommandHint extends StatelessWidget {
  final String text;
  static const Color themeBlue = Color(0xFF185B86);

  const _CommandHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.mic_rounded,
            size: 16,
            color: themeBlue,
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
