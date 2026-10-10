// Offline mode: saved answers, changes kept on the phone, and how those
// changes are shown before they reach the server.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tuitiontrack/core/api.dart';
import 'package:tuitiontrack/core/format.dart';
import 'package:tuitiontrack/core/json.dart';
import 'package:tuitiontrack/core/offline.dart';
import 'package:tuitiontrack/core/repo.dart';
import 'package:tuitiontrack/core/session.dart';

Map<String, dynamic> _tuition({int done = 0}) => {
      'id': 't1',
      'title': 'Physics',
      'active_cycle': {
        'id': 'c1',
        'cycle_number': 1,
        'total_classes': 4,
        'completed_classes': done,
        'total_fee': 4000,
        'earned_revenue': done * 1000.0,
        'pending_balance': 4000 - done * 1000.0,
        'is_complete': false,
        'classes_data': [
          for (var n = 1; n <= done; n++) {'class_no': n, 'completed': true, 'date': '2026-10-0${n}T12:00:00Z', 'topic': ''},
        ],
      },
      'wallet_summary': {'earned_revenue': done * 1000.0, 'pending_balance': 4000 - done * 1000.0, 'archived_earnings': 0},
    };

Outbox _outbox(MemorySettings settings, [String owner = 'u1']) =>
    Outbox(readString: settings.getString, writeString: settings.setString)..useOwner(owner);

