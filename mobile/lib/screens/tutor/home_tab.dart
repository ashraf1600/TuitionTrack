import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/cycle_progress.dart';
import 'group_screen.dart';

class _HomeData {
  _HomeData(this.wallet, this.tuitions, this.requests);
  final Json wallet;
  final List<Json> tuitions;
  final List<Json> requests;
}

/// Overview: the Tuition Wallet, today's classes from the weekly routine, and students asking to join.
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
          _TodayClasses(tuitions: data.tuitions, reload: reload),
          if (data.requests.isNotEmpty) _Requests(requests: data.requests, tuitions: data.tuitions, reload: reload),
          SectionTitle(
            'Earnings by group',
            icon: Icons.account_balance_wallet_outlined,
            trailing: TextButton(onPressed: () => onOpenTab(1), child: Text('All groups')),
          ),
          if (data.wallet.maps('tuition_breakdowns').isEmpty)
            EmptyState(
              icon: Icons.groups_outlined,
              title: 'No tuition groups yet',
              message: 'Create a group, add students, and mark classes as you teach. Your earnings build up here.',
              action: FilledButton(onPressed: () => onOpenTab(1), child: Text('Go to groups')),
            )
          else
            for (final row in data.wallet.maps('tuition_breakdowns')) ...[
              AppCard(
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => GroupScreen(tuitionId: row.str('tuition_id'))));
                  await reload();
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(row.str('tuition_title'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                        Text(taka(row.number('earned')), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.success)),
                        Text(' of ${taka(row.number('total_fee'))}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Cycle #${row.integer('cycle_number')} · ${row.integer('completed_classes')}/${row.integer('total_classes')} classes · '
                      '${row.integer('student_count')} student${row.integer('student_count') == 1 ? '' : 's'} · ${taka(row.number('per_class_rate'))} per class',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                    gap8,
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: row.integer('total_classes') == 0 ? 0 : row.integer('completed_classes') / row.integer('total_classes'),
                        minHeight: 6,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              gap8,
            ],
          if (data.wallet.maps('student_breakdowns').isNotEmpty) ...[
            SectionTitle('One-to-one students', subtitle: 'Older individual cycles, not part of a group.'),
            for (final row in data.wallet.maps('student_breakdowns')) ...[
              AppCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row.str('student_name'), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${row.integer('completed_classes')}/${row.integer('total_classes')} classes', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                        ],
                      ),
                    ),
                    Text(taka(row.number('earned')), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.success)),
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

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet});
  final Json wallet;

  @override
  Widget build(BuildContext context) {
    final earned = wallet.number('total_earned');
    final pending = wallet.number('total_pending');
    final total = earned + pending;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF312E81), Color(0xFF0F172A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: AppColors.primarySoft, size: 20),
              SizedBox(width: 8),
              Text('Tuition Wallet', style: TextStyle(color: AppColors.primarySoft, fontWeight: FontWeight.w700)),
            ],
          ),
          gap12,
          Text('Earned in current cycles', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          Text(taka(earned), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.success)),
          gap8,
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total <= 0 ? 0 : earned / total,
              minHeight: 8,
              color: AppColors.success,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              semanticsLabel: 'Share of current cycles already earned',
            ),
          ),
          gap16,
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              Stat(label: 'Still to earn', value: taka(pending), color: AppColors.primarySoft),
              Stat(label: 'Past cycles', value: taka(wallet.number('lifetime_archived_earnings'))),
              Stat(label: 'Groups', value: '${wallet.integer('total_tuitions')}'),
              Stat(label: 'Students', value: '${wallet.integer('total_students')}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClassRow {
  _ClassRow(this.tuition, this.day, this.time, this.recorded, this.nextClassNo);
  final Json tuition;
  final DateTime day;
  final String time;
  final bool recorded;
  final int? nextClassNo;
  String get key => '${tuition.str('id')}:${dayKey(day)}';
}

/// Connects the weekly routine to the class tracker.
///
///  - Today: every group with a class in today's routine, with one tap to record it.
///  - Not recorded: routine days in the last week with no class dated that day,
///    so a class that was held but never ticked does not silently go unpaid.
class _TodayClasses extends StatefulWidget {
  const _TodayClasses({required this.tuitions, required this.reload});
  final List<Json> tuitions;
  final Future<void> Function() reload;

  @override
  State<_TodayClasses> createState() => _TodayClassesState();
}

