import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart' show HomeworkItem, tutorSirName;
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/reminder_plan.dart' show nextClass, whenLabel;
import '../../core/session.dart';
import '../../widgets/kit.dart';
import '../../widgets/student_kit.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import 'student_lists.dart';

/// Which tab of the student home to open, and which part of it.
enum StudentTab { home, tutors, tests, homework }

/// The student's home: what matters now on top, then the week, what is due,
/// how each subject is going and the latest result.
class StudentTodayView extends StatelessWidget {
  const StudentTodayView({
    super.key,
    required this.tutors,
    required this.tuitions,
    required this.connections,
    required this.exams,
    required this.homework,
    required this.reload,
    required this.onOpenTab,
    required this.onOpenTutor,
  });

  final List<Json> tutors;
  final List<Json> tuitions;
  final List<Json> connections;
  final List<Json> exams;
  final List<HomeworkItem> homework;
  final Future<void> Function() reload;
  final void Function(StudentTab tab, {bool results}) onOpenTab;
  final void Function(String tutorId, String name) onOpenTutor;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final now = session.api.serverNow;
    final pendingRequests = connections.where((c) => c.str('status') == 'PENDING').toList();

    final openExams = exams.where((e) => !e.flag('has_submission') && e.flag('can_submit')).toList()
      ..sort((a, b) => (a.date('end_time') ?? now).compareTo(b.date('end_time') ?? now));
    final upcomingExams = exams
        .where((e) => !e.flag('has_submission') && !e.flag('can_submit') && (e.date('start_time')?.isAfter(now) ?? false))
        .toList();
    final todo = homework.where((h) => !h.isSubmitted && !h.isEvaluated).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final percents = resultPercents(exams);
    final recent = percents.length > 5 ? percents.sublist(percents.length - 5) : percents;
    final average = recent.isEmpty ? null : recent.reduce((a, b) => a + b) / recent.length;

