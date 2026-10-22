import 'dart:async';
import 'dart:math' show pi;

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
import '../../core/week_plan.dart';
import '../../widgets/charts.dart';
import '../../widgets/kit.dart';
import '../../widgets/share.dart';
import '../../widgets/student_kit.dart' show shortGap;
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
          children: staggered(context, [
            GreetingHeader(
              name: context.read<Session>().displayName,
              now: DateTime.now(),
              subtitle: _todaySummary(data.tuitions, data.wallet),
            ),
            _GetStarted(tuitions: data.tuitions, onCreateTuition: onCreateTuition, onOpen: open, reload: reload),
            _WalletStrip(wallet: data.wallet),
            if (data.requests.isNotEmpty) ...[
              gap8,
              _RequestsBanner(requests: data.requests, tuitions: data.tuitions, reload: reload),
            ],
            _Heading(tr('This week'), trailing: _weekSummary(data.tuitions)),
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
          ]),
        );
      },
    );
  }
}

/// "2 classes today · ৳1,500 to collect" under the greeting.
String _todaySummary(List<Json> tuitions, Json wallet) {
  final today = DateTime.now();
  final classes = tuitions.fold<int>(0, (n, t) => n + slotsOn(t.maps('routine'), today).length);
  final parts = <String>[
    classes == 0
        ? tr('No classes today')
        : classes == 1
            ? tr('1 class today')
            : tr('{n} classes today', {'n': classes}),
    if (wallet.integer('unpaid_cycles') > 0) tr('{p0} to collect', {'p0': taka(wallet.number('unpaid_total'))}),
  ];
  return parts.join(' · ');
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
    final tt = context.tt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 24, 2, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: tt.textPrimary))),
          if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 13, color: tt.textSecondary)),
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
    final earned = wallet.number('total_earned');
    final pending = wallet.number('total_pending');
    final total = earned + pending;
    final share = total <= 0 ? 0.0 : earned / total;
    final tt = context.tt;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Earned in current cycles'), style: TextStyle(fontSize: 13, height: 1.4, color: tt.textSecondary)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    taka(earned),
                    style: TextStyle(
                      fontSize: 30,
                      height: 1.15,
                      letterSpacing: -0.6,
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabular,
                      color: tt.success,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(tr('of {p0}', {'p0': taka(total)}),
                  style: TextStyle(fontSize: 13, fontFeatures: tabular, color: tt.textTertiary)),
            ],
          ),
          const SizedBox(height: 12),
          ProgressLine(value: share, height: 8, label: tr('Share of the current cycles already earned')),
          if (wallet.integer('unpaid_cycles') > 0) ...[
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const PaymentsScreen())),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: tt.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('{p0} to collect · {p1} unpaid cycle{p2}', {'p0': taka(wallet.number('unpaid_total')), 'p1': wallet.integer('unpaid_cycles'), 'p2': wallet.integer('unpaid_cycles') == 1 ? '' : 's'}),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tt.warning),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 20, color: tt.warning),
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

/// "This week": a strip of the seven days (Saturday first), then the classes
/// grouped by day. Today sits on a raised block, the next class is marked, and
/// days already over are quieter. By default only today and what is still to
/// come are listed; the rest of the week is one tap away.
class _WeekAtAGlance extends StatefulWidget {
  const _WeekAtAGlance({required this.tuitions, required this.onOpen});
  final List<Json> tuitions;
  final Future<void> Function(String tuitionId) onOpen;

  @override
  State<_WeekAtAGlance> createState() => _WeekAtAGlanceState();
}

class _WeekAtAGlanceState extends State<_WeekAtAGlance> {
  bool _whole = false;

  /// A day picked on the strip; null shows today and what is still to come.
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final now = DateTime.now();
    final plan = buildWeekPlan(widget.tuitions, now);
    final picked = _picked;
    final days = picked != null ? [picked] : plan.daysToShow(whole: _whole);
    final hasPast = plan.pastDaysWithClasses.isNotEmpty;
    // A busy week folds its past days into one row instead of listing them.
    final foldPast = picked == null && !_whole && plan.isBusy && hasPast;
    final next = plan.next;

