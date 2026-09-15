import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/places/place.dart';
import '../../core/places/routine.dart';
import '../../core/speech/speaker.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// Everything the app has worked out, and a way to make it forget.
///
/// §2.B documents routine, environment and person learning as features. Nothing
/// in `ui.pdf` let a user ask what was known about them, or delete it.
///
/// The wording is deliberately modest: these are places the user goes often,
/// counted. The app has not learned anything, it has counted something, and
/// saying otherwise would overclaim.
class LearnedDataScreen extends StatelessWidget {
  const LearnedDataScreen({
    super.key,
    required this.places,
    required this.onForgetAll,
    required this.onForgetPlace,
    required this.onBack,
    this.offset = Duration.zero,
    this.speaker = const SilentSpeaker(),
  });

  final List<Place> places;
  final Future<void> Function() onForgetAll;
  final Future<void> Function(Place) onForgetPlace;
  final VoidCallback onBack;

  /// Local time offset, so a routine is not described in UTC.
  final Duration offset;

  final Speaker speaker;

  @override
  Widget build(BuildContext context) {
    return ViScreen(
      speaker: speaker,
      title: 'What the app has worked out',
      body: places.isEmpty
          ? const [
              'Nothing yet. The app only remembers where you go if you have '
                  'turned that on, and it needs a few visits before a place '
                  'counts.',
            ]
          : [
              'These are places you have been more than once. Nothing here was '
                  'named by the app — you name them, or nobody does.',
            ],
      extra: places.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final place in places)
                  _PlaceCard(
                    place: place,
                    offset: offset,
                    onForget: () => onForgetPlace(place),
                  ),
              ],
            ),
      actions: [
        if (places.isNotEmpty)
          ViButton(
            label: 'Forget everything',
            detail: 'Deletes every place and every journey',
            icon: Icons.delete_outline,
            kind: ViButtonKind.emergency,
            onPressed: onForgetAll,
          ),
        ViButton(
          label: 'Back',
          kind: ViButtonKind.quiet,
          onPressed: onBack,
        ),
      ],
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.place,
    required this.offset,
    required this.onForget,
  });

  final Place place;
  final Duration offset;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final name = place.label ?? 'A place you go often';
    final visits =
        '${place.visitCount} visit${place.visitCount == 1 ? '' : 's'}';
    final routine = describeRoutine(place, offset: offset);

    return Semantics(
      label: [name, visits, if (routine != null) routine].join('. '),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.navyRaised,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(visits,
                    style: const TextStyle(
                        fontSize: 15, color: AppColors.textSecondary)),
                if (routine != null) ...[
                  const SizedBox(height: 8),
                  Text(routine,
                      style: const TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: AppColors.cyan)),
                ],
                const SizedBox(height: 10),
                Semantics(
                  button: true,
                  label: 'Forget $name',
                  onTap: onForget,
                  child: ExcludeSemantics(
                    child: TextButton.icon(
                      onPressed: onForget,
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.red, size: 22),
                      label: const Text('Forget this place',
                          style: TextStyle(
                              fontSize: 16, color: AppColors.red)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
