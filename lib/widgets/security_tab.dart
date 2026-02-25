import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
class _NoGlowScroll extends ScrollBehavior {
  const _NoGlowScroll();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context,
      Widget child,
      ScrollableDetails details) {
    return child;
  }
}
class SecurityTab extends StatefulWidget {
  const SecurityTab({super.key});

  @override
  State<SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<SecurityTab>
    with AutomaticKeepAliveClientMixin {
  // ignore: unused_field
  static const Color primaryBlue = Color(0xFF154F73);

  late final DatabaseReference alertsRef;

  late final Stream<DatabaseEvent> alertsStream;

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();

  final Set<String> _spokenAlerts = {}; // prevent repeat alerts

  @override
  void initState() {
    super.initState();
_spokenAlerts.clear();
    alertsRef = FirebaseDatabase.instance.ref("alerts");

    alertsStream = alertsRef.onValue;

    // 🔊 MAX PERCEIVED LOUDNESS SETTINGS
    _tts.setLanguage("en-US");
    _tts.setVolume(1.0);          // max allowed
    _tts.setPitch(1.35);          // higher pitch = more noticeable
    _tts.setSpeechRate(0.38);     // slower = sounds louder
    _tts.awaitSpeakCompletion(true);
  }

  @override
  bool get wantKeepAlive => true;
@override
Widget build(BuildContext context) {
  super.build(context);

  return ScrollConfiguration(
  behavior: const _NoGlowScroll(),
  child: ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
    children: [
      const _SectionTitle("Current Alerts"),
      _CurrentAlertsGrid(
        stream: alertsStream,
        onAlert: _handleAlert,
        spokenCache: _spokenAlerts,
      ),
    ],
  ),
);
}

  /// 🚨 SOUND + VOICE + VIBRATION (EMERGENCY GRADE)
  Future<void> _handleAlert(String type) async {
    // 🔔 Play loud alert sound first
    await _player.play(
      AssetSource("sounds/alert.wav"),
      volume: 1.0,
    );

    // 📳 Strong vibration
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 1200);
    }

    // 🗣️ Emergency voice message
    switch (type) {
      case "flame":
        await _tts.speak(
          "Emergency! Fire detected. Please take action immediately.",
        );
        break;
      case "smoke":
        await _tts.speak(
          "Warning! Smoke detected.",
        );
        break;
      case "motion":
        await _tts.speak(
          "Alert! Motion detected.",
        );
        break;
        case "fanovercurrent":
  await _tts.speak(
    "Warning! Fan overcurrent detected. Device may be unsafe.",
  );
  break;
    }
  }
}

////////////////////////////////////////////////////////////
/// CURRENT ALERTS GRID
////////////////////////////////////////////////////////////

class _CurrentAlertsGrid extends StatelessWidget {
  final Stream<DatabaseEvent> stream;
  final Function(String type) onAlert;
  final Set<String> spokenCache;

  const _CurrentAlertsGrid({
    required this.stream,
    required this.onAlert,
    required this.spokenCache,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: stream,
builder: (context, snapshot) {
  if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
    spokenCache.clear();
    return const _EmptyText("No active alerts");
  }

  final raw = snapshot.data!.snapshot.value as Map;
  final Map<String, dynamic> data =
      Map<String, dynamic>.from(raw);

  final List<MapEntry<String, dynamic>> activeItems = [];

  data.forEach((key, value) {
    bool isActive = false;

    // 🔥 Handle BOTH data structures
    if (value is bool) {
      isActive = value;
    } else if (value is Map) {
      isActive = value['active'] == true;
    }

    if (isActive) {
      activeItems.add(MapEntry(key, value));
    }
  });

  // Remove inactive from cache
  final activeKeys =
      activeItems.map((e) => e.key.toLowerCase()).toSet();

  spokenCache.removeWhere((key) => !activeKeys.contains(key));

  if (activeItems.isEmpty) {
    return const _EmptyText("No active alerts");
  }

  return GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1,
    ),
    itemCount: activeItems.length,
    itemBuilder: (context, index) {
      final type =
          activeItems[index].key.toLowerCase();

      if (!spokenCache.contains(type)) {
        spokenCache.add(type);
        onAlert(type);
      }

      return _AlertSquareCard(
        title: activeItems[index].key,
      );
    },
  );
}
    );
  }
}

////////////////////////////////////////////////////////////
/// ALERT CARD (SEVERITY COLORS)
////////////////////////////////////////////////////////////

class _AlertSquareCard extends StatelessWidget {
  final String title;

  const _AlertSquareCard({required this.title});

  @override
  Widget build(BuildContext context) {
    final severity = _severity(title);

    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      color: severity.bg,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(severity.icon, size: 40, color: Colors.white),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  _Severity _severity(String text) {
    final t = text.toLowerCase();
    if (t.contains("flame")) {
      return _Severity(Icons.local_fire_department, Colors.red.shade700);
    }
    if (t.contains("smoke")) {
      return _Severity(Icons.smoke_free, Colors.red.shade600);
    }
    if (t.contains("motion")) {
      return _Severity(Icons.directions_run, Colors.orange.shade700);
    }
    if (t.contains("overcurrent")) {
  return _Severity(Icons.flash_on, Colors.deepOrange.shade700);
}
    return _Severity(Icons.warning, Colors.grey);
    
  }
  
}

class _Severity {
  final IconData icon;
  final Color bg;
  _Severity(this.icon, this.bg);
}



////////////////////////////////////////////////////////////
/// SECTION TITLE / EMPTY
////////////////////////////////////////////////////////////

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  final String text;
  const _EmptyText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text, style: const TextStyle(color: Colors.grey)),
    );
  }
}
