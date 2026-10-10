import 'dart:typed_data';

import 'api.dart';
import 'connect.dart';
import 'offline.dart';

Json _map(dynamic data) => data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

/// Every server call the app makes, one method per endpoint.
///
/// Reads come from the server, or from what was saved on the phone when it
/// cannot be reached (see [ApiClient.cache]). A few writes also work offline:
/// they are kept in the [outbox] and sent later, and their result carries
/// `queued: true` instead of the server's answer.
class Repo {
  Repo(this.api, {this.outbox});
  final ApiClient api;
  final Outbox? outbox;

  /// Sends a change now, or keeps it for later when the server cannot be reached.
  Future<Json> _sendOrKeep(
    String method,
    String path,
    Json body, {
    required String kind,
    required String label,
    Json extra = const {},
  }) async {
    try {
      return _map(await api.send(method, path, body));
    } on ApiException catch (error) {
      final box = outbox;
      if (box == null || !error.isUnreachable) rethrow;
      await box.add(PendingChange(
        id: newLocalId(),
        kind: kind,
        method: method,
        path: path,
        body: body,
        extra: extra,
        label: label,
      ));
      return {'queued': true, 'message': '$label saved on this phone. It will be sent when you are back online.'};
    }
  }

  /// Completed classes of a tuition's current cycle as saved on the phone, with
  /// every waiting change and then [classNo] applied (for the wallet while offline).
  int? _completedAfter(String tuitionId, int classNo, bool completed) {
    final cache = api.cache;
    if (cache == null) return null;
    for (final key in cache.keys.toList()) {
      Json? found;
      final data = outbox?.applyTo(key, cache.read(key)) ?? cache.read(key);
      visitMaps(data, (map) {
        if (found == null && '${map['id']}' == tuitionId && map['active_cycle'] is Map<String, dynamic>) found = map;
      });
      final tuition = found;
      if (tuition == null) continue;
      if (!markClassInTuition(tuition, classNo, completed, null, '')) return null;
      final cycle = tuition['active_cycle'] as Map<String, dynamic>;
      final done = cycle['completed_classes'];
      return done is num ? done.toInt() : null;
    }
    return null;
  }

