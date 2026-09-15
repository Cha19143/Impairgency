import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/contacts/emergency_contact.dart';
import '../../core/speech/speaker.dart';
import '../../data/contact_picker.dart';
import '../widgets/vi_button.dart';
import '../widgets/vi_screen.dart';

/// Who an SOS rings, and in what order.
///
/// One person became up to five at the tester's request. The list *is* the
/// calling order - see `emergency_contact.dart` - and the screen says so, in
/// words, every time it changes: "Mum will be called first, then Dad."
///
/// Two ways to add someone: type a name and number, or choose one from the
/// phone's contacts through the system picker, which hands over one row and
/// never the address book. Still skippable, and skipping still says what it
/// costs, out loud, before it is done.
class EmergencyContactScreen extends StatefulWidget {
  const EmergencyContactScreen({
    super.key,
    required this.onSave,
    required this.onSkip,
    this.initial = const [],
    this.picker,
    this.speaker = const SilentSpeaker(),
  });

  final void Function(List<EmergencyContact> contacts) onSave;
  final VoidCallback onSkip;

  /// What is saved already, when the screen is opened from settings.
  final List<EmergencyContact> initial;

  /// The system picker. Null hides the option - a web build, or a test.
  final ContactPicker? picker;

  final Speaker speaker;

  @override
  State<EmergencyContactScreen> createState() => _EmergencyContactScreenState();
}

class _EmergencyContactScreenState extends State<EmergencyContactScreen> {
  late final List<EmergencyContact> _contacts = [...widget.initial];
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _numberFocus = FocusNode();
  final _nameFocus = FocusNode();
  String? _error;
  bool _confirmingSkip = false;
  bool _picking = false;

  static const String skipWarning =
      'Without a contact, an emergency SOS can sound the alarm and share where '
      'you are, but it will have nobody to call. You can add one later from '
      'settings.';

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _numberFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final failure = validateNewContact(
      name: _name.text,
      number: _number.text,
      existing: _contacts,
    );
    if (failure != null) {
      await _fail(failure);
      return;
    }
    final contact = EmergencyContact(
      name: _name.text.trim(),
      number: _number.text.trim(),
    );
    setState(() {
      _contacts.add(contact);
      _name.clear();
      _number.clear();
      _error = null;
    });
    await widget.speaker.speak(
        '${contact.name} added. ${describeContactOrder(_contacts)}');
    _nameFocus.requestFocus();
  }

  Future<void> _fail(String message) async {
    setState(() => _error = message);
    await widget.speaker.speak(message);
  }

  Future<void> _pick() async {
    final picker = widget.picker;
    if (picker == null || _picking) return;
    if (_contacts.length >= kMaxEmergencyContacts) {
      await _fail(validateNewContact(
          name: 'x', number: '00000000', existing: _contacts)!);
      return;
    }
    setState(() => _picking = true);
    final outcome = await picker.pick();
    if (!mounted) return;
    setState(() => _picking = false);
    switch (outcome) {
      case ContactPicked(:final contact):
        final failure = validateNewContact(
          name: contact.name,
          number: contact.number,
          existing: _contacts,
        );
        if (failure != null) {
          await _fail(failure);
          return;
        }
        setState(() {
          _contacts.add(contact);
          _error = null;
        });
        await widget.speaker.speak('${contact.name}, ${contact.number}, '
            'added. ${describeContactOrder(_contacts)}');
      case ContactPickCancelled():
        // Cancelled, or a contact with no number on it. Not an error.
        await widget.speaker.speak('No contact was chosen. You can type one '
            'instead.');
      case ContactPickUnavailable(:final reason):
        await _fail(reason);
    }
  }

  Future<void> _moveUp(int index) async {
    if (index <= 0) return;
    setState(() {
      final c = _contacts.removeAt(index);
      _contacts.insert(index - 1, c);
    });
    await widget.speaker.speak(describeContactOrder(_contacts));
  }

  Future<void> _remove(int index) async {
    final removed = _contacts[index];
    setState(() => _contacts.removeAt(index));
    await widget.speaker
        .speak('${removed.name} removed. ${describeContactOrder(_contacts)}');
  }

  Future<void> _save() async {
    if (_contacts.isEmpty) {
      // A typed but not yet added person counts. Nobody should lose a
      // contact to a button they did not know they had to press.
      if (_name.text.trim().isNotEmpty || _number.text.trim().isNotEmpty) {
        await _add();
        if (_contacts.isEmpty) return;
      } else {
        await _fail('Add at least one person, or skip this step.');
        return;
      }
    } else if (_name.text.trim().isNotEmpty ||
        _number.text.trim().isNotEmpty) {
      await _add();
      if (_error != null) return;
    }
    widget.onSave(List.unmodifiable(_contacts));
  }

  Future<void> _skip() async {
    if (!_confirmingSkip) {
      // Said before it is done, not after. A warning that arrives once the
      // decision is made is not a warning.
      setState(() => _confirmingSkip = true);
      await widget.speaker.speak(skipWarning);
      return;
    }
    widget.onSkip();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial.isNotEmpty;
    return ViScreen(
      speaker: widget.speaker,
      step: editing ? null : 'Step 4 of 7',
      title: 'Who should we call in an emergency?',
      body: [
        'Up to $kMaxEmergencyContacts people. They are called in this order '
            'when you say "help" or press the SOS button, and all of them '
            'can be sent a text.',
      ],
      spokenSuffix: _contacts.isEmpty
          ? 'Enter a name and number, choose someone from your contacts, or '
              'skip this step.'
          : describeContactOrder(_contacts),
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _contacts.length; i++)
            _ContactRow(
              index: i,
              contact: _contacts[i],
              total: _contacts.length,
              onMoveUp: i == 0 ? null : () => _moveUp(i),
              onRemove: () => _remove(i),
            ),
          if (_contacts.isNotEmpty) const SizedBox(height: 10),
          if (_contacts.length < kMaxEmergencyContacts) ...[
            Semantics(
              textField: true,
              label: 'Their name',
              child: TextField(
                controller: _name,
                focusNode: _nameFocus,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(
                    fontSize: 20, color: AppColors.textPrimary),
                onSubmitted: (_) => _numberFocus.requestFocus(),
                decoration: const InputDecoration(
                  labelText: 'Their name',
                  labelStyle: TextStyle(fontSize: 17),
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Semantics(
              textField: true,
              label: 'Their phone number',
              child: TextField(
                controller: _number,
                focusNode: _numberFocus,
                keyboardType: TextInputType.phone,
                style: const TextStyle(
                    fontSize: 20, color: AppColors.textPrimary),
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  labelText: 'Their phone number',
                  labelStyle: const TextStyle(fontSize: 17),
                  errorText: _error,
                  errorMaxLines: 3,
                  errorStyle: const TextStyle(fontSize: 15),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 20),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ViButton(
              label: 'Add this person',
              icon: Icons.person_add_alt_1,
              kind: ViButtonKind.secondary,
              onPressed: _add,
            ),
            if (widget.picker != null)
              ViButton(
                label: _picking ? 'Opening your contacts…' : 'Choose from my contacts',
                detail: 'Picks one person. The app never reads your address '
                    'book.',
                icon: Icons.contacts_outlined,
                kind: ViButtonKind.secondary,
                onPressed: _picking ? null : _pick,
              ),
          ] else if (_error != null)
            Text(
              _error!,
              style: const TextStyle(
                  fontSize: 16, height: 1.35, color: AppColors.amber),
            ),
          if (_confirmingSkip) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                skipWarning,
                style: TextStyle(
                    fontSize: 16, height: 1.4, color: AppColors.amber),
              ),
            ),
          ],
        ],
      ),
      actions: [
        ViButton(
          label: _contacts.isEmpty
              ? 'Save'
              : 'Save ${_contacts.length == 1 ? 'this contact' : 'these ${_contacts.length} contacts'}',
          semanticLabel: _contacts.isEmpty
              ? 'Save'
              : 'Save. ${describeContactOrder(_contacts)}',
          icon: Icons.check,
          onPressed: _save,
        ),
        if (!editing)
          ViButton(
            label: _confirmingSkip ? 'Skip anyway' : 'Skip for now',
            semanticLabel: _confirmingSkip
                ? 'Skip anyway. SOS will have nobody to call.'
                : 'Skip for now. This will explain what SOS cannot do without '
                    'a contact.',
            kind: ViButtonKind.quiet,
            onPressed: _skip,
          )
        else
          ViButton(
            label: 'Back without saving',
            kind: ViButtonKind.quiet,
            onPressed: widget.onSkip,
          ),
      ],
    );
  }
}

