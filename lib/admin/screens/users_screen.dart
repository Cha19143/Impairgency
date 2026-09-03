import 'package:flutter/material.dart';

import '../../data/admin_repository.dart';
import '../admin_theme.dart';

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
                    backgroundColor: AdminColors.chrome),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (invites.isNotEmpty) ...[
          _Card(
            title: 'Awaiting registration',
            footnote: 'They choose their own password when they register. '
                'Nobody here ever sees it.',
            child: Column(
              children: [
                for (final invite in invites)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(invite.email,
                              style: const TextStyle(fontSize: 13.5)),
                        ),
                        _RolePill(invite.role),
                        const SizedBox(width: 12),
                        if (onWithdraw != null)
                          TextButton(
                            onPressed: () => onWithdraw!(invite),
                            child: const Text('Withdraw'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        _Card(
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
                      for (final user in users)
                        _UserRow(user: user, stacked: stacked),
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
        padding: EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
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
  Widget _stackedRow() => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFEDF0F6))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _name),
                const SizedBox(width: 10),
                _RolePill(user.role),
              ],
            ),
            const SizedBox(height: 8),
            // Labelled here, because there is no header row to read them
            // against once the columns are gone.
            Wrap(
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
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (stacked) return _stackedRow();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEDF0F6))),
      ),
      child: Row(
        children: [
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: foreground)),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.footnote});

  final String title;
  final Widget child;
  final String? footnote;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: AdminColors.card,
          border: Border.all(color: AdminColors.line),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.inkMuted,
                )),
            const SizedBox(height: 12),
            child,
            if (footnote != null) ...[
              const SizedBox(height: 12),
              Text(footnote!,
                  style: const TextStyle(
                      fontSize: 11.5, height: 1.35, color: AdminColors.inkMuted)),
            ],
          ],
        ),
      );
}
