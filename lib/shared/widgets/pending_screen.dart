import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';

/// A screen that has a route and a place in the plan but no implementation yet.
///
/// Deliberately explicit rather than a blank page: a scaffold that lies about
/// what is finished is how the previous project ended up with an admin
/// dashboard full of hardcoded numbers.
class PendingScreen extends StatelessWidget {
  const PendingScreen({
    super.key,
    required this.title,
    required this.phase,
    required this.requirement,
  });

  final String title;

  /// Which phase of `docs/BUILD_PLAN.md` builds this.
  final String phase;

  /// The requirements-document section this screen answers.
  final String requirement;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ImpairGency'),
        actions: [
          // Scaffolding on scaffolding: both this screen and the debug screen
          // go away once Phase 4 builds the real ones.
          if (kDebugMode)
            IconButton(
              tooltip: 'Location & alerts debug',
              icon: const Icon(Icons.bug_report_outlined),
              onPressed: () => GoRouter.of(context).go(Routes.debug),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Not built yet — $phase.',
                style: const TextStyle(
                    fontSize: 16, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                'Requirements $requirement',
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
