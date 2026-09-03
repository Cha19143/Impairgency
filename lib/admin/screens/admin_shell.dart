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

/// Sidebar and content. Web only — the router never registers these on mobile.
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
    final narrow = MediaQuery.sizeOf(context).width < 900;

    return Scaffold(
      body: Row(
        children: [
          if (!narrow) _Sidebar(current: current, onSelect: onSelect, onSignOut: onSignOut),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 26,
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
                      if (narrow && onSignOut != null)
                        TextButton(onPressed: onSignOut, child: const Text('Sign out')),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, this.onSelect, this.onSignOut});

  final String current;
  final void Function(AdminSection)? onSelect;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 224,
      color: AdminColors.chrome,
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
        color: selected ? AdminColors.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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
