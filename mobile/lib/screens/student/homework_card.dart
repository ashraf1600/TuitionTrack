import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart';
import '../../core/repo.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

/// Phase 4 (critical): ticking countdown + <=2h alert + role-correct actions.
///
/// Student sees Upload + "Pending Tutor Review"/"Marked as Done".
/// Tutor sees "Mark as Done" (the only writer of is_evaluated=true).
class HomeworkCard extends StatefulWidget {
  const HomeworkCard({super.key, required this.hw, required this.isTutor, required this.onChanged});
  final HomeworkItem hw;
  final bool isTutor;
  final Future<void> Function() onChanged;

  @override
  State<HomeworkCard> createState() => _HomeworkCardState();
}

class _HomeworkCardState extends State<HomeworkCard> {
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
            title: const Text('Hurry!'),
            content: Text('Homework "${widget.hw.title}" is due in less than 2 hours!'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      });
    }
  }

  String get _countdown {
    if (_left.isNegative) return 'Overdue';
    final h = _left.inHours;
    final m = _left.inMinutes % 60;
    final s = _left.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(h)}h : ${two(m)}m : ${two(s)}s left';
  }

  Future<void> _submit() async {
    HapticFeedback.lightImpact();
    final repo = context.read<Repo>();
    setState(() => _busy = true);
    try {
      final ok = await attempt(context, () async {
        await repo.submitHomework(widget.hw.id, _url.text.trim());
      }, success: 'Submission recorded.');
      if (ok) await widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markDone() async {
    HapticFeedback.lightImpact();
    final repo = context.read<Repo>();
    final ok = await confirm(context,
        title: 'Mark as done?', message: 'This sets is_evaluated = true for the student.');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final done = await attempt(context, () async {
        await repo.evaluateHomework(widget.hw.id, evaluated: true);
      }, success: 'Marked as done.');
      if (done) await widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hw = widget.hw;
    final urgent = !hw.isEvaluated && _left.inSeconds > 0 && _left.inSeconds <= 7200;
    return AppCard(
      borderColor: urgent ? AppColors.danger.withValues(alpha: 0.6) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (urgent)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: const Row(
                children: [
                  Icon(Icons.alarm, color: AppColors.danger, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Hurry! Homework due in less than 2 hours!',
                        style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ],
              ),
            ),
          Text(hw.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (hw.sourceLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(hw.sourceLabel, style: const TextStyle(fontSize: 12, color: AppColors.primarySoft)),
            ),
          if (hw.description.isNotEmpty) ...[gap8, Text(hw.description, style: const TextStyle(fontSize: 13))],
          gap8,
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 16, color: AppColors.primarySoft),
              const SizedBox(width: 6),
              Text(_countdown,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _left.isNegative || urgent ? AppColors.danger : AppColors.primarySoft)),
            ],
          ),
          gap8,
          Pill(hw.isEvaluated ? 'Marked as Done' : 'Pending Tutor Review',
              color: hw.isEvaluated ? AppColors.success : AppColors.warning, icon: hw.isEvaluated ? Icons.verified : Icons.hourglass_empty),
          if (hw.feedback.isNotEmpty) ...[gap8, Text('Feedback: ${hw.feedback}', style: const TextStyle(fontSize: 13))],
          gap12,
          if (!widget.isTutor) ...[
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Submission link (optional)',
                hintText: 'https://docs.google.com/...',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            gap8,
            SizedBox(
              width: double.infinity,
              child: BusyButton(
                label: _busy ? 'Uploading...' : 'Upload Homework',
                icon: Icons.upload,
                onPressed: _busy
                    ? null
                    : () async {
                        HapticFeedback.lightImpact();
                        await _submit();
                      },
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: BusyButton(
                label: hw.isEvaluated ? 'Evaluated ✓' : 'Mark as Done',
                icon: Icons.verified,
                color: AppColors.success,
                onPressed: (hw.isEvaluated || _busy)
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
