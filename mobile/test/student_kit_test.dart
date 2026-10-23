// Student screen building blocks: short gaps, result percentages and the Today panel.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuitiontrack/core/connect.dart';
import 'package:tuitiontrack/widgets/student_kit.dart';
import 'package:tuitiontrack/widgets/theme.dart';

void main() {
  test('short gaps for chips', () {
    expect(shortGap(const Duration(seconds: 20)), '<1 min');
    expect(shortGap(const Duration(minutes: 25)), '25 min');
    expect(shortGap(const Duration(hours: 3, minutes: 10)), '3 h');
    expect(shortGap(const Duration(days: 3)), '3 d');
  });

  test('released results become percentages, oldest first', () {
    final percents = resultPercents([
      {'results_released': true, 'total_marks': 20, 'end_time': '2026-10-10T10:00:00Z', 'my_result': {'obtained_marks': 15}},
      {'results_released': true, 'total_marks': 50, 'end_time': '2026-10-01T10:00:00Z', 'my_result': {'obtained_marks': 25}},
      {'results_released': false, 'total_marks': 10, 'end_time': '2026-10-12T10:00:00Z', 'my_result': {'obtained_marks': 10}},
    ]);
    expect(percents, [50.0, 75.0]);
  });

  testWidgets('Today shows an open exam with a Start button and homework due soon', (tester) async {
    final now = DateTime.utc(2026, 10, 22, 10);
    Map<String, dynamic>? started;
    await tester.pumpWidget(MaterialApp(
      theme: ttTheme(isDark: true, isBangla: false),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TodayPanel(
            tuitions: const [],
            exams: [
              {'id': 'e1', 'title': 'Physics quiz', 'can_submit': true, 'has_submission': false, 'tutor_display_name': 'Ashraf Sir'},
            ],
            homework: [
              HomeworkItem(
                id: 'h1',
                title: 'Chapter 4',
                description: '',
                dueDate: now.add(const Duration(hours: 1)),
                tutorDisplay: 'Ashraf Sir',
                submittedUrl: '',
                feedback: '',
                isEvaluated: false,
                isSubmitted: false,
                studentId: 's1',
                studentName: 'Rafi',
              ),
            ],
            now: now,
            onStartExam: (exam) => started = exam,
            onOpenHomework: () {},
          ),
        ),
      ),
    ));
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Physics quiz'), findsOneWidget);
    expect(find.text('Chapter 4'), findsOneWidget);
    expect(find.text('Due in 1 h'), findsOneWidget);
    await tester.tap(find.text('Start'));
    expect(started?['id'], 'e1');
  });

  testWidgets('Today stays hidden when nothing is due', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ttTheme(isDark: true, isBangla: false),
      home: Scaffold(
        body: TodayPanel(
          tuitions: const [],
          exams: const [],
          homework: const [],
          now: DateTime.utc(2026, 10, 22),
          onStartExam: (_) {},
          onOpenHomework: () {},
        ),
      ),
    ));
    expect(find.text('Today'), findsNothing);
  });
}
