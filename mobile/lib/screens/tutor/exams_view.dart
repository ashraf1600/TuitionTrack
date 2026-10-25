import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/charts.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/leaderboard_screen.dart';
import 'exam_editor_screen.dart';
import 'submissions_screen.dart';

class _ExamsData {
  _ExamsData(this.exams, this.tuitions);
  final List<Json> exams;
  final List<Json> tuitions;
}

/// The tutor's exams and assignments — all of them, or one tuition's.
class ExamsView extends StatelessWidget {
  const ExamsView({super.key, this.tuitionId, this.toGradeOnly = false});
  final String? tuitionId;

  /// Only exams with handed-in answers that are not graded yet.
  final bool toGradeOnly;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Loader<_ExamsData>(
      load: () async {
        final results = await Future.wait([repo.exams(tuitionId: tuitionId), repo.tuitions()]);
        return _ExamsData(results[0], results[1]);
      },
      builder: (context, data, reload) {
        if (toGradeOnly) {
          final waiting = data.exams.where((e) => e.integer('submissions_count') > e.integer('graded_count')).toList();
          return PageBody(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (waiting.isEmpty)
                EmptyState(icon: Icons.task_alt_rounded, title: tr('Nothing to grade'), message: tr('Answers handed in for your exams appear here until you grade them.'))
              else
                for (final exam in waiting) ...[_ExamCard(exam: exam, tuitions: data.tuitions, reload: reload), gap12],
            ],
          );
        }
        final drafts = data.exams.where((e) => !e.flag('is_published')).toList();
        final live = data.exams.where((e) => e.flag('is_published') && ['Scheduled', 'Running', 'Late'].contains(e.str('dynamic_status'))).toList();
        final finished = data.exams.where((e) => !drafts.contains(e) && !live.contains(e)).toList();

        Widget group(String title, List<Json> items) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 16, 2, 12),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: title),
                      TextSpan(text: ' · ${localDigits('${items.length}')}', style: TextStyle(fontWeight: FontWeight.w500, color: context.tt.textTertiary)),
                    ]),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.tt.textPrimary),
                  ),
                ),
                for (final exam in items) ...[_ExamCard(exam: exam, tuitions: data.tuitions, reload: reload), gap12],
              ],
            );

        return PageBody(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            if (data.exams.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 12),
                child: EmptyState(
                  icon: Icons.assignment_outlined,
                  title: tr('No exams or assignments yet'),
                  message: tr('Tap “New exam” to set one. You can paste questions straight from ChatGPT, type them, or use pictures.'),
                ),
              )
            else ...[
              if (drafts.isNotEmpty) group(tr('Drafts'), drafts),
              if (live.isNotEmpty) group(tr('Scheduled and running'), live),
              if (finished.isNotEmpty) group(tr('Finished'), finished),
            ],
          ],
        );
      },
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam, required this.tuitions, required this.reload});
  final Json exam;
  final List<Json> tuitions;
  final Future<void> Function() reload;

  String get _id => exam.str('id');

  (String, Color) get _status => switch (exam.str('dynamic_status')) {
        'Draft' => (tr('Draft'), AppColors.faint),
        'Scheduled' => (tr('Scheduled'), AppColors.primarySoft),
        'Running' => (tr('Open now'), AppColors.success),
        'Late' => (tr('Late work open'), AppColors.warning),
        'Submitted' => (tr('Submitted'), AppColors.success),
        'Delayed' => (tr('Submitted late'), AppColors.warning),
        'Missed' => (tr('Not submitted'), AppColors.danger),
        _ => (tr('Closed'), AppColors.faint),
      };

  /// What the results button says and does next, following the exam's publication rule.
  (String, String) get _results {
    if (exam.flag('results_released')) return (tr('Results out'), tr('Students who submitted can see marks and answers. Tap to hide them.'));
    switch (exam.str('result_publish_mode')) {
      case 'IMMEDIATE':
        return ('Results on submit', 'Each student sees their result as soon as they submit. Tap to publish for everyone now.');
      case 'SCHEDULED':
        final when = exam.date('results_release_time');
        return (
          exam.date('publish_time') == null ? 'Results at close' : 'Results ${fmtShortDate(when)} ${fmtTime(when)}',
          'Results come out automatically then. Tap to publish them now.',
        );
    }
    return (tr('Publish results'), tr('Marks and answers are hidden from students. Tap to publish them.'));
  }

  Future<void> _edit(BuildContext context) async {
    final repo = context.read<Repo>();
    Json? detail;
    await attempt(context, () async => detail = await repo.exam(_id));
    if (detail == null || !context.mounted) return;
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ExamEditorScreen(exam: detail)));
    if (changed == true) await reload();
  }

  Future<void> _toggleResults(BuildContext context) async {
    final repo = context.read<Repo>();
    final out = exam.flag('results_released');
    final ok = await confirm(
      context,
      title: out ? tr('Hide the results?') : tr('Publish the results now?'),
      message: out
          ? tr('Students will see "Results pending" for "{p0}" until you publish again.', {'p0': exam.str('title')})
          : tr('Every student who submitted "{p0}" will see their marks, the correct answers and your solutions.', {'p0': exam.str('title')}),
      confirmLabel: out ? tr('Hide results') : tr('Publish results'),
      danger: out,
    );
    if (!ok || !context.mounted) return;
    if (await attempt(context, () => repo.publishResults(_id, !out), success: out ? tr('Results hidden from students.') : tr('Results published.'))) {
      await reload();
    }
  }

  Future<void> _copy(BuildContext context) async {
    final repo = context.read<Repo>();
    final target = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(tr('Copy this exam'), style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr('The copy is a draft dated one week from today. Check the dates, then publish.')),
            ),
            ListTile(leading: const Icon(Icons.copy_outlined), title: Text(tr('For the same students')), onTap: () => Navigator.pop(context, '')),
            for (final t in tuitions.where((t) => t.str('id') != exam.str('tuition_id')))
              ListTile(
                leading: Icon(Icons.groups_outlined),
                title: Text(tr('For {p0}', {'p0': t.str('title')})),
                onTap: () => Navigator.pop(context, t.str('id')),
              ),
          ],
        ),
      ),
    );
    if (target == null || !context.mounted) return;
    if (await attempt(context, () => repo.duplicateExam(_id, tuitionId: target.isEmpty ? null : target), success: tr('Copied as a draft.'))) {
      await reload();
    }
  }

  Future<void> _delete(BuildContext context) async {
    final repo = context.read<Repo>();
    final count = exam.integer('submissions_count');
    final ok = await confirm(
      context,
      title: tr('Delete "{p0}"?', {'p0': exam.str('title')}),
      message: count > 0
          ? tr('{p0} student submission{p1} and their marks will be deleted too. This cannot be undone.', {'p0': count, 'p1': count == 1 ? '' : 's'})
          : tr('This cannot be undone.'),
      confirmLabel: tr('Delete'),
      danger: true,
    );
    if (!ok || !context.mounted) return;
    if (await attempt(context, () => repo.deleteExam(_id), success: tr('Deleted.'))) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    final published = exam.flag('is_published');
    final isAssignment = exam.str('category') == 'ASSIGNMENT';
    final (statusLabel, statusColor) = _status;
    final (resultsLabel, resultsHint) = _results;
    final submitted = exam.integer('submissions_count');
    final graded = exam.integer('graded_count');
    final assigned = exam.numberOrNull('assigned_count')?.toInt();
    final toGrade = submitted - graded;

    final tt = context.tt;
    final start = exam.date('start_time');
    final end = exam.date('end_time');
    final sameDay = start != null && end != null && dayKey(start) == dayKey(end);
    final window = sameDay ? '${fmtDateTime(start)}  →  ${fmtTime(end)}' : '${fmtDateTime(start)}  →  ${fmtDateTime(end)}';
    final menu = PopupMenuButton<String>(
      tooltip: tr('More options'),
      icon: Icon(Icons.more_vert_rounded, color: tt.textTertiary),
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      onSelected: (value) => switch (value) {
        'edit' => _edit(context),
        'copy' => _copy(context),
        'board' => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => LeaderboardScreen(examId: _id, title: exam.str('title'))),
          ),
        _ => _delete(context),
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
        PopupMenuItem(value: 'copy', child: Text(tr('Copy (reuse)'))),
        if (published) PopupMenuItem(value: 'board', child: Text(tr('Leaderboard'))),
        PopupMenuItem(value: 'delete', child: Text(tr('Delete'), style: TextStyle(color: tt.danger))),
      ],
    );

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Pill(isAssignment ? tr('Assignment') : tr('Exam'), color: isAssignment ? AppColors.purple : AppColors.primarySoft),
                      Pill(statusLabel, color: statusColor),
                      if (exam.integer('duration_minutes') > 0 && !isAssignment)
                        Pill(tr('{p0} min', {'p0': exam.integer('duration_minutes')}), icon: Icons.timer_outlined),
                      if (toGrade > 0) Pill(tr('{p0} to grade', {'p0': toGrade}), color: AppColors.warning, icon: Icons.rate_review_outlined),
                    ],
                  ),
                ),
              ),
              menu,
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Text(exam.str('title'), style: TextStyle(fontSize: 17, height: 1.3, fontWeight: FontWeight.w600, color: tt.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  [
                    exam.str('student_name'),
                    tr('{n} marks', {'n': trimNumber(exam.number('total_marks'))}),
                    if (exam.integer('mcq_count') > 0) tr('{n} MCQ', {'n': exam.integer('mcq_count')}),
                  ].where((part) => part.isNotEmpty).join(' · '),
                  style: TextStyle(color: tt.textSecondary, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: tt.border),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 18, color: tt.textTertiary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(window, style: TextStyle(color: tt.textSecondary, fontSize: 14, fontFeatures: tabular)),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: tt.border),
                if (published) ...[
                  const SizedBox(height: 12),
                  Text(
                    tr('{p0}{p1} submitted · {p2} graded', {'p0': submitted, 'p1': assigned != null ? tr(' of {n}', {'n': assigned}) : '', 'p2': graded}),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tt.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  ProgressLine(
                    value: submitted <= 0 ? 0 : graded / submitted,
                    height: 6,
                    label: tr('{p0}{p1} submitted · {p2} graded', {'p0': submitted, 'p1': assigned != null ? tr(' of {n}', {'n': assigned}) : '', 'p2': graded}),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: published
                          ? FilledButton.icon(
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SubmissionsScreen(examId: _id, title: exam.str('title'))));
                                await reload();
                              },
                              icon: const Icon(Icons.fact_check_outlined, size: 18),
                              label: Text(tr('Submissions'), overflow: TextOverflow.ellipsis),
                            )
                          : BusyButton(
                              icon: Icons.send,
                              label: tr('Publish'),
                              onPressed: () async {
                                if (await attempt(context, () => repo.updateExam(_id, {'is_published': true}), success: tr('Published. Students have been notified.'))) {
                                  await reload();
                                }
                              },
                            ),
                    ),
                    if (published) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Tooltip(
                          message: resultsHint,
                          child: FilledButton.tonalIcon(
                            onPressed: () => _toggleResults(context),
                            icon: Icon(
                              exam.flag('results_released') ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            label: Text(resultsLabel, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
