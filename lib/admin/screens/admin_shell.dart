import 'package:flutter/material.dart';

import '../admin_theme.dart';

class AdminSection {
  const AdminSection(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}

const adminSections = <AdminSection>[
  AdminSection('Overview', Icons.insights_outlined, '/admin/overview'),
  AdminSection('Users', Icons.people_outline, '/admin/users'),
  // No "Sessions" entry until there is a screen behind it. A nav item that
  // goes nowhere is the same defect as the audits button that audited nothing.
  AdminSection('System health', Icons.monitor_heart_outlined, '/admin/health'),
  AdminSection('Accessibility', Icons.accessibility_new_outlined,
      '/admin/accessibility'),
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
  });

  final String current;
  final String title;
  final String? subtitle;
  final Widget child;
  final void Function(AdminSection)? onSelect;
  final VoidCallback? onSignOut;

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
              title: const Text('ImpairGency',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            )
          : null,
      body: Row(
        children: [
          if (!narrow)
            SizedBox(
              width: 224,
              child: ColoredBox(
                color: AdminColors.chrome,
                child: AdminNav(
                  current: current,
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
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            tight ? 16 : 28, narrow ? 18 : 26, tight ? 16 : 28, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: tight ? 22 : 26,
                                  fontWeight: FontWeight.bold,
                                  color: AdminColors.ink,
                                ),
                              ),
                            ),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  subtitle!,
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      color: AdminColors.inkMuted),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                              tight ? 16 : 28, 0, tight ? 16 : 28, 32),
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

/// The nav itself, shared by the sidebar and the drawer.
class AdminNav extends StatelessWidget {
  const AdminNav({
    super.key,
    required this.current,
    this.onSelect,
    this.onSignOut,
  });

  final String current;
  final void Function(AdminSection)? onSelect;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 0, 10, 20),
            child: Text(
              'ImpairGency',
              style: TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          for (final section in adminSections)
            _NavItem(
              section: section,
              selected: section.route == current,
              onTap: onSelect == null ? null : () => onSelect!(section),
            ),
          const Spacer(),
          if (onSignOut != null)
            TextButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout, size: 17,
                  color: AdminColors.chromeText),
              label: const Text('Sign out',
                  style: TextStyle(color: AdminColors.chromeText)),
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
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected
            ? AdminColors.accent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          // No ripple. A sidebar is navigation, not a control being operated,
          // and an ink splash that plays out after the pane has already changed
          // reads as lag rather than feedback.
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: AdminColors.accent.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              children: [
                Icon(section.icon,
                    size: 17,
                    color: selected ? AdminColors.accent : AdminColors.chromeText),
                const SizedBox(width: 10),
                // Expanded, not bare: "Accessibility" is wider than the
                // sidebar's inner width and overflowed by 42 px.
                Expanded(
                  child: Text(
                    section.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color:
                          selected ? AdminColors.accent : AdminColors.chromeText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
