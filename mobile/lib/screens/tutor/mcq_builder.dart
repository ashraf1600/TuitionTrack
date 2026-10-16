import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/mcq_parser.dart';
import '../../core/repo.dart';
import '../../core/rich_clipboard.dart';
import '../../widgets/math_text.dart';
import '../../widgets/media.dart';
import '../../widgets/science_paste.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

const _letters = ['A', 'B', 'C', 'D', 'E'];

const pasteExample = r'''1. If \(P(x)=x^3-3x^2+5x-7\), then \(P(1)\) is—
A) \(-4\)
B) \(-3\)
C) \(-2\)
D) 0
Answer: A
Explanation: \(P(1)=1-3+5-7=-4\)

2. The SI unit of force is:  A) Joule  B) Newton  C) Watt  D) Pascal
Answer: B''';

Json blankQuestion({String imageUrl = '', List<String>? options}) => {
      'id': newQuestionId(),
      'question': '',
      'options': options ?? ['', '', '', ''],
      'correct_answer': null,
      'explanation': '',
      'points': 1,
      'marks': 1,
      'image_url': imageUrl,
    };

/// Builds the multiple-choice part of an exam. Questions can come from pasted
/// text, be typed one at a time, start from a picture, or be reused from the
/// tutor's earlier exams — every route ends in the same list of editable cards.
class McqBuilder extends StatelessWidget {
  const McqBuilder({super.key, required this.questions, required this.onChanged});
  final List<Json> questions;
  final ValueChanged<List<Json>> onChanged;

