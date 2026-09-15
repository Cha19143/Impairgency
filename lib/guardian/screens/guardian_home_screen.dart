import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/guardian/activity.dart';
import '../../core/guardian/watched_user.dart';
import '../../core/location/location_policy.dart' show describeAge;
import '../../core/speech/speaker.dart';
import '../../vi/widgets/vi_button.dart';

/// The guardian's dashboard: who they watch, where those people are, and a
/// way to call them.
///
/// Page 17 of `ui.pdf` drew this with a hardcoded address and "Last Updated:
/// 1 min ago". This one reads the pairing, the consent-gated location fixes
/// and the SOS events that Phases 1 and 2 built, and says plainly when the
/// user is not sharing their location rather than showing a stale pin as
/// though it were live.
///
/// Its user is usually sighted, so it is denser than the visually impaired
/// app - but a guardian may be visually impaired too, so every control is a
/// labelled [ViButton] and the screen speaks a summary on arrival.
class GuardianHomeScreen extends StatefulWidget {
  const GuardianHomeScreen({
    super.key,
    required this.users,
    required this.onCall,
    required this.onOpenMap,
    this.onLiveLocation,
    required this.onEnterCode,
    required this.onSignOut,
    this.loading = false,
    this.reachabilityNote,
    this.now,
    this.speaker = const SilentSpeaker(),
  });

  final List<WatchedUser> users;
  final bool loading;

  /// Dials [CallTarget.number]. Returns false if the dialler refused.
  final Future<bool> Function(CallTarget target) onCall;
  final void Function(WatchedUser user) onOpenMap;

  /// The map that follows them, in the app. Null hides the button.
  final void Function(WatchedUser user)? onLiveLocation;
  final VoidCallback onEnterCode;
  final VoidCallback onSignOut;

  /// What this phone can and cannot be told - see `reachability.dart`.
  final String? reachabilityNote;

  /// Injected so the sentences are stable in tests.
  final DateTime Function()? now;

  final Speaker speaker;

  @override
  State<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends State<GuardianHomeScreen> {
  String? _notice;
  bool _spoken = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void didUpdateWidget(covariant GuardianHomeScreen old) {
    super.didUpdateWidget(old);
    _speakOnce();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakOnce());
  }

  /// A summary, once, when the first real data arrives.
  void _speakOnce() {
    if (_spoken || widget.loading || !mounted) return;
    _spoken = true;
    final lines = widget.users.isEmpty
        ? ['You are not watching over anyone yet. Enter the code from their phone.']
        : [
            for (final u in widget.users)
              describeWatchedLocation(u, now: _now),
          ];
    widget.speaker.speakLines(['Guardian', ...lines]);
  }

  Future<void> _call(WatchedUser user) async {
    final target = callTargetFor(user);
    if (target == null) {
      _say(noCallTargetMessage(user));
      return;
    }
    final ok = await widget.onCall(target);
    if (!ok) _say('The call to ${target.number} could not be started.');
  }

  void _say(String text) {
    if (!mounted) return;
    setState(() => _notice = text);
    widget.speaker.speak(text);
  }

