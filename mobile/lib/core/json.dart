import 'api.dart';

export 'api.dart' show Json;

/// Tolerant readers for API JSON: a missing or oddly typed value never throws.
extension JsonRead on Map<String, dynamic> {
  String str(String key, [String fallback = '']) {
    final value = this[key];
    return value == null ? fallback : '$value';
  }

  num number(String key, [num fallback = 0]) {
    final value = this[key];
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? fallback;
    return fallback;
  }

  num? numberOrNull(String key) {
    final value = this[key];
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  int integer(String key, [int fallback = 0]) => number(key, fallback).round();

  bool flag(String key) {
    final value = this[key];
    return value == true || value == 'true' || value == 1;
  }

  /// A server timestamp as local time, or null.
  DateTime? date(String key) {
    final value = this[key];
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  /// A server timestamp coerced to UTC before being shown in local time.
  ///
  /// The Django API may emit either "2025-04-12T10:00:00Z" or a naive
  /// "2025-04-12T10:00:00" (no offset). [date] would treat the latter as local
  /// time, which silently shifts the grace window by hours. [dateUtc] forces a
  /// UTC interpretation for naive ISO and only then converts to local.
  DateTime? dateUtc(String key) {
    final value = this[key];
    if (value is! String || value.isEmpty) return null;
    final hasOffset = value.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);
    if (hasOffset) {
      // "2025-04-12T12:00:00Z" or "...+06:00" — DateTime.parse gives us the
      // correct instant; expose it in local time.
      return DateTime.tryParse(value)?.toLocal();
    }
    // Naive ISO: build a UTC DateTime from the parsed components so the
    // resulting instant is unambiguous. DateTime.tryParse would otherwise
    // treat "12:00:00" as 12:00 *local*, and a +06:00 device would silently
    // shift the grace window by six hours.
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$').firstMatch(value);
    if (m == null) return DateTime.tryParse(value)?.toLocal();
    return DateTime.utc(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6) ?? '0'),
    ).toLocal();
  }

  Json? obj(String key) {
    final value = this[key];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  List<Json> maps(String key) {
    final value = this[key];
    if (value is! List) return const [];
    return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<String> strings(String key) {
    final value = this[key];
    if (value is! List) return const [];
    return value.map((e) => '$e').toList();
  }
}

/// "12", "12.5" — a number without a pointless ".0".
String trimNumber(num? value) {
  if (value == null) return '—';
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// Money in taka with thousands separators: ৳12,000.
String taka(num? value) {
  final amount = (value ?? 0).round();
  final digits = amount.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}৳$out';
}
