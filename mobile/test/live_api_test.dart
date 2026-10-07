// End-to-end check of every server call the app makes, against a running backend.
//
// Skipped unless LIVE_API is set. To run it, start the backend on a throwaway
// copy of the database that has the demo accounts, then:
//
//   LIVE_API=http://127.0.0.1:8011 DEMO_PW=<demo password> flutter test test/live_api_test.dart
//
// It creates and deletes its own group, student and exam.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tuitiontrack/core/api.dart';
import 'package:tuitiontrack/core/json.dart';
import 'package:tuitiontrack/core/mcq_parser.dart';
import 'package:tuitiontrack/core/repo.dart';
import 'package:tuitiontrack/core/session.dart';

final _server = Platform.environment['LIVE_API'] ?? '';
final _password = Platform.environment['DEMO_PW'] ?? '';

Session _newSession() => Session(api: ApiClient(baseUrl: _server, tokens: MemoryTokenStore()), settings: MemorySettings());

/// A 1×1 PNG.
final _png = Uint8List.fromList(base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
));

void main() {
  final skip = _server.isEmpty ? 'LIVE_API is not set' : false;

  test('every call works end to end, for a tutor and a student', skip: skip, timeout: const Timeout(Duration(minutes: 3)), () async {
    final tutor = _newSession();
    final student = _newSession();
    final t = Repo(tutor.api);
    final s = Repo(student.api);
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // ── Before signing in ────────────────────────────────────────────────────
    final meta = await t.meta();
    expect(meta.str('api_version'), 'v1');
    expect(meta.date('server_time'), isNotNull);
    expect(await t.tutors('demo'), isNotEmpty);
    await expectLater(tutor.login('demo_tutor', 'definitely-wrong'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));

    // ── Tutor signs in (any capitalisation) and reads everything ─────────────
    await tutor.login('DEMO_Tutor', _password);
    expect(tutor.isTutor, isTrue);
    expect(tutor.displayName, isNotEmpty);
    final wallet = await t.wallet();
    expect(wallet.containsKey('total_earned'), isTrue);
    final groups = await t.tuitions();
    final demoGroup = groups.firstWhere((g) => g.str('title') == 'Class 10 Math Batch');
    expect(demoGroup.obj('wallet_summary'), isNotNull);
    expect((await t.tuition(demoGroup.str('id'))).maps('enrollments'), isNotEmpty);
    expect(await t.cycles(demoGroup.str('id')), isNotEmpty);
    final students = await t.students();
    expect(students.map((x) => x.str('username')), contains('demo_s1'));
    await t.unassignedStudents();
    await t.connections('PENDING');
    await t.notifications();
    await t.questionBank();

    // ── A group of its own: create, edit, enrol, mark a class, clean up ──────
    final group = await t.createTuition({
      'title': 'Live test $stamp',
      'subject': 'Physics',
      'total_fee': 4000,
      'cycle_length': 4,
      'routine': [
        {'day': 'Sunday', 'start_time': '18:00', 'end_time': '19:30'},
      ],
    });
    final groupId = group.str('id');
    expect(group.obj('active_cycle')!.integer('total_classes'), 4);
    final s2 = students.firstWhere((x) => x.str('username') == 'demo_s2');
    expect((await t.enroll(groupId, [s2.str('id')])).obj('tuition')!.maps('enrollments').length, 1);
    final marked = await t.markClass(groupId, 1, true, date: DateTime.now(), topic: 'Kinematics');
    expect(marked.obj('wallet_summary')!.number('earned_revenue'), 1000);
    expect(marked.obj('cycle')!.maps('classes_data').first.str('topic'), 'Kinematics');
    await t.markClass(groupId, 1, false);
    expect((await t.updateTuition(groupId, {'title': 'Live test $stamp (edited)', 'cycle_length': 6})).obj('active_cycle')!.integer('total_classes'), 6);
    await t.unenroll(groupId, s2.str('id'));
    await expectLater(
      t.resetCycle((await t.cycles(groupId)).first.str('id')),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('before completion'))),
    );

    // ── A student of its own: create, edit, reset, deactivate ────────────────
    final created = await t.createStudent({
      'username': 'live_$stamp',
      'password': 'temp-pass-$stamp',
      'first_name': 'Live',
      'last_name': 'Student',
      'grade_level': 'Class 9',
      'tuition_id': groupId,
    });
    final newStudent = created.obj('student')!;
    expect(newStudent.flag('must_change_password'), isTrue);
    final updated = await t.updateStudent(newStudent.str('id'), {
      'first_name': 'Lively',
      'profile': {'institution': 'Test School', 'notes': 'private'},
    });
    expect(updated.str('first_name'), 'Lively');
    expect(updated.obj('profile')!.str('institution'), 'Test School');
    final reset = await t.resetStudentPassword(newStudent.str('id'));
    expect(reset.str('temporary_password').length, greaterThanOrEqualTo(8));
    expect((await t.toggleStudentActive(newStudent.str('id'))).flag('is_active'), isFalse);
    expect((await t.toggleStudentActive(newStudent.str('id'))).flag('is_active'), isTrue);

    // A brand-new student is made to choose a password, and can then use the app.
    final fresh = _newSession();
    await fresh.login('live_$stamp', reset.str('temporary_password'));
    expect(fresh.mustChangePassword, isTrue);
    await fresh.changePassword(reset.str('temporary_password'), 'Chosen-Passphrase-$stamp');
    expect(fresh.mustChangePassword, isFalse);
    expect((await Repo(fresh.api).tuitions()).single.str('title'), contains('Live test'));
    await Repo(fresh.api).updateMe({'phone': '01700000000', 'institution': 'My School'});
    await fresh.refreshUser();
    expect(fresh.user!.obj('profile')!.str('institution'), 'My School');
    await fresh.logout();

    // ── Uploading a picture ──────────────────────────────────────────────────
    final imageUrl = await tutor.api.upload(_png, 'live_test_$stamp.png');
    expect(imageUrl, startsWith('/media/'));
    expect(tutor.api.mediaUrl(imageUrl), startsWith('$_server/media/'));

    // ── An exam: pasted questions, written scheme, results on submission ─────
    final parsed = parseQuestions(r'''
1. If \(P(x)=x^3-3x^2+5x-7\), then \(P(1)\) is—
A) \(-4\)  B) \(-3\)  C) \(-2\)  D) 0
Answer: A
Explanation: \(P(1)=1-3+5-7=-4\)

2. The SI unit of force is
A) Joule
B) Newton ✅
C) Watt
D) Pascal
''');
    expect(parsed.issues, isEmpty);
    final questions = [
      ...parsed.questions,
      {'id': 'x', 'question': '', 'image_url': imageUrl, 'options': ['A', 'B', 'C', 'D'], 'correct_answer': 2, 'points': 1},
    ];
    final now = DateTime.now();
    Json examPayload(String title) => {
          'title': title,
          'category': 'EXAM',
          'exam_type': 'HYBRID',
          'tuition_id': demoGroup.str('id'),
          'student_id': null,
          'content_html': '<p>Q1. Prove that \\(\\sqrt{2}\\) is irrational.</p>',
          'mcq_data': questions,
          'written_scheme': [
            {'label': 'Q1', 'marks': 5},
          ],
          'solution_html': '<p>By contradiction.</p>',
          'total_marks': 10,
          'start_time': now.subtract(const Duration(minutes: 2)).toUtc().toIso8601String(),
          'end_time': now.add(const Duration(hours: 1)).toUtc().toIso8601String(),
          'duration_minutes': 30,
          'negative_marks_per_wrong': 0.25,
          'is_published': true,
          'result_publish_mode': 'IMMEDIATE',
          'publish_time': null,
        };
    final exam = await t.createExam(examPayload('Live exam $stamp'));
    final examId = exam.str('id');
    expect(exam.maps('mcq_data').length, 3);
    expect(exam.maps('mcq_data').first['correct_answer'], 0);
    expect((await t.exams(tuitionId: demoGroup.str('id'))).map((e) => e.str('id')), contains(examId));
    expect((await t.updateExam(examId, {'title': 'Live exam $stamp (edited)'})).str('title'), endsWith('(edited)'));
    final copy = await t.duplicateExam(examId, tuitionId: groupId);
    expect(copy.flag('is_published'), isFalse);
    await t.deleteExam(copy.str('id'));
    expect((await t.questionBank('SI unit')).first.str('question'), contains('SI unit'));

    // ── The student sits it ──────────────────────────────────────────────────
    await student.login('demo_s1', _password);
    expect(student.isStudent, isTrue);
    final myGroups = await s.tuitions();
    expect(jsonEncode(myGroups), isNot(anyOf(contains('fee'), contains('earned'), contains('wallet'))));
    await s.connections();
    await s.notifications();
    final listed = (await s.exams()).firstWhere((e) => e.str('id') == examId);
    expect(listed.flag('can_submit'), isTrue);
    expect(listed.flag('results_released'), isFalse);

    final started = await s.startExam(examId);
    final paper = started.obj('exam')!;
    expect(jsonEncode(started), isNot(anyOf(contains('correct_answer'), contains('explanation'), contains('contradiction'))));
    expect(paper.flag('is_timed'), isTrue);
    expect(paper.date('attempt_deadline'), isNotNull);
    final asked = paper.maps('mcq_data');
    expect(asked.length, 3);
    final byText = {for (final q in asked) q.str('question'): q.str('id')};
    final pictureId = asked.firstWhere((q) => q.str('image_url').isNotEmpty).str('id');
    // First right, second wrong, picture question left blank.
    final submitted = await s.submitExam(
      examId,
      answers: {byText.entries.firstWhere((e) => e.key.startsWith('If')).value: 0, byText.entries.firstWhere((e) => e.key.startsWith('The SI')).value: 0},
      text: 'Suppose it is rational…',
      images: [imageUrl],
    );
    expect(submitted.flag('results_released'), isTrue);
    await expectLater(s.submitExam(examId, answers: {}, text: 'again', images: []), throwsA(isA<ApiException>()));

    var result = await s.result(examId);
    expect(result.flag('available'), isTrue);
    var evaluated = result.obj('result')!;
    expect(evaluated.obj('summary'), {'correct': 1, 'wrong': 1, 'skipped': 1});
    expect(evaluated.number('mcq_score'), 0.75);
    expect(evaluated.obj('written')!.flag('awaiting_marking'), isTrue);
    expect(evaluated.maps('questions').firstWhere((q) => q.str('id') == pictureId).str('outcome'), 'skipped');
    expect((await s.leaderboard(examId)).maps('leaderboard'), isNotEmpty);

    // ── The tutor marks it, hides and re-publishes the results ───────────────
    final roster = await t.submissions(examId);
    final row = roster.maps('roster').firstWhere((r) => r.str('username') == 'demo_s1');
    expect(row.str('state'), 'submitted');
    final detail = await t.exam(examId);
    final schemeId = detail.maps('written_scheme').single.str('id');
    await t.grade(row.obj('submission')!.str('id'), {
      'cq_breakdown': {schemeId: 4},
      'tutor_feedback': 'Well argued.',
    });
    evaluated = (await s.result(examId)).obj('result')!;
    expect(evaluated.number('obtained_marks'), 4.75);
    expect(evaluated.str('tutor_feedback'), 'Well argued.');
    expect(evaluated.obj('written')!.maps('scheme').single.number('awarded'), 4);

    expect((await t.publishResults(examId, false)).obj('exam')!.flag('results_released'), isFalse);
    result = await s.result(examId);
    expect(result.flag('available'), isFalse);
    final hidden = jsonEncode([result, await s.exam(examId), await s.exams()]);
    expect(hidden, isNot(anyOf(contains('correct_answer'), contains('Well argued'), contains('contradiction'))));
    await expectLater(s.leaderboard(examId), throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)));
    await t.publishResults(examId, true);
    expect((await s.result(examId)).flag('available'), isTrue);

    // ── Connection requests ──────────────────────────────────────────────────
    final outsider = _newSession();
    await outsider.login('demo_s5', _password);
    final o = Repo(outsider.api);
    for (final existing in await o.connections()) {
      if (existing.str('status') == 'PENDING') await o.withdrawConnection(existing.str('id'));
    }
    final tutorId = tutor.user!.str('id');
    if ((await o.connections()).every((c) => c.str('tutor_id') != tutorId || c.str('status') == 'REJECTED')) {
      final request = await o.sendConnection(tutorId, 'Please add me.');
      expect(request.str('status'), 'PENDING');
      expect((await t.connections('PENDING')).map((c) => c.str('id')), contains(request.str('id')));
      expect((await t.rejectConnection(request.str('id'))).obj('connection')!.str('status'), 'REJECTED');
      final again = await o.sendConnection(tutorId, 'Please reconsider.');
      final accepted = await t.acceptConnection(again.str('id'), tuitionId: groupId);
      expect(accepted.obj('connection')!.str('status'), 'ACCEPTED');
      expect((await o.tuitions()).map((g) => g.str('id')), contains(groupId));
    }
    await outsider.logout();

    // ── Sessions: renewing an expired token, and signing out ─────────────────
    final tokens = await tutor.api.tokens.read();
    await tutor.api.setTokens('not-a-real-token', tokens['refresh']);
    expect((await t.tuitions()), isNotEmpty); // renewed behind the scenes
    expect((await tutor.api.tokens.read())['access'], isNot('not-a-real-token'));

    // ── Clean up, then sign out ──────────────────────────────────────────────
    await t.deleteExam(examId);
    await t.toggleStudentActive(newStudent.str('id'));
    await t.deleteTuition(groupId);
    expect((await t.tuitions()).map((g) => g.str('id')), isNot(contains(groupId)));

    final refresh = (await tutor.api.tokens.read())['refresh'];
    var expired = false;
    tutor.api.onSessionExpired = () => expired = true;
    await tutor.logout();
    expect(tutor.signedIn, isFalse);
    // The old refresh token is dead on the server, not just forgotten locally.
    await tutor.api.setTokens('not-a-real-token', refresh);
    await expectLater(t.tuitions(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
    expect(expired, isTrue);
    await student.logout();
  });

  test('a server that cannot be reached gives a readable error', () async {
    final api = ApiClient(baseUrl: 'http://127.0.0.1:9', tokens: MemoryTokenStore());
    await expectLater(
      api.get('/meta/'),
      throwsA(isA<ApiException>().having((e) => e.isOffline, 'isOffline', isTrue).having((e) => e.message, 'message', contains('Cannot reach'))),
    );
  });
}
