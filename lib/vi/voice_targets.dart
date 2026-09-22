import 'package:flutter/foundation.dart';

import '../core/voice/spoken_targets.dart';

/// A button that can be pressed by saying its label.
class VoiceTarget {
  const VoiceTarget(this.label, this.onPressed);

  final String label;
  final VoidCallback onPressed;
}

/// Undoes or refreshes one [VoiceTargets.register].
class VoiceTargetHandle {
  VoiceTargetHandle._(this._owner, this._entry);

  final VoiceTargets _owner;
  final _Entry _entry;

  /// The button was rebuilt: a new label, or a new callback.
  void update(VoiceTarget target) => _entry.target = target;

  void remove() => _owner._entries.remove(_entry);
}

class _Entry {
  _Entry(this.target, this.route);
  VoiceTarget target;
  final String? route;
}

/// The buttons on screen, by route, for the microphone to press.
///
/// Each button registers with the route that was showing when it was built,
/// and only the current route's buttons are matched. The old screen's Back is
/// still mounted for a frame after the next screen opens - the same thing that
/// once let a leaving screen end the SOS countdown's listening.
class VoiceTargets {
  final List<_Entry> _entries = [];
  String? _route;

  void routeChanged(String? route) => _route = route;

  VoiceTargetHandle register(VoiceTarget target) {
    final entry = _Entry(target, _route);
    _entries.add(entry);
    return VoiceTargetHandle._(this, entry);
  }

  /// The buttons on the screen showing now, oldest first.
  List<VoiceTarget> get current => [
        for (final entry in _entries)
          if (entry.route == _route) entry.target,
      ];

  /// The buttons [words] names. The same label twice - a dialog's Cancel over
  /// a screen's - is one choice: the newest, which is the one on top.
  List<VoiceTarget> matches(String words, {bool exactOnly = false}) {
    final byLabel = <String, VoiceTarget>{};
    for (final target in current) {
      byLabel[identifyingWords(target.label).join(' ')] = target;
    }
    final targets = byLabel.values.toList();
    return [
      for (final i in matchSpokenTargets(
          words, [for (final t in targets) t.label],
          exactOnly: exactOnly))
        targets[i],
    ];
  }
}
