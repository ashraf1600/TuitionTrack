import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import 'group_screen.dart';

/// The tutor's tuition groups.
class GroupsTab extends StatelessWidget {
  const GroupsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Loader<List<Json>>(
      load: repo.tuitions,
      builder: (context, tuitions, reload) => PageBody(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (tuitions.isEmpty)
            EmptyState(
              icon: Icons.groups_outlined,
              title: 'No tuition groups yet',
              message: 'A group is a batch of students who share classes, a fee and a cycle. Tap “New group” to create your first one.',
            )
          else
            for (final tuition in tuitions) ...[
              Builder(builder: (context) {
                final cycle = tuition.obj('active_cycle');
                final wallet = tuition.obj('wallet_summary') ?? {};
                final routine = tuition.maps('routine');
                final completed = cycle?.integer('completed_classes') ?? 0;
                final total = cycle?.integer('total_classes') ?? tuition.integer('cycle_length');
                return AppCard(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => GroupScreen(tuitionId: tuition.str('id'))));
                    await reload();
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(tuition.str('title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                          Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ],
                      ),
                      Text(
                        [
                          if (tuition.str('subject').isNotEmpty) tuition.str('subject'),
                          '${tuition.integer('enrolled_count')} student${tuition.integer('enrolled_count') == 1 ? '' : 's'}',
                          'Cycle #${cycle?.integer('cycle_number') ?? 1} · $completed/$total classes',
                        ].join(' · '),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                      gap8,
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(value: total == 0 ? 0 : completed / total, minHeight: 6, color: AppColors.success),
                      ),
                      gap8,
                      Row(
                        children: [
                          Text(taka(wallet.number('earned_revenue')), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.success)),
                          Text(' earned of ${taka(tuition.number('total_fee'))}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
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
                                '${slot.str('day').length > 3 ? slot.str('day').substring(0, 3) : slot.str('day')} ${to12h(slot.str('start_time', slot.str('time')))}',
                                color: AppColors.primarySoft,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),
              gap12,
            ],
        ],
      ),
    );
  }
}
