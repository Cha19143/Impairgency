import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/navigation/destination.dart';
import '../../core/speech/speaker.dart';
import '../widgets/place_search_panel.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// Returns null when saved, or a sentence to say and show.
typedef SaveHereHandler = Future<String?> Function(
    DestinationKind kind, String label);

/// Add, rename and remove saved places.
///
/// A place is saved by standing in it - "save where I am now as Home" is what
/// people actually do the first time they open the app at home - or by
/// finding it by name on OpenStreetMap, for somewhere not yet been.
class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({
    super.key,
    required this.places,
    required this.onSaveHere,
    required this.onRename,
    required this.onRemove,
    required this.onBack,
    this.speaker = const SilentSpeaker(),
    this.search,
    this.onSaveFound,
  });

  final List<Destination> places;
  final SaveHereHandler onSaveHere;
  final Future<void> Function(Destination place, String label) onRename;
  final Future<void> Function(Destination place) onRemove;
  final VoidCallback onBack;
  final Speaker speaker;

  /// Finds places by name. Null, or no [onSaveFound], hides the search.
  final Future<PlaceSearchResult> Function(String query)? search;

  /// Saves a place that was found. Null when saved, or a sentence to say.
  final Future<String?> Function(Destination place)? onSaveFound;

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  final _label = TextEditingController();
  DestinationKind? _saving;
  String? _notice;
  bool _noticeIsError = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _saveHere(DestinationKind kind) async {
    if (_saving != null) return;
    final failure = validateDestinationLabel(_label.text, kind: kind);
    if (failure != null) {
      await _tell(failure, error: true);
      return;
    }
    setState(() => _saving = kind);
    final label = kind == DestinationKind.other
        ? _label.text.trim()
        : kDestinationKindLabels[kind]!;
    final result = await widget.onSaveHere(kind, label);
    if (!mounted) return;
    setState(() => _saving = null);
    if (result != null) {
      await _tell(result, error: true);
      return;
    }
    _label.clear();
    await _tell('Saved where you are now as $label.');
  }

  Future<void> _saveFound(Destination place) async {
    final save = widget.onSaveFound;
    if (save == null) return;
    final result = await save(place);
    if (!mounted) return;
    if (result != null) {
      await _tell(result, error: true);
      return;
    }
    await _tell('Saved ${place.label}.');
  }

  Future<void> _tell(String text, {bool error = false}) async {
    if (!mounted) return;
    setState(() {
      _notice = text;
      _noticeIsError = error;
    });
    await widget.speaker.speak(text);
  }

  Future<void> _remove(Destination place) async {
    await widget.onRemove(place);
    await _tell('${place.label} removed.');
  }

  Future<void> _rename(Destination place) async {
    final controller = TextEditingController(text: place.label);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename ${place.label}'),
        content: Semantics(
          textField: true,
          label: 'New name',
          child: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(labelText: 'New name'),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(fontSize: 18)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    final failure =
        validateDestinationLabel(name, kind: DestinationKind.other);
    if (failure != null) {
      await _tell(failure, error: true);
      return;
    }
    await widget.onRename(place, name.trim());
    await _tell('Renamed to ${name.trim()}.');
  }

  @override
  Widget build(BuildContext context) {
    final ordered = orderForButtons(widget.places);
    return ViScreen(
      speaker: widget.speaker,
      title: 'Saved places',
      body: const [
        'Stand where you want to save, then choose what to call it. Home, '
            'Work and School each have one spot; saving again moves it.',
      ],
      spokenSuffix: ordered.isEmpty
          ? 'Nothing is saved yet.'
          : 'Saved: ${ordered.map((p) => p.label).join(', ')}.',
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final place in ordered)
            _PlaceRow(
              place: place,
              onRename:
                  place.kind == DestinationKind.other ? () => _rename(place) : null,
              onRemove: () => _remove(place),
            ),
          if (ordered.isNotEmpty) const SizedBox(height: 14),
          Semantics(
            header: true,
            child: const Text(
              'Save where I am now as',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final kind in kReadyMadeKinds)
            ViButton(
              label: _saving == kind
                  ? 'Finding where you are…'
                  : kDestinationKindLabels[kind]!,
              detail: widget.places.any((p) => p.kind == kind)
                  ? 'Already saved. Saving again moves it here.'
                  : null,
              icon: Icons.my_location,
              kind: ViButtonKind.secondary,
              onPressed: _saving == null ? () => _saveHere(kind) : null,
            ),
          Semantics(
            textField: true,
            label: 'Name for somewhere else',
            child: TextField(
              controller: _label,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 20, color: AppColors.textPrimary),
              onSubmitted: (_) => _saveHere(DestinationKind.other),
              decoration: const InputDecoration(
                labelText: 'Somewhere else - give it a name',
                labelStyle: TextStyle(fontSize: 17),
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ViButton(
            label: _saving == DestinationKind.other
                ? 'Finding where you are…'
                : 'Save it with that name',
            icon: Icons.my_location,
            kind: ViButtonKind.secondary,
            onPressed:
                _saving == null ? () => _saveHere(DestinationKind.other) : null,
          ),
          if (widget.search != null && widget.onSaveFound != null) ...[
            const SizedBox(height: 22),
            Semantics(
              header: true,
              child: const Text(
                'Or find a place by name',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            PlaceSearchPanel(
              search: widget.search!,
              onChoose: _saveFound,
              chooseDetail: 'Save it',
              onResult: widget.speaker.speak,
            ),
          ],
          if (_notice != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _notice!,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.35,
                    color: _noticeIsError ? AppColors.amber : AppColors.green,
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: [
        ViButton(
          label: 'Back',
          kind: ViButtonKind.quiet,
          onPressed: widget.onBack,
        ),
      ],
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.place,
    required this.onRename,
    required this.onRemove,
  });

  final Destination place;
  final VoidCallback? onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: AppColors.navyRaised,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                label: '${place.label}. ${kDestinationKindLabels[place.kind]}.',
                child: ExcludeSemantics(
                  child: Text(
                    place.label,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            if (onRename != null)
              Semantics(
                button: true,
                label: 'Rename ${place.label}',
                onTap: onRename,
                child: ExcludeSemantics(
                  child: IconButton(
                    iconSize: 30,
                    constraints: const BoxConstraints(
                        minWidth: kMinTargetSize, minHeight: kMinTargetSize),
                    onPressed: onRename,
                    icon: const Icon(Icons.edit_outlined, color: AppColors.cyan),
                  ),
                ),
              ),
            Semantics(
              button: true,
              label: 'Remove ${place.label}',
              onTap: onRemove,
              child: ExcludeSemantics(
                child: IconButton(
                  iconSize: 30,
                  constraints: const BoxConstraints(
                      minWidth: kMinTargetSize, minHeight: kMinTargetSize),
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline, color: AppColors.red),
                ),
              ),
            ),
          ],
        ),
      );
}
