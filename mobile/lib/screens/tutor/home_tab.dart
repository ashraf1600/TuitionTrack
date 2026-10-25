import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import 'to_check_screen.dart';
import 'tuition_form_screen.dart';
import 'tuition_screen.dart';

class _HomeData {
  _HomeData(this.wallet, this.tuitions, this.requests, this.updates);
  final Json wallet;
  final List<Json> tuitions;
  final List<Json> requests;

  /// The notification feed: work to grade and homework handed in come from here.
  final List<Json> updates;
}

/// Overview: what to do now. The next class (mark it done in one tap), what
/// is waiting to be checked across all tuitions, and the week. Tuitions and
/// money have their own tabs.
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
        final results = await Future.wait<dynamic>([
          repo.wallet(),
          repo.tuitions(),
          repo.connections('PENDING'),
          repo.notifications().catchError((_) => <Json>[]),
        ]);
        final tuitions = results[1] as List<Json>;
        // Class reminders for the coming week, set again on every load (they work offline).
        unawaited(Reminders.instance.schedule(settings, tutorReminders(tuitions, DateTime.now())));
        return _HomeData(results[0] as Json, tuitions, results[2] as List<Json>, results[3] as List<Json>);
      },
      builder: (context, data, reload) {
        Future<void> open(String tuitionId) async {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TuitionScreen(tuitionId: tuitionId)));
          await reload();
        }

        final now = DateTime.now();
        final plan = buildWeekPlan(data.tuitions, now);
        final next = plan.next;
        return PageBody(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: staggered(context, [
            GreetingHeader(
              name: context.read<Session>().displayName,
              now: now,
              subtitle: _todaySummary(data.tuitions, data.wallet),
            ),
            _GetStarted(tuitions: data.tuitions, onCreateTuition: onCreateTuition, onOpen: open, reload: reload),
            if (next != null) _NextUp(item: next, plan: plan, now: now, onOpen: () => open(next.tuition.str('id')), reload: reload),
            if (data.tuitions.isNotEmpty) ...[
              _ToCheck(updates: data.updates, requests: data.requests, tuitions: data.tuitions, reload: reload),
              _Heading(tr('This week'), trailing: _weekSummary(data.tuitions)),
              _WeekAtAGlance(tuitions: data.tuitions, onOpen: open),
            ] else
              EmptyState(
                icon: Icons.class_outlined,
                title: tr('No tuitions yet'),
                message: tr('Create a tuition, add its students and class days, then mark classes as you teach.'),
                action: FilledButton.icon(onPressed: onCreateTuition, icon: const Icon(Icons.add), label: Text(tr('New tuition'))),
              ),
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

/// The list of students asking to join, in a sheet.
Future<void> _openRequests(BuildContext context, List<Json> requests, List<Json> tuitions, Future<void> Function() reload) {
  return showModalBottomSheet<void>(
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
  );
}

/// Everything waiting on the tutor, across all tuitions: answers to grade,
/// homework handed in, students asking to join. "All caught up" when empty.
class _ToCheck extends StatelessWidget {
  const _ToCheck({required this.updates, required this.requests, required this.tuitions, required this.reload});
  final List<Json> updates;
  final List<Json> requests;
  final List<Json> tuitions;
  final Future<void> Function() reload;

  Future<void> _openList(BuildContext context, int tab) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ToCheckScreen(initialTab: tab)));
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final grade = updates.where((n) => n.str('kind') == 'grade').toList();
    final toGrade = grade.fold<int>(0, (sum, n) => sum + (int.tryParse(n.str('id').split('-').last) ?? 1));
    final handedIn = updates.where((n) => n.str('kind') == 'homework' && n.str('id').startsWith('handed-in-')).toList();
    final total = toGrade + handedIn.length + requests.length;
    final rows = <Widget>[
      if (toGrade > 0)
        _CheckRow(
          icon: Icons.fact_check_outlined,
          accent: AppColors.success,
          title: toGrade == 1 ? tr('1 exam answer to grade') : tr('{n} exam answers to grade', {'n': toGrade}),
          subtitle: grade.map((n) => n.str('body')).where((b) => b.isNotEmpty).toSet().join(', '),
          onTap: () => _openList(context, 0),
        ),
      if (handedIn.isNotEmpty)
        _CheckRow(
          icon: Icons.menu_book_rounded,
          accent: AppColors.warning,
          title: handedIn.length == 1 ? tr('1 homework handed in') : tr('{n} homework handed in', {'n': handedIn.length}),
          subtitle: handedIn.map((n) => n.str('title').replaceAll(' handed in homework', '')).toSet().join(', '),
          onTap: () => _openList(context, 1),
        ),
      if (requests.isNotEmpty)
        _CheckRow(
          icon: Icons.person_add_alt_1_outlined,
          accent: AppColors.primarySoft,
          title: requests.length == 1 ? tr('1 student asked to join') : tr('{n} students asked to join', {'n': requests.length}),
          subtitle: requests.map((r) => r.str('student_name')).where((n) => n.isNotEmpty).join(', '),
          onTap: () => _openRequests(context, requests, tuitions, reload),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 24, 2, 10),
          child: Row(
            children: [
              Text(tr('To check'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: tt.textPrimary)),
              if (total > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(color: tt.cardRaised, borderRadius: BorderRadius.circular(10)),
                  child: Text(localDigits('$total'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tt.textSecondary)),
                ),
              ],
              const Spacer(),
              TextButton(onPressed: () => _openList(context, 0), child: Text(tr('See all'))),
            ],
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.task_alt_rounded, color: tt.success),
                      const SizedBox(width: 12),
                      Expanded(child: Text(tr('All caught up. Nothing waiting to be checked.'), style: TextStyle(fontSize: 14, color: tt.textSecondary))),
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (final (i, row) in rows.indexed) ...[
                      if (i > 0) Divider(height: 1, indent: 64, color: tt.border),
                      row,
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.icon, required this.accent, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: tonalContainer(context, accent), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20, color: tone(context, accent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tt.textPrimary)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: tt.textSecondary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: tt.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// "This week", kept small: a strip of the seven days
/// (Saturday first), and the classes of one day as cards — today by default,
/// or whichever day is tapped.
class _WeekAtAGlance extends StatefulWidget {
  const _WeekAtAGlance({required this.tuitions, required this.onOpen});
  final List<Json> tuitions;
  final Future<void> Function(String tuitionId) onOpen;

  @override
  State<_WeekAtAGlance> createState() => _WeekAtAGlanceState();
}

class _WeekAtAGlanceState extends State<_WeekAtAGlance> {
  /// The day shown below the strip; null means today.
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final now = DateTime.now();
    final plan = buildWeekPlan(widget.tuitions, now);
    final day = _picked ?? plan.today;
    final classes = plan.byDay[day]!;

    return Container(
      decoration: BoxDecoration(color: tt.card, borderRadius: BorderRadius.circular(20), boxShadow: tt.cardShadow),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DayStrip(
            plan: plan,
            picked: day,
            onPick: (d) => setState(() => _picked = d == plan.today ? null : d),
          ),
          const SizedBox(height: 12),
          if (plan.isEmpty)
            _WeekEmpty(hasTuitions: widget.tuitions.isNotEmpty)
          else if (classes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                day == plan.today ? tr('No classes today.') : tr('No classes on {day}', {'day': dayLabel(day, short: false)}),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: tt.textSecondary),
              ),
            )
          else
            for (final (i, c) in classes.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              _ClassCard(item: c, live: _isNow(c, plan, now), onTap: () => widget.onOpen(c.tuition.str('id'))),
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

/// When a class of this week starts, as a date.
DateTime _classTime(WeekClass item, WeekPlan plan, DateTime now) {
  final offset = weekOrder.indexOf(item.day) - plan.todayIndex;
  final minutes = minutesOf(item.start);
  return DateTime(now.year, now.month, now.day + offset, minutes ~/ 60, minutes % 60);
}

/// Going on right now (started today and not over).
bool _isNow(WeekClass item, WeekPlan plan, DateTime now) =>
    item.day == plan.today && !item.past && minutesOf(item.start) <= now.hour * 60 + now.minute;

/// The next class, large, with the two things to do about it: mark it done
/// (dated today, with Undo) or open the tuition.
class _NextUp extends StatelessWidget {
  const _NextUp({required this.item, required this.plan, required this.now, required this.onOpen, required this.reload});
  final WeekClass item;
  final WeekPlan plan;
  final DateTime now;
  final VoidCallback onOpen;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final color = tuitionColorOf(item.tuition.str('id'));
    final at = _classTime(item, plan, now);
    final live = _isNow(item, plan, now);
    final students = item.tuition.integer('enrolled_count');
    final cycle = item.tuition.obj('active_cycle');
    final nextNo = cycle == null ? null : orderedClasses(cycle).where((c) => !c.flag('completed')).firstOrNull;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Color.alphaBlend(color.withValues(alpha: 0.10), tt.card), borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Container(width: 4, height: 52, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(live ? tr('Class now') : tr('Next class'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: live ? tt.success : tt.textSecondary)),
                      const SizedBox(height: 2),
                      Text(item.tuition.str('title'),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: tt.textPrimary)),
                      Text(
                        [
                          '${whenLabel(at, now)}${item.end.isEmpty ? '' : ' – ${to12h(item.end)}'}',
                          tr('{p0} student{p1}', {'p0': students, 'p1': students == 1 ? '' : 's'}),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: tt.textSecondary),
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: tt.onPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (nextNo != null) ...[
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    onPressed: () async {
                      await markNextClassFromReminder(context.read<Repo>(), context.read<Session>(), item.tuition.str('id'));
                      await reload();
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: Text(tr('Mark class done')),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(88, 46)),
                onPressed: onOpen,
                child: Text(tr('Open')),
              ),
            ],
          ),
        ],
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

/// One class as a small card in the tuition's colour: time, tuition, subject
/// and students, with "Now" or "Next" when it applies. Opens the tuition.
class _ClassCard extends StatelessWidget {
  const _ClassCard({required this.item, required this.onTap, this.live = false});
  final WeekClass item;
  final VoidCallback onTap;

  /// The class is going on right now.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final color = tuitionColorOf(item.tuition.str('id'));
    final ink = item.past ? tt.textSecondary : tt.textPrimary;
    final students = item.tuition.integer('enrolled_count');
    return Material(
      color: tt.cardRaised,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The tuition's colour, the same as on its card below.
              Container(width: 4, color: color.withValues(alpha: item.past ? 0.35 : 1)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: isBangla ? 84 : 68,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(to12h(item.start),
                                maxLines: 1,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFeatures: tabular, color: ink)),
                            if (item.end.isNotEmpty)
                              Text(to12h(item.end), maxLines: 1, style: TextStyle(fontSize: 12, fontFeatures: tabular, color: tt.textTertiary)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.tuition.str('title'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: isBangla ? 1.55 : 1.4, color: ink)),
                            Text(
                              [
                                if (item.tuition.str('subject').isNotEmpty) item.tuition.str('subject'),
                                tr('{p0} student{p1}', {'p0': students, 'p1': students == 1 ? '' : 's'}),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: tt.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      if (live)
                        _Tag(tr('Now'), background: tt.successContainer, foreground: tt.onSuccessContainer)
                      else if (item.isNext)
                        _Tag(tr('Next'), background: tt.primaryContainer, foreground: tt.onPrimaryContainer)
                      else if (item.past)
                        Icon(Icons.check_rounded, size: 18, color: tt.textTertiary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {required this.background, required this.foreground});
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: foreground)),
      );
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
