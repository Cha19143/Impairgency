import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_theme.dart';
import 'admin_shell.dart';

/// Returns null on success, or a message to show.
typedef SignInHandler = Future<String?> Function(String email, String password);

/// The dashboard's front door.
///
/// Three states on one page: the form; when someone authenticates with an
/// account that is not on the admin roster, the explanation of why the
/// dashboard still will not open; and, when the roster could not be read at
/// all, that it is still being checked.
///
/// The layout answers to the dashboard behind it. At
/// [kAdminSidebarBreakpoint], the width where the shell shows its sidebar
/// rather than a drawer, this page splits into a navy panel and the form, so
/// the first screen of the product already looks like the rest of it. Below
/// that width the panel's ground carries the whole page and the card floats on
/// it: a phone has no room for both, and a white card on a white page has no
/// shape at all.
class AdminSignInScreen extends StatefulWidget {
  const AdminSignInScreen({
    super.key,
    required this.onSignIn,
    this.signedInAs,
    this.signedInUid,
    this.checkingRoster = false,
    this.onCheckAgain,
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

  /// With [signedInAs]: the roster read did not answer, so whether this
  /// account is an administrator is not known yet. Saying "not an
  /// administrator" then would be a guess, and the wrong one for the person
  /// most likely to be here.
  final bool checkingRoster;

  /// Asks the roster again.
  final Future<void> Function()? onCheckAgain;

  final VoidCallback? onSignOut;

  @override
  State<AdminSignInScreen> createState() => _AdminSignInScreenState();
}

class _AdminSignInScreenState extends State<AdminSignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  String? _error;
  bool _busy = false;
  bool _revealPassword = false;
  bool _checking = false;

  Future<void> _checkAgain() async {
    final check = widget.onCheckAgain;
    if (check == null || _checking) return;
    setState(() => _checking = true);
    try {
      await check();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Trimmed: an address pasted from a password manager, or typed on a phone
    // keyboard that adds a space after a word, arrives with whitespace on the
    // end. "That email and password do not match an account" is a poor way to
    // find that out.
    final failure = await widget.onSignIn(_email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kAdminSidebarBreakpoint;
    final onRoster = widget.signedInAs == null;

    return Scaffold(
      backgroundColor: AdminColors.canvas,
      body: _Page(
        wide: wide,
        maxCardWidth: onRoster ? 416 : 520,
        card: onRoster
            ? _signInCard(wide)
            : widget.checkingRoster
                ? _checkingRosterCard(wide)
                : _notOnRosterCard(context, wide),
      ),
    );
  }

  Widget _signInCard(bool wide) => _Card(
        children: [
          // The brand is on the panel when there is a panel. On a phone there
          // is not, so it comes into the card rather than going missing.
          if (!wide) ...[
            const _BrandMark(onDark: false),
            const SizedBox(height: 26),
          ],
          Semantics(
            header: true,
            child: const Text(
              'Sign in',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
                color: AdminColors.ink,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Staff access to the ImpairGency dashboard.',
            style: TextStyle(fontSize: 13.5, color: AdminColors.inkMuted),
          ),
          const SizedBox(height: 26),
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Field(
                  label: 'Email',
                  hint: 'you@example.com',
                  icon: Icons.alternate_email,
                  controller: _email,
                  enabled: !_busy,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passwordFocus.requestFocus(),
                ),
                const SizedBox(height: 16),
                _Field(
                  label: 'Password',
                  icon: Icons.lock_outline,
                  controller: _password,
                  focusNode: _passwordFocus,
                  enabled: !_busy,
                  obscure: !_revealPassword,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  trailing: IconButton(
                    onPressed: _busy
                        ? null
                        : () =>
                            setState(() => _revealPassword = !_revealPassword),
                    icon: Icon(
                      _revealPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 19,
                    ),
                    color: AdminColors.inkMuted,
                    // A typed password nobody can check is a password typed
                    // twice. The tooltip is also the screen reader's label.
                    tooltip:
                        _revealPassword ? 'Hide password' : 'Show password',
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 18),
            _ErrorBanner(_error!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AdminColors.chrome,
              foregroundColor: Colors.white,
              // Barely lightened, not greyed out: while it is busy the
              // button is still saying something ("Signing in…"), and a
              // disabled fill pale enough to make that unreadable would be
              // hiding the only progress the user has.
              disabledBackgroundColor:
                  AdminColors.chrome.withValues(alpha: 0.88),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
            child: _busy
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 17,
                        width: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 12),
                      // Named, not just spinning: a spinner says something is
                      // happening, the word says what.
                      Text('Signing in…'),
                    ],
                  )
                : const Text('Sign in'),
          ),
          const SizedBox(height: 20),
          const _Footnote(
            'Administrator accounts are granted in the Firebase console. '
            'Signing in here does not create one.',
          ),
        ],
      );

  Widget _checkingRosterCard(bool wide) => _Card(
        children: [
          if (!wide) ...[
            const _BrandMark(onDark: false),
            const SizedBox(height: 26),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AdminColors.field,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.cloud_sync_outlined,
                    size: 20, color: AdminColors.chrome),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Semantics(
                  header: true,
                  child: const Text(
                    'Checking the admin roster…',
                    style: TextStyle(
                      fontSize: 19,
                      height: 1.25,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'You are signed in as ${widget.signedInAs}, but the database has '
            'not answered whether that account is an administrator. This '
            'usually means the connection is slow or down. The dashboard '
            'opens as soon as it answers.',
            style: const TextStyle(
                fontSize: 13.5, height: 1.5, color: AdminColors.ink),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _checking ? null : _checkAgain,
            style: FilledButton.styleFrom(
              backgroundColor: AdminColors.chrome,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  AdminColors.chrome.withValues(alpha: 0.88),
              disabledForegroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: Text(_checking ? 'Checking…' : 'Check again'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: widget.onSignOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminColors.ink,
              minimumSize: const Size.fromHeight(46),
              side: const BorderSide(color: AdminColors.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: const Text('Sign out'),
          ),
        ],
      );

  Widget _notOnRosterCard(BuildContext context, bool wide) {
    final uid = widget.signedInUid ?? '';
    return _Card(
      children: [
        if (!wide) ...[
          const _BrandMark(onDark: false),
          const SizedBox(height: 26),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AdminColors.badTint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.person_off_outlined,
                  size: 20, color: AdminColors.bad),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Semantics(
                header: true,
                child: const Text(
                  'Signed in, but not an administrator',
                  style: TextStyle(
                    fontSize: 19,
                    height: 1.25,
                    fontWeight: FontWeight.bold,
                    color: AdminColors.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'You are signed in as ${widget.signedInAs}. That account is not on '
          'the admin roster, so the dashboard will not open.',
          style: const TextStyle(
              fontSize: 13.5, height: 1.5, color: AdminColors.ink),
        ),
        const SizedBox(height: 20),
        const Text(
          'To grant it, create a document in Firestore with this exact ID:',
          style: TextStyle(
              fontSize: 13, height: 1.45, color: AdminColors.inkMuted),
        ),
        const SizedBox(height: 10),
        _CodeLine(text: 'admins/$uid'),
        const SizedBox(height: 16),
        const Text(
          'The roster is deny-all from every client, so it can only be granted '
          'in the Firebase console. That is deliberate: it is what lets admin '
          'work without a paid plan.',
          style: TextStyle(
              fontSize: 12.5, height: 1.5, color: AdminColors.inkMuted),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: widget.onSignOut,
          style: OutlinedButton.styleFrom(
            foregroundColor: AdminColors.ink,
            minimumSize: const Size.fromHeight(46),
            side: const BorderSide(color: AdminColors.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

/// Panel and form, or one column with the card on the brand's ground.
class _Page extends StatelessWidget {
  const _Page({
    required this.card,
    required this.wide,
    required this.maxCardWidth,
  });

  final Widget card;
  final bool wide;
  final double maxCardWidth;

  @override
  Widget build(BuildContext context) {
    final form = _Centred(maxWidth: maxCardWidth, child: card);
    if (!wide) return _BrandGround(child: form);

    return Row(
      children: [
        const Expanded(child: _BrandPanel()),
        Expanded(
          child: ColoredBox(color: AdminColors.canvas, child: form),
        ),
      ],
    );
  }
}

/// Centred when there is room, scrolled when there is not.
///
/// A login page is the one screen that has to survive a laptop with a browser
/// bar, a phone with a keyboard open, and 200% zoom. `Center` alone clips at
/// the top; a scroll view alone parks the card against the ceiling. This is
/// both.
class _Centred extends StatelessWidget {
  const _Centred({required this.child, required this.maxWidth});

  final Widget child;
  final double maxWidth;

  static const EdgeInsets _padding =
      EdgeInsets.symmetric(horizontal: 24, vertical: 32);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: _padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - _padding.vertical)
                  .clamp(0.0, double.infinity),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: child,
              ),
            ),
          ),
        ),
      );
}

/// Navy, lifted by one soft light source off the top corner.
class _BrandGround extends StatelessWidget {
  const _BrandGround({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AdminColors.chrome, Color(0xFF16336B)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -170,
              right: -140,
              child: Container(
                width: 520,
                height: 520,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AdminColors.accent.withValues(alpha: 0.16),
                      AdminColors.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      );
}

/// What is behind the door, said plainly.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(48, 44, 48, 40);

  @override
  Widget build(BuildContext context) => _BrandGround(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: _padding,
              // Top-centre, not Center: a Center hands the column loose
              // height, the column shrinks to fit its content, and the
              // spaceBetween below then has nothing to space.
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 460,
                    minHeight: (constraints.maxHeight - _padding.vertical)
                        .clamp(0.0, double.infinity),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _BrandMark(onDark: true),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'The dashboard behind the app.',
                              style: TextStyle(
                                fontSize: 30,
                                height: 1.2,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Who is using ImpairGency, what the service is '
                              'doing right now, and the evidence behind what '
                              'it claims.',
                              style: TextStyle(
                                fontSize: 14.5,
                                height: 1.55,
                                color: AdminColors.chromeText,
                              ),
                            ),
                            const SizedBox(height: 28),
                            // The sections the sidebar will show, from the
                            // list the sidebar itself renders — so this can
                            // never advertise a screen that is not there.
                            LayoutBuilder(
                              builder: (context, box) => Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final section in adminSections)
                                    SizedBox(
                                      // Two to a row: four sections of
                                      // uneven name length wrap 3 + 1 left
                                      // to themselves, which reads as an
                                      // accident rather than a list.
                                      width: (box.maxWidth - 10) / 2,
                                      child: _SectionChip(section),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        'Assistive navigation, environment awareness and '
                        'emergency contact.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: AdminColors.chromeText,
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
              ),
            ),
          ),
      );
}

class _SectionChip extends StatelessWidget {
  const _SectionChip(this.section);

  final AdminSection section;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(section.icon, size: 16, color: AdminColors.accent),
            const SizedBox(width: 9),
            // Flexible, like the sidebar item this mirrors: "System health"
            // is wider than half a narrow panel, and a Row that cannot give
            // way overflows rather than shortening.
            Flexible(
              child: Text(
                section.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.onDark});

  final bool onDark;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AdminColors.accent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.shield_outlined,
                size: 22, color: AdminColors.inkOnAccent),
          ),
          const SizedBox(width: 13),
          // Flexible: on a narrow phone, or at a large text scale, the name
          // is wider than the card it sits in. Wrapping is fine; a product
          // name clipped mid-word on its own login page is not.
          Flexible(
            child: Text(
              'ImpairGency admin',
              style: TextStyle(
                fontSize: 17,
                height: 1.2,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
                color: onDark ? Colors.white : AdminColors.ink,
              ),
            ),
          ),
        ],
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AdminColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AdminColors.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A0A1A3F),
              blurRadius: 34,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.icon,
    required this.controller,
    required this.enabled,
    this.hint,
    this.focusNode,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.trailing,
  });

  final String label;
  final String? hint;
  final IconData icon;
  final TextEditingController controller;
  final bool enabled;
  final FocusNode? focusNode;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // The fill, the borders, the label style and the focus ring come from
    // buildAdminTheme's inputDecorationTheme, so a field here and a field in
    // the invite dialog cannot drift apart.
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscure,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 14.5, color: AdminColors.ink),
      decoration: InputDecoration(
        // The label stays above the field rather than sitting in it — the
        // theme floats it always. A label that vanishes as soon as there is
        // text is a label you cannot check your answer against.
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: AdminColors.inkMuted),
        prefixIcon: Icon(icon, size: 19, color: AdminColors.inkMuted),
        suffixIcon: trailing,
      ),
    );
  }
}

