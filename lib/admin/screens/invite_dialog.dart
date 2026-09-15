import 'package:flutter/material.dart';

import '../../core/auth/email_address.dart';
import '../admin_theme.dart';

class InviteRequest {
  const InviteRequest({required this.email, required this.role, this.deviceId});

  final String email;
  final String role;
  final String? deviceId;
}

/// §1.2's add-user form.
///
/// Email and role, which the old one lacked. Device ID optional, which the old
/// one insisted on. No password field at all — the invited person chooses their
/// own when they register, and no administrator ever sees it.
Future<InviteRequest?> showInviteDialog(BuildContext context) =>
    showDialog<InviteRequest>(
      context: context,
      builder: (_) => const _InviteDialog(),
    );

class _InviteDialog extends StatefulWidget {
  const _InviteDialog();

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _email = TextEditingController();
  final _device = TextEditingController();
  String _role = 'vi';
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _device.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _email.text.trim();
    if (emailAddressProblem(email) != null) {
      setState(() => _error = 'Enter the email address they will register with.');
      return;
    }
    Navigator.of(context).pop(InviteRequest(
      email: email,
      role: _role,
      deviceId: _device.text.trim().isEmpty ? null : _device.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AdminColors.card,
      title: const Text('Invite someone'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                border: const OutlineInputBorder(),
                errorText: _error,
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
                DropdownMenuItem(value: 'vi', child: Text('Visually impaired user')),
                DropdownMenuItem(value: 'guardian', child: Text('Guardian')),
              ],
              onChanged: (value) => setState(() => _role = value ?? 'vi'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _device,
              decoration: const InputDecoration(
                labelText: 'Device ID (optional)',
                helperText: 'Leave blank. Most accounts have no device.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'They register themselves and choose their own password. '
              'Administrators are granted separately, in the Firebase console.',
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: AdminColors.inkMuted),
            ),
          ],
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
          child: const Text('Send invitation'),
        ),
      ],
    );
  }
}
