// The logo and its loading animation draw without errors, animate, and stand still when the phone asks for no motion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tuitiontrack/widgets/theme.dart';
import 'package:tuitiontrack/widgets/tt_logo.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
      theme: ttTheme(isDark: true, isBangla: false),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child,
        ),
      ),
    );

void main() {
  testWidgets('the splash shows the animated logo and the name', (tester) async {
    await tester.pumpWidget(_app(const TtSplash(message: 'Starting…')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TtLoader), findsOneWidget);
    expect(find.textContaining('Track', findRichText: true), findsOneWidget);
    expect(find.text('Starting…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the logo draws itself once when asked to', (tester) async {
    await tester.pumpWidget(_app(const Scaffold(body: Center(child: TtLogo(size: 80, animate: true)))));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(TtLogo), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with reduced motion the loader is a still logo', (tester) async {
    await tester.pumpWidget(_app(const Scaffold(body: Center(child: TtLoader())), reduceMotion: true));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TtLogo), findsOneWidget);
  });
}