/// Why the sign-in was refused, where the eye already is.
///
/// It used to be `errorText` under the password field, which put the reason
/// below the fold of the card on a short window and left the button looking
/// like it had done nothing.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AdminColors.badTint,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFF0C8CD)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 18, color: AdminColors.bad),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AdminColors.bad,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.lock_outline, size: 15,
                color: AdminColors.inkMuted),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AdminColors.inkMuted,
              ),
            ),
          ),
        ],
      );
}

/// The document ID, selectable and copyable.
///
/// A UID nobody can copy is a UID nobody can act on, and this one has to be
/// typed into the Firebase console exactly.
class _CodeLine extends StatelessWidget {
  const _CodeLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        decoration: BoxDecoration(
          color: AdminColors.field,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AdminColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              // Selectable for the mouse, but read out as text: on the web a
              // SelectableText reaches a screen reader as an empty, disabled
              // text area, so the one line this screen exists to give was the
              // one line a screen reader could not read.
              child: Semantics(
                label: text,
                child: ExcludeSemantics(
                  child: SelectableText(
                    text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13.5,
                      color: AdminColors.ink,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copy',
              iconSize: 18,
              color: AdminColors.inkMuted,
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied $text'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    width: 420,
                  ),
                );
              },
            ),
          ],
        ),
      );
}