    final blocks = <Widget>[
      GreetingHeader(name: session.displayName, now: now.toLocal(), subtitle: _summary(openExams.length, todo, now)),
      if (pendingRequests.isNotEmpty) ...[
        Banner2(
          pendingRequests.length == 1
              ? tr('Your request to {p0} is waiting for an answer.', {'p0': _requestName(pendingRequests.first)})
              : tr('{p0} requests are waiting for an answer.', {'p0': pendingRequests.length}),
          icon: Icons.hourglass_top_rounded,
          color: AppColors.warning,
        ),
        gap16,
      ],
      _hero(context, now, openExams, todo),
      gap12,
      TileRow(children: [
        StatTile(
          icon: Icons.menu_book_rounded,
          value: localDigits('${todo.length}'),
          label: tr('Homework to do'),
          accent: todo.isEmpty ? AppColors.success : AppColors.warning,
          onTap: () => onOpenTab(StudentTab.homework),
        ),
        StatTile(
          icon: Icons.quiz_rounded,
          value: localDigits('${openExams.length + upcomingExams.length}'),
          label: tr('Tests ahead'),
          accent: AppColors.primarySoft,
          onTap: () => onOpenTab(StudentTab.tests),
        ),
        StatTile(
          icon: Icons.insights_rounded,
          value: average == null ? '—' : '${localDigits('${average.round()}')}%',
          label: tr('Average score'),
          accent: AppColors.success,
          onTap: () => onOpenTab(StudentTab.tests, results: true),
        ),
      ]),
      if (tuitions.isNotEmpty) ...[
        SectionHeader(tr('This week')),
        WeekSchedule(tuitions: tuitions, now: now.toLocal(), onOpenTutor: onOpenTutor),
      ],
      if (todo.isNotEmpty) ...[
        SectionHeader(tr('Due next'), count: todo.length, onAction: () => onOpenTab(StudentTab.homework)),
        RowGroup(children: [
          for (final hw in todo.take(3))
            KitRow(
              icon: Icons.menu_book_rounded,
              accent: hw.dueDate.isBefore(now) ? AppColors.danger : AppColors.warning,
              title: hw.title,
              subtitle: [hw.tutorDisplay, fmtDateTime(hw.dueDate)].where((s) => s.isNotEmpty).join(' · '),
              trailing: DeadlineChip(at: hw.dueDate, now: now),
              onTap: () => onOpenTab(StudentTab.homework),
            ),
        ]),
      ],
      if (tuitions.isNotEmpty) ...[
        SectionHeader(tr('Your subjects'), actionLabel: tr('Tutors'), onAction: () => onOpenTab(StudentTab.tutors)),
        RowGroup(children: [for (final t in tuitions) _SubjectRow(tuition: t, onOpenTutor: onOpenTutor)]),
      ],
      if (percents.isNotEmpty) ...[
        SectionHeader(tr('Latest result'), onAction: () => onOpenTab(StudentTab.tests, results: true)),
        _LatestResult(exams: exams, percents: percents),
      ],
      if (tutors.isEmpty && tuitions.isEmpty) ...[
        gap24,
        EmptyState(
          icon: Icons.key_rounded,
          title: tr('Connect with your tutor'),
          message: tr('Enter the invite code your tutor gave you. Your classes, tests and homework then appear here.'),
          action: FilledButton.icon(
            onPressed: () => onOpenTab(StudentTab.tutors),
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('Add a tutor')),
          ),
        ),
      ],
    ];
    return PageBody(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: staggered(context, blocks));
  }

  /// "2 things due today" style line under the greeting.
  String _summary(int openExams, List<HomeworkItem> todo, DateTime now) {
    final dueToday = todo.where((h) => h.dueDate.difference(now) < const Duration(hours: 24)).length;
    if (openExams > 0) return openExams == 1 ? tr('A test is open right now.') : tr('{n} tests are open right now.', {'n': openExams});
    if (dueToday > 0) return dueToday == 1 ? tr('1 homework is due within a day.') : tr('{n} homework are due within a day.', {'n': dueToday});
    if (todo.isEmpty) return tr("You're all caught up.");
    return tr('{n} homework to do this week.', {'n': todo.length});
  }

  Widget _hero(BuildContext context, DateTime now, List<Json> openExams, List<HomeworkItem> todo) {
    if (openExams.isNotEmpty) {
      final exam = openExams.first;
      final isAssignment = exam.str('category') == 'ASSIGNMENT';
      final minutes = exam.integer('duration_minutes');
      final end = exam.date('end_time') ?? now;
      return HeroCard(
        eyebrow: isAssignment ? tr('Assignment open') : tr('Live now'),
        live: !isAssignment,
        icon: isAssignment ? Icons.assignment_rounded : Icons.timer_rounded,
        accent: AppColors.success,
        title: exam.str('title'),
        subtitle: tutorSirName(exam),
        meta: [
          DeadlineChip(at: end, now: now, kind: isAssignment ? DeadlineKind.due : DeadlineKind.closes),
          if (minutes > 0 && !isAssignment) Pill(tr('{p0} min', {'p0': minutes}), icon: Icons.timer_outlined),
          Pill(tr('{p0} marks', {'p0': trimNumber(exam.number('total_marks'))}), icon: Icons.star_outline_rounded),
        ],
        action: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.successDeep, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(50)),
          onPressed: () => takeExam(context, exam, reload),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(isAssignment ? tr('Open assignment') : tr('Start now')),
        ),
      );
    }
    final next = nextClass(tuitions, now);
    if (next != null && next.at.difference(now) < const Duration(hours: 36)) {
      final subject = next.tuition.str('subject');
      final tutor = tutorSirName(next.tuition);
      return HeroCard(
        eyebrow: tr('Next class'),
        icon: Icons.event_available_rounded,
        accent: AppColors.primary,
        title: subject.isEmpty ? tr('Class') : subject,
        subtitle: tutor.isEmpty ? null : tr('with {tutor}', {'tutor': Raw(tutor)}),
        meta: [
          Pill(whenLabel(next.at.toLocal(), now.toLocal()), icon: Icons.schedule_rounded, color: AppColors.primarySoft),
          Pill(tr('in {t}', {'t': Raw(shortGap(next.at.difference(now)))}), color: AppColors.primarySoft),
        ],
        onTap: () => onOpenTutor(next.tuition.str('tutor_id'), tutor),
      );
    }
    if (todo.isNotEmpty && todo.first.dueDate.difference(now) < const Duration(hours: 48)) {
      final hw = todo.first;
      return HeroCard(
        eyebrow: hw.dueDate.isBefore(now) ? tr('Overdue') : tr('Due soon'),
        icon: Icons.menu_book_rounded,
        accent: hw.dueDate.isBefore(now) ? AppColors.danger : AppColors.warning,
        title: hw.title,
        subtitle: hw.tutorDisplay,
        meta: [DeadlineChip(at: hw.dueDate, now: now)],
        action: OutlinedButton(onPressed: () => onOpenTab(StudentTab.homework), child: Text(tr('Open homework'))),
      );
    }
    return HeroCard(
      eyebrow: tr('All caught up'),
      icon: Icons.task_alt_rounded,
      accent: AppColors.success,
      title: tr('Nothing due right now'),
      subtitle: tr('New tests and homework from your tutors will show up here.'),
    );
  }

  static String _requestName(Json c) =>
      c.str('tutor_display_name').isNotEmpty ? c.str('tutor_display_name') : c.str('tutor_name');
}