class _TodayClassesState extends State<_TodayClasses> {
  static const _lookbackDays = 7;
  static const _dismissKey = 'routine_dismissed_classes';

  @override
  Widget build(BuildContext context) {
    final settings = context.read<Session>().settings;
    final dismissed = settings.getList(_dismissKey).toSet();
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
      // Never look back past the start of the current cycle or the group itself.
      final cycleStart = cycle.date('created_at') ?? now;
      final groupStart = tuition.date('created_at') ?? now;
      final earliest = dayKey(cycleStart.isAfter(groupStart) ? cycleStart : groupStart);

      for (var back = 0; back <= _lookbackDays; back++) {
        final day = DateTime(now.year, now.month, now.day - back);
        if (dayKey(day).compareTo(earliest) < 0) break;
        final slots = routine.where((s) => s.str('day').toLowerCase() == weekdayName(day).toLowerCase()).toList();
        if (slots.isEmpty) continue;
        final row = _ClassRow(tuition, day, slots.first.str('start_time', slots.first.str('time')), recordedDays.contains(dayKey(day)), next);
        if (back == 0) {
          today.add(row);
        } else if (!row.recorded && next != null && !dismissed.contains(row.key)) {
          missed.add(row);
        }
      }
    }
    if (today.isEmpty && missed.isEmpty) return const SizedBox.shrink();
    today.sort((a, b) => a.time.compareTo(b.time));
    missed.sort((a, b) => b.day.compareTo(a.day));

    Future<void> record(_ClassRow row) async {
      final repo = context.read<Repo>();
      final at = DateTime(row.day.year, row.day.month, row.day.day, 12);
      final ok = await attempt(
        context,
        () => repo.markClass(row.tuition.str('id'), row.nextClassNo!, true, date: at),
        success: 'Class ${row.nextClassNo} recorded for ${row.tuition.str('title')}.',
      );
      if (ok) await widget.reload();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle("Today's classes", icon: Icons.event_available_outlined),
        if (today.isEmpty)
          Text('No classes in your routine today.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
        else
          for (final row in today) ...[
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.tuition.str('title'), style: TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          row.recorded
                              ? 'Recorded for today'
                              : row.nextClassNo == null
                                  ? 'This cycle is complete'
                                  : '${to12h(row.time)} · class ${row.nextClassNo} of the cycle',
                          style: TextStyle(color: row.recorded ? AppColors.success : Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (row.recorded)
                    Icon(Icons.check_circle, color: AppColors.success)
                  else if (row.nextClassNo != null)
                    BusyButton(onPressed: () => record(row), label: 'Mark done', icon: Icons.check),
                ],
              ),
            ),
            gap8,
          ],
        if (missed.isNotEmpty) ...[
          gap8,
          Text('Not recorded in the last week', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
          gap8,
          for (final row in missed) ...[
            AppCard(
              borderColor: AppColors.warning.withValues(alpha: 0.4),
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row.tuition.str('title'), style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${fmtDate(row.day)} · was it held?', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                      ],
                    ),
                  ),
                  TextButton(onPressed: () => record(row), child: const Text('Yes, record')),
                  IconButton(
                    tooltip: 'No class that day',
                    icon: Icon(Icons.close, size: 20),
                    onPressed: () async {
                      await settings.setList(_dismissKey, [...dismissed, row.key].take(200).toList());
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
            ),
            gap8,
          ],
        ],
      ],
    );
  }
}

/// Students who asked to join this tutor.
class _Requests extends StatelessWidget {
  const _Requests({required this.requests, required this.tuitions, required this.reload});
  final List<Json> requests;
  final List<Json> tuitions;
  final Future<void> Function() reload;

  Future<void> _accept(BuildContext context, Json request, {required bool pickGroup}) async {
    final repo = context.read<Repo>();
    String? tuitionId;
    if (pickGroup) {
      tuitionId = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text('Add ${request.str('student_name')} to which group?', style: TextStyle(fontWeight: FontWeight.w700))),
              for (final t in tuitions)
                ListTile(
                  leading: Icon(Icons.groups_outlined),
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
                Text(request.str('student_name'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
                      FilledButton(onPressed: () => _accept(context, request, pickGroup: true), child: const Text('Accept & add to group')),
                    OutlinedButton(onPressed: () => _accept(context, request, pickGroup: false), child: const Text('Accept only')),
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