  // ── Account ────────────────────────────────────────────────────────────────
  Future<Json> meta() async => _map(await api.get('/meta/'));
  Future<Json> updateMe(Json changes) async => _map(await api.patch('/auth/me/', changes));
  Future<Json> setProfilePhoto(Uint8List bytes, String filename) async => _map(await api.uploadProfilePhoto(bytes, filename));
  Future<Json> removeProfilePhoto() async => _map(await api.delete('/auth/me/photo/'));
  Future<String> requestPasswordReset(String identifier) async =>
      _map(await api.post('/auth/password-reset/', {'identifier': identifier}))['message'] as String? ?? '';
  Future<List<Json>> tutors([String search = '']) => api.list('/auth/tutors/', query: {'search': search});
  Future<List<Json>> notifications() async {
    final raw = await api.get('/notifications/');
    List<dynamic>? list;
    if (raw is List) {
      list = raw;
    } else if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      // The endpoint may return any of these shapes depending on whether the
      // session is paginated or the result set is empty.
      list = (map['notifications'] ?? map['results'] ?? map['items']) as List?;
    }
    return (list ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ── Students (tutor) ───────────────────────────────────────────────────────
  Future<List<Json>> students() => api.list('/students/');
  Future<List<Json>> unassignedStudents() => api.list('/students/unassigned/');
  Future<Json> createStudent(Json form) async => _map(await api.post('/students/', form));
  Future<Json> updateStudent(String id, Json changes) async => _map(await api.patch('/students/$id/', changes));
  Future<Json> toggleStudentActive(String id) async => _map(await api.post('/students/$id/toggle_active/'));
  Future<Json> resetStudentPassword(String id) async => _map(await api.post('/students/$id/reset_password/'));

  // ── Tuition groups ─────────────────────────────────────────────────────────
  Future<List<Json>> tuitions() => api.list('/tuitions/');
  Future<Json> tuition(String id) async => _map(await api.get('/tuitions/$id/'));
  Future<Json> createTuition(Json form) async => _map(await api.post('/tuitions/', form));
  Future<Json> updateTuition(String id, Json changes) async => _map(await api.patch('/tuitions/$id/', changes));
  Future<void> deleteTuition(String id) async => api.delete('/tuitions/$id/');
  Future<Json> enroll(String tuitionId, List<String> studentIds) async =>
      _map(await api.post('/tuitions/$tuitionId/enroll/', {'student_ids': studentIds}));
  Future<Json> unenroll(String tuitionId, String studentId) async =>
      _map(await api.post('/tuitions/$tuitionId/unenroll/', {'student_id': studentId}));
  /// Marks a class of the tuition's current cycle. Works offline: the class
  /// is dated now (or [date]) on the phone, so it keeps that date when sent later.
  Future<Json> markClass(String tuitionId, int classNo, bool completed,
      {DateTime? date, String topic = '', String tuitionTitle = ''}) async {
    final at = completed ? (date ?? DateTime.now()) : null;
    final body = <String, dynamic>{
      'class_no': classNo,
      'completed': completed,
      if (at != null) 'date': at.toUtc().toIso8601String(),
      if (topic.isNotEmpty) 'topic': topic,
    };
    return _sendOrKeep(
      'PATCH',
      '/tuitions/$tuitionId/mark_class/',
      body,
      kind: PendingKind.markClass,
      label: tuitionTitle.isEmpty ? 'Class $classNo' : 'Class $classNo of $tuitionTitle',
      extra: {
        'tuition_id': tuitionId,
        if (_completedAfter(tuitionId, classNo, completed) case final int done) 'completed_after': done,
      },
    );
  }
  Future<List<Json>> cycles(String tuitionId) => api.list('/attendance-cycles/', query: {'tuition_id': tuitionId});
  Future<Json> resetCycle(String cycleId) async => _map(await api.post('/attendance-cycles/$cycleId/reset/'));
  Future<Json> wallet() async => _map(await api.get('/analytics/wallet/'));

  // ── Connection requests ────────────────────────────────────────────────────
  Future<List<Json>> connections([String status = '']) => api.list('/connections/', query: {'status': status});
  Future<Json> sendConnection(String tutorId, String message) async =>
      _map(await api.post('/connections/', {'tutor_id': tutorId, 'message': message}));
  Future<void> withdrawConnection(String id) async => api.delete('/connections/$id/');
  Future<Json> acceptConnection(String id, {String? tuitionId}) async =>
      _map(await api.post('/connections/$id/accept/', {if (tuitionId != null) 'tuition_id': tuitionId}));
  Future<Json> rejectConnection(String id) async => _map(await api.post('/connections/$id/reject/'));

  // ── TutorTrack: invite-code + tutor dashboard ──────────────────────────────
  /// GET /my-tutors/ -> [{id, display_name, username, profile_picture(_url), tuitions, subjects}]
  Future<List<Json>> myTutors() => api.list('/my-tutors/');

  /// `GET /my-tutors/{id}/` -> {tutor, weekly_routine, upcoming_classes, homework}
  Future<Json> tutorDetail(String tutorId) async => _map(await api.get('/my-tutors/$tutorId/'));

  /// POST /connections/by-code/ {tutor_code, message} -> {status, tutor_display_name, ...}
  ///
  /// Normalises the invite code (trim, uppercase, strip separators) before
  /// sending. Throws an [ApiException] with `code: 'bad_code'` when the input
  /// is not a usable code, so callers can show a precise message without
  /// hitting the network.
  Future<Json> connectByCode(String code, {String message = ''}) async {
    final normalized = normalizeInviteCode(code);
    if (normalized == null) {
      throw ApiException(
        'Enter the 4–8 character invite code from your tutor.',
        code: 'bad_code',
      );
    }
    return _map(await api.post('/connections/by-code/', {
      'tutor_code': normalized,
      'message': message,
    }));
  }

  // ── Homework ───────────────────────────────────────────────────────────────
  Future<List<Json>> homework({String? tutorId, bool? evaluated}) => api.list('/homework/', query: {
        if (tutorId != null) 'tutor_id': tutorId,
        if (evaluated != null) 'evaluated': '$evaluated',
      });
  Future<Json> homeworkDetail(String id) async => _map(await api.get('/homework/$id/'));
  /// Tutor creates homework tied to one tuition or one student.
  /// `dueDate` is sent as a UTC ISO string; pass a local DateTime.
  /// Description is optional — leaving it empty omits the field.
  /// `sourceLabel` (e.g. "Class 4 · Oct 9") records where it came from.
  /// Works offline. Every request carries a `client_ref`, so sending it again
  /// (a retry after reconnecting) never makes a second copy on the server.
  /// [targetName] (the tuition or student) is only for showing it before it is sent.
  Future<Json> createHomework({
    required String title,
    String description = '',
    required DateTime dueDate,
    String? tuitionId,
    String? studentId,
    String sourceLabel = '',
    String targetName = '',
  }) async {
    assert(tuitionId != null || studentId != null, 'homework needs a tuition or a student');
    final body = <String, dynamic>{
      'title': title,
      if (description.isNotEmpty) 'description': description,
      'due_date': dueDate.toUtc().toIso8601String(),
      if (sourceLabel.isNotEmpty) 'source_label': sourceLabel,
      if (tuitionId != null) 'tuition': tuitionId,
      if (studentId != null) 'student': studentId,
      'client_ref': newLocalId(),
    };
    return _sendOrKeep('POST', '/homework/', body,
        kind: PendingKind.createHomework,
        label: 'Homework "$title"${targetName.isEmpty ? '' : ' for $targetName'}',
        extra: {'target_name': targetName});
  }
  Future<Json> updateHomework(String id, Json changes) async {
    _refuseLocal(id);
    return _map(await api.patch('/homework/$id/', changes));
  }

  Future<void> deleteHomework(String id) async {
    _refuseLocal(id);
    await api.delete('/homework/$id/');
  }
  /// Tutor: turn a shared group task into one row per enrolled student, in one
  /// server step. Work already handed in is kept. Returns the per-student rows.
  Future<List<Json>> splitHomework(String id) async {
    final data = _map(await api.post('/homework/$id/split/'));
    return (data['homework'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Student upload: URL only — never sends is_evaluated. On a shared group
  /// task the server answers with the student's own copy (a different id).
  /// Works offline.
  Future<Json> submitHomework(String id, String url) async {
    _refuseLocal(id);
    final data = await _sendOrKeep('POST', '/homework/$id/submit/', {'submitted_online_url': url},
        kind: PendingKind.submitHomework, label: 'Your homework link', extra: {'homework_id': id});
    return data.containsKey('homework') ? _map(data['homework']) : data;
  }

  /// Tutor close: the ONLY writer of is_evaluated. Works offline.
  Future<Json> evaluateHomework(String id, {bool evaluated = true, String feedback = ''}) async {
    _refuseLocal(id);
    final data = await _sendOrKeep('POST', '/homework/$id/evaluate/', {'is_evaluated': evaluated, 'tutor_feedback': feedback},
        kind: PendingKind.evaluateHomework, label: 'Homework check', extra: {'homework_id': id});
    return data.containsKey('homework') ? _map(data['homework']) : data;
  }

  /// Homework assigned offline has no server id yet; it can be changed once it is sent.
  void _refuseLocal(String id) {
    if (id.startsWith('local-')) {
      throw ApiException('This homework is still waiting to be sent. Try again once you are back online.',
          code: 'pending_sync');
    }
  }

  // ── Routines & dated classes ───────────────────────────────────────────────
  Future<List<Json>> routines() => api.list('/routines/');
  Future<List<Json>> schedules({bool upcoming = false}) =>
      api.list('/schedules/', query: {'upcoming': '$upcoming'});

  // ── Exams ──────────────────────────────────────────────────────────────────
  Future<List<Json>> exams({String? tuitionId}) => api.list('/exams/', query: {'tuition_id': tuitionId});
  Future<Json> exam(String id) async => _map(await api.get('/exams/$id/'));
  Future<Json> createExam(Json form) async => _map(_map(await api.post('/exams/', form))['exam']);
  Future<Json> updateExam(String id, Json changes) async => _map(await api.patch('/exams/$id/', changes));
  Future<void> deleteExam(String id) async => api.delete('/exams/$id/');
  Future<Json> duplicateExam(String id, {String? tuitionId}) async =>
      _map(_map(await api.post('/exams/$id/duplicate/', {if (tuitionId != null) 'tuition_id': tuitionId}))['exam']);
  Future<Json> publishResults(String id, bool publish) async =>
      _map(await api.post('/exams/$id/publish_results/', {'publish': publish}));
  Future<List<Json>> questionBank([String search = '']) async {
    final data = _map(await api.get('/exams/question_bank/', query: {'search': search}));
    return (data['questions'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Json> submissions(String examId) async => _map(await api.get('/exams/$examId/submissions/'));
  Future<Json> grade(String submissionId, Json marks) async => _map(await api.patch('/submissions/$submissionId/grade/', marks));
  Future<Json> leaderboard(String examId) async => _map(await api.get('/exams/$examId/leaderboard/'));

  // Student side
  Future<Json> startExam(String id) async => _map(await api.post('/exams/$id/start/'));
  Future<Json> submitExam(String id, {required Json answers, required String text, required List<String> images}) async {
    // The backend serializer accepts ints natively and a single-letter string
    // for "A"–"E" answers, but rejects other shapes; we therefore type-coerce
    // each answer before posting. Falls back to a Stringified value when the
    // input is not a recognisable answer so the payload is always well-formed.
    final typed = <String, Object>{};
    answers.forEach((key, value) {
      if (value is int) {
        typed[key] = value;
      } else if (value is String && RegExp(r'^[A-E]$').hasMatch(value.toUpperCase())) {
        typed[key] = value.toUpperCase();
      } else {
        typed[key] = value?.toString() ?? '';
      }
    });
    return _map(await api.post('/exams/$id/submit/', {
      'answers_data': typed,
      'text_answer': text,
      'image_urls': images,
      'uploaded_images': images,
    }));
  }
  Future<Json> result(String id) async => _map(await api.get('/exams/$id/result/'));
}
