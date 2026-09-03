import 'package:flutter/material.dart';

import '../admin_theme.dart';

/// Returns null on success, or a message to show.
typedef SignInHandler = Future<String?> Function(String email, String password);

class AdminSignInScreen extends StatefulWidget {
  const AdminSignInScreen({
    super.key,
    required this.onSignIn,
    this.signedInAs,
    this.signedInUid,
    this.onSignOut,
  });

  final SignInHandler onSignIn;

  /// Set when the visitor is authenticated but not on the admin roster.
  ///
  /// Without this the guard sends them back to this screen, which they are
  /// already looking at, and nothing appears to happen. Authenticating
  /// successfully and being shown the login form again is the most confusing
  /// failure a sign-in page can have.
  final String? signedInAs;

  final String? signedInUid;
  final VoidCallback? onSignOut;

  @override
  State<AdminSignInScreen> createState() => _AdminSignInScreenState();
}

class _AdminSignInScreenState extends State<AdminSignInScreen> {
  Widget _notOnRoster(BuildContext context) {
    final uid = widget.signedInUid ?? '';
    return Scaffold(
      backgroundColor: AdminColors.chrome,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AdminColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      'Signed in, but not an administrator',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AdminColors.ink),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You are signed in as ${widget.signedInAs}. That account '
                    'is not on the admin roster, so the dashboard will not '
                    'open.',
                    style: const TextStyle(
                        fontSize: 13.5, height: 1.45, color: AdminColors.ink),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'To grant it, create a document in Firestore with this '
                    'exact ID:',
                    style: TextStyle(
                        fontSize: 13, color: AdminColors.inkMuted, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    'admins/$uid',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13.5,
                      color: AdminColors.ink,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'The roster is deny-all from every client, so it can only '
                    'be granted in the Firebase console. That is deliberate: '
                    'it is what lets admin work without a paid plan.',
                    style: TextStyle(
                        fontSize: 12.5, height: 1.45,
                        color: AdminColors.inkMuted),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: widget.onSignOut,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44)),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final failure = await widget.onSignIn(_email.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.signedInAs != null) return _notOnRoster(context);

    return Scaffold(
      backgroundColor: AdminColors.chrome,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AdminColors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      'ImpairGency admin',
                      style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: AdminColors.ink),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Administrator accounts are granted in the Firebase '
                    'console. Signing in here does not create one.',
                    style:
                        TextStyle(fontSize: 13, color: AdminColors.inkMuted),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _email,
                    autofocus: true,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      errorText: _error,
                      errorMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: AdminColors.chrome,
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('SIGN IN'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
