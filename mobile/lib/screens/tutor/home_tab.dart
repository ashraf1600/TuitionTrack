import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/reminder_plan.dart';
import '../../core/reminders.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/charts.dart';
import '../../widgets/share.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/cycle_progress.dart';
import '../common/notification_actions.dart';
import '../common/payments_screen.dart';
import 'homework_tab.dart';
import 'tuition_form_screen.dart';
import 'tuition_screen.dart';

class _HomeData {
  _HomeData(this.wallet, this.tuitions, this.requests);
  final Json wallet;
  final List<Json> tuitions;
  final List<Json> requests;
}

/// Overview on one screen: the wallet, the week at a glance, and every tuition
/// as a card. Tap a tuition to mark classes, see its students and exams.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.onCreateTuition});

  /// Opens the "New tuition" form (the same as the + button).
  final Future<void> Function() onCreateTuition;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Loader<_HomeData>(
      load: () async {
        final settings = context.read<Session>().settings;
        final results = await Future.wait<dynamic>([repo.wallet(), repo.tuitions(), repo.connections('PENDING')]);
        final tuitions = results[1] as List<Json>;
        // Class reminders for the coming week, set again on every load (they work offline).
        unawaited(Reminders.instance.schedule(settings, tutorReminders(tuitions, DateTime.now())));
        return _HomeData(results[0] as Json, tuitions, results[2] as List<Json>);
      },
      builder: (context, data, reload) {
        Future<void> open(String tuitionId) async {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TuitionScreen(tuitionId: tuitionId)));
          await reload();
        }

        return PageBody(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _GetStarted(tuitions: data.tuitions, onCreateTuition: onCreateTuition, onOpen: open, reload: reload),
            _WalletStrip(wallet: data.wallet),
            if (data.requests.isNotEmpty) ...[
              gap8,
              _RequestsBanner(requests: data.requests, tuitions: data.tuitions, reload: reload),
            ],
            _Heading(tr('This week')),
            _WeekAtAGlance(tuitions: data.tuitions, onOpen: open),
            _Heading(tr('Tuitions'), trailing: data.tuitions.isEmpty ? null : tr('Hold a card for shortcuts')),
            if (data.tuitions.isEmpty)
              EmptyState(
                icon: Icons.class_outlined,
                title: tr('No tuitions yet'),
                message: tr('Create a tuition, add its students and class days, then mark classes as you teach.'),
                action: FilledButton.icon(onPressed: onCreateTuition, icon: const Icon(Icons.add), label: Text(tr('New tuition'))),
              )
            else
              _TuitionGrid(tuitions: data.tuitions, onOpen: open, onActions: (t) => _quickActions(context, t, open, reload)),
          ],
        );
      },
    );
  }
}

/// First steps for a new tutor, ticked off as they happen; gone once all are
/// done or the tutor hides it.
class _GetStarted extends StatefulWidget {
  const _GetStarted({required this.tuitions, required this.onCreateTuition, required this.onOpen, required this.reload});
  final List<Json> tuitions;
  final Future<void> Function() onCreateTuition;
  final Future<void> Function(String tuitionId) onOpen;
  final Future<void> Function() reload;

  @override
  State<_GetStarted> createState() => _GetStartedState();
}

