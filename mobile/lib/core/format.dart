import 'package:intl/intl.dart';

final _dateTime = DateFormat('EEE d MMM, h:mm a');
final _date = DateFormat('EEE d MMM yyyy');
final _shortDate = DateFormat('d MMM');
final _time = DateFormat('h:mm a');

String fmtDateTime(DateTime? value) => value == null ? '—' : _dateTime.format(value.toLocal());
String fmtDate(DateTime? value) => value == null ? '—' : _date.format(value.toLocal());
String fmtShortDate(DateTime? value) => value == null ? '—' : _shortDate.format(value.toLocal());
String fmtTime(DateTime? value) => value == null ? '—' : _time.format(value.toLocal());

/// "in 2 h 5 min", "in 3 days" — coarse on purpose; the exam screen has the exact timer.
String relativeFromNow(Duration gap) {
  final mins = gap.inMinutes < 0 ? 0 : gap.inMinutes;
  if (mins < 1) return 'in under a minute';
  if (mins < 60) return 'in $mins min';
  final hours = mins ~/ 60;
  if (hours < 24) return 'in $hours h ${mins % 60} min';
  final days = hours ~/ 24;
  return 'in $days day${days == 1 ? '' : 's'}';
}

/// "3 min ago", "2 days ago".
String timeAgo(DateTime? value) {
  if (value == null) return '';
  final gap = DateTime.now().difference(value.toLocal());
  if (gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
  if (gap.inHours < 24) return '${gap.inHours} h ago';
  if (gap.inDays < 7) return '${gap.inDays} day${gap.inDays == 1 ? '' : 's'} ago';
  return fmtShortDate(value);
}

/// Countdown text: 01:23:45, or "2d 01:23:45".
String countdown(Duration left) {
  final total = left.isNegative ? 0 : left.inSeconds;
  final d = total ~/ 86400;
  String two(int n) => n.toString().padLeft(2, '0');
  final hms = '${two((total % 86400) ~/ 3600)}:${two((total % 3600) ~/ 60)}:${two(total % 60)}';
  return d > 0 ? '${d}d $hms' : hms;
}

/// "18:00" -> "6:00 PM".
String to12h(String? time) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(time ?? '');
  if (match == null) return time ?? '';
  final h = int.parse(match[1]!);
  return '${h % 12 == 0 ? 12 : h % 12}:${match[2]} ${h < 12 ? 'AM' : 'PM'}';
}

/// yyyy-MM-dd in local time; used to compare calendar days.
String dayKey(DateTime value) {
  final v = value.toLocal();
  return '${v.year.toString().padLeft(4, '0')}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
}

const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
String weekdayName(DateTime value) => weekdays[value.weekday - 1];
