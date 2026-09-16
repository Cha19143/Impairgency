import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/navigation/destination.dart';
import '../../core/navigation/map_services.dart';
import '../../core/navigation/place_search.dart';
import '../../core/navigation/route.dart';
import 'dictated_field.dart';
import 'vi_button.dart';

/// What a search found, and from where - or why it found nothing.
class PlaceSearchResult {
  const PlaceSearchResult({this.found = const [], this.from, this.problem});

  final List<PlaceCandidate> found;

  /// Where the person was, for "about 600 metres away".
  final RoutePoint? from;

  /// Said and shown instead of results: no connection, no position.
  final String? problem;
}

/// Looks up a place that is not saved: "Jollibee", "Bulacan Medical Center".
///
/// Typed, for anyone who can type - TalkBack users do - and for a helper
/// setting up a trip. Saying "take me to" does the same by voice. Results are
/// buttons, each saying what and how far, because two branches of the same
/// shop are told apart by their street and their distance.
class PlaceSearchPanel extends StatefulWidget {
  const PlaceSearchPanel({
    super.key,
    required this.search,
    required this.onChoose,
    this.chooseDetail = 'Start directions',
    this.onResult,
  });

  final Future<PlaceSearchResult> Function(String query) search;
  final void Function(Destination place) onChoose;

  /// What choosing a result does, said with it.
  final String chooseDetail;

  /// Told what to say about a result - how many, or what went wrong.
  final void Function(String sentence)? onResult;

  @override
  State<PlaceSearchPanel> createState() => PlaceSearchPanelState();
}

class PlaceSearchPanelState extends State<PlaceSearchPanel> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  final _field = GlobalKey<DictatedFieldState>();

  /// Asks for a place to search for: by voice when there is a microphone,
  /// otherwise by putting the keyboard on the field.
  Future<void> ask() async {
    final context = _field.currentContext;
    if (context != null) {
      await Scrollable.ensureVisible(context,
          duration: const Duration(milliseconds: 200));
    }
    final field = _field.currentState;
    if (field != null && field.canDictate) {
      await field.dictate();
    } else {
      _focus.requestFocus();
    }
  }
  bool _searching = false;
  PlaceSearchResult? _result;
  String? _searched;

  @override
  void dispose() {
    _focus.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final query = _query.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _result = null;
    });
    PlaceSearchResult result;
    try {
      result = await widget.search(query);
    } catch (_) {
      result = const PlaceSearchResult(
          problem: 'The search did not work. Try again in a moment.');
    }
    if (!mounted) return;
    setState(() {
      _searching = false;
      _result = result;
      _searched = query;
    });
    widget.onResult?.call(_summary(result, query));
  }

  static String _summary(PlaceSearchResult result, String query) {
    if (result.problem != null) return result.problem!;
    final count = result.found.length;
    if (count == 0) return 'Nothing called $query was found nearby.';
    return '${count == 1 ? 'One place' : '$count places'} found for $query.';
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DictatedField(
          key: _field,
          label: 'Place to search for',
          prompt: 'Say the place to search for: a shop, a clinic, a street.',
          controller: _query,
          inForm: false,
          // Said and kept means searched: nobody should have to find the
          // Search button after answering by voice.
          onDictated: (_) => _run(),
          field: TextField(
            controller: _query,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            style: const TextStyle(fontSize: 20, color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Search for a place that is not saved',
              hintText: 'A shop, a clinic, a street',
            ),
          ),
        ),
        const SizedBox(height: 10),
        ViButton(
          label: _searching ? 'Searching…' : 'Search',
          icon: Icons.search,
          kind: ViButtonKind.secondary,
          onPressed: _searching ? null : _run,
        ),
        if (result != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                _summary(result, _searched ?? ''),
                style: TextStyle(
                  fontSize: 16,
                  color: result.problem != null
                      ? AppColors.amber
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        if (result != null)
          for (final place in result.found)
            ViButton(
              label: place.label,
              detail: '${describeCandidate(place, from: result.from)} '
                  '${widget.chooseDetail}.',
              icon: Icons.place_outlined,
              kind: ViButtonKind.secondary,
              onPressed: () => widget.onChoose(place.toDestination()),
            ),
        if (result != null && result.found.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Places $kOsmAttribution',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }
}
