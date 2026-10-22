// Takes dark-mode screenshots of every main screen of the app, with demo data
// (a tutor "Ashraf Sir" and his students; no real users).
//
// Run from mobile/:   flutter test test_screens/app_screens_test.dart
// The pictures land in mobile/test_screens/shots/.
//
// The server is replaced by recorded answers (fixtures.json) whose times are
// moved to "now", so "Today", countdowns and open exams look current.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:tuitiontrack/core/api.dart';
import 'package:tuitiontrack/core/app_keys.dart';
import 'package:tuitiontrack/core/repo.dart';
import 'package:tuitiontrack/core/session.dart';
import 'package:tuitiontrack/screens/auth/login_screen.dart';
import 'package:tuitiontrack/screens/common/account_screen.dart';
import 'package:tuitiontrack/screens/common/notifications.dart';
import 'package:tuitiontrack/screens/student/exam_result_screen.dart';
import 'package:tuitiontrack/screens/student/student_home.dart';
import 'package:tuitiontrack/screens/student/tutor_detail_screen.dart';
import 'package:tuitiontrack/screens/tutor/exam_editor_screen.dart';
import 'package:tuitiontrack/screens/tutor/tuition_screen.dart';
import 'package:tuitiontrack/screens/tutor/tutor_home.dart';
import 'package:tuitiontrack/widgets/theme.dart';

late Map<String, dynamic> _fixtures;
late Duration _shift;
String _role = 'tutor';

final _isoTime = RegExp(r'"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))"');

/// The recorded answer for a request, with every timestamp moved to the present.
http.Response _answer(http.Request request) {
  var path = request.url.path.replaceFirst('/api/v1', '');
  final tuitionId = request.url.queryParameters['tuition_id'];
  if (path == '/attendance-cycles/' && tuitionId != null) path = '/attendance-cycles/@$tuitionId';
  final body = _fixtures['$_role:$path'];
  final headers = {'content-type': 'application/json', 'date': HttpDate.format(DateTime.now().toUtc())};
  if (body == null) return http.Response(request.method == 'GET' ? '[]' : '{}', 200, headers: headers);
  final text = jsonEncode(body).replaceAllMapped(_isoTime, (m) {
    final moved = DateTime.parse(m[1]!).add(_shift).toUtc();
    return '"${moved.toIso8601String()}"';
  });
  return http.Response.bytes(utf8.encode(text), 200, headers: headers);
}

Future<void> _loadFont(String family, List<Future<ByteData>> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(f);
  }
  await loader.load();
}

Future<ByteData> _file(String path) async => ByteData.sublistView(await File(path).readAsBytes());

Future<void> _loadFonts() async {
  await _loadFont('HankenGrotesk', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) rootBundle.load('assets/fonts/HankenGrotesk-$w.ttf'),
  ]);
  await _loadFont('HindSiliguri', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) rootBundle.load('assets/fonts/HindSiliguri-$w.ttf'),
  ]);
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  if (root.isNotEmpty && File(icons).existsSync()) await _loadFont('MaterialIcons', [_file(icons)]);
  final roboto = '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf';
  if (root.isNotEmpty && File(roboto).existsSync()) await _loadFont('Roboto', [_file(roboto)]);
  // Typeset maths (flutter_math_fork ships its KaTeX fonts in the package).
  for (final (family, file) in [
    ('KaTeX_Main', 'KaTeX_Main-Regular'),
    ('KaTeX_Math', 'KaTeX_Math-Italic'),
    ('KaTeX_Size1', 'KaTeX_Size1-Regular'),
    ('KaTeX_Size2', 'KaTeX_Size2-Regular'),
    ('KaTeX_AMS', 'KaTeX_AMS-Regular'),
  ]) {
    try {
      await _loadFont('packages/flutter_math_fork/$family', [rootBundle.load('packages/flutter_math_fork/lib/katex_fonts/fonts/$file.ttf')]);
    } catch (_) {
      // Not found under this name in this package version: maths falls back to a default font.
    }
  }
}

Future<Session> _session(String? role) async {
  _role = role ?? 'tutor';
  final api = ApiClient(baseUrl: 'http://demo.local', tokens: MemoryTokenStore(), client: MockClient((r) async => _answer(r)));
  final session = Session(api: api, settings: MemorySettings());
  if (role != null) {
    await api.setTokens('demo-access', 'demo-refresh');
    session.user = Map<String, dynamic>.from(_fixtures['$role:/auth/me/'] as Map);
    // Already seen: keeps the "Get started" list and first-run hints out of the pictures.
    await session.settings.setString('get_started_hidden', 'yes');
  }
  session.ready = true;
  return session;
}

final _frame = GlobalKey();

Widget _app(Session session, Widget home) => RepaintBoundary(
      key: _frame,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<Session>.value(value: session),
          Provider<Repo>(create: (_) => Repo(session.api, outbox: session.outbox)),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ttTheme(isDark: true, isBangla: false),
          darkTheme: ttTheme(isDark: true, isBangla: false),
          themeMode: ThemeMode.dark,
          navigatorKey: rootNavigatorKey,
          scaffoldMessengerKey: rootMessengerKey,
          home: home,
        ),
      ),
    );

/// Lets loads finish and animations come to rest (some repeat forever, so no pumpAndSettle).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await _settle(tester);
  await expectLater(find.byKey(_frame), matchesGoldenFile('shots/$name.png'));
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) return;
  await tester.tap(finder.last, warnIfMissed: false);
  await _settle(tester);
}