  Future<void> _paste(BuildContext context) async {
    final parsed = await Navigator.push<ParsedQuestions>(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _PasteScreen()));
    if (parsed == null || parsed.questions.isEmpty || !context.mounted) return;
    onChanged([...questions, ...parsed.questions]);
    showToast(
      context,
      parsed.issues.isEmpty
          ? tr('Added {p0} question{p1}. Check each one before publishing.', {'p0': parsed.questions.length, 'p1': parsed.questions.length == 1 ? '' : 's'})
          : tr('Added {p0}. {p1} need{p2} a quick check — they are marked.', {'p0': parsed.questions.length, 'p1': parsed.issues.length, 'p2': parsed.issues.length == 1 ? 's' : ''}),
    );
  }

  Future<void> _type(BuildContext context) async {
    final created = await Navigator.push<Json>(
      context,
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => QuestionEditorScreen(question: blankQuestion(), number: questions.length + 1)),
    );
    if (created != null) onChanged([...questions, created]);
  }

  Future<void> _fromPictures(BuildContext context) async {
    final urls = await pickAndUpload(context);
    if (urls.isEmpty || !context.mounted) return;
    onChanged([...questions, for (final url in urls) blankQuestion(imageUrl: url, options: ['A', 'B', 'C', 'D'])]);
    showToast(context, tr('Added {p0} picture question{p1}. Now mark the correct answer for each.', {'p0': urls.length, 'p1': urls.length == 1 ? '' : 's'}));
  }

  Future<void> _fromBank(BuildContext context) async {
    final chosen = await Navigator.push<List<Json>>(
      context,
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => _BankScreen(inExam: questions)),
    );
    if (chosen != null && chosen.isNotEmpty) onChanged([...questions, ...chosen]);
  }

  Future<void> _edit(BuildContext context, int index) async {
    final edited = await Navigator.push<Json>(
      context,
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => QuestionEditorScreen(question: questions[index], number: index + 1)),
    );
    if (edited != null) onChanged([for (var i = 0; i < questions.length; i++) i == index ? edited : questions[i]]);
  }

  @override
  Widget build(BuildContext context) {
    final unfinished = questions.where((q) => questionProblems(q).isNotEmpty).length;
    final total = questions.fold<num>(0, (sum, q) => sum + q.number('points', 1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          tr('Multiple choice'),
          subtitle: tr('{p0} question{p1} · {p2} mark{p3}{p4}', {'p0': questions.length, 'p1': questions.length == 1 ? '' : 's', 'p2': trimNumber(total), 'p3': total == 1 ? '' : 's', 'p4': unfinished > 0 ? tr(' · {p0} need{p1} attention', {'p0': unfinished, 'p1': unfinished == 1 ? 's' : ''}) : ''}),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(onPressed: () => _paste(context), icon: const Icon(Icons.content_paste, size: 18), label: Text(tr('Paste text'))),
            OutlinedButton.icon(onPressed: () => _type(context), icon: const Icon(Icons.edit_outlined, size: 18), label: Text(tr('Type a question'))),
            OutlinedButton.icon(onPressed: () => _fromPictures(context), icon: const Icon(Icons.add_photo_alternate_outlined, size: 18), label: Text(tr('From a picture'))),
            OutlinedButton.icon(onPressed: () => _fromBank(context), icon: const Icon(Icons.history, size: 18), label: Text(tr('My past questions'))),
          ],
        ),
        gap12,
        if (questions.isEmpty)
          EmptyState(
            icon: Icons.quiz_outlined,
            title: tr('No questions yet'),
            message: tr('Paste a whole set from ChatGPT, type one, or start from a photo of a question.'),
          )
        else
          for (var i = 0; i < questions.length; i++) ...[
            _QuestionCard(
              key: ValueKey(questions[i].str('id')),
              question: questions[i],
              index: i,
              onEdit: () => _edit(context, i),
              onPickAnswer: (answer) => onChanged([
                for (var j = 0; j < questions.length; j++) j == i ? {...questions[j], 'correct_answer': answer} : questions[j],
              ]),
              onDuplicate: () => onChanged([
                ...questions.sublist(0, i + 1),
                {...questions[i], 'id': newQuestionId(), 'options': [...questions[i].strings('options')]},
                ...questions.sublist(i + 1),
              ]),
              onDelete: () => onChanged([...questions]..removeAt(i)),
            ),
            gap8,
          ],
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    super.key,
    required this.question,
    required this.index,
    required this.onEdit,
    required this.onPickAnswer,
    required this.onDuplicate,
    required this.onDelete,
  });
  final Json question;
  final int index;
  final VoidCallback onEdit;
  final ValueChanged<int> onPickAnswer;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final problems = questionProblems(question);
    final correct = correctIndexOf(question);
    final options = question.strings('options');
    final points = question.number('points', 1);
    return AppCard(
      borderColor: problems.isEmpty ? null : AppColors.warning.withValues(alpha: 0.6),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: context.tt.primaryContainer,
                  child: Text(localDigits('${index + 1}'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.tt.onPrimaryContainer)),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: question.str('question').isEmpty
                      ? Text(
                          question.str('image_url').isEmpty ? tr('No question text yet') : tr('Picture question'),
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                        )
                      : MathText(question.str('question'), style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 6),
                child: Text(tr('{p0} mk', {'p0': trimNumber(points)}), style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              PopupMenuButton<String>(
                tooltip: tr('Options for question {p0}', {'p0': index + 1}),
                onSelected: (value) => switch (value) { 'edit' => onEdit(), 'copy' => onDuplicate(), _ => onDelete() },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                  PopupMenuItem(value: 'copy', child: Text(tr('Duplicate'))),
                  PopupMenuItem(value: 'delete', child: Text(tr('Delete'), style: TextStyle(color: AppColors.danger))),
                ],
              ),
            ],
          ),
          if (question.str('image_url').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: ServerImage(question.str('image_url'), height: 160, label: tr('Question {p0} picture', {'p0': index + 1})),
            ),
          gap8,
          // Tap an option to mark it as the correct answer.
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 8),
              child: Semantics(
                inMutuallyExclusiveGroup: true,
                checked: correct == i,
                label: tr('Option {p0}{p1}', {'p0': _letters[i], 'p1': correct == i ? tr(', correct answer') : ''}),
                child: Material(
                  color: correct == i ? context.tt.successContainer : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: correct == i ? context.tt.success : Theme.of(context).colorScheme.outline),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: options[i].trim().isEmpty ? onEdit : () => onPickAnswer(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      child: Row(
                        children: [
                          Icon(
                            correct == i ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 18,
                            color: correct == i ? AppColors.success : Theme.of(context).colorScheme.outlineVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(_letters[i], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: options[i].trim().isEmpty
                                ? Text(tr('Empty option — tap to edit'), style: TextStyle(color: AppColors.warning, fontStyle: FontStyle.italic, fontSize: 13))
                                : MathText(options[i], style: TextStyle(fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (question.str('explanation').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: MathText(tr('Explanation: {p0}', {'p0': question.str('explanation')}), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
            ),
          if (problems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(child: Text(problems.join(' · '), style: const TextStyle(color: AppColors.warning, fontSize: 13))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Paste any number of questions and see how many were recognised before adding them.
class _PasteScreen extends StatefulWidget {
  const _PasteScreen();

  @override
  State<_PasteScreen> createState() => _PasteScreenState();
}

class _PasteScreenState extends State<_PasteScreen> {
  final _text = TextEditingController();
  ParsedQuestions _parsed = ParsedQuestions([], []);

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() => _parsed = parseQuestions(_text.text)));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _fromClipboard() async {
    // Keeps typeset maths (as LaTeX) and H₂O / x² from web pages, Word and Google Docs.
    final text = await readClipboardForQuestions() ?? '';
    if (!mounted) return;
    if (text.trim().isEmpty) {
      showToast(context, tr('The clipboard is empty. Copy the questions first.'), error: true);
      return;
    }
    _text.text = _text.text.trim().isEmpty ? text : '${_text.text.trimRight()}\n\n$text';
  }

  @override
  Widget build(BuildContext context) {
    final count = _parsed.questions.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Paste questions')),
        actions: [TextButton(onPressed: () => _text.text = pasteExample, child: Text(tr('Example')))],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Paste any number of questions from ChatGPT, a website or a document. Numbered questions with options A–D (or ক–ঘ) are recognised, on separate lines or on one line. Maths is kept exactly as written. In ChatGPT, use its Copy button so the formulas come across as LaTeX.'),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              gap12,
              OutlinedButton.icon(onPressed: _fromClipboard, icon: const Icon(Icons.content_paste_go), label: Text(tr('Paste from clipboard'))),
              gap12,
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
                  contextMenuBuilder: sciencePasteMenu,
                  decoration: const InputDecoration(hintText: pasteExample, alignLabelWithHint: true),
                ),
              ),
              gap12,
              Semantics(
                liveRegion: true,
                child: Text(
                  _text.text.trim().isEmpty
                      ? tr('Answers can be written as “Answer: B”, a ✅ after the option, or an answer key at the end.')
                      : count == 0
                          ? tr('No questions recognised yet. Number each question (1. 2. 3.) and label the options A, B, C, D.')
                          : tr('Found {p0} question{p1}{p2}', {'p0': count, 'p1': count == 1 ? '' : 's', 'p2': _parsed.issues.isEmpty ? tr(' · all have an answer') : tr(' · {p0} will need a quick check', {'p0': _parsed.issues.length})}),
                  style: TextStyle(color: count == 0 && _text.text.trim().isNotEmpty ? AppColors.warning : Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
              gap12,
              FilledButton.icon(
                onPressed: count == 0 ? null : () => Navigator.pop(context, _parsed),
                icon: const Icon(Icons.auto_awesome),
                label: Text(count == 0 ? tr('Add questions') : tr('Add {p0} question{p1}', {'p0': count, 'p1': count == 1 ? '' : 's'})),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edit one question: text, picture, options, the correct answer, marks and explanation.
/// Pops with the edited question.
class QuestionEditorScreen extends StatefulWidget {
  const QuestionEditorScreen({super.key, required this.question, required this.number});
  final Json question;
  final int number;

  @override
  State<QuestionEditorScreen> createState() => _QuestionEditorScreenState();
}

class _QuestionEditorScreenState extends State<QuestionEditorScreen> {
  late final _question = TextEditingController(text: widget.question.str('question'));
  late final _explanation = TextEditingController(text: widget.question.str('explanation'));
  late final _points = TextEditingController(text: trimNumber(widget.question.number('points', 1)));
  late final List<TextEditingController> _options = [for (final o in widget.question.strings('options')) TextEditingController(text: o)];
  late int? _correct = correctIndexOf(widget.question);
  late String _image = widget.question.str('image_url');
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    while (_options.length < 2) {
      _options.add(TextEditingController());
    }
    for (final controller in [_question, _explanation, ..._options]) {
      controller.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _question.dispose();
    _explanation.dispose();
    _points.dispose();
    for (final controller in _options) {
      controller.dispose();
    }
    super.dispose();
  }

  Json get _value {
    final points = num.tryParse(_points.text.trim());
    final safePoints = (points != null && points > 0) ? points : 1;
    return {
      ...widget.question,
      'question': _question.text.trim(),
      'options': [for (final o in _options) o.text.trim()],
      'correct_answer': _correct,
      'explanation': _explanation.text.trim(),
      'points': safePoints,
      'marks': safePoints,
      'image_url': _image,
    };
  }

  static bool _hasMath(String text) => text.contains(r'$') || text.contains(r'\') || text.contains('^') || text.contains('_');

  @override
  Widget build(BuildContext context) {
    final problems = questionProblems(_value);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Question {p0}', {'p0': widget.number})),
        actions: [TextButton(onPressed: () => Navigator.pop(context, _value), child: Text(tr('Done')))],
      ),
      body: PageBody(
        children: [
          TextField(
            controller: _question,
            contextMenuBuilder: sciencePasteMenu,
            maxLines: null,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr('Question'),
              helperText: r'Maths works as $x^2$ or \(x_1\).',
              alignLabelWithHint: true,
            ),
          ),
          if (_hasMath(_question.text)) ...[
            gap8,
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Students will see'), style: TextStyle(color: Theme.of(context).colorScheme.outlineVariant, fontSize: 11, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  MathText(_question.text),
                ],
              ),
            ),
          ],
          gap12,
          if (_image.isNotEmpty) ...[
            ServerImage(_image, label: tr('Question picture')),
            TextButton.icon(
              onPressed: () => setState(() => _image = ''),
              icon: Icon(Icons.delete_outline),
              label: Text(tr('Remove picture')),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            ),
          ] else
            OutlinedButton.icon(
              onPressed: _uploading
                  ? null
                  : () async {
                      setState(() => _uploading = true);
                      final urls = await pickAndUpload(context, multiple: false);
                      if (mounted) {
                        setState(() {
                          if (urls.isNotEmpty) _image = urls.first;
                          _uploading = false;
                        });
                      }
                    },
              icon: _uploading
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.add_photo_alternate_outlined),
              label: Text(_uploading ? tr('Uploading…') : tr('Add a picture (diagram, graph, photo)')),
            ),
          SectionTitle(tr('Options'), subtitle: tr('Select the circle next to the correct answer.')),
          RadioGroup<int>(
            groupValue: _correct,
            onChanged: (value) => setState(() => _correct = value),
            child: Column(
              children: [
                for (var i = 0; i < _options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Semantics(label: tr('Option {p0} is correct', {'p0': _letters[i]}), child: Radio<int>(value: i)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _options[i],
                                contextMenuBuilder: sciencePasteMenu,
                                maxLines: null,
                                decoration: InputDecoration(labelText: tr('Option {p0}', {'p0': _letters[i]})),
                              ),
                              if (_hasMath(_options[i].text))
                                Padding(padding: const EdgeInsets.only(top: 4, left: 4), child: MathText(_options[i].text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                            ],
                          ),
                        ),
                        if (_options.length > 2)
                          IconButton(
                            tooltip: tr('Remove option {p0}', {'p0': _letters[i]}),
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => setState(() {
                              _options.removeAt(i).dispose();
                              if (_correct == i) {
                                _correct = null;
                              } else if (_correct != null && _correct! > i) {
                                _correct = _correct! - 1;
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_options.length < _letters.length)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _options.add(TextEditingController()..addListener(_refresh))),
                icon: const Icon(Icons.add),
                label: Text(tr('Add option')),
              ),
            ),
          gap12,
          TextField(
            controller: _points,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Marks for this question')),
          ),
          gap12,
          TextField(
            controller: _explanation,
            contextMenuBuilder: sciencePasteMenu,
            maxLines: null,
            decoration: InputDecoration(labelText: tr('Explanation (optional)'), helperText: tr('Shown to students with their results.')),
          ),
          if (problems.isNotEmpty) ...[gap12, Banner2(tr('Still needed: {p0}', {'p0': problems.join(' · ')}), color: AppColors.warning, icon: Icons.warning_amber_rounded)],
          gap16,
          FilledButton.icon(onPressed: () => Navigator.pop(context, _value), icon: const Icon(Icons.check), label: Text(tr('Done'))),
        ],
      ),
    );
  }
}

/// Every MCQ the tutor has written before, for reuse.
class _BankScreen extends StatefulWidget {
  const _BankScreen({required this.inExam});
  final List<Json> inExam;

  @override
  State<_BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends State<_BankScreen> {
  List<Json>? _items;
  final _picked = <String>{};
  String _search = '';

  static String _key(Json q) => '${q.str('question')}|${q.str('image_url')}|${q.strings('options').join('|')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final search = _search;
    try {
      final items = await context.read<Repo>().questionBank(search);
      if (mounted && search == _search) setState(() => _items = items);
    } on ApiException catch (error) {
      if (mounted) {
        showToast(context, error.message, error: true);
        setState(() => _items ??= []);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final used = widget.inExam.map(_key).toSet();
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(tr('My past questions'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: InputDecoration(labelText: tr('Search by words in the question or options'), prefixIcon: Icon(Icons.search)),
                onChanged: (value) {
                  _search = value.trim();
                  _load();
                },
              ),
            ),
            Expanded(
              child: items == null
                  ? Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _search.isEmpty ? tr('Questions you write in any exam will appear here for reuse.') : tr('No past questions match that search.'),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) => Divider(),
                          itemBuilder: (context, index) {
                            final q = items[index];
                            final key = _key(q);
                            final already = used.contains(key);
                            return CheckboxListTile(
                              value: already || _picked.contains(key),
                              enabled: !already,
                              onChanged: (value) => setState(() => value == true ? _picked.add(key) : _picked.remove(key)),
                              title: MathText(q.str('question').isEmpty ? tr('(picture question)') : q.str('question'), maxLines: 3),
                              subtitle: Text(
                                already
                                    ? tr('Already in this exam')
                                    : tr('{p0}\nFrom: {p1} · {p2} mark(s)', {'p0': q.strings('options').join(' · '), 'p1': q.str('source_exam'), 'p2': trimNumber(q.number('points', 1))}),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _picked.isEmpty
                      ? null
                      : () => Navigator.pop(context, [
                            for (final q in items ?? const <Json>[])
                              if (_picked.contains(_key(q)))
                                {
                                  'id': newQuestionId(),
                                  'question': q.str('question'),
                                  'options': q.strings('options'),
                                  'correct_answer': q['correct_answer'],
                                  'explanation': q.str('explanation'),
                                  'points': q.number('points', 1),
                                  'marks': q.number('points', 1),
                                  'image_url': q.str('image_url'),
                                },
                          ]),
                  child: Text(_picked.isEmpty ? tr('Choose questions') : tr('Add {p0} selected', {'p0': _picked.length})),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
