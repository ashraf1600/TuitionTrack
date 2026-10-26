import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/connect.dart' show tutorSirName;
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/math_text.dart';
import '../../widgets/media.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../tutor/cq_builder.dart' show CqQuestionView;

/// Option letters as on a board paper: ক খ গ ঘ in Bangla, A B C D in English.
List<String> get _letters => isBangla ? const ['ক', 'খ', 'গ', 'ঘ', 'ঙ'] : const ['A', 'B', 'C', 'D', 'E'];

/// A link a tutor can open: http(s) and something after it.
bool isAnswerLink(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.contains('.');
}

/// Sitting an exam or handing in an assignment, laid out like a printed
/// question paper: a header with the title, time and full marks, the
/// instructions, then section A (MCQ, bubbles to fill) and section B (creative
/// questions). The written answers are done on paper and handed in as one link
/// to the answer sheet (Google Drive, Docs…), never as photos in the app.
///
/// The countdown follows the server clock. At the deadline the answers are sent
/// automatically once (the server allows a short grace period for that); if the
/// tutor accepts late work nothing is sent automatically and the student can
/// hand in late. Answers are saved on the device as they are given, so leaving
/// the screen never loses them. Pops with the server's response after a
/// successful submission.
///
/// With [preview] the tutor sees the same paper: no clock, nothing is saved or sent.
class ExamTakeScreen extends StatefulWidget {
  const ExamTakeScreen({super.key, required this.exam, this.preview = false});

  /// The exam as returned by `POST /exams/<id>/start/` — questions without any answers.
  final Json exam;
  final bool preview;

  @override
  State<ExamTakeScreen> createState() => _ExamTakeScreenState();
}

enum _Phase { onTime, late, grace, over }

class _ExamTakeScreenState extends State<ExamTakeScreen> {
  final _answers = <String, int>{};
  final _link = TextEditingController();
  final _scroll = ScrollController();
  late final List<GlobalKey> _questionKeys = List.generate(_questions.length, (_) => GlobalKey());
  final _linkKey = GlobalKey();
  Timer? _ticker;
  Duration _left = Duration.zero;
  _Phase _phase = _Phase.onTime;
  bool _submitting = false;
  bool _autoSent = false;
  String? _error;

  Json get exam => widget.exam;
  bool get _preview => widget.preview;

  /// Drafts are per exam and per account, so two students sharing a phone never see each other's answers.
  late final String _draftKey;
  List<Json> get _questions => exam.maps('mcq_data');
  List<Json> get _cq => exam.maps('cq_data');
  bool get _mcqOnly => exam.str('exam_type') == 'MCQ';
  bool get _isAssignment => exam.str('category') == 'ASSIGNMENT';
  bool get _hasLegacyPaper {
    final html = exam.str('content_html').trim();
    return !_mcqOnly && _cq.isEmpty && html.isNotEmpty && html != '<p></p>' && html != '<p>Multiple Choice Examination</p>';
  }

  bool get _hasWritten => !_mcqOnly && (_cq.isNotEmpty || _hasLegacyPaper);
  bool get _linkOk => isAnswerLink(_link.text);