class _GetStartedState extends State<_GetStarted> {
  static const _hiddenKey = 'get_started_hidden';

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final settings = session.settings;
    if (settings.getString(_hiddenKey) == 'yes') return const SizedBox.shrink();
    final tuitions = widget.tuitions;
    final withoutDays = tuitions.where((t) => t.maps('routine').isEmpty).firstOrNull;
    final code = (session.user ?? {}).str('tutor_code');
    final steps = <(String, bool, Future<void> Function())>[
      (tr('Create a tuition'), tuitions.isNotEmpty, widget.onCreateTuition),
      (
        tr('Add class days and times'),
        tuitions.isNotEmpty && withoutDays == null,
        () async {
          final target = withoutDays ?? tuitions.firstOrNull;
          if (target == null) return widget.onCreateTuition();
          final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => TuitionFormScreen(tuition: target)));
          if (changed == true) await widget.reload();
        },
      ),
      (
        tr('Add students'),
        tuitions.any((t) => t.integer('enrolled_count') > 0),
        () async {
          final target = tuitions.firstOrNull;
          if (target == null) return widget.onCreateTuition();
          await widget.onOpen(target.str('id'));
        },
      ),
      (
        tr('Share your invite code'),
        settings.getString(inviteSharedKey) == 'yes',
        () async {
          if (code.isEmpty) {
            showToast(context, tr('Connect to the internet to see your invite code.'), error: true);
            return;
          }
          await shareInviteCode(context, code);
          if (mounted) setState(() {});
        },
      ),
    ];
    final done = steps.where((s) => s.$2).length;
    if (done == steps.length) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tr('Get started · {done} of {total} done', {'done': done, 'total': steps.length}),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: () async {
                    await settings.setString(_hiddenKey, 'yes');
                    if (mounted) setState(() {});
                  },
                  child: Text(tr('Hide')),
                ),
              ],
            ),
            ProgressLine(value: done / steps.length, height: 4),
            const SizedBox(height: 4),
            for (final (label, isDone, action) in steps)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    color: isDone ? tone(context, AppColors.success) : scheme.onSurfaceVariant),
                title: Text(
                  label,
                  style: TextStyle(
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    color: isDone ? scheme.onSurfaceVariant : scheme.onSurface,
                  ),
                ),
                trailing: isDone ? null : Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                onTap: isDone ? null : action,
              ),
          ],
        ),
      ),
    );
  }
}

/// Shortcuts for one tuition (long-press its card): mark the next class,
/// set homework, record a payment, or open it.
Future<void> _quickActions(
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

/// A quiet section label: small caps, no icon, optional count on the right.
class _Heading extends StatelessWidget {
  const _Heading(this.title, {this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title.toUpperCase(),
                style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
          ),
          if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// The wallet in one line: earned in the current cycles and how far along they are.
class _WalletStrip extends StatelessWidget {
  const _WalletStrip({required this.wallet});
  final Json wallet;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final earned = wallet.number('total_earned');
    final pending = wallet.number('total_pending');
    final total = earned + pending;
    final share = total <= 0 ? 0.0 : earned / total;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Earned in current cycles'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(taka(earned), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: tone(context, AppColors.success))),
                  ],
                ),
              ),
              Text(tr('of {p0}', {'p0': taka(total)}), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          ProgressLine(value: share, height: 5, label: tr('Share of the current cycles already earned')),
          if (wallet.integer('unpaid_cycles') > 0) ...[
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const PaymentsScreen())),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: tone(context, AppColors.warning)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr('{p0} to collect · {p1} unpaid cycle{p2}', {'p0': taka(wallet.number('unpaid_total')), 'p1': wallet.integer('unpaid_cycles'), 'p2': wallet.integer('unpaid_cycles') == 1 ? '' : 's'}),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tone(context, AppColors.warning)),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: tone(context, AppColors.warning)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Students asking to join, folded into one line that opens the list.
class _RequestsBanner extends StatelessWidget {
  const _RequestsBanner({required this.requests, required this.tuitions, required this.reload});
  final List<Json> requests;
  final List<Json> tuitions;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final n = requests.length;
    return Banner2(
      tr('{p0} student{p1} asked to join you.', {'p0': n, 'p1': n == 1 ? '' : 's'}),
      icon: Icons.person_add_alt_1_outlined,
      action: TextButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (sheetContext) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.8),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _Requests(
                  requests: requests,
                  tuitions: tuitions,
                  reload: () async {
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    await reload();
                  },
                ),
              ),
            ),
          ),
        ),
        child: Text(tr('Review')),
      ),
    );
  }
}

class _Slot {
  _Slot(this.tuition, this.slot);
  final Json tuition;
  final Json slot;
  String get start => slotStart(slot);
  String get end => '${slot['end_time'] ?? ''}';
}

