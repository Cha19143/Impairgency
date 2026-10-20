import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/navigation/navigation_history.dart';
import '../../core/speech/screen_reading.dart';
import '../../core/speech/speaker.dart';
import '../../data/navigation_history_repository.dart';
import '../../vi/widgets/vi_button.dart';

/// The paired user's trips, newest first, for the last 30 days at most.
///
/// Status is filtered on the phone. A trip the rules still call ongoing is
/// shown as cancelled once it is more than two hours old, and a query that
/// asked Firestore for `status == cancelled` would miss those. The date
/// range is the query, so the listener never reads an unbounded history.
class NavigationHistoryScreen extends StatelessWidget {
  const NavigationHistoryScreen({
    super.key,
    required this.uid,
    required this.repository,
    required this.onOpen,
    required this.onBack,
    this.now,
    this.speaker = const SilentSpeaker(),
  });

  final String uid;
  final NavigationHistoryRepository repository;
  final void Function(NavigationEntry entry) onOpen;
  final VoidCallback onBack;
  final DateTime Function()? now;
  final Speaker speaker;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      key: ValueKey(uid),
      create: (_) => NavigationHistoryController(
        uid: uid,
        repository: repository,
        now: now,
      ),
      child: _NavigationHistoryView(
        onOpen: onOpen,
        onBack: onBack,
        speaker: speaker,
      ),
    );
  }
}

/// Filter, page size, and the live query. One listener; a new date range or
/// a larger page replaces it.
class NavigationHistoryController extends ChangeNotifier {
  NavigationHistoryController({
    required this.uid,
    required this.repository,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _listen();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      notifyListeners();
    });
  }

  final String uid;
  final NavigationHistoryRepository repository;
  final DateTime Function() _now;

  NavigationStatusFilter status = NavigationStatusFilter.all;
  NavigationDateFilter date = NavigationDateFilter.last30Days;

  List<NavigationEntry> _entries = const [];
  int _fetched = 0;
  int _limit = kNavigationHistoryPageSize;
  bool loading = true;
  bool loadingMore = false;
  String? error;
  StreamSubscription<NavigationHistoryPage>? _sub;
  Timer? _clock;

  DateTime get now => _now();

  List<NavigationEntry> get visible => [
    for (final entry in _entries)
      if (entry.matchesFilter(status, now)) entry,
  ];

  bool get hasMore => _fetched >= _limit;

  String? get emptyMessage => navigationHistoryEmptyMessage(
    loading: loading,
    hasError: error != null,
    fetched: _fetched,
    visible: visible.length,
    date: date,
  );

  void setStatus(NavigationStatusFilter value) {
    if (status == value) return;
    status = value;
    notifyListeners();
  }

  void setDate(NavigationDateFilter value) {
    if (date == value) return;
    date = value;
    _limit = kNavigationHistoryPageSize;
    _entries = const [];
    _fetched = 0;
    loading = true;
    loadingMore = false;
    error = null;
    _listen();
    notifyListeners();
  }

  void loadMore() {
    if (!hasMore || loadingMore) return;
    _limit += kNavigationHistoryPageSize;
    loadingMore = true;
    _listen();
    notifyListeners();
  }

  void _listen() {
    _sub?.cancel();
    _sub = repository
        .watch(uid: uid, since: navigationRangeStart(date, now), limit: _limit)
        .listen(
          (page) {
            _entries = page.entries;
            _fetched = page.fetched;
            loading = false;
            loadingMore = false;
            error = null;
            notifyListeners();
          },
          onError: (Object e) {
            debugPrint('navigation history listen failed: $e');
            loading = false;
            loadingMore = false;
            error = 'Navigation history could not be loaded.';
            notifyListeners();
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _clock?.cancel();
    super.dispose();
  }
}

class _NavigationHistoryView extends StatelessWidget {
  const _NavigationHistoryView({
    required this.onOpen,
    required this.onBack,
    required this.speaker,
  });

  final void Function(NavigationEntry entry) onOpen;
  final VoidCallback onBack;
  final Speaker speaker;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NavigationHistoryController>();
    final entries = controller.visible;
    final empty = controller.emptyMessage;
    final ready = !controller.loading || entries.isNotEmpty;

    return AnnounceOnce(
      speaker: speaker,
      ready: ready,
      lines: [
        'Navigation history',
        'Back',
        'Status',
        for (final option in NavigationStatusFilter.values) option.label,
        'Date',
        for (final option in NavigationDateFilter.values) option.label,
        if (controller.error != null && entries.isEmpty) controller.error,
        empty,
        for (final entry in entries) _entryWords(entry, controller.now),
        if (controller.hasMore) 'Load more',
        if (controller.hasMore) 'Older trips in this date range',
      ],
      child: Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: const Text('Navigation history'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: onBack,
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: _Filters(controller: controller),
            ),
            Expanded(
              child: controller.loading && controller.visible.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.cyan),
                    )
                  : controller.error != null && entries.isEmpty
                  ? _Message(controller.error!)
                  : empty != null
                  ? _Message(empty)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return _EntryTile(
                          entry: entry,
                          now: controller.now,
                          onTap: () => onOpen(entry),
                        );
                      },
                    ),
            ),
            if (controller.hasMore)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: ViButton(
                  label: controller.loadingMore ? 'Loading…' : 'Load more',
                  detail: 'Older trips in this date range',
                  kind: ViButtonKind.secondary,
                  icon: Icons.expand_more,
                  onPressed: controller.loadingMore
                      ? null
                      : controller.loadMore,
                ),
              ),
          ],
        ),
      ),
    ),
    );
  }
}

