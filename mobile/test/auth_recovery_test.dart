// Forgot password (6-digit code) and Sign in with Google: what the app sends
// and how it reads the answers. No server or Google plugin needed.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tuitiontrack/core/api.dart';
import 'package:tuitiontrack/core/repo.dart';
import 'package:tuitiontrack/core/session.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _user = {'id': 'u1', 'username': 'rina', 'name': 'Rina', 'role': 'STUDENT', 'has_password': false};

void main() {
  late List<http.Request> sent;
  late Map<String, http.Response Function(http.Request)> routes;

  ApiClient client() => ApiClient(
        baseUrl: 'https://api.example.com',
        tokens: MemoryTokenStore(),
        client: MockClient((request) async {
          sent.add(request);
          final path = request.url.path.replaceFirst('/api/v1', '');
          final handler = routes[path];
          return handler == null ? _json(404, {'message': 'no route'}) : handler(request);
        }),
      );

  setUp(() {
    sent = [];
    routes = {};
  });

  group('forgot password', () {
    test('code check answers uid and token, confirm sends them with the new password', () async {
      routes['/auth/password-reset/verify/'] = (_) => _json(200, {'uid': 'U', 'token': 'T', 'username': 'rina'});
      routes['/auth/password-reset/confirm/'] = (_) => _json(200, {'message': 'ok'});
      final repo = Repo(client());

      final reset = await repo.verifyResetCode('rina@gmail.com', '123456');
      expect(reset['uid'], 'U');
      expect(jsonDecode(sent.last.body), {'identifier': 'rina@gmail.com', 'code': '123456'});

      await repo.confirmPasswordReset('U', 'T', 'BrandNew456!y');
      expect(jsonDecode(sent.last.body), {'uid': 'U', 'token': 'T', 'new_password': 'BrandNew456!y'});
    });

    test('a wrong code is an ApiException with the server message', () async {
      routes['/auth/password-reset/verify/'] =
          (_) => _json(400, {'message': 'That code is not correct or has expired.', 'code': 'invalid_reset_code'});
      await expectLater(
        Repo(client()).verifyResetCode('rina', '000000'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_reset_code')),
      );
    });
  });

  group('sign in with Google', () {
    test('an existing account signs straight in', () async {
      routes['/auth/google/'] = (_) => _json(200, {'access': 'A', 'refresh': 'R', 'user': _user, 'created': false});
      routes['/auth/me/'] = (_) => _json(200, _user);
      final session = Session(api: client(), settings: MemorySettings());

      final created = await session.loginWithGoogle('google-id-token');
      expect(created, isFalse);
      expect(jsonDecode(sent.first.body), {'id_token': 'google-id-token'});
      expect(session.signedIn, isTrue);
      expect(session.isStudent, isTrue);
      expect(session.hasPassword, isFalse);
    });

    test('no account: the error carries the Google email, and a role creates one', () async {
      var calls = 0;
      routes['/auth/google/'] = (request) {
        calls++;
        final body = jsonDecode(request.body) as Map;
        if (!body.containsKey('role')) {
          return _json(404, {
            'message': 'No TuitionTrack account uses this Google email yet.',
            'code': 'google_account_not_found',
            'email': 'rina@gmail.com',
            'signup_allowed': true,
          });
        }
        return _json(201, {'access': 'A', 'refresh': 'R', 'user': _user, 'created': true});
      };
      routes['/auth/me/'] = (_) => _json(200, _user);
      final session = Session(api: client(), settings: MemorySettings());

      try {
        await session.loginWithGoogle('tok');
        fail('expected google_account_not_found');
      } on ApiException catch (error) {
        expect(error.code, 'google_account_not_found');
        expect(error.status, 404);
        expect(error.data['email'], 'rina@gmail.com');
        expect(error.data['signup_allowed'], isTrue);
      }
      expect(session.signedIn, isFalse);

      final created = await session.loginWithGoogle('tok', role: 'STUDENT');
      expect(created, isTrue);
      expect(calls, 2);
      expect(jsonDecode(sent.firstWhere((r) => r.body.contains('role')).body), {'id_token': 'tok', 'role': 'STUDENT'});
      expect(session.signedIn, isTrue);
    });
  });
}
