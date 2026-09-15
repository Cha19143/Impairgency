import 'package:flutter/material.dart';

import '../../core/admin/user_filter.dart';
import '../../core/profile/impairment.dart';
import '../../data/admin_repository.dart';
import '../admin_theme.dart';
import '../admin_ui.dart';

/// §1.2 — visually impaired users, guardians, administrators, device links.
///
/// Takes its data rather than fetching it, so every cell can be asserted.
///
/// The testers asked for two things here: a way to see only the blind users,
/// the colour-blind users or the guardians, and a way to add, edit and remove
/// accounts. The filters work on the rows already loaded; the actions are
/// callbacks, so this screen never talks to Firebase itself.
class UsersScreen extends StatefulWidget {
  const UsersScreen({
    super.key,
    required this.users,
    this.invites = const [],
    this.onInvite,
    this.onWithdraw,
    this.onAdd,
    this.onEdit,
    this.onRemove,
  });

  final List<AdminUserRow> users;
  final List<UserInvite> invites;
  final void Function()? onInvite;
  final void Function(UserInvite)? onWithdraw;
  final void Function()? onAdd;
  final void Function(AdminUserRow)? onEdit;
  final void Function(AdminUserRow)? onRemove;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _search = TextEditingController();
  UserFilter _filter = UserFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clear() => setState(() {
        _filter = UserFilter.all;
        _search.clear();
      });

  @override
  Widget build(BuildContext context) {
    final users = widget.users;
    final counts = countUsers(users);
    final shown = filterUsers(users, filter: _filter, query: _search.text);
    final narrowed = _filter != UserFilter.all || _search.text.trim().isNotEmpty;
    final total = '${users.length} account${users.length == 1 ? '' : 's'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(narrowed ? 'Showing ${shown.length} of $total' : total,
                  style: const TextStyle(
                      fontSize: 13.5, color: AdminColors.inkMuted)),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (widget.onAdd != null)
                  FilledButton.icon(
                    onPressed: widget.onAdd,
                    icon: const Icon(Icons.person_add_alt_1, size: 17),
                    label: const Text('Add account'),
                    style: _primaryButton,
                  ),
                if (widget.onInvite != null)
                  FilledButton.icon(
                    onPressed: widget.onInvite,
                    icon: const Icon(Icons.person_add_alt, size: 17),
                    label: const Text('Invite someone'),
                    style: _primaryButton,
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.invites.isNotEmpty) ...[
          AdminPanel(
            title: 'Awaiting registration',
            footnote: 'They choose their own password when they register. '
                'Nobody here ever sees it.',
            child: Column(
              children: [
                for (final (i, invite) in widget.invites.indexed) ...[
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
                        if (widget.onWithdraw != null)
                          TextButton(
                            onPressed: () => widget.onWithdraw!(invite),
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
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Filters(
                      search: _search,
                      filter: _filter,
                      counts: counts,
                      onSearch: (_) => setState(() {}),
                      onFilter: (filter) => setState(() => _filter = filter),
                    ),
                    const SizedBox(height: 14),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          children: [
                            const Text('No accounts match.',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AdminColors.inkMuted)),
                            TextButton(
                              onPressed: _clear,
                              child: const Text('Clear filters'),
                            ),
                          ],
                        ),
                      )
                    else
                      LayoutBuilder(builder: (context, constraints) {
                        // Five columns need room. Below this they crush the
                        // name to an ellipsis and the device id to nothing, so
                        // each account becomes a small block instead.
                        final stacked = constraints.maxWidth < 720;
                        return Column(
                          children: [
                            if (!stacked) const _HeaderRow(),
                            for (final (i, user) in shown.indexed) ...[
                              if (i > 0 || !stacked) const AdminRowDivider(),
                              _UserRow(
                                user: user,
                                stacked: stacked,
                                onEdit: widget.onEdit,
                                onRemove: widget.onRemove,
                              ),
                            ],
                          ],
                        );
                      }),
                  ],
                ),
        ),
      ],
    );
  }
}

