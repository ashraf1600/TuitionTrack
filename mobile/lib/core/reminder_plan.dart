import 'format.dart';
import 'i18n.dart';
import 'json.dart';

/// One phone notification to show at a set time.
class PlannedReminder {
  const PlannedReminder({
    required this.key,
    required this.at,
    required this.title,
    required this.body,
    this.payload = const {},
    this.markAction = false,
  });

  /// Stable name, e.g. `after:t1:2026-10-11T18:00` (the id is derived from it).
  final String key;
  final DateTime at;
  final String title;
  final String body;
  final Map<String, Object?> payload;

  /// Adds a "Mark done" button that records the class from the notification.
  final bool markAction;
}

/// How far ahead reminders are set. They are set again every time the app
/// loads its data, so a week is plenty and keeps the phone's list short.
const reminderDays = 7;

/// Each weekly class time of [routine] in the next [reminderDays] days, as
/// (start, end). A slot without an end time is taken to last an hour.
List<(DateTime, DateTime)> upcomingSlots(List<Json> routine, DateTime now) {
  final out = <(DateTime, DateTime)>[];
  for (var ahead = 0; ahead < reminderDays; ahead++) {
    final day = DateTime(now.year, now.month, now.day + ahead);
    for (final slot in slotsOn(routine, day)) {
      final startMinutes = minutesOf(slotStart(slot));
      if (startMinutes >= 24 * 60) continue;
      final start = day.add(Duration(minutes: startMinutes));
      final endText = slot.str('end_time');
      final endMinutes = endText.isEmpty ? startMinutes + 60 : minutesOf(endText);
      final end = day.add(Duration(minutes: endMinutes > startMinutes && endMinutes < 24 * 60 ? endMinutes : startMinutes + 60));
      out.add((start, end));
    }
  }
  return out;
}

/// True when the tuition's current cycle already has a class dated on [day].
bool classRecordedOn(Json tuition, DateTime day) {
  final cycle = tuition.obj('active_cycle');
  if (cycle == null) return false;
  final key = dayKey(day);
  return cycle.maps('classes_data').any((c) => c.flag('completed') && c.date('date') != null && dayKey(c.date('date')!) == key);
}

/// Tutor: a heads-up 15 minutes before each class, and after it a question
/// with a "Mark done" button (skipped for a day already recorded).
List<PlannedReminder> tutorReminders(List<Json> tuitions, DateTime now) {
  final out = <PlannedReminder>[];
  for (final tuition in tuitions) {
    if (tuition.obj('active_cycle') == null) continue;
    final id = tuition.str('id');
    final title = tuition.str('title');
    for (final (start, end) in upcomingSlots(tuition.maps('routine'), now)) {
      final before = start.subtract(const Duration(minutes: 15));
      if (before.isAfter(now)) {
        out.add(PlannedReminder(
          key: 'before:$id:${start.toIso8601String()}',
          at: before,
          title: tr('{title} at {time}', {'title': title, 'time': to12h(_hhmm(start))}),
          body: tr('Class starts in 15 minutes.'),
          payload: {'type': 'tuition', 'tuition': id},
        ));
      }
      final after = end.add(const Duration(minutes: 5));
      if (after.isAfter(now) && !classRecordedOn(tuition, start)) {
        out.add(PlannedReminder(
          key: 'after:$id:${start.toIso8601String()}',
          at: after,
          title: tr('Did {title} happen today?', {'title': title}),
          body: tr('Tap Mark done to record the class.'),
          payload: {'type': 'mark', 'tuition': id},
          markAction: true,
        ));
      }
    }
  }
  return out;
}

/// Student: each class 30 minutes ahead, and homework two hours before it is due.
List<PlannedReminder> studentReminders(List<Json> tuitions, List<Json> homework, DateTime now) {
  final out = <PlannedReminder>[];
  for (final tuition in tuitions) {
    final id = tuition.str('id');
    for (final (start, _) in upcomingSlots(tuition.maps('routine'), now)) {
      final at = start.subtract(const Duration(minutes: 30));
      if (!at.isAfter(now)) continue;
      out.add(PlannedReminder(
        key: 'class:$id:${start.toIso8601String()}',
        at: at,
        title: tr('{title} at {time}', {'title': tuition.str('title'), 'time': to12h(_hhmm(start))}),
        body: tuition.str('tutor_name').isEmpty
            ? tr('Class starts in 30 minutes.')
            : tr('Class with {tutor} starts in 30 minutes.', {'tutor': tuition.str('tutor_name')}),
        payload: {'type': 'tutor', 'tutor': tuition.str('tutor_id')},
      ));
    }
  }
  for (final hw in homework) {
    if (hw.flag('is_evaluated') || hw.flag('is_submitted') || hw.flag('pending_sync')) continue;
    final due = hw.date('due_date')?.toLocal();
    if (due == null) continue;
    final at = due.subtract(const Duration(hours: 2));
    if (!at.isAfter(now) || at.isAfter(now.add(const Duration(days: reminderDays)))) continue;
    out.add(PlannedReminder(
      key: 'homework:${hw.str('id')}',
      at: at,
      title: tr('Homework due in 2 hours'),
      body: hw.str('title'),
      payload: {'type': 'homework'},
    ));
  }
  return out;
}

String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// A stable notification id in [base, base + 89999] for a reminder key.
int reminderId(String key, {int base = 100000}) {
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return base + hash % 90000;
}

/// The next class start (after [now]) across [tuitions], with its tuition.
({DateTime at, Json tuition})? nextClass(List<Json> tuitions, DateTime now) {
  ({DateTime at, Json tuition})? best;
  for (final tuition in tuitions) {
    for (final (start, _) in upcomingSlots(tuition.maps('routine'), now)) {
      if (!start.isAfter(now)) continue;
      if (best == null || start.isBefore(best.at)) best = (at: start, tuition: tuition);
    }
  }
  return best;
}

/// "Today 6:00 PM", "Tomorrow 9:15 AM" or "Wed 6:00 PM" (in the app language).
String whenLabel(DateTime at, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = day.difference(today).inDays;
  final time = to12h(_hhmm(at));
  if (days == 0) return tr('Today {time}', {'time': time});
  if (days == 1) return tr('Tomorrow {time}', {'time': time});
  return '${dayLabel(weekdayName(at))} $time';
}
