import 'format.dart';
import 'json.dart';

/// The Bangladesh week, as the "This week" section shows it.
const weekOrder = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

/// A week this busy folds its past days into one summary row.
const busyWeekClasses = 15;

/// One weekly class time of a tuition, placed in the current week.
class WeekClass {
  const WeekClass({
    required this.tuition,
    required this.day,
    required this.start,
    required this.end,
    required this.past,
    this.isNext = false,
  });

  final Json tuition;

  /// English weekday name, e.g. "Saturday".
  final String day;

  /// "18:00"; [end] is empty when the routine has no end time.
  final String start;
  final String end;

  /// Already over: an earlier day, or earlier today and finished.
  final bool past;

  /// The first class that is not over yet (it may be going on now).
  final bool isNext;

  WeekClass markNext() => WeekClass(tuition: tuition, day: day, start: start, end: end, past: past, isNext: true);
}

/// Every class of the week, grouped by day (Saturday first), with today,
/// the next class and what is already over worked out.
class WeekPlan {
  WeekPlan._(this.today, this.byDay);

  /// English name of today, e.g. "Thursday".
  final String today;
  final Map<String, List<WeekClass>> byDay;

  int get todayIndex => weekOrder.indexOf(today);
  int get total => byDay.values.fold(0, (sum, list) => sum + list.length);
  bool get isEmpty => total == 0;
  bool get isBusy => total >= busyWeekClasses;

  bool isPastDay(String day) => weekOrder.indexOf(day) < todayIndex;

  /// Days before today that had classes, in week order.
  List<String> get pastDaysWithClasses => [for (final d in weekOrder) if (isPastDay(d) && byDay[d]!.isNotEmpty) d];
  int get pastDayClasses => pastDaysWithClasses.fold(0, (sum, d) => sum + byDay[d]!.length);

  /// Days to list, in week order: every day with classes when [whole],
  /// otherwise only today and the days after it.
  List<String> daysToShow({required bool whole}) => [
        for (final d in weekOrder)
          if (byDay[d]!.isNotEmpty && (whole || !isPastDay(d))) d,
      ];

  WeekClass? get next {
    for (final d in weekOrder) {
      for (final c in byDay[d]!) {
        if (c.isNext) return c;
      }
    }
    return null;
  }
}

/// Builds the week from the tuitions' routines, as of [now].
WeekPlan buildWeekPlan(List<Json> tuitions, DateTime now) {
  final today = weekdayName(now);
  final todayIndex = weekOrder.indexOf(today);
  final nowMinutes = now.hour * 60 + now.minute;
  final byDay = {for (final d in weekOrder) d: <WeekClass>[]};
  for (final tuition in tuitions) {
    for (final slot in tuition.maps('routine')) {
      final day = normalizeDay('${slot['day'] ?? slot['day_of_week'] ?? ''}');
      if (day.isEmpty) continue;
      final start = slotStart(slot);
      final end = '${slot['end_time'] ?? ''}';
      final index = weekOrder.indexOf(day);
      final startMinutes = minutesOf(start);
      final endMinutes = end.isEmpty ? startMinutes + 60 : minutesOf(end);
      final past = index < todayIndex || (index == todayIndex && endMinutes <= nowMinutes);
      byDay[day]!.add(WeekClass(tuition: tuition, day: day, start: start, end: end, past: past));
    }
  }
  for (final list in byDay.values) {
    list.sort((a, b) => minutesOf(a.start).compareTo(minutesOf(b.start)));
  }
  // The first class that is not over yet, from today on.
  outer:
  for (final d in weekOrder.skip(todayIndex)) {
    final list = byDay[d]!;
    for (var i = 0; i < list.length; i++) {
      if (!list[i].past) {
        list[i] = list[i].markNext();
        break outer;
      }
    }
  }
  return WeekPlan._(today, byDay);
}
