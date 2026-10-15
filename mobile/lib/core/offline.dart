import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'i18n.dart';

/// Offline support.
///
///  * [ResponseCache] keeps the last answer of every GET the app made, on the
///    phone, so screens can be shown without internet (or while the free
///    server is still waking up).
///  * [Outbox] keeps changes made while offline (a class marked done, homework
///    assigned or checked, a homework link handed in) until they can be sent.
///  * [applyPendingChange] shows those waiting changes on top of the saved
///    answers, so the screen already looks the way it will after syncing.

// ── Saved answers ────────────────────────────────────────────────────────────

/// Where saved answers are kept between launches.
abstract class CacheStorage {
  Future<String?> read();
  Future<void> write(String contents);
  Future<void> delete();
}

/// One JSON file in the app's private storage.
class FileCacheStorage implements CacheStorage {
  FileCacheStorage([this.fileName = 'api_cache.json']);
  final String fileName;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<String?> read() async {
    try {
      final file = await _file();
      return await file.exists() ? await file.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String contents) async {
    final file = await _file();
    // Write a copy first, then swap it in, so a crash never leaves half a file.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(contents, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> delete() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // nothing saved, nothing to delete
    }
  }
}

class _CacheEntry {
  _CacheEntry(this.data, this.savedAt);
  final dynamic data;
  final DateTime savedAt;
}

/// The last server answer for each GET, keyed by path + query (see [cacheKeyFor]).
/// Without a [storage] it lives in memory only (tests, the web build).
class ResponseCache {
  ResponseCache({this.storage, this.maxEntries = 400});

  final CacheStorage? storage;

  /// Oldest answers are dropped beyond this many, so the file stays small.
  final int maxEntries;

  final Map<String, _CacheEntry> _entries = {};
  Timer? _saveTimer;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await storage?.read();
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v'] != 1 || decoded['entries'] is! Map) return;
      (decoded['entries'] as Map).forEach((key, value) {
        if (value is Map && value.containsKey('data')) {
          _entries['$key'] = _CacheEntry(value['data'], DateTime.tryParse('${value['at']}') ?? DateTime.now());
        }
      });
    } catch (_) {
      // A damaged file is simply ignored; it is rebuilt as the app is used.
    }
  }

  Iterable<String> get keys => _entries.keys;
  bool contains(String key) => _entries.containsKey(key);
  DateTime? savedAt(String key) => _entries[key]?.savedAt;

  /// A copy of the saved answer (callers may change it freely), or null.
  dynamic read(String key) {
    final entry = _entries[key];
    return entry == null ? null : deepCopy(entry.data);
  }

  void write(String key, dynamic data) {
    _entries.remove(key); // re-inserted last = most recently used
    _entries[key] = _CacheEntry(deepCopy(data), DateTime.now());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _scheduleSave();
  }

  Future<void> clear() async {
    _entries.clear();
    _saveTimer?.cancel();
    await storage?.delete();
  }

  void _scheduleSave() {
    if (storage == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), save);
  }

  Future<void> save() async {
    final store = storage;
    if (store == null) return;
    try {
      await store.write(jsonEncode({
        'v': 1,
        'entries': {
          for (final e in _entries.entries) e.key: {'at': e.value.savedAt.toIso8601String(), 'data': e.value.data},
        },
      }));
    } catch (_) {
      // Out of space or storage unavailable: the app still works, it just saves less.
    }
  }
}

/// The cache key of a request: path plus sorted query, without the host, so the
/// same screen finds its saved answer whatever page or order the query came in.
String cacheKeyFor(Uri uri) {
  final params = uri.queryParameters.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  final query = params.map((e) => '${e.key}=${e.value}').join('&');
  return query.isEmpty ? uri.path : '${uri.path}?$query';
}

/// A full copy of decoded JSON (maps keep String keys).
dynamic deepCopy(dynamic value) {
  if (value is Map) return <String, dynamic>{for (final e in value.entries) '${e.key}': deepCopy(e.value)};
  if (value is List) return [for (final v in value) deepCopy(v)];
  return value;
}

// ── Changes waiting to be sent ───────────────────────────────────────────────

/// The kinds of change the app can make offline. Each is safe to send twice:
/// marking a class sets it, homework carries a `client_ref` the server de-duplicates.
class PendingKind {
  static const markClass = 'mark_class';
  static const createHomework = 'create_homework';
  static const evaluateHomework = 'evaluate_homework';
  static const submitHomework = 'submit_homework';
}

