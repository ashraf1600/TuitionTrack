import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/math_text.dart';
import '../../widgets/media.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

const _letters = ['A', 'B', 'C', 'D', 'E'];

/// Sitting an exam or handing in an assignment.
///
/// The countdown follows the server clock. At the deadline the answers are sent
/// automatically once (the server allows a short grace period for that); if the
/// tutor accepts late work nothing is sent automatically and the student can
/// hand in late. Answers are saved on the device as they are given, so leaving
/// the screen never loses them. Pops with the server's response after a
/// successful submission.
class ExamTakeScreen extends StatefulWidget {
  const ExamTakeScreen({super.key, required this.exam});

  /// The exam as returned by `POST /exams/<id>/start/` — questions without any answers.
  final Json exam;

  @override
  State<ExamTakeScreen> createState() => _ExamTakeScreenState();
}

enum _Phase { onTime, late, grace, over }

class _ExamTakeScreenState extends State<ExamTakeScreen> {
  final _answers = <String, int>{};
  final _text = TextEditingController();
  final _images = <String>[];
  Timer? _ticker;
  Duration _left = Duration.zero;
  _Phase _phase = _Phase.onTime;
  bool _submitting = false;
  bool _uploading = false;
  bool _autoSent = false;
  String? _error;

  Json get exam => widget.exam;

  /// Drafts are per exam and per account, so two students sharing a phone never see each other's answers.
  late final String _draftKey;
  List<Json> get _questions => exam.maps('mcq_data');
  bool get _mcqOnly => exam.str('exam_type') == 'MCQ';
  bool get _isAssignment => exam.str('category') == 'ASSIGNMENT';
  bool get _hasPaper {
    final html = exam.str('content_html').trim();
    return !_mcqOnly && html.isNotEmpty && html != '<p></p>' && html != '<p>Multiple Choice Examination</p>';
  }

