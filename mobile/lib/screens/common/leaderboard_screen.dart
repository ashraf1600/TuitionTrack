import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

/// Ranking of everyone who sat an exam.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key, required this.examId, required this.title});
  final String examId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    final myId = context.read<Session>().user?.str('id');
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: Loader<Json>(
        load: () => repo.leaderboard(examId),
        builder: (context, data, reload) {
          final rows = data.maps('leaderboard');
          return PageBody(
            children: [
              Text(data.str('exam_title', title), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(
                [if (data.str('tuition_title').isNotEmpty) data.str('tuition_title'), 'Out of ${trimNumber(data.number('total_marks'))}'].join(' · '),
                style: const TextStyle(color: AppColors.muted),
              ),
              gap16,
              if (rows.isEmpty)
                const EmptyState(icon: Icons.emoji_events_outlined, title: 'No submissions yet', message: 'The ranking appears once students hand in.')
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) const Divider(),
                        _Row(row: rows[i], mine: rows[i].str('student_id') == myId),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.mine});
  final Json row;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final rank = row.integer('rank');
    final missed = row.str('status') == 'MISSED';
    final medal = switch (rank) { 1 => const Color(0xFFFBBF24), 2 => const Color(0xFFCBD5E1), 3 => const Color(0xFFD97706), _ => null };
    return Container(
      color: mine ? AppColors.primary.withValues(alpha: 0.12) : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (medal ?? AppColors.card).withValues(alpha: medal == null ? 1 : 0.2),
          child: Text('$rank', style: TextStyle(fontWeight: FontWeight.w800, color: medal ?? AppColors.muted)),
        ),
        title: Text(
          '${row.str('student_name')}${mine ? ' (you)' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          missed
              ? 'Did not submit'
              : [
                  '${trimNumber(row.number('percentage'))}%',
                  if (!row.flag('is_graded')) 'not fully marked',
                  if (row.str('status') == 'DELAYED') 'late',
                ].join(' · '),
          style: TextStyle(color: missed ? AppColors.danger : AppColors.muted),
        ),
        trailing: Text(
          trimNumber(row.number('obtained_marks')),
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: missed ? AppColors.faint : AppColors.success),
        ),
      ),
    );
  }
}
