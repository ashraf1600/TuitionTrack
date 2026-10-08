import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
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
  String get _draftKey => 'exam_draft_${exam.str('id')}';
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
        setState(() => _error = 'The submission time has ended.');
        return;
      }
      if (_mcqOnly && _answers.isEmpty) {
        setState(() => _error = 'Choose an answer for at least one question.');
        return;
      }
      if (!_mcqOnly && !hasWritten && _answers.isEmpty) {
        setState(() => _error = 'Answer the questions, type your answer, or add a photo of your written work.');
        return;
      }
      if (_hasPaper && !hasWritten) {
        setState(() => _error = 'The written part needs an answer: type it or add a photo.');
        return;
      }
      final unanswered = _questions.length - _answers.length;
      final ok = await confirm(
        context,
        title: _isAssignment ? 'Turn in the assignment?' : 'Turn in the exam?',
        message: unanswered > 0
            ? 'You have left $unanswered question${unanswered == 1 ? '' : 's'} blank. You cannot change your answers after turning in.'
            : 'You cannot change your answers after turning in.',
        confirmLabel: 'Turn in',
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
        _error = auto ? 'Time is up, and your answers could not be sent: ${error.message} Tap "Turn in" to try again.' : error.message;
      });
    }
  }

  Future<bool> _confirmLeave() async {
    if (_submitting) return false;
    return confirm(
      context,
      title: 'Leave without turning in?',
      message: exam.flag('is_timed')
          ? 'Your answers are saved on this phone, but the clock keeps running. Come back before the time ends.'
          : 'Your answers are saved on this phone. Come back and turn in before the deadline.',
      confirmLabel: 'Leave',
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<Session>().api;
    final warning = _phase == _Phase.late || _phase == _Phase.grace || _phase == _Phase.over;
    final timerColor = warning ? AppColors.warning : (_left.inSeconds <= 300 ? AppColors.danger : AppColors.primarySoft);
    final timerLabel = switch (_phase) {
      _Phase.over => 'Time is up',
      _Phase.late => 'Deadline passed — late work accepted for',
      _Phase.grace => 'Time is up — sending your answers',
      _Phase.onTime => exam.flag('is_timed')
          ? 'Your time remaining'
          : _isAssignment
              ? 'Time until the deadline'
              : 'Time remaining',
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
                color: timerColor.withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, color: timerColor),
                    const SizedBox(width: 10),
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
                        Text('${trimNumber(exam.number('total_marks'))} marks', style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (_questions.isNotEmpty)
                          Text('${_answers.length} of ${_questions.length} answered', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
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
                      'Each wrong answer loses ${trimNumber(exam.number('negative_marks_per_wrong'))} mark(s). A blank answer loses nothing.',
                      color: AppColors.warning,
                    ),
                    gap12,
                  ],
                  if (_questions.isNotEmpty) ...[
                    const SectionTitle('Multiple choice', subtitle: 'Tap an option to choose it. Tap it again to clear.'),
                    for (var i = 0; i < _questions.length; i++) ...[_question(i, _questions[i]), gap12],
                  ],
                  if (_hasPaper) ...[
                    const SectionTitle('Written questions'),
                    AppCard(child: HtmlMath(exam.str('content_html'), baseUrl: api.baseUrl)),
                    gap12,
                  ],
                  if (!_mcqOnly) ...[
                    const SectionTitle('Your written answer', subtitle: 'Type it, add photos of your handwritten work, or both.'),
                    TextField(
                      controller: _text,
                      maxLines: 6,
                      maxLength: 20000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'Type your answer here', alignLabelWithHint: true),
                    ),
                    gap8,
                    OutlinedButton.icon(
                      onPressed: _uploading ? null : _addPhotos,
                      icon: _uploading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_a_photo_outlined),
                      label: Text(_uploading ? 'Uploading…' : 'Add photos of your answer'),
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
                                SizedBox(width: 96, child: ServerImage(_images[i], height: 96, fit: BoxFit.cover, label: 'Page ${i + 1}')),
                                Positioned(
                                  top: -8,
                                  right: -8,
                                  child: IconButton.filled(
                                    tooltip: 'Remove page ${i + 1}',
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xFFBE123C),
                                      minimumSize: const Size(28, 28),
                                      padding: EdgeInsets.zero,
                                    ),
                                    icon: const Icon(Icons.close, size: 16, color: Colors.white),
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
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669), minimumSize: const Size.fromHeight(52)),
                    onPressed: (_submitting || _uploading || _phase == _Phase.over) ? null : () => _submit(),
                    icon: _submitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                    label: Text(_submitting ? 'Sending…' : (_isAssignment ? 'Turn in assignment' : 'Turn in exam')),
                  ),
                  if (_phase == _Phase.over)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('The submission time has ended.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.danger)),
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
                backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                child: Text('${index + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primarySoft)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: q.str('question').isEmpty
                    ? const SizedBox.shrink()
                    : MathText(q.str('question'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
              ),
              const SizedBox(width: 8),
              Text('${trimNumber(q.number('points', 1))} mark${q.number('points', 1) == 1 ? '' : 's'}', style: const TextStyle(color: AppColors.success, fontSize: 12)),
            ],
          ),
          if (q.str('image_url').isNotEmpty) ...[gap8, ServerImage(q.str('image_url'), label: 'Question ${index + 1} picture')],
          gap12,
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                inMutuallyExclusiveGroup: true,
                checked: chosen == i,
                child: Material(
                  color: chosen == i ? AppColors.primary.withValues(alpha: 0.2) : AppColors.card.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: chosen == i ? AppColors.primary : AppColors.border),
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
                            backgroundColor: chosen == i ? AppColors.primary : AppColors.border,
                            child: Text(
                              i < _letters.length ? _letters[i] : '${i + 1}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
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
