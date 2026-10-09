import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/mcq_parser.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/math_text.dart';
import '../../widgets/media.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import 'mcq_builder.dart';

class _SchemeRow {
  _SchemeRow({this.id, String label = '', String marks = '5'})
      : label = TextEditingController(text: label),
        marks = TextEditingController(text: marks);
  final String? id;
  final TextEditingController label;
  final TextEditingController marks;

  void dispose() {
    label.dispose();
    marks.dispose();
  }
}

Future<DateTime?> pickDateTime(BuildContext context, DateTime initial, {String? help}) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime.now().subtract(const Duration(days: 366)),
    lastDate: DateTime.now().add(const Duration(days: 730)),
    helpText: help,
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial), helpText: help);
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Create an exam or assignment, or edit one. Pops with `true` when saved.
class ExamEditorScreen extends StatefulWidget {
  const ExamEditorScreen({super.key, this.exam, this.initialTuitionId});

  /// Full exam detail (tutor view) to edit; null to create a new one.
  final Json? exam;
  final String? initialTuitionId;

  @override
  State<ExamEditorScreen> createState() => _ExamEditorScreenState();
}

class _ExamEditorScreenState extends State<ExamEditorScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final _title = TextEditingController();
  final _written = TextEditingController();
  final _totalMarks = TextEditingController(text: '100');
  final _duration = TextEditingController();
  final _grace = TextEditingController(text: '5');
  final _negative = TextEditingController(text: '0');
  final _solution = TextEditingController();
  final List<_SchemeRow> _scheme = [];

  String _category = 'EXAM';
  String _type = 'HYBRID';
  bool _forGroup = true;
  String? _tuitionId;
  String? _studentId;
  List<Json> _tuitions = const [];
  List<Json> _students = const [];
  List<Json> _mcq = [];
  // A paper formatted on the website (tables, bold…) is kept untouched unless the tutor rewrites it here.
  bool _keepPaper = false;
  String _originalHtml = '';
  late DateTime _start = _roundUp(DateTime.now().add(const Duration(minutes: 10)));
  late DateTime _end = _start.add(const Duration(hours: 1));
  DateTime? _lateUntil;
  bool _shuffle = false;
  String _resultsMode = 'MANUAL'; // IMMEDIATE | CLOSE | TIME | MANUAL  (CLOSE and TIME are the server's SCHEDULED)
  DateTime? _resultsAt;
  String _solutionMedia = '';
  bool _saving = false;
  String? _error;

  bool get _editing => widget.exam != null;
  bool get _wasPublished => widget.exam?.flag('is_published') ?? false;

  static DateTime _roundUp(DateTime value) => DateTime(value.year, value.month, value.day, value.hour, value.minute - value.minute % 5 + 5);

  @override
  void initState() {
    super.initState();
    _tuitionId = widget.initialTuitionId;
    final exam = widget.exam;
    if (exam != null) {
      _title.text = exam.str('title');
      _category = exam.str('category', 'EXAM');
      _type = exam.str('exam_type') == 'MIXED' ? 'HYBRID' : exam.str('exam_type', 'HYBRID');
      _forGroup = exam.str('tuition_id').isNotEmpty;
      _tuitionId = exam.str('tuition_id').isEmpty ? null : exam.str('tuition_id');
      _studentId = exam.str('student').isEmpty ? null : exam.str('student');
      _totalMarks.text = trimNumber(exam.number('total_marks', 100));
      _duration.text = exam.integer('duration_minutes') > 0 ? '${exam.integer('duration_minutes')}' : '';
      _grace.text = '${exam.integer('grace_period_minutes', 5)}';
      _negative.text = trimNumber(exam.number('negative_marks_per_wrong'));
      _lateUntil = exam.date('late_submission_until');
      _shuffle = exam.flag('shuffle_questions');
      _start = exam.date('start_time') ?? _start;
      _end = exam.date('end_time') ?? _end;
      _mcq = [
        for (final q in exam.maps('mcq_data')) {...q, 'points': q.number('points', q.number('marks', 1))},
      ];
      for (final row in exam.maps('written_scheme')) {
        _scheme.add(_SchemeRow(id: row.str('id'), label: row.str('label'), marks: trimNumber(row.number('marks'))));
      }
      _solution.text = htmlToPlainText(exam.str('solution_html')).text;
      _solutionMedia = exam.str('solution_media_url');
      _resultsMode = exam.str('result_publish_mode') == 'SCHEDULED'
          ? (exam.date('publish_time') == null ? 'CLOSE' : 'TIME')
          : exam.str('result_publish_mode', 'MANUAL');
      _resultsAt = exam.date('publish_time');
      if (_type != 'MCQ') {
        _originalHtml = exam.str('content_html');
        final editable = htmlToPlainText(_originalHtml);
        _keepPaper = editable.lossy;
        _written.text = editable.text;
      }
    }
    _written.addListener(() => setState(() {}));
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    final repo = context.read<Repo>();
    try {
      final results = await Future.wait([repo.tuitions(), repo.students()]);
      if (!mounted) return;
      setState(() {
        _tuitions = results[0];
        _students = results[1].where((s) => s.flag('is_active')).toList();
        _tuitionId ??= _tuitions.isNotEmpty ? _tuitions.first.str('id') : null;
        if (_tuitions.isEmpty && !_editing) _forGroup = false;
      });
    } on ApiException catch (error) {
      if (mounted) showToast(context, error.message, error: true);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_title, _written, _totalMarks, _duration, _grace, _negative, _solution]) {
      c.dispose();
    }
    for (final row in _scheme) {
      row.dispose();
    }
    super.dispose();
  }

  num get _mcqTotal => _type == 'CQ' ? 0 : _mcq.fold<num>(0, (sum, q) => sum + q.number('points', 1));
  num get _writtenTotal => _type == 'MCQ' ? 0 : _scheme.fold<num>(0, (sum, row) => sum + (num.tryParse(row.marks.text.trim()) ?? 0));

  bool _fail(String message, int tab) {
    setState(() => _error = message);
    _tabs.animateTo(tab);
    return false;
  }

  bool _validate(bool publish) {
    final total = num.tryParse(_totalMarks.text.trim());
    if (_title.text.trim().isEmpty) return _fail('Give the exam a title.', 0);
    if (_forGroup && _tuitionId == null) return _fail('Choose the group this is for.', 0);
    if (!_forGroup && _studentId == null) return _fail('Choose the student this is for.', 0);
    if (total == null || total <= 0) return _fail('Enter the total marks.', 2);
    if (!_end.isAfter(_start)) return _fail('The end time must be after the start time.', 2);
    if (!_editing && !_end.isAfter(DateTime.now())) return _fail('The end time is already in the past.', 2);
    if (_lateUntil != null && !_lateUntil!.isAfter(_end)) return _fail('"Accept late work until" must be after the deadline.', 2);
    if (_type != 'MCQ' && _scheme.any((row) => (num.tryParse(row.marks.text.trim()) ?? 0) <= 0)) {
      return _fail('Every written question in the marking scheme needs marks above 0.', 1);
    }
    if (_mcqTotal + _writtenTotal > total) {
      return _fail(
        'MCQ marks (${trimNumber(_mcqTotal)}) plus written marks (${trimNumber(_writtenTotal)}) come to more than the total of ${trimNumber(total)}.',
        2,
      );
    }
    if (publish && _type == 'MCQ' && _mcq.isEmpty) return _fail('Add at least one question, or change the type to written.', 1);
    if (publish && _type != 'CQ') {
      final unfinished = _mcq.indexWhere((q) => questionProblems(q).isNotEmpty);
      if (unfinished != -1) {
        return _fail(
          'Question ${unfinished + 1} is not ready: ${questionProblems(_mcq[unfinished]).first.toLowerCase()}. You can still save it as a draft.',
          1,
        );
      }
    }
    if (publish && _type == 'CQ' && !_keepPaper && _written.text.trim().isEmpty) return _fail('The written paper is empty.', 1);
    if (_resultsMode == 'TIME') {
      if (_resultsAt == null) return _fail('Choose the date and time when results should be published.', 3);
      if (!_resultsAt!.isAfter(_start)) return _fail('Results cannot be published before the exam starts.', 3);
    }
    return true;
  }

  Future<void> _save(bool publish) async {
    if (_saving || !_validate(publish)) return;
    final repo = context.read<Repo>();
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = <String, dynamic>{
      'title': _title.text.trim(),
      'category': _category,
      'exam_type': _type,
      'student_id': _forGroup ? null : _studentId,
      'tuition_id': _forGroup ? _tuitionId : null,
      'content_html': _type == 'MCQ' ? '<p>Multiple Choice Examination</p>' : (_keepPaper ? _originalHtml : plainTextToHtml(_written.text)),
      'mcq_data': _type == 'CQ' ? <Json>[] : _mcq,
      'written_scheme': _type == 'MCQ'
          ? <Json>[]
          : [
              for (final row in _scheme)
                {'id': ?row.id, 'label': row.label.text.trim(), 'marks': num.tryParse(row.marks.text.trim()) ?? 0},
            ],
      'solution_html': plainTextToHtml(_solution.text),
      'solution_media_url': _solutionMedia,
      'total_marks': num.tryParse(_totalMarks.text.trim()) ?? 100,
      'start_time': _start.toUtc().toIso8601String(),
      'end_time': _end.toUtc().toIso8601String(),
      'duration_minutes': _category == 'EXAM' ? int.tryParse(_duration.text.trim()) : null,
      'grace_period_minutes': int.tryParse(_grace.text.trim()) ?? 5,
      'late_submission_until': _lateUntil?.toUtc().toIso8601String(),
      'shuffle_questions': _type != 'CQ' && _shuffle,
      'negative_marks_per_wrong': _type == 'CQ' ? 0 : (num.tryParse(_negative.text.trim()) ?? 0),
      'is_published': publish,
      'result_publish_mode': (_resultsMode == 'CLOSE' || _resultsMode == 'TIME') ? 'SCHEDULED' : _resultsMode,
      'publish_time': _resultsMode == 'TIME' ? _resultsAt!.toUtc().toIso8601String() : null,
    };
    try {
      _editing ? await repo.updateExam(widget.exam!.str('id'), payload) : await repo.createExam(payload);
      if (!mounted) return;
      showToast(
        context,
        _editing
            ? (publish ? 'Changes saved.' : 'Saved as a draft — students cannot see it.')
            : (publish ? 'Published. Students have been notified.' : 'Draft saved — publish it when you are ready.'),
      );
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.message;
        });
      }
    }
  }

  Future<void> _pasteWritten() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Paste written questions'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Numbered questions are kept apart and maths stays as written. If every question ends with its marks — [10] or (5 marks) — '
                'the marking scheme is filled in too.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              gap12,
              TextField(
                controller: controller,
                maxLines: 8,
                autofocus: true,
                autocorrect: false,
                style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(hintText: '1. A particle moves with velocity \\(v(t) = 3t^2 - 4t\\). Find its acceleration at t = 2 s. [5]'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Add to the paper')),
        ],
      ),
    );
    if (text == null || !mounted) return;
    final items = parseWrittenQuestions(text);
    if (items.isEmpty) {
      showToast(context, 'No questions found in that text.', error: true);
      return;
    }
    final blocks = items.map((q) => '${q.label}. ${q.text}${q.marks != null ? ' [${trimNumber(q.marks)}]' : ''}').join('\n\n');
    setState(() {
      _written.text = _written.text.trim().isEmpty ? blocks : '${_written.text.trimRight()}\n\n$blocks';
      if (items.every((q) => (q.marks ?? 0) > 0)) {
        _scheme.addAll(items.map((q) => _SchemeRow(label: q.label, marks: trimNumber(q.marks))));
      }
    });
    showToast(context, 'Added ${items.length} written question${items.length == 1 ? '' : 's'}.');
  }

  // ── Tabs ───────────────────────────────────────────────────────────────────

  Widget _detailsTab() {
    return PageBody(
      children: [
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Chapter 3 quiz — Polynomials'),
        ),
        gap16,
        Text('What is it?', style: TextStyle(fontWeight: FontWeight.w700)),
        gap8,
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'EXAM', label: Text('Timed exam'), icon: Icon(Icons.timer_outlined)),
            ButtonSegment(value: 'ASSIGNMENT', label: Text('Assignment'), icon: Icon(Icons.home_work_outlined)),
          ],
          selected: {_category},
          onSelectionChanged: (value) => setState(() => _category = value.first),
        ),
        gap8,
        Text(
          _category == 'EXAM' ? 'Sat between a start and an end time, with an optional time limit per student.' : 'Homework with a deadline. No stopwatch.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
        ),
        gap16,
        Text('Question types', style: TextStyle(fontWeight: FontWeight.w700)),
        gap8,
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'HYBRID', label: Text('Both')),
            ButtonSegment(value: 'MCQ', label: Text('MCQ only')),
            ButtonSegment(value: 'CQ', label: Text('Written only')),
          ],
          selected: {_type},
          showSelectedIcon: false,
          onSelectionChanged: (value) => setState(() => _type = value.first),
        ),
        gap8,
        Text(
          switch (_type) {
            'MCQ' => 'Multiple choice only — marked automatically.',
            'CQ' => 'Written (creative) questions only — you mark them.',
            _ => 'Multiple choice (marked automatically) plus written questions (you mark them).',
          },
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
        ),
        gap16,
        const Text('Who is it for?', style: TextStyle(fontWeight: FontWeight.w700)),
        gap8,
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('A tuition group'), icon: Icon(Icons.groups_outlined)),
            ButtonSegment(value: false, label: Text('One student'), icon: Icon(Icons.person_outline)),
          ],
          selected: {_forGroup},
          onSelectionChanged: (value) => setState(() => _forGroup = value.first),
        ),
        gap12,
        if (_forGroup)
          _tuitions.isEmpty
              ? const Text('You have no tuition groups yet. Create one first, or choose one student.', style: TextStyle(color: AppColors.warning))
              : DropdownButtonFormField<String>(
                  key: ValueKey('group-$_tuitionId-${_tuitions.length}'),
                  initialValue: _tuitions.any((t) => t.str('id') == _tuitionId) ? _tuitionId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tuition group'),
                  items: [
                    for (final t in _tuitions)
                      DropdownMenuItem(value: t.str('id'), child: Text('${t.str('title')} (${t.integer('enrolled_count')} student${t.integer('enrolled_count') == 1 ? '' : 's'})', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (value) => setState(() => _tuitionId = value),
                )
        else
          _students.isEmpty
              ? const Text('You have no active students yet.', style: TextStyle(color: AppColors.warning))
              : DropdownButtonFormField<String>(
                  key: ValueKey('student-$_studentId-${_students.length}'),
                  initialValue: _students.any((s) => s.str('id') == _studentId) ? _studentId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Student'),
                  items: [
                    for (final s in _students)
                      DropdownMenuItem(value: s.str('id'), child: Text('${s.str('full_name')} (@${s.str('username')})', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (value) => setState(() => _studentId = value),
                ),
        gap24,
        OutlinedButton.icon(
          onPressed: () => _tabs.animateTo(1),
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Next: questions'),
        ),
      ],
    );
  }

  Widget _questionsTab() {
    final api = context.read<Session>().api;
    final total = num.tryParse(_totalMarks.text.trim()) ?? 0;
    final allocated = _mcqTotal + _writtenTotal;
    final preview = plainTextToHtml(_written.text);
    final needsPreview = _written.text.contains(r'$') || _written.text.contains(r'\') || _written.text.contains('[picture:');
    return PageBody(
      children: [
        if (_type != 'CQ') McqBuilder(questions: _mcq, onChanged: (value) => setState(() => _mcq = value)),
        if (_type != 'MCQ') ...[
          gap8,
          const SectionTitle('Written questions', subtitle: 'Students type their answer or upload photos of their handwriting.'),
          if (_keepPaper) ...[
            const Banner2(
              'This paper was formatted on the website (tables, bold or lists). It is kept exactly as it is. '
              'Rewriting it here keeps the text and pictures but drops that formatting.',
            ),
            gap8,
            AppCard(child: HtmlMath(_originalHtml, baseUrl: api.baseUrl)),
            TextButton.icon(
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: 'Rewrite the paper here?',
                  message: 'The text and pictures are kept. Tables, bold text and lists become plain paragraphs.',
                  confirmLabel: 'Rewrite',
                );
                if (ok) setState(() => _keepPaper = false);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Rewrite on this phone'),
            ),
          ] else ...[
            TextField(
              controller: _written,
              maxLines: null,
              minLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Q1. Prove that …\n\nQ2. Evaluate \$\$\\int_0^1 x^2\\,dx\$\$',
                helperText: 'Leave a blank line between questions. Maths works as \$x^2\$, \\(x_1\\) or \$\$…\$\$.',
                alignLabelWithHint: true,
              ),
            ),
            gap8,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(onPressed: _pasteWritten, icon: const Icon(Icons.content_paste, size: 18), label: const Text('Paste questions')),
                OutlinedButton.icon(
                  onPressed: () async {
                    final urls = await pickAndUpload(context);
                    if (urls.isEmpty) return;
                    setState(() => _written.text = '${_written.text.trimRight()}\n\n${urls.map((u) => '[picture: $u]').join('\n\n')}\n\n'.trimLeft());
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: const Text('Add a picture'),
                ),
              ],
            ),
            if (needsPreview && preview.isNotEmpty) ...[
              gap12,
              AppCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Students will see', style: TextStyle(color: Theme.of(context).colorScheme.outlineVariant, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    HtmlMath(preview, baseUrl: api.baseUrl),
                  ],
                ),
              ),
            ],
          ],
          SectionTitle(
            'Marks per written question',
            subtitle: 'Optional. List each question and its marks to mark them one by one. Leave empty to give one overall written mark.',
            trailing: TextButton.icon(
              onPressed: () => setState(() => _scheme.add(_SchemeRow(label: 'Q${_scheme.length + 1}'))),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ),
          for (var i = 0; i < _scheme.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _scheme[i].label,
                      maxLength: 120,
                      decoration: InputDecoration(labelText: 'Question ${i + 1}', hintText: 'e.g. Q1 (a)', counterText: ''),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _scheme[i].marks,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Marks'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove written question ${i + 1}',
                    icon: Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _scheme.removeAt(i).dispose()),
                  ),
                ],
              ),
            ),
        ],
        gap12,
        Text(
          'Marks set so far: ${trimNumber(_mcqTotal)} MCQ${_type != 'MCQ' && _scheme.isNotEmpty ? ' + ${trimNumber(_writtenTotal)} written' : ''}'
          ' = ${trimNumber(allocated)} of ${trimNumber(total)} total.',
          style: TextStyle(color: allocated > total ? AppColors.danger : Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: allocated > total ? FontWeight.w700 : null),
        ),
      ],
    );
  }

  Widget _dateTile(String label, DateTime? value, {required ValueChanged<DateTime> onPicked, VoidCallback? onClear, String? helper, String? empty}) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.event_outlined),
        title: Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value == null ? (empty ?? 'Not set') : fmtDateTime(value), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
            if (helper != null) Text(helper, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        trailing: value != null && onClear != null
            ? IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: onClear)
            : const Icon(Icons.edit_calendar_outlined),
        onTap: () async {
          final picked = await pickDateTime(context, value ?? _end.add(const Duration(days: 1)), help: label);
          if (picked != null) onPicked(picked);
        },
      ),
    );
  }

  Widget _scheduleTab() {
    final isExam = _category == 'EXAM';
    return PageBody(
      children: [
        _dateTile('Opens', _start, helper: 'Students cannot see the questions before this.', onPicked: (value) => setState(() {
              final length = _end.difference(_start);
              _start = value;
              if (!_end.isAfter(_start)) _end = _start.add(length.isNegative ? const Duration(hours: 1) : length);
            })),
        gap8,
        _dateTile(isExam ? 'Closes' : 'Deadline', _end, onPicked: (value) => setState(() => _end = value)),
        gap12,
        TextField(
          controller: _totalMarks,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Total marks'),
          onChanged: (_) => setState(() {}),
        ),
        if (isExam) ...[
          gap12,
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Time limit per student (minutes)',
              hintText: 'No limit — open until it closes',
              helperText: "Each student's clock starts when they open the exam and never runs past the closing time.",
            ),
          ),
        ],
        gap12,
        _dateTile(
          'Accept late work until',
          _lateUntil,
          empty: 'Not accepted',
          helper: 'Optional. After the deadline students can still hand in until then, marked "late".',
          onPicked: (value) => setState(() => _lateUntil = value),
          onClear: () => setState(() => _lateUntil = null),
        ),
        gap12,
        TextField(
          controller: _grace,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Grace period (minutes)',
            helperText: 'Extra minutes after the end for answers to finish uploading.',
          ),
        ),
        if (_type != 'CQ') ...[
          gap12,
          TextField(
            controller: _negative,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Marks deducted per wrong MCQ',
              helperText: '0 means no negative marking. Unanswered questions never lose marks.',
            ),
          ),
          gap8,
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _shuffle,
            onChanged: (value) => setState(() => _shuffle = value),
            title: const Text('Shuffle MCQ order'),
            subtitle: Text('Each student sees the questions in a different order.'),
          ),
        ],
      ],
    );
  }

  Widget _resultsTab() {
    final options = [
      (
        'IMMEDIATE',
        'As soon as each student submits',
        _forGroup
            ? 'Marks and correct answers appear the moment they hand in. In a group, someone who finishes early could pass the answers on.'
            : 'Marks and correct answers appear the moment they hand in.',
      ),
      ('CLOSE', 'When the exam closes', 'After the deadline and any late-work time, when nobody can still be answering.'),
      ('TIME', 'At a time I choose', 'Results come out automatically at the date and time you set.'),
      ('MANUAL', 'When I publish them', 'Results stay hidden until you press “Publish results” on the exam.'),
    ];
    return PageBody(
      children: [
        const Text('When do students see their results?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          'Until then a student who has submitted sees only “Results pending” — no marks, no correct answers, no solutions.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
        ),
        gap12,
        RadioGroup<String>(
          groupValue: _resultsMode,
          onChanged: (value) => setState(() => _resultsMode = value ?? _resultsMode),
          child: Column(
            children: [
              for (final (value, label, hint) in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    borderColor: _resultsMode == value ? AppColors.primary : null,
                    child: RadioListTile<String>(
                      value: value,
                      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      subtitle: Text(hint, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_resultsMode == 'TIME')
          _dateTile('Publish results at', _resultsAt, empty: 'Choose a date and time', onPicked: (value) => setState(() => _resultsAt = value)),
        if (_type != 'MCQ')
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'MCQs are marked automatically. A written part shows as “awaiting marking” until you have marked it.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
        const SectionTitle('Model solution (optional)', subtitle: 'Students can read it once results are out.'),
        TextField(
          controller: _solution,
          maxLines: null,
          minLines: 4,
          decoration: const InputDecoration(hintText: 'Worked solutions. Maths works as \$x^2\$ or \$\$…\$\$.', alignLabelWithHint: true),
        ),
        gap12,
        if (_solutionMedia.isNotEmpty) ...[
          ServerImage(_solutionMedia, label: 'solution sheet'),
          TextButton.icon(
            onPressed: () => setState(() => _solutionMedia = ''),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove the solution sheet'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        ] else
          OutlinedButton.icon(
            onPressed: () async {
              final urls = await pickAndUpload(context, multiple: false);
              if (urls.isNotEmpty && mounted) setState(() => _solutionMedia = urls.first);
            },
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Attach a photo of the solution sheet'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final noun = _category == 'ASSIGNMENT' ? 'assignment' : 'exam';
    return Scaffold(
      appBar: AppBar(
        title: Text('${_editing ? 'Edit' : 'New'} $noun'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            const Tab(text: 'Details'),
            Tab(text: 'Questions${_type != 'CQ' && _mcq.isNotEmpty ? ' (${_mcq.length})' : ''}'),
            const Tab(text: 'Schedule'),
            const Tab(text: 'Results & solutions'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Banner2(
                _error!,
                color: AppColors.danger,
                icon: Icons.error_outline,
                action: InkWell(onTap: () => setState(() => _error = null), child: const Icon(Icons.close, size: 18, color: AppColors.danger)),
              ),
            ),
          Expanded(
            child: TabBarView(controller: _tabs, children: [_detailsTab(), _questionsTab(), _scheduleTab(), _resultsTab()]),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              if (!_wasPublished) ...[
                Expanded(child: OutlinedButton(onPressed: _saving ? null : () => _save(false), child: const Text('Save as draft'))),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _save(true),
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send, size: 18),
                  label: Text(_wasPublished ? 'Save changes' : 'Publish'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
