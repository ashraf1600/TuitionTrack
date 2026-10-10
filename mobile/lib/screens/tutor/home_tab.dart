import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/charts.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/cycle_progress.dart';
import 'tuition_screen.dart';

class _HomeData {
  _HomeData(this.wallet, this.tuitions, this.requests);
  final Json wallet;
  final List<Json> tuitions;
  final List<Json> requests;
}

/// Overview, kept short on purpose: the wallet, today's classes, students
/// asking to join, and each tuition's progress. Everything else is one tap away.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.onOpenTab});
  final void Function(int index) onOpenTab;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Loader<_HomeData>(
      load: () async {
        final results = await Future.wait<dynamic>([repo.wallet(), repo.tuitions(), repo.connections('PENDING')]);
        return _HomeData(results[0] as Json, results[1] as List<Json>, results[2] as List<Json>);
      },
      builder: (context, data, reload) => PageBody(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _WalletCard(wallet: data.wallet),
          gap8,
          _TodayRoutine(tuitions: data.tuitions, reload: reload),
          if (data.requests.isNotEmpty) _Requests(requests: data.requests, tuitions: data.tuitions, reload: reload),
          SectionTitle(
            'Your tuitions',
            icon: Icons.class_outlined,
            trailing: data.tuitions.isEmpty ? null : TextButton(onPressed: () => onOpenTab(1), child: const Text('See all')),
          ),
          if (data.tuitions.isEmpty)
            EmptyState(
              icon: Icons.class_outlined,
              title: 'No tuitions yet',
              message: 'Create a tuition, add its students and weekly routine, and mark classes as you teach. Your earnings build up here.',
              action: FilledButton(onPressed: () => onOpenTab(1), child: const Text('Go to tuitions')),
            )
          else
            for (final tuition in data.tuitions) ...[
              TuitionProgressTile(
                tuition: tuition,
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TuitionScreen(tuitionId: tuition.str('id'))));
                  await reload();
                },
              ),
              gap8,
            ],
          if (data.wallet.maps('student_breakdowns').isNotEmpty) ...[
            const SectionTitle('One-to-one students', subtitle: 'Older individual cycles, not part of a tuition.'),
            for (final row in data.wallet.maps('student_breakdowns')) ...[
              AppCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ProgressRing(done: row.integer('completed_classes'), total: row.integer('total_classes'), size: 44, thickness: 5),
                    const SizedBox(width: 12),
                    Expanded(child: Text(row.str('student_name'), style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text(taka(row.number('earned')), style: TextStyle(fontWeight: FontWeight.w800, color: tone(context, AppColors.success))),
                  ],
                ),
              ),
              gap8,
            ],
          ],
        ],
      ),
    );
  }
}

/// The wallet as a ring: earned so far against what the current cycles will
/// still bring in, with past cycles, tuitions and students underneath.
class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet});
  final Json wallet;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final earned = wallet.number('total_earned').toDouble();
    final pending = wallet.number('total_pending').toDouble();
    final pastCycles = wallet.number('lifetime_archived_earnings');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 20, color: tone(context, AppColors.primarySoft)),
              const SizedBox(width: 8),
              const Expanded(child: Text('Tuition Wallet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              Text('Current cycles', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
          gap16,
          DonutChart(
            slices: [
              DonutSlice(label: 'Earned', value: earned, color: AppColors.chartEarned, display: taka(earned)),
              DonutSlice(label: 'Still to earn', value: pending, color: AppColors.chartPending, display: taka(pending)),
            ],
            centerValue: taka(earned + pending),
            centerLabel: 'this cycle',
            semanticsLabel: 'Tuition wallet: ${taka(earned)} earned, ${taka(pending)} still to earn in the current cycles.',
          ),
          gap16,
          Divider(color: scheme.outline),
          gap12,
          Row(
            children: [
              Expanded(child: Stat(label: 'Past cycles', value: taka(pastCycles))),
              Expanded(child: Stat(label: 'Tuitions', value: '${wallet.integer('total_tuitions')}')),
              Expanded(child: Stat(label: 'Students', value: '${wallet.integer('total_students')}')),
            ],
          ),
        ],
      ),
    );
  }
}

