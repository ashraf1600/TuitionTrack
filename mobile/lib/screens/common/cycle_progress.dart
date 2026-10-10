import 'package:flutter/material.dart';

import '../../core/format.dart';
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

/// Read-only class progress for a tuition's current cycle: what a student sees.
/// No money appears here.
class CycleProgress extends StatelessWidget {
  const CycleProgress({super.key, required this.cycle});
  final Json cycle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = cycle.integer('total_classes');
    final completed = cycle.integer('completed_classes');
    final classes = orderedClasses(cycle);
    final log = classes.where((c) => c.flag('completed')).toList()
      ..sort((a, b) => (b.date('date') ?? DateTime(0)).compareTo(a.date('date') ?? DateTime(0)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ProgressRing(done: completed, total: total, size: 60, thickness: 6),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$completed/$total classes done', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('Cycle #${cycle.integer('cycle_number')}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in classes)
              Tooltip(
                message: c.flag('completed') ? 'Class ${classNoOf(c)} · ${fmtShortDate(c.date('date'))}' : 'Class ${classNoOf(c)} · not yet',
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.flag('completed') ? AppColors.chartEarned.withValues(alpha: 0.16) : scheme.surfaceContainerHighest,
                    border: Border.all(color: c.flag('completed') ? AppColors.chartEarned : scheme.outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: c.flag('completed')
                      ? Icon(Icons.check, size: 16, color: tone(context, AppColors.success))
                      : Text('${classNoOf(c)}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ),
              ),
          ],
        ),
        if (log.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Done classes', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
          for (final c in log)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Class ${classNoOf(c)} · ${fmtDate(c.date('date'))}${c.str('topic').isNotEmpty ? ' · ${c.str('topic')}' : ''}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
        if (cycle.flag('is_complete'))
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('This cycle is complete. Your tutor will start the next one.', style: TextStyle(fontSize: 13)),
          ),
      ],
    );
  }
}
