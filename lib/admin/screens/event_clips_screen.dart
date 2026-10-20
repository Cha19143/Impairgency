/// Event clips for an administrator: filter, then play the frames.
///
/// The other admin pages are not this one. This is the only new screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/admin/admin_user.dart';
import '../../core/clips/event_clip.dart';
import '../../core/speech/speaker.dart';
import '../admin_theme.dart';
import '../admin_ui.dart';
import 'admin_page.dart';

/// Today starts at local midnight. Last 7 days is everything the query asked
/// for, which already stops at [kClipRetention].
enum ClipDateFilter { last7Days, today }

class EventClipsScreen extends StatefulWidget {
  const EventClipsScreen({
    super.key,
    required this.clips,
    required this.users,
    required this.loadFrames,
    this.speaker = const SilentSpeaker(),
  });

  final List<EventClipRecord> clips;
  final List<AdminUserRow> users;
  final Future<List<StoredClipFrame>> Function(String clipId) loadFrames;
  final Speaker speaker;

  @override
  State<EventClipsScreen> createState() => _EventClipsScreenState();
}

class _EventClipsScreenState extends State<EventClipsScreen> {
  String? _userId;
  ClipDateFilter _date = ClipDateFilter.last7Days;
  String? _trigger;
  String? _selectedId;
  List<StoredClipFrame>? _frames;
  Object? _frameError;
  int _index = 0;
  bool _playing = false;
  Timer? _ticker;
  int _loadGeneration = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  List<EventClipRecord> get _shown {
    final start = _date == ClipDateFilter.today ? _todayStart() : null;
    return [
      for (final clip in widget.clips)
        if (_userId == null || clip.userId == _userId)
          if (_trigger == null || clip.triggers.contains(_trigger))
            if (start == null || !clip.at.toLocal().isBefore(start)) clip,
    ];
  }

  DateTime _todayStart() {
    final local = DateTime.now().toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  String _name(String uid) {
    for (final user in widget.users) {
      if (user.uid != uid) continue;
      final name = user.displayName;
      if (name != null && name.isNotEmpty) return name;
      final email = user.email;
      if (email != null && email.isNotEmpty) return email;
    }
    return uid;
  }

  String _when(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _triggers(EventClipRecord clip) {
    if (clip.triggers.isEmpty) return 'Event';
    return clip.triggers.map(clipTriggerLabel).join(', ');
  }

  void _select(EventClipRecord clip) {
    _ticker?.cancel();
    final generation = ++_loadGeneration;
    setState(() {
      _selectedId = clip.id;
      _frames = null;
      _frameError = null;
      _index = 0;
      _playing = false;
    });
    if (!clip.hasFrames) {
      unawaited(widget.speaker.speak(kClipNoFramesMessage));
      return;
    }
    unawaited(_load(clip.id, generation));
  }

  Future<void> _load(String clipId, int generation) async {
    try {
      final frames = await widget.loadFrames(clipId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _frames = frames;
        _playing = frames.length > 1;
      });
      if (frames.length > 1) _startTicker();
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _frameError = e);
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(kClipFrameGap, (_) {
      final frames = _frames;
      if (frames == null || frames.length < 2) return;
      if (_index >= frames.length - 1) {
        _ticker?.cancel();
        setState(() => _playing = false);
        return;
      }
      setState(() => _index++);
    });
  }

  void _togglePlay() {
    final frames = _frames;
    if (frames == null || frames.length < 2) return;
    if (_playing) {
      _ticker?.cancel();
      setState(() => _playing = false);
      return;
    }
    if (_index >= frames.length - 1) {
      setState(() => _index = 0);
    }
    setState(() => _playing = true);
    _startTicker();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final selected = _selected();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _menu<String?>(
              label: 'User',
              value: _userId,
              entries: [
                const DropdownMenuEntry(value: null, label: 'All users'),
                for (final user in _usersIn(widget.clips))
                  DropdownMenuEntry(value: user, label: _name(user)),
              ],
              onChanged: (value) => setState(() {
                _userId = value;
                _dropHiddenSelection();
              }),
            ),
            _menu<ClipDateFilter>(
              label: 'Date',
              value: _date,
              entries: const [
                DropdownMenuEntry(
                  value: ClipDateFilter.last7Days,
                  label: 'Last 7 days',
                ),
                DropdownMenuEntry(value: ClipDateFilter.today, label: 'Today'),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _date = value;
                  _dropHiddenSelection();
                });
              },
            ),
            _menu<String?>(
              label: 'Trigger',
              value: _trigger,
              entries: [
                const DropdownMenuEntry(value: null, label: 'All triggers'),
                for (final trigger in kClipTriggerOrder)
                  DropdownMenuEntry(
                    value: trigger,
                    label: clipTriggerLabel(trigger),
                  ),
              ],
              onChanged: (value) => setState(() {
                _trigger = value;
                _dropHiddenSelection();
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (selected != null) ...[
          _player(selected),
          const SizedBox(height: 16),
        ],
        if (shown.isEmpty)
          AdminMessage(
            icon: Icons.photo_library_outlined,
            title: 'No clips in this filter',
            detail: 'Clips appear when a signed-in user with recording '
                'turned on has an obstacle, a fall, an SOS, an hour in one '
                'place, or a route deviation. They are kept for 7 days.',
          )
        else
          for (final clip in shown) _tile(clip, selected?.id == clip.id),
      ],
    );
  }

