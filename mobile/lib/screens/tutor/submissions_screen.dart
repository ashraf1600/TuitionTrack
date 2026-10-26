import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/mcq_parser.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/math_text.dart';
import '../../widgets/media.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

const _letters = ['A', 'B', 'C', 'D', 'E'];

class _SubmissionsData {
  _SubmissionsData(this.roster, this.exam);
  final Json roster;
  final Json exam;
}

/// Everyone the exam was set for — who has submitted, who is late, who is missing —
/// and the way in to mark each paper.
class SubmissionsScreen extends StatelessWidget {
  const SubmissionsScreen({super.key, required this.examId, required this.title});
  final String examId;
  final String title;

  static (String, Color, IconData) _state(String state) => switch (state) {
        'graded' => (tr('Marked'), AppColors.success, Icons.check_circle),
        'submitted' => (tr('To mark'), AppColors.warning, Icons.rate_review_outlined),
        'late' => (tr('Late — to mark'), AppColors.warning, Icons.rate_review_outlined),
        'in_progress' => (tr('Working on it'), AppColors.primarySoft, Icons.edit_note),
        'missing' => (tr('Did not submit'), AppColors.danger, Icons.cancel_outlined),
        _ => (tr('Not started'), AppColors.faint, Icons.hourglass_empty),
      };

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: Loader<_SubmissionsData>(
        load: () async {
          final results = await Future.wait([repo.submissions(examId), repo.exam(examId)]);
          return _SubmissionsData(results[0], results[1]);
        },
        builder: (context, data, reload) {
          final roster = data.roster.maps('roster');
          final toMark = roster.where((r) => r.str('state') == 'submitted' || r.str('state') == 'late').length;
          return PageBody(
            children: [
              AppCard(
                child: Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    Stat(label: tr('Submitted'), value: tr('{a} of {b}', {'a': data.roster.integer('count'), 'b': data.roster.integer('assigned_count')})),
                    Stat(label: tr('Marked'), value: '${data.roster.integer('graded_count')}', color: AppColors.success),
                    Stat(label: tr('To mark'), value: '$toMark', color: toMark > 0 ? AppColors.warning : Theme.of(context).colorScheme.onSurface),
                  ],
                ),
              ),
              gap8,
              Text(
                data.exam.flag('results_released')
                    ? tr('Results are out: students see marks as soon as you save them.')
                    : switch (data.exam.str('result_publish_mode')) {
                        'IMMEDIATE' => tr('Each student sees their result as soon as they submit.'),
                        'SCHEDULED' => tr('Students see marks when results are published automatically.'),
                        _ => tr('Results are hidden from students until you publish them.'),
                      },
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              gap16,
              if (roster.isEmpty)
                EmptyState(icon: Icons.person_off_outlined, title: tr('Nobody is assigned'), message: tr('Add students to the tuition to set this for them.'))
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < roster.length; i++) ...[
                        if (i > 0) const Divider(),
                        Builder(builder: (context) {
                          final row = roster[i];
                          final submission = row.obj('submission');
                          final (label, color, icon) = _state(row.str('state'));
                          return ListTile(
                            leading: Icon(icon, color: color),
                            title: Text(row.str('student_name'), style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              [
                                label,
                                if (submission?.date('submitted_at') != null) fmtDateTime(submission!.date('submitted_at')),
                                if (row.flag('is_late') && row.str('state') == 'graded') 'late',
                              ].join(' · '),
                              style: TextStyle(color: color, fontSize: 13),
                            ),
                            trailing: submission == null
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (submission.flag('is_graded') && submission.numberOrNull('obtained_marks') != null)
                                        Text(
                                          '${trimNumber(submission.number('obtained_marks'))} / ${trimNumber(data.exam.number('total_marks'))}',
                                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.success),
                                        ),
                                      const Icon(Icons.chevron_right),
                                    ],
                                  ),
                            onTap: submission == null
                                ? null
                                : () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => GradeScreen(exam: data.exam, submission: submission, studentName: row.str('student_name')),
                                      ),
                                    );
                                    await reload();
                                  },
                          );
                        }),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// One student's paper: the auto-marked MCQs, their written answer, and the tutor's marks and feedback.
class GradeScreen extends StatefulWidget {
  const GradeScreen({super.key, required this.exam, required this.submission, required this.studentName});
  final Json exam;
  final Json submission;
  final String studentName;

  @override
  State<GradeScreen> createState() => _GradeScreenState();
}