    return Container(
      decoration: BoxDecoration(color: tt.card, borderRadius: BorderRadius.circular(20), boxShadow: tt.cardShadow),
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (next != null && picked == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _NextClassHero(item: next, plan: plan, now: now, onTap: () => widget.onOpen(next.tuition.str('id'))),
            ),
            const SizedBox(height: 16),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _DayStrip(
              plan: plan,
              picked: picked,
              onPick: (day) => setState(() => _picked = (day == _picked) ? null : day),
            ),
          ),
          const SizedBox(height: 12),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Divider(height: 1, color: tt.border)),
          if (plan.isEmpty)
            _WeekEmpty(hasTuitions: widget.tuitions.isNotEmpty)
          else ...[
            const SizedBox(height: 8),
            if (picked != null && plan.byDay[picked]!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  tr('No classes on {day}', {'day': dayLabel(picked, short: false)}),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: tt.textSecondary),
                ),
              ),
            if (foldPast)
              _PastSummary(plan: plan, onTap: () => setState(() => _whole = true)),
            for (final day in days)
              if (plan.byDay[day]!.isNotEmpty) _DayGroup(plan: plan, day: day, now: now, onOpen: widget.onOpen),
            if (picked != null)
              TextButton(
                onPressed: () => setState(() => _picked = null),
                child: Text(tr('Back to today and upcoming')),
              )
            else if (hasPast)
              TextButton(
                onPressed: () => setState(() => _whole = !_whole),
                child: Text(
                  _whole
                      ? tr('Show today and upcoming only')
                      : tr('Show whole week · {n} classes', {'n': plan.total}),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// "3 today · 12 this week" beside the heading.
String? _weekSummary(List<Json> tuitions) {
  final plan = buildWeekPlan(tuitions, DateTime.now());
  if (plan.isEmpty) return null;
  final today = plan.byDay[plan.today]!.length;
  return tr('{a} today · {b} this week', {'a': today, 'b': plan.total});
}

/// A stable colour per tuition, shared by its classes in the week and its card,
/// so the schedule and the cards read together.
const _tuitionPalette = [
  Color(0xFF5C95CB), // blue
  Color(0xFF4FA37F), // green
  Color(0xFFD9A443), // amber
  Color(0xFF8E7CC3), // violet
  Color(0xFF3FA3A8), // teal
  Color(0xFFD27A7A), // rose
];

Color tuitionColor(Json tuition) {
  final id = tuition.str('id');
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _tuitionPalette[hash % _tuitionPalette.length];
}

/// When a class of this week starts, as a date.
DateTime _classTime(WeekClass item, WeekPlan plan, DateTime now) {
  final offset = weekOrder.indexOf(item.day) - plan.todayIndex;
  final minutes = minutesOf(item.start);
  return DateTime(now.year, now.month, now.day + offset, minutes ~/ 60, minutes % 60);
}

/// Going on right now (started today and not over).
bool _isNow(WeekClass item, WeekPlan plan, DateTime now) =>
    item.day == plan.today && !item.past && minutesOf(item.start) <= now.hour * 60 + now.minute;

/// The next class, large: which tuition, when, and how long until it starts (or "Now").
class _NextClassHero extends StatelessWidget {
  const _NextClassHero({required this.item, required this.plan, required this.now, required this.onTap});
  final WeekClass item;
  final WeekPlan plan;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final color = tuitionColor(item.tuition);
    final at = _classTime(item, plan, now);
    final live = _isNow(item, plan, now);
    final students = item.tuition.integer('enrolled_count');
    final subject = item.tuition.str('subject');
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              Container(width: 4, height: 48, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(live ? tr('Class now') : tr('Next class'),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: live ? tt.success : tt.textSecondary)),
                    const SizedBox(height: 2),
                    Text(item.tuition.str('title'),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tt.textPrimary)),
                    Text(
                      [
                        whenLabel(at, now),
                        if (subject.isNotEmpty) subject,
                        tr('{p0} student{p1}', {'p0': students, 'p1': students == 1 ? '' : 's'}),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: tt.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: live ? tt.success : color, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  live ? tr('Now') : tr('in {t}', {'t': Raw(shortGap(at.difference(now)))}),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seven equal cells: day name, a marker, and a bar under today.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.plan, required this.picked, required this.onPick});
  final WeekPlan plan;
  final String? picked;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Row(
      children: [
        for (final (i, day) in weekOrder.indexed) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onPick(day),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: picked == day ? tt.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _DayCell(day: day, count: plan.byDay[day]!.length, isToday: day == plan.today, isPast: plan.isPastDay(day), tt: tt),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.count, required this.isToday, required this.isPast, required this.tt});
  final String day;
  final int count;
  final bool isToday;
  final bool isPast;
  final TtTokens tt;

  @override
  Widget build(BuildContext context) {
    final name = isBangla ? dayLabel(day) : day.substring(0, 2);
    final countText = Text(
      localDigits('$count'),
      style: TextStyle(
        fontSize: 13,
        height: 1,
        fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
        fontFeatures: tabular,
        color: isToday ? tt.onPrimary : (isPast ? tt.textTertiary : tt.onPrimaryContainer),
      ),
    );
    final Widget marker;
    if (isToday) {
      marker = Container(
        decoration: BoxDecoration(color: tt.primary, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: countText,
      );
    } else if (count == 0) {
      // A free day: dashed outline and a dash, so it never depends on colour.
      marker = CustomPaint(
        painter: _DashedCircle(tt.textTertiary),
        child: Center(child: Text('–', style: TextStyle(fontSize: 13, height: 1, color: tt.textTertiary))),
      );
    } else {
      marker = Container(
        decoration: BoxDecoration(
          color: isPast ? tt.pastDayFill : tt.primaryContainer,
          shape: BoxShape.circle,
          border: Border.all(color: isPast ? tt.border : tt.primary.withValues(alpha: 0.35)),
        ),
        alignment: Alignment.center,
        child: countText,
      );
    }
    return Semantics(
      label: '${dayLabel(day, short: false)}: '
          '${count == 0 ? tr('no classes') : tr('{n} classes', {'n': count})}'
          '${isToday ? tr(', today') : ''}',
      excludeSemantics: true,
      child: Column(
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              color: isToday ? tt.primary : tt.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(width: 30, height: 30, child: marker),
          const SizedBox(height: 6),
          Container(
            width: 16,
            height: 3,
            decoration: BoxDecoration(
              color: isToday ? tt.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dashes = 14;
    const sweep = 2 * pi / dashes;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

/// A busy week's past days in one row; tapping it shows them.
class _PastSummary extends StatelessWidget {
  const _PastSummary({required this.plan, required this.onTap});
  final WeekPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final days = plan.pastDaysWithClasses;
    final range = days.length == 1 ? dayLabel(days.first) : '${dayLabel(days.first)} – ${dayLabel(days.last)}';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr('{days} · {n} classes done', {'days': range, 'n': plan.pastDayClasses}),
                  style: TextStyle(fontSize: 14, color: tt.textSecondary, fontFeatures: tabular),
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: tt.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// One day's classes under its header; today's group sits on a raised block.
class _DayGroup extends StatelessWidget {
  const _DayGroup({required this.plan, required this.day, required this.now, required this.onOpen});
  final WeekPlan plan;
  final String day;
  final DateTime now;
  final Future<void> Function(String tuitionId) onOpen;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final isToday = day == plan.today;
    final isPast = plan.isPastDay(day);
    final header = isToday
        ? tr('Today · {day}', {'day': dayLabel(day, short: !isBangla)})
        : dayLabel(day, short: !isBangla);
    final group = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Text(
            header,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
              color: isToday ? tt.primary : (isPast ? tt.textTertiary : tt.textSecondary),
            ),
          ),
        ),
        for (final c in plan.byDay[day]!) _ClassRow(item: c, live: _isNow(c, plan, now), onTap: () => onOpen(c.tuition.str('id'))),
      ],
    );
    if (!isToday) return group;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(color: tt.cardRaised, borderRadius: BorderRadius.circular(12)),
      child: group,
    );
  }
}

/// [ start / end ] [ dot ] [ tuition name ] [ Next ] [ > ] — the whole row opens the tuition.
class _ClassRow extends StatelessWidget {
  const _ClassRow({required this.item, required this.onTap, this.live = false});
  final WeekClass item;
  final VoidCallback onTap;

  /// The class is going on right now.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final ink = item.past ? tt.textSecondary : tt.textPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: isBangla ? 64 : 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              SizedBox(
                width: isBangla ? 86 : 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(to12h(item.start),
                        maxLines: 1,
                        style: TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w600, fontFeatures: tabular, color: ink)),
                    if (item.end.isNotEmpty)
                      Text(to12h(item.end),
                          maxLines: 1,
                          style: TextStyle(fontSize: 12, height: 1.3, fontFeatures: tabular, color: tt.textTertiary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Dot(item: item, tt: tt),
              const SizedBox(width: 10),
              // The tuition's colour, the same as on its card below.
              Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: tuitionColor(item.tuition).withValues(alpha: item.past ? 0.35 : 1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.tuition.str('title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: isBangla ? 1.55 : 1.45, color: ink),
                    ),
                    Text(
                      [
                        if (item.tuition.str('subject').isNotEmpty) item.tuition.str('subject'),
                        tr('{p0} student{p1}', {'p0': item.tuition.integer('enrolled_count'), 'p1': item.tuition.integer('enrolled_count') == 1 ? '' : 's'}),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: tt.textTertiary),
                    ),
                  ],
                ),
              ),
              if (live) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: tt.successContainer, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: tt.success, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(tr('Now'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tt.onSuccessContainer)),
                    ],
                  ),
                ),
              ] else if (item.isNext) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: tt.primaryContainer, borderRadius: BorderRadius.circular(8)),
                  child: Text(tr('Next'),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tt.onPrimaryContainer)),
                ),
              ],
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 22, color: tt.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Next class: filled primary with a ring. Other upcoming: hollow. Past: solid grey.
class _Dot extends StatelessWidget {
  const _Dot({required this.item, required this.tt});
  final WeekClass item;
  final TtTokens tt;

