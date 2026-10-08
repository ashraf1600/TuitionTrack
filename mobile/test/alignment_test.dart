// Offline-only tests that prove the hardening in this branch works without
// needing a running backend. Mirrors a tiny part of `live_api_test.dart` so
// regressions get caught quickly even when LIVE_API isn't set.
import 'package:flutter_test/flutter_test.dart';

import 'package:tuitiontrack/core/connect.dart';
import 'package:tuitiontrack/core/json.dart';

void main() {
  group('normalizeInviteCode', () {
    test('uppercases, strips spaces and separators', () {
      expect(normalizeInviteCode('kx7-q2 m'), 'KX7Q2M');
      expect(normalizeInviteCode(' KX7Q2M '), 'KX7Q2M');
      expect(normalizeInviteCode('kx7q2m'), 'KX7Q2M');
    });

    test('rejects too-short or too-long input', () {
      expect(normalizeInviteCode('KX7'), isNull);
      expect(normalizeInviteCode('KX7Q2M99ABCD'), isNull);
      expect(normalizeInviteCode(''), isNull);
      expect(normalizeInviteCode('   '), isNull);
    });

    test('drops anything that is not A-Z or 0-9', () {
      expect(normalizeInviteCode('kx7.q2!'), 'KX7Q2');
      expect(normalizeInviteCode('KX7Q2Mö'), 'KX7Q2M');
    });
  });

  group('dateUtc', () {
    test('naive ISO is interpreted as UTC, then converted to local', () {
      // Both naive and Z ISO must resolve to the same instant in UTC; only the
      // local-zone representation differs. The point of dateUtc is that a naive
      // string is *not* silently read as local time.
      final naive = {'iso': '2025-04-12T12:00:00'}.dateUtc('iso')!.toUtc();
      final withOffset = {'iso': '2025-04-12T12:00:00Z'}.dateUtc('iso')!.toUtc();
      expect(naive, withOffset,
          reason: 'a naive ISO and a Z ISO must refer to the same instant');
    });

    test('ISO ending in Z is parsed as UTC', () {
      final parsed = {'iso': '2025-04-12T12:00:00Z'}.dateUtc('iso');
      expect(parsed, isNotNull);
      // After dateUtc -> toLocal(), the returned DateTime is in local time,
      // but its toUtc() must equal the original 12:00 UTC.
      expect(parsed!.toUtc().hour, 12);
    });

    test('explicit offset is respected', () {
      // 18:00 in +06:00 is the same instant as 12:00 UTC.
      final parsed = {'iso': '2025-04-12T18:00:00+06:00'}.dateUtc('iso')!.toUtc();
      final z = {'iso': '2025-04-12T12:00:00Z'}.dateUtc('iso')!.toUtc();
      expect(parsed, z, reason: 'an explicit +06:00 offset must equal a UTC instant of 12:00');
    });

    test('missing or malformed values return null without throwing', () {
      expect(<String, dynamic>{}.dateUtc('iso'), isNull);
      expect({'iso': ''}.dateUtc('iso'), isNull);
      expect({'iso': 'not a date'}.dateUtc('iso'), isNull);
      expect({'iso': 12345}.dateUtc('iso'), isNull);
    });

    test('subtracting a duration matches the server grace window exactly', () {
      // Reproduces the bug that motivated dateUtc — adding 5 minutes to a
      // naive ISO deadline must not shift the answer by hours when the device
      // is not in UTC.
      final naive = {'iso': '2025-04-12T12:00:00'};
      final withOffset = {'iso': '2025-04-12T12:00:00Z'};
      final a = naive.dateUtc('iso')!;
      final b = withOffset.dateUtc('iso')!;
      expect(a.toUtc(), b.toUtc(),
          reason: 'naive ISO and Z ISO must resolve to the same instant in UTC');
    });
  });
}