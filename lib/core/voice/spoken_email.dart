/// A spoken email address, as the recogniser wrote it down.
///
/// The shaping rules already live in [shapeDictation]. This names them for
/// the onboarding voice flow, so a screen does not grow a second parser.
library;

import 'dictation.dart';

/// [heard] as an email address: "at" is `@`, "dot" is `.`, spaces are
/// removed, and the rest is lower case. Empty when nothing usable was heard.
String spokenEmail(String heard) =>
    shapeDictation(DictationShape.email, heard);

/// [email] read back slowly, with "at" and "dot" spoken as words.
String spokenEmailAloud(String email) =>
    readBack(DictationShape.email, email);