class PendingChange {
  PendingChange({
    required this.id,
    required this.kind,
    required this.method,
    required this.path,
    required this.body,
    required this.label,
    this.extra = const {},
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String kind;
  final String method;

  /// API path below /api/v1, e.g. `/tuitions/{id}/mark_class/`.
  final String path;
  final Map<String, dynamic> body;

  /// Display-only details for showing the change before it is sent (names, counts).
  final Map<String, dynamic> extra;

  /// What the person did, in words: "Class 4 of Physics".
  final String label;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'method': method,
        'path': path,
        'body': body,
        'extra': extra,
        'label': label,
        'created_at': createdAt.toIso8601String(),
      };

  static PendingChange? fromJson(dynamic json) {
    if (json is! Map) return null;
    final body = json['body'];
    final extra = json['extra'];
    final id = '${json['id'] ?? ''}';
    final path = '${json['path'] ?? ''}';
    if (id.isEmpty || path.isEmpty) return null;
    return PendingChange(
      id: id,
      kind: '${json['kind'] ?? ''}',
      method: '${json['method'] ?? 'POST'}',
      path: path,
      body: body is Map ? Map<String, dynamic>.from(deepCopy(body) as Map) : <String, dynamic>{},
      extra: extra is Map ? Map<String, dynamic>.from(deepCopy(extra) as Map) : <String, dynamic>{},
      label: '${json['label'] ?? tr('A change')}',
      createdAt: DateTime.tryParse('${json['created_at']}'),
    );
  }
}

/// A random id for things made on the phone (pending changes, homework client refs).
String newLocalId() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Changes made offline, in the order they were made, kept per signed-in
/// person so one account never sends another's changes.
class Outbox extends ChangeNotifier {
  Outbox({required this.readString, required this.writeString});

  final String? Function(String key) readString;
  final Future<void> Function(String key, String value) writeString;

  String _owner = '';
  List<PendingChange> _items = [];

  /// Changes the server refused for good, in words, until the person dismisses them.
  final List<String> failures = [];

  String get _key => 'outbox_v1_$_owner';
  List<PendingChange> get items => List.unmodifiable(_items);
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  /// Switches to the waiting changes of the person now signed in.
  void useOwner(String userId) {
    if (userId == _owner) return;
    _owner = userId;
    failures.clear();
    _items = [];
    final raw = userId.isEmpty ? null : readString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        _items = [
          for (final item in jsonDecode(raw) as List)
            if (PendingChange.fromJson(item) case final PendingChange change) change,
        ];
      } catch (_) {
        _items = [];
      }
    }
    notifyListeners();
  }

  Future<void> add(PendingChange change) async {
    _items = [..._items, change];
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id, {String? failure}) async {
    _items = _items.where((c) => c.id != id).toList();
    if (failure != null) failures.add(failure);
    await _save();
    notifyListeners();
  }

  void clearFailures() {
    if (failures.isEmpty) return;
    failures.clear();
    notifyListeners();
  }

  /// Drops every waiting change of the current person (they signed out).
  Future<void> clear() async {
    _items = [];
    failures.clear();
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    if (_owner.isEmpty) return;
    await writeString(_key, jsonEncode([for (final c in _items) c.toJson()]));
  }

  /// [data] (the answer saved under [key]) with every waiting change shown on it.
  dynamic applyTo(String key, dynamic data) {
    for (final change in _items) {
      applyPendingChange(key, data, change);
    }
    return data;
  }
}

// ── Showing a waiting change on saved answers ────────────────────────────────

num _num(dynamic value) => value is num ? value : (num.tryParse('${value ?? ''}') ?? 0);
int _classNo(dynamic entry) => entry is Map ? _num(entry['class_no'] ?? entry['classNo']).toInt() : 0;
double _money(num value) => (value * 100).roundToDouble() / 100;

/// Calls [visit] for every JSON object inside [node].
void visitMaps(dynamic node, void Function(Map<String, dynamic> map) visit) {
  if (node is Map<String, dynamic>) {
    visit(node);
    for (final value in node.values.toList()) {
      visitMaps(value, visit);
    }
  } else if (node is List) {
    for (final value in node) {
      visitMaps(value, visit);
    }
  }
}