  @override
  void initState() {
    super.initState();
    final userId = context.read<Session>().user?.str('id') ?? '';
    _draftKey = 'exam_draft_${exam.str('id')}_$userId';
    if (_preview) return;
    _restoreDraft();
    _link.addListener(() {
      _saveDraft();
      setState(() {});
    });
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _link.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _restoreDraft() {
    final raw = context.read<Session>().settings.getString(_draftKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final draft = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final ids = _questions.map((q) => q.str('id')).toSet();
      (draft['answers'] as Map?)?.forEach((key, value) {
        if (ids.contains(key) && value is int) _answers['$key'] = value;
      });
      _link.text = '${draft['link'] ?? ''}';
    } catch (_) {
      // a damaged draft is simply ignored
    }
  }

  void _saveDraft() {
    if (_preview) return;
    context.read<Session>().settings.setString(_draftKey, jsonEncode({'answers': _answers, 'link': _link.text}));
  }

  void _tick() {
    final now = context.read<Session>().api.serverNow;
    // dateUtc forces naive ISO strings (no trailing Z / offset) to be read as
    // UTC; subtracting a 5-minute grace window must match the server exactly.
    final deadline = exam.dateUtc('attempt_deadline') ?? exam.dateUtc('end_time') ?? now;
    final graceEnd = deadline.add(Duration(minutes: exam.integer('grace_period_minutes', 5)));
    final lateEnd = exam.dateUtc('late_submission_until');

    _Phase phase;
    Duration left;
    if (!now.isAfter(deadline)) {
      phase = _Phase.onTime;
      left = deadline.difference(now);
    } else if (lateEnd != null && lateEnd.isAfter(now)) {
      phase = _Phase.late;
      left = lateEnd.difference(now);
    } else if (!now.isAfter(graceEnd)) {
      phase = _Phase.grace;
      left = graceEnd.difference(now);
    } else {
      phase = _Phase.over;
      left = Duration.zero;
    }
    if (mounted) {
      setState(() {
        _phase = phase;
        _left = left;
      });
    }
    // Time is up and late work is not accepted: send whatever has been answered, once.
    if (phase == _Phase.grace && !_autoSent && !_submitting) {
      _autoSent = true;
      _submit(auto: true);
    }
  }

  void _jumpTo(GlobalKey key) {
    final target = key.currentContext;
    if (target != null) Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 300), alignment: 0.1);
  }

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      showToast(context, tr('Nothing to paste. Copy the link first.'), error: true);
      return;
    }
    _link.text = text;
  }

  Future<void> _submit({bool auto = false}) async {
    if (_submitting || _preview) return;
    final link = _link.text.trim();
    if (!auto) {
      setState(() => _error = null);
      if (_phase == _Phase.over) {
        setState(() => _error = tr('The submission time has ended.'));
        return;
      }
      if (link.isNotEmpty && !_linkOk) {
        setState(() => _error = tr('That does not look like a link. Paste the full link that starts with https://'));
        _jumpTo(_linkKey);
        return;
      }
      if (_mcqOnly && _answers.isEmpty) {
        setState(() => _error = tr('Choose an answer for at least one question.'));
        return;
      }
      // A written-only paper is nothing without the answer sheet.
      if (_hasWritten && _questions.isEmpty && link.isEmpty) {
        setState(() => _error = tr('Add the link to your written answer sheet before turning in.'));
        _jumpTo(_linkKey);
        return;
      }
      final unanswered = _questions.length - _answers.length;
      final notes = <String>[
        if (_questions.isNotEmpty)
          unanswered > 0
              ? tr('MCQ: {p0} of {p1} answered, {p2} left blank.', {'p0': _answers.length, 'p1': _questions.length, 'p2': unanswered})
              : tr('MCQ: all {p0} answered.', {'p0': _questions.length}),
        if (_hasWritten) link.isEmpty ? tr('Written part: no answer link — it will get no marks.') : tr('Written part: answer link added.'),
        tr('You cannot change your answers after turning in.'),
      ];
      final ok = await confirm(
        context,
        title: _isAssignment ? tr('Turn in the assignment?') : tr('Turn in the exam?'),
        message: notes.join('\n\n'),
        confirmLabel: tr('Turn in'),
      );
      if (!ok || !mounted) return;
    }

    setState(() => _submitting = true);
    final session = context.read<Session>();
    try {
      final response = await context.read<Repo>().submitExam(
            exam.str('id'),
            answers: Map<String, dynamic>.from(_answers),
            // At the deadline a half-typed link is dropped rather than refused.
            answerLink: _linkOk ? link : '',
          );
      await session.settings.setString(_draftKey, '');
      if (mounted) Navigator.pop(context, response);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = auto ? tr('Time is up, and your answers could not be sent: {p0} Tap "Turn in" to try again.', {'p0': error.message}) : error.message;
      });
    } catch (_) {
      // Never leave the button stuck on "sending": the answers are still saved on the device.
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = tr('Your answers could not be sent. They are saved on this phone; tap "Turn in" to try again.');
      });
    }
  }

  Future<bool> _confirmLeave() async {
    if (_preview) return true;
    if (_submitting) return false;
    return confirm(
      context,
      title: tr('Leave without turning in?'),
      message: exam.flag('is_timed')
          ? tr('Your answers are saved on this phone, but the clock keeps running. Come back before the time ends.')
          : tr('Your answers are saved on this phone. Come back and turn in before the deadline.'),
      confirmLabel: tr('Leave'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return PopScope(
      canPop: _preview,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: tt.background,
        appBar: AppBar(
          title: Text(_preview ? tr('Preview') : (_isAssignment ? tr('Assignment') : tr('Exam'))),
          actions: [
            if (_questions.isNotEmpty)
              IconButton(
                tooltip: tr('Go to a question'),
                icon: const Icon(Icons.grid_view_rounded),
                onPressed: _openNavigator,
              ),
          ],
        ),
        body: Column(
          children: [
            if (!_preview) _timerBar(context) else _previewBar(context),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) ...[Banner2(_error!, color: AppColors.danger, icon: Icons.error_outline), gap12],
                        _paper(context),
                        gap16,
                        if (!_preview) _submitButton(context),
                        if (_phase == _Phase.over && !_preview)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(tr('The submission time has ended.'), textAlign: TextAlign.center, style: TextStyle(color: tt.danger)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bars ───────────────────────────────────────────────────────────────

  Widget _timerBar(BuildContext context) {
    final tt = context.tt;
    final warning = _phase == _Phase.late || _phase == _Phase.grace || _phase == _Phase.over;
    final color = warning ? AppColors.warning : (_left.inSeconds <= 300 ? AppColors.danger : AppColors.primarySoft);
    final ink = tone(context, color);
    final label = switch (_phase) {
      _Phase.over => tr('Time is up'),
      _Phase.late => tr('Late work accepted for'),
      _Phase.grace => tr('Sending your answers…'),
      _Phase.onTime => exam.flag('is_timed') ? tr('Your time left') : (_isAssignment ? tr('Until the deadline') : tr('Time left')),
    };
    final answered = _questions.isEmpty ? null : _answers.length / _questions.length;
    return Semantics(
      liveRegion: _left.inSeconds % 60 == 0,
      child: Container(
        color: tonalContainer(context, color),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, color: ink, size: 20),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(
                  countdown(_left),
                  style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
            if (answered != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: answered, minHeight: 4, backgroundColor: tt.card, color: ink),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    tr('{p0}/{p1} MCQ', {'p0': _answers.length, 'p1': _questions.length}),
                    style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previewBar(BuildContext context) => Container(
        width: double.infinity,
        color: context.tt.primaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          tr('This is how students will see the paper. Nothing here is saved.'),
          style: TextStyle(color: context.tt.onPrimaryContainer, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );

  // ── The paper ──────────────────────────────────────────────────────────────

  Widget _paper(BuildContext context) {
    final tt = context.tt;
    final api = context.read<Session>().api;
    final minutes = exam.integer('duration_minutes');
    final negative = exam.number('negative_marks_per_wrong');
    final instructions = exam.str('instructions').trim();
    final mcqMarks = _questions.fold<num>(0, (sum, q) => sum + q.number('points', q.number('marks', 1)));
    final cqMarks = _cq.fold<num>(0, (sum, q) => sum + q.maps('parts').fold<num>(0, (s, p) => s + p.number('marks')));
    final sir = tutorSirName(exam);
    final meta = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tt.textSecondary);

    return Material(
      color: tt.card,
      borderRadius: BorderRadius.circular(6),
      elevation: tt.isDark ? 0 : 1,
      shadowColor: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header, as printed at the top of a question paper.
            if (sir.isNotEmpty) Text(sir, textAlign: TextAlign.center, style: meta),
            const SizedBox(height: 4),
            Text(
              exam.str('title'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.3, color: tt.textPrimary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isAssignment
                        ? tr('Due: {p0}', {'p0': fmtDateTime(exam.date('end_time'))})
                        : minutes > 0
                            ? tr('Time: {p0} minutes', {'p0': minutes})
                            : tr('Closes: {p0}', {'p0': fmtDateTime(exam.date('end_time'))}),
                    style: meta,
                  ),
                ),
                Text(tr('Full marks: {p0}', {'p0': trimNumber(exam.number('total_marks'))}), style: meta),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, thickness: 1.2, color: tt.textTertiary.withValues(alpha: 0.5)),
            if (instructions.isNotEmpty || (negative > 0 && _questions.isNotEmpty)) ...[
              const SizedBox(height: 10),
              if (instructions.isNotEmpty)
                Text(
                  '[ $instructions ]',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, fontStyle: FontStyle.italic, height: 1.5, color: tt.textSecondary),
                ),
              if (negative > 0 && _questions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    tr('Each wrong MCQ answer loses {p0} mark(s); a blank one loses nothing.', {'p0': trimNumber(negative)}),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: tone(context, AppColors.warning)),
                  ),
                ),
            ],
            if (_questions.isNotEmpty) ...[
              _sectionHeading(context, _hasWritten ? tr('Section A — Multiple choice') : tr('Multiple choice'), mcqMarks),
              for (var i = 0; i < _questions.length; i++) ...[
                KeyedSubtree(key: _questionKeys[i], child: _mcqQuestion(context, i, _questions[i])),
                if (i < _questions.length - 1) Divider(height: 24, color: tt.border),
              ],
            ],
            if (_hasWritten) ...[
              _sectionHeading(
                context,
                _questions.isNotEmpty ? tr('Section B — Creative questions') : tr('Creative questions'),
                _cq.isNotEmpty ? cqMarks : null,
              ),
              if (_cq.isNotEmpty)
                for (final (i, q) in _cq.indexed) ...[
                  CqQuestionView(q, number: i + 1),
                  if (i < _cq.length - 1) const SizedBox(height: 18),
                ]
              else
                HtmlMath(exam.str('content_html'), baseUrl: api.baseUrl),
              const SizedBox(height: 18),
              KeyedSubtree(key: _linkKey, child: _answerLinkBox(context)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionHeading(BuildContext context, String title, num? marks) {
    final tt = context.tt;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 14),
      child: Row(
        children: [
          Expanded(child: Divider(color: tt.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              marks == null || marks <= 0 ? title : '$title · ${tr('{p0} marks', {'p0': trimNumber(marks)})}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.2, color: tt.textSecondary),
            ),
          ),
          Expanded(child: Divider(color: tt.border)),
        ],
      ),
    );
  }

  Widget _mcqQuestion(BuildContext context, int index, Json q) {
    final tt = context.tt;
    final id = q.str('id');
    final options = q.strings('options');
    final chosen = _answers[id];
    final points = q.number('points', q.number('marks', 1));
    final body = TextStyle(fontSize: 15, height: 1.5, color: tt.textPrimary);
    // Short options sit two to a row, like a printed paper; long ones get a row each.
    final twoColumns = options.length == 4 && options.every((o) => o.length <= 22 && !o.contains(r'$$'));

    Widget option(int i) {
      final selected = chosen == i;
      final letter = i < _letters.length ? _letters[i] : '${i + 1}';
      return Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _preview || _phase == _Phase.over
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  setState(() => selected ? _answers.remove(id) : _answers[id] = i);
                  _saveDraft();
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? tt.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The answer bubble, filled in when chosen.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? tt.primary : Colors.transparent,
                    border: Border.all(color: selected ? tt.primary : tt.textTertiary, width: 1.5),
                  ),
                  child: Text(
                    letter,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? tt.onPrimary : tt.textSecondary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: MathText(options[i], style: body.copyWith(fontSize: 14.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 30, child: Text('${localDigits('${index + 1}')}.', style: body.copyWith(fontWeight: FontWeight.w700))),
            Expanded(child: q.str('question').isEmpty ? const SizedBox.shrink() : MathText(q.str('question'), style: body)),
            const SizedBox(width: 8),
            Text(localDigits(trimNumber(points)), style: body.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: tt.textSecondary)),
          ],
        ),
        if (q.str('image_url').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 8, 0, 0),
            child: ServerImage(q.str('image_url'), label: tr('Question {p0} picture', {'p0': index + 1})),
          ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: twoColumns
              ? Column(
                  children: [
                    for (var row = 0; row < 2; row++)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Expanded(child: option(row * 2)), Expanded(child: option(row * 2 + 1))],
                      ),
                  ],
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = 0; i < options.length; i++) option(i)]),
        ),
      ],
    );
  }

  /// Where the student hands in the written part: one link to their answer sheet.
  Widget _answerLinkBox(BuildContext context) {
    final tt = context.tt;
    final text = _link.text.trim();
    final ok = _linkOk;
    final bad = text.isNotEmpty && !ok;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok ? tt.successContainer : tt.cardRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.check_circle_rounded : Icons.link_rounded, size: 20, color: ok ? tt.success : tt.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('Your written answer sheet'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tt.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr('Write the answers on paper. Scan or photograph the pages into one PDF or folder, upload it to Google Drive (or any site), set it so anyone with the link can view, and paste the link here.'),
            style: TextStyle(fontSize: 13, height: 1.5, color: tt.textSecondary),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _link,
            enabled: !_preview,
            keyboardType: TextInputType.url,
            autocorrect: false,
            maxLength: 1000,
            decoration: InputDecoration(
              hintText: 'https://drive.google.com/…',
              counterText: '',
              errorText: bad ? tr('Paste the full link that starts with https://') : null,
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: text.isEmpty
                  ? IconButton(tooltip: tr('Paste'), icon: const Icon(Icons.content_paste_rounded), onPressed: _preview ? null : _pasteLink)
                  : IconButton(tooltip: tr('Clear'), icon: const Icon(Icons.close_rounded), onPressed: () => _link.clear()),
            ),
          ),
          if (ok)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openExternal(context, text),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(tr('Check the link opens')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _submitButton(BuildContext context) {
    final tt = context.tt;
    return FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: tt.success, foregroundColor: tt.background, minimumSize: const Size.fromHeight(54)),
      onPressed: (_submitting || _phase == _Phase.over) ? null : () => _submit(),
      icon: _submitting
          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: tt.background))
          : const Icon(Icons.send_rounded),
      label: Text(_submitting ? tr('Sending…') : (_isAssignment ? tr('Turn in assignment') : tr('Turn in exam'))),
    );
  }

  /// A grid of question numbers — answered ones filled — to jump around the paper.
  void _openNavigator() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) {
        final tt = sheet.tt;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('{p0} of {p1} MCQ answered', {'p0': _answers.length, 'p1': _questions.length}),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tt.textPrimary),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _questions.length; i++)
                      Builder(builder: (_) {
                        final done = _answers.containsKey(_questions[i].str('id'));
                        return InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            Navigator.pop(sheet);
                            _jumpTo(_questionKeys[i]);
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: done ? tt.primary : tt.cardRaised,
                            ),
                            child: Text(
                              localDigits('${i + 1}'),
                              style: TextStyle(fontWeight: FontWeight.w700, color: done ? tt.onPrimary : tt.textSecondary),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
                if (_hasWritten) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheet);
                      _jumpTo(_linkKey);
                    },
                    icon: Icon(_linkOk ? Icons.check_circle_rounded : Icons.link_rounded, size: 18),
                    label: Text(_linkOk ? tr('Written answer link added') : tr('Add the written answer link')),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
