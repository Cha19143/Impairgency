/// Types of visual impairment, as a list to choose from.
///
/// A list rather than a free-text field, because a blind user dictating
/// "retinitis pigmentosa" into a text box and hoping the recogniser spelt it
/// is not a form they can fill in. The list is short, in plain words, and
/// ends in "Other" with a text field for the person the list left out.
///
/// Kept in `core/` so the labels the screen shows and the values the account
/// stores cannot drift apart, and so the list is unit-tested for the two
/// things that matter about it: every entry has a spoken description, and
/// none of them is a diagnosis the app would be pretending to make.
library;

enum ImpairmentType {
  blind,
  lowVision,
  colourBlind,
  nightBlind,
  tunnelVision,
  other,
}

/// What each choice says, on screen and out loud.
///
/// The detail says what it *means for the app*, not what it means clinically.
/// The question is asked so the app can behave differently, and the user
/// deserves to know which way.
const Map<ImpairmentType, ({String label, String detail})> kImpairmentChoices = {
  ImpairmentType.blind: (
    label: 'Blind',
    detail: 'Little or no useful sight. The app speaks everything.',
  ),
  ImpairmentType.lowVision: (
    label: 'Low vision',
    detail: 'Some sight. Large text and high contrast help.',
  ),
  ImpairmentType.colourBlind: (
    label: 'Colour blindness',
    detail: 'Colours are hard to tell apart. Nothing here relies on colour '
        'alone.',
  ),
  ImpairmentType.nightBlind: (
    label: 'Night blindness',
    detail: 'Hard to see in low light. Obstacle warnings matter most after '
        'dark.',
  ),
  ImpairmentType.tunnelVision: (
    label: 'Tunnel vision',
    detail: 'Narrow field of view. Warnings about things to the side matter '
        'most.',
  ),
  ImpairmentType.other: (
    label: 'Other',
    detail: 'Something else. You can describe it in your own words.',
  ),
};

/// The value stored on the account. The enum name, so a renamed label never
/// changes what old accounts mean.
String impairmentKey(ImpairmentType type) => type.name;

ImpairmentType? impairmentFromKey(String? key) {
  if (key == null) return null;
  for (final type in ImpairmentType.values) {
    if (type.name == key) return type;
  }
  return null;
}

/// The whole of what the personal-information step collects.
class PersonalInfo {
  const PersonalInfo({
    required this.name,
    required this.age,
    required this.impairment,
    this.impairmentDetail,
    this.phone,
  });

  final String name;
  final int age;
  final ImpairmentType impairment;

  /// Free text, only when [impairment] is [ImpairmentType.other].
  final String? impairmentDetail;

  /// The number a guardian's Call button dials. Optional, and said to be.
  final String? phone;

  Map<String, Object?> toJson() => {
        'name': name,
        // functions/index.js and the admin dashboard read displayName.
        'displayName': name,
        'age': age,
        'impairment': impairmentKey(impairment),
        if (impairmentDetail != null && impairmentDetail!.trim().isNotEmpty)
          'impairmentDetail': impairmentDetail!.trim(),
        if (phone != null && phone!.trim().isNotEmpty) 'phone': phone!.trim(),
      };
}

/// Why a personal-info form cannot be submitted, or null if it can.
///
/// Pure so the rules are tested once rather than re-implemented in every
/// screen that asks the same questions.
String? validatePersonalInfo({
  required String name,
  required String age,
  required ImpairmentType? impairment,
  String? impairmentDetail,
}) {
  if (name.trim().isEmpty) return 'Enter your name.';
  final years = int.tryParse(age.trim());
  if (years == null) return 'Enter your age as a number.';
  if (years < 1 || years > 120) return 'That does not look like an age.';
  if (impairment == null) return 'Choose the type of impairment that fits best.';
  if (impairment == ImpairmentType.other &&
      (impairmentDetail == null || impairmentDetail.trim().isEmpty)) {
    return 'Describe your impairment in a few words, or choose one from the '
        'list.';
  }
  return null;
}