final ButtonStyle _primaryButton = FilledButton.styleFrom(
  backgroundColor: AdminColors.chrome,
  foregroundColor: Colors.white,
  minimumSize: const Size(0, 42),
  padding: const EdgeInsets.symmetric(horizontal: 18),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(10),
  ),
  textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
);

/// The search box and one chip per filter, each with how many it would show.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.search,
    required this.filter,
    required this.counts,
    required this.onSearch,
    required this.onFilter,
  });

  final TextEditingController search;
  final UserFilter filter;
  final Map<UserFilter, int> counts;
  final ValueChanged<String> onSearch;
  final ValueChanged<UserFilter> onFilter;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: TextField(
              controller: search,
              onChanged: onSearch,
              decoration: const InputDecoration(
                labelText: 'Search by name or email',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in UserFilter.values)
                // A filter nobody matches is still shown, with its zero: "no
                // colour-blind users" is an answer, and a missing chip is not.
                ChoiceChip(
                  label: Text(
                      '${kUserFilterLabels[option]} · ${counts[option] ?? 0}'),
                  selected: filter == option,
                  onSelected: (_) => onFilter(option),
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: filter == option ? Colors.white : AdminColors.ink,
                  ),
                  selectedColor: AdminColors.chrome,
                  backgroundColor: AdminColors.field,
                  side: const BorderSide(color: AdminColors.line),
                  showCheckmark: false,
                ),
            ],
          ),
        ],
      );
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
            Expanded(flex: 3, child: _H('Impairment')),
            Expanded(flex: 3, child: _H('Device')),
            Expanded(flex: 2, child: _H('Linked')),
            SizedBox(width: 48),
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

/// What the impairment cell says. Guardians and administrators have none to
/// record, and say nothing.
String? _impairmentText(AdminUserRow user) {
  if (!user.isVisuallyImpaired) return null;
  final type = user.knownImpairment;
  return type == null ? 'Not recorded' : kImpairmentChoices[type]!.label;
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    this.stacked = false,
    this.onEdit,
    this.onRemove,
  });

  final AdminUserRow user;
  final bool stacked;
  final void Function(AdminUserRow)? onEdit;
  final void Function(AdminUserRow)? onRemove;

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

  /// Edit and remove. Not offered on administrators: the roster is managed in
  /// the Firebase console, and the rules refuse the rest.
  Widget get _actions {
    if (user.isAdmin || (onEdit == null && onRemove == null)) {
      return const SizedBox(width: 48);
    }
    return SizedBox(
      width: 48,
      child: PopupMenuButton<String>(
        tooltip: 'Actions for ${user.name}',
        icon: const Icon(Icons.more_vert, size: 20, color: AdminColors.inkMuted),
        onSelected: (choice) {
          if (choice == 'edit') onEdit?.call(user);
          if (choice == 'remove') onRemove?.call(user);
        },
        itemBuilder: (_) => [
          if (onEdit != null)
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined, size: 18),
                title: Text('Edit'),
                dense: true,
              ),
            ),
          if (onRemove != null)
            const PopupMenuItem(
              value: 'remove',
              child: ListTile(
                leading: Icon(Icons.person_remove_outlined,
                    size: 18, color: AdminColors.bad),
                title: Text('Remove',
                    style: TextStyle(color: AdminColors.bad)),
                dense: true,
              ),
            ),
        ],
      ),
    );
  }

  /// One block per account, for a phone.
  Widget _stackedRow() {
    final impairment = _impairmentText(user);
    return Padding(
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
              _actions,
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
                if (impairment != null)
                  Text(
                    'Impairment: $impairment',
                    style: const TextStyle(
                        fontSize: 12.5, color: AdminColors.inkMuted),
                  ),
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
  }

  @override
  Widget build(BuildContext context) {
    if (stacked) return _stackedRow();
    final impairment = _impairmentText(user);

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
              impairment ?? '',
              style: TextStyle(
                fontSize: 12.5,
                color: user.knownImpairment == null
                    ? AdminColors.inkMuted
                    : AdminColors.ink,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
          _actions,
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
