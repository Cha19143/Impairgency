/// A yes or a no, and nothing else.
///
/// Only the words a prompt asked for. "Okay", "done", and "keep it" are not
/// a yes: those words save, skip, or sign out on other screens, and a loose
/// match would do that by accident. "Keep it" belongs only to a prompt that
/// says "Keep it", and that prompt does not use this.
library;

/// The answer [parseYesNo] heard.
enum YesNo { yes, no }

/// [heard] as a single utterance: lower case, punctuation aside from
/// apostrophes removed, and a trailing "please" or "po" taken off.
///
/// Null when nothing was said.
String? normalizeUtterance(String? heard) {
  if (heard == null) return null;
  var said = heard
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9\s']"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  while (said.isNotEmpty) {
    final stripped = said.replaceFirst(RegExp(r"\s+(please|po)$"), '');
    if (stripped == said) break;
    said = stripped.trim();
  }
  if (said.isEmpty) return null;
  return said;
}

/// [heard] as yes or no. Null when it is anything else, including silence.
YesNo? parseYesNo(String? heard) {
  return switch (normalizeUtterance(heard)) {
    'yes' || 'yeah' || 'correct' => YesNo.yes,
    'no' || 'nope' => YesNo.no,
    _ => null,
  };
}
