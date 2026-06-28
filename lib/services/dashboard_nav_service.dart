import 'package:flutter/foundation.dart';

/// =========================================================
/// DASHBOARD NAV SERVICE
/// =========================================================
/// Tiny pub-sub for cross-tab navigation. Any widget anywhere
/// in the dashboard can call `requestTab(index)` and the
/// dashboard's bottom-nav will switch to that index.
///
/// Used so the Energy tab's "View AI Optimization Report" CTA
/// can deep-link into the Optimization tab without us having
/// to thread a callback through every widget.
class DashboardNavService {
  DashboardNavService._();

  /// Latest requested tab index, or null when nothing pending.
  /// Dashboard listens to this and switches its bottom-nav.
  static final ValueNotifier<int?> requestedTab =
      ValueNotifier<int?>(null);

  static void switchTo(int index) {
    requestedTab.value = index;
  }

  static void clear() {
    requestedTab.value = null;
  }
}

/// Canonical tab indices — keep in sync with the dashboard
/// `tabs` list so callers can use a name instead of a number.
class DashboardTab {
  DashboardTab._();
  static const home = 0;
  static const rooms = 1;
  static const optimization = 2;
  static const control = 3;
  static const anomalies = 4;
  static const energy = 5;
  static const bills = 6;
  static const security = 7;
  static const logs = 8;
  static const voice = 9;
  static const agent = 10;
}
