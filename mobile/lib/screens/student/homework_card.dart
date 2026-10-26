import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/connect.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/repo.dart';
import '../../widgets/math_text.dart';
import '../../widgets/media.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

/// One homework, for either side, with a ticking countdown.
///
/// Student: "Homework done?" → Yes; then it waits for the tutor (Undo until checked).
/// Tutor: when the student says done, "Done" or "Not done" (sent back with a note);
/// otherwise "Mark as done" after checking it on paper.
class HomeworkCard extends StatefulWidget {
  const HomeworkCard({super.key, required this.hw, required this.isTutor, required this.onChanged, this.trailing, this.showTutor = false});

  /// Student view: name the tutor ("Ashraf Sir") under the title.
  final bool showTutor;
  final HomeworkItem hw;
  final bool isTutor;
  final Future<void> Function() onChanged;

  /// A small action at the card's top right (the tutor's delete button).
  final Widget? trailing;

  @override
  State<HomeworkCard> createState() => _HomeworkCardState();
}

class _HomeworkCardState extends State<HomeworkCard> {
  /// "Ashraf Sir · Class 4 · Oct 9": who set it (students only) and where it came from.
  String _byline(HomeworkItem hw) => [
        if (!widget.isTutor && widget.showTutor && hw.tutorDisplay.isNotEmpty) hw.tutorDisplay,
        if (hw.sourceLabel.isNotEmpty) hw.sourceLabel,
      ].join(' · ');

