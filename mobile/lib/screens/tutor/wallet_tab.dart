import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/charts.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/broadcast_screen.dart';
import '../common/payments_screen.dart';
import 'tuition_screen.dart';

/// The tutor's money in one place: earned so far and still to earn, finished
/// cycles waiting for payment (mark paid, or remind the tuition's students),
/// each tuition's classes and taka as pies, and the latest payments.
class WalletTab extends StatelessWidget {
  const WalletTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Loader<Json>(
      load: repo.wallet,
      builder: (context, wallet, reload) {
        final unpaid = wallet.maps('unpaid_list');
        final tuitions = wallet.maps('tuition_breakdowns');
        final paid = wallet.maps('recent_paid');
        return PageBody(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _Totals(wallet: wallet),
            if (unpaid.isNotEmpty) ...[
              _Header(tr('Cycle finished · get paid'), trailing: taka(wallet.number('unpaid_total')), trailingColor: AppColors.warning),
              for (final (i, row) in unpaid.indexed) ...[
                if (i > 0) gap12,
                _UnpaidCard(row: row, reload: reload),
              ],
            ],
            if (tuitions.isNotEmpty) ...[
              _Header(tr('By tuition'), trailing: tr('this cycle')),
              for (final (i, t) in tuitions.indexed) ...[
                if (i > 0) gap12,
                _TuitionPies(row: t, reload: reload),
              ],
            ],
            _Header(
              tr('Recently paid'),
              action: TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const PaymentsScreen())),
                child: Text(tr('All payments')),
              ),
            ),
            if (paid.isEmpty)
              AppCard(
                child: Text(tr('Payments you mark as received appear here.'), style: TextStyle(fontSize: 14, color: context.tt.textSecondary)),
              )
            else
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final (i, p) in paid.indexed) ...[
                      if (i > 0) Divider(height: 1, indent: 60, color: context.tt.border),
                      _PaidRow(row: p),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, {this.trailing, this.trailingColor, this.action});
  final String title;
  final String? trailing;
  final Color? trailingColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 24, 2, 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: tt.textPrimary))),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                fontSize: trailingColor == null ? 13 : 15,
                fontWeight: trailingColor == null ? FontWeight.w400 : FontWeight.w700,
                color: trailingColor == null ? tt.textSecondary : tone(context, trailingColor!),
                fontFeatures: tabular,
              ),
            ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Earned (all time, all tuitions) and still to be earned in the current cycles.
