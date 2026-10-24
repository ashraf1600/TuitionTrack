// Screenshots of the tutor side (see harness.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuitiontrack/core/app_keys.dart';
import 'package:tuitiontrack/main.dart';
import 'package:tuitiontrack/screens/tutor/homework_tab.dart';
import 'package:tuitiontrack/screens/tutor/tuition_screen.dart';

import 'harness.dart';

void main() {
  final fixtures = Fixtures('tutor');

  setUpAll(loadAppFonts);

  Future<void> openApp(WidgetTester tester, {Size size = tallPhone, bool light = false}) async {
    usePhone(tester, size: size);
    final session = (await tester.runAsync(() => demoSession(fixtures, light: light)))!;
    await tester.pumpWidget(TuitionTrackApp(session: session));
    await settle(tester);
  }

  Future<void> tapTab(WidgetTester tester, int index) async {
    final bar = find.byType(NavigationBar);
    if (bar.evaluate().isEmpty) return;
    await tester.tap(find.descendant(of: bar, matching: find.byType(NavigationDestination)).at(index));
    await settle(tester);
  }

  testWidgets('home', (tester) async {
    await openApp(tester, size: phone);
    await shoot(tester, 'tutor_01_home');
  });

  testWidgets('home, whole page', (tester) async {
    await openApp(tester);
    await shoot(tester, 'tutor_02_home_full');
  });

  for (final (index, name) in [(1, 'tutor_03_tab2'), (2, 'tutor_04_tab3'), (3, 'tutor_05_tab4')]) {
    testWidgets('tab $index', (tester) async {
      await openApp(tester);
      await tapTab(tester, index);
      await shoot(tester, name);
    });
  }

  testWidgets('tuition', (tester) async {
    await openApp(tester);
    rootNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => TuitionScreen(tuitionId: fixtures.meta['tuition_id'] as String)),
    );
    await settle(tester);
    await shoot(tester, 'tutor_06_tuition');
  });

  testWidgets('home, light theme', (tester) async {
    await openApp(tester, light: true);
    await shoot(tester, 'tutor_07_home_light');
  });

  testWidgets('homework form with science typing', (tester) async {
    await openApp(tester, size: phone);
    rootNavigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => const HomeworkCreateScreen()));
    await settle(tester);
    final fields = find.byType(TextField);
    if (fields.evaluate().isNotEmpty) {
      await tester.enterText(fields.first, r'Kinematics: show $v^2 = u^2 + 2as$');
      await settle(tester);
      final more = find.text('Add instructions');
      if (more.evaluate().isNotEmpty) {
        await tester.tap(more);
        await settle(tester);
        await tester.enterText(find.byType(TextField).at(1), r'Q1. Find $\frac{1}{2}mv^2$ for m = 2 kg, v = 3 m/s. Q2. Balance H₂ + O₂ → H₂O');
        await settle(tester);
      }
    }
    await shoot(tester, 'tutor_08_homework_form');
  });
}