/// One person on the list: their place in the order, and the two things
/// that can be done to it. The order is spoken as "called first" rather
/// than "1", because a number is a position and a blind user wants to know
/// what the position does.
class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.index,
    required this.contact,
    required this.total,
    required this.onMoveUp,
    required this.onRemove,
  });

  final int index;
  final EmergencyContact contact;
  final int total;
  final VoidCallback? onMoveUp;
  final VoidCallback onRemove;

  String get _position => index == 0
      ? 'Called first'
      : index == 1
          ? 'Called second'
          : 'Called ${index + 1}${_ordinal(index + 1)}';

  static String _ordinal(int n) => switch (n % 10) {
        3 when n != 13 => 'rd',
        _ => 'th',
      };

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: AppColors.navyRaised,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                label: '${contact.name}, ${contact.number}. $_position.',
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${contact.number} · $_position',
                        style: const TextStyle(
                            fontSize: 15, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Semantics(
              button: true,
              enabled: onMoveUp != null,
              label: 'Move ${contact.name} up, so they are called sooner',
              onTap: onMoveUp,
              child: ExcludeSemantics(
                child: IconButton(
                  iconSize: 32,
                  constraints: const BoxConstraints(
                      minWidth: kMinTargetSize, minHeight: kMinTargetSize),
                  onPressed: onMoveUp,
                  icon: Icon(Icons.arrow_upward,
                      color: onMoveUp == null
                          ? AppColors.hairline
                          : AppColors.cyan),
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Remove ${contact.name}',
              onTap: onRemove,
              child: ExcludeSemantics(
                child: IconButton(
                  iconSize: 32,
                  constraints: const BoxConstraints(
                      minWidth: kMinTargetSize, minHeight: kMinTargetSize),
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline, color: AppColors.red),
                ),
              ),
            ),
          ],
        ),
      );
}
