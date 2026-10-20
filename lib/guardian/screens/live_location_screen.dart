import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/guardian/watched_user.dart';
import '../../core/location/location_fix.dart';
import '../../core/location/location_policy.dart' show describeAge;
import '../../core/navigation/map_services.dart' show kOsmCopyrightUrl;
import '../../core/speech/screen_reading.dart';
import '../../core/speech/speaker.dart';
import '../../vi/widgets/vi_button.dart';

/// Builds the map for a fix. Injected so a widget test does not fetch tiles.
typedef LiveMapBuilder = Widget Function(LocationFix fix);

/// Where the person is, on a map that follows them.
///
/// The card on the dashboard says it in words; this is the same fix drawn,
/// and redrawn as the user's phone publishes a new one. The tester's mock
/// calls it "Live location". Live here means as often as the user's phone
/// shares - every half minute while it is open and they are moving - and
/// the line under the map says exactly how old the point is, because a pin
/// with no age is a claim the app cannot stand behind.
class LiveLocationScreen extends StatefulWidget {
  const LiveLocationScreen({
    super.key,
    required this.user,
    required this.onBack,
    this.onOpenMap,
    this.now = DateTime.now,
    this.mapBuilder,
    this.speaker = const SilentSpeaker(),
  });

  /// The person, kept live by whoever built this screen.
  final Stream<WatchedUser?> user;
  final VoidCallback onBack;

  /// Hands the fix to the phone's own maps app, for directions.
  final void Function(LocationFix fix)? onOpenMap;
  final DateTime Function() now;
  final LiveMapBuilder? mapBuilder;
  final Speaker speaker;

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen> {
  StreamSubscription<WatchedUser?>? _sub;
  WatchedUser? _user;
  Timer? _clock;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.user.listen((u) {
      if (!mounted) return;
      setState(() {
        _user = u;
        _opened = true;
      });
    });
    // The age line has to move on its own: a guardian leaves this screen
    // open and glances at it.
    _clock = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final fix = user?.fix;
    final now = widget.now();
    final title = user?.displayName ?? 'Live location';
    final lines = <String?>[
      title,
      'Back',
      if (user == null)
        'Loading…'
      else if (fix == null)
        describeWatchedLocation(user, now: now)
      else ...[
        'Updated ${describeAge(now.difference(fix.at))}, '
            'to within ${fix.accuracyMetres.round()} metres.',
        if (widget.onOpenMap != null) 'Open in your maps app',
        if (widget.onOpenMap != null) 'For directions to them',
      ],
    ];

    return AnnounceOnce(
      speaker: widget.speaker,
      ready: _opened,
      lines: lines,
      child: Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: widget.onBack,
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: fix == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          user == null
                              ? 'Loading…'
                              : describeWatchedLocation(user, now: now),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.4,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : (widget.mapBuilder ?? _defaultMap)(fix),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (fix != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        'Updated ${describeAge(now.difference(fix.at))}, '
                        'to within ${fix.accuracyMetres.round()} metres.',
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  if (fix != null && widget.onOpenMap != null) ...[
                    const SizedBox(height: 12),
                    ViButton(
                      label: 'Open in your maps app',
                      detail: 'For directions to them',
                      icon: Icons.directions_outlined,
                      kind: ViButtonKind.secondary,
                      onPressed: () => widget.onOpenMap!(fix),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

/// OpenStreetMap tiles, a marker, and the accuracy circle. Keyed on the fix
/// so a new position rebuilds the map centred on it: following, without a
/// controller to keep in step.
Widget _defaultMap(LocationFix fix) {
  final point = LatLng(fix.latitude, fix.longitude);
  return FlutterMap(
    key: ValueKey('${fix.latitude},${fix.longitude},${fix.at}'),
    options: MapOptions(initialCenter: point, initialZoom: 17),
    children: [
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'ph.impairgency.app',
      ),
      CircleLayer(
        circles: [
          CircleMarker(
            point: point,
            radius: fix.accuracyMetres,
            useRadiusInMeter: true,
            color: AppColors.cyan.withValues(alpha: 0.15),
            borderColor: AppColors.cyan,
            borderStrokeWidth: 1.5,
          ),
        ],
      ),
      MarkerLayer(
        markers: [
          Marker(
            point: point,
            width: 44,
            height: 44,
            child: const Icon(Icons.person_pin_circle,
                size: 44, color: AppColors.red),
          ),
        ],
      ),
      // The tiles are OpenStreetMap's, and its licence asks for the credit
      // on the map itself.
      RichAttributionWidget(
        alignment: AttributionAlignment.bottomLeft,
        attributions: [
          TextSourceAttribution(
            'OpenStreetMap contributors',
            onTap: () => launchUrl(Uri.parse(kOsmCopyrightUrl),
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
    ],
  );
}