// ── Week ─────────────────────────────────────────────────────────────────────

/// Seven days from today; tap a day to see its classes.
class WeekSchedule extends StatefulWidget {
  const WeekSchedule({super.key, required this.tuitions, required this.now, required this.onOpenTutor});
  final List<Json> tuitions;
  final DateTime now;
  final void Function(String tutorId, String name) onOpenTutor;

  @override
  State<WeekSchedule> createState() => _WeekScheduleState();
}

class _WeekScheduleState extends State<WeekSchedule> {
  int _day = 0;

  /// The classes on [day]: (start, end, tuition), earliest first.
  List<(DateTime, DateTime, Json)> _classesOn(DateTime day) {
    final out = <(DateTime, DateTime, Json)>[];
    for (final t in widget.tuitions) {
      for (final slot in slotsOn(t.maps('routine'), day)) {
        final start = minutesOf(slotStart(slot));
        final endRaw = slot['end_time'];
        final end = endRaw == null ? start + 60 : minutesOf('$endRaw');
        if (start >= 24 * 60) continue;
        out.add((day.add(Duration(minutes: start)), day.add(Duration(minutes: end >= 24 * 60 ? start + 60 : end)), t));
      }
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final days = [for (var i = 0; i < 7; i++) today.add(Duration(days: i))];
    final selected = days[_day];
    final classes = _classesOn(selected);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (i, day) in days.indexed)
                Expanded(
                  child: _DayChip(
                    day: day,
                    selected: i == _day,
                    today: i == 0,
                    hasClass: _classesOn(day).isNotEmpty,
                    onTap: () => setState(() => _day = i),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: classes.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      _day == 0 ? tr('No classes today.') : tr('No classes on {day}.', {'day': Raw(shortWeekday(selected))}),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: tt.textSecondary, fontSize: 14),
                    ),
                  )
                : Column(
                    children: [
                      for (final (start, end, tuition) in classes)
                        _ClassRow(
                          start: start,
                          end: end,
                          tuition: tuition,
                          now: widget.now,
                          onTap: () => widget.onOpenTutor(tuition.str('tutor_id'), tutorSirName(tuition)),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, required this.selected, required this.today, required this.hasClass, required this.onTap});
  final DateTime day;
  final bool selected;
  final bool today;
  final bool hasClass;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final fg = selected ? tt.onPrimary : (today ? tt.primary : tt.textPrimary);
    return Semantics(
      selected: selected,
      button: true,
      label: longDate(day),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? tt.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Text(shortWeekday(day),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? tt.onPrimary : tt.textTertiary)),
              const SizedBox(height: 4),
              Text(localDigits('${day.day}'),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg, fontFeatures: tabular)),
              const SizedBox(height: 4),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasClass ? (selected ? tt.onPrimary : tt.primary) : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassRow extends StatelessWidget {
  const _ClassRow({required this.start, required this.end, required this.tuition, required this.now, required this.onTap});
  final DateTime start;
  final DateTime end;
  final Json tuition;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final subject = tuition.str('subject').isEmpty ? tr('Class') : tuition.str('subject');
    final live = !now.isBefore(start) && now.isBefore(end);
    final over = !now.isBefore(end);
    final soon = !live && !over && start.difference(now) < const Duration(hours: 12);
    return KitRow(
      dense: true,
      icon: Icons.class_outlined,
      accent: live ? AppColors.success : AppColors.primarySoft,
      title: subject,
      subtitle: '${fmtTime(start)} – ${fmtTime(end)} · ${tutorSirName(tuition)}',
      trailing: live
          ? Pill(tr('Now'), color: AppColors.success, icon: Icons.circle)
          : over
              ? Icon(Icons.check_rounded, size: 18, color: tt.textTertiary)
              : soon
                  ? Pill(tr('in {t}', {'t': Raw(shortGap(start.difference(now)))}), color: AppColors.primarySoft)
                  : null,
      onTap: onTap,
    );
  }
}

