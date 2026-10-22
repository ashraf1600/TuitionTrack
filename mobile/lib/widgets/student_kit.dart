import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/connect.dart' show HomeworkItem, tutorSirName;
import '../core/i18n.dart';
import '../core/json.dart';
import '../core/reminder_plan.dart' show nextClass, whenLabel;
import 'theme.dart';
import 'ui.dart';

/// Building blocks of the student screens: deadline chips, the "Today" panel,
/// the score ring and the score trend. Kept in one place so every student card
/// looks and reads the same way.

// ── Deadlines ────────────────────────────────────────────────────────────────

/// "25 min", "3 h", "2 d" — a short gap for chips.
String shortGap(Duration gap) {
  final mins = math.max(0, gap.inMinutes);
  if (mins < 1) return tr('<1 min');
  if (mins < 60) return tr('{n} min', {'n': mins});
  final hours = mins ~/ 60;
  if (hours < 48) return tr('{n} h', {'n': hours});
  return tr('{n} d', {'n': hours ~/ 24});
}

enum DeadlineKind { due, closes, opens }

/// "Due in 3 h", "Closes in 25 min", "Opens in 2 d", "Late". Turns red with less than two hours to go.
class DeadlineChip extends StatelessWidget {
  const DeadlineChip({super.key, required this.at, required this.now, this.kind = DeadlineKind.due});
  final DateTime at;
  final DateTime now;
  final DeadlineKind kind;

  @override
  Widget build(BuildContext context) {
    final left = at.difference(now);
    if (kind != DeadlineKind.opens && left.isNegative) {
      return Pill(tr('Late'), color: AppColors.danger, icon: Icons.error_outline_rounded);
    }
    final urgent = kind != DeadlineKind.opens && left < const Duration(hours: 2);
    final gap = shortGap(left);
    final label = switch (kind) {
      DeadlineKind.due => tr('Due in {t}', {'t': Raw(gap)}),
      DeadlineKind.closes => tr('Closes in {t}', {'t': Raw(gap)}),
      DeadlineKind.opens => tr('Opens in {t}', {'t': Raw(gap)}),
    };
    return Pill(
      label,
      color: urgent ? AppColors.danger : (kind == DeadlineKind.opens ? AppColors.primarySoft : AppColors.success),
      icon: urgent ? Icons.alarm_rounded : Icons.schedule_rounded,
    );
  }
}

// ── Today ────────────────────────────────────────────────────────────────────

/// The top of the student home: the next class, exams open right now (with a
/// Start button) and homework due within a day. Hidden when there is nothing.
class TodayPanel extends StatelessWidget {
  const TodayPanel({
    super.key,
    required this.tuitions,
    required this.exams,
    required this.homework,
    required this.now,
    required this.onStartExam,
    required this.onOpenHomework,
  });

