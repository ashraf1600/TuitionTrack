import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

class _PaymentRow {
  _PaymentRow(this.tuition, this.cycles);
  final Json tuition;
  final List<Json> cycles;
}

/// Every cycle of every tuition and whether it was paid.
///
/// Tutors record cash payments here ("Mark paid", or undo it). Students see
/// the same list read-only, without amounts. A pending payment never blocks
/// anything; it is only a reminder on both sides.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, this.tuitionId, this.tutorId});

  /// Show only this tuition (tutor) …
  final String? tuitionId;

  /// … or only this tutor's tuitions (student).
  final String? tutorId;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  Future<List<_PaymentRow>> _load() async {
    final repo = context.read<Repo>();
    final tuitions = (await repo.tuitions()).where((t) {
      if (widget.tuitionId != null) return t.str('id') == widget.tuitionId;
      if (widget.tutorId != null) return t.str('tutor_id') == widget.tutorId;
      return true;
    }).toList();
    final cycles = await Future.wait(tuitions.map((t) => repo.cycles(t.str('id'))));
    return [
      for (var i = 0; i < tuitions.length; i++)
        _PaymentRow(tuitions[i], [...cycles[i]]..sort((a, b) => b.integer('cycle_number').compareTo(a.integer('cycle_number')))),
    ];
  }

  Future<void> _setPaid(Json cycle, bool paid, Future<void> Function() reload) async {
    final repo = context.read<Repo>();
    final n = cycle.integer('cycle_number');
    final amount = cycle.numberOrNull('earned_revenue');
    final ok = await confirm(
      context,
      title: paid ? 'Mark cycle #$n as paid?' : 'Mark cycle #$n as not paid?',
      message: paid
          ? 'Record that ${amount == null ? 'the fee' : taka(amount)} was received. Your students stop seeing "payment pending" for this cycle.'
          : 'Your students will see "payment pending" for this cycle again.',
      confirmLabel: paid ? 'Mark paid' : 'Mark not paid',
      danger: !paid,
    );
    if (!ok || !mounted) return;
    if (await attempt(context, () => repo.setCyclePayment(cycle.str('id'), paid), success: paid ? 'Cycle #$n marked as paid.' : 'Cycle #$n marked as not paid.')) {
      await reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTutor = context.watch<Session>().isTutor;
    return Scaffold(
      appBar: AppBar(title: Text(isTutor ? 'Payments' : 'Payment history')),
      body: Loader<List<_PaymentRow>>(
        load: _load,
        builder: (context, rows, reload) {
          if (rows.isEmpty || rows.every((r) => r.cycles.isEmpty)) {
            return const PageBody(children: [
              EmptyState(icon: Icons.receipt_long_outlined, title: 'No cycles yet', message: 'Cycles and their payments appear here.'),
            ]);
          }
          final unpaid = rows.fold<int>(0, (n, r) => n + r.cycles.where(_isUnpaid).length);
          return PageBody(
            children: [
              if (unpaid > 0) ...[
                Banner2(
                  isTutor
                      ? '$unpaid finished cycle${unpaid == 1 ? ' is' : 's are'} not marked paid. Tap “Mark paid” when you receive the money.'
                      : '$unpaid finished cycle${unpaid == 1 ? ' is' : 's are'} waiting for payment. Classes go on as usual.',
                  color: AppColors.warning,
                  icon: Icons.warning_amber_rounded,
                ),
                gap16,
              ],
              for (final row in rows)
                if (row.cycles.isNotEmpty) ...[
                  FlatGroup(
                    title: row.tuition.str('title'),
                    children: [
                      for (final cycle in row.cycles)
                        _CycleRow(
                          cycle: cycle,
                          isTutor: isTutor,
                          onPaid: (paid) => _setPaid(cycle, paid, reload),
                        ),
                    ],
                  ),
                  gap16,
                ],
            ],
          );
        },
      ),
    );
  }
}

bool _isUnpaid(Json cycle) => cycle.str('status') == 'ARCHIVED' && cycle.str('payment_status') != 'PAID';

class _CycleRow extends StatelessWidget {
  const _CycleRow({required this.cycle, required this.isTutor, required this.onPaid});
  final Json cycle;
  final bool isTutor;
  final ValueChanged<bool> onPaid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = cycle.str('status') == 'ACTIVE';
    final paid = cycle.str('payment_status') == 'PAID';
    final amount = cycle.numberOrNull('earned_revenue');
    final (label, color, icon) = paid
        ? ('Paid${cycle.date('paid_at') == null ? '' : ' · ${fmtShortDate(cycle.date('paid_at'))}'}', AppColors.success, Icons.check_circle_rounded)
        : current
            ? ('In progress', AppColors.primarySoft, Icons.timelapse_rounded)
            : ('Payment pending', AppColors.warning, Icons.warning_amber_rounded);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cycle #${cycle.integer('cycle_number')}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text(
                  [
                    '${cycle.integer('completed_classes')}/${cycle.integer('total_classes')} classes',
                    if (isTutor && amount != null) taka(amount),
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Pill(label, color: color, icon: icon),
          if (isTutor)
            paid
                ? IconButton(
                    tooltip: 'Mark as not paid',
                    icon: Icon(Icons.undo_rounded, size: 20, color: scheme.onSurfaceVariant),
                    onPressed: () => onPaid(false),
                  )
                : TextButton(onPressed: () => onPaid(true), child: const Text('Mark paid'))
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}
