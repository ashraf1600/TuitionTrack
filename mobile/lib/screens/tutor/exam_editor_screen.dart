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

class _ExamEditorScreenState extends State<ExamEditorScreen> {
  // One page of collapsible steps: 0 basic info, 1 questions, 2 extra rules, 3 results.
  int _open = 0;
  final _sectionKeys = List.generate(4, (_) => GlobalKey());
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

  bool _fail(String message, int section) {
    setState(() {
      _error = message;
      _open = section;
    });
    _reveal(section);
    return false;
  }

  /// Opens [section] (closing the others) and scrolls it into view.
  void _openSection(int section) {
    setState(() => _open = _open == section ? -1 : section);
    if (_open == section) _reveal(section);
  }

  void _reveal(int section) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 220)); // let the previous step fold away
      final target = _sectionKeys[section].currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 250), alignment: 0.02);
      }
    });
  }

  bool _validate(bool publish) {
    final total = num.tryParse(_totalMarks.text.trim());
    if (_title.text.trim().isEmpty) return _fail(tr('Give the exam a title.'), 0);
    if (_forGroup && _tuitionId == null) return _fail(tr('Choose the tuition this is for.'), 0);
    if (!_forGroup && _studentId == null) return _fail(tr('Choose the student this is for.'), 0);
    if (total == null || total <= 0) return _fail(tr('Enter the total marks.'), 0);
    if (!_end.isAfter(_start)) return _fail(tr('The end time must be after the start time.'), 0);
    if (!_editing && !_end.isAfter(DateTime.now())) return _fail(tr('The end time is already in the past.'), 0);
    if (_lateUntil != null && !_lateUntil!.isAfter(_end)) return _fail(tr('"Accept late work until" must be after the deadline.'), 2);
    if (_type != 'MCQ' && _scheme.any((row) => (num.tryParse(row.marks.text.trim()) ?? 0) <= 0)) {
      return _fail(tr('Every written question in the marking scheme needs marks above 0.'), 1);
    }
    if (_mcqTotal + _writtenTotal > total) {
      return _fail(
        tr('MCQ marks ({p0}) plus written marks ({p1}) come to more than the total of {p2}.', {'p0': trimNumber(_mcqTotal), 'p1': trimNumber(_writtenTotal), 'p2': trimNumber(total)}),
        0,
      );
    }
    if (publish && _type == 'MCQ' && _mcq.isEmpty) return _fail(tr('Add at least one question, or change the type to written.'), 1);
    if (publish && _type != 'CQ') {
      final unfinished = _mcq.indexWhere((q) => questionProblems(q).isNotEmpty);
      if (unfinished != -1) {
        return _fail(
          tr('Question {p0} is not ready: {p1}. You can still save it as a draft.', {'p0': unfinished + 1, 'p1': questionProblems(_mcq[unfinished]).first.toLowerCase()}),
          1,
        );
      }
    }
    if (publish && _type == 'CQ' && !_keepPaper && _written.text.trim().isEmpty) return _fail(tr('The written paper is empty.'), 1);
    if (_resultsMode == 'TIME') {
      if (_resultsAt == null) return _fail(tr('Choose the date and time when results should be published.'), 3);
      if (!_resultsAt!.isAfter(_start)) return _fail(tr('Results cannot be published before the exam starts.'), 3);
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
            ? (publish ? tr('Changes saved.') : tr('Saved as a draft — students cannot see it.'))
            : (publish ? tr('Published. Students have been notified.') : tr('Draft saved — publish it when you are ready.')),
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
        title: Text(tr('Paste written questions')),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('Numbered questions are kept apart and maths stays as written. If every question ends with its marks — [10] or (5 marks) — the marking scheme is filled in too.'),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              gap12,
              TextField(
                controller: controller,
                maxLines: 8,
                autofocus: true,
                autocorrect: false,
                style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(hintText: tr('1. A particle moves with velocity \\(v(t) = 3t^2 - 4t\\). Find its acceleration at t = 2 s. [5]')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(tr('Add to the paper'))),
        ],
      ),
    );
    if (text == null || !mounted) return;
    final items = parseWrittenQuestions(text);
    if (items.isEmpty) {
      showToast(context, tr('No questions found in that text.'), error: true);
      return;
    }
    final blocks = items.map((q) => '${q.label}. ${q.text}${q.marks != null ? ' [${trimNumber(q.marks)}]' : ''}').join('\n\n');
    setState(() {
      _written.text = _written.text.trim().isEmpty ? blocks : '${_written.text.trimRight()}\n\n$blocks';
      if (items.every((q) => (q.marks ?? 0) > 0)) {
        _scheme.addAll(items.map((q) => _SchemeRow(label: q.label, marks: trimNumber(q.marks))));
      }
    });
    showToast(context, tr('Added {p0} written question{p1}.', {'p0': items.length, 'p1': items.length == 1 ? '' : 's'}));
  }

  Widget _questionsSection() {
    final api = context.read<Session>().api;
    final total = num.tryParse(_totalMarks.text.trim()) ?? 0;
    final allocated = _mcqTotal + _writtenTotal;
    final preview = plainTextToHtml(_written.text);
    final needsPreview = _written.text.contains(r'$') || _written.text.contains(r'\') || _written.text.contains('[picture:');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_type != 'CQ') McqBuilder(questions: _mcq, onChanged: (value) => setState(() => _mcq = value)),
        if (_type != 'MCQ') ...[
          gap8,
          _Label(tr('Written questions'), info: tr('Students type their answer or upload photos of their handwriting.\n\nLeave a blank line between questions. Maths works as \$x^2\$, \\(x_1\\) or \$\$…\$\$.')),
          if (_keepPaper) ...[
            Banner2(
              tr('This paper was formatted on the website (tables, bold or lists). It is kept exactly as it is. Rewriting it here keeps the text and pictures but drops that formatting.'),
            ),
            gap8,
            AppCard(child: HtmlMath(_originalHtml, baseUrl: api.baseUrl)),
            TextButton.icon(
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: tr('Rewrite the paper here?'),
                  message: tr('The text and pictures are kept. Tables, bold text and lists become plain paragraphs.'),
                  confirmLabel: tr('Rewrite'),
                );
                if (ok && mounted) setState(() => _keepPaper = false);
              },
              icon: const Icon(Icons.edit_outlined),
              label: Text(tr('Rewrite on this phone')),
            ),
          ] else ...[
            TextField(
              controller: _written,
              maxLines: null,
              minLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: tr('Q1. Prove that …\n\nQ2. Evaluate \$\$\\int_0^1 x^2\\,dx\$\$'),
                alignLabelWithHint: true,
              ),
            ),
            gap8,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(onPressed: _pasteWritten, icon: const Icon(Icons.content_paste, size: 18), label: Text(tr('Paste questions'))),
                OutlinedButton.icon(
                  onPressed: () async {
                    final urls = await pickAndUpload(context);
                    if (urls.isEmpty || !mounted) return;
                    setState(() => _written.text = '${_written.text.trimRight()}\n\n${urls.map((u) => '[picture: $u]').join('\n\n')}\n\n'.trimLeft());
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: Text(tr('Add a picture')),
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
                    Text(tr('Students will see'), style: TextStyle(color: Theme.of(context).colorScheme.outlineVariant, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    HtmlMath(preview, baseUrl: api.baseUrl),
                  ],
                ),
              ),
            ],
          ],
          gap12,
          _Label(
            tr('Marks per written question'),
            info: tr('Optional. List each question and its marks to mark them one by one. Leave it empty to give one overall written mark.'),
            trailing: TextButton.icon(
              onPressed: () => setState(() => _scheme.add(_SchemeRow(label: tr('Q{p0}', {'p0': _scheme.length + 1})))),
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('Add')),
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
                      decoration: InputDecoration(labelText: tr('Question {p0}', {'p0': i + 1}), hintText: tr('e.g. Q1 (a)'), counterText: ''),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _scheme[i].marks,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: tr('Marks')),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Remove written question {p0}', {'p0': i + 1}),
                    icon: Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _scheme.removeAt(i).dispose()),
                  ),
                ],
              ),
            ),
        ],
        gap12,
        Text(
          tr('Marks set so far: {p0} MCQ{p1} = {p2} of {p3} total.', {'p0': trimNumber(_mcqTotal), 'p1': _type != 'MCQ' && _scheme.isNotEmpty ? tr(' + {p0} written', {'p0': trimNumber(_writtenTotal)}) : '', 'p2': trimNumber(allocated), 'p3': trimNumber(total)}),
          style: TextStyle(color: allocated > total ? AppColors.danger : Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: allocated > total ? FontWeight.w700 : null),
        ),
      ],
    );
  }

  // ── Steps ──────────────────────────────────────────────────────────────────

  String get _targetName {
    if (_forGroup) {
      final t = _tuitions.where((t) => t.str('id') == _tuitionId).firstOrNull;
      return t?.str('title') ?? (_tuitions.isEmpty ? tr('No tuitions yet') : tr('Choose'));
    }
    final s = _students.where((s) => s.str('id') == _studentId).firstOrNull;
    return s == null ? (_students.isEmpty ? tr('No students yet') : tr('Choose')) : (s.str('full_name').isNotEmpty ? s.str('full_name') : '@${s.str('username')}');
  }

  Future<void> _chooseTarget() async {
    final picked = _forGroup
        ? await pickFromSheet(
            context,
            title: tr('Choose a tuition'),
            icon: Icons.class_outlined,
            selected: _tuitionId,
            options: [
              for (final t in _tuitions)
                (value: t.str('id'), label: t.str('title'), subtitle: '${t.integer('enrolled_count')} student${t.integer('enrolled_count') == 1 ? '' : 's'}'),
            ],
          )
        : await pickFromSheet(
            context,
            title: tr('Choose a student'),
            selected: _studentId,
            options: [
              for (final s in _students)
                (value: s.str('id'), label: s.str('full_name').isNotEmpty ? s.str('full_name') : '@${s.str('username')}', subtitle: '@${s.str('username')}'),
            ],
          );
    if (picked == null || !mounted) return;
    setState(() {
      if (_forGroup) {
        _tuitionId = picked;
      } else {
        _studentId = picked;
      }
    });
  }

  Future<void> _pickInto(String label, DateTime? current, ValueChanged<DateTime> onPicked) async {
    final picked = await pickDateTime(context, current ?? _end.add(const Duration(days: 1)), help: label);
    if (picked != null) onPicked(picked);
  }

  /// Choices as a 44 dp tonal segmented control.
  Widget _chips<T>(List<(T, String)> options, T selected, ValueChanged<T> onSelect) {
    return PillToggle<T>(
      options: [for (final (value, label) in options) (value, label, null)],
      selected: selected,
      onChanged: (value) => setState(() => onSelect(value)),
    );
  }

  Widget _basicSection() {
    final isExam = _category == 'EXAM';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(tr('Title')),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(hintText: tr('Title, e.g. Chapter 3 quiz — Polynomials')),
          onChanged: (_) => setState(() {}),
        ),
        gap16,
        _Label(tr('Type'), info: tr('Timed exam: open between a start and an end time, with an optional time limit per student.\n\nAssignment: homework with a deadline and no stopwatch.')),
        _chips<String>([('EXAM', tr('Timed exam')), ('ASSIGNMENT', tr('Assignment'))], _category, (v) => _category = v),
        gap16,
        _Label(tr('Questions'), info: tr('MCQ: multiple choice, marked automatically.\n\nWritten: creative questions you mark yourself.\n\nBoth: a mix of the two.')),
        _chips<String>([('HYBRID', tr('Both')), ('MCQ', tr('MCQ only')), ('CQ', tr('Written only'))], _type, (v) => _type = v),
        gap16,
        _Label(tr('For')),
        _chips<bool>([(true, tr('A tuition')), (false, tr('One student'))], _forGroup, (v) => _forGroup = v),
        gap12,
        FlatGroup(children: [
          PickerRow(
            leading: InitialAvatar(_targetName, radius: 14, icon: _forGroup ? Icons.class_outlined : null),
            label: _forGroup ? tr('Tuition') : tr('Student'),
            value: _targetName,
            onTap: (_forGroup ? _tuitions.isEmpty : _students.isEmpty) ? null : _chooseTarget,
          ),
          PickerRow(
            leading: Icon(Icons.play_circle_outline, size: 22, color: context.tt.textTertiary),
            label: tr('Opens'),
            value: fmtDateTime(_start),
            onTap: () => _pickInto(tr('Opens'), _start, (value) => setState(() {
                  final length = _end.difference(_start);
                  _start = value;
                  if (!_end.isAfter(_start)) _end = _start.add(length.isNegative ? const Duration(hours: 1) : length);
                })),
          ),
          PickerRow(
            leading: Icon(Icons.flag_outlined, size: 22, color: context.tt.textTertiary),
            label: isExam ? tr('Closes') : tr('Deadline'),
            value: fmtDateTime(_end),
            onTap: () => _pickInto(isExam ? tr('Closes') : tr('Deadline'), _end, (value) => setState(() => _end = value)),
          ),
          _NumberRow(label: tr('Total marks'), controller: _totalMarks, onChanged: () => setState(() {})),
          if (isExam)
            _NumberRow(
              label: tr('Time limit'),
              controller: _duration,
              hint: tr('No limit'),
              suffix: 'min',
              info: tr('Each student\'s clock starts when they open the exam and never runs past the closing time. Leave empty for no limit.'),
            ),
        ]),
      ],
    );
  }

  Widget _rulesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlatGroup(children: [
          PickerRow(
            leading: Icon(Icons.schedule_send_outlined, size: 22, color: context.tt.textTertiary),
            label: tr('Late work until'),
            value: _lateUntil == null ? tr('Not accepted') : fmtDateTime(_lateUntil),
            onTap: () => _pickInto(tr('Accept late work until'), _lateUntil, (value) => setState(() => _lateUntil = value)),
            trailing: _lateUntil == null
                ? null
                : IconButton(
                    tooltip: tr('Do not accept late work'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _lateUntil = null),
                  ),
          ),
          _NumberRow(
            label: tr('Grace period'),
            controller: _grace,
            suffix: 'min',
            info: tr('Extra minutes after the end for answers that are still uploading.'),
          ),
          if (_type != 'CQ') ...[
            _NumberRow(
              label: tr('Minus per wrong MCQ'),
              controller: _negative,
              decimal: true,
              info: tr('0 means no negative marking. Unanswered questions never lose marks.'),
            ),
            SwitchListTile(
              dense: true,
              value: _shuffle,
              onChanged: (value) => setState(() => _shuffle = value),
              title: Text(tr('Shuffle MCQ order'), style: TextStyle(fontSize: 14)),
            ),
          ],
        ]),
      ],
    );
  }

  static const _resultModes = [
    ('IMMEDIATE', 'On submit'),
    ('CLOSE', 'When it closes'),
    ('TIME', 'At a set time'),
    ('MANUAL', 'When I publish'),
  ];

  Widget _resultsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(
          tr('Students see results'),
          info: tr('Until then a student who has submitted sees only “Results pending”: no marks, no correct answers, no solutions.\n\nOn submit: marks and answers appear the moment they hand in{p0}.\nWhen it closes: after the deadline and any late-work time.\nAt a set time: automatically at the date and time you choose.\nWhen I publish: hidden until you press “Publish results”.{p1}', {'p0': _forGroup ? tr(' (someone who finishes early could pass the answers on)') : '', 'p1': _type != 'MCQ' ? tr('\n\nMCQs are marked automatically. A written part shows as “awaiting marking” until you mark it.') : ''}),
        ),
        _chips<String>([for (final (value, label) in _resultModes) (value, tr(label))], _resultsMode, (v) => _resultsMode = v),
        if (_resultsMode == 'TIME') ...[
          gap8,
          FlatGroup(children: [
            PickerRow(
              leading: Icon(Icons.event_available_outlined, size: 22, color: context.tt.textTertiary),
              label: tr('Publish at'),
              value: _resultsAt == null ? tr('Choose') : fmtDateTime(_resultsAt),
              onTap: () => _pickInto(tr('Publish results at'), _resultsAt, (value) => setState(() => _resultsAt = value)),
            ),
          ]),
        ],
        gap12,
        _Label(tr('Model solution'), info: tr('Optional. Students can read it once results are out.')),
        FlatGroup(children: [
          FlatField(controller: _solution, hint: tr('Worked solutions. Maths works as \$x^2\$ or \$\$…\$\$.'), minLines: 3, maxLines: 10),
          if (_solutionMedia.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.all(12), child: ServerImage(_solutionMedia, label: tr('solution sheet'), height: 140)),
            ListTile(
              dense: true,
              leading: Icon(Icons.delete_outline, color: tone(context, AppColors.danger)),
              title: Text(tr('Remove the solution sheet'), style: TextStyle(color: tone(context, AppColors.danger))),
              onTap: () => setState(() => _solutionMedia = ''),
            ),
          ] else
            ListTile(
              dense: true,
              leading: const Icon(Icons.upload_file_outlined),
              title: Text(tr('Attach a photo of the solution sheet')),
              onTap: () async {
                final urls = await pickAndUpload(context, multiple: false);
                if (urls.isNotEmpty && mounted) setState(() => _solutionMedia = urls.first);
              },
            ),
        ]),
      ],
    );
  }

  String get _basicSummary {
    final title = _title.text.trim().isEmpty ? tr('No title yet') : _title.text.trim();
    return '$title · ${_category == 'EXAM' ? tr('Timed exam') : tr('Assignment')} · $_targetName';
  }

  String get _questionsSummary {
    final parts = <String>[
      if (_type != 'CQ') tr('{n} MCQ', {'n': _mcq.length}),
      if (_type != 'MCQ') _keepPaper || _written.text.trim().isNotEmpty ? tr('written paper') : tr('no written paper yet'),
    ];
    return tr('{p0} · {p1} of {p2} marks', {'p0': parts.join(' + '), 'p1': trimNumber(_mcqTotal + _writtenTotal), 'p2': _totalMarks.text.trim().isEmpty ? '?' : _totalMarks.text.trim()});
  }

  String get _rulesSummary {
    final parts = <String>[
      if (_lateUntil != null) tr('late work until {p0}', {'p0': fmtShortDate(_lateUntil)}),
      tr('grace {p0} min', {'p0': _grace.text.trim().isEmpty ? '0' : _grace.text.trim()}),
      if (_type != 'CQ' && (num.tryParse(_negative.text.trim()) ?? 0) > 0) tr('negative marking'),
      if (_type != 'CQ' && _shuffle) tr('shuffled'),
    ];
    return parts.join(' · ');
  }

  String get _resultsSummary => tr(_resultModes.firstWhere((m) => m.$1 == _resultsMode, orElse: () => _resultModes.last).$2);

  Widget _step(int index, String title, String summary, Widget body, {bool done = false, bool optional = false}) {
    final open = _open == index;
    final last = index == 3;
    return Padding(
      key: _sectionKeys[index],
      padding: const EdgeInsets.only(bottom: 12),
      child: _Step(
        number: index + 1,
        title: title,
        summary: summary,
        open: open,
        done: done,
        optional: optional,
        onToggle: () => _openSection(index),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            if (!last) ...[
              gap16,
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  setState(() => _open = index + 1);
                  _reveal(index + 1);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Continue')),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_downward_rounded, size: 18),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final noun = _category == 'ASSIGNMENT' ? 'assignment' : 'exam';
    final hasQuestions = (_type != 'CQ' && _mcq.isNotEmpty) || (_type != 'MCQ' && (_keepPaper || _written.text.trim().isNotEmpty));
    // Publishing needs a title and a question; until then the button shows it is not ready.
    final canPublish = _wasPublished || (_title.text.trim().isNotEmpty && hasQuestions);
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing
            ? (noun == 'assignment' ? tr('Edit assignment') : tr('Edit exam'))
            : (noun == 'assignment' ? tr('New assignment') : tr('New exam'))),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_error != null) ...[
            Banner2(
              _error!,
              color: AppColors.danger,
              icon: Icons.error_outline,
              action: InkWell(onTap: () => setState(() => _error = null), child: Icon(Icons.close, size: 18, color: tone(context, AppColors.danger))),
            ),
            gap12,
          ],
          _step(0, tr('Basic info'), _basicSummary, _basicSection(),
              done: _title.text.trim().isNotEmpty && (_forGroup ? _tuitionId != null : _studentId != null)),
          _step(1, tr('Questions'), _questionsSummary, _questionsSection(), done: hasQuestions),
          _step(2, tr('Extra rules'), _rulesSummary, _rulesSection(), optional: true),
          _step(3, tr('Results & solution'), _resultsSummary, _resultsSection(), done: true),
          if (!canPublish)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Text(tr('Add a title and at least one question before you publish.'),
                  style: TextStyle(fontSize: 14, height: 1.5, color: context.tt.textSecondary)),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        color: context.tt.surface,
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              if (!_wasPublished) ...[
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: context.tt.cardRaised,
                      foregroundColor: context.tt.textPrimary,
                    ),
                    onPressed: _saving ? null : () => _save(false),
                    child: Text(tr('Save draft')),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _saving || !canPublish ? null : () => _save(true),
                  icon: _saving
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.tt.onPrimary))
                      : const Icon(Icons.send, size: 18),
                  label: Text(_wasPublished ? tr('Save changes') : tr('Publish')),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