String _entryWords(NavigationEntry entry, DateTime now) {
  final shown = entry.displayStatus(now);
  return [
    entry.destinationName,
    if (entry.destinationAddress.isNotEmpty) entry.destinationAddress,
    formatNavigationWhen(entry.startedAt),
    shown.label,
  ].join(', ');
}

class _Filters extends StatelessWidget {
  const _Filters({required this.controller});

  final NavigationHistoryController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FilterLabel('Status'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in NavigationStatusFilter.values)
              _FilterChip(
                label: option.label,
                selected: controller.status == option,
                onSelected: () => controller.setStatus(option),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const _FilterLabel('Date'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in NavigationDateFilter.values)
              _FilterChip(
                label: option.label,
                selected: controller.date == option,
                onSelected: () => controller.setDate(option),
              ),
          ],
        ),
      ],
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.cyan,
      backgroundColor: AppColors.navyRaised,
      labelStyle: TextStyle(
        color: selected ? AppColors.inkOnLight : AppColors.textPrimary,
        fontWeight: FontWeight.bold,
        fontSize: 15,
      ),
      side: BorderSide(color: selected ? AppColors.cyan : AppColors.hairline),
      onSelected: (_) => onSelected(),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            height: 1.4,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.now,
    required this.onTap,
  });

  final NavigationEntry entry;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final when = formatNavigationWhen(entry.startedAt);
    final shown = entry.displayStatus(now);
    final spoken = [
      entry.destinationName,
      if (entry.destinationAddress.isNotEmpty) entry.destinationAddress,
      when,
      shown.label,
    ].join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: spoken,
        child: Material(
          color: AppColors.navyRaised,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            entry.destinationName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        NavigationStatusChip(status: shown),
                      ],
                    ),
                    if (entry.destinationAddress.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        entry.destinationAddress,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      when,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
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
}

/// Status as a word and a colour. The word is the thing that carries the
/// meaning; the colour only agrees with it.
class NavigationStatusChip extends StatelessWidget {
  const NavigationStatusChip({super.key, required this.status});

  final NavigationStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      NavigationStatus.completed => AppColors.green,
      NavigationStatus.cancelled => AppColors.amber,
      NavigationStatus.ongoing => AppColors.cyan,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
