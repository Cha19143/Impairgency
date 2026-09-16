import 'package:flutter/widgets.dart';

import '../voice_controller.dart';

/// The app's microphone, for widgets deep in a screen: a button that can be
/// pressed by name, a field that can be filled in by voice, the microphone
/// button every screen carries.
///
/// Provided once, above every route. Absent in a widget test that does not
/// provide it, and then those widgets are exactly what they were before voice
/// reached them.
class VoiceAccess extends InheritedWidget {
  const VoiceAccess({super.key, required this.voice, required super.child});

  final VoiceController? voice;

  static VoiceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VoiceAccess>()?.voice;

  @override
  bool updateShouldNotify(VoiceAccess oldWidget) => voice != oldWidget.voice;
}
