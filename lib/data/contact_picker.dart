import 'dart:async';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/contacts/emergency_contact.dart';

/// Choosing an emergency contact from the phone's address book.
///
/// There is deliberately no contact-picker *package* here.
///
/// `flutter_contacts` force-unwraps `UIApplication.shared.delegate!.window!!`
/// at iOS plugin registration; that has been nil since iOS 13, so it crashes
/// any app that merely includes it. `flutter_native_contact_picker` declares
/// Java 1.8 while its Kotlin compiles to 17, and Gradle refuses the mismatch.
///
/// So this is the *system* picker, reached over a method channel of our own:
/// `ACTION_PICK` on Android and `CNContactPickerViewController` on iOS. Both
/// hand back the one contact the user chose and nothing else, which is why
/// neither needs the contacts permission - the app never reads the address
/// book, the user reads it and hands over one row. For an app holding data
/// about disabled people, that is the better design as well as the cheaper
/// one. The native halves are in `MainActivity.kt` and `AppDelegate.swift`.
///
/// One Android edge remains: some vendor pickers return a row the app cannot
/// then read without `READ_CONTACTS`. The native side reports that as
/// [ContactPickOutcome.needsPermission], the permission is asked for once,
/// and the pick is retried.
sealed class ContactPickOutcome {
  const ContactPickOutcome();
}

class ContactPicked extends ContactPickOutcome {
  const ContactPicked(this.contact);

  final EmergencyContact contact;
}

/// The user backed out, or chose a row with no phone number.
class ContactPickCancelled extends ContactPickOutcome {
  const ContactPickCancelled();
}

/// No picker on this device, or it refused to open.
class ContactPickUnavailable extends ContactPickOutcome {
  const ContactPickUnavailable(this.reason);

  final String reason;
}

abstract interface class ContactPicker {
  Future<ContactPickOutcome> pick();
}

class SystemContactPicker implements ContactPicker {
  const SystemContactPicker();

  static const _channel = MethodChannel('ph.impairgency/contacts');

  @override
  Future<ContactPickOutcome> pick() async {
    var askedForPermission = false;
    while (true) {
      try {
        final result = await _channel.invokeMethod<Map<Object?, Object?>>(
            'pick');
        if (result == null) return const ContactPickCancelled();
        final name = result['name'] as String? ?? '';
        final number = result['number'] as String? ?? '';
        if (dialableNumber(number).isEmpty) return const ContactPickCancelled();
        return ContactPicked(EmergencyContact(
          name: name.trim().isEmpty ? number.trim() : name.trim(),
          number: number.trim(),
        ));
      } on PlatformException catch (e) {
        if (e.code == 'needs_permission' && !askedForPermission) {
          askedForPermission = true;
          final status = await Permission.contacts.request();
          if (status.isGranted || status.isLimited) continue;
          return const ContactPickUnavailable(
              'The app was not allowed to read the contact you chose. You '
              'can type the number instead.');
        }
        return ContactPickUnavailable(e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'The contacts picker could not open. You can type the number '
                'instead.');
      } on MissingPluginException {
        return const ContactPickUnavailable(
            'Choosing from contacts is not available on this device. You can '
            'type the number instead.');
      }
    }
  }
}
