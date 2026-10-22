// Update check, phone reminders, "next class" and the Bangla option.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuitiontrack/core/app_info.dart';
import 'package:tuitiontrack/core/i18n.dart';
import 'package:tuitiontrack/core/reminder_plan.dart';
import 'package:tuitiontrack/core/strings_bn.dart';

// Saturday 10 October 2026, 5:00 PM.
final _now = DateTime(2026, 10, 10, 17);

Map<String, dynamic> _tuition({
  String id = 't1',
  String title = 'Physics',
  List<Map<String, dynamic>> routine = const [],
  List<Map<String, dynamic>> classes = const [],
  bool withCycle = true,
}) =>
    {
      'id': id,
      'title': title,
      'tutor_id': 'u1',
      'tutor_name': 'Ashraf Sir',
      'routine': routine,
      if (withCycle) 'active_cycle': <String, dynamic>{'id': 'c1', 'classes_data': classes},
    };

Map<String, dynamic> _slot(String day, String start, [String end = '']) =>
    {'day': day, 'start_time': start, if (end.isNotEmpty) 'end_time': end};

void main() {
  tearDown(() => setAppLanguage('en'));

  group('app version', () {
    test('appVersion matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(pubspec);
      expect(match?.group(1), appVersion);
    });

    test('compareVersions orders versions numerically', () {
      expect(compareVersions('1.1.0', '1.2.0'), lessThan(0));
      expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('2.0.0+5', '2.0.0'), 0);
      expect(compareVersions('', '0.0.1'), lessThan(0));
    });
  });

  group('tutor reminders', () {
    test('15 minutes before, and a Mark done question after each class', () {
      final reminders = tutorReminders([
        _tuition(routine: [_slot('Saturday', '18:00', '19:00')]),
      ], _now);
      final today = reminders.where((r) => r.key.contains('2026-10-10')).toList();
      expect(today.map((r) => r.at), [DateTime(2026, 10, 10, 17, 45), DateTime(2026, 10, 10, 19, 5)]);
      expect(today.first.markAction, isFalse);
      expect(today.last.markAction, isTrue);
      expect(today.last.payload, {'type': 'mark', 'tuition': 't1'});
      // Only the coming week is set; next Saturday is set on a later load.
      expect(reminders.where((r) => r.key.contains('2026-10-17')), isEmpty);
    });

    test('no "did it happen" question for a day already recorded', () {
      final reminders = tutorReminders([
        _tuition(
          routine: [_slot('Saturday', '18:00', '19:00')],
          classes: [
            {'class_no': 1, 'completed': true, 'date': '2026-10-10T12:00:00'},
          ],
        ),
      ], _now);
      final today = reminders.where((r) => r.key.contains('2026-10-10')).toList();
      expect(today.map((r) => r.markAction), [false]);
    });

    test('a tuition without a cycle and past times are skipped', () {
      expect(tutorReminders([_tuition(withCycle: false, routine: [_slot('Saturday', '18:00')])], _now), isEmpty);
      final reminders = tutorReminders([_tuition(routine: [_slot('Saturday', '09:00', '10:00')])], _now);
      expect(reminders.where((r) => r.key.contains('2026-10-10')), isEmpty);
    });
  });

  group('student reminders', () {
    test('classes 30 minutes ahead and homework 2 hours before it is due', () {
      final due = DateTime(2026, 10, 11, 20);
      final reminders = studentReminders(
        [_tuition(routine: [_slot('Sunday', '16:00')])],
        [
          {'id': 'h1', 'title': 'Chapter 4', 'due_date': due.toIso8601String()},
          {'id': 'h2', 'title': 'Done already', 'due_date': due.toIso8601String(), 'is_submitted': true},
          {'id': 'h3', 'title': 'Far away', 'due_date': DateTime(2026, 12, 1).toIso8601String()},
        ],
        _now,
      );
      final classes = reminders.where((r) => r.key.startsWith('class:')).toList();
      expect(classes.first.at, DateTime(2026, 10, 11, 15, 30));
      expect(classes.first.body, 'Class with Ashraf Sir starts in 30 minutes.');
      // Students never see the name the tutor gave the tuition.
      expect(classes.first.title, isNot(contains('Physics')));
      final homework = reminders.where((r) => r.key.startsWith('homework:')).toList();
      expect(homework.map((r) => r.key), ['homework:h1']);
      expect(homework.single.at, DateTime(2026, 10, 11, 18));
    });

    test('reminder ids are stable and inside their range', () {
      final id = reminderId('class:t1:2026-10-11T16:00:00.000');
      expect(id, reminderId('class:t1:2026-10-11T16:00:00.000'));
      expect(id, inInclusiveRange(100000, 189999));
      expect(reminderId('x', base: 200000), inInclusiveRange(200000, 289999));
    });
  });

  group('next class', () {
    test('picks the soonest class across tuitions', () {
      final next = nextClass([
        _tuition(id: 'a', title: 'Maths', routine: [_slot('Monday', '10:00')]),
        _tuition(id: 'b', title: 'Physics', routine: [_slot('Sunday', '16:00'), _slot('Saturday', '16:00')]),
      ], _now);
      expect(next?.at, DateTime(2026, 10, 11, 16));
      expect(next?.tuition['id'], 'b');
      expect(nextClass([_tuition()], _now), isNull);
    });

    test('labels today, tomorrow and later days', () {
      expect(whenLabel(DateTime(2026, 10, 10, 18), _now), 'Today 6:00 PM');
      expect(whenLabel(DateTime(2026, 10, 11, 9, 15), _now), 'Tomorrow 9:15 AM');
      expect(whenLabel(DateTime(2026, 10, 14, 18), _now), 'Wed 6:00 PM');
      setAppLanguage('bn');
      expect(whenLabel(DateTime(2026, 10, 11, 9, 15), _now), 'আগামীকাল সকাল ৯:১৫');
      expect(whenLabel(DateTime(2026, 10, 14, 18), _now), 'বুধ সন্ধ্যা ৬:০০');
    });
  });

  group('Bangla', () {
    test('tr translates, fills placeholders and uses Bangla digits', () {
      expect(tr('Class {n} marked done.', {'n': 3}), 'Class 3 marked done.');
      setAppLanguage('bn');
      expect(isBangla, isTrue);
      expect(tr('Class {n} marked done.', {'n': 12}), 'ক্লাস ১২ সম্পন্ন হয়েছে।');
      expect(tr('Not a key {n}', {'n': 2}), 'Not a key ২');
      expect(dayLabel('Saturday'), 'শনি');
      expect(dayLabel('Saturday', short: false), 'শনিবার');
    });

    test('codes and links keep their digits', () {
      setAppLanguage('bn');
      expect(tr('Invite code: {code}', {'code': const Raw('KX72')}), 'আমন্ত্রণ কোড: KX72');
      expect(localDigits('2/4'), '২/৪');
    });

    test('every translation keeps only placeholders its English text has', () {
      final placeholder = RegExp(r'\{\w+\}');
      for (final entry in bnStrings.entries) {
        final english = placeholder.allMatches(entry.key).map((m) => m[0]).toSet();
        final bangla = placeholder.allMatches(entry.value).map((m) => m[0]).toSet();
        expect(english.containsAll(bangla), isTrue, reason: entry.key);
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      }
    });
  });
}