/// The whole week without scrolling: a strip of seven days (a dot for a free
/// day, the number of classes for a busy one), then one slim line per class,
/// grouped by day, Saturday first. Today stands out.
class _WeekAtAGlance extends StatelessWidget {
  const _WeekAtAGlance({required this.tuitions, required this.onOpen});
  final List<Json> tuitions;
  final Future<void> Function(String tuitionId) onOpen;

  static const _order = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = weekdayName(DateTime.now());
    final byDay = {for (final d in _order) d: <_Slot>[]};
    for (final tuition in tuitions) {
      for (final slot in tuition.maps('routine')) {
        final day = normalizeDay('${slot['day'] ?? slot['day_of_week'] ?? ''}');
        if (day.isNotEmpty) byDay[day]!.add(_Slot(tuition, slot));
      }
    }
    for (final slots in byDay.values) {
      slots.sort((a, b) => minutesOf(a.start).compareTo(minutesOf(b.start)));
    }
    final busyDays = _order.where((d) => byDay[d]!.isNotEmpty).toList();
    final accent = tone(context, AppColors.primarySoft);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Seven days in a row.
          Row(
            children: [
              for (final day in _order)
                Expanded(
                  child: Semantics(
                    label: '${dayLabel(day, short: false)}: ${byDay[day]!.isEmpty ? tr('no classes') : tr('{n} classes', {'n': byDay[day]!.length})}${day == today ? tr(', today') : ''}',
                    excludeSemantics: true,
                    child: Column(
                      children: [
                        Text(isBangla ? dayLabel(day) : day.substring(0, 2),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: day == today ? FontWeight.w800 : FontWeight.w500,
                                color: day == today ? accent : scheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 22,
                          child: Center(
                            child: byDay[day]!.isEmpty
                                ? Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(color: scheme.outlineVariant.withValues(alpha: 0.5), shape: BoxShape.circle),
                                  )
                                : Container(
                                    width: 22,
                                    height: 22,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: day == today ? AppColors.chartPending : AppColors.chartPending.withValues(alpha: 0.18),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text('${byDay[day]!.length}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: day == today ? Colors.white : accent)),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (busyDays.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text(
                tuitions.isEmpty ? tr('Your class days appear here.') : tr('No class days set yet. Add them when you edit a tuition.'),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: scheme.outline.withValues(alpha: 0.6)),
            const SizedBox(height: 4),
            for (final day in busyDays)
              for (var i = 0; i < byDay[day]!.length; i++)
                _SlotLine(
                  day: i == 0 ? dayLabel(day) : '',
                  isToday: day == today,
                  slot: byDay[day]![i],
                  onTap: () => onOpen(byDay[day]![i].tuition.str('id')),
                ),
          ],
        ],
      ),
    );
  }
}

class _SlotLine extends StatelessWidget {
  const _SlotLine({required this.day, required this.isToday, required this.slot, required this.onTap});
  final String day;
  final bool isToday;
  final _Slot slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = tone(context, AppColors.primarySoft);
    final time = slot.end.isEmpty ? to12h(slot.start) : '${to12h(slot.start)} – ${to12h(slot.end)}';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: isToday
            ? BoxDecoration(color: AppColors.chartPending.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10))
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(day,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isToday ? accent : scheme.onSurfaceVariant)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
              child: Text(time, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(slot.tuition.str('title'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Every tuition as a small card, two per row: name, cycle, classes done.
class _TuitionGrid extends StatelessWidget {
  const _TuitionGrid({required this.tuitions, required this.onOpen, required this.onActions});
  final List<Json> tuitions;
  final Future<void> Function(String tuitionId) onOpen;
  final void Function(Json tuition) onActions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tuition in tuitions)
              SizedBox(
                width: width,
                child: _TuitionCard(tuition: tuition, onTap: () => onOpen(tuition.str('id')), onLongPress: () => onActions(tuition)),
              ),
          ],
        );
      },
    );
  }
}

