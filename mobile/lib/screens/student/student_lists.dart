import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart' show HomeworkItem, tutorSirName;
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/kit.dart';
import '../../widgets/student_kit.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/leaderboard_screen.dart';
import 'exam_result_screen.dart';
import 'exam_take_screen.dart';
import 'homework_card.dart';

/// Lists a student sees in more than one place: on the home tabs (everything)
/// and inside one tutor's page (only that tutor's work).

// ── Counts for the badges ───────────────────────────────────────────────────

/// Exams and assignments still waiting for this student: open now or coming up, not turned in.
int pendingExamCount(List<Json> exams, DateTime now) => exams
    .where((e) => !e.flag('has_submission') && (e.flag('can_submit') || (e.date('start_time')?.isAfter(now) ?? false)))
    .length;

/// Homework not handed in yet (and not already closed by the tutor).
int pendingHomeworkCount(List<HomeworkItem> items) => items.where((h) => !h.isSubmitted && !h.isEvaluated).length;

/// A tab or menu label with a small red count beside it when [count] is above zero.
/// [offset] moves the count clear of a text label (icons can use the default).
Widget countBadge(Widget child, int count, {Offset? offset}) =>
    Badge(isLabelVisible: count > 0, label: Text(localDigits('$count')), offset: offset, child: child);

// ── Exams ────────────────────────────────────────────────────────────────────

/// Which part of the tests list is showing.
enum ExamsView { todo, upcoming, results }

/// A student's exams and assignments in three parts: To do (open now),
/// Upcoming (not open yet) and Results (turned in or over).
class StudentExamsList extends StatefulWidget {
  const StudentExamsList({super.key, required this.exams, required this.reload, this.showTutor = true, this.initialView});

  /// Name the tutor ("Ashraf Sir") on each card. Off on one tutor's own page, where it goes without saying.
  final bool showTutor;
  final List<Json> exams;
  final Future<void> Function() reload;

  /// Opens on this part instead of the first one with something in it.
  final ExamsView? initialView;

  @override
  State<StudentExamsList> createState() => _StudentExamsListState();
}

class _StudentExamsListState extends State<StudentExamsList> {
  ExamsView? _view;

  @override
  Widget build(BuildContext context) {
    final exams = widget.exams;
    final now = context.read<Session>().api.serverNow;
    // To do = can be turned in now; Upcoming = not open yet; Results = turned in or over.
    final todo = exams.where((e) => !e.flag('has_submission') && e.flag('can_submit')).toList()
      ..sort((a, b) => (a.date('end_time') ?? now).compareTo(b.date('end_time') ?? now));
    final upcoming = exams
        .where((e) => !e.flag('has_submission') && !e.flag('can_submit') && (e.date('start_time')?.isAfter(now) ?? false))
        .toList()
      ..sort((a, b) => (a.date('start_time') ?? now).compareTo(b.date('start_time') ?? now));
    // Handed in and waiting for marks first, then everything else newest first.
    bool waiting(Json e) => e.flag('has_submission') && !e.flag('results_released');
    final done = exams.where((e) => !todo.contains(e) && !upcoming.contains(e)).toList()
      ..sort((a, b) {
        if (waiting(a) != waiting(b)) return waiting(a) ? -1 : 1;
        return (b.date('end_time') ?? now).compareTo(a.date('end_time') ?? now);
      });

    if (exams.isEmpty) {
      return PageBody(children: [
        EmptyState(
          icon: Icons.quiz_outlined,
          title: tr('No tests or assignments yet'),
          message: tr('When your tutor sets one, it appears here.'),
        ),
      ]);
    }
    final view = _view ??
        widget.initialView ??
        (todo.isNotEmpty ? ExamsView.todo : (upcoming.isNotEmpty ? ExamsView.upcoming : ExamsView.results));
    final percents = resultPercents(exams);

    final List<Widget> body;
    switch (view) {
      case ExamsView.todo:
        body = todo.isEmpty
            ? [EmptyState(icon: Icons.task_alt_rounded, title: tr('Nothing to do right now'), message: tr('Open tests and assignments appear here.'))]
            : [for (final exam in todo) ...[StudentExamCard(exam: exam, reload: widget.reload, showTutor: widget.showTutor), gap12]];
      case ExamsView.upcoming:
        body = upcoming.isEmpty
            ? [EmptyState(icon: Icons.event_available_rounded, title: tr('Nothing scheduled'), message: tr('When your tutor schedules a test, it shows here before it opens.'))]
            : [for (final exam in upcoming) ...[StudentExamCard(exam: exam, reload: widget.reload, showTutor: widget.showTutor), gap12]];
      case ExamsView.results:
        body = done.isEmpty
            ? [EmptyState(icon: Icons.insights_rounded, title: tr('No results yet'), message: tr('Your marks appear here once your tutor publishes them.'))]
            : [
                if (percents.length >= 2) ...[
                  ScoreTrend(percents: percents.length > 8 ? percents.sublist(percents.length - 8) : percents),
                  gap12,
                ],
                RowGroup(children: [for (final exam in done) _ResultRow(exam: exam, showTutor: widget.showTutor)]),
              ];
    }
    return PageBody(
      children: [
        SegmentTabs<ExamsView>(
          options: [
            (ExamsView.todo, tr('To do'), todo.length),
            (ExamsView.upcoming, tr('Upcoming'), upcoming.length),
            (ExamsView.results, tr('Results'), null),
          ],
          selected: view,
          onChanged: (v) => setState(() => _view = v),
        ),
        gap16,
        ...staggered(context, body),
      ],
    );
  }
}

