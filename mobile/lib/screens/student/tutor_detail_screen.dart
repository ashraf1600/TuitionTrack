import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/cycle_progress.dart';
import '../common/payments_screen.dart';
import 'student_lists.dart';

class _Detail {
  _Detail({
    required this.tutor,
    required this.tuitions,
    required this.legacyRoutine,
    required this.upcoming,
    required this.homework,
    required this.exams,
  });
  final Json tutor;
  final List<Json> tuitions;
  final List<RoutineSlot> legacyRoutine;
  final List<ScheduledClass> upcoming;
  final List<HomeworkItem> homework;
  final List<Json> exams;
}

/// One tutor's page for a student: their classes (routine, class tracker,
/// payment reminders), exams and homework — only what belongs to this tutor.
/// It refreshes by itself every 30 seconds while open, so a payment the tutor
/// records or a class they mark shows up without pulling to refresh.
class TutorDetailScreen extends StatefulWidget {
  const TutorDetailScreen({super.key, required this.tutorId, required this.title});
  final String tutorId;
  final String title;

  @override
  State<TutorDetailScreen> createState() => _TutorDetailScreenState();
}

class _TutorDetailScreenState extends State<TutorDetailScreen> {
  final _key = GlobalKey<LoaderState<_Detail>>();
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) => _key.currentState?.reload(quiet: true));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<_Detail> _load() async {
    final repo = context.read<Repo>();
    final results = await Future.wait<dynamic>([repo.tutorDetail(widget.tutorId), repo.tuitions(), repo.exams()]);
    final d = results[0] as Json;
    List<Map<String, dynamic>> rows(String key) =>
        ((d[key] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final homework = rows('homework').map(HomeworkItem.fromJson).toList()
      ..sort((a, b) {
        if (a.isEvaluated != b.isEvaluated) return a.isEvaluated ? 1 : -1;
        return a.dueDate.compareTo(b.dueDate);
      });
    return _Detail(
      tutor: Map<String, dynamic>.from(d['tutor'] as Map? ?? {}),
      tuitions: (results[1] as List<Json>).where((t) => t.str('tutor_id') == widget.tutorId).toList(),
      legacyRoutine: rows('weekly_routine').map(RoutineSlot.fromJson).toList(),
      upcoming: rows('upcoming_classes').map(ScheduledClass.fromJson).toList(),
      homework: homework,
      exams: (results[2] as List<Json>).where((e) => e.str('tutor') == widget.tutorId).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Payment history',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => PaymentsScreen(tutorId: widget.tutorId)),
              ),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Classes'), Tab(text: 'Exams'), Tab(text: 'Homework')]),
        ),
        body: Loader<_Detail>(
          key: _key,
          load: _load,
          scrollable: false,
          builder: (context, d, reload) => TabBarView(
            children: [
              RefreshIndicator(onRefresh: reload, child: _ClassesTab(detail: d)),
              RefreshIndicator(onRefresh: reload, child: StudentExamsList(exams: d.exams, reload: reload)),
              RefreshIndicator(onRefresh: reload, child: StudentHomeworkList(items: d.homework, reload: reload)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassesTab extends StatelessWidget {
  const _ClassesTab({required this.detail});
  final _Detail detail;

  static const _week = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (detail.tuitions.isEmpty && detail.legacyRoutine.isEmpty && detail.upcoming.isEmpty) {
      return const PageBody(children: [
        EmptyState(
          icon: Icons.class_outlined,
          title: 'No classes yet',
          message: 'When your tutor adds you to a tuition, its routine and class tracker appear here.',
        ),
      ]);
    }
    return PageBody(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        for (final tuition in detail.tuitions) ...[
          // Reminders first, but they never stop anything below from working.
          for (final p in tuition.maps('pending_payments')) ...[
            Banner2(
              'Payment pending for cycle #${p.integer('cycle_number')}${detail.tuitions.length > 1 ? ' (${tuition.str('title')})' : ''}. '
              'Classes go on as usual; this goes away when your tutor marks it paid.',
              color: AppColors.warning,
              icon: Icons.warning_amber_rounded,
            ),
            gap8,
          ],
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tuition.str('title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                if (tuition.str('subject').isNotEmpty)
                  Text(tuition.str('subject'), style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                if (tuition.maps('routine').isNotEmpty) ...[
                  gap12,
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final slot in _sorted(tuition.maps('routine')))
                        Pill(_slotLabel(slot), color: AppColors.primarySoft, icon: Icons.schedule),
                    ],
                  ),
                ],
                gap16,
                if (tuition.obj('active_cycle') case final cycle?)
                  CycleProgress(cycle: cycle)
                else
                  Text('No classes recorded yet.', style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          gap16,
        ],
        if (detail.legacyRoutine.isNotEmpty) ...[
          const SectionTitle('Other class times'),
          FlatGroup(children: [
            for (final r in detail.legacyRoutine)
              ListTile(
                dense: true,
                leading: const Icon(Icons.schedule, size: 20),
                title: Text(r.subject.isEmpty ? 'Class' : r.subject),
                trailing: Text('${normalizeDay(r.day).isEmpty ? r.day : normalizeDay(r.day).substring(0, 3)} · ${to12h(r.start)}${r.end.isEmpty ? '' : '–${to12h(r.end)}'}'),
              ),
          ]),
          gap16,
        ],
        if (detail.upcoming.isNotEmpty) ...[
          const SectionTitle('Upcoming classes'),
          FlatGroup(children: [
            for (final c in detail.upcoming)
              ListTile(
                dense: true,
                leading: const Icon(Icons.event_rounded, size: 20),
                title: Text(c.topic.isEmpty ? 'Class' : c.topic),
                trailing: Text(fmtDateTime(c.at)),
              ),
          ]),
        ],
      ],
    );
  }

  static List<Json> _sorted(List<Json> slots) => [...slots]
    ..sort((a, b) {
      final byDay = _week.indexOf(normalizeDay(a.str('day'))).compareTo(_week.indexOf(normalizeDay(b.str('day'))));
      return byDay != 0 ? byDay : minutesOf(slotStart(a)).compareTo(minutesOf(slotStart(b)));
    });

  static String _slotLabel(Json slot) {
    final day = normalizeDay(slot.str('day'));
    final end = slot.str('end_time');
    return '${day.isEmpty ? slot.str('day') : day.substring(0, 3)} ${to12h(slotStart(slot))}${end.isEmpty ? '' : '–${to12h(end)}'}';
  }
}
