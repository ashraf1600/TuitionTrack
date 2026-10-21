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
                  Text(tr('{p0}/{p1} classes done', {'p0': completed, 'p1': total}), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(tr('Cycle #{p0}', {'p0': cycle.integer('cycle_number')}), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
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
                message: c.flag('completed') ? tr('Class {p0} · {p1}', {'p0': classNoOf(c), 'p1': fmtShortDate(c.date('date'))}) : tr('Class {p0} · not yet', {'p0': classNoOf(c)}),
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.flag('completed') ? context.tt.successContainer : scheme.surfaceContainerHighest,
                    border: Border.all(color: c.flag('completed') ? tone(context, AppColors.chartEarned) : scheme.outline),
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
          Text(tr('Done classes'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
          for (final c in log)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr('Class {p0} · {p1}{p2}', {'p0': classNoOf(c), 'p1': fmtDate(c.date('date')), 'p2': c.str('topic').isNotEmpty ? ' · ${c.str('topic')}' : ''}),
                style: const TextStyle(fontSize: 13),
              ),
            ),
        ],
        if (cycle.flag('is_complete'))
          Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(tr('This cycle is complete. Your tutor will start the next one.'), style: TextStyle(fontSize: 13)),
          ),
      ],
    );
  }
}
