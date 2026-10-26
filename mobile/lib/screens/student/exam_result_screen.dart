import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/math_text.dart';
import '../../widgets/media.dart';
import '../../widgets/student_kit.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/leaderboard_screen.dart';

const _letters = ['A', 'B', 'C', 'D', 'E'];

class _ResultData {
  _ResultData(this.status, this.exam, {this.rank, this.outOf});
  final Json status;

  /// The student's place among everyone who sat it, when the leaderboard is open to them.
  final int? rank;
  final int? outOf;

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
          if (!status.flag('available')) return _ResultData(status, await repo.exam(examId));
          int? rank;
          int? outOf;
          try {
            final board = await repo.leaderboard(examId);
            final rows = board.maps('leaderboard');
            final me = context.mounted ? context.read<Session>().user?.str('id') : null;
            final mine = rows.where((r) => r.str('student_id') == me).firstOrNull;
            if (mine != null && rows.length > 1) {
              rank = mine.integer('rank');
              outOf = rows.length;
            }
          } catch (_) {
            // The ranking is a bonus: the result shows without it.
          }
          return _ResultData(status, null, rank: rank, outOf: outOf);
        },
        builder: (context, data, reload) => data.status.flag('available')
            ? _Released(result: data.status.obj('result') ?? {}, examId: examId, title: title, rank: data.rank, outOf: data.outOf)
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
        SectionTitle(tr('Your answer sheets ({p0})', {'p0': safe.length})),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < safe.length; i++)
              SizedBox(width: 100, child: ServerImage(safe[i], height: 100, fit: BoxFit.cover, label: tr('Page {p0}', {'p0': i + 1}))),
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
        ? tr('Results will be published on {p0}.', {'p0': fmtDateTime(publishAt)})
        : status.str('mode') == 'IMMEDIATE'
            ? tr('Your result is being prepared.')
            : tr('Your tutor has not published the results yet.');
    final submittedAt = submission.date('submitted_at') ?? status.date('submitted_at');

    return PageBody(
      children: [
        AppCard(
          borderColor: AppColors.primary.withValues(alpha: 0.4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.hourglass_top_rounded, color: AppColors.primarySoft, size: 32),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Results pending'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text(message),
                    SizedBox(height: 6),
                    Text(
                      tr('Your answers are safely handed in{p0}. Your marks and the correct answers will appear here when results are out.', {'p0': submittedAt != null ? ' (${fmtDateTime(submittedAt)})' : ''}),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (questions.isNotEmpty) ...[
          SectionTitle(tr('What you answered')),
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
                    if (q.str('question').isNotEmpty) MathText('${i + 1}. ${q.str('question')}', style: TextStyle(fontWeight: FontWeight.w600)),
                    if (q.str('image_url').isNotEmpty) ...[gap8, ServerImage(q.str('image_url'), height: 160)],
                    gap8,
                    if (chosen == null || chosen < 0 || chosen >= options.length)
                      Text(tr('Your answer: left blank'), style: TextStyle(color: Theme.of(context).colorScheme.outlineVariant, fontSize: 13))
                    else
                      MathText(tr('Your answer: {p0}. {p1}', {'p0': _letters[chosen], 'p1': options[chosen]}), style: TextStyle(color: AppColors.primarySoft, fontSize: 13)),
                  ],
                ),
              );
            }),
            gap8,
          ],
        ],
        if (submission.str('answer_link').isNotEmpty) ...[
          SectionTitle(tr('Your written answer')),
          AnswerLinkCard(submission.str('answer_link')),
        ],
        if (submission.str('text_answer').isNotEmpty) ...[
          SectionTitle(tr('Your typed answer')),
          AppCard(child: SelectableText(submission.str('text_answer'))),
        ],
        _AnswerSheets(submission.strings('image_urls')),
      ],
    );
  }
}

