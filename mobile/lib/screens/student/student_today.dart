import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart' show HomeworkItem, tutorSirName;
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/session.dart';
import '../../widgets/charts.dart';
import '../../widgets/kit.dart';
import '../../widgets/student_kit.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import 'student_lists.dart';
import 'tutor_detail_screen.dart' show classLabel;

/// Which tab of the student home to open, and which part of it.
enum StudentTab { home, tests, homework }

/// The student's home: what matters now on top (a test that is open, or the
/// next class), each tutor as a card, homework due and the latest result.
class StudentTodayView extends StatelessWidget {
  const StudentTodayView({
    super.key,
    required this.tutors,
    required this.tuitions,
    required this.connections,
    required this.exams,
    required this.homework,
    required this.reload,
    required this.onOpenTab,
    required this.onOpenTutor,
    required this.onConnect,
  });

  final List<Json> tutors;
  final List<Json> tuitions;
  final List<Json> connections;
  final List<Json> exams;
  final List<HomeworkItem> homework;
  final Future<void> Function() reload;
  final void Function(StudentTab tab, {bool results}) onOpenTab;
  /// Opens a tutor's page on one of their tuitions (null: the first one).
  final void Function(String tutorId, String name, String? tuitionId) onOpenTutor;

  /// Opens "Connect to a tutor" (invite code, requests, search).
  final Future<void> Function() onConnect;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final now = session.api.serverNow;
    final pendingRequests = connections.where((c) => c.str('status') == 'PENDING').toList();

    final openExams = exams.where((e) => !e.flag('has_submission') && e.flag('can_submit')).toList()
      ..sort((a, b) => (a.date('end_time') ?? now).compareTo(b.date('end_time') ?? now));
    final todo = homework.where((h) => !h.isSubmitted && !h.isEvaluated).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final percents = resultPercents(exams);
    final hero = _hero(context, now, openExams);
    // Handed in, marks not out yet: stays on Home so the student knows it arrived.
    final waiting = exams.where((e) => e.flag('has_submission') && !e.flag('results_released')).toList()
      ..sort((a, b) => (_submittedAt(b) ?? now).compareTo(_submittedAt(a) ?? now));

