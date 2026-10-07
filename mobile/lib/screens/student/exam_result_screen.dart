import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/math_text.dart';
import '../../widgets/media.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/leaderboard_screen.dart';

const _letters = ['A', 'B', 'C', 'D', 'E'];

class _ResultData {
  _ResultData(this.status, this.exam);
  final Json status;

  /// The exam detail (only needed while results are pending, to show what was answered).
  final Json? exam;
}

/// A student's view of an exam they have handed in. The server decides what is
/// shown: "results pending" (its response then contains no marks and no answer
/// key at all) or the fully evaluated paper.
class ExamResultScreen extends StatelessWidget {
  const ExamResultScreen({super.key, required this.examId, required this.title});
  final String examId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: Loader<_ResultData>(
        load: () async {
          final status = await repo.result(examId);
          return _ResultData(status, status.flag('available') ? null : await repo.exam(examId));
        },
        builder: (context, data, reload) => data.status.flag('available')
            ? _Released(result: data.status.obj('result') ?? {}, examId: examId, title: title)
            : _Pending(status: data.status, exam: data.exam ?? {}),
      ),
    );
  }
}

class _AnswerSheets extends StatelessWidget {
  const _AnswerSheets(this.urls);
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    final safe = urls.where(isSafeMedia).toList();
    if (safe.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle('Your answer sheets (${safe.length})'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < safe.length; i++)
              SizedBox(width: 100, child: ServerImage(safe[i], height: 100, fit: BoxFit.cover, label: 'Page ${i + 1}')),
          ],
        ),
      ],
    );
  }
}

/// Before results are out: what the student handed in, with nothing marked right or wrong.
class _Pending extends StatelessWidget {
  const _Pending({required this.status, required this.exam});
  final Json status;
  final Json exam;

  @override
  Widget build(BuildContext context) {
    final submission = exam.obj('submission') ?? {};
    final answers = submission.obj('answers_data') ?? {};
    final questions = exam.maps('mcq_data');
    final publishAt = status.date('publish_at');
    final message = status.str('mode') == 'SCHEDULED' && publishAt != null
        ? 'Results will be published on ${fmtDateTime(publishAt)}.'
        : status.str('mode') == 'IMMEDIATE'
            ? 'Your result is being prepared.'
            : 'Your tutor has not published the results yet.';
    final submittedAt = submission.date('submitted_at') ?? status.date('submitted_at');

    return PageBody(
      children: [
        AppCard(
          borderColor: AppColors.primary.withValues(alpha: 0.4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.hourglass_top_rounded, color: AppColors.primarySoft, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Results pending', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(message),
                    const SizedBox(height: 6),
                    Text(
                      'Your answers are safely handed in${submittedAt != null ? ' (${fmtDateTime(submittedAt)})' : ''}. '
                      'Your marks and the correct answers will appear here when results are out.',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (questions.isNotEmpty) ...[
          const SectionTitle('What you answered'),
          for (var i = 0; i < questions.length; i++) ...[
            Builder(builder: (context) {
              final q = questions[i];
              final raw = answers[q.str('id')] ?? answers['mcq_$i'] ?? answers['$i'];
              final chosen = raw == null || '$raw'.isEmpty ? null : int.tryParse('$raw');
              final options = q.strings('options');
              return AppCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (q.str('question').isNotEmpty) MathText('${i + 1}. ${q.str('question')}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (q.str('image_url').isNotEmpty) ...[gap8, ServerImage(q.str('image_url'), height: 160)],
                    gap8,
                    if (chosen == null || chosen < 0 || chosen >= options.length)
                      const Text('Your answer: left blank', style: TextStyle(color: AppColors.faint, fontSize: 13))
                    else
                      MathText('Your answer: ${_letters[chosen]}. ${options[chosen]}', style: const TextStyle(color: AppColors.primarySoft, fontSize: 13)),
                  ],
                ),
              );
            }),
            gap8,
          ],
        ],
        if (submission.str('text_answer').isNotEmpty) ...[
          const SectionTitle('Your typed answer'),
          AppCard(child: SelectableText(submission.str('text_answer'))),
        ],
        _AnswerSheets(submission.strings('image_urls')),
      ],
    );
  }
}

/// The evaluated paper, once results are released.
class _Released extends StatelessWidget {
  const _Released({required this.result, required this.examId, required this.title});
  final Json result;
  final String examId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final api = context.read<Session>().api;
    final exam = result.obj('exam') ?? {};
    final summary = result.obj('summary') ?? {};
    final questions = result.maps('questions');
    final written = result.obj('written');
    final awaiting = written?.flag('awaiting_marking') ?? false;
    final scheme = written?.maps('scheme') ?? const <Json>[];
    final hasBreakdown = scheme.any((item) => item.numberOrNull('awarded') != null);
    final obtained = result.numberOrNull('obtained_marks');
    final negative = exam.number('negative_marks_per_wrong');

