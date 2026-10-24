import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../widgets/charts.dart';
import '../../widgets/theme.dart';

int classNoOf(Json entry) => entry.integer('class_no', entry.integer('classNo'));

/// A cycle's classes in order, one entry per class number (missing ones filled in as not done).
List<Json> orderedClasses(Json cycle) {
  final total = cycle.integer('total_classes');
  final byNumber = {for (final c in cycle.maps('classes_data')) classNoOf(c): c};
  return [
    for (var n = 1; n <= total; n++) byNumber[n] ?? {'class_no': n, 'completed': false, 'date': null, 'topic': ''},
  ];
}

/// Read-only class progress for one subject's current cycle, as a student
/// sees it: a ring, then the classes done (newest first, each with its date and
/// topic). The latest three show; the rest are one tap away. No money here.
class CycleProgress extends StatefulWidget {
  const CycleProgress({super.key, required this.cycle, required this.title, this.paymentDue = false});
  final Json cycle;

  /// The subject ("Physics"). The tuition's own name is never shown to students.
  final String title;

  /// A cycle of this subject waits for payment (a reminder only).
  final bool paymentDue;

  @override
  State<CycleProgress> createState() => _CycleProgressState();
}

class _CycleProgressState extends State<CycleProgress> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final cycle = widget.cycle;
    final total = cycle.integer('total_classes');
    final completed = cycle.integer('completed_classes');
    final log = orderedClasses(cycle).where((c) => c.flag('completed')).toList()
      ..sort((a, b) => classNoOf(b).compareTo(classNoOf(a)));
    final shown = _all ? log : log.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ProgressRing(done: completed, total: total, size: 52, thickness: 5),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tt.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      tr('{p0} of {p1} classes', {'p0': completed, 'p1': total}),
                      tr('Cycle {n}', {'n': cycle.integer('cycle_number', 1)}),
                      if (widget.paymentDue) tr('Payment due'),
                    ].join(' · '),
                    style: TextStyle(fontSize: 13, color: widget.paymentDue ? tone(context, AppColors.warning) : tt.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (log.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(tr('No classes done yet in this cycle.'), style: TextStyle(fontSize: 13, color: tt.textSecondary)),
          )
        else ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: tt.border),
          for (final c in shown) _DoneClass(entry: c),
          if (log.length > 3)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? tr('Show fewer') : tr('Show all {n} classes', {'n': log.length})),
              ),
            ),
        ],
        if (cycle.flag('is_complete'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr('This cycle is complete. Your tutor will start the next one.'), style: TextStyle(fontSize: 13, color: tt.textSecondary)),
          ),
      ],
    );
  }
}

/// "✓ 7  Energy · Thu 22 Oct" — one class done.
class _DoneClass extends StatelessWidget {
  const _DoneClass({required this.entry});
  final Json entry;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final topic = entry.str('topic');
    final date = entry.date('date');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tt.successContainer, shape: BoxShape.circle),
            child: Text(localDigits('${classNoOf(entry)}'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tt.onSuccessContainer, fontFeatures: tabular)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              topic.isNotEmpty ? topic : tr('Class {n}', {'n': classNoOf(entry)}),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: tt.textPrimary),
            ),
          ),
          if (date != null) ...[
            const SizedBox(width: 8),
            Text(fmtShortDate(date), style: TextStyle(fontSize: 12, color: tt.textTertiary, fontFeatures: tabular)),
          ],
        ],
      ),
    );
  }
}