    // Each thing appears once: the next class in the card on top, each tutor's
    // progress on their card (their routine is one tap away), homework in one
    // list, and the tests and homework counts on the tab badges.
    final blocks = <Widget>[
      GreetingHeader(name: session.displayName, now: now.toLocal(), subtitle: _summary(openExams.length, todo, now)),
      if (pendingRequests.isNotEmpty) ...[
        Banner2(
          pendingRequests.length == 1
              ? tr('Your request to {p0} is waiting for an answer.', {'p0': _requestName(pendingRequests.first)})
              : tr('{p0} requests are waiting for an answer.', {'p0': pendingRequests.length}),
          icon: Icons.hourglass_top_rounded,
          color: AppColors.warning,
          action: TextButton(onPressed: onConnect, child: Text(tr('View'))),
        ),
        gap16,
      ],
      if (hero != null) hero,
      if (waiting.isNotEmpty) ...[
        SectionHeader(tr('Waiting for result'), count: waiting.length, onAction: () => onOpenTab(StudentTab.tests, results: true)),
        RowGroup(children: [
          for (final exam in waiting.take(3))
            KitRow(
              icon: Icons.hourglass_top_rounded,
              accent: AppColors.warning,
              title: exam.str('title'),
              subtitle: [
                if (tutorSirName(exam).isNotEmpty) tutorSirName(exam),
                tr('Submitted {p0}', {'p0': fmtShortDate(_submittedAt(exam) ?? exam.date('end_time'))}),
                if (exam.obj('my_result')?.str('status') == 'DELAYED') tr('Late'),
              ].join(' · '),
              trailing: Pill(tr('Waiting'), color: AppColors.warning),
              onTap: () => openExamResult(context, exam),
            ),
        ]),
      ],
      if (tutors.isNotEmpty) ...[
        SectionHeader(tr('Your tutors'), actionLabel: tr('Add'), onAction: onConnect),
        // One card per tuition: a student in Physics and Math with the same tutor gets two cards.
        for (final (i, (tutor, tuition, label)) in _classCards().indexed) ...[
          if (i > 0) gap12,
          TutorCard(
            tutor: tutor,
            tuitions: tuition == null ? const [] : [tuition],
            classLabel: label,
            onTap: () => onOpenTutor(tutor.str('id'), tutorCardName(tutor), tuition?.str('id')),
          ),
        ],
      ],
      if (todo.isNotEmpty) ...[
        SectionHeader(tr('Homework due'), count: todo.length, onAction: () => onOpenTab(StudentTab.homework)),
        RowGroup(children: [
          for (final hw in todo.take(3))
            KitRow(
              icon: Icons.menu_book_rounded,
              accent: hw.dueDate.isBefore(now) ? AppColors.danger : AppColors.warning,
              title: hw.title,
              subtitle: hw.tutorDisplay,
              trailing: DeadlineChip(at: hw.dueDate, now: now),
              onTap: () => onOpenTab(StudentTab.homework),
            ),
        ]),
      ],
      if (percents.isNotEmpty) ...[
        SectionHeader(tr('Latest result'), onAction: () => onOpenTab(StudentTab.tests, results: true)),
        _LatestResult(exams: exams, percents: percents),
      ],
      if (tutors.isEmpty && tuitions.isEmpty) ...[
        gap24,
        EmptyState(
          icon: Icons.key_rounded,
          title: tr('Connect with your tutor'),
          message: tr('Enter the invite code your tutor gave you. Your classes, tests and homework then appear here.'),
          action: FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('Add a tutor')),
          ),
        ),
      ],
    ];
    return PageBody(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: staggered(context, blocks));
  }

  /// (tutor, tuition, label) for each card: a tutor with no tuition yet still gets one card.
  /// The label is the tuition's subject ("Physics"), shown when it tells two cards apart or says what the class is.
  List<(Json, Json?, String)> _classCards() {
    final cards = <(Json, Json?, String)>[];
    for (final tutor in tutors) {
      final mine = tuitions.where((t) => t.str('tutor_id') == tutor.str('id')).toList();
      if (mine.isEmpty) {
        cards.add((tutor, null, ''));
        continue;
      }
      for (final (i, t) in mine.indexed) {
        final hasSubject = t.str('subject').trim().isNotEmpty;
        cards.add((tutor, t, mine.length > 1 || hasSubject ? classLabel(t, i) : ''));
      }
    }
    return cards;
  }

  /// "2 things due today" style line under the greeting.
  String _summary(int openExams, List<HomeworkItem> todo, DateTime now) {
    final dueToday = todo.where((h) => h.dueDate.difference(now) < const Duration(hours: 24)).length;
    if (openExams > 0) return openExams == 1 ? tr('A test is open right now.') : tr('{n} tests are open right now.', {'n': openExams});
    if (dueToday > 0) return dueToday == 1 ? tr('1 homework is due within a day.') : tr('{n} homework are due within a day.', {'n': dueToday});
    if (todo.isEmpty) return tr("You're all caught up.");
    return tr('{n} homework to do this week.', {'n': todo.length});
  }

  /// A test that is open now. Nothing otherwise: no "next class" card, because tutors
  /// often move classes and a countdown from the routine could be wrong.
  Widget? _hero(BuildContext context, DateTime now, List<Json> openExams) {
    if (openExams.isNotEmpty) {
      final exam = openExams.first;
      final isAssignment = exam.str('category') == 'ASSIGNMENT';
      final minutes = exam.integer('duration_minutes');
      final end = exam.date('end_time') ?? now;
      return HeroCard(
        eyebrow: isAssignment ? tr('Assignment open') : tr('Live now'),
        live: !isAssignment,
        icon: isAssignment ? Icons.assignment_rounded : Icons.timer_rounded,
        accent: AppColors.success,
        title: exam.str('title'),
        subtitle: tutorSirName(exam),
        meta: [
          DeadlineChip(at: end, now: now, kind: isAssignment ? DeadlineKind.due : DeadlineKind.closes),
          if (minutes > 0 && !isAssignment) Pill(tr('{p0} min', {'p0': minutes}), icon: Icons.timer_outlined),
          Pill(tr('{p0} marks', {'p0': trimNumber(exam.number('total_marks'))}), icon: Icons.star_outline_rounded),
        ],
        action: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.successDeep, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(50)),
          onPressed: () => takeExam(context, exam, reload),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(isAssignment ? tr('Open assignment') : tr('Start now')),
        ),
      );
    }
    return null;
  }

  static DateTime? _submittedAt(Json exam) => exam.obj('my_result')?.date('submitted_at');

  static String _requestName(Json c) =>
      c.str('tutor_display_name').isNotEmpty ? c.str('tutor_display_name') : c.str('tutor_name');
}