/// One collapsible step of the form: a numbered header that shows a one-line
/// summary while folded, and the step's fields while open.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.summary,
    required this.open,
    required this.done,
    required this.optional,
    required this.onToggle,
    required this.child,
  });
  final int number;
  final String title;
  final String summary;
  final bool open;
  final bool done;
  final bool optional;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    // Badge: open = primary with its number; finished = green check; otherwise a quiet number.
    final Color badgeFill = open ? tt.primary : (done ? tt.successContainer : tt.cardRaised);
    final Widget badge = done && !open
        ? Icon(Icons.check_rounded, size: 18, color: tt.success)
        : Text(localDigits('$number'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: open ? tt.onPrimary : tt.textSecondary));
    // An unfinished required step says so in the warning colour.
    final summaryColor = !done && !optional ? tt.warning : tt.textSecondary;
    return Material(
      color: tt.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: badgeFill, shape: BoxShape.circle),
                      child: badge,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(text: title),
                              if (optional)
                                TextSpan(
                                  text: ' · ${tr('  optional').trim()}',
                                  style: TextStyle(fontWeight: FontWeight.w400, color: tt.textTertiary),
                                ),
                            ]),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: tt.textPrimary),
                          ),
                          if (!open && summary.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(summary,
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: summaryColor)),
                            ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more_rounded, color: tt.textTertiary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), child: child)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// A small field label with an optional (i) for the explanation.
class _Label extends StatelessWidget {
  const _Label(this.text, {this.info, this.trailing});
  final String text;
  final String? info;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: Row(
        children: [
          Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.tt.textSecondary)),
          if (info != null) InfoTip(info!, title: text) else const SizedBox(height: 36),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A label and a short number field on one row, inside a [FlatGroup].
class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.label, required this.controller, this.hint, this.suffix, this.info, this.decimal = false, this.onChanged});
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? suffix;
  final String? info;
  final bool decimal;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const none = InputBorder.none;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
          if (info != null) InfoTip(info!, title: label),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.numberWithOptions(decimal: decimal),
              onChanged: onChanged == null ? null : (_) => onChanged!(),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: hint,
                suffixText: suffix,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: none,
                enabledBorder: none,
                focusedBorder: none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