String _examId(String role, String title) {
  final raw = _fixtures['$role:/exams/'];
  final list = raw is List ? raw : (raw as Map)['results'] as List;
  return (list.firstWhere((e) => e['title'] == title) as Map)['id'] as String;
}

void _check(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      // ignore: avoid_print
      print('::error::$name: ${details.exceptionAsString().replaceAll('\n', ' ')} ${details.stack.toString().split('\n').take(4).join(' | ')}');
      original?.call(details);
    };
    try {
      await body(tester);
    } catch (e, s) {
      // ignore: avoid_print
      print('::error::$name THROWN: ${'$e'.replaceAll('\n', ' ')} ${s.toString().split('\n').take(4).join(' | ')}');
      rethrow;
    } finally {
      FlutterError.onError = original;
    }
  });
}

void main() {
  setUpAll(() async {
    autoUpdateGoldenFiles = true;
    _fixtures = jsonDecode(File('test_screens/fixtures.json').readAsStringSync()) as Map<String, dynamic>;
    _shift = DateTime.now().toUtc().difference(DateTime.parse(_fixtures['__captured_at'] as String));
    await _loadFonts();
  });

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  _check('signed out', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(await _session(null), const LoginScreen()));
    await _shot(tester, '01_login');
    await tester.pumpWidget(const SizedBox());
  });

  _check('tutor', (tester) async {
    await phone(tester);
    final session = await _session('tutor');
    await tester.pumpWidget(_app(session, const TutorHome()));
    await _shot(tester, '10_tutor_home_this_week');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await _shot(tester, '11_tutor_home_tuitions');
    await _tapText(tester, 'Students');
    await _shot(tester, '12_tutor_students');
    await _tapText(tester, 'Homework');
    await _shot(tester, '13_tutor_homework');
    await _tapText(tester, 'Exams');
    await _shot(tester, '14_tutor_exams');
    await tester.pumpWidget(const SizedBox());
  });

  _check('tutor: a tuition', (tester) async {
    await phone(tester);
    final session = await _session('tutor');
    final raw = _fixtures['tutor:/tuitions/'];
    final first = ((raw is List ? raw : (raw as Map)['results'] as List).firstWhere((t) => t['title'] == 'Class 10 Physics') as Map)['id'] as String;
    await tester.pumpWidget(_app(session, TuitionScreen(tuitionId: first)));
    await _shot(tester, '15_tutor_tuition');
    await tester.pumpWidget(const SizedBox());
  });

  _check('tutor: new exam with the symbol toolbar', (tester) async {
    await phone(tester);
    final session = await _session('tutor');
    await tester.pumpWidget(_app(session, const ExamEditorScreen()));
    await _settle(tester);
    final fields = find.byType(TextField);
    if (fields.evaluate().isNotEmpty) {
      await tester.tap(fields.first);
      await tester.enterText(fields.first, 'Physics — Chapter 3 Test (H₂O, v = u + at)');
    }
    await _shot(tester, '16_tutor_exam_editor_toolbar');
    await tester.pumpWidget(const SizedBox());
  });

  _check('tutor: notifications and account', (tester) async {
    await phone(tester);
    final session = await _session('tutor');
    final items = [for (final n in (_fixtures['tutor:/notifications/'] as Map)['notifications'] as List) Map<String, dynamic>.from(n as Map)];
    await tester.pumpWidget(_app(session, NotificationsScreen(items: items)));
    await _shot(tester, '17_tutor_notifications');
    await tester.pumpWidget(_app(session, const AccountScreen()));
    await _shot(tester, '18_account');
    await tester.pumpWidget(const SizedBox());
  });

  _check('student', (tester) async {
    await phone(tester);
    final session = await _session('student');
    await tester.pumpWidget(_app(session, const StudentHome()));
    await _shot(tester, '20_student_home_today');
    await _tapText(tester, 'Exams');
    await _shot(tester, '21_student_exams');
    await _tapText(tester, 'Homework');
    await _shot(tester, '22_student_homework');
    // The side menu.
    final menu = find.byTooltip('Open navigation menu');
    if (menu.evaluate().isNotEmpty) {
      await tester.tap(menu.first);
      await _shot(tester, '23_menu');
    }
    await tester.pumpWidget(const SizedBox());
  });

  _check('student: a tutor page', (tester) async {
    await phone(tester);
    final session = await _session('student');
    final raw = _fixtures['student:/my-tutors/'];
    final tutor = ((raw is List ? raw : (raw as Map)['results'] as List).first as Map);
    await tester.pumpWidget(_app(session, TutorDetailScreen(tutorId: tutor['id'] as String, title: tutor['display_name'] as String)));
    await _shot(tester, '24_student_tutor_classes');
    await _tapText(tester, 'Exams');
    await _shot(tester, '25_student_tutor_exams');
    await _tapText(tester, 'Homework');
    await _shot(tester, '26_student_tutor_homework');
    await tester.pumpWidget(const SizedBox());
  });

  _check('student: a result', (tester) async {
    await phone(tester);
    final session = await _session('student');
    final id = _examId('student', 'Motion — Weekly Test 3');
    await tester.pumpWidget(_app(session, ExamResultScreen(examId: id, title: 'Motion — Weekly Test 3')));
    await _shot(tester, '27_student_result');
    await tester.pumpWidget(const SizedBox());
  });
}
