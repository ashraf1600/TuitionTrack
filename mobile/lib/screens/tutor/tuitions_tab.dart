import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/charts.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import 'tuition_screen.dart';

/// The tutor's tuitions: each with its class progress, earnings and weekly days.
class TuitionsTab extends StatelessWidget {
  const TuitionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Loader<List<Json>>(
      load: repo.tuitions,
      builder: (context, tuitions, reload) => PageBody(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (tuitions.isEmpty)
            const EmptyState(
              icon: Icons.class_outlined,
              title: 'No tuitions yet',
              message: 'A tuition is a batch of students who share classes, a fee and a cycle. Tap “New tuition” to create your first one.',
            )
          else
            for (final tuition in tuitions) ...[
              _TuitionCard(
                tuition: tuition,
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TuitionScreen(tuitionId: tuition.str('id'))));
                  await reload();
                },
              ),
              gap12,
            ],
        ],
      ),
    );
  }
}

class _TuitionCard extends StatelessWidget {
  const _TuitionCard({required this.tuition, required this.onTap});
  final Json tuition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cycle = tuition.obj('active_cycle');
    final wallet = tuition.obj('wallet_summary') ?? {};
    final routine = [...tuition.maps('routine')]
      ..sort((a, b) {
        final byDay = weekdays.indexOf(normalizeDay(a.str('day'))).compareTo(weekdays.indexOf(normalizeDay(b.str('day'))));
        return byDay != 0 ? byDay : minutesOf(slotStart(a)).compareTo(minutesOf(slotStart(b)));
      });
    final done = cycle?.integer('completed_classes') ?? 0;
    final total = cycle?.integer('total_classes') ?? tuition.integer('cycle_length');
    final students = tuition.integer('enrolled_count');
    final today = weekdayName(DateTime.now());
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProgressRing(done: done, total: total, size: 64, thickness: 7, caption: 'classes'),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tuition.str('title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(
                      [
                        if (tuition.str('subject').isNotEmpty) tuition.str('subject'),
                        '$students student${students == 1 ? '' : 's'}',
                      ].join(' · '),
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text('$done/$total classes done · cycle #${cycle?.integer('cycle_number') ?? 1}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
          gap12,
          Row(
            children: [
              Text(taka(wallet.number('earned_revenue')), style: TextStyle(fontWeight: FontWeight.w800, color: tone(context, AppColors.success))),
              Expanded(
                child: Text(' earned of ${taka(tuition.number('total_fee'))} this cycle',
                    overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              ),
            ],
          ),
          if (routine.isNotEmpty) ...[
            gap8,
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final slot in routine)
                  Pill(
                    '${normalizeDay(slot.str('day')).isEmpty ? slot.str('day') : normalizeDay(slot.str('day')).substring(0, 3)} ${to12h(slotStart(slot))}',
                    color: normalizeDay(slot.str('day')) == today ? AppColors.success : AppColors.primarySoft,
                    icon: normalizeDay(slot.str('day')) == today ? Icons.today : null,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
