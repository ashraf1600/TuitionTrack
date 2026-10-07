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
