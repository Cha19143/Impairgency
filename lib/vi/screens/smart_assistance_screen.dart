import 'package:flutter/material.dart';

import '../../core/navigation/destination.dart';
import '../../core/speech/speaker.dart';
import '../voice_controller.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';
import '../widgets/voice_mic_button.dart';

/// Where are you going?
///
/// The tester's request was that this work "more like Google Maps": say
/// where you are going before you leave, and be told which way as you go.
/// This is the first half. One tap on a saved place sets the destination
/// and opens the scan screen with directions; the ready-made three - Home,
/// Work, School - come first, and a place not saved yet says so and points
/// at where to save it rather than sitting there as a button that does
/// nothing.
///
/// The second half, the directions, is `core/navigation/guidance.dart`, and
/// the honesty about what it is - straight-line, not routed - lives there.
class SmartAssistanceScreen extends StatelessWidget {
  const SmartAssistanceScreen({
    super.key,
    required this.places,
    required this.onGo,
    required this.onManagePlaces,
    required this.onBack,
    this.voice,
    this.speaker = const SilentSpeaker(),
  });

  final List<Destination> places;
  final void Function(Destination destination) onGo;
  final VoidCallback onManagePlaces;
  final VoidCallback onBack;
  final VoiceController? voice;
  final Speaker speaker;

  @override
  Widget build(BuildContext context) {
    final ordered = orderForButtons(places);
    final missing =
        kReadyMadeKinds.where((k) => !places.any((p) => p.kind == k)).toList();

    return ViScreen(
      speaker: speaker,
      title: 'Where are you going?',
      body: [
        if (ordered.isEmpty)
          'No places are saved yet. Save where you are now as Home, Work or '
              'School, and it becomes a button here.'
        else
          'Tap a place and the app will tell you which way it lies and how '
              'far, while still warning you about what is in front of you.',
      ],
      spokenSuffix: ordered.isEmpty
          ? 'One choice: save a place.'
          : '${ordered.length} saved ${ordered.length == 1 ? 'place' : 'places'}: '
              '${ordered.map((p) => p.label).join(', ')}.',
      extra: voice == null
          ? null
          : VoiceMicButton(controller: voice!, detail: 'Say help, or repeat'),
      actions: [
        for (final place in ordered)
          ViButton(
            label: place.label,
            detail: 'Start directions to ${place.label}',
            icon: _iconFor(place.kind),
            kind: place.kind == DestinationKind.other
                ? ViButtonKind.secondary
                : ViButtonKind.primary,
            onPressed: () => onGo(place),
          ),
        for (final kind in missing)
          ViButton(
            label: '${kDestinationKindLabels[kind]} is not saved yet',
            detail: 'Tap to save where you are now as '
                '${kDestinationKindLabels[kind]}',
            icon: _iconFor(kind),
            kind: ViButtonKind.quiet,
            onPressed: onManagePlaces,
          ),
        ViButton(
          label: 'Saved places',
          detail: 'Add, rename or remove',
          icon: Icons.edit_location_alt_outlined,
          kind: ViButtonKind.secondary,
          onPressed: onManagePlaces,
        ),
        ViButton(
          label: 'Back',
          kind: ViButtonKind.quiet,
          onPressed: onBack,
        ),
      ],
    );
  }

  static IconData _iconFor(DestinationKind kind) => switch (kind) {
        DestinationKind.home => Icons.home_outlined,
        DestinationKind.work => Icons.work_outline,
        DestinationKind.school => Icons.school_outlined,
        DestinationKind.other => Icons.place_outlined,
      };
}