/// The evaluated paper, once results are released.
class _Released extends StatelessWidget {
  const _Released({required this.result, required this.examId, required this.title, this.rank, this.outOf});
  final Json result;
  final String examId;
  final String title;
  final int? rank;
  final int? outOf;

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
                  if (!awaiting && result.numberOrNull('percentage') != null)
                    ScoreRing(percent: result.number('percentage').toDouble(), size: 84)
                  else
                    Icon(Icons.workspace_premium_outlined, color: AppColors.success, size: 36),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(awaiting ? tr('Your score so far') : tr('Your score'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
                        if (obtained == null)
                          Text(tr('Awaiting marking'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primarySoft))
                        else
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(text: trimNumber(obtained), style: const TextStyle(color: AppColors.success)),
                              TextSpan(text: ' / ${trimNumber(exam.number('total_marks'))}'),
                              if (!awaiting && result.numberOrNull('percentage') != null)
                                TextSpan(
                                  text: '  (${trimNumber(result.number('percentage'))}%)',
                                  style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                                ),
                            ]),
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
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
                  if (questions.isNotEmpty) Pill(tr('MCQ {p0} / {p1}', {'p0': trimNumber(result.number('mcq_score')), 'p1': trimNumber(result.number('mcq_total'))}), color: AppColors.primarySoft),
                  if (written != null)
                    Pill(
                      awaiting ? tr('Written: awaiting marking') : tr('Written {p0}', {'p0': trimNumber(result.numberOrNull('cq_score') ?? 0)}),
                      color: awaiting ? AppColors.warning : AppColors.success,
                    ),
                  if (result.str('status') == 'DELAYED') Pill(tr('Handed in late'), color: AppColors.warning),
                  if (rank != null && outOf != null)
                    Pill(tr('Rank {p0} of {p1}', {'p0': rank, 'p1': outOf}), color: AppColors.warning, icon: Icons.emoji_events_outlined),
                ],
              ),
              gap12,
              Row(
                children: [
                  Expanded(
                    child: Text(
                      result.date('submitted_at') == null ? '' : tr('Submitted {p0}', {'p0': fmtDateTime(result.date('submitted_at'))}),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => LeaderboardScreen(examId: examId, title: title)),
                    ),
                    icon: const Icon(Icons.emoji_events_outlined, color: AppColors.warning, size: 18),
                    label: Text(tr('Leaderboard')),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (result.str('tutor_feedback').isNotEmpty) ...[
          SectionTitle(tr('Feedback from your tutor'), icon: Icons.chat_bubble_outline),
          AppCard(child: Text(result.str('tutor_feedback'), style: const TextStyle(height: 1.4))),
        ],
        if (questions.isNotEmpty) ...[
          SectionTitle(tr('Multiple choice — question by question')),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Pill(tr('{p0} correct', {'p0': summary.integer('correct')}), color: AppColors.success),
              Pill(tr('{p0} wrong', {'p0': summary.integer('wrong')}), color: AppColors.danger),
              Pill(tr('{p0} blank', {'p0': summary.integer('skipped')})),
            ],
          ),
          if (negative > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                tr('Each wrong answer lost {p0} mark(s). Blank answers lost nothing.', {'p0': trimNumber(negative)}),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
          gap12,
          _QuestionReview(questions: questions),
        ],
        if (written != null) ...[
          SectionTitle(tr('Written part')),
          if (awaiting) ...[
            Banner2(tr('Your tutor has not marked the written part yet, so the score above does not include it.'), color: AppColors.warning),
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
          if (written.str('answer_link').isNotEmpty) ...[
            SectionTitle(tr('Your written answer')),
            AnswerLinkCard(written.str('answer_link')),
          ],
          if (written.str('text_answer').isNotEmpty) ...[
            SectionTitle(tr('Your typed answer')),
            AppCard(child: SelectableText(written.str('text_answer'))),
          ],
          _AnswerSheets(written.strings('image_urls')),
        ],
        if (result.str('solution_html').isNotEmpty || isSafeMedia(result.str('solution_media_url'))) ...[
          SectionTitle(tr('Model solution'), icon: Icons.menu_book_outlined),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.str('solution_html').isNotEmpty) HtmlMath(_solutionHtml(result.str('solution_html')), baseUrl: api.baseUrl),
                if (isSafeMedia(result.str('solution_media_url'))) ...[
                  gap12,
                  ServerImage(result.str('solution_media_url'), label: tr('solution sheet')),
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
    final color = switch (outcome) { 'correct' => AppColors.success, 'wrong' => AppColors.danger, _ => Theme.of(context).colorScheme.outlineVariant };
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
              Icon(icon, color: color, size: 22, semanticLabel: switch (outcome) { 'correct' => tr('Correct'), 'wrong' => tr('Wrong'), _ => tr('Not answered') }),
              SizedBox(width: 10),
              Expanded(
                child: q.str('question').isEmpty
                    ? Text(tr('Question {p0}', {'p0': index + 1}), style: TextStyle(fontWeight: FontWeight.w600))
                    : MathText('${index + 1}. ${q.str('question')}', style: TextStyle(fontWeight: FontWeight.w600, height: 1.4)),
              ),
              SizedBox(width: 8),
              Pill(
                '${awarded > 0 ? '+' : ''}${trimNumber(awarded)} / ${trimNumber(q.number('points', 1))}',
                color: awarded > 0 ? AppColors.success : (awarded < 0 ? AppColors.danger : Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          if (q.str('image_url').isNotEmpty) ...[gap8, ServerImage(q.str('image_url'), label: tr('Question {p0} picture', {'p0': index + 1}))],
          gap12,
          for (var i = 0; i < options.length; i++)
            Builder(builder: (context) {
              final isCorrect = correct == i;
              final isChosen = selected == i;
              final mark = isCorrect
                  ? tone(context, AppColors.success)
                  : (isChosen ? tone(context, AppColors.danger) : Theme.of(context).colorScheme.outline);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: (isCorrect || isChosen) ? mark.withValues(alpha: 0.13) : null,
                  border: Border.all(color: mark.withValues(alpha: (isCorrect || isChosen) ? 0.5 : 1)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i < _letters.length ? _letters[i] : '${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    const SizedBox(width: 10),
                    Expanded(child: MathText(options[i], style: TextStyle(color: (isCorrect || isChosen) ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant))),
                    if (isCorrect)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(isChosen ? tr('Your answer · correct') : tr('Correct answer'), style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700)),
                      )
                    else if (isChosen)
                      Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text(tr('Your answer'), style: TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              );
            }),
          if (outcome == 'skipped') Text(tr('You left this one blank.'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          if (q.str('explanation').isNotEmpty) ...[
            gap8,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, size: 16, color: AppColors.primarySoft),
                SizedBox(width: 6),
                Expanded(child: MathText(tr('Explanation: {p0}', {'p0': q.str('explanation')}), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, height: 1.4))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


/// Every MCQ with the right answer, or only the ones to revise (wrong or left blank).
class _QuestionReview extends StatefulWidget {
  const _QuestionReview({required this.questions});
  final List<Json> questions;

  @override
  State<_QuestionReview> createState() => _QuestionReviewState();
}

class _QuestionReviewState extends State<_QuestionReview> {
  bool _onlyMistakes = false;

  @override
  Widget build(BuildContext context) {
    final mistakes = [
      for (var i = 0; i < widget.questions.length; i++)
        if (widget.questions[i].str('outcome') != 'correct') i,
    ];
    final shown = _onlyMistakes ? mistakes : [for (var i = 0; i < widget.questions.length; i++) i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mistakes.isNotEmpty) ...[
          PillToggle<bool>(
            options: [(false, tr('All questions'), null), (true, tr('To revise ({p0})', {'p0': mistakes.length}), null)],
            selected: _onlyMistakes,
            onChanged: (value) => setState(() => _onlyMistakes = value),
          ),
          gap12,
        ],
        for (final i in shown) ...[_ReviewQuestion(q: widget.questions[i], index: i), gap12],
      ],
    );
  }
}
