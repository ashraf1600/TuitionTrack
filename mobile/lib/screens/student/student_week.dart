import 'package:flutter/material.dart';

import '../../core/connect.dart' show tutorSirName;
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/week_plan.dart';
import '../../theme/tt_theme.dart';
import '../../widgets/charts.dart' show tuitionColorOf;
import '../../widgets/student_kit.dart' show shortGap;
import '../../widgets/ui.dart';

// A student's classes across every tutor. Classes are named by the tutor and
// subject ("Ashraful Sir · Physics"), never by the tuition's own name.

/// "Ashraful Sir · Physics" (just the tutor when there is no subject).
String studentClassName(Json tuition) {
  final sir = tutorSirName(tuition);
  final subject = tuition.str('subject').trim();
  return [if (sir.isNotEmpty) sir, if (subject.isNotEmpty) subject].join(' · ');
}

/// "10:00 AM – 11:30 AM".
String _timeRange(WeekClass c) => c.end.isEmpty ? to12h(c.start) : '${to12h(c.start)} – ${to12h(c.end)}';

/// Started today and not over yet.
bool _isNow(WeekClass c, WeekPlan plan, DateTime now) =>
    c.day == plan.today && !c.past && minutesOf(c.start) <= now.hour * 60 + now.minute;

DateTime _startOf(WeekClass c, WeekPlan plan, DateTime now) {
  final offset = weekOrder.indexOf(c.day) - plan.todayIndex;
  final m = minutesOf(c.start);
  return DateTime(now.year, now.month, now.day + offset, m ~/ 60, m % 60);
}

/// On the student home: the next class this week (or the one going on now),
/// with a link to the whole week. Nothing when no tutor has set class days.
class StudentNextClass extends StatelessWidget {
  const StudentNextClass({super.key, required this.tuitions, required this.photos, required this.onWholeWeek});
  final List<Json> tuitions;

  /// Tutor id -> photo.
  final Map<String, String?> photos;
  final VoidCallback onWholeWeek;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final plan = buildWeekPlan(tuitions, now);
    final next = plan.next;
    if (plan.isEmpty) return const SizedBox.shrink();
    final tt = context.tt;
    final today = plan.byDay[plan.today]!;
    final live = next != null && _isNow(next, plan, now);
    final color = next == null ? tt.primary : tuitionColorOf(next.tuition.str('id'));
    return Material(
      color: tt.card,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onWholeWeek,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                  child: next == null
                      ? Row(
                          children: [
                            Icon(Icons.event_available_rounded, color: tt.textSecondary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(tr('No more classes this week.'),
                                  style: TextStyle(fontSize: 14, color: tt.textSecondary)),
                            ),
                            Icon(Icons.chevron_right, color: tt.textTertiary),
                          ],
                        )
                      : Row(
                          children: [
                            PersonAvatar(name: tutorSirName(next.tuition), photo: photos[next.tuition.str('tutor_id')], radius: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (live ? tr('Class now') : tr('Next class')).toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                      color: live ? tt.success : tt.textTertiary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(studentClassName(next.tuition),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tt.textPrimary)),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      next.day == plan.today ? tr('Today') : dayLabel(next.day, short: false),
                                      _timeRange(next),
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, color: tt.textSecondary, fontFeatures: tabular),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _Chip(
                                  live ? tr('Now') : tr('in {t}', {'t': Raw(shortGap(_startOf(next, plan, now).difference(now)))}),
                                  background: live ? tt.successContainer : tt.primaryContainer,
                                  foreground: live ? tt.onSuccessContainer : tt.onPrimaryContainer,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  today.isEmpty
                                      ? tr('{n} this week', {'n': plan.total})
                                      : tr('{a} today · {b} this week', {'a': today.length, 'b': plan.total}),
                                  style: TextStyle(fontSize: 11, color: tt.textTertiary),
                                ),
                              ],
                            ),
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

/// Every class of the week from every tutor, Saturday first, with a warning
/// when two tutors' classes fall at the same time.
class StudentWeekScreen extends StatelessWidget {
  const StudentWeekScreen({super.key, required this.tuitions, required this.photos});
  final List<Json> tuitions;
  final Map<String, String?> photos;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final now = DateTime.now();
    final plan = buildWeekPlan(tuitions, now);
    final clashes = clashingClasses(plan);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Weekly routine'))),
      body: PageBody(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (clashes.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: tt.dangerContainer, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: tt.danger, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('Two of your classes are at the same time. Tell one of your tutors.'),
                      style: TextStyle(fontSize: 13, height: 1.4, color: tt.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          for (final day in weekOrder) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
              child: Row(
                children: [
                  Text(dayLabel(day, short: false),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: plan.isPastDay(day) ? tt.textSecondary : tt.textPrimary,
                      )),
                  if (day == plan.today) ...[
                    const SizedBox(width: 8),
                    _Chip(tr('Today'), background: tt.primaryContainer, foreground: tt.onPrimaryContainer),
                  ],
                ],
              ),
            ),
            if (plan.byDay[day]!.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(tr('Free'), style: TextStyle(fontSize: 13, color: tt.textTertiary)),
              )
            else
              for (final (i, c) in plan.byDay[day]!.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                _WeekRow(
                  item: c,
                  photo: photos[c.tuition.str('tutor_id')],
                  live: _isNow(c, plan, now),
                  clash: clashes.contains(c),
                ),
              ],
          ],
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.item, required this.photo, required this.live, required this.clash});
  final WeekClass item;
  final String? photo;
  final bool live;
  final bool clash;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final ink = item.past ? tt.textSecondary : tt.textPrimary;
    return Container(
      decoration: BoxDecoration(color: tt.card, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: tuitionColorOf(item.tuition.str('id')).withValues(alpha: item.past ? 0.35 : 1)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    PersonAvatar(name: tutorSirName(item.tuition), photo: photo, radius: 16),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(studentClassName(item.tuition),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink)),
                          Text(_timeRange(item), style: TextStyle(fontSize: 12, color: tt.textTertiary, fontFeatures: tabular)),
                        ],
                      ),
                    ),
                    if (clash)
                      _Chip(tr('Time clash'), background: tt.dangerContainer, foreground: tt.danger)
                    else if (live)
                      _Chip(tr('Now'), background: tt.successContainer, foreground: tt.onSuccessContainer)
                    else if (item.isNext)
                      _Chip(tr('Next'), background: tt.primaryContainer, foreground: tt.onPrimaryContainer)
                    else if (item.past)
                      Icon(Icons.check_rounded, size: 18, color: tt.textTertiary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.background, required this.foreground});
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
