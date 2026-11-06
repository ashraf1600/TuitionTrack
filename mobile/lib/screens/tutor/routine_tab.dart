import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/week_plan.dart';
import '../../theme/tt_theme.dart';
import '../../widgets/ui.dart';
import 'home_tab.dart' show ClassCard;
import 'tuition_form_screen.dart';
import 'tuition_screen.dart';

/// The whole week across every tuition, Saturday first: each day's classes in
/// time order, today marked, free days shown as free, and a warning wherever
/// two classes overlap. Tap a class to open its tuition.
class RoutineTab extends StatelessWidget {
  const RoutineTab({super.key, required this.onCreateTuition});
  final Future<void> Function() onCreateTuition;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Loader<List<Json>>(
      load: repo.tuitions,
      builder: (context, tuitions, reload) {
        Future<void> open(String id) async {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TuitionScreen(tuitionId: id)));
          await reload();
        }

        final now = DateTime.now();
        final plan = buildWeekPlan(tuitions, now);
        if (plan.isEmpty) {
          final withoutDays = tuitions.where((t) => t.maps('routine').isEmpty).firstOrNull;
          return PageBody(children: [
            EmptyState(
              icon: Icons.calendar_view_week_outlined,
              title: tr('No class days yet'),
              message: tr('Add the days and times of each tuition. Your whole week then shows here, with any time clash marked.'),
              action: FilledButton.icon(
                onPressed: () async {
                  if (withoutDays == null) return onCreateTuition();
                  final changed = await Navigator.push<bool>(
                      context, MaterialPageRoute(builder: (_) => TuitionFormScreen(tuition: withoutDays)));
                  if (changed == true) await reload();
                },
                icon: Icon(withoutDays == null ? Icons.add : Icons.schedule),
                label: Text(withoutDays == null ? tr('New tuition') : tr('Add class days and times')),
              ),
            ),
          ]);
        }

        final clashes = clashingClasses(plan);
        final teachingMinutes = plan.byDay.values
            .expand((list) => list)
            .fold<int>(0, (sum, c) => sum + (classEnd(c) - minutesOf(c.start)).clamp(0, 24 * 60));
        final busyDays = weekOrder.where((d) => plan.byDay[d]!.isNotEmpty).length;
        final tt = context.tt;
        return PageBody(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(
              children: [
                _Stat(value: plan.total, label: plan.total == 1 ? tr('class a week') : tr('classes a week')),
                const SizedBox(width: 10),
                _Stat(value: busyDays, label: tr('days busy'), text: localDigits('$busyDays/7')),
                const SizedBox(width: 10),
                _Stat(value: teachingMinutes, label: tr('teaching'), text: hoursLabel(teachingMinutes)),
              ],
            ),
            if (clashes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: tt.dangerContainer, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: tt.danger, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr('{n} classes overlap. Change a time so you are not in two places at once.', {'n': clashes.length}),
                          style: TextStyle(fontSize: 13, color: tt.textPrimary, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            for (final day in weekOrder) ...[
              _DayHeader(day: day, isToday: day == plan.today, count: plan.byDay[day]!.length, past: plan.isPastDay(day)),
              if (plan.byDay[day]!.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 4),
                  child: Text(tr('Free'), style: TextStyle(fontSize: 13, color: tt.textTertiary)),
                )
              else
                for (final (i, c) in plan.byDay[day]!.indexed) ...[
                  if (i > 0) const SizedBox(height: 8),
                  ClassCard(
                    item: c,
                    clash: clashes.contains(c),
                    live: day == plan.today && !c.past && minutesOf(c.start) <= now.hour * 60 + now.minute,
                    onTap: () => open(c.tuition.str('id')),
                  ),
                ],
            ],
          ],
        );
      },
    );
  }
}

/// 90 -> "1 h 30 m", 120 -> "2 h".
String hoursLabel(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return tr('{m} m', {'m': m});
  if (m == 0) return tr('{h} h', {'h': h});
  return tr('{h} h {m} m', {'h': h, 'm': m});
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.text});
  final int value;
  final String label;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(color: tt.card, borderRadius: BorderRadius.circular(16), boxShadow: tt.cardShadow),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text ?? localDigits('$value'),
                maxLines: 1,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: tt.textPrimary)),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: tt.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.isToday, required this.count, required this.past});
  final String day;
  final bool isToday;
  final int count;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(
        children: [
          Text(
            dayLabel(day, short: false),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: past ? tt.textSecondary : tt.textPrimary,
            ),
          ),
          if (isToday) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: tt.primaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Text(tr('Today'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tt.onPrimaryContainer)),
            ),
          ],
          const Spacer(),
          if (count > 0)
            Text(count == 1 ? tr('1 class') : tr('{n} classes', {'n': count}), style: TextStyle(fontSize: 13, color: tt.textSecondary)),
        ],
      ),
    );
  }
}
