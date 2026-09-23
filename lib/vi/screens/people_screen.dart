import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/speech/speaker.dart';
import '../../core/vision/faces.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// The people whose faces this phone knows, and the way to forget them.
///
/// Every face here was saved with that person's spoken yes, and is kept on
/// this phone only, as numbers rather than a picture. Forgetting one deletes
/// it; turning off "Recognise people I know" deletes all of them.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({
    super.key,
    required this.friends,
    required this.onForget,
    required this.onForgetEveryone,
    required this.onBack,
    this.onRename,
    this.consented = true,
    this.speaker = const SilentSpeaker(),
  });

  final List<Friend> friends;
  final Future<void> Function(Friend friend) onForget;
  final Future<void> Function() onForgetEveryone;
  final VoidCallback onBack;

  /// Gives a saved friend another name. Returns what to say. Null hides it.
  final Future<String> Function(Friend friend, String name)? onRename;

  /// Whether recognition is on. Off, there is nobody to show - turning it
  /// off deleted them - and the screen says how to turn it on.
  final bool consented;
  final Speaker speaker;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  String? _notice;

  Future<void> _forget(Friend friend) async {
    await widget.onForget(friend);
    await _tell('${friend.name} is forgotten.');
  }

  Future<void> _forgetEveryone() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget everyone?'),
        content: Text(
            'All ${widget.friends.length} saved faces are deleted from this '
            'phone. Nobody will be recognised until they are saved again.'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(fontSize: 18)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget everyone'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await widget.onForgetEveryone();
    await _tell('Everyone is forgotten.');
  }

  Future<void> _rename(Friend friend) async {
    final field = TextEditingController(text: friend.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename ${friend.name}'),
        content: TextField(
          controller: field,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(fontSize: 20),
          decoration: const InputDecoration(labelText: 'New name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(fontSize: 18)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(field.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    field.dispose();
    final rename = widget.onRename;
    if (name == null || name.trim().isEmpty || rename == null) return;
    await _tell(await rename(friend, name.trim()));
  }

  Future<void> _tell(String text) async {
    if (!mounted) return;
    setState(() => _notice = text);
    await widget.speaker.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    final friends = widget.friends;
    return ViScreen(
      speaker: widget.speaker,
      title: 'People I know',
      body: [
        if (!widget.consented)
          'Recognising people is off. Turn on "Recognise people I know" in '
              'What the app is using, then say "hello friend" and their name '
              'on the scan screen, with them in front of the camera.'
        else if (friends.isEmpty)
          'Nobody is saved yet. On the scan screen, with a friend in front of '
              'the camera, say "hello friend" and their name. They will be '
              'asked if they agree.'
        else
          'The scan screen tells you when one of these people is nearby.',
        'Faces are kept only on this phone, as numbers rather than pictures, '
            'and only for people who said yes.',
      ],
      spokenSuffix: friends.isEmpty
          ? null
          : '${friends.length} saved: ${friends.map((f) => f.name).join(', ')}.',
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final friend in friends) ...[
            if (widget.onRename != null)
              ViButton(
                label: 'Rename ${friend.name}',
                detail: 'Changes the name said when they are near',
                icon: Icons.drive_file_rename_outline,
                kind: ViButtonKind.secondary,
                onPressed: () => _rename(friend),
              ),
            ViButton(
              label: 'Forget ${friend.name}',
              detail: 'Deletes their saved face from this phone',
              icon: Icons.person_remove_outlined,
              kind: ViButtonKind.secondary,
              onPressed: () => _forget(friend),
            ),
          ],
          if (_notice != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _notice!,
                  style: const TextStyle(fontSize: 16, color: AppColors.green),
                ),
              ),
            ),
        ],
      ),
      actions: [
        if (friends.length > 1)
          ViButton(
            label: 'Forget everyone',
            kind: ViButtonKind.quiet,
            onPressed: _forgetEveryone,
          ),
        ViButton(
          label: 'Back',
          kind: ViButtonKind.quiet,
          onPressed: widget.onBack,
        ),
      ],
    );
  }
}
