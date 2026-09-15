import 'package:flutter/widgets.dart';

import '../voice_controller.dart';

/// Listens for [scope] while [child] is on screen.
///
/// For screens that do not keep their own state - Smart assistance - so the
/// router can give them a vocabulary without each screen growing one.
class VoiceScopeHost extends StatefulWidget {
  const VoiceScopeHost({
    super.key,
    required this.voice,
    required this.scope,
    required this.child,
  });

  final VoiceController? voice;
  final VoiceScope scope;
  final Widget child;

  @override
  State<VoiceScopeHost> createState() => _VoiceScopeHostState();
}

class _VoiceScopeHostState extends State<VoiceScopeHost> {
  VoiceScopeHandle? _handle;

  @override
  void initState() {
    super.initState();
    _handle = widget.voice?.attach(widget.scope);
  }

  @override
  void dispose() {
    _handle?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
