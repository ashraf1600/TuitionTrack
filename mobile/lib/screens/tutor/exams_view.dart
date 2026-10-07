import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
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

/// The tutor's exams and assignments — all of them, or one group's.
class ExamsView extends StatelessWidget {
  const ExamsView({super.key, this.tuitionId});
  final String? tuitionId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Loader<_ExamsData>(
      load: () async {
        final results = await Future.wait([repo.exams(tuitionId: tuitionId), repo.tuitions()]);
        return _ExamsData(results[0], results[1]);
      },
      builder: (context, data, reload) {
        final drafts = data.exams.where((e) => !e.flag('is_published')).toList();
        final live = data.exams.where((e) => e.flag('is_published') && ['Scheduled', 'Running', 'Late'].contains(e.str('dynamic_status'))).toList();
        final finished = data.exams.where((e) => !drafts.contains(e) && !live.contains(e)).toList();

        Widget group(String title, List<Json> items) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle('$title (${items.length})'),
                for (final exam in items) ...[_ExamCard(exam: exam, tuitions: data.tuitions, reload: reload), gap12],
              ],
            );

        return PageBody(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            if (data.exams.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: EmptyState(
                  icon: Icons.assignment_outlined,
                  title: 'No exams or assignments yet',
                  message: 'Tap “New exam” to set one. You can paste questions straight from ChatGPT, type them, or use pictures.',
                ),
              )
            else ...[
              if (drafts.isNotEmpty) group('Drafts', drafts),
              if (live.isNotEmpty) group('Scheduled and running', live),
              if (finished.isNotEmpty) group('Finished', finished),
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
        'Draft' => ('Draft', AppColors.muted),
        'Scheduled' => ('Scheduled', AppColors.primarySoft),
        'Running' => ('Open now', AppColors.success),
        'Late' => ('Late work open', AppColors.warning),
        'Submitted' => ('Submitted', AppColors.success),
        'Delayed' => ('Submitted late', AppColors.warning),
        'Missed' => ('Not submitted', AppColors.danger),
        _ => ('Closed', AppColors.muted),
      };

  /// What the results button says and does next, following the exam's publication rule.
  (String, String) get _results {
    if (exam.flag('results_released')) return ('Results out', 'Students who submitted can see marks and answers. Tap to hide them.');
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
    return ('Publish results', 'Marks and answers are hidden from students. Tap to publish them.');
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
      title: out ? 'Hide the results?' : 'Publish the results now?',
      message: out
          ? 'Students will see "Results pending" for "${exam.str('title')}" until you publish again.'
          : 'Every student who submitted "${exam.str('title')}" will see their marks, the correct answers and your solutions.',
      confirmLabel: out ? 'Hide results' : 'Publish results',
      danger: out,
    );
    if (!ok || !context.mounted) return;
    if (await attempt(context, () => repo.publishResults(_id, !out), success: out ? 'Results hidden from students.' : 'Results published.')) {
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
            const ListTile(
              title: Text('Copy this exam', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('The copy is a draft dated one week from today. Check the dates, then publish.'),
            ),
            ListTile(leading: const Icon(Icons.copy_outlined), title: const Text('For the same students'), onTap: () => Navigator.pop(context, '')),
            for (final t in tuitions.where((t) => t.str('id') != exam.str('tuition_id')))
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text('For ${t.str('title')}'),
                onTap: () => Navigator.pop(context, t.str('id')),
              ),
          ],
        ),
      ),
    );
    if (target == null || !context.mounted) return;
    if (await attempt(context, () => repo.duplicateExam(_id, tuitionId: target.isEmpty ? null : target), success: 'Copied as a draft.')) {
      await reload();
    }
  }

  Future<void> _delete(BuildContext context) async {
    final repo = context.read<Repo>();
    final count = exam.integer('submissions_count');
    final ok = await confirm(
      context,
      title: 'Delete "${exam.str('title')}"?',
      message: count > 0
          ? '$count student submission${count == 1 ? '' : 's'} and their marks will be deleted too. This cannot be undone.'
          : 'This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    if (await attempt(context, () => repo.deleteExam(_id), success: 'Deleted.')) await reload();
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

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill(isAssignment ? 'Assignment' : 'Exam', color: isAssignment ? AppColors.purple : AppColors.primarySoft),
              Pill(statusLabel, color: statusColor),
              if (exam.integer('duration_minutes') > 0 && !isAssignment) Pill('${exam.integer('duration_minutes')} min', icon: Icons.timer_outlined),
              if (toGrade > 0) Pill('$toGrade to grade', color: AppColors.warning, icon: Icons.rate_review_outlined),
            ],
          ),
          gap8,
          Text(exam.str('title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(
            [
              exam.str('student_name'),
              '${trimNumber(exam.number('total_marks'))} marks',
              if (exam.integer('mcq_count') > 0) '${exam.integer('mcq_count')} MCQ',
            ].join(' · '),
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '${fmtDateTime(exam.date('start_time'))}  →  ${fmtDateTime(exam.date('end_time'))}',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          if (published)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$submitted${assigned != null ? ' of $assigned' : ''} submitted · $graded graded',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          gap12,
          Row(
            children: [
              Expanded(
                child: published
                    ? FilledButton.tonalIcon(
                        onPressed: () async {
                          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SubmissionsScreen(examId: _id, title: exam.str('title'))));
                          await reload();
                        },
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: const Text('Submissions'),
                      )
                    : BusyButton(
                        icon: Icons.send,
                        label: 'Publish',
                        onPressed: () async {
                          if (await attempt(context, () => repo.updateExam(_id, {'is_published': true}), success: 'Published. Students have been notified.')) {
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
                    child: OutlinedButton.icon(
                      onPressed: () => _toggleResults(context),
                      icon: Icon(
                        exam.flag('results_released') ? Icons.visibility : Icons.visibility_off_outlined,
                        size: 18,
                        color: exam.flag('results_released') ? AppColors.success : null,
                      ),
                      label: Text(resultsLabel, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
              ],
              PopupMenuButton<String>(
                tooltip: 'More options',
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
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'copy', child: Text('Copy (reuse)')),
                  if (published) const PopupMenuItem(value: 'board', child: Text('Leaderboard')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.danger))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