  EventClipRecord? _selected() {
    final id = _selectedId;
    if (id == null) return null;
    for (final clip in _shown) {
      if (clip.id == id) return clip;
    }
    return null;
  }

  void _dropHiddenSelection() {
    if (_selected() != null) return;
    _ticker?.cancel();
    _selectedId = null;
    _frames = null;
    _playing = false;
  }

  List<String> _usersIn(List<EventClipRecord> clips) {
    final seen = <String>[];
    for (final clip in clips) {
      if (!seen.contains(clip.userId)) seen.add(clip.userId);
    }
    return seen;
  }

  Widget _menu<T>({
    required String label,
    required T value,
    required List<DropdownMenuEntry<T>> entries,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 240,
      child: DropdownMenu<T>(
        key: ValueKey(label),
        initialSelection: value,
        label: Text(label),
        dropdownMenuEntries: entries,
        onSelected: onChanged,
        textStyle: const TextStyle(color: AdminColors.ink, fontSize: 14),
      ),
    );
  }

  Widget _tile(EventClipRecord clip, bool selected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AdminCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            key: ValueKey('clip-${clip.id}'),
            selected: selected,
            title: Text(
              _triggers(clip),
              style: const TextStyle(
                color: AdminColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '${_name(clip.userId)} · ${_when(clip.at)}'
              '${clip.hasFrames ? '' : ' · No pictures'}',
              style: const TextStyle(color: AdminColors.inkMuted),
            ),
            onTap: () => _select(clip),
          ),
        ),
      ),
    );
  }

  Widget _player(EventClipRecord clip) {
    final frames = _frames;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _triggers(clip),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AdminColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_name(clip.userId)} · ${_when(clip.at)}',
            style: const TextStyle(color: AdminColors.inkMuted),
          ),
          const SizedBox(height: 12),
          if (!clip.hasFrames)
            const Text(
              kClipNoFramesMessage,
              style: TextStyle(fontSize: 16, height: 1.4, color: AdminColors.ink),
            )
          else if (_frameError != null)
            const Text(
              'Could not load the pictures.',
              style: TextStyle(fontSize: 16, color: AdminColors.ink),
            )
          else if (frames == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (frames.isEmpty)
            const Text(
              kClipNoFramesMessage,
              style: TextStyle(fontSize: 16, height: 1.4, color: AdminColors.ink),
            )
          else ...[
            Image.memory(
              frames[_index.clamp(0, frames.length - 1)].jpeg,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Picture ${_index + 1} of ${frames.length}',
                  style: const TextStyle(color: AdminColors.ink),
                ),
                const Spacer(),
                if (frames.length > 1)
                  TextButton(
                    onPressed: _togglePlay,
                    child: Text(_playing ? 'Pause' : 'Play'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
