import 'package:flutter/material.dart';

import '../../core/navigation/destination.dart';
import '../../core/speech/speaker.dart';
import '../voice_controller.dart';
import '../widgets/place_search_panel.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';
import '../widgets/voice_mic_button.dart';

/// Where are you going?
///
/// The tester's request was that this work "more like Google Maps": say
/// where you are going before you leave, and be told which way as you go.
/// This is the first half. One tap on a saved place sets the destination
/// and opens the journey screen, with a map; the ready-made three - Home,
/// Work, School - come first, and a place not saved yet says so and points
/// at where to save it rather than sitting there as a button that does
/// nothing.
///
/// The second half, the directions, is `core/navigation/journey_guide.dart`:
/// a walking route from OpenStreetMap when there is one, the straight line
/// when there is not, and the difference always said.
///
/// A place that is not saved can be searched for by name - "Somewhere else",
/// first, asks for one - typed here or said anywhere: "take me to Jollibee".
/// The map is on the journey screen, not here: this screen asks a question.
class SmartAssistanceScreen extends StatefulWidget {
  const SmartAssistanceScreen({
    super.key,
    required this.places,
    required this.onGo,
    required this.onManagePlaces,
    required this.onBack,
    this.voice,
    this.speaker = const SilentSpeaker(),
    this.search,
  });

  final List<Destination> places;
  final void Function(Destination destination) onGo;
  final VoidCallback onManagePlaces;
  final VoidCallback onBack;
  final VoiceController? voice;
  final Speaker speaker;

  /// Looks up places that are not saved. Null hides the search.
  final Future<PlaceSearchResult> Function(String query)? search;

  @override
  State<SmartAssistanceScreen> createState() => _SmartAssistanceScreenState();
}

class _SmartAssistanceScreenState extends State<SmartAssistanceScreen> {
  final _searchPanel = GlobalKey<PlaceSearchPanelState>();

  @override
  Widget build(BuildContext context) {
    final places = widget.places;
    final voice = widget.voice;
    final search = widget.search;
    final speaker = widget.speaker;
    final onGo = widget.onGo;
    final onManagePlaces = widget.onManagePlaces;
    final onBack = widget.onBack;
    final ordered = orderForButtons(places);
    final missing =
        kReadyMadeKinds.where((k) => !places.any((p) => p.kind == k)).toList();

    return ViScreen(
      // Its own microphone sits above the places, with its own words.
      mic: false,
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
      spokenSuffix: [
        if (ordered.isEmpty)
          'Save a place,'
        else
          '${ordered.length} saved ${ordered.length == 1 ? 'place' : 'places'}: '
              '${ordered.map((p) => p.label).join(', ')},',
        if (search != null) 'or say somewhere else.' else 'or save a place.',
      ].join(' '),
      extra: voice == null && search == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (voice != null)
                  VoiceMicButton(
                    controller: voice,
                    detail: 'Say a saved place, or take me to, and a place',
                  ),
                if (search != null)
                  PlaceSearchPanel(
                    key: _searchPanel,
                    search: search,
                    onChoose: onGo,
                    onResult: speaker.speak,
                  ),
              ],
            ),
      actions: [
        // First, because a place nobody has saved is the one most likely to
        // need asking for.
        if (search != null)
          ViButton(
            label: 'Somewhere else',
            detail: 'Search by name, or say take me to, and a place',
            icon: Icons.search,
            onPressed: () => _searchPanel.currentState?.ask(),
          ),
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
