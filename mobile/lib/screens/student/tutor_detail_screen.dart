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
///
/// A student in two tuitions of the same tutor (say Physics and Math) never
/// sees them merged: the page shows one tuition at a time, with a switch at
/// the top, and each tuition keeps its own routine, classes done, exams and
/// homework. One-to-one work from the tutor (not tied to a tuition) shows in
/// each of them.
///
/// It refreshes by itself every 30 seconds while open, so a payment the tutor
/// records or a class they mark shows up without pulling to refresh.
class TutorDetailScreen extends StatefulWidget {
  const TutorDetailScreen({super.key, required this.tutorId, required this.title, this.tuitionId});
  final String tutorId;
  final String title;

  /// The tuition to open on; null opens the first one.
  final String? tuitionId;

  @override
  State<TutorDetailScreen> createState() => _TutorDetailScreenState();
}

/// What a student calls one of a tutor's tuitions: its subject, else "Class 2".
/// Never the name the tutor gave the tuition.
String classLabel(Json tuition, int index) {
  final subject = tuition.str('subject').trim();
  return subject.isNotEmpty ? subject : tr('Class {n}', {'n': index + 1});
}

class _TutorDetailScreenState extends State<TutorDetailScreen> {
  final _key = GlobalKey<LoaderState<_Detail>>();
  Timer? _refresh;
  _Detail? _all;
  late String? _classId = widget.tuitionId;

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
    final all = _Detail(
      tutor: Map<String, dynamic>.from(d['tutor'] as Map? ?? {}),
      tuitions: (results[1] as List<Json>).where((t) => t.str('tutor_id') == widget.tutorId).toList(),
      legacyRoutine: rows('weekly_routine').map(RoutineSlot.fromJson).toList(),
      upcoming: rows('upcoming_classes').map(ScheduledClass.fromJson).toList(),
      homework: homework,
      exams: exams,
    );
    if (mounted) setState(() => _all = all);
    return all;
  }

  /// The tuition on screen (null when the student has at most one with this tutor).
  String? _selected(_Detail d) {
    if (d.tuitions.length < 2) return null;
    final ids = d.tuitions.map((t) => t.str('id')).toList();
    return ids.contains(_classId) ? _classId : ids.first;
  }

  /// Only what belongs to the tuition on screen, plus one-to-one work.
  _Detail _scope(_Detail d) {
    final id = _selected(d);
    if (id == null) return d;
    bool mine(String tuitionId) => tuitionId.isEmpty || tuitionId == id;
    return _Detail(
      tutor: d.tutor,
      tuitions: d.tuitions.where((t) => t.str('id') == id).toList(),
      legacyRoutine: d.legacyRoutine.where((r) => mine(r.tuitionId)).toList(),
      upcoming: d.upcoming.where((c) => mine(c.tuitionId)).toList(),
      homework: d.homework.where((h) => mine(h.classId)).toList(),
      exams: d.exams.where((e) => mine(e.str('tuition_id'))).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final scoped = all == null ? null : _scope(all);
    final now = context.read<Session>().api.serverNow;
    final examCount = scoped == null ? 0 : pendingExamCount(scoped.exams, now);
    final homeworkCount = scoped == null ? 0 : pendingHomeworkCount(scoped.homework);
    final selected = all == null ? null : _selected(all);
    final tabs = TabBar(tabs: [
      Tab(text: tr('Classes')),
      Tab(child: countBadge(Text(tr('Exams')), examCount, offset: const Offset(14, -6))),
      Tab(child: countBadge(Text(tr('Homework')), homeworkCount, offset: const Offset(14, -6))),
    ]);
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
          // One tuition at a time (Physics / Math…), then how many exams and homework are waiting in it.
          bottom: selected == null
              ? tabs
              : PreferredSize(
                  preferredSize: Size.fromHeight(tabs.preferredSize.height + 60),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: PillToggle<String>(
                          options: [
                            for (final (i, t) in all!.tuitions.indexed) (t.str('id'), classLabel(t, i), null),
                          ],
                          selected: selected,
                          onChanged: (id) => setState(() => _classId = id),
                        ),
                      ),
                      tabs,
                    ],
                  ),
                ),
        ),
        body: Loader<_Detail>(
          key: _key,
          load: _load,
          scrollable: false,
          builder: (context, d, reload) {
            final view = _scope(d);
            return TabBarView(
              children: [
                RefreshIndicator(onRefresh: reload, child: _ClassesTab(detail: view)),
                RefreshIndicator(onRefresh: reload, child: StudentExamsList(exams: view.exams, reload: reload, showTutor: false)),
                RefreshIndicator(onRefresh: reload, child: StudentHomeworkList(items: view.homework, reload: reload, showTutor: false)),
              ],
            );
          },
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
          // Date-wise, as the tutor marks them — for the tuition on screen only.
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
              // "Physics" when this page shows one tuition with a subject; otherwise just "Your tutor".
              Text(
                detail.tuitions.length == 1 && detail.tuitions.first.str('subject').trim().isNotEmpty
                    ? detail.tuitions.first.str('subject').trim()
                    : tr('Your tutor'),
                style: TextStyle(fontSize: 14, color: tt.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
