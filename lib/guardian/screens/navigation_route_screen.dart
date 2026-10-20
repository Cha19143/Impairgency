import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/navigation/map_services.dart';
import '../../core/navigation/navigation_history.dart';
import '../../core/navigation/route.dart';
import '../../core/speech/screen_reading.dart';
import '../../core/speech/speaker.dart';
import 'navigation_history_screen.dart';

/// Draws the remembered trip. Injected so a test never fetches tiles.
typedef NavigationMapBuilder = Widget Function(NavigationRouteMapState state);

/// Origin, destination, and the walking route between them.
///
/// The line is asked of OpenStreetMap when this screen opens. It is not
/// stored with the trip. If the router has no answer, the two markers stay
/// and the screen says the route is unavailable.
class NavigationRouteScreen extends StatefulWidget {
  const NavigationRouteScreen({
    super.key,
    required this.load,
    required this.onBack,
    this.routing,
    this.mapBuilder,
    this.now = DateTime.now,
    this.speaker = const SilentSpeaker(),
  });

  final Future<NavigationEntry?> Function() load;
  final RoutingService? routing;
  final VoidCallback onBack;
  final NavigationMapBuilder? mapBuilder;
  final DateTime Function() now;
  final Speaker speaker;

  @override
  State<NavigationRouteScreen> createState() => _NavigationRouteScreenState();
}

class NavigationRouteMapState {
  const NavigationRouteMapState({
    required this.origin,
    required this.destination,
    this.line,
  });

  final LatLng origin;
  final LatLng destination;
  final List<LatLng>? line;
}

class _NavigationRouteScreenState extends State<NavigationRouteScreen> {
  NavigationEntry? _entry;
  bool _loadingEntry = true;
  bool _loadingRoute = false;
  bool _routeFailed = false;
  List<LatLng>? _line;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final entry = await widget.load();
      if (!mounted) return;
      setState(() {
        _entry = entry;
        _loadingEntry = false;
        _loadingRoute = entry != null && widget.routing != null;
        _routeFailed = entry != null && widget.routing == null;
      });
      if (entry != null && widget.routing != null) {
        await _loadRoute(entry);
      }
    } catch (e) {
      debugPrint('navigation trip load failed: $e');
      if (!mounted) return;
      setState(() {
        _loadingEntry = false;
        _routeFailed = true;
      });
    }
  }

  Future<void> _loadRoute(NavigationEntry entry) async {
    final routing = widget.routing;
    if (routing == null) return;
    try {
      final route = await routing.walkingRoute(
        RoutePoint(entry.originLat, entry.originLng),
        RoutePoint(entry.destinationLat, entry.destinationLng),
      );
      if (!mounted) return;
      final line = [
        for (final point in route.geometry)
          LatLng(point.latitude, point.longitude),
      ];
      setState(() {
        _loadingRoute = false;
        if (line.length >= 2) {
          _line = line;
        } else {
          _routeFailed = true;
        }
      });
    } catch (e) {
      debugPrint('navigation route failed: $e');
      if (!mounted) return;
      setState(() {
        _loadingRoute = false;
        _routeFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final now = widget.now();
    final shown = entry?.displayStatus(now);
    return AnnounceOnce(
      speaker: widget.speaker,
      ready: !_loadingEntry,
      lines: [
        entry?.destinationName ?? 'Navigation history',
        'Back',
        if (entry == null && !_loadingEntry) 'This trip could not be opened.',
        if (entry != null) ...[
          if (entry.destinationAddress.isNotEmpty) entry.destinationAddress,
          formatNavigationWhen(entry.startedAt),
          shown?.label,
          if (_loadingRoute) 'Finding the walking route.',
          if (_routeFailed) 'Route unavailable',
        ],
      ],
      child: Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: Text(entry?.destinationName ?? 'Navigation history'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: widget.onBack,
        ),
      ),
      body: SafeArea(
        child: _loadingEntry
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.cyan),
              )
            : entry == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'This trip could not be opened.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _map(entry)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: _Summary(
                      entry: entry,
                      now: widget.now(),
                      loadingRoute: _loadingRoute,
                      routeFailed: _routeFailed,
                    ),
                  ),
                ],
              ),
      ),
    ),
    );
  }

  Widget _map(NavigationEntry entry) {
    final state = NavigationRouteMapState(
      origin: LatLng(entry.originLat, entry.originLng),
      destination: LatLng(entry.destinationLat, entry.destinationLng),
      line: _line,
    );
    return (widget.mapBuilder ?? _defaultMap)(state);
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.entry,
    required this.now,
    required this.loadingRoute,
    required this.routeFailed,
  });

  final NavigationEntry entry;
  final DateTime now;
  final bool loadingRoute;
  final bool routeFailed;

  @override
  Widget build(BuildContext context) {
    final shown = entry.displayStatus(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                entry.destinationName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            NavigationStatusChip(status: shown),
          ],
        ),
        if (entry.destinationAddress.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            entry.destinationAddress,
            style: const TextStyle(
              fontSize: 16,
              height: 1.35,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          formatNavigationWhen(entry.startedAt),
          style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        if (loadingRoute)
          const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.cyan,
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Finding the walking route.',
                style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
              ),
            ],
          )
        else if (routeFailed)
          const Text(
            'Route unavailable',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.amber,
            ),
          ),
      ],
    );
  }
}

Widget _defaultMap(NavigationRouteMapState state) {
  final origin = state.origin;
  final destination = state.destination;
  final samePlace =
      (origin.latitude - destination.latitude).abs() < 0.0001 &&
      (origin.longitude - destination.longitude).abs() < 0.0001;
  final options = samePlace
      ? MapOptions(initialCenter: destination, initialZoom: 16)
      : MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([origin, destination]),
            padding: const EdgeInsets.all(48),
            maxZoom: 17,
          ),
        );

  return FlutterMap(
    options: options,
    children: [
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'ph.impairgency.app',
      ),
      if (state.line != null && state.line!.length >= 2)
        PolylineLayer(
          polylines: [
            Polyline(
              points: state.line!,
              color: AppColors.cyan,
              strokeWidth: 6,
              borderColor: AppColors.navy,
              borderStrokeWidth: 2,
            ),
          ],
        ),
      MarkerLayer(
        markers: [
          Marker(
            point: destination,
            width: 44,
            height: 44,
            alignment: Alignment.topCenter,
            child: const Icon(Icons.flag, size: 44, color: AppColors.red),
          ),
          Marker(
            point: origin,
            width: 28,
            height: 28,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.cyan,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.navy, width: 3),
              ),
            ),
          ),
        ],
      ),
      RichAttributionWidget(
        alignment: AttributionAlignment.bottomLeft,
        attributions: [
          TextSourceAttribution(
            'OpenStreetMap contributors',
            onTap: () => launchUrl(
              Uri.parse(kOsmCopyrightUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    ],
  );
}
