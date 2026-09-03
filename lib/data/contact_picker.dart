/// Choosing an emergency contact.
///
/// There is deliberately no contact-picker package here.
///
/// `flutter_contacts` force-unwraps `UIApplication.shared.delegate!.window!!`
/// at iOS plugin registration; that has been nil since iOS 13, so it crashes
/// any app that merely includes it.
///
/// `flutter_native_contact_picker` wraps the system picker and would have been
/// right, but it declares Java 1.8 while its Kotlin compiles to 17, and Gradle
/// refuses the mismatch. It cannot be configured from outside the plugin, and
/// it broke the Android build outright — a convenience is not worth a platform.
///
/// So the emergency contact is typed. Two fields, both labelled for a screen
/// reader, and the screen speaks any error rather than only showing it. The
/// picker can come back the day one of those packages is fixed; nothing else
/// has to change, because the screen already takes an injected picker and hides
/// the option when none is supplied.
library;

/// One chosen contact, if a picker is ever wired in again.
typedef PickedContact = ({String name, String number});
