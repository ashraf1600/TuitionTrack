import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/connect.dart';
import '../../core/i18n.dart';
import '../../core/repo.dart';
import '../../widgets/media.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

/// Phase 4 (critical): ticking countdown + <=2h alert + role-correct actions.
///
/// Student sees Upload + "Pending Tutor Review"/"Marked as Done".
/// Tutor sees "Mark as Done" (the only writer of is_evaluated=true).
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
  final _url = TextEditingController();

  @override
  void initState() {
    super.initState();
    _url.text = widget.hw.submittedUrl;
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
    _url.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final left = widget.hw.dueDate.difference(DateTime.now());
    setState(() => _left = left);
    // Alert once: <= 7200s AND not evaluated AND still in the future.
    if (!_alertShown && !widget.hw.isEvaluated && left.inSeconds > 0 && left.inSeconds <= 7200) {
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

  Future<void> _submit() async {
    HapticFeedback.lightImpact();
    final repo = context.read<Repo>();
    setState(() => _busy = true);
    try {
      final ok = await attemptSave(context, () => repo.submitHomework(widget.hw.id, _url.text.trim()),
          success: tr('Submission recorded.'));
      if (ok) await widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Marks the homework checked at once, with Undo instead of a confirmation.
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

  @override
  Widget build(BuildContext context) {
    final hw = widget.hw;
    final urgent = !hw.isEvaluated && _left.inSeconds > 0 && _left.inSeconds <= 7200;
    final tt = context.tt;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (urgent)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: tt.dangerContainer, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.alarm, color: tt.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tr('Hurry! Homework due in less than 2 hours!'),
                        style: TextStyle(color: tt.danger, fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(hw.title, style: TextStyle(fontSize: 17, height: 1.3, fontWeight: FontWeight.w600, color: tt.textPrimary))),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
          if (_byline(hw).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_byline(hw), style: TextStyle(fontSize: 13, color: tt.textSecondary)),
            ),
          if (hw.description.isNotEmpty) ...[gap8, Text(hw.description, style: const TextStyle(fontSize: 14, height: 1.5))],
          gap12,
          // Status as icon + word chips: the time left, and where the work stands.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill(_countdown,
                  color: _left.isNegative || urgent ? AppColors.danger : AppColors.primarySoft,
                  icon: _left.isNegative ? Icons.schedule_rounded : Icons.timer_outlined),
              if (hw.isPending)
                Pill(tr('Waiting to sync'), color: AppColors.primarySoft, icon: Icons.cloud_upload_outlined)
              else
                Pill(hw.isEvaluated ? tr('Marked as Done') : tr('Pending Tutor Review'),
                    color: hw.isEvaluated ? AppColors.success : AppColors.warning,
                    icon: hw.isEvaluated ? Icons.check_rounded : Icons.hourglass_empty_rounded),
            ],
          ),
          if (hw.feedback.isNotEmpty) ...[gap12, Text(tr('Feedback: {p0}', {'p0': hw.feedback}), style: const TextStyle(fontSize: 14, height: 1.5))],
          // What the student handed in, for the tutor to review (and for the student to check).
          if (hw.submittedUrl.isNotEmpty || hw.submissionFileUrl.isNotEmpty) ...[
            gap12,
            if (hw.submittedUrl.isNotEmpty)
              _QuietButton(icon: Icons.link_rounded, label: tr('Open submitted link'), onPressed: () => openExternal(context, hw.submittedUrl)),
            if (hw.submittedUrl.isNotEmpty && hw.submissionFileUrl.isNotEmpty) gap8,
            if (hw.submissionFileUrl.isNotEmpty)
              _QuietButton(icon: Icons.attach_file_rounded, label: tr('Open submitted file'), onPressed: () => openExternal(context, hw.submissionFileUrl)),
          ] else if (widget.isTutor && hw.isSubmitted) ...[
            gap8,
            Text(tr('Marked as submitted (no link or file).'), style: TextStyle(fontSize: 13, color: tt.textSecondary)),
          ],
          gap12,
          if (hw.isPending)
            Text(tr('Assigned on this phone while offline. It reaches your students once you are back online.'),
                style: TextStyle(fontSize: 13, color: tt.textSecondary))
          else if (!widget.isTutor) ...[
            // Checked work is closed: the server refuses changes after the tutor marks it done.
            if (!hw.isEvaluated) ...[
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: tr('Submission link (optional)'),
                  hintText: tr('https://docs.google.com/...'),
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              gap8,
              SizedBox(
                width: double.infinity,
                child: BusyButton(
                  label: _busy ? tr('Submitting...') : (hw.isSubmitted ? tr('Update submission') : tr('Submit homework')),
                  icon: Icons.upload,
                  onPressed: _busy
                      ? null
                      : () async {
                          HapticFeedback.lightImpact();
                          await _submit();
                        },
                ),
              ),
            ],
          ] else if (hw.isEvaluated)
            // Rest state: nothing left to do on this one.
            Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tt.isDark ? tt.background : tt.cardRaised, borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_rounded, size: 18, color: tt.textSecondary),
                  const SizedBox(width: 8),
                  Text(tr('Evaluated ✓').replaceAll('✓', '').trim(),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tt.textSecondary)),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: BusyButton(
                label: tr('Mark as Done'),
                icon: Icons.check_rounded,
                onPressed: _busy
                    ? null
                    : () async {
                        HapticFeedback.lightImpact();
                        await _markDone();
                      },
              ),
            ),
        ],
      ),
    );
  }
}

/// A full-width, quiet 48 dp button for secondary actions on a card.
class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          backgroundColor: tt.isDark ? tt.background : tt.cardRaised,
          foregroundColor: tt.textPrimary,
          minimumSize: const Size.fromHeight(48),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}
