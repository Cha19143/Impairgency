import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../admin_theme.dart';

class AdminSection {
  const AdminSection(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}

const adminSections = <AdminSection>[
  AdminSection('Overview', Icons.insights_outlined, Routes.adminOverview),
  AdminSection('Users', Icons.people_outline, Routes.adminUsers),
  // No "Sessions" entry until there is a screen behind it. A nav item that
  // goes nowhere is the same defect as the audits button that audited nothing.
  AdminSection(
      'System health', Icons.monitor_heart_outlined, Routes.adminHealth),
  AdminSection('Accessibility', Icons.accessibility_new_outlined,
      Routes.adminAccessibility),
];

/// Below this the sidebar becomes a drawer.
const double kAdminSidebarBreakpoint = 900;

/// Content stops growing here. On a very wide monitor a table row stretched to
/// the full window puts the number a long way from the label it belongs to.
const double kAdminMaxContentWidth = 1180;

/// Sidebar and content, or a drawer and content.
///
/// The narrow layout used to drop the sidebar and put nothing in its place,
/// which left every section but the current one unreachable. A responsive
/// layout that hides navigation is not responsive, it is broken.
class AdminShell extends StatelessWidget {
  const AdminShell({
    super.key,
    required this.current,
    required this.title,
    required this.child,
    this.onSelect,
    this.onSignOut,
    this.subtitle,
    this.account,
  });

  final String current;
  final String title;
  final String? subtitle;
  final Widget child;
  final void Function(AdminSection)? onSelect;
  final VoidCallback? onSignOut;

  /// Who is signed in, shown above the sign-out button.
  ///
  /// This dashboard has a whole screen for the case where someone is signed in
  /// as an account they did not mean to be. Naming the account in the sidebar
  /// is how that gets noticed before it becomes confusing.
  final String? account;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < kAdminSidebarBreakpoint;
    final tight = width < 520;

    return Scaffold(
      drawer: narrow
          ? Drawer(
              backgroundColor: AdminColors.chrome,
              child: SafeArea(
                child: AdminNav(
                  current: current,
                  account: account,
                  onSignOut: onSignOut,
                  onSelect: (section) {
                    // Close the drawer first: leaving it open over the page it
                    // just navigated to hides the thing the user asked for.
                    Navigator.of(context).pop();
                    onSelect?.call(section);
                  },
                ),
              ),
            )
          : null,
      appBar: narrow
          ? AppBar(
              backgroundColor: AdminColors.chrome,
              foregroundColor: Colors.white,
              titleSpacing: 4,
              title: const AdminBrandMark(compact: true),
            )
          : null,
      body: Row(
        children: [
          if (!narrow)
            SizedBox(
              width: 236,
              child: ColoredBox(
                color: AdminColors.chrome,
                child: AdminNav(
                  current: current,
                  account: account,
                  onSelect: onSelect,
                  onSignOut: onSignOut,
                ),
              ),
            ),
          Expanded(
            child: SafeArea(
              top: !narrow,
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: kAdminMaxContentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The page's own heading, on a hairline that separates it
                      // from the cards below without a second background.
                      Container(
                        padding: EdgeInsets.fromLTRB(
                          tight ? 16 : 30,
                          narrow ? 18 : 28,
                          tight ? 16 : 30,
                          18,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AdminColors.line),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: tight ? 22 : 27,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.4,
                                  color: AdminColors.ink,
                                ),
                              ),
                            ),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  subtitle!,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: AdminColors.inkMuted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                              tight ? 16 : 30, 20, tight ? 16 : 30, 36),
                          child: child,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The product, on the dashboard's chrome.
///
/// The same lockup the sign-in page opens with, so the dashboard behind the
/// door looks like the door.
class AdminBrandMark extends StatelessWidget {
  const AdminBrandMark({super.key, this.compact = false});

  /// Drops the "admin" line, for the narrow layout's app bar.
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AdminColors.accent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.shield_outlined,
                size: 18, color: AdminColors.inkOnAccent),
          ),
          const SizedBox(width: 11),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ImpairGency',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                if (!compact)
                  const Text(
                    'ADMIN',
                    style: TextStyle(
                      color: AdminColors.chromeText,
                      fontSize: 9.5,
                      height: 1.4,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
}

/// The nav itself, shared by the sidebar and the drawer.
class AdminNav extends StatelessWidget {
  const AdminNav({
    super.key,
    required this.current,
    this.onSelect,
    this.onSignOut,
    this.account,
  });

  final String current;
  final void Function(AdminSection)? onSelect;
  final VoidCallback? onSignOut;
  final String? account;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 0, 10, 22),
            child: AdminBrandMark(),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Text(
              'DASHBOARD',
              style: TextStyle(
                color: AdminColors.chromeText,
                fontSize: 9.5,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final section in adminSections)
            _NavItem(
              section: section,
              selected: section.route == current,
              onTap: onSelect == null ? null : () => onSelect!(section),
            ),
          const Spacer(),
          if (account != null || onSignOut != null) _Account(
            account: account,
            onSignOut: onSignOut,
          ),
        ],
      ),
    );
  }
}

/// Who is signed in, and the way out.
class _Account extends StatelessWidget {
  const _Account({this.account, this.onSignOut});

  final String? account;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final initial =
        (account?.trim().isNotEmpty ?? false) ? account!.trim()[0] : '?';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 6, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (account != null)
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AdminColors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    initial.toUpperCase(),
                    style: const TextStyle(
                      color: AdminColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    account!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          if (onSignOut != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout, size: 16,
                    color: AdminColors.chromeText),
                label: const Text('Sign out',
                    style: TextStyle(
                        color: AdminColors.chromeText, fontSize: 13)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.section, required this.selected, this.onTap});

  final AdminSection section;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      // A button to a screen reader, and the open section marked as selected.
      // A bare InkWell is announced as its text alone, with nothing to say it
      // can be pressed or which one is current.
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected
              ? AdminColors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            // No ripple. A sidebar is navigation, not a control being
            // operated, and an ink splash that plays out after the pane has
            // already changed reads as lag rather than feedback.
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: AdminColors.accent.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 11, 10, 11),
              child: Row(
                children: [
                  // The marker on the left edge, so which section you are on
                  // survives being read at a glance or in greyscale.
                  Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: selected
                          ? AdminColors.accent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Icon(section.icon,
                      size: 18,
                      color: selected
                          ? AdminColors.accent
                          : AdminColors.chromeText),
                  const SizedBox(width: 10),
                  // Expanded, not bare: "Accessibility" is wider than the
                  // sidebar's inner width and overflowed by 42 px.
                  Expanded(
                    child: Text(
                      section.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? AdminColors.accent
                            : AdminColors.chromeText,
                      ),
                    ),
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
