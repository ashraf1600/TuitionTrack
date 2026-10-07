import 'api.dart';

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
    final data = _map(await api.get('/notifications/'));
    return (data['notifications'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
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
  Future<Json> submitExam(String id, {required Json answers, required String text, required List<String> images}) async =>
      _map(await api.post('/exams/$id/submit/', {
        'answers_data': answers.map((key, value) => MapEntry(key, '$value')),
        'text_answer': text,
        'image_urls': images,
        'uploaded_images': images,
      }));
  Future<Json> result(String id) async => _map(await api.get('/exams/$id/result/'));
}
