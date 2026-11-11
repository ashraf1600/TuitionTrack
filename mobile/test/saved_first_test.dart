// Opening fast: screens and the session start from what the phone saved last
// time, without waiting for a server that may be asleep.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tuitiontrack/core/api.dart';
import 'package:tuitiontrack/core/offline.dart';
import 'package:tuitiontrack/core/session.dart';

void main() {
  test('fromSavedOnly answers from the phone and never calls the server', () async {
    var calls = 0;
    final api = ApiClient(
      baseUrl: 'https://example.test',
      tokens: MemoryTokenStore(),
      cache: ResponseCache(),
      client: MockClient((request) async {
        calls++;
        return http.Response(jsonEncode({'n': calls}), 200, headers: {'content-type': 'application/json'});
      }),
    );
    // Nothing saved yet: the saved-only pass reports it and leaves the network alone.
    await expectLater(ApiClient.fromSavedOnly(() => api.get('/meta/')), throwsA(isA<SavedCopyMissing>()));
    expect(calls, 0);

    expect((await api.get('/meta/') as Map)['n'], 1);
    // Saved now: answered at once, the server is not asked again.
    expect((await ApiClient.fromSavedOnly(() => api.get('/meta/')) as Map)['n'], 1);
    expect(calls, 1);
    expect((api.saved('/meta/') as Map)['n'], 1);
    expect(api.saved('/never/'), isNull);
    // Outside the saved-only pass requests go to the server as before.
    expect((await api.get('/meta/') as Map)['n'], 2);
  });

  test('a returning user is signed in from the saved profile before the server answers', () async {
    final gate = Completer<void>();
    final cache = ResponseCache()..write('/api/v1/auth/me/', {'id': 'u1', 'role': 'TUTOR', 'username': 'ash', 'name': 'Old name'});
    final tokens = MemoryTokenStore();
    await tokens.write(access: 'access-token', refresh: 'refresh-token');
    final api = ApiClient(
      baseUrl: 'https://example.test',
      tokens: tokens,
      cache: cache,
      client: MockClient((request) async {
        await gate.future; // a sleeping server
        return http.Response(jsonEncode({'id': 'u1', 'role': 'TUTOR', 'username': 'ash', 'name': 'New name'}), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    final session = Session(api: api, settings: MemorySettings());
    await session.restore();
    expect(session.ready, isTrue);
    expect(session.signedIn, isTrue);
    expect(session.user!['name'], 'Old name');

    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(session.user!['name'], 'New name');
  });
}