class _GradeScreenState extends State<GradeScreen> {
  late final _feedback = TextEditingController(text: widget.submission.str('tutor_feedback'));
  late final _written = TextEditingController(
    text: widget.submission.numberOrNull('cq_score') == null ? '' : trimNumber(widget.submission.number('cq_score')),
  );
  late final Map<String, TextEditingController> _perQuestion = {
    for (final item in widget.exam.maps('written_scheme'))
      item.str('id'): TextEditingController(
        text: (widget.submission.obj('cq_breakdown') ?? {})[item.str('id')] == null
            ? ''
            : trimNumber((widget.submission.obj('cq_breakdown') ?? {}).number(item.str('id'))),
      ),
  };
  String? _error;

  Json get exam => widget.exam;
  Json get submission => widget.submission;
  List<Json> get _scheme => exam.maps('written_scheme');
  bool get _hasWritten => exam.str('exam_type') != 'MCQ';
  num get _mcqScore => submission.number('mcq_score');
  num get _writtenTotal => _scheme.isNotEmpty
      ? _perQuestion.values.fold<num>(0, (sum, c) => sum + (num.tryParse(c.text.trim()) ?? 0))
      : (num.tryParse(_written.text.trim()) ?? 0);

  @override
  void dispose() {
    _feedback.dispose();
    _written.dispose();
    for (final controller in _perQuestion.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final repo = context.read<Repo>();
    final payload = <String, dynamic>{'tutor_feedback': _feedback.text.trim()};
    if (_hasWritten) {
      if (_scheme.isNotEmpty) {
        final breakdown = <String, num>{};
        for (final item in _scheme) {
          final text = _perQuestion[item.str('id')]!.text.trim();
          final marks = text.isEmpty ? 0 : num.tryParse(text);
          if (marks == null || marks < 0) {
            setState(() => _error = tr('Enter the marks for "{p0}" as a number.', {'p0': item.str('label')}));
            return;
          }
          if (marks > item.number('marks')) {
            setState(() => _error = tr('"{p0}" is out of {p1}.', {'p0': item.str('label'), 'p1': trimNumber(item.number('marks'))}));
            return;
          }
          breakdown[item.str('id')] = marks;
        }
        payload['cq_breakdown'] = breakdown;
      } else {
        final text = _written.text.trim();
        final marks = text.isEmpty ? 0 : num.tryParse(text);
        if (marks == null || marks < 0) {
          setState(() => _error = tr('Enter the written marks as a number.'));
          return;
        }
        payload['cq_score'] = marks;
      }
      if (_mcqScore + _writtenTotal > exam.number('total_marks')) {
        setState(() => _error = tr('MCQ marks plus written marks come to more than the total of {p0}.', {'p0': trimNumber(exam.number('total_marks'))}));
        return;
      }
    }
    setState(() => _error = null);
    try {
      await repo.grade(submission.str('id'), payload);
      if (!mounted) return;
      showToast(context, tr('Marks saved for {p0}.', {'p0': widget.studentName}));
      Navigator.pop(context);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<Session>().api;
    final answers = submission.obj('answers_data') ?? {};
    final questions = exam.maps('mcq_data');
    final images = submission.strings('image_urls').where(isSafeMedia).toList();
    final paper = exam.str('content_html').trim();
    final hasPaper = _hasWritten && paper.isNotEmpty && paper != '<p></p>' && paper != '<p>Multiple Choice Examination</p>';

    var correctCount = 0;
    final review = <(Json, int?, int?)>[];
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final raw = answers[q.str('id')] ?? answers['mcq_$i'] ?? answers['$i'];
      final chosen = raw == null || '$raw'.isEmpty ? null : correctIndexOf({'correct_answer': '$raw'});
      final correct = correctIndexOf(q);
      if (chosen != null && chosen == correct) correctCount++;
      review.add((q, chosen, correct));
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.studentName, overflow: TextOverflow.ellipsis)),
      body: PageBody(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Pill(tr('Submitted {p0}', {'p0': fmtDateTime(submission.date('submitted_at'))})),
              if (submission.str('status') == 'DELAYED') Pill(tr('Late'), color: AppColors.warning),
              if (submission.date('started_at') != null && submission.date('submitted_at') != null)
                Pill(tr('Took {p0} min', {'p0': submission.date('submitted_at')!.difference(submission.date('started_at')!).inMinutes}), icon: Icons.timer_outlined),
            ],
          ),
          if (questions.isNotEmpty) ...[
            SectionTitle(tr('Multiple choice'), subtitle: tr('{p0} of {p1} correct · {p2} marks (marked automatically)', {'p0': correctCount, 'p1': questions.length, 'p2': trimNumber(_mcqScore)})),
            for (var i = 0; i < review.length; i++) ...[
              Builder(builder: (context) {
                final (q, chosen, correct) = review[i];
                final options = q.strings('options');
                final right = chosen != null && chosen == correct;
                final color = chosen == null
                    ? Theme.of(context).colorScheme.outlineVariant
                    : tone(context, right ? AppColors.success : AppColors.danger);
                String option(int? index) => index == null || index < 0 || index >= options.length ? '' : '${_letters[index]}. ${options[index]}';
                return AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(chosen == null ? Icons.remove_circle_outline : (right ? Icons.check_circle : Icons.cancel), color: color, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MathText('${i + 1}. ${q.str('question')}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (q.str('image_url').isNotEmpty) ...[gap8, ServerImage(q.str('image_url'), height: 140)],
                            SizedBox(height: 4),
                            if (chosen == null)
                              Text(tr('Left blank'),
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.outlineVariant, fontSize: 13))
                            else
                              MathText(tr('Answered: {p0}', {'p0': option(chosen)}), style: TextStyle(color: color, fontSize: 13)),
                            if (!right && correct != null) MathText(tr('Correct: {p0}', {'p0': option(correct)}), style: TextStyle(color: AppColors.success, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
              gap8,
            ],
          ],
          if (_hasWritten) ...[
            SectionTitle(tr('Written part')),
            if (hasPaper)
              AppCard(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  shape: Border(),
                  title: Text(tr('Show the question paper')),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [HtmlMath(paper, baseUrl: api.baseUrl)],
                ),
              ),
            gap8,
            if (submission.str('answer_link').isNotEmpty) ...[
              AnswerLinkCard(submission.str('answer_link')),
              gap12,
            ],
            if (submission.str('text_answer').isEmpty && images.isEmpty && submission.str('answer_link').isEmpty)
              Banner2(tr('This student did not hand in a written answer.'), color: AppColors.warning)
            else ...[
              if (submission.str('text_answer').isNotEmpty) ...[
                Text(tr('Typed answer'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
                gap8,
                AppCard(child: SelectableText(submission.str('text_answer'), style: const TextStyle(height: 1.4))),
                gap12,
              ],
              if (images.isNotEmpty) ...[
                Text(tr('Answer sheets ({p0}) — tap to enlarge', {'p0': images.length}), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
                gap8,
                for (var i = 0; i < images.length; i++) ...[ServerImage(images[i], height: 420, label: tr('Page {p0}', {'p0': i + 1})), gap8],
              ],
            ],
            SectionTitle(tr('Marks for the written part')),
            if (_scheme.isNotEmpty)
              for (final item in _scheme)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(child: Text(item.str('label'), style: const TextStyle(fontWeight: FontWeight.w600))),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _perQuestion[item.str('id')],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(suffixText: '/ ${trimNumber(item.number('marks'))}', hintText: '0'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                )
            else
              TextField(
                controller: _written,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: tr('Written marks'),
                  helperText: tr('Up to {p0} (total {p1} minus {p2} MCQ).', {'p0': trimNumber(exam.number('total_marks') - _mcqScore), 'p1': trimNumber(exam.number('total_marks')), 'p2': trimNumber(_mcqScore)}),
                ),
                onChanged: (_) => setState(() {}),
              ),
          ],
          gap12,
          TextField(
            controller: _feedback,
            maxLines: null,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Feedback for the student (optional)'), alignLabelWithHint: true),
          ),
          gap16,
          AppCard(
            child: Row(
              children: [
                Expanded(child: Text(tr('Total'), style: TextStyle(fontWeight: FontWeight.w700))),
                Text(
                  '${trimNumber(_mcqScore + (_hasWritten ? _writtenTotal : 0))} / ${trimNumber(exam.number('total_marks'))}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.success),
                ),
              ],
            ),
          ),
          if (_error != null) ...[gap12, Banner2(_error!, color: AppColors.danger, icon: Icons.error_outline)],
          gap16,
          BusyButton(onPressed: _save, label: submission.flag('is_graded') ? tr('Update marks') : tr('Save marks'), icon: Icons.check),
        ],
      ),
    );
  }
}