/// Marks class [classNo] of a cycle done (or not), and updates its counts and
/// money the way the server does. Returns false when the class is not in the cycle.
bool markClassInCycle(Map<String, dynamic> cycle, int classNo, bool completed, String? dateIso, String topic) {
  final total = _num(cycle['total_classes']).toInt();
  if (classNo < 1 || classNo > total) return false;
  final raw = cycle['classes_data'];
  final classes = <Map<String, dynamic>>[
    for (final c in (raw is List ? raw : const [])) if (c is Map) Map<String, dynamic>.from(c),
  ];
  var entry = classes.where((c) => _classNo(c) == classNo).firstOrNull;
  if (entry == null) {
    entry = <String, dynamic>{'class_no': classNo, 'topic': ''};
    classes.add(entry);
  }
  entry['completed'] = completed;
  entry['date'] = completed ? (dateIso ?? DateTime.now().toUtc().toIso8601String()) : null;
  // Like the server: a blank topic keeps the one already there; undoing a class clears it.
  entry['topic'] = completed ? (topic.isNotEmpty ? topic : '${entry['topic'] ?? ''}') : '';
  classes.sort((a, b) => _classNo(a).compareTo(_classNo(b)));
  cycle['classes_data'] = classes;

  final done = classes.where((c) => c['completed'] == true).length;
  final percent = total == 0 ? 0 : min(100, (done * 100 / total).round());
  cycle['completed_classes'] = done;
  cycle['progress_percent'] = percent;
  cycle['progress_percentage'] = percent;
  cycle['is_complete'] = total > 0 && done >= total;
  if (cycle.containsKey('total_fee')) {
    final fee = _num(cycle['total_fee']);
    final earned = total == 0 ? 0.0 : _money(fee * min(done, total) / total);
    cycle['earned_revenue'] = earned;
    cycle['pending_balance'] = max(0.0, _money(fee - earned));
  }
  return true;
}

/// The same for a tuition object (its `active_cycle` and `wallet_summary`).
bool markClassInTuition(Map<String, dynamic> tuition, int classNo, bool completed, String? dateIso, String topic) {
  final cycle = tuition['active_cycle'];
  if (cycle is! Map<String, dynamic>) return false;
  if (!markClassInCycle(cycle, classNo, completed, dateIso, topic)) return false;
  final wallet = tuition['wallet_summary'];
  if (wallet is Map<String, dynamic>) {
    wallet['completed_classes'] = cycle['completed_classes'];
    if (cycle.containsKey('earned_revenue')) {
      wallet['earned_revenue'] = cycle['earned_revenue'];
      wallet['pending_balance'] = cycle['pending_balance'];
      wallet['lifetime_earnings'] = _money(_num(wallet['archived_earnings']) + _num(cycle['earned_revenue']));
    }
  }
  return true;
}

/// The wallet totals after one tuition's current cycle reached [completedClasses].
bool setWalletProgress(Map<String, dynamic> wallet, String tuitionId, int completedClasses) {
  final rows = wallet['tuition_breakdowns'];
  if (rows is! List) return false;
  for (final row in rows) {
    if (row is! Map<String, dynamic> || '${row['tuition_id']}' != tuitionId) continue;
    final total = _num(row['total_classes']).toInt();
    final done = min(max(completedClasses, 0), total);
    final fee = _num(row['total_fee']);
    final earnedBefore = _num(row['earned']);
    final earned = total == 0 ? 0.0 : _money(fee * done / total);
    row['completed_classes'] = done;
    row['earned'] = earned;
    row['pending'] = max(0.0, _money(fee - earned));
    row['progress_percentage'] = total == 0 ? 0 : min(100, (done * 100 / total).round());
    final delta = earned - earnedBefore;
    wallet['total_earned'] = _money(_num(wallet['total_earned']) + delta);
    wallet['total_pending'] = max(0.0, _money(_num(wallet['total_pending']) - delta));
    final chart = wallet['chart_data'];
    if (chart is List) {
      for (final slice in chart) {
        if (slice is! Map<String, dynamic>) continue;
        if (slice['name'] == 'Earned') slice['value'] = wallet['total_earned'];
        if (slice['name'] == 'Pending') slice['value'] = wallet['total_pending'];
      }
    }
    return true;
  }
  return false;
}