/// One finished test: the score ring, what it was and the marks. Tap for the full result.
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.exam, required this.showTutor});
  final Json exam;
  final bool showTutor;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final result = exam.obj('my_result');
    final released = exam.flag('results_released');
    final obtained = result?.numberOrNull('obtained_marks');
    final total = exam.number('total_marks');
    final turnedIn = exam.flag('has_submission');
    final percent = released && obtained != null && total > 0 ? (obtained * 100 / total).toDouble() : null;
    final when = fmtShortDate(exam.date('end_time'));
    return InkWell(
      onTap: turnedIn ? () => openExamResult(context, exam) : null,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            if (percent != null)
              ScoreRing(percent: percent, size: 46)
            else
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: tt.cardRaised, shape: BoxShape.circle),
                child: Icon(turnedIn ? Icons.hourglass_top_rounded : Icons.block_rounded, size: 20, color: tt.textTertiary),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exam.str('title'), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tt.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (showTutor && tutorSirName(exam).isNotEmpty) tutorSirName(exam),
                      when,
                      if (!turnedIn) tr('Missed'),
                      if (turnedIn && !released) tr('Submitted · waiting for result'),
                      if (result?.str('status') == 'DELAYED') tr('Late'),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: !turnedIn
                          ? tone(context, AppColors.danger)
                          : (!released ? tone(context, AppColors.warning) : tt.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            if (percent != null) ...[
              const SizedBox(width: 8),
              Text(
                '${trimNumber(obtained)}/${trimNumber(total)}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tt.textPrimary, fontFeatures: tabular),
              ),
            ],
            if (turnedIn) Icon(Icons.chevron_right_rounded, color: tt.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Starts (or opens) [exam] for the student, then shows what happens to the answers.
Future<void> takeExam(BuildContext context, Json exam, Future<void> Function() reload) async {
  final repo = context.read<Repo>();
  final isAssignment = exam.str('category') == 'ASSIGNMENT';
  final minutes = exam.integer('duration_minutes');
  if (minutes > 0 && !isAssignment) {
    final ok = await confirm(
      context,
      title: tr('Start the timed exam?'),
      message: tr('You get {p0} minutes from the moment you start, and the clock keeps running if you leave the app.', {'p0': minutes}),
      confirmLabel: tr('Start now'),
    );
    if (!ok || !context.mounted) return;
  }
  Json? started;
  await attempt(context, () async => started = await repo.startExam(exam.str('id')));
  if (started == null || !context.mounted) return;
  final response = await Navigator.push<Json>(
    context,
    MaterialPageRoute(builder: (_) => ExamTakeScreen(exam: started!.obj('exam') ?? {})),
  );
  await reload();
  if (response == null || !context.mounted) return;
  final status = response.obj('result_status') ?? {};
  if (response.flag('results_released')) {
    showToast(context, tr('Submitted. Here is your result.'));
    openExamResult(context, exam);
  } else if (status.str('mode') == 'SCHEDULED' && status.date('publish_at') != null) {
    showToast(context, tr('Submitted. Results will be published on {p0}.', {'p0': fmtDateTime(status.date('publish_at'))}));
  } else {
    showToast(context, tr('Submitted. Your tutor will publish the results.'));
  }
}

void openExamResult(BuildContext context, Json exam) {
  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ExamResultScreen(examId: exam.str('id'), title: exam.str('title'))));
}

class StudentExamCard extends StatelessWidget {
  const StudentExamCard({super.key, required this.exam, required this.reload, this.showTutor = true});
  final Json exam;
  final bool showTutor;
  final Future<void> Function() reload;