class _Totals extends StatelessWidget {
  const _Totals({required this.wallet});
  final Json wallet;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final current = wallet.number('total_earned');
    final left = wallet.number('total_pending');
    final allTime = wallet.number('lifetime_archived_earnings') + current;
    Widget figure(String label, Color dot, String value, String note, {Color? color}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tt.textSecondary)),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8, fontFeatures: tabular, color: color ?? tt.textPrimary)),
            ),
            Text(note, style: TextStyle(fontSize: 12, color: tt.textTertiary)),
          ],
        );
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: figure(tr('Earned'), tt.chartEarned, taka(allTime), tr('all time, all tuitions'), color: tt.success)),
              const SizedBox(width: 12),
              Expanded(child: figure(tr('To be earned'), tt.chartTrack, taka(left), tr('left in current cycles'))),
            ],
          ),
          const SizedBox(height: 14),
          ProgressLine(value: current + left <= 0 ? 0 : current / (current + left), height: 8),
          const SizedBox(height: 6),
          Text(
            tr('Current cycles: {a} of {b} earned', {'a': Raw(taka(current)), 'b': Raw(taka(current + left))}),
            style: TextStyle(fontSize: 12, color: tt.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A finished cycle waiting for payment: mark it paid, or remind the students.
class _UnpaidCard extends StatelessWidget {
  const _UnpaidCard({required this.row, required this.reload});
  final Json row;
  final Future<void> Function() reload;

  Future<void> _markPaid(BuildContext context) async {
    HapticFeedback.lightImpact();
    final repo = context.read<Repo>();
    final id = row.str('cycle_id');
    final n = row.integer('cycle_number');
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await attempt(context, () => repo.setCyclePayment(id, true))) return;
    showToastOn(
      messenger,
      tr('Cycle #{n} marked as paid.', {'n': n}),
      actionLabel: tr('Undo'),
      onAction: () async {
        try {
          await repo.setCyclePayment(id, false);
        } on ApiException catch (error) {
          showToastOn(messenger, error.message, error: true);
        }
        await reload();
      },
    );
    await reload();
  }

  Future<void> _remind(BuildContext context) async {
    final amount = taka(row.number('amount'));
    final n = row.integer('cycle_number');
    // Students never see the tuition's own name, so the message does not use it.
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BroadcastScreen(
          initialTuitionId: row.str('tuition_id'),
          initialText: tr('Assalamu alaikum. The tuition fee of {amount} for cycle #{n} is due. Thank you.', {'amount': Raw(amount), 'n': n}),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final finished = row.date('finished_at')?.toLocal();
    final days = finished == null ? 0 : DateTime.now().difference(finished).inDays;
    final hasTuition = row.str('tuition_id').isNotEmpty;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: hasTuition ? tuitionColorOf(row.str('tuition_id')) : tt.textTertiary, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.str('tuition_title'), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tt.textPrimary)),
                    Text(
                      tr('Cycle #{n} · {done}/{total} classes', {'n': row.integer('cycle_number'), 'done': row.integer('completed_classes'), 'total': row.integer('total_classes')}),
                      style: TextStyle(fontSize: 12, color: tt.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(taka(row.number('amount')), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tt.textPrimary, fontFeatures: tabular)),
                  Text(
                    days <= 0 ? tr('since today') : (days == 1 ? tr('1 day') : tr('{n} days', {'n': days})),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: days > 7 ? tt.danger : tt.textSecondary),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: () => _markPaid(context),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(tr('Mark paid')),
                ),
              ),
              if (hasTuition) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => _remind(context),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: Text(tr('Remind')),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One tuition this cycle: classes done and taka earned, as two pies.
class _TuitionPies extends StatelessWidget {
  const _TuitionPies({required this.row, required this.reload});
  final Json row;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final color = tuitionColorOf(row.str('tuition_id'));
    final done = row.integer('completed_classes');
    final total = row.integer('total_classes');
    final earned = row.number('earned');
    final fee = row.number('total_fee');
    final share = fee <= 0 ? 0.0 : earned / fee;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TuitionScreen(tuitionId: row.str('tuition_id'))));
        await reload();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(row.str('tuition_title'), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tt.textPrimary)),
              ),
              Text(tr('Cycle {n}', {'n': row.integer('cycle_number')}), style: TextStyle(fontSize: 12, color: tt.textTertiary)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    ProgressRing(done: done, total: total, size: 84, thickness: 10),
                    const SizedBox(height: 8),
                    Text(tr('Classes done'), style: TextStyle(fontSize: 12, color: tt.textSecondary)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    RingChart(
                      value: share,
                      color: color,
                      size: 84,
                      thickness: 10,
                      label: tr('Taka earned: {a} of {b}', {'a': Raw(taka(earned)), 'b': Raw(taka(fee))}),
                      center: Text('${localDigits('${(share * 100).round()}')}%',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tt.textPrimary)),
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: taka(earned), style: TextStyle(fontWeight: FontWeight.w700, color: tt.success)),
                        TextSpan(text: ' ${tr('of {p0}', {'p0': taka(fee)})}'),
                      ]),
                      style: TextStyle(fontSize: 12, color: tt.textSecondary, fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaidRow extends StatelessWidget {
  const _PaidRow({required this.row});
  final Json row;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final at = row.date('paid_at')?.toLocal();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: tt.successContainer, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: 18, color: tt.onSuccessContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.str('tuition_title'), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tt.textPrimary)),
                Text(
                  [tr('Cycle #{n}', {'n': row.integer('cycle_number')}), if (at != null) fmtShortDate(at)].join(' · '),
                  style: TextStyle(fontSize: 12, color: tt.textTertiary),
                ),
              ],
            ),
          ),
          Text(taka(row.number('amount')), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tt.textPrimary, fontFeatures: tabular)),
        ],
      ),
    );
  }
}