  @override
  void dispose() {
    widget.speaker.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Semantics(
                header: true,
                child: const Text(
                  'Guardian',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
                children: [
                  if (widget.loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.cyan)),
                    )
                  else if (widget.users.isEmpty)
                    const Text(
                      'You are not watching over anyone yet. Ask them to open '
                      'Settings, then Guardian, and read you the code.',
                      style: TextStyle(
                          fontSize: 18,
                          height: 1.45,
                          color: AppColors.textSecondary),
                    )
                  else
                    for (final user in widget.users)
                      _UserCard(
                        user: user,
                        now: _now,
                        onCall: () => _call(user),
                        onOpenMap: user.fix == null
                            ? null
                            : () => widget.onOpenMap(user),
                        onLiveLocation:
                            user.fix == null || widget.onLiveLocation == null
                                ? null
                                : () => widget.onLiveLocation!(user),
                      ),
                  if (_notice != null)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 12),
                        child: Text(
                          _notice!,
                          style: const TextStyle(
                              fontSize: 16,
                              height: 1.35,
                              color: AppColors.amber),
                        ),
                      ),
                    ),
                  if (widget.reachabilityNote != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      child: Text(
                        widget.reachabilityNote!,
                        style: const TextStyle(
                            fontSize: 15,
                            height: 1.35,
                            color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ViButton(
                    label: widget.users.isEmpty
                        ? 'Enter their code'
                        : 'Watch over someone else',
                    detail: 'The eight-character code from their phone',
                    icon: Icons.key_outlined,
                    kind: widget.users.isEmpty
                        ? ViButtonKind.primary
                        : ViButtonKind.secondary,
                    onPressed: widget.onEnterCode,
                  ),
                  ViButton(
                    label: 'Sign out',
                    kind: ViButtonKind.quiet,
                    onPressed: widget.onSignOut,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.now,
    required this.onCall,
    required this.onOpenMap,
    required this.onLiveLocation,
  });

  final WatchedUser user;
  final DateTime now;
  final VoidCallback onCall;
  final VoidCallback? onOpenMap;
  final VoidCallback? onLiveLocation;

  @override
  Widget build(BuildContext context) {
    final location = describeWatchedLocation(user, now: now);
    final sos = describeLastSos(user, now: now);
    final target = callTargetFor(user);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.navyRaised,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              user.displayName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (sos != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.emergency_outlined,
                    color: AppColors.red, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sos,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.red),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                user.sharesLocation
                    ? Icons.location_on_outlined
                    : Icons.location_off_outlined,
                color: AppColors.textSecondary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  location,
                  style: const TextStyle(
                      fontSize: 17,
                      height: 1.4,
                      color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RecentActivity(user: user, now: now),
          const SizedBox(height: 14),
          ViButton(
            label: 'Call',
            detail: target?.label ?? noCallTargetMessage(user),
            semanticLabel: target?.label ?? noCallTargetMessage(user),
            icon: Icons.call,
            kind: ViButtonKind.emergency,
            onPressed: onCall,
          ),
          if (onLiveLocation != null)
            ViButton(
              label: 'Live location',
              detail: 'A map that follows them',
              icon: Icons.my_location,
              kind: ViButtonKind.primary,
              onPressed: onLiveLocation,
            ),
          if (onOpenMap != null)
            ViButton(
              label: 'Open on a map',
              detail: 'Shows the last position in your maps app',
              icon: Icons.map_outlined,
              kind: ViButtonKind.secondary,
              onPressed: onOpenMap,
            ),
        ],
      ),
    );
  }
}

/// The last few things the app noticed - the tester's "recent activity".
///
/// Three rows at most on the card; the point is the newest one. Says so
/// when the user has not agreed to share this, rather than showing nothing
/// and leaving the guardian to wonder whether the app is working.
class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.user, required this.now});

  final WatchedUser user;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final rows = user.activity.take(3).toList();
    final String? note = !user.sharesActivity
        ? '${user.displayName} is not sharing what the app notices.'
        : rows.isEmpty
            ? 'Nothing noticed yet.'
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent activity',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        if (note != null)
          Text(
            note,
            style: const TextStyle(
                fontSize: 16, height: 1.4, color: AppColors.textSecondary),
          ),
        for (final event in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Semantics(
              label: describeActivity(event, now: now),
              child: ExcludeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (event.kind) {
                        ActivityKind.obstacle => Icons.warning_amber_outlined,
                        ActivityKind.textRead => Icons.menu_book_outlined,
                        ActivityKind.journey => Icons.directions_walk,
                      },
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        activityHeadline(event),
                        style: const TextStyle(
                            fontSize: 16,
                            height: 1.3,
                            color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      describeAge(now.difference(event.at)),
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
