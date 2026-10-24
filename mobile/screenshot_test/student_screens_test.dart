// Screenshots of the student side (see harness.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuitiontrack/core/app_keys.dart';
import 'package:tuitiontrack/main.dart';
import 'package:tuitiontrack/core/chat.dart';
import 'package:tuitiontrack/screens/common/account_screen.dart';
import 'package:tuitiontrack/screens/common/chat_screen.dart';
import 'package:tuitiontrack/screens/common/chats_screen.dart';
import 'package:tuitiontrack/screens/common/notifications.dart';
import 'package:tuitiontrack/screens/student/exam_result_screen.dart';
import 'package:tuitiontrack/screens/student/tutor_detail_screen.dart';

import 'harness.dart';

void main() {
  final fixtures = Fixtures('student');

  setUpAll(loadAppFonts);

  Future<void> openApp(WidgetTester tester, {Size size = phone, bool light = false, String language = 'en', bool signedIn = true}) async {
    usePhone(tester, size: size);
    final session = (await tester.runAsync(() => demoSession(fixtures, light: light, language: language, signedIn: signedIn)))!;
    await tester.pumpWidget(TuitionTrackApp(session: session));
    await settle(tester);
  }

  Future<void> push(WidgetTester tester, Widget screen) async {
    rootNavigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => screen));
    await settle(tester);
  }

  Future<void> tapTab(WidgetTester tester, int index) async {
    final bar = find.byType(NavigationBar);
    if (bar.evaluate().isEmpty) return;
    final destinations = find.descendant(of: bar, matching: find.byType(NavigationDestination));
    await tester.tap(destinations.at(index));
    await settle(tester);
  }

  testWidgets('home', (tester) async {
    await openApp(tester);
    await shoot(tester, 'student_01_home');
  });

  testWidgets('home, whole page', (tester) async {
    await openApp(tester, size: tallPhone);
    await shoot(tester, 'student_02_home_full');
  });

  testWidgets('second tab', (tester) async {
    await openApp(tester, size: tallPhone);
    await tapTab(tester, 1);
    await shoot(tester, 'student_03_tab2');
  });

  testWidgets('third tab', (tester) async {
    await openApp(tester, size: tallPhone);
    await tapTab(tester, 2);
    await shoot(tester, 'student_04_tab3');
  });

  testWidgets('fourth tab', (tester) async {
    await openApp(tester, size: tallPhone);
    final bar = find.byType(NavigationBar);
    if (bar.evaluate().isNotEmpty &&
        find.descendant(of: bar, matching: find.byType(NavigationDestination)).evaluate().length > 3) {
      await tapTab(tester, 3);
      await shoot(tester, 'student_05_tab4');
    }
  });

  testWidgets('tests, results', (tester) async {
    await openApp(tester, size: tallPhone);
    await tapTab(tester, 1);
    final results = find.text('Results');
    if (results.evaluate().isNotEmpty) {
      await tester.tap(results.first);
      await settle(tester);
    }
    await shoot(tester, 'student_05b_results');
  });

  testWidgets('tutor detail', (tester) async {
    await openApp(tester, size: tallPhone);
    await push(tester, TutorDetailScreen(tutorId: fixtures.meta['tutor_detail_id'] as String, title: 'Ashraful Sir'));
    await shoot(tester, 'student_06_tutor_detail');
  });

  testWidgets('exam result', (tester) async {
    await openApp(tester, size: tallPhone);
    await push(tester, ExamResultScreen(examId: fixtures.meta['result_exam_id'] as String, title: 'Monthly Test: Kinematics'));
    await shoot(tester, 'student_07_exam_result');
  });

  testWidgets('notifications', (tester) async {
    await openApp(tester);
    final raw = fixtures.load('notifications');
    final items = [
      for (final n in (raw is Map ? (raw['notifications'] ?? raw['results'] ?? const []) : raw) as List)
        Map<String, dynamic>.from(n as Map),
    ];
    await push(tester, NotificationsScreen(items: items));
    await shoot(tester, 'student_08_notifications');
  });

  testWidgets('menu', (tester) async {
    await openApp(tester);
    final state = tester.firstState<ScaffoldState>(find.byType(Scaffold));
    if (state.hasDrawer) {
      state.openDrawer();
      await shoot(tester, 'student_09_menu');
    }
  });

  testWidgets('account', (tester) async {
    await openApp(tester, size: tallPhone);
    await push(tester, const AccountScreen());
    await shoot(tester, 'student_10_account');
  });

  testWidgets('home, light theme', (tester) async {
    await openApp(tester, light: true, size: tallPhone);
    await shoot(tester, 'student_11_home_light');
  });

  testWidgets('home, Bangla', (tester) async {
    await openApp(tester, language: 'bn', size: tallPhone);
    await shoot(tester, 'student_12_home_bangla');
  });

  testWidgets('sign in', (tester) async {
    await openApp(tester, signedIn: false);
    await shoot(tester, 'student_13_sign_in');
  });

  testWidgets('messages', (tester) async {
    await openApp(tester);
    await push(tester, const ChatsScreen());
    await shoot(tester, 'student_14_messages');
  });

  testWidgets('chat with tutor', (tester) async {
    await openApp(tester);
    await push(
      tester,
      const ChatScreen(
        conversationId: '9a7c1e40-1111-4c1d-8a1b-000000000001',
        person: ChatPerson(id: '5314ab58-c2bc-462c-a9d1-65283d8f73b5', name: 'Ashraful Sir', role: 'TUTOR'),
      ),
    );
    await shoot(tester, 'student_15_chat');
  });
}
