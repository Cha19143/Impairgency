import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/guardian/obstacle_event.dart';
import '../../core/navigation/navigation_history.dart' show formatNavigationWhen;
import '../../core/speech/screen_reading.dart';
import '../../core/speech/speaker.dart';
import '../../data/obstacle_history_repository.dart';
import '../../vi/widgets/vi_button.dart';

/// Near obstacles the paired user was warned about, newest first.
///
/// The date range is the query. Type is filtered on the phone, so choosing
/// "Car" does not ask Firestore for a second index. Spoken once, when the
/// list is ready.
class ObstacleHistoryScreen extends StatefulWidget {
  const ObstacleHistoryScreen({
    super.key,
    required this.uid,
    required this.repository,
    required this.onBack,
    this.now,
    this.speaker = const SilentSpeaker(),
  });

  final String uid;
  final ObstacleHistoryRepository repository;
  final VoidCallback onBack;
  final DateTime Function()? now;
  final Speaker speaker;

  @override
  State<ObstacleHistoryScreen> createState() => _ObstacleHistoryScreenState();
}

class _ObstacleHistoryScreenState extends State<ObstacleHistoryScreen> {
  late final DateTime Function() _now = widget.now ?? DateTime.now;

  ObstacleDateFilter date = ObstacleDateFilter.last30Days;

  /// Empty means every type.
  String type = '';

  List<ObstacleSighting> _entries = const [];
  int _fetched = 0;
  int _limit = kObstacleHistoryPageSize;
  bool loading = true;
  bool loadingMore = false;
  String? error;
  StreamSubscription<ObstacleHistoryPage>? _sub;

  DateTime get now => _now();

  List<ObstacleSighting> get visible => [
        for (final entry in _entries)
          if (type.isEmpty || entry.type.toLowerCase() == type) entry,
      ];

  List<String> get types {
    final names = <String>{
      for (final entry in _entries) entry.type.toLowerCase(),
    }.toList()
      ..sort();
    return names;
  }

  bool get hasMore => _fetched >= _limit;

  String? get emptyMessage => obstacleHistoryEmptyMessage(
        loading: loading,
        hasError: error != null,
        fetched: _fetched,
        visible: visible.length,
        date: date,
        typeNarrowed: type.isNotEmpty,
      );

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void setDate(ObstacleDateFilter value) {
    if (date == value) return;
    setState(() {
      date = value;
      _limit = kObstacleHistoryPageSize;
      _entries = const [];
      _fetched = 0;
      loading = true;
      loadingMore = false;
      error = null;
    });
    _listen();
  }

  void setType(String value) {
    if (type == value) return;
    setState(() => type = value);
  }

  void loadMore() {
    if (!hasMore || loadingMore) return;
    setState(() {
      _limit += kObstacleHistoryPageSize;
      loadingMore = true;
    });
    _listen();
  }

  void _listen() {
    _sub?.cancel();
    _sub = widget.repository
        .watch(
          uid: widget.uid,
          since: obstacleRangeStart(date, now),
          limit: _limit,
        )
        .listen(
          (page) {
            if (!mounted) return;
            setState(() {
              _entries = page.entries;
              _fetched = page.fetched;
              loading = false;
              loadingMore = false;
              error = null;
              if (type.isNotEmpty &&
                  !_entries.any((e) => e.type.toLowerCase() == type)) {
                // The type chip is gone with this date range. Show all.
                type = '';
              }
            });
          },
          onError: (Object e) {
            debugPrint('obstacle history listen failed: $e');
            if (!mounted) return;
            setState(() {
              loading = false;
              loadingMore = false;
              error = 'Obstacle history could not be loaded.';
            });
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = visible;
    final empty = emptyMessage;
    final ready = !loading || entries.isNotEmpty;
    return AnnounceOnce(
      speaker: widget.speaker,
      ready: ready,
      lines: [
        'Obstacle history',
        'Back',
        'Type',
        'All',
        for (final name in types) obstacleTypeLabel(name),
        'Date',
        for (final option in ObstacleDateFilter.values) option.label,
        if (error != null && entries.isEmpty) error,
        empty,
        for (final entry in entries) _entryWords(entry),
        if (hasMore) 'Load more',
        if (hasMore) 'Older obstacles in this date range',
      ],
      child: Scaffold(
        backgroundColor: AppColors.navy,
        appBar: AppBar(
          title: const Text('Obstacle history'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: widget.onBack,
          ),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: _Filters(
                  types: types,
                  type: type,
                  date: date,
                  onType: setType,
                  onDate: setDate,
                ),
              ),
              Expanded(
                child: loading && entries.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.cyan),
                      )
                    : error != null && entries.isEmpty
                        ? _Message(error!)
                        : empty != null
                            ? _Message(empty)
                            : ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 8, 20, 12),
                                itemCount: entries.length,
                                itemBuilder: (context, index) =>
                                    _EntryTile(entry: entries[index]),
                              ),
              ),
              if (hasMore)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: ViButton(
                    label: loadingMore ? 'Loading…' : 'Load more',
                    detail: 'Older obstacles in this date range',
                    kind: ViButtonKind.secondary,
                    icon: Icons.expand_more,
                    onPressed: loadingMore ? null : loadMore,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _entryWords(ObstacleSighting entry) => [
      obstacleTypeLabel(entry.type),
      formatNavigationWhen(entry.at),
      obstacleLocationText(entry),
      obstacleDistanceText(entry),
    ].join(', ');

class _Filters extends StatelessWidget {
  const _Filters({
    required this.types,
    required this.type,
    required this.date,
    required this.onType,
    required this.onDate,
  });

  final List<String> types;
  final String type;
  final ObstacleDateFilter date;
  final ValueChanged<String> onType;
  final ValueChanged<ObstacleDateFilter> onDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FilterLabel('Type'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterChip(
              label: 'All',
              selected: type.isEmpty,
              onSelected: () => onType(''),
            ),
            for (final name in types)
              _FilterChip(
                label: obstacleTypeLabel(name),
                selected: type == name,
                onSelected: () => onType(name),
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
            for (final option in ObstacleDateFilter.values)
              _FilterChip(
                label: option.label,
                selected: date == option,
                onSelected: () => onDate(option),
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
  const _EntryTile({required this.entry});

  final ObstacleSighting entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.navyRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                obstacleTypeLabel(entry.type),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatNavigationWhen(entry.at),
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.3,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                obstacleLocationText(entry),
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.3,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                obstacleDistanceText(entry),
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.3,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
