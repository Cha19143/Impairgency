/// One navigation the visually impaired user started, as the guardian sees it.
///
/// The route itself is not stored. A guardian who opens an entry asks
/// OpenStreetMap for the walking line from the origin to the destination.
library;

/// How a trip ended, or that it has not ended yet.
enum NavigationStatus { ongoing, completed, cancelled }

/// The status filter on the guardian's list. Ongoing is not a filter: a trip
/// still marked ongoing after two hours is shown as cancelled.
enum NavigationStatusFilter { all, completed, cancelled }

/// How far back the list looks. The widest is also the retention window.
enum NavigationDateFilter { today, last7Days, last30Days }

/// Trips older than this are not shown, and are due for deletion.
const Duration kNavigationRetention = Duration(days: 30);

/// An ongoing trip older than this is shown and filtered as cancelled.
///
/// The phone may have been killed mid-navigation, which never gets to write
/// an ending. Two hours is long enough for a real walk and short enough that
/// a dead session does not sit on the guardian's list as if it were live.
const Duration kNavigationStaleOngoing = Duration(hours: 2);

/// How many trips one page of the guardian's list asks for.
const int kNavigationHistoryPageSize = 20;

extension NavigationStatusLabel on NavigationStatus {
  String get label => switch (this) {
    NavigationStatus.ongoing => 'Ongoing',
    NavigationStatus.completed => 'Completed',
    NavigationStatus.cancelled => 'Cancelled',
  };
}

extension NavigationStatusFilterLabel on NavigationStatusFilter {
  String get label => switch (this) {
    NavigationStatusFilter.all => 'All',
    NavigationStatusFilter.completed => 'Completed',
    NavigationStatusFilter.cancelled => 'Cancelled',
  };
}

extension NavigationDateFilterLabel on NavigationDateFilter {
  String get label => switch (this) {
    NavigationDateFilter.today => 'Today',
    NavigationDateFilter.last7Days => 'Last 7 days',
    NavigationDateFilter.last30Days => 'Last 30 days',
  };
}

/// The first instant included by [filter], in local time for [today] and as
/// a rolling window otherwise.
DateTime navigationRangeStart(NavigationDateFilter filter, DateTime now) {
  switch (filter) {
    case NavigationDateFilter.today:
      final local = now.toLocal();
      return DateTime(local.year, local.month, local.day);
    case NavigationDateFilter.last7Days:
      return now.subtract(const Duration(days: 7));
    case NavigationDateFilter.last30Days:
      return now.subtract(kNavigationRetention);
  }
}

/// "Oct 15, 2026 - 3:42 PM", in the phone's local time.
String formatNavigationWhen(DateTime at) {
  final local = at.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour24 = local.hour;
  final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = hour24 < 12 ? 'AM' : 'PM';
  return '${months[local.month - 1]} ${local.day}, ${local.year} - '
      '$hour:$minute $period';
}

/// What the empty list should say, or null when there are rows to show.
///
/// "No navigation history yet." is only for a last-30-days query that came
/// back empty. Any narrower filter that matches nothing says so.
String? navigationHistoryEmptyMessage({
  required bool loading,
  required bool hasError,
  required int fetched,
  required int visible,
  required NavigationDateFilter date,
}) {
  if (loading || hasError || visible > 0) return null;
  if (fetched == 0 && date == NavigationDateFilter.last30Days) {
    return 'No navigation history yet.';
  }
  return 'No results for this filter.';
}

/// One stored trip. [status] is what was written; [displayStatus] is what the
/// guardian is shown, including the two-hour rule.
class NavigationEntry {
  const NavigationEntry({
    required this.id,
    required this.destinationName,
    required this.destinationAddress,
    required this.destinationLat,
    required this.destinationLng,
    required this.originLat,
    required this.originLng,
    required this.startedAt,
    required this.endedAt,
    required this.status,
    this.expiresAt,
  });

  final String id;
  final String destinationName;
  final String destinationAddress;
  final double destinationLat;
  final double destinationLng;
  final double originLat;
  final double originLng;
  final DateTime startedAt;
  final DateTime? endedAt;
  final NavigationStatus status;
  final DateTime? expiresAt;

  /// [status], except an ongoing trip that started more than two hours ago,
  /// which is shown as cancelled.
  NavigationStatus displayStatus(DateTime now) {
    if (status == NavigationStatus.ongoing &&
        now.difference(startedAt) > kNavigationStaleOngoing) {
      return NavigationStatus.cancelled;
    }
    return status;
  }

  /// Whether this trip belongs in a list filtered by [filter].
  bool matchesFilter(NavigationStatusFilter filter, DateTime now) {
    final shown = displayStatus(now);
    return switch (filter) {
      NavigationStatusFilter.all => true,
      NavigationStatusFilter.completed => shown == NavigationStatus.completed,
      NavigationStatusFilter.cancelled => shown == NavigationStatus.cancelled,
    };
  }

  /// Null when the document is missing a field the list cannot do without.
  /// A server timestamp that has not landed yet is skipped until it has.
  static NavigationEntry? tryParse(String id, Map<String, dynamic> data) {
    final name = data['destinationName'];
    final address = data['destinationAddress'];
    final destinationLat = data['destinationLat'];
    final destinationLng = data['destinationLng'];
    final originLat = data['originLat'];
    final originLng = data['originLng'];
    final startedAt = data['startedAt'];
    final status = _status(data['status']);
    if (name is! String ||
        name.isEmpty ||
        address is! String ||
        destinationLat is! num ||
        destinationLng is! num ||
        originLat is! num ||
        originLng is! num ||
        startedAt is! DateTime ||
        status == null) {
      return null;
    }
    final endedAt = data['endedAt'];
    final expiresAt = data['expiresAt'];
    return NavigationEntry(
      id: id,
      destinationName: name,
      destinationAddress: address,
      destinationLat: destinationLat.toDouble(),
      destinationLng: destinationLng.toDouble(),
      originLat: originLat.toDouble(),
      originLng: originLng.toDouble(),
      startedAt: startedAt,
      endedAt: endedAt is DateTime ? endedAt : null,
      status: status,
      expiresAt: expiresAt is DateTime ? expiresAt : null,
    );
  }
}

NavigationStatus? _status(Object? raw) {
  if (raw is! String) return null;
  for (final status in NavigationStatus.values) {
    if (status.name == raw) return status;
  }
  return null;
}
