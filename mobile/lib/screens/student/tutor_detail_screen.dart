import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../core/reminder_plan.dart' show nextClass, whenLabel;
import '../../widgets/kit.dart';
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
              RefreshIndicator(onRefresh: reload, child: StudentExamsList(exams: d.exams, reload: reload, showTutor: false)),
              RefreshIndicator(onRefresh: reload, child: StudentHomeworkList(items: d.homework, reload: reload, showTutor: false)),
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
        _TutorHeader(detail: detail),
        gap16,
        for (final (index, tuition) in detail.tuitions.indexed) ...[
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
                if (tuition.str('subject').isNotEmpty || detail.tuitions.length > 1)
                  Row(
                    children: [
                      InitialTile(tuition.str('subject').isNotEmpty ? tuition.str('subject') : '${index + 1}', size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tuition.str('subject').isNotEmpty ? tuition.str('subject') : tr('Class group {n}', {'n': index + 1}),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                        ),
                      ),
                    ],
                  ),
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

/// Who the tutor is and when the next class with them is.
class _TutorHeader extends StatelessWidget {
  const _TutorHeader({required this.detail});
  final _Detail detail;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final tutor = detail.tutor;
    final name = tutor.str('display_name').isNotEmpty ? tutor.str('display_name') : tutor.str('username');
    final photo = context.read<Session>().api.mediaUrl(tutor.str('profile_picture_url'));
    final subjects = tutor.strings('subjects');
    final now = context.read<Session>().api.serverNow;
    final next = nextClass(detail.tuitions, now);
    final done = detail.tuitions.fold<int>(0, (sum, t) => sum + (t.obj('active_cycle')?.integer('completed_classes') ?? 0));
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox.square(
                  dimension: 60,
                  child: photo.isEmpty
                      ? InitialTile(name, size: 60, seed: tutor.str('id'))
                      : Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, _, _) => InitialTile(name, size: 60, seed: tutor.str('id'))),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: tt.textPrimary)),
                    if (subjects.isNotEmpty)
                      Text(subjects.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: tt.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          gap16,
          TileRow(children: [
            _MiniStat(
              icon: Icons.event_available_rounded,
              label: tr('Next class'),
              value: next == null ? '—' : whenLabel(next.at.toLocal(), now.toLocal()),
            ),
            _MiniStat(icon: Icons.check_circle_outline_rounded, label: tr('Classes this cycle'), value: localDigits('$done')),
          ]),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: tt.cardRaised, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tt.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: tt.textSecondary)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tt.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
