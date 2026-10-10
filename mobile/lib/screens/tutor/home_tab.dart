import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/charts.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
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
        final results = await Future.wait<dynamic>([repo.wallet(), repo.tuitions(), repo.connections('PENDING')]);
        return _HomeData(results[0] as Json, results[1] as List<Json>, results[2] as List<Json>);
      },
      builder: (context, data, reload) {
        Future<void> open(String tuitionId) async {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TuitionScreen(tuitionId: tuitionId)));
          await reload();
        }

        return PageBody(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _WalletStrip(wallet: data.wallet),
            if (data.requests.isNotEmpty) ...[
              gap8,
              _RequestsBanner(requests: data.requests, tuitions: data.tuitions, reload: reload),
            ],
            const _Heading('This week'),
            _WeekAtAGlance(tuitions: data.tuitions, onOpen: open),
            _Heading('Tuitions', trailing: data.tuitions.isEmpty ? null : '${data.tuitions.length}'),
            if (data.tuitions.isEmpty)
              EmptyState(
                icon: Icons.class_outlined,
                title: 'No tuitions yet',
                message: 'Create a tuition, add its students and class days, then mark classes as you teach.',
                action: FilledButton.icon(onPressed: onCreateTuition, icon: const Icon(Icons.add), label: const Text('New tuition')),
              )
            else
              _TuitionGrid(tuitions: data.tuitions, onOpen: open),
          ],
        );
      },
    );
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
                    Text('Earned in current cycles', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(taka(earned), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: tone(context, AppColors.success))),
                  ],
                ),
              ),
              Text('of ${taka(total)}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          ProgressLine(value: share, height: 5, label: 'Share of the current cycles already earned'),
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
      '$n student${n == 1 ? '' : 's'} asked to join you.',
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
        child: const Text('Review'),
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
                    label: '$day: ${byDay[day]!.isEmpty ? 'no classes' : '${byDay[day]!.length} classes'}${day == today ? ', today' : ''}',
                    excludeSemantics: true,
                    child: Column(
                      children: [
                        Text(day.substring(0, 2),
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
                tuitions.isEmpty ? 'Your class days appear here.' : 'No class days set yet. Add them when you edit a tuition.',
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
                  day: i == 0 ? day.substring(0, 3) : '',
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
  const _TuitionGrid({required this.tuitions, required this.onOpen});
  final List<Json> tuitions;
  final Future<void> Function(String tuitionId) onOpen;

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
              SizedBox(width: width, child: _TuitionCard(tuition: tuition, onTap: () => onOpen(tuition.str('id')))),
          ],
        );
      },
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
    final done = cycle?.integer('completed_classes') ?? 0;
    final total = cycle?.integer('total_classes') ?? tuition.integer('cycle_length');
    final cycleNo = cycle?.integer('cycle_number') ?? 1;
    final complete = total > 0 && done >= total;
    return AppCard(
      onTap: onTap,
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
              Text('Cycle $cycleNo', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const Spacer(),
              Text('$done/$total',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: complete ? tone(context, AppColors.success) : scheme.onSurface)),
            ],
          ),
          const SizedBox(height: 6),
          ProgressLine(value: total == 0 ? 0.0 : done / total, height: 4, label: '$done of $total classes done'),
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
