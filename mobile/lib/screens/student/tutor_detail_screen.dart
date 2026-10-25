import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../core/week_plan.dart' show weekOrder;
import '../../widgets/kit.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/chats_screen.dart' show openChatWith;
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
              tooltip: tr('Message {name}', {'name': Raw(widget.title)}),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              onPressed: () => openChatWith(context, widget.tutorId),
            ),
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

/// The tutor at a glance, then three plain sections: Subjects, Weekly
/// routine (day and time only) and Classes done (by date).
class _ClassesTab extends StatelessWidget {
  const _ClassesTab({required this.detail});
  final _Detail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.tuitions.isEmpty && detail.legacyRoutine.isEmpty && detail.upcoming.isEmpty) {
      return PageBody(children: [
        _TutorHeader(detail: detail),
        gap24,
        EmptyState(
          icon: Icons.class_outlined,
          title: tr('No classes yet'),
          message: tr('When your tutor adds you to a tuition, its routine and class tracker appear here.'),
        ),
      ]);
    }
    final routine = _routine(detail);
    return PageBody(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _TutorHeader(detail: detail),
        if (routine.isNotEmpty) ...[
          SectionHeader(tr('Weekly routine')),
          _RoutineCard(rows: routine),
        ],
        if (detail.tuitions.isNotEmpty) ...[
          SectionHeader(tr('Classes done')),
          // One date-wise list for this tutor, as they mark classes; no split by subject.
          AppCard(
            child: ClassesDone(
              cycles: [
                for (final t in detail.tuitions)
                  if (t.obj('active_cycle') case final cycle?) cycle,
              ],
              homework: detail.homework,
              paymentDue: detail.tuitions.any((t) => t.maps('pending_payments').isNotEmpty),
            ),
          ),
        ],
        if (detail.upcoming.isNotEmpty) ...[
          SectionHeader(tr('Extra classes')),
          RowGroup(children: [
            for (final c in detail.upcoming)
              KitRow(
                dense: true,
                icon: Icons.event_rounded,
                accent: AppColors.primarySoft,
                title: c.topic.isEmpty ? tr('Class') : c.topic,
                subtitle: fmtDateTime(c.at),
              ),
          ]),
        ],
      ],
    );
  }

  /// Every class time with this tutor, Saturday first: (day, start, end).
  static List<(String, String, String)> _routine(_Detail detail) {
    final out = <(String, String, String)>{
      for (final t in detail.tuitions)
        for (final slot in t.maps('routine')) (normalizeDay(slot.str('day')), slotStart(slot), slot.str('end_time')),
      for (final r in detail.legacyRoutine) (normalizeDay(r.day), r.start, r.end),
    }.where((r) => r.$1.isNotEmpty).toList()
      ..sort((a, b) {
        final byDay = weekOrder.indexOf(a.$1).compareTo(weekOrder.indexOf(b.$1));
        return byDay != 0 ? byDay : minutesOf(a.$2).compareTo(minutesOf(b.$2));
      });
    return out;
  }
}

/// One row per class time: "Sat   8:00 – 9:30 AM". Today's rows are marked.
class _RoutineCard extends StatelessWidget {
  const _RoutineCard({required this.rows});
  final List<(String, String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final today = weekdayName(DateTime.now());
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (final (i, (day, start, end)) in rows.indexed) ...[
            if (i > 0 && rows[i - 1].$1 != day) Divider(height: 1, color: tt.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: isBangla ? 64 : 44,
                    // The day is written once, on its first class.
                    child: i > 0 && rows[i - 1].$1 == day
                        ? null
                        : Text(
                            dayLabel(day),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: day == today ? tt.primary : tt.textSecondary,
                            ),
                          ),
                  ),
                  Expanded(
                    child: Text(
                      end.isEmpty ? to12h(start) : '${to12h(start)} – ${to12h(end)}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tt.textPrimary, fontFeatures: tabular),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Who the tutor is. No "next class" time: tutors often move classes.
class _TutorHeader extends StatelessWidget {
  const _TutorHeader({required this.detail});
  final _Detail detail;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final tutor = detail.tutor;
    final name = tutor.str('display_name').isNotEmpty ? tutor.str('display_name') : tutor.str('username');
    return Row(
      children: [
        PersonAvatar(name: name, photo: tutor.str('profile_picture_url', tutor.str('profile_picture')), radius: 32),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: tt.textPrimary)),
              const SizedBox(height: 2),
              Text(tr('Your tutor'), style: TextStyle(fontSize: 14, color: tt.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