// ── Subjects ─────────────────────────────────────────────────────────────────

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({required this.tuition, required this.onOpenTutor});
  final Json tuition;
  final void Function(String tutorId, String name) onOpenTutor;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final subject = tuition.str('subject').isEmpty ? tr('Class') : tuition.str('subject');
    final cycle = tuition.obj('active_cycle');
    final done = cycle?.integer('completed_classes') ?? 0;
    final total = cycle?.integer('total_classes') ?? tuition.integer('cycle_length');
    final unpaid = tuition.maps('pending_payments').isNotEmpty;
    final tutor = tutorSirName(tuition);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onOpenTutor(tuition.str('tutor_id'), tutor),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: [
            InitialTile(subject),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tt.textPrimary)),
                      ),
                      Text(
                        '${localDigits('$done')}/${localDigits('$total')}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tt.textPrimary, fontFeatures: tabular),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (tutor.isNotEmpty) tutor,
                      tr('Cycle {n}', {'n': cycle?.integer('cycle_number') ?? 1}),
                      if (unpaid) tr('Payment due'),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: unpaid ? tone(context, AppColors.warning) : tt.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  GrowBar(value: total == 0 ? 0 : done / total, height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Latest result ────────────────────────────────────────────────────────────

class _LatestResult extends StatelessWidget {
  const _LatestResult({required this.exams, required this.percents});
  final List<Json> exams;
  final List<double> percents;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final released = exams.where((e) => e.flag('results_released') && e.obj('my_result')?.numberOrNull('obtained_marks') != null).toList()
      ..sort((a, b) => (b.date('end_time') ?? DateTime(2000)).compareTo(a.date('end_time') ?? DateTime(2000)));
    if (released.isEmpty) return const SizedBox.shrink();
    final exam = released.first;
    final got = exam.obj('my_result')!.number('obtained_marks');
    final total = exam.number('total_marks');
    final percent = total <= 0 ? 0.0 : (got * 100 / total).toDouble();
    final change = percents.length > 1 ? percents.last - percents[percents.length - 2] : 0.0;
    return AppCard(
      onTap: () => openExamResult(context, exam),
      child: Row(
        children: [
          ScoreRing(percent: percent, size: 72),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exam.str('title'), maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tt.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  '${trimNumber(got)} / ${trimNumber(total)} · ${tutorSirName(exam)}',
                  style: TextStyle(fontSize: 13, color: tt.textSecondary),
                ),
                if (change.abs() >= 1) ...[
                  const SizedBox(height: 6),
                  TrendChip(change: change),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: tt.textTertiary),
        ],
      ),
    );
  }
}
