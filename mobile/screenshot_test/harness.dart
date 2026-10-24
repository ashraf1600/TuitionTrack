// Renders real app screens against recorded API answers, as PNG screenshots.
//
//   flutter test screenshot_test --update-goldens
//
// writes screenshot_test/goldens/*.png. The answers in test/fixtures/ come from
// backend/scripts/make_demo_fixtures.py; every date in them is moved forward
// so it keeps the same distance from "now" as when it was recorded.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tuitiontrack/core/api.dart';
import 'package:tuitiontrack/core/session.dart';

const fixtureDir = 'test/fixtures';

/// Phone-sized canvas (logical pixels) and the pixel ratio of the saved PNG.
const phone = Size(412, 892);
const tallPhone = Size(412, 1900);
const shotPixelRatio = 2.0;

bool _fontsLoaded = false;

Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  Future<void> family(String name, List<String> assets) async {
    final loader = FontLoader(name);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await family('HankenGrotesk', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/HankenGrotesk-$w.ttf',
  ]);
  // Widgets that set no font (button labels) ask for Roboto, which tests do not have;
  // a phone draws them in its system font, so the app font stands in here.
  await family('Roboto', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/HankenGrotesk-$w.ttf',
  ]);
  await family('HindSiliguri', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/HindSiliguri-$w.ttf',
  ]);
  // Material icons come with the Flutter SDK.
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
    await loader.load();
  }
  _fontsLoaded = true;
}

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$');
const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

dynamic _shift(dynamic value, Duration by) {
  if (value is Map) return {for (final e in value.entries) e.key: _shift(e.value, by)};
  if (value is List) return [for (final v in value) _shift(v, by)];
  if (value is String && _isoDate.hasMatch(value)) {
    return DateTime.parse(value).add(by).toUtc().toIso8601String();
  }
  return value;
}

Map<String, dynamic> _slot(DateTime at, {int minutes = 90}) {
  final end = at.add(Duration(minutes: minutes));
  String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  return {'day': _days[at.weekday - 1], 'start_time': hm(at), 'end_time': hm(end)};
}

/// Weekly class times placed relative to the test's clock, by subject.
List<Map<String, dynamic>> _routineFor(String subject, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final soon = DateTime(now.year, now.month, now.day, now.hour).add(const Duration(hours: 2));
  return switch (subject) {
    'Physics' => [_slot(soon), _slot(today.add(const Duration(days: 2, hours: 17))), _slot(today.add(const Duration(days: 4, hours: 17)))],
    'Higher Math' => [_slot(today.add(const Duration(days: 1, hours: 10))), _slot(today.add(const Duration(days: 5, hours: 10)))],
    'Chemistry' => [_slot(today.add(const Duration(days: 1, hours: 18, minutes: 30))), _slot(today.add(const Duration(days: 3, hours: 18, minutes: 30)))],
    _ => const [],
  };
}

dynamic _withRoutines(dynamic value, DateTime now) {
  if (value is List) return [for (final v in value) _withRoutines(v, now)];
  if (value is! Map) return value;
  final map = {for (final e in value.entries) e.key as String: _withRoutines(e.value, now)};
  final subject = map['subject'];
  if (subject is String && map.containsKey('routine')) {
    final routine = _routineFor(subject, now);
    map['routine'] = routine;
    if (map.containsKey('weekly_routine')) map['weekly_routine'] = routine;
  }
  return map;
}

/// The recorded answers for one side ('student' or 'tutor'), moved to now.
class Fixtures {
  Fixtures(this.side) {
    final meta = jsonDecode(File('$fixtureDir/meta.json').readAsStringSync()) as Map<String, dynamic>;
    this.meta = meta;
    shift = DateTime.now().difference(DateTime.parse(meta['captured_at'] as String));
  }

  final String side;
  late final Map<String, dynamic> meta;
  late final Duration shift;

  dynamic load(String name) {
    final file = File('$fixtureDir/$side/$name.json');
    if (!file.existsSync()) return null;
    return _withRoutines(_shift(jsonDecode(file.readAsStringSync()), shift), DateTime.now());
  }

  /// Which fixture answers a GET to [path] (without /api/v1).
  String? nameFor(String path) {
    const plain = {
      '/auth/me/': 'me', '/my-tutors/': 'my_tutors', '/tuitions/': 'tuitions', '/connections/': 'connections',
      '/exams/': 'exams', '/homework/': 'homework', '/notifications/': 'notifications', '/meta/': 'meta',
      '/routines/': 'routines', '/schedules/': 'schedules', '/students/': 'students', '/analytics/wallet/': 'wallet',
    };
    if (plain.containsKey(path)) return plain[path];
    if (path == '/students/unassigned/') return 'students_unassigned';
    if (path == '/attendance-cycles/') return 'cycles';
    if (path.endsWith('/submissions/')) return 'submissions';
    if (RegExp(r'^/tuitions/[0-9a-f-]+/$').hasMatch(path)) return 'tuition_detail';
    if (path.startsWith('/my-tutors/')) return 'tutor_detail';
    if (path.endsWith('/result/')) return 'exam_result';
    if (path.endsWith('/leaderboard/')) return 'leaderboard';
    if (path == '/chats/') return 'chats';
    if (path == '/chats/unread/') return 'chats_unread';
    if (path == '/chats/contacts/') return 'chats_contacts';
    if (RegExp(r'^/chats/[0-9a-f-]+/messages/$').hasMatch(path)) return 'chat_messages';
    if (RegExp(r'^/chats/[0-9a-f-]+/$').hasMatch(path)) return 'chat_detail';
    return null;
  }

  http.Client client() => MockClient((request) async {
        final path = request.url.path.replaceFirst('/api/v1', '');
        final name = request.method == 'GET' ? nameFor(path) : null;
        final body = name == null ? null : load(name);
        if (body == null) {
          return http.Response(jsonEncode({'message': 'Not in the demo data.', 'code': 'not_found'}), 404,
              headers: {'content-type': 'application/json'});
        }
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
}

/// A signed-in session (or a signed-out one) talking to the recorded answers.
Future<Session> demoSession(Fixtures fixtures, {bool signedIn = true, bool light = false, String language = 'en'}) async {
  final settings = MemorySettings();
  await settings.setString('language', language);
  if (light) await settings.setString('theme_mode', 'light');
  final tokens = MemoryTokenStore();
  if (signedIn) await tokens.write(access: 'demo-access', refresh: 'demo-refresh');
  final session = Session(
    api: ApiClient(baseUrl: 'https://tuitiontrack-api.onrender.com', tokens: tokens, client: fixtures.client()),
    settings: settings,
  );
  await session.restore();
  return session;
}

/// Sizes the test window like a phone.
void usePhone(WidgetTester tester, {Size size = phone}) {
  tester.view.physicalSize = size * shotPixelRatio;
  tester.view.devicePixelRatio = shotPixelRatio;
  addTearDown(tester.view.reset);
}

/// Lets loading, staggered entrances and tweens finish without waiting on endless animations.
Future<void> settle(WidgetTester tester, {int seconds = 3}) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shoot(WidgetTester tester, String name) async {
  await settle(tester);
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('goldens/$name.png'));
}
