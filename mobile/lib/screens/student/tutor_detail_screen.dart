import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
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
  int _examCount = 0;
  int _homeworkCount = 0;

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
    final exams = (results[2] as List<Json>).where((e) => e.str('tutor') == widget.tutorId).toList();
    if (mounted) {
      final now = context.read<Session>().api.serverNow;
      setState(() {
        _examCount = pendingExamCount(exams, now);
        _homeworkCount = pendingHomeworkCount(homework);
      });
    }
    return _Detail(
      tutor: Map<String, dynamic>.from(d['tutor'] as Map? ?? {}),
      tuitions: (results[1] as List<Json>).where((t) => t.str('tutor_id') == widget.tutorId).toList(),
      legacyRoutine: rows('weekly_routine').map(RoutineSlot.fromJson).toList(),
      upcoming: rows('upcoming_classes').map(ScheduledClass.fromJson).toList(),
      homework: homework,
      exams: exams,
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
              tooltip: tr('Payment history'),
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => PaymentsScreen(tutorId: widget.tutorId)),
              ),
            ),
          ],
          // How many exams and homework are waiting, so the student knows where to tap.
          bottom: TabBar(tabs: [
            Tab(text: tr('Classes')),
            Tab(child: countBadge(Text(tr('Exams')), _examCount, offset: const Offset(14, -6))),
            Tab(child: countBadge(Text(tr('Homework')), _homeworkCount, offset: const Offset(14, -6))),
          ]),
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
      return PageBody(children: [
        EmptyState(
          icon: Icons.class_outlined,
          title: tr('No classes yet'),
          message: tr('When your tutor adds you to a tuition, its routine and class tracker appear here.'),
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
              tr('Payment pending for cycle #{p0}{p1}. Classes go on as usual; this goes away when your tutor marks it paid.', {'p0': p.integer('cycle_number'), 'p1': ''}),
              color: AppColors.warning,
              icon: Icons.warning_amber_rounded,
            ),
            gap8,
          ],
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The tuition's own name stays with the tutor; the student sees the subject only.
                if (tuition.str('subject').isNotEmpty)
                  Text(tuition.str('subject'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
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
                  Text(tr('No classes recorded yet.'), style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          gap16,
        ],
        if (detail.legacyRoutine.isNotEmpty) ...[
          SectionTitle(tr('Other class times')),
          FlatGroup(children: [
            for (final r in detail.legacyRoutine)
              ListTile(
                dense: true,
                leading: const Icon(Icons.schedule, size: 20),
                title: Text(r.subject.isEmpty ? tr('Class') : r.subject),
                trailing: Text('${normalizeDay(r.day).isEmpty ? r.day : dayLabel(normalizeDay(r.day))} · ${to12h(r.start)}${r.end.isEmpty ? '' : '–${to12h(r.end)}'}'),
              ),
          ]),
          gap16,
        ],
        if (detail.upcoming.isNotEmpty) ...[
          SectionTitle(tr('Upcoming classes')),
          FlatGroup(children: [
            for (final c in detail.upcoming)
              ListTile(
                dense: true,
                leading: const Icon(Icons.event_rounded, size: 20),
                title: Text(c.topic.isEmpty ? tr('Class') : c.topic),
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
    return '${day.isEmpty ? slot.str('day') : dayLabel(day)} ${to12h(slotStart(slot))}${end.isEmpty ? '' : '–${to12h(end)}'}';
  }
}
