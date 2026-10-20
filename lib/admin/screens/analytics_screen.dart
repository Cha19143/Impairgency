import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/speech/screen_reading.dart';
import '../../core/speech/speaker.dart';


const _timeKeys = ['createdAt', 'timestamp', 'at', 'startedAt', 'endedAt', 'time'];


const double _kCardHeight = 140;


String getPerformance(int contacts) {
  if (contacts >= 3) {
    return 'Excellent';
  } else if (contacts >= 2) {
    return 'Good';
  } else if (contacts >= 1) {
    return 'Passing';
  } else {
    return 'Needs Attention';
  }
}

Color performanceColor(String category) {
  switch (category) {
    case 'Excellent':
      return Colors.green;
    case 'Good':
      return Colors.blue;
    case 'Passing':
      return Colors.orange;
    default:
      return Colors.red;
  }
}

class _AnalyticsData {
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> sos;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> pairings;

  _AnalyticsData(this.users, this.sos, this.sessions, this.pairings);
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, this.speaker = const SilentSpeaker()});

  final Speaker speaker;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  static const Color primary = Color(0xFF3949AB);
  static const Color sosColor = Color(0xFFC62828);
  static const Color sessionColor = Color(0xFF00897B);
  static const Color outlierColor = Color(0xFFEF6C00); // NEW
  static const List<Color> pieColors = [
    Color(0xFF3949AB),
    Color(0xFFF9A825),
    Color(0xFF00897B),
    Color(0xFF8E24AA),
    Color(0xFF6D4C41),
  ];
  static const List<String> weekLabels = ['Week 1', 'Week 2', 'Week 3', 'Week 4'];

  late Future<_AnalyticsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    unawaited(_announceWhenLoaded());
  }

  Future<void> _announceWhenLoaded() async {
    final ok = await _future.then((_) => true, onError: (Object _) => false);
    if (!mounted) return;
    widget.speaker.speakLines(screenReadingLines([
      'ImpairGency Analytics',
      'Refresh',
      if (ok) ...const [
        'Trend Analytics: Navigation Sessions per Week',
        'Sessions Trend (Last 4 Weeks)',
        'Performance Records',
        'Section Comparison',
        'Key Performance Indicators',
        'Users by Impairment',
        'SOS Events per Day (Last 7 Days)',
        'Sessions per Day (Last 7 Days)',
        'EDA Insight',
        'Possible Outliers',
        'Performance Summary (Emergency Contact Readiness)',
        'User Records',
        'Recent SOS Events',
        'Recent Sessions',
      ],
    ]));
  }

  Future<_AnalyticsData> _load() async {
    final db = FirebaseFirestore.instance;
    final results = await Future.wait([
      db.collection('users').get(),
      db.collection('sos_events').get(),
      db.collection('session_summaries').get(),
      db.collection('pairings').get(),
    ]);

    List<Map<String, dynamic>> toList(QuerySnapshot<Map<String, dynamic>> s) =>
        s.docs.map((d) => {...d.data(), '_id': d.id}).toList();

    return _AnalyticsData(
      toList(results[0]),
      toList(results[1]),
      toList(results[2]),
      toList(results[3]),
    );
  }

  

  DateTime? _time(Map<String, dynamic> d) {
    for (final k in _timeKeys) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
    }
    return null;
  }


  List<int> _perDay(List<Map<String, dynamic>> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final counts = List<int>.filled(7, 0);
    for (final item in items) {
      final t = _time(item);
      if (t == null) continue;
      final day = DateTime(t.year, t.month, t.day);
      final diff = today.difference(day).inDays;
      if (diff >= 0 && diff < 7) counts[6 - diff]++;
    }
    return counts;
  }


  List<int> _perWeek(List<Map<String, dynamic>> items) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final counts = List<int>.filled(4, 0);
    for (final item in items) {
      final t = _time(item);
      if (t == null) continue;
      final day = DateTime(t.year, t.month, t.day);
      final diff = today.difference(day).inDays;
      if (diff >= 0 && diff < 28) counts[3 - (diff ~/ 7)]++;
    }
    return counts;
  }

  String _dayLabel(int index) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final day = DateTime.now().subtract(Duration(days: 6 - index));
    return names[day.weekday - 1];
  }

  String _fmt(DateTime? t) {
    if (t == null) return 'No date';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}  ${two(t.hour)}:${two(t.minute)}';
  }

  List<Map<String, dynamic>> _recent(List<Map<String, dynamic>> items,
      {int limit = 10}) {
    final sorted = [...items];
    sorted.sort((a, b) {
      final ta = _time(a);
      final tb = _time(b);
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return sorted.take(limit).toList();
  }

  // ---------------- NEW: EDA helpers ----------------

  double _mean(List<int> v) =>
      v.isEmpty ? 0 : v.fold<int>(0, (a, b) => a + b) / v.length;

  double _std(List<int> v) {
    if (v.isEmpty) return 0;
    final m = _mean(v);
    double s = 0;
    for (final x in v) {
      s += (x - m) * (x - m);
    }
    return sqrt(s / v.length);
  }

  Set<int> _outlierIdx(List<int> v) {
    final sd = _std(v);
    if (sd == 0) return {};
    final m = _mean(v);
    return {
      for (int i = 0; i < v.length; i++)
        if ((v[i] - m).abs() > 1.5 * sd) i,
    };
  }

  int _contactsOf(Map<String, dynamic> u) {
    final c = u['emergencyContacts'];
    return c is List ? c.length : 0;
  }

  String _userName(Map<String, dynamic> u) {
    for (final k in ['name', 'fullName', 'displayName', 'email']) {
      final v = u[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return u['_id'].toString();
  }

 
  Map<String, int> _performanceSummary(List<Map<String, dynamic>> users) {
    final summary = <String, int>{
      'Excellent': 0,
      'Good': 0,
      'Passing': 0,
      'Needs Attention': 0,
    };
    for (final u in users) {
      final cat = getPerformance(_contactsOf(u));
      summary[cat] = summary[cat]! + 1;
    }
    return summary;
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ImpairGency Analytics'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => setState(() => _future = _load()),
          ),
        ],
      ),
      body: FutureBuilder<_AnalyticsData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Hindi ma-load ang data.\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _buildDashboard(snap.data!);
        },
      ),
    );
  }

  Widget _buildDashboard(_AnalyticsData data) {
    // ---------- KPI computations ----------
    final totalUsers = data.users.length;
    final totalPairings = data.pairings.length;
    final totalSos = data.sos.length;
    final totalSessions = data.sessions.length;

    final sosPerDay = _perDay(data.sos);
    final sessionsPerDay = _perDay(data.sessions);
    final sos7 = sosPerDay.fold<int>(0, (a, b) => a + b);
    final sessions7 = sessionsPerDay.fold<int>(0, (a, b) => a + b);

    final usersWithDevice =
        data.users.where((u) => u['hasDevice'] == true).length;

    int totalContacts = 0;
    for (final u in data.users) {
      final c = u['emergencyContacts'];
      if (c is List) totalContacts += c.length;
    }
    final avgContacts = totalUsers == 0 ? 0.0 : totalContacts / totalUsers;

    // Users by impairment
    final Map<String, int> impairment = {};
    for (final u in data.users) {
      final key = (u['impairment'] ?? 'unspecified').toString();
      impairment[key] = (impairment[key] ?? 0) + 1;
    }

    // ---------- TREND computations (sessions per week) ----------
    final weekly = _perWeek(data.sessions);
    final startValue = weekly.first;
    final currentValue = weekly.last;

    // Percentage change (walang division by zero)
    final double? pctChange = startValue == 0
        ? (currentValue == 0 ? 0.0 : null)
        : ((currentValue - startValue) / startValue) * 100;
    final String pctText = pctChange == null
        ? 'N/A'
        : '${pctChange >= 0 ? '+' : ''}${pctChange.toStringAsFixed(1)}%';

    final String trendText = currentValue > startValue
        ? 'Increasing'
        : (currentValue < startValue ? 'Decreasing' : 'Stable');
    final Color trendColor = currentValue > startValue
        ? Colors.green
        : (currentValue < startValue ? sosColor : Colors.grey);
    final IconData trendIcon = currentValue > startValue
        ? Icons.trending_up
        : (currentValue < startValue
            ? Icons.trending_down
            : Icons.trending_flat);

    // ---------- GROUP COMPARISON ----------
    // Section A = users with device, Section B = users without device
    double sectionA = usersWithDevice.toDouble();
    double sectionB = (totalUsers - usersWithDevice).toDouble();

    double sectionDifference = (sectionA - sectionB).abs();

    String higherSection;
    if (sectionA > sectionB) {
      higherSection = 'Section A';
    } else if (sectionB > sectionA) {
      higherSection = 'Section B';
    } else {
      higherSection = 'Equal';
    }

    // ---------- NEW: EDA computations ----------
    final sosOutliers = _outlierIdx(sosPerDay);
    final sessionOutliers = _outlierIdx(sessionsPerDay);
    final sosMean = _mean(sosPerDay);
    final sessionMean = _mean(sessionsPerDay);
    final busiestSosDay = sosPerDay.indexOf(sosPerDay.reduce(max));
    final summary = _performanceSummary(data.users);
    final needsAttention = summary['Needs Attention']!;

    final insightText = StringBuffer()
      ..write('On average there were ${sosMean.toStringAsFixed(1)} SOS events '
          'and ${sessionMean.toStringAsFixed(1)} navigation sessions per day '
          'over the last 7 days. ');
    if (sos7 > 0) {
      insightText.write('The busiest SOS day was ${_dayLabel(busiestSosDay)} '
          '(${sosPerDay[busiestSosDay]} events). ');
    } else {
      insightText.write('No SOS events were recorded in the last 7 days. ');
    }
    insightText.write(needsAttention > 0
        ? '$needsAttention user(s) have no emergency contact and need attention.'
        : (totalUsers == 0
            ? 'There are no users yet.'
            : 'Every user has at least one emergency contact.'));

    // Users na may pinakakaunting contacts ang una (Needs Attention first)
    final sortedUsers = [...data.users]
      ..sort((a, b) => _contactsOf(a).compareTo(_contactsOf(b)));

    // Para hindi sobrang lapad ang laman sa malapad na screen
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sidePad = screenWidth > 932 ? (screenWidth - 900) / 2 : 16.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: sidePad, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // =====================================================
          //                TREND ANALYTICS
          // =====================================================
          _sectionTitle('Trend Analytics: Navigation Sessions per Week'),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: _kCardHeight,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            children: [
              _kpiCard('Starting Value\n(Week 1)', '$startValue',
                  Icons.flag_outlined, primary),
              _kpiCard('Current Value\n(Week 4)', '$currentValue',
                  Icons.my_location, sessionColor),
              _kpiCard('Percentage\nChange', pctText, Icons.percent,
                  Colors.orange),
              _kpiCard('Trend', trendText, trendIcon, trendColor),
            ],
          ),

          // ---------- Line chart ----------
          const SizedBox(height: 24),
          _sectionTitle('Sessions Trend (Last 4 Weeks)'),
          SizedBox(
            height: 260,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: 3,
                  minY: 0,
                  maxY: _maxY(weekly),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(
                        4,
                        (i) => FlSpot(i.toDouble(), weekly[i].toDouble()),
                      ),
                      isCurved: true,
                      color: trendColor,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: trendColor.withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                  titlesData: _weekTitles(weekly),
                ),
              ),
            ),
          ),

          // ---------- Performance records ----------
          const SizedBox(height: 24),
          _sectionTitle('Performance Records'),
          ...List.generate(4, (i) {
            final change = i == 0 ? null : weekly[i] - weekly[i - 1];
            final changeText = change == null
                ? 'Starting week'
                : '${change > 0 ? '+$change' : '$change'} vs previous week';
            final changeColor = change == null || change == 0
                ? Colors.grey
                : (change > 0 ? Colors.green : sosColor);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.calendar_view_week,
                    color: sessionColor),
                title: Text(weekLabels[i],
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Sessions: ${weekly[i]}'),
                trailing: Text(
                  changeText,
                  style: TextStyle(
                      color: changeColor, fontWeight: FontWeight.w600),
                ),
              ),
            );
          }),

          // ---------- Group comparison ----------
          const SizedBox(height: 24),
          _sectionTitle('Section Comparison'),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: _kCardHeight,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            children: [
              _kpiCard('Section A\n(With Device)',
                  sectionA.toStringAsFixed(0), Icons.watch, primary),
              _kpiCard('Section B\n(Without Device)',
                  sectionB.toStringAsFixed(0), Icons.phone_android,
                  Colors.teal),
              _kpiCard('Difference', sectionDifference.toStringAsFixed(2),
                  Icons.compare_arrows, Colors.orange),
              _kpiCard('Higher Value', higherSection, Icons.emoji_events,
                  Colors.purple),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Difference: ${sectionDifference.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.grey),
          ),

          // =====================================================
          //            KPI / CHARTS / RECORDS (MIDTERM)
          // =====================================================
          const SizedBox(height: 40),
          _sectionTitle('Key Performance Indicators'),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: _kCardHeight,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            children: [
              _kpiCard('Total Users', '$totalUsers', Icons.people, primary),
              _kpiCard('Paired Guardians', '$totalPairings',
                  Icons.family_restroom, Colors.teal),
              _kpiCard('Total SOS Events', '$totalSos', Icons.sos, sosColor),
              _kpiCard('SOS (Last 7 Days)', '$sos7', Icons.warning_amber,
                  Colors.orange),
              _kpiCard('Total Sessions', '$totalSessions', Icons.history,
                  sessionColor),
              _kpiCard('Sessions\n(Last 7 Days)', '$sessions7',
                  Icons.trending_up, sessionColor),
              _kpiCard('Users with Device', '$usersWithDevice',
                  Icons.watch, Colors.purple),
              _kpiCard('Avg. Emergency\nContacts',
                  avgContacts.toStringAsFixed(1), Icons.contact_phone,
                  Colors.indigo),
            ],
          ),

          // ================= PIE =================
          const SizedBox(height: 30),
          _sectionTitle('Users by Impairment'),
          if (impairment.isEmpty)
            _emptyNote('Wala pang user data.')
          else ...[
            SizedBox(
              height: 240,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 40,
                  sections: [
                    for (int i = 0; i < impairment.length; i++)
                      PieChartSectionData(
                        value: impairment.values.elementAt(i).toDouble(),
                        color: pieColors[i % pieColors.length],
                        radius: 80,
                        title:
                            '${(impairment.values.elementAt(i) / totalUsers * 100).toStringAsFixed(0)}%',
                        titleStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 6,
              children: [
                for (int i = 0; i < impairment.length; i++)
                  _legend(
                    '${impairment.keys.elementAt(i)} (${impairment.values.elementAt(i)})',
                    pieColors[i % pieColors.length],
                  ),
              ],
            ),
          ],

          // ================= BAR =================
          const SizedBox(height: 40),
          _sectionTitle('SOS Events per Day (Last 7 Days)'),
          SizedBox(
            height: 260,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: _maxY(sosPerDay),
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                barGroups: List.generate(7, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: sosPerDay[i].toDouble(),
                        width: 18,
                        // NEW: outlier days are highlighted in orange
                        color: sosOutliers.contains(i) ? outlierColor : sosColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  );
                }),
                titlesData: _titles(sosPerDay),
              ),
            ),
          ),
          if (sosOutliers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _legend('Possible outlier day', outlierColor),
            ),

          // ================= LINE =================
          const SizedBox(height: 40),
          _sectionTitle('Sessions per Day (Last 7 Days)'),
          SizedBox(
            height: 260,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: 6,
                  minY: 0,
                  maxY: _maxY(sessionsPerDay),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(
                        7,
                        (i) => FlSpot(i.toDouble(),
                            sessionsPerDay[i].toDouble()),
                      ),
                      isCurved: true,
                      color: sessionColor,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: sessionColor.withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                  titlesData: _titles(sessionsPerDay),
                ),
              ),
            ),
          ),

          // =====================================================
          //                NEW: EDA INSIGHT
          // =====================================================
          const SizedBox(height: 40),
          _sectionTitle('EDA Insight'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(insightText.toString()),
            ),
          ),

          // =====================================================
          //                NEW: POSSIBLE OUTLIERS
          // =====================================================
          const SizedBox(height: 24),
          _sectionTitle('Possible Outliers'),
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: (sosOutliers.isEmpty && sessionOutliers.isEmpty)
                  ? const Text('No unusual days detected in the last 7 days.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final i in sosOutliers)
                          Text(
                            '⚠ ${_dayLabel(i)}: ${sosPerDay[i]} SOS events '
                            '(${sosPerDay[i] > sosMean ? 'unusually high' : 'unusually low'}, '
                            'avg ${sosMean.toStringAsFixed(1)}/day)',
                          ),
                        for (final i in sessionOutliers)
                          Text(
                            '⚠ ${_dayLabel(i)}: ${sessionsPerDay[i]} sessions '
                            '(${sessionsPerDay[i] > sessionMean ? 'unusually high' : 'unusually low'}, '
                            'avg ${sessionMean.toStringAsFixed(1)}/day)',
                          ),
                      ],
                    ),
            ),
          ),

          // =====================================================
          //        NEW: PERFORMANCE / PREPAREDNESS SUMMARY
          // =====================================================
          const SizedBox(height: 24),
          _sectionTitle('Performance Summary (Emergency Contact Readiness)'),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 110,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            children: [
              for (final e in summary.entries)
                Card(
                  color: performanceColor(e.key).withValues(alpha: 0.12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${e.value}',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: performanceColor(e.key),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(e.key, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Excellent: 3+ contacts  •  Good: 2  •  Passing: 1  •  Needs Attention: 0',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),

          // =====================================================
          //                NEW: USER RECORDS
          // =====================================================
          const SizedBox(height: 24),
          _sectionTitle('User Records'),
          if (sortedUsers.isEmpty)
            _emptyNote('Wala pang user data.')
          else
            ...sortedUsers.take(10).map((u) {
              final contacts = _contactsOf(u);
              final perf = getPerformance(contacts);
              return _recordTile(
                icon: Icons.person,
                color: performanceColor(perf),
                title: _userName(u),
                line1: 'Emergency contacts: $contacts',
                line2: 'Performance: $perf',
              );
            }),

          // ================= RECORDS =================
          const SizedBox(height: 30),
          _sectionTitle('Recent SOS Events'),
          if (data.sos.isEmpty)
            _emptyNote('Wala pang SOS event.')
          else
            ..._recent(data.sos).map((e) => _recordTile(
                  icon: Icons.sos,
                  color: sosColor,
                  title: 'SOS Event',
                  line1: _fmt(_time(e)),
                  line2: 'Status: ${e['status'] ?? 'n/a'}',
                )),

          const SizedBox(height: 24),
          _sectionTitle('Recent Sessions'),
          if (data.sessions.isEmpty)
            _emptyNote('Wala pang session summary.')
          else
            ..._recent(data.sessions).map((s) => _recordTile(
                  icon: Icons.history,
                  color: sessionColor,
                  title: 'Session',
                  line1: _fmt(_time(s)),
                  line2: 'ID: ${s['_id']}',
                )),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ---------------- Reusable widgets ----------------

  double _maxY(List<int> values) {
    final m = values.fold<int>(0, (a, b) => a > b ? a : b);
    return (m < 4 ? 4 : m + 1).toDouble();
  }

  FlTitlesData _titles(List<int> values) {
    final maxY = _maxY(values);
    final interval = (maxY / 4).ceilToDouble();
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 1,
          reservedSize: 30,
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i < 0 || i > 6 || value != i.toDouble()) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_dayLabel(i), style: const TextStyle(fontSize: 11)),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          interval: interval,
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

 
  FlTitlesData _weekTitles(List<int> values) {
    final maxY = _maxY(values);
    final interval = (maxY / 4).ceilToDouble();
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: 1,
          reservedSize: 30,
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i < 0 || i > 3 || value != i.toDouble()) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(weekLabels[i], style: const TextStyle(fontSize: 11)),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          interval: interval,
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      );

  Widget _emptyNote(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text, style: const TextStyle(color: Colors.grey)),
      );

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label),
        ],
      );

  Widget _recordTile({
    required IconData icon,
    required Color color,
    required String title,
    required String line1,
    required String line2,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$line1\n$line2'),
        isThreeLine: true,
      ),
    );
  }
}