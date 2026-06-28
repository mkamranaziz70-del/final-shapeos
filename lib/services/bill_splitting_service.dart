import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// =========================================================
/// BILL SPLITTING SERVICE
/// =========================================================
/// The home holds multiple users; each maps to a room and each
/// room owns a subset of devices. The bill across an arbitrary
/// date range is split across users in proportion to the energy
/// used by the devices that were active for them in that range.
///
/// Source data (written elsewhere in the app):
///   • /energy_daily/{YYYY-MM-DD}.devices  ->  per-device kWh
///   • /users/{uid}.{fullName, room, selectedDevices}
///
/// Output: only users who actually consumed energy in the chosen
/// range — quiet roommates don't appear in the split.
class UserBillShare {
  final String uid;
  final String name;
  final String room;
  final double kWh;
  final double rupees;
  final double percent;
  final int activeDays;

  const UserBillShare({
    required this.uid,
    required this.name,
    required this.room,
    required this.kWh,
    required this.rupees,
    required this.percent,
    required this.activeDays,
  });
}

class BillBreakdown {
  final String label;
  final DateTime startDate;
  final DateTime endDate;
  final double totalKWh;
  final double totalRupees;
  final List<UserBillShare> shares;
  final int totalActiveDays;

  const BillBreakdown({
    required this.label,
    required this.startDate,
    required this.endDate,
    required this.totalKWh,
    required this.totalRupees,
    required this.shares,
    required this.totalActiveDays,
  });

  static BillBreakdown get empty {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return BillBreakdown(
      label: "—",
      startDate: epoch,
      endDate: epoch,
      totalKWh: 0,
      totalRupees: 0,
      shares: const [],
      totalActiveDays: 0,
    );
  }
}

class BillSplittingService {
  BillSplittingService._();

  /// Pakistan reference tariff used elsewhere in the app.
  static const double tariffPerKWh = 55.0;

  /// kWh below which a user is considered inactive in this range
  /// and excluded from the breakdown entirely.
  static const double _activityFloor = 0.001;

  /// Compute the bill split for any inclusive date range.
  ///
  /// Bills now split per-room (via the admin-managed `/rooms/`
  /// collection). Each room contributes its occupant's name and
  /// the devices that live in it; the bill is divided
  /// proportionally to the energy used by those devices.
  static Future<BillBreakdown> compute({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final fs = FirebaseFirestore.instance;

    // Normalise to whole-day boundaries so the user can pass in
    // a partial DateTime without surprises.
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final label = _formatRange(start, end);

    // 1) Read every room — that's now the source of truth.
    final roomsSnap = await fs.collection("rooms").get();
    final users = roomsSnap.docs.map((d) {
      final data = d.data();
      return {
        "uid": d.id,
        "name": (data["occupant"] ?? data["name"] ?? "Room").toString(),
        "room": (data["name"] ?? "").toString(),
        "deviceIds":
            List<String>.from(data["deviceIds"] ?? const []),
      };
    }).toList();

    // 2) Walk every energy_daily doc inside the range and build:
    //      perDeviceKWh        — total kWh per device
    //      perDeviceActiveDays — set of YYYY-MM-DD where the device
    //                            had non-zero energy
    final perDeviceKWh = <String, double>{};
    final perDeviceActiveDays = <String, Set<String>>{};
    final daysSnap = await fs.collection("energy_daily").get();

    for (final doc in daysSnap.docs) {
      final id = doc.id;
      final docDate = DateTime.tryParse(id);
      if (docDate == null) continue;
      // Inclusive range.
      if (docDate.isBefore(start)) continue;
      if (docDate.isAfter(end)) continue;

      final devicesField = doc.data()["devices"];
      if (devicesField is! Map) continue;
      devicesField.forEach((k, v) {
        if (v is! Map) return;
        final energy = _toD(v["energy"]);
        if (energy <= 0) return;
        final deviceId = k.toString();
        perDeviceKWh.update(deviceId, (prev) => prev + energy,
            ifAbsent: () => energy);
        perDeviceActiveDays
            .putIfAbsent(deviceId, () => <String>{})
            .add(id);
      });
    }

    // 3) Aggregate per user, dropping anyone who didn't consume.
    final shares = <UserBillShare>[];
    double totalKWh = 0;
    final allActiveDays = <String>{};

    for (final u in users) {
      final ids = u["deviceIds"] as List<String>;
      double kWh = 0;
      final userDays = <String>{};
      for (final id in ids) {
        kWh += perDeviceKWh[id] ?? 0;
        userDays.addAll(perDeviceActiveDays[id] ?? const <String>{});
      }
      if (kWh < _activityFloor) continue; // inactive in this range
      totalKWh += kWh;
      allActiveDays.addAll(userDays);
      shares.add(UserBillShare(
        uid: u["uid"] as String,
        name: u["name"] as String,
        room: u["room"] as String,
        kWh: kWh,
        rupees: kWh * tariffPerKWh,
        percent: 0,
        activeDays: userDays.length,
      ));
    }

    // 4) Backfill percentages once the total is known.
    final finalShares = totalKWh <= 0
        ? shares
        : shares
            .map((s) => UserBillShare(
                  uid: s.uid,
                  name: s.name,
                  room: s.room,
                  kWh: s.kWh,
                  rupees: s.rupees,
                  percent: (s.kWh / totalKWh) * 100,
                  activeDays: s.activeDays,
                ))
            .toList();
    finalShares.sort((a, b) => b.kWh.compareTo(a.kWh));

    return BillBreakdown(
      label: label,
      startDate: start,
      endDate: end,
      totalKWh: totalKWh,
      totalRupees: totalKWh * tariffPerKWh,
      shares: finalShares,
      totalActiveDays: allActiveDays.length,
    );
  }

  /// Convenience: month-to-date (1st of current month → today).
  static Future<BillBreakdown> currentMonthToDate() async {
    final now = DateTime.now();
    return _safe(
      DateTime(now.year, now.month, 1),
      now,
    );
  }

  /// Convenience: trailing 7-day window ending today.
  static Future<BillBreakdown> last7Days() async {
    final now = DateTime.now();
    return _safe(now.subtract(const Duration(days: 6)), now);
  }

  /// Convenience: full previous month.
  static Future<BillBreakdown> lastMonth() async {
    final now = DateTime.now();
    final firstOfThis = DateTime(now.year, now.month, 1);
    final lastOfPrev = firstOfThis.subtract(const Duration(days: 1));
    final firstOfPrev =
        DateTime(lastOfPrev.year, lastOfPrev.month, 1);
    return _safe(firstOfPrev, lastOfPrev);
  }

  static Future<BillBreakdown> _safe(DateTime s, DateTime e) async {
    try {
      return await compute(startDate: s, endDate: e);
    } catch (err) {
      debugPrint("BillSplittingService failed: $err");
      return BillBreakdown.empty;
    }
  }

  static String _formatRange(DateTime s, DateTime e) {
    final df = DateFormat("MMM d");
    if (s.year == e.year && s.month == e.month) {
      return "${df.format(s)} – ${DateFormat("d, yyyy").format(e)}";
    }
    final dfFull = DateFormat("MMM d, yyyy");
    return "${dfFull.format(s)} – ${dfFull.format(e)}";
  }

  static double _toD(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