  Timer? _timer;
  Duration _left = Duration.zero;
  bool _alertShown = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(HomeworkCard old) {
    super.didUpdateWidget(old);
    if (old.hw.id != widget.hw.id || old.hw.dueDate != widget.hw.dueDate) {
      _alertShown = false;
      _tick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel(); // prevent memory leaks
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final left = widget.hw.dueDate.difference(DateTime.now());
    setState(() => _left = left);
    // Alert once: <= 7200s AND not evaluated AND still in the future. Tutors get
    // a dialog; for students the card itself turns red (a pop-up on every list
    // open would only get in the way).
    if (widget.isTutor && !_alertShown && !widget.hw.isEvaluated && left.inSeconds > 0 && left.inSeconds <= 7200) {
      _alertShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        HapticFeedback.lightImpact();
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(tr('Hurry!')),
            content: Text(tr('Homework "{p0}" is due in less than 2 hours!', {'p0': widget.hw.title})),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('OK')))],
          ),
        );
      });
    }
  }

  String get _countdown {
    if (_left.isNegative) return tr('Overdue');
    final h = _left.inHours;
    final m = _left.inMinutes % 60;
    final s = _left.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return tr('{p0}h : {p1}m : {p2}s left', {'p0': two(h), 'p1': two(m), 'p2': two(s)});
  }

  String get _sir => widget.hw.tutorDisplay.isEmpty ? tr('your tutor') : widget.hw.tutorDisplay;

  /// Runs [action] with the card busy, then reloads the list.
  Future<void> _run(Future<bool> Function() action) async {
    setState(() => _busy = true);
    try {
      if (await action()) await widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Student: "Homework done?" → Yes. The tutor then checks it.
  Future<void> _sayDone() async {
    HapticFeedback.lightImpact();
    final yes = await confirm(
      context,
      title: tr('Homework done?'),
      message: tr('Tell {p0} you finished "{p1}". {p0} will check it and mark it done.', {'p0': Raw(_sir), 'p1': widget.hw.title}),
      confirmLabel: tr('Yes, done'),
    );
    if (!yes || !mounted) return;
    final repo = context.read<Repo>();
    await _run(() => attemptSave(context, () => repo.submitHomework(widget.hw.id, ''),
        success: tr('Sent. Waiting for {p0} to check.', {'p0': Raw(_sir)})));
    HapticFeedback.mediumImpact();
  }

  /// Student: a mistaken tap. Only before the tutor checks it.
  Future<void> _undoDone() async {
    HapticFeedback.lightImpact();
    final repo = context.read<Repo>();
    await _run(() => attempt(context, () => repo.undoHomeworkDone(widget.hw.id), success: tr('Back to to-do.')));
  }

  /// Tutor: done. At once, with Undo instead of a confirmation.
  Future<void> _markDone() async {
    HapticFeedback.lightImpact();
    final repo = context.read<Repo>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      Json result = const {};
      final done = await attempt(context, () async {
        result = await repo.evaluateHomework(widget.hw.id, evaluated: true);
      });
      if (!done || !mounted) return;
      final onChanged = widget.onChanged;
      final id = widget.hw.id;
      showToast(
        context,
        result['queued'] == true ? tr('Saved on this phone. It will be sent when you are back online.') : tr('Marked as done.'),
        actionLabel: tr('Undo'),
        onAction: () async {
          try {
            await repo.evaluateHomework(id, evaluated: false);
          } on ApiException catch (error) {
            showToastOn(messenger, error.message, error: true);
          }
          await onChanged();
        },
      );
      await onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tutor: the student said done but it is not. Back to them with an optional note.
  Future<void> _notDone() async {
    HapticFeedback.lightImpact();
    final note = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(tr('Not done?')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('"{p0}" goes back to the student as to-do.', {'p0': widget.hw.title})),
            gap12,
            TextField(
              controller: note,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(labelText: tr('Note for the student (optional)'), hintText: tr('e.g. Q4 and Q5 are missing')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TtColors.lDanger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(tr('Send back')),
          ),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (send != true || !mounted) return;
    final repo = context.read<Repo>();
    await _run(() => attempt(context, () => repo.homeworkNotDone(widget.hw.id, note: text), success: tr('Sent back as not done.')));
  }

  /// A tinted note box: the tutor's feedback (green) or why it was sent back (red).
  Widget _noteBox(BuildContext context, String label, String text, {required bool warning}) {
    final tt = context.tt;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: warning ? tt.dangerContainer : tt.successContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote_rounded, size: 18, color: warning ? tt.danger : tt.onSuccessContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: warning ? tt.danger : tt.onSuccessContainer)),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(fontSize: 14, height: 1.45, color: tt.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Links handed in with older app versions, still openable.
  List<Widget> _oldHandIn(BuildContext context, HomeworkItem hw) => [
        if (hw.submittedUrl.isNotEmpty || hw.submissionFileUrl.isNotEmpty) ...[
          gap8,
          Wrap(
            spacing: 8,
            children: [
              if (hw.submittedUrl.isNotEmpty)
                TextButton.icon(
                  onPressed: () => openExternal(context, hw.submittedUrl),
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: Text(tr('Link')),
                ),
              if (hw.submissionFileUrl.isNotEmpty)
                TextButton.icon(
                  onPressed: () => openExternal(context, hw.submissionFileUrl),
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: Text(tr('File')),
                ),
            ],
          ),
        ],
      ];

  /// The student's card: where it stands, when it is due, and one button.
  Widget _studentCard(BuildContext context) {
    final hw = widget.hw;
    final tt = context.tt;
    final late = _left.isNegative;
    final open = !hw.isSubmitted && !hw.isEvaluated;
    final urgent = open && !late && _left.inSeconds <= 7200;
    final (String status, Color color, IconData icon) = hw.isPending
        ? (tr('Waiting to sync'), AppColors.primarySoft, Icons.cloud_upload_outlined)
        : hw.isEvaluated
            ? (tr('Done · checked by {p0}', {'p0': Raw(_sir)}), AppColors.success, Icons.verified_rounded)
            : hw.isSubmitted
                ? (tr('You said done · {p0} will check', {'p0': Raw(_sir)}), AppColors.primarySoft, Icons.hourglass_top_rounded)
                : hw.isSentBack
                    ? (tr('{p0} says not done', {'p0': Raw(_sir)}), AppColors.danger, Icons.replay_rounded)
                    : late
                        ? (tr('Not done · late'), AppColors.danger, Icons.error_outline_rounded)
                        : (tr('To do'), AppColors.warning, Icons.radio_button_unchecked_rounded);
    final gap = _left.abs();
    final gapText = gap.inDays >= 1 ? tr('{n} d', {'n': gap.inDays}) : (gap.inHours >= 1 ? tr('{n} h', {'n': gap.inHours}) : tr('{n} min', {'n': gap.inMinutes}));
    final dueText = !open
        ? tr('Was due {p0}', {'p0': fmtDateTime(hw.dueDate)})
        : late
            ? tr('Due {p0} · {p1} late', {'p0': fmtDateTime(hw.dueDate), 'p1': Raw(gapText)})
            : tr('Due {p0} · in {p1}', {'p0': fmtDateTime(hw.dueDate), 'p1': Raw(gapText)});
    final red = urgent || (late && open);

    return AppCard(
      borderColor: urgent || hw.isSentBack ? tt.danger.withValues(alpha: 0.6) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pill(status, color: color, icon: icon),
          gap12,
          MathText(hw.title, style: TextStyle(fontSize: 17, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: tt.textPrimary)),
          if (_byline(hw).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(_byline(hw), style: TextStyle(fontSize: 13, color: tt.textSecondary)),
            ),
          if (hw.description.isNotEmpty) ...[
            gap8,
            MathText(hw.description, maxLines: 4, style: TextStyle(fontSize: 14, height: 1.5, color: tt.textPrimary)),
          ],
          gap12,
          Row(
            children: [
              Icon(Icons.event_rounded, size: 16, color: red ? tt.danger : tt.textTertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dueText,
                  style: TextStyle(fontSize: 13, fontWeight: urgent ? FontWeight.w700 : FontWeight.w500, color: red ? tt.danger : tt.textSecondary),
                ),
              ),
            ],
          ),
          if (hw.feedback.isNotEmpty) ...[
            gap12,
            _noteBox(
              context,
              hw.isSentBack ? tr('Why {p0} sent it back', {'p0': Raw(_sir)}) : tr('Feedback from {p0}', {'p0': Raw(_sir)}),
              hw.feedback,
              warning: hw.isSentBack,
            ),
          ],
          ..._oldHandIn(context, hw),
          if (!hw.isPending && !hw.isEvaluated) ...[
            gap12,
            SizedBox(
              width: double.infinity,
              child: hw.isSubmitted
                  ? OutlinedButton.icon(
                      onPressed: _busy ? null : _undoDone,
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: Text(tr('Not done yet? Undo')),
                    )
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: AppColors.successDeep,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _busy ? null : _sayDone,
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                      label: Text(tr('Homework done?')),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isTutor) return _studentCard(context);
    final hw = widget.hw;
    final tt = context.tt;
    final urgent = !hw.isEvaluated && !hw.isSubmitted && _left.inSeconds > 0 && _left.inSeconds <= 7200;
    final who = hw.studentName.isNotEmpty ? hw.studentName : tr('Student');
    final (String status, Color color, IconData icon) = hw.isPending
        ? (tr('Waiting to sync'), AppColors.primarySoft, Icons.cloud_upload_outlined)
        : hw.isEvaluated
            ? (tr('Done'), AppColors.success, Icons.check_rounded)
            : hw.isSubmitted
                ? (tr('{p0} says done', {'p0': Raw(who)}), AppColors.primarySoft, Icons.front_hand_rounded)
                : hw.isSentBack
                    ? (tr('Sent back · not done'), AppColors.danger, Icons.replay_rounded)
                    : (tr('Not done yet'), AppColors.warning, Icons.hourglass_empty_rounded);
    return AppCard(
      borderColor: hw.isSubmitted && !hw.isEvaluated ? tt.primary.withValues(alpha: 0.6) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: MathText(hw.title, style: TextStyle(fontSize: 17, height: 1.3, fontWeight: FontWeight.w600, color: tt.textPrimary))),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
          if (_byline(hw).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_byline(hw), style: TextStyle(fontSize: 13, color: tt.textSecondary)),
            ),
          if (hw.description.isNotEmpty) ...[gap8, MathText(hw.description, style: const TextStyle(fontSize: 14, height: 1.5))],
          gap12,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill(status, color: color, icon: icon),
              if (!hw.isEvaluated)
                Pill(_countdown,
                    color: _left.isNegative || urgent ? AppColors.danger : AppColors.muted,
                    icon: _left.isNegative ? Icons.schedule_rounded : Icons.timer_outlined),
            ],
          ),
          if (hw.feedback.isNotEmpty) ...[
            gap12,
            Text(hw.isSentBack ? tr('Your note: {p0}', {'p0': hw.feedback}) : tr('Feedback: {p0}', {'p0': hw.feedback}),
                style: TextStyle(fontSize: 14, height: 1.5, color: tt.textSecondary)),
          ],
          ..._oldHandIn(context, hw),
          gap12,
          if (hw.isPending)
            Text(tr('Assigned on this phone while offline. It reaches your students once you are back online.'),
                style: TextStyle(fontSize: 13, color: tt.textSecondary))
          else if (hw.isEvaluated)
            // Rest state: nothing left to do on this one.
            Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tt.isDark ? tt.background : tt.cardRaised, borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, size: 18, color: tt.textSecondary),
                  const SizedBox(width: 8),
                  Text(tr('Checked'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tt.textSecondary)),
                ],
              ),
            )
          else if (hw.isSubmitted)
            // The student says done: confirm it, or send it back.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: tone(context, AppColors.danger)),
                    onPressed: _busy ? null : _notDone,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: Text(tr('Not done')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: AppColors.successDeep, foregroundColor: Colors.white),
                    onPressed: _busy ? null : _markDone,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(tr('Done')),
                  ),
                ),
              ],
            )
          else
            // Checked on paper in class: mark it done without waiting for the student.
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : _markDone,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(hw.isSharedGroupTask ? tr('Mark done for everyone') : tr('Mark as done')),
              ),
            ),
        ],
      ),
    );
  }
}