  @override
  Widget build(BuildContext context) {
    if (item.isNext) {
      // A 9 dp dot with a 3 dp ring around it: 15 dp in all, like the others' box.
      return Container(
        width: 9,
        height: 9,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: tt.primary,
          shape: BoxShape.circle,
          border: Border.all(color: tt.primaryContainer, width: 3, strokeAlign: BorderSide.strokeAlignOutside),
        ),
      );
    }
    return SizedBox(
      width: 15,
      height: 15,
      child: Center(
        child: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: item.past ? tt.dotPast : Colors.transparent,
            shape: BoxShape.circle,
            border: item.past ? null : Border.all(color: tt.dotUpcoming, width: 2),
          ),
        ),
      ),
    );
  }
}

/// No class days anywhere this week.
class _WeekEmpty extends StatelessWidget {
  const _WeekEmpty({required this.hasTuitions});
  final bool hasTuitions;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      child: Column(
        children: [
          Icon(Icons.calendar_today_outlined, size: 32, color: tt.textTertiary),
          const SizedBox(height: 12),
          Text(tr('No classes this week'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tt.textPrimary)),
          const SizedBox(height: 4),
          Text(
            hasTuitions ? tr('No class days set yet. Add them when you edit a tuition.') : tr('Your class days appear here.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: tt.textSecondary),
          ),
        ],
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
        const spacing = 12.0;
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
    final tt = context.tt;
    final cycle = tuition.obj('active_cycle');
    final done = cycle?.integer('completed_classes') ?? 0;
    final total = cycle?.integer('total_classes') ?? tuition.integer('cycle_length');
    final cycleNo = cycle?.integer('cycle_number') ?? 1;
    final students = tuition.integer('enrolled_count');
    final due = tuition.maps('pending_payments').isNotEmpty;
    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      accent: tuitionColor(tuition),
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: isBangla ? 116 : 104),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tuition.str('title'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tt.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    '${tr('{p0} student{p1}', {'p0': students, 'p1': students == 1 ? '' : 's'})} · ${tr('Cycle {p0}', {'p0': cycleNo})}',
                    style: TextStyle(fontSize: 12, height: 1.4, color: tt.textSecondary),
                  ),
                  if (due) ...[
                    const SizedBox(height: 8),
                    _DueChip(tt: tt),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            ProgressRing(done: done, total: total, size: 52, thickness: 4),
          ],
        ),
      ),
    );
  }
}

/// Amber "Due" badge: a cycle of this tuition waits for payment. Word + dot, never colour alone.
class _DueChip extends StatelessWidget {
  const _DueChip({required this.tt});
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