void main() {
  group('cacheKeyFor', () {
    test('ignores host and query order', () {
      expect(
        cacheKeyFor(Uri.parse('https://a.example/api/v1/homework/?b=2&a=1')),
        cacheKeyFor(Uri.parse('http://10.0.2.2:8000/api/v1/homework/?a=1&b=2')),
      );
      expect(cacheKeyFor(Uri.parse('https://a.example/api/v1/meta/')), '/api/v1/meta/');
    });
  });

  group('ResponseCache', () {
    test('hands out copies, so a screen cannot change what is saved', () {
      final cache = ResponseCache();
      cache.write('/k/', {'list': [1, 2]});
      final copy = cache.read('/k/') as Map;
      (copy['list'] as List).add(3);
      expect((cache.read('/k/') as Map)['list'], [1, 2]);
    });

    test('drops the oldest answers beyond its limit', () {
      final cache = ResponseCache(maxEntries: 2);
      cache.write('/a/', 1);
      cache.write('/b/', 2);
      cache.write('/c/', 3);
      expect(cache.contains('/a/'), isFalse);
      expect(cache.keys.toList(), ['/b/', '/c/']);
    });
  });

  group('markClassInTuition', () {
    test('counts the class and the money like the server', () {
      final tuition = _tuition(done: 1);
      expect(markClassInTuition(tuition, 2, true, '2026-10-10T12:00:00Z', 'Optics'), isTrue);
      final cycle = tuition['active_cycle'] as Map<String, dynamic>;
      expect(cycle['completed_classes'], 2);
      expect(cycle['earned_revenue'], 2000.0);
      expect(cycle['pending_balance'], 2000.0);
      expect((tuition['wallet_summary'] as Map)['earned_revenue'], 2000.0);
      final entry = (cycle['classes_data'] as List).last as Map;
      expect(entry['topic'], 'Optics');
    });

    test('is safe to apply twice and can be undone', () {
      final tuition = _tuition(done: 1);
      markClassInTuition(tuition, 2, true, null, '');
      markClassInTuition(tuition, 2, true, null, '');
      expect((tuition['active_cycle'] as Map)['completed_classes'], 2);
      markClassInTuition(tuition, 2, false, null, '');
      expect((tuition['active_cycle'] as Map)['completed_classes'], 1);
    });

    test('refuses a class outside the cycle', () {
      expect(markClassInTuition(_tuition(), 9, true, null, ''), isFalse);
    });
  });

  test('setWalletProgress moves money from "still to earn" to "earned"', () {
    final wallet = <String, dynamic>{
      'total_earned': 1000.0,
      'total_pending': 3000.0,
      'tuition_breakdowns': [
        {'tuition_id': 't1', 'total_classes': 4, 'completed_classes': 1, 'total_fee': 4000, 'earned': 1000.0},
      ],
    };
    expect(setWalletProgress(wallet, 't1', 3), isTrue);
    expect(wallet['total_earned'], 3000.0);
    expect(wallet['total_pending'], 1000.0);
    // Applying the same state again changes nothing.
    setWalletProgress(wallet, 't1', 3);
    expect(wallet['total_earned'], 3000.0);
  });

  group('Outbox', () {
    test('keeps changes per person across restarts', () async {
      final settings = MemorySettings();
      final box = _outbox(settings);
      await box.add(PendingChange(id: 'x', kind: PendingKind.markClass, method: 'PATCH', path: '/tuitions/t1/mark_class/', body: {'class_no': 1}, label: 'Class 1'));
      expect(_outbox(settings).length, 1);
      expect(_outbox(settings, 'someone-else').length, 0);
    });

    test('shows a waiting homework at the top of the homework list, once', () async {
      final box = _outbox(MemorySettings());
      await box.add(PendingChange(
        id: 'h',
        kind: PendingKind.createHomework,
        method: 'POST',
        path: '/homework/',
        body: {'title': 'Ch 4', 'due_date': '2030-01-01T00:00:00Z', 'tuition': 't1', 'client_ref': 'abc'},
        extra: {'target_name': 'Physics'},
        label: 'Homework',
      ));
      final page = {'count': 1, 'results': [{'id': 'server-1', 'title': 'Old'}]};
      box.applyTo('/api/v1/homework/?page_size=200', page);
      box.applyTo('/api/v1/homework/?page_size=200', page);
      final rows = page['results'] as List;
      expect(rows.length, 2);
      expect((rows.first as Map)['id'], 'local-abc');
      expect((rows.first as Map)['pending_sync'], isTrue);
      expect((rows.first as Map)['tuition_title'], 'Physics');
    });
  });

  group('Repo offline', () {
    late bool online;
    late ApiClient api;
    late Outbox box;
    late Repo repo;
    final sent = <String>[];

    setUp(() {
      online = true;
      sent.clear();
      api = ApiClient(
        baseUrl: 'http://test',
        tokens: MemoryTokenStore(),
        cache: ResponseCache(),
        client: MockClient((request) async {
          if (!online) throw http.ClientException('no network');
          sent.add('${request.method} ${request.url.path}');
          if (request.method == 'GET' && request.url.path == '/api/v1/tuitions/') {
            return http.Response(jsonEncode([_tuition(done: 1)]), 200, headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode({'ok': true}), 200, headers: {'content-type': 'application/json'});
        }),
      );
      box = _outbox(MemorySettings());
      api.overlay = box.applyTo;
      repo = Repo(api, outbox: box);
    });

    test('marking a class offline keeps it and shows it on the saved tuitions', () async {
      expect((await repo.tuitions()).single.str('title'), 'Physics');
      online = false;
      final result = await repo.markClass('t1', 2, true, tuitionTitle: 'Physics');
      expect(result['queued'], isTrue);
      expect(box.length, 1);
      expect(api.offline.value, isTrue);

      final saved = await repo.tuitions();
      expect((saved.single['active_cycle'] as Map)['completed_classes'], 2);
    });

    test('a refusal from the server is not kept for later', () async {
      api = ApiClient(
        baseUrl: 'http://test',
        tokens: MemoryTokenStore(),
        client: MockClient((_) async => http.Response(jsonEncode({'detail': 'No.'}), 400, headers: {'content-type': 'application/json'})),
      );
      repo = Repo(api, outbox: box);
      await expectLater(repo.markClass('t1', 2, true), throwsA(isA<ApiException>()));
      expect(box.length, 0);
    });

    test('homework made offline cannot be edited before it is sent', () async {
      await expectLater(repo.deleteHomework('local-abc'), throwsA(isA<ApiException>()));
    });
  });

  group('routine days', () {
    test('normalizeDay reads short and long names', () {
      expect(normalizeDay('sat'), 'Saturday');
      expect(normalizeDay(' SUNDAY '), 'Sunday');
      expect(normalizeDay('x'), '');
    });

    test('slotsOn picks the day and sorts by real time', () {
      final routine = [
        {'day': 'Saturday', 'start_time': '18:00'},
        {'day': 'sat', 'start_time': '9:30'},
        {'day': 'Monday', 'start_time': '08:00'},
      ];
      final saturday = DateTime(2026, 10, 10); // a Saturday
      expect(slotsOn(routine, saturday).map(slotStart).toList(), ['9:30', '18:00']);
    });
  });
}
