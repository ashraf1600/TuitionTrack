import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart' show HomeworkItem;
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/leaderboard_screen.dart';
import 'exam_result_screen.dart';
import 'exam_take_screen.dart';
import 'homework_card.dart';

/// Lists a student sees in more than one place: on the home tabs (everything)
/// and inside one tutor's page (only that tutor's work).

// ── Exams ────────────────────────────────────────────────────────────────────

/// A student's exams and assignments, grouped into To do, Upcoming and Done.
class StudentExamsList extends StatelessWidget {
  const StudentExamsList({required this.exams, required this.reload});
  final List<Json> exams;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final now = context.read<Session>().api.serverNow;
    // To do = can be turned in now; Upcoming = not open yet; Done = turned in or over.
    final todo = exams.where((e) => !e.flag('has_submission') && e.flag('can_submit')).toList()
      ..sort((a, b) => (a.date('end_time') ?? now).compareTo(b.date('end_time') ?? now));
    final upcoming = exams
        .where((e) => !e.flag('has_submission') && !e.flag('can_submit') && (e.date('start_time')?.isAfter(now) ?? false))
        .toList()
      ..sort((a, b) => (a.date('start_time') ?? now).compareTo(b.date('start_time') ?? now));
    final done = exams.where((e) => !todo.contains(e) && !upcoming.contains(e)).toList();

    if (exams.isEmpty) {
      return const PageBody(children: [
        EmptyState(
          icon: Icons.assignment_outlined,
          title: 'No exams or assignments yet',
          message: 'When your tutor sets one, it appears here.',
        ),
      ]);
    }
    Widget group(String title, String subtitle, IconData icon, List<Json> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle('$title (${items.length})', subtitle: subtitle, icon: icon),
            for (final exam in items) ...[StudentExamCard(exam: exam, reload: reload), gap12],
          ],
        );
    return PageBody(
      children: [
        if (todo.isNotEmpty) group('To do', 'Open now', Icons.play_circle_outline, todo),
        if (upcoming.isNotEmpty) group('Upcoming', 'Not open yet', Icons.schedule, upcoming),
        if (done.isNotEmpty) group('Done', 'Turned in or finished', Icons.check_circle_outline, done),
      ],
    );
  }
}

class StudentExamCard extends StatelessWidget {
  const StudentExamCard({required this.exam, required this.reload});
  final Json exam;
  final Future<void> Function() reload;

  Future<void> _take(BuildContext context) async {
    final repo = context.read<Repo>();
    final isAssignment = exam.str('category') == 'ASSIGNMENT';
    final minutes = exam.integer('duration_minutes');
    if (minutes > 0 && !isAssignment) {
      final ok = await confirm(
        context,
        title: 'Start the timed exam?',
        message: 'You get $minutes minutes from the moment you start, and the clock keeps running if you leave the app.',
        confirmLabel: 'Start now',
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
      showToast(context, 'Submitted. Here is your result.');
      _openResult(context);
    } else if (status.str('mode') == 'SCHEDULED' && status.date('publish_at') != null) {
      showToast(context, 'Submitted. Results will be published on ${fmtDateTime(status.date('publish_at'))}.');
    } else {
      showToast(context, 'Submitted. Your tutor will publish the results.');
    }
  }

  void _openResult(BuildContext context) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ExamResultScreen(examId: exam.str('id'), title: exam.str('title'))));
  }

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
            children: [
              Pill(isAssignment ? 'Assignment' : 'Exam', color: AppColors.primarySoft),
              if (minutes > 0 && !isAssignment) ...[SizedBox(width: 6), Pill('$minutes min', icon: Icons.timer_outlined)],
              Spacer(),
              Text('${trimNumber(exam.number('total_marks'))} marks', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success)),
            ],
          ),
          gap8,
          Text(exam.str('title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (exam.str('batch_name').isNotEmpty) Text(exam.str('batch_name'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          gap8,
          if (upcoming)
            Text('Opens ${relativeFromNow(start.difference(now))} · ${fmtDateTime(start)}', style: TextStyle(color: AppColors.primarySoft))
          else
            Text('${isAssignment ? 'Due' : 'Ends'} ${fmtDateTime(end)}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          if (open && !isLate) Text('Closes ${relativeFromNow(end.difference(now))}', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
          if (isLate)
            Text(
              lateEnd != null && lateEnd.isAfter(now)
                  ? 'Deadline passed — late work accepted ${relativeFromNow(lateEnd.difference(now)).replaceFirst('in ', 'for ')}'
                  : 'Deadline passed — hand in now',
              style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600),
            ),
          if (!isAssignment && upcoming && negative > 0)
            Text('Wrong MCQ answers lose ${trimNumber(negative)} mark(s).', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          Divider(height: 24),
          if (done) ...[
            Row(
              children: [
                const Icon(Icons.check_circle, size: 18, color: AppColors.success),
                const SizedBox(width: 6),
                Text('Turned in${result?.str('status') == 'DELAYED' ? ' (late)' : ''}'),
                const Spacer(),
                if (released && result?.numberOrNull('obtained_marks') != null)
                  Text(
                    '${trimNumber(result!.number('obtained_marks'))} / ${trimNumber(exam.number('total_marks'))}${result.flag('is_graded') ? '' : ' so far'}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.success),
                  )
                else
                  Pill('Results pending', icon: Icons.hourglass_empty, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ),
            if (!released && exam.str('result_publish_mode') == 'SCHEDULED' && exam.date('results_release_time') != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Results on ${fmtDateTime(exam.date('results_release_time'))}', style: TextStyle(color: Theme.of(context).colorScheme.outlineVariant, fontSize: 12)),
              ),
            gap12,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => _openResult(context), child: Text(released ? 'View my result' : 'View my submission')),
                ),
                if (released) ...[
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Leaderboard',
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
                    ? 'Hand in late'
                    : isAssignment
                        ? 'Open assignment'
                        : minutes > 0
                            ? 'Start exam ($minutes min)'
                            : 'Start exam',
              ),
            )
          else if (upcoming)
            Text('Questions unlock when the ${isAssignment ? 'assignment' : 'exam'} opens.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))
          else if (missed)
            Text(
              '${isAssignment ? 'The deadline has passed.' : 'This exam has ended.'} You did not turn it in.',
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
        ],
      ),
    );
  }
}

// ── Homework ─────────────────────────────────────────────────────────────────

/// Student homework dashboard: pending + done, ordered by due date.
class StudentHomeworkList extends StatelessWidget {
  const StudentHomeworkList({required this.items, required this.reload});
  final List<HomeworkItem> items;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final pending = items.where((h) => !h.isEvaluated).length;
    final dueSoon = items
        .where((h) => !h.isEvaluated && h.dueDate.difference(DateTime.now()).inHours <= 24)
        .length;
    if (items.isEmpty) {
      return const PageBody(children: [
        EmptyState(
          icon: Icons.menu_book_outlined,
          title: 'No homework yet',
          message: 'When your tutor sets homework from class, it appears here with a due date.',
        ),
      ]);
    }
    return PageBody(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (pending > 0)
          AppCard(
            child: Row(
              children: [
                const Icon(Icons.assignment_late_outlined, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$pending pending${dueSoon > 0 ? ' · $dueSoon due within 24 hours' : ''} — newest deadline first.',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        if (pending > 0) gap12,
        for (final hw in items) ...[
          HomeworkCard(hw: hw, isTutor: false, onChanged: reload),
          gap12,
        ],
      ],
    );
  }
}
