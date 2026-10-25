import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/reminder_plan.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/charts.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/cycle_progress.dart';
import '../common/notification_actions.dart';
import 'homework_tab.dart';
import 'tuition_screen.dart';

/// Every tuition as a card, two to a row: its colour, name, subject and
/// students, a ring of classes done (or "Due" when a finished cycle waits for
/// payment) and the next class. The last card makes a new tuition. Hold a card
/// for shortcuts.
class TuitionsTab extends StatelessWidget {
  const TuitionsTab({super.key, required this.onCreateTuition});
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

        final students = tuitions.fold<int>(0, (n, t) => n + t.integer('enrolled_count'));
        return PageBody(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (tuitions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  [
                    tuitions.length == 1 ? tr('1 tuition') : tr('{n} tuitions', {'n': tuitions.length}),
                    students == 1 ? tr('1 student') : tr('{n} students', {'n': students}),
                    tr('hold a card for shortcuts'),
                  ].join(' · '),
                  style: TextStyle(fontSize: 14, color: context.tt.textSecondary),
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 12.0;
                final columns = constraints.maxWidth >= 640 ? 3 : 2;
                final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final t in tuitions)
                      SizedBox(
                        width: width,
                        child: TuitionCard(
                          tuition: t,
                          onTap: () => open(t.str('id')),
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            showTuitionShortcuts(context, t, open, reload);
                          },
                        ),
                      ),
                    SizedBox(width: width, child: _NewTuitionCard(onTap: onCreateTuition)),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// One tuition as a square-ish card.
class TuitionCard extends StatelessWidget {
  const TuitionCard({super.key, required this.tuition, required this.onTap, this.onLongPress});
  final Json tuition;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final color = tuitionColorOf(tuition.str('id'));
    final cycle = tuition.obj('active_cycle');
    final done = cycle?.integer('completed_classes') ?? 0;
    final total = cycle?.integer('total_classes') ?? tuition.integer('cycle_length');
    final students = tuition.integer('enrolled_count');
    final subject = tuition.str('subject');
    final due = tuition.maps('pending_payments').isNotEmpty;
    final now = DateTime.now();
    final next = nextClass([tuition], now);
    final soon = next != null && next.at.difference(now) < const Duration(hours: 24);
    return Semantics(
      button: true,
      label: [tuition.str('title'), if (subject.isNotEmpty) subject, tr('{p0} of {p1} classes', {'p0': done, 'p1': total}), if (due) tr('Payment pending')].join(', '),
      child: Material(
        color: tt.card,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 196),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.class_rounded, size: 18, color: color),
                      ),
                      const Spacer(),
                      if (due) DueChip(tt: tt) else ProgressRing(done: done, total: total, size: 46, thickness: 4.5),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(tuition.str('title'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: tt.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    [if (subject.isNotEmpty) subject, tr('{p0} student{p1}', {'p0': students, 'p1': students == 1 ? '' : 's'})].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: tt.textSecondary),
                  ),
                  if (due) ...[
                    const SizedBox(height: 10),
                    Text(tr('{p0}/{p1} classes', {'p0': done, 'p1': total}),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tt.textPrimary, fontFeatures: tabular)),
                    const SizedBox(height: 6),
                    ProgressLine(value: total <= 0 ? 0 : done / total, height: 5),
                  ],
                  const SizedBox(height: 12),
                  if (next != null)
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 14, color: soon ? tt.onPrimaryContainer : tt.textTertiary),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            whenLabel(next.at, now),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: soon ? tt.onPrimaryContainer : tt.textSecondary),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(tr('No class days set'), style: TextStyle(fontSize: 12, color: tt.textTertiary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewTuitionCard extends StatelessWidget {
  const _NewTuitionCard({required this.onTap});
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: tt.border, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: SizedBox(
          height: 196,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(radius: 22, backgroundColor: tt.primaryContainer, child: Icon(Icons.add_rounded, color: tt.onPrimaryContainer)),
              const SizedBox(height: 10),
              Text(tr('New tuition'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tt.onPrimaryContainer)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shortcuts for one tuition (long-press its card): mark the next class,
/// set homework, record a payment, or open it.
Future<void> showTuitionShortcuts(
  BuildContext context,
  Json tuition,
  Future<void> Function(String tuitionId) open,
  Future<void> Function() reload,
) async {
  final session = context.read<Session>();
  final repo = context.read<Repo>();
  final id = tuition.str('id');
  final cycle = tuition.obj('active_cycle');
  final next = cycle == null ? null : orderedClasses(cycle).where((c) => !c.flag('completed')).firstOrNull;
  final pending = tuition.maps('pending_payments');
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(tuition.str('title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          if (next != null)
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(tr('Mark class {n} done', {'n': classNoOf(next)})),
              subtitle: Text(tr('Dated today. You can undo it.')),
              onTap: () => Navigator.pop(sheet, 'mark'),
            ),
          ListTile(
            leading: const Icon(Icons.assignment_outlined),
            title: Text(tr('Assign homework')),
            onTap: () => Navigator.pop(sheet, 'homework'),
          ),
          for (final p in pending)
            ListTile(
              leading: Icon(Icons.payments_outlined, color: tone(sheet, AppColors.warning)),
              title: Text(tr('Mark cycle #{n} paid', {'n': p.integer('cycle_number')})),
              subtitle: p.numberOrNull('amount') == null ? null : Text(taka(p.number('amount'))),
              onTap: () => Navigator.pop(sheet, 'paid:${p.str('cycle_id')}:${p.integer('cycle_number')}'),
            ),
          ListTile(
            leading: const Icon(Icons.open_in_new_rounded),
            title: Text(tr('Open tuition')),
            onTap: () => Navigator.pop(sheet, 'open'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'mark') {
    await markNextClassFromReminder(repo, session, id);
    await reload();
  } else if (choice == 'homework') {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => HomeworkCreateScreen(initialTuitionId: id)),
    );
    if (changed == true) await reload();
  } else if (choice == 'open') {
    await open(id);
  } else if (choice.startsWith('paid:')) {
    final parts = choice.split(':');
    final cycleId = parts[1];
    final n = parts[2];
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await attempt(context, () => repo.setCyclePayment(cycleId, true))) return;
    showToastOn(
      messenger,
      tr('Cycle #{n} marked as paid.', {'n': n}),
      actionLabel: tr('Undo'),
      onAction: () async {
        try {
          await repo.setCyclePayment(cycleId, false);
        } on ApiException catch (error) {
          showToastOn(messenger, error.message, error: true);
        }
        await reload();
      },
    );
    await reload();
  }
}

/// Amber "Due" badge: a cycle of this tuition waits for payment. Word + dot, never colour alone.
class DueChip extends StatelessWidget {
  const DueChip({required this.tt});
  final TtTokens tt;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr('Payment pending'),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: tt.warningContainer, borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: tt.warning, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(tr('@payment_due'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tt.onWarningContainer)),
          ],
        ),
      ),
    );
  }
}