/// A tuition with its current cycle at a glance: "7/12 classes done" and what it earned.
class TuitionProgressTile extends StatelessWidget {
  const TuitionProgressTile({super.key, required this.tuition, required this.onTap});
  final Json tuition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cycle = tuition.obj('active_cycle');
    final wallet = tuition.obj('wallet_summary') ?? {};
    final done = cycle?.integer('completed_classes') ?? 0;
    final total = cycle?.integer('total_classes') ?? tuition.integer('cycle_length');
    final students = tuition.integer('enrolled_count');
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: Row(
        children: [
          ProgressRing(done: done, total: total, size: 56, thickness: 6),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tuition.str('title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (tuition.str('subject').isNotEmpty) tuition.str('subject'),
                    '$students student${students == 1 ? '' : 's'}',
                    'Cycle #${cycle?.integer('cycle_number') ?? 1}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$done/$total classes done', style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: '  ·  ${taka(wallet.number('earned_revenue'))} earned', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ]),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _ClassRow {
  _ClassRow(this.tuition, this.day, this.slot, this.recorded, this.nextClassNo, this.total);
  final Json tuition;
  final DateTime day;
  final Json slot;
  final bool recorded;
  final int? nextClassNo;
  final int total;
  String get key => '${tuition.str('id')}:${dayKey(day)}';
  String get time => slotStart(slot);
}

/// Today's classes from the weekly routine — only today, in time order, each
/// with one tap to mark it done. Routine days of the last week that were never
/// recorded collapse into a single reminder, so a class that was held but not
/// ticked does not silently go unpaid.
class _TodayRoutine extends StatefulWidget {
  const _TodayRoutine({required this.tuitions, required this.reload});
  final List<Json> tuitions;
  final Future<void> Function() reload;

  @override
  State<_TodayRoutine> createState() => _TodayRoutineState();
}

class _TodayRoutineState extends State<_TodayRoutine> {
  static const _lookbackDays = 7;
  static const _dismissKey = 'routine_dismissed_classes';

  ({List<_ClassRow> today, List<_ClassRow> missed, (DateTime, Json, Json)? next}) _plan(Set<String> dismissed) {
    final now = DateTime.now();
    final today = <_ClassRow>[];
    final missed = <_ClassRow>[];
    for (final tuition in widget.tuitions) {
      final cycle = tuition.obj('active_cycle');
      final routine = tuition.maps('routine');
      if (cycle == null || routine.isEmpty) continue;
      final classes = orderedClasses(cycle);
      final recordedDays = {
        for (final c in classes)
          if (c.flag('completed') && c.date('date') != null) dayKey(c.date('date')!),
      };
      int? next;
      for (final c in classes) {
        if (!c.flag('completed')) {
          next = classNoOf(c);
          break;
        }
      }
      final total = cycle.integer('total_classes');
      // Never look back past the start of the current cycle or the tuition itself.
      final cycleStart = cycle.date('created_at') ?? now;
      final tuitionStart = tuition.date('created_at') ?? now;
      final earliest = dayKey(cycleStart.isAfter(tuitionStart) ? cycleStart : tuitionStart);

      for (var back = 0; back <= _lookbackDays; back++) {
        final day = DateTime(now.year, now.month, now.day - back);
        if (back > 0 && dayKey(day).compareTo(earliest) < 0) break;
        final slots = slotsOn(routine, day);
        if (slots.isEmpty) continue;
        final row = _ClassRow(tuition, day, slots.first, recordedDays.contains(dayKey(day)), next, total);
        if (back == 0) {
          today.add(row);
        } else if (!row.recorded && next != null && !dismissed.contains(row.key)) {
          missed.add(row);
        }
      }
    }
    today.sort((a, b) => minutesOf(a.time).compareTo(minutesOf(b.time)));
    missed.sort((a, b) => b.day.compareTo(a.day));

    // With nothing today, say when the next class is.
    (DateTime, Json, Json)? upcoming;
    if (today.isEmpty) {
      for (var ahead = 1; ahead <= 7 && upcoming == null; ahead++) {
        final day = DateTime(now.year, now.month, now.day + ahead);
        for (final tuition in widget.tuitions) {
          final slots = slotsOn(tuition.maps('routine'), day);
          if (slots.isEmpty) continue;
          final candidate = (day, tuition, slots.first);
          final current = upcoming;
          if (current == null || minutesOf(slotStart(slots.first)) < minutesOf(slotStart(current.$3))) upcoming = candidate;
        }
      }
    }
    return (today: today, missed: missed, next: upcoming);
  }

  Future<void> _record(_ClassRow row) async {
    final classNo = row.nextClassNo;
    if (classNo == null) return;
    final repo = context.read<Repo>();
    final at = DateTime(row.day.year, row.day.month, row.day.day, 12);
    final ok = await attemptSave(
      context,
      () => repo.markClass(row.tuition.str('id'), classNo, true, date: at, tuitionTitle: row.tuition.str('title')),
      success: 'Class $classNo of ${row.tuition.str('title')} marked done.',
    );
    if (ok) await widget.reload();
  }

  Future<void> _reviewMissed(List<_ClassRow> missed, Set<String> dismissed) async {
    final settings = context.read<Session>().settings;
    final picked = await showModalBottomSheet<(_ClassRow, bool)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const Text('Classes not marked', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(
                'Your routine had these classes in the last week, but none was marked done that day. Mark the ones you taught.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              gap12,
              for (final row in missed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(row.tuition.str('title'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${fmtDate(row.day)} · ${to12h(row.time)}'),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'No class that day',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, (row, false)),
                      ),
                      FilledButton.tonal(onPressed: () => Navigator.pop(context, (row, true)), child: const Text('Mark done')),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final (row, held) = picked;
    if (held) {
      await _record(row);
    } else {
      await settings.setList(_dismissKey, [...dismissed, row.key].take(200).toList());
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = context.read<Session>().settings;
    final dismissed = settings.getList(_dismissKey).toSet();
    final plan = _plan(dismissed);
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    // The first class still to come today gets an "Up next" badge.
    final upNext = plan.today.where((r) => !r.recorded && minutesOf(r.time) >= nowMinutes - 30).firstOrNull;
    final hasRoutine = widget.tuitions.any((t) => t.maps('routine').isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          "Today's classes",
          icon: Icons.today_outlined,
          subtitle: '${weekdayName(now)}, ${fmtShortDate(now)}',
          trailing: plan.today.isEmpty
              ? null
              : Pill('${plan.today.where((r) => r.recorded).length}/${plan.today.length} done', color: AppColors.success),
        ),
        if (plan.today.isEmpty)
          AppCard(
            child: Row(
              children: [
                Icon(Icons.wb_sunny_outlined, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hasRoutine ? 'No classes today' : 'No weekly routine yet',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        switch (plan.next) {
                          (final day, final tuition, final slot) =>
                            'Next: ${tuition.str('title')} · ${weekdayName(day)} ${to12h(slotStart(slot))}',
                          null => hasRoutine
                              ? 'Enjoy the day off.'
                              : 'Add class days and times to a tuition and today\'s classes show up here.',
                        },
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < plan.today.length; i++) ...[
                  if (i > 0) const Divider(indent: 16, endIndent: 16),
                  _TodayClassRow(
                    row: plan.today[i],
                    upNext: identical(plan.today[i], upNext),
                    onMark: () => _record(plan.today[i]),
                  ),
                ],
              ],
            ),
          ),
        if (plan.missed.isNotEmpty) ...[
          gap8,
          Banner2(
            '${plan.missed.length} class${plan.missed.length == 1 ? '' : 'es'} from the last week ${plan.missed.length == 1 ? 'was' : 'were'} not marked.',
            color: AppColors.warning,
            icon: Icons.history_toggle_off,
            action: TextButton(onPressed: () => _reviewMissed(plan.missed, dismissed), child: const Text('Review')),
          ),
        ],
      ],
    );
  }
}

class _TodayClassRow extends StatelessWidget {
  const _TodayClassRow({required this.row, required this.upNext, required this.onMark});
  final _ClassRow row;
  final bool upNext;
  final Future<void> Function() onMark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final end = '${row.slot['end_time'] ?? ''}';
    final classNo = row.nextClassNo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(to12h(row.time), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: tone(context, AppColors.primarySoft))),
                if (end.isNotEmpty) Text(to12h(end), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Container(width: 3, height: 36, decoration: BoxDecoration(color: row.recorded ? AppColors.chartEarned : AppColors.chartPending, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(row.tuition.str('title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    if (upNext) ...[const SizedBox(width: 6), const Pill('Up next', color: AppColors.primarySoft)],
                  ],
                ),
                Text(
                  row.recorded
                      ? 'Marked done for today'
                      : classNo == null
                          ? 'This cycle is complete'
                          : 'Class $classNo of ${row.total}${row.tuition.str('subject').isEmpty ? '' : ' · ${row.tuition.str('subject')}'}',
                  style: TextStyle(color: row.recorded ? tone(context, AppColors.success) : scheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          if (row.recorded)
            Icon(Icons.check_circle, color: tone(context, AppColors.success))
          else if (classNo != null)
            BusyButton(onPressed: onMark, label: 'Done', icon: Icons.check),
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
              ListTile(title: Text('Add ${request.str('student_name')} to which tuition?', style: const TextStyle(fontWeight: FontWeight.w700))),
              for (final t in tuitions)
                ListTile(
                  leading: const Icon(Icons.class_outlined),
                  title: Text(t.str('title')),
                  subtitle: Text('${t.integer('enrolled_count')} student${t.integer('enrolled_count') == 1 ? '' : 's'}'),
                  onTap: () => Navigator.pop(context, t.str('id')),
                ),
            ],
          ),
        ),
      );
      if (tuitionId == null || !context.mounted) return;
    }
    String message = 'Accepted.';
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
        SectionTitle('Requests to join (${requests.length})', icon: Icons.person_add_alt_1_outlined),
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
                      FilledButton(onPressed: () => _accept(context, request, pickTuition: true), child: const Text('Accept & add to tuition')),
                    OutlinedButton(onPressed: () => _accept(context, request, pickTuition: false), child: const Text('Accept only')),
                    TextButton(
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          title: 'Decline this request?',
                          message: '${request.str('student_name')} will see that the request was declined and can ask again.',
                          confirmLabel: 'Decline',
                          danger: true,
                        );
                        if (!ok || !context.mounted) return;
                        if (await attempt(context, () => repo.rejectConnection(request.str('id')), success: 'Request declined.')) await reload();
                      },
                      child: const Text('Decline'),
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
