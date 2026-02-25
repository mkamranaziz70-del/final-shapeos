// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
class LogsTab extends StatelessWidget {
  const LogsTab({super.key});

  static const Color themeBlue = Color(0xFF185B86);

  DateTime _parseTimestamp(String ts) {
    try {
      final parts = ts.split(' ');
      final date = parts[0].split('-');
      final time = parts[1].split(':');

      return DateTime(
        int.parse(date[0]),
        int.parse(date[1]),
        int.parse(date[2]),
        int.parse(time[0]),
        int.parse(time[1]),
        int.parse(time[2]),
      );
    } catch (_) {
      return DateTime(1970);
    }
  }

 @override
Widget build(BuildContext context) {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final dbRef =
      FirebaseDatabase.instance.ref("users/$uid/logs");

  return StreamBuilder<DatabaseEvent>(
    stream: dbRef.onValue,
    builder: (context, snapshot) {
      if (snapshot.connectionState ==
          ConnectionState.waiting) {
        return const Center(
            child: CircularProgressIndicator());
      }

      if (!snapshot.hasData ||
          snapshot.data!.snapshot.value == null) {
        return const _EmptyState();
      }

      final raw =
          snapshot.data!.snapshot.value
              as Map<dynamic, dynamic>;

      final logs = raw.entries.map((entry) {
        final value = entry.value;

        if (value is Map) {
          final map =
              Map<String, dynamic>.from(value);
          return _LogItem(
            event: map['event'] ?? '',
            time: map['time'] ?? '',
            dateTime:
                _parseTimestamp(map['time'] ?? ''),
          );
        }

        return _LogItem(
          event: value.toString(),
          time: '',
          dateTime: DateTime(1970),
        );
      }).toList();

      logs.sort((a, b) =>
          b.dateTime.compareTo(a.dateTime));

      return ListView.builder(
        padding:
            const EdgeInsets.fromLTRB(16, 16, 16, 110),
        itemCount: logs.length,
        itemBuilder: (context, index) {
          return Padding(
            padding:
                const EdgeInsets.only(bottom: 14),
            child: _CleanLogCard(
                log: logs[index]),
          );
        },
      );
    },
  );
}
}

////////////////////////////////////////////////////////////
/// 🔹 LOG MODEL
////////////////////////////////////////////////////////////

class _LogItem {
  final String event;
  final String time;
  final DateTime dateTime;

  _LogItem({
    required this.event,
    required this.time,
    required this.dateTime,
  });
}

////////////////////////////////////////////////////////////
/// 🧼 CLEAN PROFESSIONAL LOG CARD (NO BLUR)
////////////////////////////////////////////////////////////

class _CleanLogCard extends StatelessWidget {
  final _LogItem log;
  static const Color themeBlue = Color(0xFF185B86);

  const _CleanLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 TIMELINE STRIP (SOLID COLOR)
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: themeBlue,
              borderRadius: BorderRadius.circular(4),
            ),
          ),

          const SizedBox(width: 14),

          // 🔹 LOG CONTENT
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.event,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  log.time,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          const Icon(
            Icons.history_rounded,
            size: 20,
            color: Colors.grey,
          ),
        ],
      ),
    );
  }
}

////////////////////////////////////////////////////////////
/// 🔹 EMPTY STATE (CLEAN)
////////////////////////////////////////////////////////////

class _EmptyState extends StatelessWidget {
  static const Color themeBlue = Color(0xFF185B86);

  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 48,
            color: Colors.grey,
          ),
          SizedBox(height: 12),
          Text(
            "No Activity Logs",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            "Device actions will appear here",
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
