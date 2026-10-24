import 'package:flutter/material.dart';

import '../../core/connect.dart' show HomeworkItem;
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../widgets/charts.dart';
import '../../widgets/theme.dart';

int classNoOf(Json entry) => entry.integer('class_no', entry.integer('classNo'));

/// A cycle's classes in order, one entry per class number (missing ones filled in as not done).
List<Json> orderedClasses(Json cycle) {
  final total = cycle.integer('total_classes');
  final byNumber = {for (final c in cycle.maps('classes_data')) classNoOf(c): c};
  return [
    for (var n = 1; n <= total; n++) byNumber[n] ?? {'class_no': n, 'completed': false, 'date': null, 'topic': ''},
  ];
}

/// Read-only class progress with one tutor, as a student sees it: a ring of
/// classes done in the current cycle, then every class done by date, newest
/// first, as the tutor marks them. Subjects are not split out. The latest five
/// show; the rest are one tap away. No money here.
class ClassesDone extends StatefulWidget {
  const ClassesDone({super.key, required this.cycles, this.homework = const [], this.paymentDue = false});

  /// The current cycle of each of the tutor's tuitions this student is in.
  final List<Json> cycles;

  /// This tutor's homework; each piece shows under the class done on the day it was given.
  final List<HomeworkItem> homework;

  /// A cycle waits for payment (a reminder only).
  final bool paymentDue;

  @override
  State<ClassesDone> createState() => _ClassesDoneState();
}

class _ClassesDoneState extends State<ClassesDone> {
  static const _first = 5;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    var done = 0;
    var total = 0;
    final log = <Json>[];
    for (final cycle in widget.cycles) {
      done += cycle.integer('completed_classes');
      total += cycle.integer('total_classes');
      log.addAll(orderedClasses(cycle).where((c) => c.flag('completed')));
    }
    // Oldest first to number them 1, 2, 3…; shown newest first.
    log.sort((a, b) => (a.date('date') ?? DateTime(0)).compareTo(b.date('date') ?? DateTime(0)));
    final numbered = [for (final (i, c) in log.indexed) (i + 1, c)].reversed.toList();
    final shown = _all ? numbered : numbered.take(_first).toList();
    final givenOn = <String, List<HomeworkItem>>{};
    for (final hw in widget.homework) {
      final at = hw.createdAt;
      if (at != null) givenOn.putIfAbsent(_dayKey(at.toLocal()), () => []).add(hw);
    }
    final complete = widget.cycles.isNotEmpty && widget.cycles.every((c) => c.flag('is_complete'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ProgressRing(done: done, total: total, size: 56, thickness: 6),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('{p0} of {p1} classes', {'p0': done, 'p1': total}),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tt.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    widget.paymentDue ? tr('This cycle · Payment due') : tr('This cycle'),
                    style: TextStyle(fontSize: 13, color: widget.paymentDue ? tone(context, AppColors.warning) : tt.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (log.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(tr('No classes done yet in this cycle.'), style: TextStyle(fontSize: 13, color: tt.textSecondary)),
          )
        else ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: tt.border),
          for (final (n, c) in shown)
            _DoneClass(
              number: n,
              entry: c,
              homework: c.date('date') == null ? const [] : givenOn[_dayKey(c.date('date')!)] ?? const [],
            ),
          if (numbered.length > _first)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? tr('Show fewer') : tr('Show all {n} classes', {'n': numbered.length})),
              ),
            ),
        ],
        if (complete)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr('This cycle is complete. Your tutor will start the next one.'), style: TextStyle(fontSize: 13, color: tt.textSecondary)),
          ),
      ],
    );
  }
}

String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// "Thu, 22 Oct   Energy" — one class done, on the day the tutor marked it,
/// with any homework given that day.
class _DoneClass extends StatelessWidget {
  const _DoneClass({required this.number, required this.entry, this.homework = const []});
  final int number;
  final Json entry;
  final List<HomeworkItem> homework;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final topic = entry.str('topic');
    final date = entry.date('date');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tt.successContainer, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: 16, color: tt.onSuccessContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date == null ? tr('Class {n}', {'n': number}) : '${dayLabel(weekdayName(date))}, ${fmtShortDate(date)}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tt.textPrimary, fontFeatures: tabular),
                ),
                if (topic.isNotEmpty)
                  Text(topic, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: tt.textSecondary)),
                for (final hw in homework)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(Icons.menu_book_rounded, size: 14, color: tone(context, AppColors.warning)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tr('Homework: {title}', {'title': Raw(hw.title)}),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: tone(context, AppColors.warning)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Text(tr('Class {n}', {'n': number}), style: TextStyle(fontSize: 12, color: tt.textTertiary, fontFeatures: tabular)),
        ],
      ),
    );
  }
}