    return PageBody(
      children: [
        AppCard(
          borderColor: AppColors.primary.withValues(alpha: 0.4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.workspace_premium_outlined, color: AppColors.success, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(awaiting ? 'Your score so far' : 'Your score', style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                        if (obtained == null)
                          const Text('Awaiting marking', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primarySoft))
                        else
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(text: trimNumber(obtained), style: const TextStyle(color: AppColors.success)),
                              TextSpan(text: ' / ${trimNumber(exam.number('total_marks'))}'),
                              if (!awaiting && result.numberOrNull('percentage') != null)
                                TextSpan(
                                  text: '  (${trimNumber(result.number('percentage'))}%)',
                                  style: const TextStyle(fontSize: 14, color: AppColors.muted, fontWeight: FontWeight.w600),
                                ),
                            ]),
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              gap12,
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (questions.isNotEmpty) Pill('MCQ ${trimNumber(result.number('mcq_score'))} / ${trimNumber(result.number('mcq_total'))}', color: AppColors.primarySoft),
                  if (written != null)
                    Pill(
                      awaiting ? 'Written: awaiting marking' : 'Written ${trimNumber(result.numberOrNull('cq_score') ?? 0)}',
                      color: awaiting ? AppColors.warning : AppColors.success,
                    ),
                  if (result.str('status') == 'DELAYED') const Pill('Handed in late', color: AppColors.warning),
                ],
              ),
              gap12,
              Row(
                children: [
                  Expanded(
                    child: Text(
                      result.date('submitted_at') == null ? '' : 'Submitted ${fmtDateTime(result.date('submitted_at'))}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => LeaderboardScreen(examId: examId, title: title)),
                    ),
                    icon: const Icon(Icons.emoji_events_outlined, color: AppColors.warning, size: 18),
                    label: const Text('Leaderboard'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (result.str('tutor_feedback').isNotEmpty) ...[
          const SectionTitle('Feedback from your tutor', icon: Icons.chat_bubble_outline),
          AppCard(child: Text(result.str('tutor_feedback'), style: const TextStyle(height: 1.4))),
        ],
        if (questions.isNotEmpty) ...[
          const SectionTitle('Multiple choice — question by question'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Pill('${summary.integer('correct')} correct', color: AppColors.success),
              Pill('${summary.integer('wrong')} wrong', color: AppColors.danger),
              Pill('${summary.integer('skipped')} blank'),
            ],
          ),
          if (negative > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Each wrong answer lost ${trimNumber(negative)} mark(s). Blank answers lost nothing.',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
          gap12,
          for (var i = 0; i < questions.length; i++) ...[_ReviewQuestion(q: questions[i], index: i), gap12],
        ],
        if (written != null) ...[
          const SectionTitle('Written part'),
          if (awaiting) ...[
            const Banner2('Your tutor has not marked the written part yet, so the score above does not include it.', color: AppColors.warning),
            gap12,
          ],
          if (hasBreakdown)
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < scheme.length; i++) ...[
                    if (i > 0) const Divider(),
                    ListTile(
                      dense: true,
                      title: Text(scheme[i].str('label')),
                      trailing: Text(
                        '${scheme[i].numberOrNull('awarded') == null ? '—' : trimNumber(scheme[i].number('awarded'))} / ${trimNumber(scheme[i].number('marks'))}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.success),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (written.str('text_answer').isNotEmpty) ...[
            const SectionTitle('Your typed answer'),
            AppCard(child: SelectableText(written.str('text_answer'))),
          ],
          _AnswerSheets(written.strings('image_urls')),
        ],
        if (result.str('solution_html').isNotEmpty || isSafeMedia(result.str('solution_media_url'))) ...[
          const SectionTitle('Model solution', icon: Icons.menu_book_outlined),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.str('solution_html').isNotEmpty) HtmlMath(_solutionHtml(result.str('solution_html')), baseUrl: api.baseUrl),
                if (isSafeMedia(result.str('solution_media_url'))) ...[
                  gap12,
                  ServerImage(result.str('solution_media_url'), label: 'solution sheet'),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Solutions typed as plain text keep their line breaks.
  static String _solutionHtml(String value) => value.contains('<') ? value : value.replaceAll('\n', '<br>');
}

class _ReviewQuestion extends StatelessWidget {
  const _ReviewQuestion({required this.q, required this.index});
  final Json q;
  final int index;

  @override
  Widget build(BuildContext context) {
    final outcome = q.str('outcome');
    final color = switch (outcome) { 'correct' => AppColors.success, 'wrong' => AppColors.danger, _ => AppColors.faint };
    final icon = switch (outcome) { 'correct' => Icons.check_circle, 'wrong' => Icons.cancel, _ => Icons.remove_circle_outline };
    final awarded = q.number('awarded');
    final correct = q.numberOrNull('correct_answer')?.toInt();
    final selected = q.numberOrNull('selected')?.toInt();
    final options = q.strings('options');

    return AppCard(
      borderColor: color.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22, semanticLabel: switch (outcome) { 'correct' => 'Correct', 'wrong' => 'Wrong', _ => 'Not answered' }),
              const SizedBox(width: 10),
              Expanded(
                child: q.str('question').isEmpty
                    ? Text('Question ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600))
                    : MathText('${index + 1}. ${q.str('question')}', style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4)),
              ),
              const SizedBox(width: 8),
              Pill(
                '${awarded > 0 ? '+' : ''}${trimNumber(awarded)} / ${trimNumber(q.number('points', 1))}',
                color: awarded > 0 ? AppColors.success : (awarded < 0 ? AppColors.danger : AppColors.muted),
              ),
            ],
          ),
          if (q.str('image_url').isNotEmpty) ...[gap8, ServerImage(q.str('image_url'), label: 'Question ${index + 1} picture')],
          gap12,
          for (var i = 0; i < options.length; i++)
            Builder(builder: (context) {
              final isCorrect = correct == i;
              final isChosen = selected == i;
              final tone = isCorrect ? AppColors.success : (isChosen ? AppColors.danger : AppColors.border);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: (isCorrect || isChosen) ? tone.withValues(alpha: 0.13) : null,
                  border: Border.all(color: tone.withValues(alpha: (isCorrect || isChosen) ? 0.5 : 1)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i < _letters.length ? _letters[i] : '${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    const SizedBox(width: 10),
                    Expanded(child: MathText(options[i], style: TextStyle(color: (isCorrect || isChosen) ? AppColors.text : AppColors.muted))),
                    if (isCorrect)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(isChosen ? 'Your answer · correct' : 'Correct answer', style: const TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700)),
                      )
                    else if (isChosen)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text('Your answer', style: TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              );
            }),
          if (outcome == 'skipped') const Text('You left this one blank.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          if (q.str('explanation').isNotEmpty) ...[
            gap8,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.primarySoft),
                const SizedBox(width: 6),
                Expanded(child: MathText('Explanation: ${q.str('explanation')}', style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
