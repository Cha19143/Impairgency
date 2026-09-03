import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/alerts/alert_presenter.dart';
import '../../core/alerts/sos_alert.dart';
import '../../core/location/location_fix.dart';
import '../../core/location/location_policy.dart';
import '../../core/location/location_source.dart';

/// A proving ground for the two things that cannot be tested off a device:
/// a real satellite fix, and a notification that actually makes a sound.
///
/// Debug builds only - `router.dart` does not register it in release. Issue #13
/// calls it throwaway, and it should be: once Phase 4 has a real SOS screen,
/// this stops earning its place.
class LocationDebugScreen extends StatefulWidget {
  const LocationDebugScreen({
    super.key,
    required this.source,
    required this.presenter,
    required this.bestEffort,
  });

  final LocationSource source;
  final AlertPresenter presenter;

  /// The same call SOS makes: a fresh fix, falling back to the last known one.
  final Future<LocationFix?> Function(LocationSource) bestEffort;

  @override
  State<LocationDebugScreen> createState() => _LocationDebugScreenState();
}

class _LocationDebugScreenState extends State<LocationDebugScreen> {
  final _log = <String>[];
  bool _busy = false;

  /// Mirrored to the console as well as the screen, because a physical device
  /// can be driven from a laptop but not seen from one.
  void _say(String line) {
    debugPrint('[debug-screen] $line');
    if (mounted) setState(() => _log.insert(0, line));
  }

  Future<void> _run(String label, Future<void> Function() body) async {
    setState(() => _busy = true);
    _say('▸ $label');
    final started = DateTime.now();
    try {
      await body();
    } catch (e) {
      _say('  threw: $e');
    }
    _say('  took ${DateTime.now().difference(started).inMilliseconds} ms');
    setState(() => _busy = false);
  }

  Future<void> _checkPermission() => _run('availability()', () async {
        _say('  ${await widget.source.availability()}');
      });

  Future<void> _requestPermission() => _run('requestPermission()', () async {
        final result = await widget.source.requestPermission();
        _say('  $result');
        _say('  "${permissionGuidance(result)}"');
      });

  Future<void> _getFix() => _run('bestEffortFix()', () async {
        final availability = await widget.source.availability();
        final fix = await widget.bestEffort(widget.source);

        if (fix == null) {
          _say('  no fix');
        } else {
          _say('  ${fix.latitude.toStringAsFixed(6)}, '
              '${fix.longitude.toStringAsFixed(6)}');
          _say('  ±${fix.accuracyMetres.round()} m, '
              'age ${describeAge(fix.ageAt(DateTime.now()))}');
        }

        // The point of the screen: not "did it return a number" but "what would
        // an SOS actually say about it".
        final outcome = resolveLocationForSos(
          availability: availability,
          fix: fix,
          now: DateTime.now(),
        );
        _say('  trust: ${outcome.trust.name}');
        _say('  SOS would say: "${outcome.spoken}"');
      });

  Future<void> _testAlert() => _run('local alert', () async {
        await widget.presenter.show(buildSosAlert(
          SosEvent(
            id: 'debug-${DateTime.now().millisecondsSinceEpoch}',
            userId: 'debug',
            at: DateTime.now(),
            locationSummary: 'This is a test. Nobody needs help.',
          ),
          name: 'Test User',
        ));
        _say('  shown - check the lock screen and listen for the sound');
      });

  @override
  void initState() {
    super.initState();
    // Runs itself so the whole check lands in `flutter run` output without
    // anyone having to tap through it on the phone.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkPermission();
      await _requestPermission();
      await _getFix();
      await _testAlert();
      _say('▸ done');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Location & alerts — debug')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Btn('Check', _busy ? null : _checkPermission),
                  _Btn('Ask', _busy ? null : _requestPermission),
                  _Btn('Get fix', _busy ? null : _getFix),
                  _Btn('Test alert', _busy ? null : _testAlert),
                  _Btn('Clear', _busy ? null : () => setState(_log.clear)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _log.isEmpty
                  ? const Center(
                      child: Text('Nothing yet.',
                          style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: _log.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          _log[i],
                          style: TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: 13,
                            height: 1.35,
                            color: _log[i].startsWith('▸')
                                ? AppColors.cyan
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn(this.label, this.onPressed);

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
}