// ── Tutors ───────────────────────────────────────────────────────────────────

/// "Ashraf Sir" for a tutor from /my-tutors/.
String tutorCardName(Json tutor) {
  final name = tutor.str('display_name');
  return name.isNotEmpty ? name : tutor.str('username');
}

/// One tutor on the student's home: photo, name, classes a week and a ring of
/// classes done in the current cycle.
/// Tap for the weekly routine and every class done.
class TutorCard extends StatelessWidget {
  const TutorCard({super.key, required this.tutor, required this.tuitions, required this.onTap, this.classLabel = ''});
  final Json tutor;
  final List<Json> tuitions;
  final VoidCallback onTap;

  /// Which of the tutor's tuitions this card is ("Physics"); empty when there is nothing to tell apart.
  final String classLabel;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final name = tutorCardName(tutor);
    final perWeek = tuitions.fold<int>(0, (n, t) => n + t.maps('routine').length);
    var done = 0;
    var total = 0;
    for (final t in tuitions) {
      final cycle = t.obj('active_cycle');
      done += cycle?.integer('completed_classes') ?? 0;
      total += cycle?.integer('total_classes') ?? t.integer('cycle_length');
    }
    final unpaid = tuitions.any((t) => t.maps('pending_payments').isNotEmpty);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Row(
        children: [
          PersonAvatar(name: name, photo: tutor.str('profile_picture_url', tutor.str('profile_picture')), radius: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: tt.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (classLabel.isNotEmpty) classLabel,
                    tuitions.isEmpty
                        ? tr('No classes yet')
                        : perWeek == 1
                            ? tr('1 class a week')
                            : tr('{n} classes a week', {'n': perWeek}),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: tt.textSecondary),
                ),
                if (unpaid) ...[
                  const SizedBox(height: 6),
                  Text(tr('Payment due'),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tone(context, AppColors.warning))),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (tuitions.isNotEmpty && total > 0)
            ProgressRing(done: done, total: total, size: 60, thickness: 6, caption: tr('classes'))
          else
            Icon(Icons.chevron_right_rounded, color: tt.textTertiary),
        ],
      ),
    );
  }
}

// ── Latest result ────────────────────────────────────────────────────────────

class _LatestResult extends StatelessWidget {
  const _LatestResult({required this.exams, required this.percents});
  final List<Json> exams;
  final List<double> percents;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final released = exams.where((e) => e.flag('results_released') && e.obj('my_result')?.numberOrNull('obtained_marks') != null).toList()
      ..sort((a, b) => (b.date('end_time') ?? DateTime(2000)).compareTo(a.date('end_time') ?? DateTime(2000)));
    if (released.isEmpty) return const SizedBox.shrink();
    final exam = released.first;
    final got = exam.obj('my_result')!.number('obtained_marks');
    final total = exam.number('total_marks');
    final percent = total <= 0 ? 0.0 : (got * 100 / total).toDouble();
    final change = percents.length > 1 ? percents.last - percents[percents.length - 2] : 0.0;
    return AppCard(
      onTap: () => openExamResult(context, exam),
      child: Row(
        children: [
          ScoreRing(percent: percent, size: 72),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exam.str('title'), maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tt.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  '${trimNumber(got)} / ${trimNumber(total)} · ${tutorSirName(exam)}',
                  style: TextStyle(fontSize: 13, color: tt.textSecondary),
                ),
                if (change.abs() >= 1) ...[
                  const SizedBox(height: 6),
                  TrendChip(change: change),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: tt.textTertiary),
        ],
      ),
    );
  }
}
