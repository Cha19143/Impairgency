import 'package:flutter/material.dart';

import '../../core/admin/admin_user.dart';
import '../../core/profile/impairment.dart';
import '../admin_theme.dart';

/// §1.2's add-account form, now that the dashboard can make one.
///
/// Still no password field. The new account gets Firebase's own email to
/// choose a password, so nobody at a dashboard ever knows one.
Future<NewAccount?> showAddAccountDialog(BuildContext context) =>
    showDialog<NewAccount>(
      context: context,
      builder: (_) => const _AccountDialog(),
    );

/// Edits what an administrator may change. Returns only the fields that
/// changed - a value of null removes the field - or null if nothing did.
Future<Map<String, Object?>?> showEditAccountDialog(
        BuildContext context, AdminUserRow user) =>
    showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _AccountDialog(editing: user),
    );

/// Asks before removing an account, and says exactly what removing does.
Future<bool> confirmRemoveAccount(BuildContext context, AdminUserRow user) async {
  final removed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AdminColors.card,
      title: Text('Remove ${user.name}?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This deletes their profile, their links to '
              '${user.isGuardian ? 'the people they watch over' : 'guardians'}, '
              'their location history and what the app noticed. Their phone '
              'is signed out and deletes their saved places.',
              style: const TextStyle(fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 12),
            Text(
              'Their sign-in record stays in Firebase Authentication: removing '
              'that needs the Firebase console. Until it is removed there, '
              '${user.email ?? 'this email'} cannot be used for a new account.',
              style: const TextStyle(
                  fontSize: 12.5, height: 1.45, color: AdminColors.inkMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AdminColors.bad),
          child: const Text('Remove account'),
        ),
      ],
    ),
  );
  return removed ?? false;
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({this.editing});

  final AdminUserRow? editing;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final AdminUserRow? _user = widget.editing;
  late final _email = TextEditingController(text: _user?.email ?? '');
  late final _name = TextEditingController(text: _user?.displayName ?? '');
  late final _age = TextEditingController(text: _user?.age?.toString() ?? '');
  late final _phone = TextEditingController(text: _user?.phone ?? '');
  late String _role = _user?.role == 'guardian' ? 'guardian' : 'vi';
  late ImpairmentType? _impairment = _user?.impairment;
  String? _error;

  bool get _editing => _user != null;

  @override
  void dispose() {
    for (final c in [_email, _name, _age, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final problem = newAccountProblem(
      email: _email.text,
      name: _name.text,
      age: _role == 'vi' ? _age.text : '',
      phone: _phone.text,
      role: _role,
      checkEmail: !_editing,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final age = _role == 'vi' ? int.tryParse(_age.text.trim()) : null;
    final phone = _phone.text.trim().isEmpty ? null : _phone.text.trim();
    final impairment = _role == 'vi' ? _impairment : null;

    final user = _user;
    if (user == null) {
      Navigator.of(context).pop(NewAccount(
        email: _email.text.trim(),
        name: _name.text.trim(),
        role: _role,
        impairment: impairment,
        age: age,
        phone: phone,
      ));
      return;
    }

    final name = _name.text.trim();
    final changes = <String, Object?>{
      if (name != (user.displayName ?? '')) ...{
        'name': name,
        'displayName': name,
      },
      if (_role != user.role) 'role': _role,
      if (age != user.age) 'age': age,
      if (phone != user.phone) 'phone': phone,
      if (impairment != user.impairment)
        'impairment': impairment == null ? null : impairmentKey(impairment),
    };
    Navigator.of(context).pop(changes.isEmpty ? null : changes);
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final roleChanged = user != null && _role != user.role;

    return AlertDialog(
      backgroundColor: AdminColors.card,
      title: Text(_editing ? 'Edit ${user!.name}' : 'Add an account'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _email,
                autofocus: !_editing,
                enabled: !_editing,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  helperText: _editing
                      ? 'The sign-in email cannot be changed from here.'
                      : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                autofocus: _editing,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'vi', child: Text('Visually impaired user')),
                  DropdownMenuItem(value: 'guardian', child: Text('Guardian')),
                ],
                onChanged: (value) => setState(() => _role = value ?? 'vi'),
              ),
              if (roleChanged) ...[
                const SizedBox(height: 8),
                Text(
                  'Changing the role removes their '
                  '${user.linkedTo.length} link'
                  '${user.linkedTo.length == 1 ? '' : 's'}, and their phone '
                  'opens the other app the next time it is online.',
                  style: const TextStyle(
                      fontSize: 12, height: 1.4, color: AdminColors.warn),
                ),
              ],
              if (_role == 'vi') ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<ImpairmentType?>(
                  initialValue: _impairment,
                  decoration: const InputDecoration(
                    labelText: 'Type of impairment',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Not recorded')),
                    for (final entry in kImpairmentChoices.entries)
                      DropdownMenuItem(
                          value: entry.key, child: Text(entry.value.label)),
                  ],
                  onChanged: (value) => setState(() => _impairment = value),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _age,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Age (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!,
                      style: const TextStyle(
                          fontSize: 13, color: AdminColors.bad)),
                ),
              ],
              if (!_editing) ...[
                const SizedBox(height: 14),
                const Text(
                  'No password is chosen here. They get an email with a link '
                  'to choose their own, and confirm their address with it.',
                  style: TextStyle(
                      fontSize: 12, height: 1.4, color: AdminColors.inkMuted),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AdminColors.chrome),
          child: Text(_editing ? 'Save changes' : 'Add account'),
        ),
      ],
    );
  }
}
