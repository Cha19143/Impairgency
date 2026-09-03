import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import '../admin_theme.dart';
import '../admin_ui.dart';

/// §1.2 — visually impaired users, guardians, administrators, device links.
///
/// Takes its data rather than fetching it, so every cell can be asserted.
class UsersScreen extends StatelessWidget {
  const UsersScreen({
    super.key,
    required this.users,
    this.invites = const [],
    this.onInvite,
    this.onWithdraw,
  });

  final List<AdminUserRow> users;
  final List<UserInvite> invites;
  final void Function()? onInvite;
  final void Function(UserInvite)? onWithdraw;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${users.length} account${users.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 13.5, color: AdminColors.inkMuted)),
            ),
            if (onInvite != null)
              FilledButton.icon(
                onPressed: onInvite,
                icon: const Icon(Icons.person_add_alt, size: 17),
                label: const Text('Invite someone'),
                style: FilledButton.styleFrom(
                  backgroundColor: AdminColors.chrome,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (invites.isNotEmpty) ...[
          AdminPanel(
            title: 'Awaiting registration',
            footnote: 'They choose their own password when they register. '
                'Nobody here ever sees it.',
            child: Column(
              children: [
                for (final (i, invite) in invites.indexed) ...[
                  if (i > 0) const AdminRowDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const _Avatar(pending: true),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(invite.email,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500)),
                        ),
                        _RolePill(invite.role),
                        const SizedBox(width: 8),
                        if (onWithdraw != null)
                          TextButton(
                            onPressed: () => onWithdraw!(invite),
                            style: TextButton.styleFrom(
                                foregroundColor: AdminColors.bad),
                            child: const Text('Withdraw'),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        AdminPanel(
          title: 'Accounts',
          child: users.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('No accounts yet.',
                      style: TextStyle(
                          fontSize: 13, color: AdminColors.inkMuted)),
                )
              : LayoutBuilder(builder: (context, constraints) {
                  // Four columns need room. Below this they crush the name to
                  // an ellipsis and the device id to nothing, so each account
                  // becomes a small block instead.
                  final stacked = constraints.maxWidth < 560;
                  return Column(
                    children: [
                      if (!stacked) const _HeaderRow(),
                      for (final (i, user) in users.indexed) ...[
                        if (i > 0 || !stacked) const AdminRowDivider(),
                        _UserRow(user: user, stacked: stacked),
                      ],
                    ],
                  );
                }),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            SizedBox(width: 46),
            Expanded(flex: 4, child: _H('Name')),
            Expanded(flex: 2, child: _H('Role')),
            Expanded(flex: 3, child: _H('Device')),
            Expanded(flex: 2, child: _H('Linked')),
          ],
        ),
      );
}

class _H extends StatelessWidget {
  const _H(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
          color: AdminColors.inkMuted,
        ),
      );
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user, this.stacked = false});

  final AdminUserRow user;
  final bool stacked;

  Widget get _name => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.name,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis),
          if (user.email != null && user.email != user.name)
            Text(user.email!,
                style: const TextStyle(
                    fontSize: 12, color: AdminColors.inkMuted),
                overflow: TextOverflow.ellipsis),
        ],
      );

  /// One block per account, for a phone.
  Widget _stackedRow() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(name: user.name),
                const SizedBox(width: 12),
                Expanded(child: _name),
                const SizedBox(width: 10),
                _RolePill(user.role),
              ],
            ),
            const SizedBox(height: 10),
            // Labelled here, because there is no header row to read them
            // against once the columns are gone.
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  'Device: ${user.deviceId ?? 'None'}',
                  style: const TextStyle(
                      fontSize: 12.5, color: AdminColors.inkMuted),
                ),
                Text(
                  user.linkedTo.isEmpty
                      ? 'Linked to nobody'
                      : 'Linked to ${user.linkedTo.length}',
                  style: const TextStyle(
                      fontSize: 12.5, color: AdminColors.inkMuted),
                ),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (stacked) return _stackedRow();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          _Avatar(name: user.name),
          const SizedBox(width: 12),
          Expanded(flex: 4, child: _name),
          Expanded(flex: 2, child: Align(
            alignment: Alignment.centerLeft,
            child: _RolePill(user.role),
          )),
          Expanded(
            flex: 3,
            child: Text(
              // §1.2 asks admins to manage device connections. It does not ask
              // every account to have one, and most will not.
              user.deviceId ?? 'None',
              style: TextStyle(
                fontSize: 12.5,
                fontFamily: user.deviceId == null ? null : 'monospace',
                color: user.deviceId == null
                    ? AdminColors.inkMuted
                    : AdminColors.ink,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              user.linkedTo.isEmpty ? '—' : '${user.linkedTo.length}',
              style: const TextStyle(
                  fontSize: 12.5, color: AdminColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The initial, so a row of accounts scans as people rather than as text.
///
/// Decorative only: the name is right beside it, and the semantics come from
/// the row. An invitation has no name yet, so it gets an envelope.
class _Avatar extends StatelessWidget {
  const _Avatar({this.name, this.pending = false});

  final String? name;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final initial = (name?.trim().isNotEmpty ?? false)
        ? name!.trim()[0].toUpperCase()
        : '?';

    return ExcludeSemantics(
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AdminTone.neutral.tint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: pending
            ? const Icon(Icons.mail_outline,
                size: 16, color: AdminColors.inkMuted)
            : Text(
                initial,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.chrome,
                ),
              ),
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill(this.role);

  final String role;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (role) {
      'admin' => ('Admin', const Color(0xFFF3E4CE), AdminColors.warn),
      'guardian' => ('Guardian', const Color(0xFFE2E8F8), const Color(0xFF1E3A8A)),
      _ => ('VI user', const Color(0xFFD2ECEF), const Color(0xFF0A5A63)),
    };
    return AdminPill(label, background: background, foreground: foreground);
  }
}