class _TuitionCard extends StatelessWidget {
  const _TuitionCard({required this.tuition, required this.onTap, required this.onLongPress});
  final Json tuition;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cycle = tuition.obj('active_cycle');
    final done = cycle?.integer('completed_classes') ?? 0;
    final total = cycle?.integer('total_classes') ?? tuition.integer('cycle_length');
    final cycleNo = cycle?.integer('cycle_number') ?? 1;
    final complete = total > 0 && done >= total;
    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 38,
            child: Text(tuition.str('title'),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.3)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(tr('Cycle {p0}', {'p0': cycleNo}), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              if (tuition.maps('pending_payments').isNotEmpty) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: tr('Payment pending'),
                  child: Icon(Icons.warning_amber_rounded, size: 14, color: tone(context, AppColors.warning)),
                ),
              ],
              const Spacer(),
              Text('$done/$total',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: complete ? tone(context, AppColors.success) : scheme.onSurface)),
            ],
          ),
          const SizedBox(height: 6),
          ProgressLine(value: total == 0 ? 0.0 : done / total, height: 4, label: tr('{p0} of {p1} classes done', {'p0': done, 'p1': total})),
        ],
      ),
    );
  }
}

/// Students who asked to join this tutor.
class _Requests extends StatelessWidget {
  const _Requests({required this.requests, required this.tuitions, required this.reload});
  final List<Json> requests;
  final List<Json> tuitions;
  final Future<void> Function() reload;

  Future<void> _accept(BuildContext context, Json request, {required bool pickTuition}) async {
    final repo = context.read<Repo>();
    String? tuitionId;
    if (pickTuition) {
      tuitionId = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text(tr('Add {p0} to which tuition?', {'p0': request.str('student_name')}), style: const TextStyle(fontWeight: FontWeight.w700))),
              for (final t in tuitions)
                ListTile(
                  leading: const Icon(Icons.class_outlined),
                  title: Text(t.str('title')),
                  subtitle: Text(tr('{p0} student{p1}', {'p0': t.integer('enrolled_count'), 'p1': t.integer('enrolled_count') == 1 ? '' : 's'})),
                  onTap: () => Navigator.pop(context, t.str('id')),
                ),
            ],
          ),
        ),
      );
      if (tuitionId == null || !context.mounted) return;
    }
    String message = tr('Accepted.');
    final ok = await attempt(context, () async {
      message = (await repo.acceptConnection(request.str('id'), tuitionId: tuitionId)).str('message', 'Accepted.');
    });
    if (ok && context.mounted) showToast(context, message);
    if (ok) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(tr('Requests to join ({p0})', {'p0': requests.length}), icon: Icons.person_add_alt_1_outlined),
        for (final request in requests) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.str('student_name'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Builder(builder: (context) {
                  final s = request.obj('student') ?? {};
                  final details = [
                    '@${request.str('student_username')}',
                    if (s.str('grade_level').isNotEmpty) s.str('grade_level'),
                    if (s.str('institution').isNotEmpty) s.str('institution'),
                    if (s.str('phone').isNotEmpty) s.str('phone'),
                  ].join(' · ');
                  return Text(details, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13));
                }),
                if (request.str('message').isNotEmpty) ...[
                  gap8,
                  Text('“${request.str('message')}”', style: const TextStyle(fontStyle: FontStyle.italic)),
                ],
                gap12,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (tuitions.isNotEmpty)
                      FilledButton(onPressed: () => _accept(context, request, pickTuition: true), child: Text(tr('Accept & add to tuition'))),
                    OutlinedButton(onPressed: () => _accept(context, request, pickTuition: false), child: Text(tr('Accept only'))),
                    TextButton(
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          title: tr('Decline this request?'),
                          message: tr('{p0} will see that the request was declined and can ask again.', {'p0': request.str('student_name')}),
                          confirmLabel: tr('Decline'),
                          danger: true,
                        );
                        if (!ok || !context.mounted) return;
                        if (await attempt(context, () => repo.rejectConnection(request.str('id')), success: tr('Request declined.'))) await reload();
                      },
                      child: Text(tr('Decline')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          gap8,
        ],
      ],
    );
  }
}
