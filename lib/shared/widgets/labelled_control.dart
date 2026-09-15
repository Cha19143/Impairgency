import 'package:flutter/widgets.dart';

/// A control whose screen-reader label is written by hand, and which can
/// still be pressed without touching it.
///
/// `Semantics(label) > ExcludeSemantics > InkWell` is how this app makes a
/// control announce one clear sentence instead of its fragments. Excluding the
/// child's semantics also excludes its tap action, and nothing put it back.
/// TalkBack happened to cope, because Android injects a touch at the centre of
/// a node that has no click action. Voice Access ("tap Cancel"), Switch Access
/// and a keyboard have no such fallback: for them the button was a label.
///
/// So the action lives here, on the node that is announced.
class LabelledControl extends StatelessWidget {
  const LabelledControl({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.hint,
    this.toggled,
    this.selected,
    this.enabled,
  });

  final String label;
  final String? hint;
  final Widget child;

  /// Null disables the control, for the reader as well as for touch.
  final VoidCallback? onTap;

  /// Set for a switch-like control, which is announced as on or off rather
  /// than as a button.
  final bool? toggled;

  final bool? selected;

  /// Defaults to whether there is anything to do on tap.
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    final active = (enabled ?? true) && onTap != null;
    return Semantics(
      button: toggled == null,
      toggled: toggled,
      selected: selected,
      enabled: active,
      label: label,
      hint: hint,
      onTap: active ? onTap : null,
      child: ExcludeSemantics(child: child),
    );
  }
}