/// A homework row standing in for one assigned offline, until the server has it.
Map<String, dynamic> homeworkPlaceholder(Map<String, dynamic> body, Map<String, dynamic> extra) {
  final now = DateTime.now().toUtc().toIso8601String();
  final student = body['student'];
  final tuition = body['tuition'];
  return {
    'id': 'local-${body['client_ref']}',
    'title': '${body['title'] ?? ''}',
    'description': '${body['description'] ?? ''}',
    'due_date': body['due_date'],
    'source_label': '${body['source_label'] ?? ''}',
    'tutor_name': '',
    'tutor_display_name': '',
    'tutor_profile_picture': null,
    'student_id': student,
    'student_name': student == null ? null : '${extra['target_name'] ?? ''}',
    'tuition_id': tuition,
    'tuition_title': tuition == null ? null : '${extra['target_name'] ?? ''}',
    'is_group': student == null && tuition != null,
    'group_source_id': null,
    'client_ref': body['client_ref'],
    'submitted_online_url': '',
    'submission_file_url': null,
    'submitted_at': null,
    'is_submitted': false,
    'is_evaluated': false,
    'evaluated_at': null,
    'tutor_feedback': '',
    'created_at': now,
    'updated_at': now,
    'pending_sync': true,
  };
}

bool _isHomeworkList(String key) {
  final uri = Uri.parse('http://app$key');
  if (!uri.path.endsWith('/homework/')) return false;
  final page = int.tryParse(uri.queryParameters['page'] ?? '1') ?? 1;
  return page == 1 && uri.queryParameters['evaluated'] != 'true';
}

/// Shows [change] on [data], the saved answer for [key]. Safe to apply twice.
void applyPendingChange(String key, dynamic data, PendingChange change) {
  final body = change.body;
  switch (change.kind) {
    case PendingKind.markClass: {
      final tuitionId = '${change.extra['tuition_id'] ?? ''}';
      final classNo = _num(body['class_no']).toInt();
      final completed = body['completed'] == true;
      final date = body['date'] as String?;
      final topic = '${body['topic'] ?? ''}';
      visitMaps(data, (map) {
        if ('${map['id']}' == tuitionId && map.containsKey('active_cycle')) {
          markClassInTuition(map, classNo, completed, date, topic);
        } else if (map['tuition_id'] != null && '${map['tuition_id']}' == tuitionId && map.containsKey('classes_data') &&
            map['status'] == 'ACTIVE') {
          markClassInCycle(map, classNo, completed, date, topic); // an attendance-cycles list
        }
      });
      final after = change.extra['completed_after'];
      if (after is num) {
        visitMaps(data, (map) {
          if (map.containsKey('tuition_breakdowns')) setWalletProgress(map, tuitionId, after.toInt());
        });
      }
    }
    case PendingKind.createHomework: {
      if (!_isHomeworkList(key)) return;
      final ref = body['client_ref'];
      final rows = data is Map && data['results'] is List ? data['results'] as List : (data is List ? data : null);
      if (rows == null || rows.any((r) => r is Map && r['client_ref'] == ref)) return;
      rows.insert(0, homeworkPlaceholder(body, change.extra));
      if (data is Map && data['count'] is num) data['count'] = (data['count'] as num) + 1;
    }
    case PendingKind.evaluateHomework: {
      final id = '${change.extra['homework_id'] ?? ''}';
      visitMaps(data, (map) {
        if ('${map['id']}' != id || !map.containsKey('is_evaluated')) return;
        map['is_evaluated'] = body['is_evaluated'] != false;
        map['evaluated_at'] = map['is_evaluated'] == true ? change.createdAt.toUtc().toIso8601String() : null;
        final feedback = '${body['tutor_feedback'] ?? ''}';
        if (feedback.isNotEmpty) map['tutor_feedback'] = feedback;
      });
    }
    case PendingKind.submitHomework: {
      final id = '${change.extra['homework_id'] ?? ''}';
      visitMaps(data, (map) {
        if ('${map['id']}' != id || !map.containsKey('is_submitted')) return;
        map['submitted_online_url'] = '${body['submitted_online_url'] ?? ''}';
        map['submitted_at'] = change.createdAt.toUtc().toIso8601String();
        map['is_submitted'] = true;
      });
    }
  }
}

/// True when this build can keep files (not the web build).
bool get canPersistCache => !kIsWeb;