  final List<Json> tuitions;
  final List<Json> exams;
  final List<HomeworkItem> homework;
  final DateTime now;
  final void Function(Json exam) onStartExam;
  final VoidCallback onOpenHomework;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final next = nextClass(tuitions, now);
    final openExams = exams.where((e) => !e.flag('has_submission') && e.flag('can_submit')).toList()
      ..sort((a, b) => (a.date('end_time') ?? now).compareTo(b.date('end_time') ?? now));
    final dueSoon = homework
        .where((h) => !h.isSubmitted && !h.isEvaluated && h.dueDate.difference(now) < const Duration(hours: 24))
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final nextIsSoon = next != null && next.at.difference(now) < const Duration(hours: 36);
    if (!nextIsSoon && openExams.isEmpty && dueSoon.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tt.primary.withValues(alpha: 0.22), tt.primary.withValues(alpha: 0.06)],
        ),
        border: Border.all(color: tt.primary.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.wb_sunny_outlined, size: 18, color: tt.primary),
              const SizedBox(width: 8),
              Text(tr('Today'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tt.textPrimary)),
            ],
          ),
          if (nextIsSoon) ...[
            gap12,
            _TodayRow(
              icon: Icons.event_available_rounded,
              color: AppColors.primarySoft,
              title: tutorSirName(next.tuition).isEmpty
                  ? tr('Next class')
                  : tr('Class with {tutor}', {'tutor': Raw(tutorSirName(next.tuition))}),
              subtitle: whenLabel(next.at, now),
              trailing: Pill(tr('in {t}', {'t': Raw(shortGap(next.at.difference(now)))}), color: AppColors.primarySoft),
            ),
          ],
          for (final exam in openExams.take(3)) ...[
            gap12,
            _TodayRow(
              icon: exam.str('category') == 'ASSIGNMENT' ? Icons.assignment_outlined : Icons.quiz_outlined,
              color: AppColors.success,
              title: exam.str('title'),
              subtitle: tutorSirName(exam),
              trailing: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.successDeep,
                  minimumSize: const Size(72, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: () => onStartExam(exam),
                child: Text(exam.str('category') == 'ASSIGNMENT' ? tr('Open') : tr('Start')),
              ),
            ),
          ],
          for (final hw in dueSoon.take(3)) ...[
            gap12,
            _TodayRow(
              icon: Icons.menu_book_outlined,
              color: AppColors.warning,
              title: hw.title,
              subtitle: hw.tutorDisplay,
              trailing: DeadlineChip(at: hw.dueDate, now: now),
              onTap: onOpenHomework,
            ),
          ],
        ],
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({required this.icon, required this.color, required this.title, required this.subtitle, required this.trailing, this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final row = Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: tonalContainer(context, color), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: tone(context, color)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tt.textPrimary)),
              if (subtitle.isNotEmpty)
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: tt.textSecondary)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        trailing,
      ],
    );
    if (onTap == null) return row;
    return InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: row);
  }
}

// ── Scores ───────────────────────────────────────────────────────────────────

/// A ring filled to [percent] with the percentage in the middle.
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.percent, this.size = 92});
  final double percent;
  final double size;

  static Color colorFor(double percent) =>
      percent >= 80 ? AppColors.success : (percent >= 50 ? AppColors.primarySoft : AppColors.warning);

  @override
  Widget build(BuildContext context) {
    final value = (percent / 100).clamp(0.0, 1.0).toDouble();
    final color = tone(context, colorFor(percent));
    return Semantics(
      label: tr('Score {p0} percent', {'p0': percent.round()}),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => CircularProgressIndicator(
                value: v,
                strokeWidth: size * 0.1,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
            Center(
              child: Text(
                '${localDigits('${percent.round()}')}%',
                style: TextStyle(fontSize: size * 0.24, fontWeight: FontWeight.w800, color: context.tt.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How the student's results have gone, oldest to newest, as a small line chart.
class ScoreTrend extends StatelessWidget {
  const ScoreTrend({super.key, required this.percents});
  final List<double> percents;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final last = percents.last;
    final change = percents.length > 1 ? last - percents[percents.length - 2] : 0.0;
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Your recent results'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tt.textSecondary)),
                const SizedBox(height: 2),
                Text('${localDigits('${last.round()}')}%', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: tt.textPrimary)),
                if (change.abs() >= 1)
                  Text(
                    change > 0
                        ? tr('▲ {p0}% from the last one', {'p0': change.round()})
                        : tr('▼ {p0}% from the last one', {'p0': change.abs().round()}),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tone(context, change > 0 ? AppColors.success : AppColors.warning)),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 150,
            height: 56,
            child: CustomPaint(painter: _TrendPainter(percents, tone(context, AppColors.primarySoft))),
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    Offset at(int i) => Offset(
          size.width * i / (values.length - 1),
          size.height - 4 - (size.height - 8) * (values[i].clamp(0, 100) / 100),
        );
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(at(values.length - 1), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.values != values || old.color != color;
}

/// A student's released results as percentages, oldest first (for [ScoreTrend]).
List<double> resultPercents(List<Json> exams) {
  final rows = <(DateTime, double)>[];
  for (final e in exams) {
    final result = e.obj('my_result');
    final total = e.number('total_marks');
    final obtained = result?.numberOrNull('obtained_marks');
    if (!e.flag('results_released') || obtained == null || total <= 0) continue;
    rows.add((e.date('end_time') ?? DateTime(2000), (obtained * 100 / total).toDouble()));
  }
  rows.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final r in rows) r.$2.clamp(0, 100).toDouble()];
}
