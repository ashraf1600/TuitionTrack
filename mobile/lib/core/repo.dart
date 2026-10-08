import 'api.dart';
import 'connect.dart';

Json _map(dynamic data) => data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

/// Every server call the app makes, one method per endpoint.
class Repo {
  Repo(this.api);
  final ApiClient api;

  // ── Account ────────────────────────────────────────────────────────────────
  Future<Json> meta() async => _map(await api.get('/meta/'));
  Future<Json> updateMe(Json changes) async => _map(await api.patch('/auth/me/', changes));
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
  Future<Json> markClass(String tuitionId, int classNo, bool completed, {DateTime? date, String topic = ''}) async =>
      _map(await api.patch('/tuitions/$tuitionId/mark_class/', {
        'class_no': classNo,
        'completed': completed,
        if (date != null) 'date': date.toUtc().toIso8601String(),
        if (topic.isNotEmpty) 'topic': topic,
      }));
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

  /// GET /my-tutors/<id>/ -> {tutor, weekly_routine, upcoming_classes, homework}
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
  Future<Json> createHomework({
    required String title,
    String description = '',
    required DateTime dueDate,
    String? tuitionId,
    String? studentId,
  }) async {
    assert(tuitionId != null || studentId != null, 'homework needs a tuition or a student');
    return _map(await api.post('/homework/', {
      'title': title,
      if (description.isNotEmpty) 'description': description,
      'due_date': dueDate.toUtc().toIso8601String(),
      if (tuitionId != null) 'tuition': tuitionId,
      if (studentId != null) 'student': studentId,
    }));
  }
  /// Student upload: URL only — never sends is_evaluated.
  Future<Json> submitHomework(String id, String url) async {
    final data = _map(await api.post('/homework/$id/submit/', {'submitted_online_url': url}));
    return data.containsKey('homework') ? _map(data['homework']) : data;
  }

  /// Tutor close: the ONLY writer of is_evaluated (tries evaluate/, falls back to mark_done/).
  Future<Json> evaluateHomework(String id, {bool evaluated = true, String feedback = ''}) async {
    try {
      final data = _map(await api.post('/homework/$id/evaluate/', {
        'is_evaluated': evaluated,
        'tutor_feedback': feedback,
      }));
      return data.containsKey('homework') ? _map(data['homework']) : data;
    } on ApiException catch (e) {
      if (e.status == 404) {
        final data = _map(await api.post('/homework/$id/mark_done/', {'feedback': feedback}));
        return data.containsKey('homework') ? _map(data['homework']) : data;
      }
      rethrow;
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
