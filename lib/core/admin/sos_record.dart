/// One SOS, as the dashboard lists it.
///
/// The phone writes `sos_events`; nothing on the dashboard read them, so an
/// emergency fired in front of a tester never reached it. The Emergencies
/// tile summed a counter from session summaries the app did not write.
///
/// Flutter- and Firestore-free: the repository turns timestamps into
/// [DateTime]s and hands the rest over as it came.
library;

enum SosStatus {
  /// Fired, and nobody has said it is over.
  active,

  /// Stopped before anyone was called.
  cancelled,

  /// Said to be over - by the user, or by an administrator.
  resolved,
}

class SosRecord {
  const SosRecord({
    required this.id,
    required this.userId,
    this.at,
    this.lat,
    this.lng,
    this.accuracyMetres,
    this.locationSummary,
    this.contactName,
    this.cancelled = false,
    this.stage,
    this.resolvedAt,
    this.resolvedBy,
  });

  /// [data] as a `sos_events` document holds it. [toDate] reads a
  /// timestamp field, which only the caller knows how to.
  factory SosRecord.fromJson(
    String id,
    Map<String, Object?> data, {
    required DateTime? Function(Object? value) toDate,
  }) {
    final contact = data['contact'];
    return SosRecord(
      id: id,
      userId: data['userId'] as String? ?? '',
      at: toDate(data['at']),
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      accuracyMetres: (data['accuracy'] as num?)?.toDouble(),
      locationSummary: data['locationSummary'] as String?,
      contactName: contact is Map ? contact['name'] as String? : null,
      cancelled: data['cancelled'] == true,
      stage: data['stage'] as String?,
      resolvedAt: toDate(data['resolvedAt']),
      resolvedBy: data['resolvedBy'] as String?,
    );
  }

  final String id;
  final String userId;

  /// When the server took it. Null for a moment after it is written.
  final DateTime? at;

  final double? lat;
  final double? lng;
  final double? accuracyMetres;

  /// The sentence the phone said about the position.
  final String? locationSummary;

  /// Who was rung first.
  final String? contactName;

  final bool cancelled;

  /// How far a cancelled SOS had gone: 'before-call' when the alarm had
  /// already sounded. Null for a countdown stopped in time.
  final String? stage;

  final DateTime? resolvedAt;

  /// 'user', or the uid of the administrator who resolved it.
  final String? resolvedBy;

  SosStatus get status => cancelled
      ? SosStatus.cancelled
      : resolvedAt != null || resolvedBy != null
          ? SosStatus.resolved
          : SosStatus.active;

  bool get hasPosition => lat != null && lng != null;

  /// How the status reads in the table.
  String get statusLabel => switch (status) {
        SosStatus.active => 'Active',
        SosStatus.cancelled =>
          stage == 'before-call' ? 'Cancelled before the call' : 'Cancelled',
        SosStatus.resolved =>
          resolvedBy == 'user' ? 'Resolved by user' : 'Resolved by admin',
      };

  /// A map of where it happened that anyone can open, with no key.
  Uri? get mapLink => hasPosition
      ? Uri.https('www.openstreetmap.org', '/', {
          'mlat': '$lat',
          'mlon': '$lng',
        }).replace(fragment: 'map=18/$lat/$lng')
      : null;
}

/// SOS that were actually sent: not the countdowns stopped in time.
int sosIncidentsIn(Iterable<SosRecord> records) =>
    records.where((r) => r.status != SosStatus.cancelled).length;