  @override
  void initState() {
    super.initState();
    final userId = context.read<Session>().user?.str('id') ?? '';
    _draftKey = 'exam_draft_${exam.str('id')}_$userId';
    _restoreDraft();
    _text.addListener(_saveDraft);
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _text.dispose();
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
      _text.text = '${draft['text'] ?? ''}';
      _images.addAll((draft['images'] as List? ?? const []).map((e) => '$e'));
    } catch (_) {
      // a damaged draft is simply ignored
    }
  }

  void _saveDraft() {
    context.read<Session>().settings.setString(_draftKey, jsonEncode({'answers': _answers, 'text': _text.text, 'images': _images}));
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

  Future<void> _addPhotos() async {
    setState(() => _uploading = true);
    final urls = await pickAndUpload(context);
    if (!mounted) return;
    setState(() {
      _images.addAll(urls);
      _uploading = false;
    });
    _saveDraft();
  }

  Future<void> _submit({bool auto = false}) async {
    if (_submitting) return;
    final hasWritten = _images.isNotEmpty || _text.text.trim().isNotEmpty;
    if (!auto) {
      setState(() => _error = null);
      if (_phase == _Phase.over) {
        setState(() => _error = tr('The submission time has ended.'));
        return;
      }
      if (_mcqOnly && _answers.isEmpty) {
        setState(() => _error = tr('Choose an answer for at least one question.'));
        return;
      }
      if (!_mcqOnly && !hasWritten && _answers.isEmpty) {
        setState(() => _error = tr('Answer the questions, type your answer, or add a photo of your written work.'));
        return;
      }
      if (_hasPaper && !hasWritten) {
        setState(() => _error = tr('The written part needs an answer: type it or add a photo.'));
        return;
      }
      final unanswered = _questions.length - _answers.length;
      final ok = await confirm(
        context,
        title: _isAssignment ? tr('Turn in the assignment?') : tr('Turn in the exam?'),
        message: unanswered > 0
            ? tr('You have left {p0} question{p1} blank. You cannot change your answers after turning in.', {'p0': unanswered, 'p1': unanswered == 1 ? '' : 's'})
            : tr('You cannot change your answers after turning in.'),
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
            text: _text.text.trim(),
            images: _images,
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
    final api = context.read<Session>().api;
    final warning = _phase == _Phase.late || _phase == _Phase.grace || _phase == _Phase.over;
    final timerColor = warning ? AppColors.warning : (_left.inSeconds <= 300 ? AppColors.danger : AppColors.primarySoft);
    final timerLabel = switch (_phase) {
      _Phase.over => tr('Time is up'),
      _Phase.late => tr('Deadline passed — late work accepted for'),
      _Phase.grace => tr('Time is up — sending your answers'),
      _Phase.onTime => exam.flag('is_timed')
          ? tr('Your time remaining')
          : _isAssignment
              ? tr('Time until the deadline')
              : tr('Time remaining'),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(exam.str('title'), overflow: TextOverflow.ellipsis)),
        body: Column(
          children: [
            Semantics(
              liveRegion: _left.inSeconds % 60 == 0,
              child: Container(
                width: double.infinity,
                color: tonalContainer(context, timerColor),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, color: timerColor),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(timerLabel, style: TextStyle(color: timerColor, fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(
                            countdown(_left),
                            style: TextStyle(
                              color: timerColor,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(tr('{p0} marks', {'p0': trimNumber(exam.number('total_marks'))}), style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (_questions.isNotEmpty)
                          Text(tr('{p0} of {p1} answered', {'p0': _answers.length, 'p1': _questions.length}), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: PageBody(
                children: [
                  if (_error != null) ...[Banner2(_error!, color: AppColors.danger, icon: Icons.error_outline), gap12],
                  if (exam.number('negative_marks_per_wrong') > 0 && _questions.isNotEmpty) ...[
                    Banner2(
                      tr('Each wrong answer loses {p0} mark(s). A blank answer loses nothing.', {'p0': trimNumber(exam.number('negative_marks_per_wrong'))}),
                      color: AppColors.warning,
                    ),
                    gap12,
                  ],
                  if (_questions.isNotEmpty) ...[
                    SectionTitle(tr('Multiple choice'), subtitle: tr('Tap an option to choose it. Tap it again to clear.')),
                    for (var i = 0; i < _questions.length; i++) ...[_question(i, _questions[i]), gap12],
                  ],
                  if (_hasPaper) ...[
                    SectionTitle(tr('Written questions')),
                    AppCard(child: HtmlMath(exam.str('content_html'), baseUrl: api.baseUrl)),
                    gap12,
                  ],
                  if (!_mcqOnly) ...[
                    SectionTitle(tr('Your written answer'), subtitle: tr('Type it, add photos of your handwritten work, or both.')),
                    TextField(
                      controller: _text,
                      maxLines: 6,
                      maxLength: 20000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: tr('Type your answer here'), alignLabelWithHint: true),
                    ),
                    gap8,
                    OutlinedButton.icon(
                      onPressed: _uploading ? null : _addPhotos,
                      icon: _uploading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_a_photo_outlined),
                      label: Text(_uploading ? tr('Uploading…') : tr('Add photos of your answer')),
                    ),
                    if (_images.isNotEmpty) ...[
                      gap12,
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (var i = 0; i < _images.length; i++)
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                SizedBox(width: 96, child: ServerImage(_images[i], height: 96, fit: BoxFit.cover, label: tr('Page {p0}', {'p0': i + 1}))),
                                Positioned(
                                  top: -8,
                                  right: -8,
                                  child: IconButton.filled(
                                    tooltip: tr('Remove page {p0}', {'p0': i + 1}),
                                    style: IconButton.styleFrom(
                                      backgroundColor: context.tt.danger,
                                      minimumSize: const Size(28, 28),
                                      padding: EdgeInsets.zero,
                                    ),
                                    icon: Icon(Icons.close, size: 16, color: context.tt.background),
                                    onPressed: () {
                                      setState(() => _images.removeAt(i));
                                      _saveDraft();
                                    },
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ],
                  gap24,
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: context.tt.success,
                      foregroundColor: context.tt.background,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: (_submitting || _uploading || _phase == _Phase.over) ? null : () => _submit(),
                    icon: _submitting
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.tt.background))
                        : const Icon(Icons.send),
                    label: Text(_submitting ? tr('Sending…') : (_isAssignment ? tr('Turn in assignment') : tr('Turn in exam'))),
                  ),
                  if (_phase == _Phase.over)
                    Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(tr('The submission time has ended.'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.danger)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _question(int index, Json q) {
    final id = q.str('id');
    final options = q.strings('options');
    final chosen = _answers[id];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: context.tt.primaryContainer,
                child: Text(localDigits('${index + 1}'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.tt.onPrimaryContainer)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: q.str('question').isEmpty
                    ? const SizedBox.shrink()
                    : MathText(q.str('question'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
              ),
              const SizedBox(width: 8),
              Text(tr('{p0} mark{p1}', {'p0': trimNumber(q.number('points', 1)), 'p1': q.number('points', 1) == 1 ? '' : 's'}), style: const TextStyle(color: AppColors.success, fontSize: 12)),
            ],
          ),
          if (q.str('image_url').isNotEmpty) ...[gap8, ServerImage(q.str('image_url'), label: tr('Question {p0} picture', {'p0': index + 1}))],
          gap12,
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                inMutuallyExclusiveGroup: true,
                checked: chosen == i,
                child: Material(
                  color: chosen == i ? context.tt.primaryContainer : context.tt.cardRaised,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: chosen == i ? context.tt.primary : Colors.transparent),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      setState(() => chosen == i ? _answers.remove(id) : _answers[id] = i);
                      _saveDraft();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: chosen == i ? context.tt.primary : context.tt.cardRaised,
                            child: Text(
                              i < _letters.length ? _letters[i] : '${i + 1}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: chosen == i ? context.tt.onPrimary : context.tt.textSecondary),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: MathText(options[i], style: const TextStyle(fontSize: 14))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