  Future<void> _take(BuildContext context) => takeExam(context, exam, reload);

  void _openResult(BuildContext context) => openExamResult(context, exam);

  @override
  Widget build(BuildContext context) {
    final now = context.read<Session>().api.serverNow;
    final isAssignment = exam.str('category') == 'ASSIGNMENT';
    final start = exam.date('start_time') ?? now;
    final end = exam.date('end_time') ?? now;
    final lateEnd = exam.date('late_submission_until');
    final done = exam.flag('has_submission');
    final upcoming = !done && now.isBefore(start);
    final open = !done && !upcoming && exam.flag('can_submit');
    final isLate = open && now.isAfter(end);
    final missed = !done && !upcoming && !open;
    final result = exam.obj('my_result');
    final released = exam.flag('results_released');
    final minutes = exam.integer('duration_minutes');
    final negative = exam.number('negative_marks_per_wrong');

    return AppCard(
      borderColor: open ? (isLate ? AppColors.warning : AppColors.success).withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type, length and the time left, wrapping onto a second line on small phones.
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Pill(isAssignment ? tr('Assignment') : tr('Exam'), color: AppColors.primarySoft),
                    if (minutes > 0 && !isAssignment) Pill(tr('{p0} min', {'p0': minutes}), icon: Icons.timer_outlined),
                    if (open && !isLate) DeadlineChip(at: end, now: now, kind: isAssignment ? DeadlineKind.due : DeadlineKind.closes),
                    if (upcoming) DeadlineChip(at: start, now: now, kind: DeadlineKind.opens),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(tr('{p0} marks', {'p0': trimNumber(exam.number('total_marks'))}), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success)),
            ],
          ),
          gap8,
          Text(exam.str('title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: context.tt.textPrimary)),
          // Who set it ("Ashraf Sir"); the tuition's own name is the tutor's business.
          if (showTutor && tutorSirName(exam).isNotEmpty)
            Text(tutorSirName(exam), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          gap8,
          if (upcoming)
            Text(tr('Opens {p0} · {p1}', {'p0': relativeFromNow(start.difference(now)), 'p1': fmtDateTime(start)}), style: TextStyle(color: AppColors.primarySoft))
          else
            Text('${isAssignment ? tr('Due') : tr('Ends')} ${fmtDateTime(end)}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          if (isLate)
            Text(
              lateEnd != null && lateEnd.isAfter(now)
                  ? tr('Deadline passed — late work accepted {p0}', {'p0': relativeFromNow(lateEnd.difference(now)).replaceFirst('in ', 'for ')})
                  : tr('Deadline passed — hand in now'),
              style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600),
            ),
          if (!isAssignment && upcoming && negative > 0)
            Text(tr('Wrong MCQ answers lose {p0} mark(s).', {'p0': trimNumber(negative)}), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          Divider(height: 24),
          if (done) ...[
            Row(
              children: [
                const Icon(Icons.check_circle, size: 18, color: AppColors.success),
                const SizedBox(width: 6),
                Text(tr('Turned in{p0}', {'p0': result?.str('status') == 'DELAYED' ? tr(' (late)') : ''})),
                const Spacer(),
                if (released && result?.numberOrNull('obtained_marks') != null)
                  Text(
                    '${trimNumber(result!.number('obtained_marks'))} / ${trimNumber(exam.number('total_marks'))}${result.flag('is_graded') ? '' : tr(' so far')}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.success),
                  )
                else
                  Pill(tr('Results pending'), icon: Icons.hourglass_empty, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ),
            if (!released && exam.str('result_publish_mode') == 'SCHEDULED' && exam.date('results_release_time') != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('Results on {p0}', {'p0': fmtDateTime(exam.date('results_release_time'))}), style: TextStyle(color: Theme.of(context).colorScheme.outlineVariant, fontSize: 12)),
              ),
            gap12,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => _openResult(context), child: Text(released ? tr('View my result') : tr('View my submission'))),
                ),
                if (released) ...[
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: tr('Leaderboard'),
                    icon: Icon(Icons.emoji_events_outlined, color: AppColors.warning),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => LeaderboardScreen(examId: exam.str('id'), title: exam.str('title'))),
                    ),
                  ),
                ],
              ],
            ),
          ] else if (open)
            SizedBox(
              width: double.infinity,
              child: BusyButton(
                onPressed: () => _take(context),
                color: isLate ? AppColors.warningDeep : AppColors.successDeep,
                icon: Icons.arrow_forward,
                label: isLate
                    ? tr('Hand in late')
                    : isAssignment
                        ? tr('Open assignment')
                        : minutes > 0
                            ? tr('Start exam ({p0} min)', {'p0': minutes})
                            : tr('Start exam'),
              ),
            )
          else if (upcoming)
            Text(isAssignment ? tr('Questions unlock when the assignment opens.') : tr('Questions unlock when the exam opens.'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))
          else if (missed)
            Text(
              tr('{p0} You did not turn it in.', {'p0': isAssignment ? tr('The deadline has passed.') : tr('This exam has ended.')}),
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
        ],
      ),
    );
  }
}

