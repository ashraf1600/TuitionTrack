// The "This week" section: grouping, today, the next class and what is over.
import 'package:flutter_test/flutter_test.dart';
import 'package:tuitiontrack/core/format.dart';
import 'package:tuitiontrack/core/i18n.dart';
import 'package:tuitiontrack/core/week_plan.dart';

// Thursday 15 October 2026, 5:00 PM.
final _thu5pm = DateTime(2026, 10, 15, 17);

Map<String, dynamic> _tuition(String id, List<(String, String, String)> slots) => {
      'id': id,
      'title': id,
      'routine': [
        for (final (day, start, end) in slots) {'day': day, 'start_time': start, if (end.isNotEmpty) 'end_time': end},
      ],
    };

void main() {
  tearDown(() => setAppLanguage('en'));

  test('groups by day, Saturday first, sorted by time', () {
    final plan = buildWeekPlan([
      _tuition('a', [('Thursday', '20:00', '21:00'), ('saturday', '09:00', '')]),
      _tuition('b', [('Thursday', '08:00', '09:30'), ('FRI', '18:00', '19:30')]),
    ], _thu5pm);
    expect(plan.today, 'Thursday');
    expect(plan.total, 4);
    expect(plan.byDay['Thursday']!.map((c) => c.start), ['08:00', '20:00']);
    expect(plan.byDay['Saturday']!.single.tuition['id'], 'a');
    expect(plan.byDay['Friday']!.single.start, '18:00');
  });

  test('earlier days and finished classes today are past; the next one is marked', () {
    final plan = buildWeekPlan([
      _tuition('a', [('Saturday', '09:00', ''), ('Thursday', '08:00', '09:30'), ('Thursday', '16:30', '17:30'), ('Thursday', '20:00', '')]),
    ], _thu5pm);
    final today = plan.byDay['Thursday']!;
    expect(plan.byDay['Saturday']!.single.past, isTrue);
    expect(today.map((c) => c.past), [true, false, false]);
    // A class going on right now (16:30–17:30) is the next one, not the 20:00.
    expect(today.map((c) => c.isNext), [false, true, false]);
    expect(plan.next?.start, '16:30');
  });

  test('the next class can be on a later day', () {
    final plan = buildWeekPlan([
      _tuition('a', [('Thursday', '08:00', '09:00'), ('Friday', '09:00', '')]),
    ], _thu5pm);
    expect(plan.next?.day, 'Friday');
  });

  test('today and upcoming by default; the whole week on request', () {
    final plan = buildWeekPlan([
      _tuition('a', [('Saturday', '09:00', ''), ('Tuesday', '15:00', ''), ('Thursday', '18:00', ''), ('Friday', '09:00', '')]),
    ], _thu5pm);
    expect(plan.daysToShow(whole: false), ['Thursday', 'Friday']);
    expect(plan.daysToShow(whole: true), ['Saturday', 'Tuesday', 'Thursday', 'Friday']);
    expect(plan.pastDaysWithClasses, ['Saturday', 'Tuesday']);
    expect(plan.pastDayClasses, 2);
    expect(plan.isBusy, isFalse);
  });

  test('15 classes or more is a busy week; no classes is empty', () {
    final busy = buildWeekPlan([
      for (var i = 0; i < 15; i++) _tuition('t$i', [('Sunday', '${10 + i % 8}:00', '')]),
    ], _thu5pm);
    expect(busy.isBusy, isTrue);
    expect(buildWeekPlan([_tuition('a', [])], _thu5pm).isEmpty, isTrue);
  });

  test('Bangla times say the part of the day', () {
    expect(to12h('18:00'), '6:00 PM');
    setAppLanguage('bn');
    expect(to12h('18:00'), 'সন্ধ্যা ৬:০০');
    expect(to12h('19:30'), 'রাত ৭:৩০');
    expect(to12h('09:00'), 'সকাল ৯:০০');
    expect(to12h('13:15'), 'দুপুর ১:১৫');
    expect(to12h('16:00'), 'বিকাল ৪:০০');
    expect(to12h('05:00'), 'ভোর ৫:০০');
  });
}
