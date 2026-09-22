import 'package:flutter/widgets.dart';

import '../voice_targets.dart';
import 'voice_access.dart';

/// Lets the microphone press [child] by saying [label], while it is on screen.
///
/// [ViButton] wraps itself in one. A control drawn some other way - an icon
/// button, a row that acts as a choice - wraps itself in one with the label a
/// screen reader announces for it, so every button on a screen answers to its
/// name the same way.
///
/// Registers with the app's microphone when there is one above it, and does
/// nothing at all when there is not - a widget test that never provides one
/// sees the button it always did.
class PressByVoice extends StatefulWidget {
  const PressByVoice({
    super.key,
    required this.label,
    required this.onPressed,
    required this.child,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  State<PressByVoice> createState() => _PressByVoiceState();
}

class _PressByVoiceState extends State<PressByVoice> {
  VoiceTargets? _targets;
  VoiceTargetHandle? _handle;

  VoiceTarget? get _target {
    final onPressed = widget.onPressed;
    return onPressed == null ? null : VoiceTarget(widget.label, onPressed);
  }

  void _sync() {
    final target = _target;
    if (target == null) {
      _handle?.remove();
      _handle = null;
    } else if (_handle == null) {
      _handle = _targets?.register(target);
    } else {
      _handle!.update(target);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final targets = VoiceAccess.maybeOf(context)?.targets;
    if (targets == _targets) return;
    _handle?.remove();
    _handle = null;
    _targets = targets;
    _sync();
  }

  @override
  void didUpdateWidget(PressByVoice oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _handle?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