// ── Homework ─────────────────────────────────────────────────────────────────

enum _HomeworkView { todo, handedIn, checked }

/// Student homework in three parts: still to do (grouped by when it is due),
/// handed in and waiting for the tutor, and checked.
class StudentHomeworkList extends StatefulWidget {
  const StudentHomeworkList({super.key, required this.items, required this.reload, this.showTutor = true});

  /// Name the tutor on each card (off on one tutor's own page).
  final bool showTutor;
  final List<HomeworkItem> items;
  final Future<void> Function() reload;

  @override
  State<StudentHomeworkList> createState() => _StudentHomeworkListState();
}

class _StudentHomeworkListState extends State<StudentHomeworkList> {
  _HomeworkView? _view;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) {
      return PageBody(children: [
        EmptyState(
          icon: Icons.menu_book_outlined,
          title: tr('No homework yet'),
          message: tr('When your tutor sets homework from class, it appears here with a due date.'),
        ),
      ]);
    }
    final now = DateTime.now();
    final todo = items.where((h) => !h.isSubmitted && !h.isEvaluated).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final handedIn = items.where((h) => h.isSubmitted && !h.isEvaluated).toList()..sort((a, b) => b.dueDate.compareTo(a.dueDate));
    final checked = items.where((h) => h.isEvaluated).toList()..sort((a, b) => b.dueDate.compareTo(a.dueDate));
    final view = _view ?? (todo.isNotEmpty ? _HomeworkView.todo : (handedIn.isNotEmpty ? _HomeworkView.handedIn : _HomeworkView.checked));

    Widget card(HomeworkItem hw) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: HomeworkCard(hw: hw, isTutor: false, onChanged: widget.reload, showTutor: widget.showTutor),
        );

    final body = <Widget>[];
    switch (view) {
      case _HomeworkView.todo:
        if (todo.isEmpty) {
          body.add(EmptyState(icon: Icons.task_alt_rounded, title: tr('All done!'), message: tr('Nothing left to hand in.')));
        } else {
          final today = DateTime(now.year, now.month, now.day);
          final groups = <String, List<HomeworkItem>>{};
          for (final hw in todo) {
            final due = hw.dueDate.toLocal();
            final days = DateTime(due.year, due.month, due.day).difference(today).inDays;
            final group = hw.dueDate.isBefore(now)
                ? tr('Overdue')
                : days == 0
                    ? tr('Due today')
                    : days == 1
                        ? tr('Due tomorrow')
                        : days < 7
                            ? tr('This week')
                            : tr('Later');
            groups.putIfAbsent(group, () => []).add(hw);
          }
          for (final entry in groups.entries) {
            body.add(_GroupLabel(entry.key, count: entry.value.length, urgent: entry.key == tr('Overdue')));
            body.addAll(entry.value.map(card));
          }
        }
      case _HomeworkView.handedIn:
        if (handedIn.isEmpty) {
          body.add(EmptyState(icon: Icons.outbox_rounded, title: tr('Nothing waiting'), message: tr('Homework you hand in waits here until your tutor checks it.')));
        } else {
          body.addAll(handedIn.map(card));
        }
      case _HomeworkView.checked:
        if (checked.isEmpty) {
          body.add(EmptyState(icon: Icons.fact_check_outlined, title: tr('Nothing checked yet'), message: tr('Homework your tutor has checked appears here, with any feedback.')));
        } else {
          body.addAll(checked.map(card));
        }
    }

    return PageBody(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        SegmentTabs<_HomeworkView>(
          options: [
            (_HomeworkView.todo, tr('To do'), todo.length),
            (_HomeworkView.handedIn, tr('Handed in'), handedIn.length),
            (_HomeworkView.checked, tr('Checked'), null),
          ],
          selected: view,
          onChanged: (v) => setState(() => _view = v),
        ),
        gap16,
        ...staggered(context, body),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label, {required this.count, this.urgent = false});
  final String label;
  final int count;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final color = urgent ? tone(context, AppColors.danger) : tt.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 10),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: color)),
          const SizedBox(width: 6),
          Text(localDigits('$count'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tt.textTertiary)),
        ],
      ),
    );
  }
}
