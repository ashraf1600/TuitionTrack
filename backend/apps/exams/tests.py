"""Tests for Exams app — Sanitization, Lifecycle, Submission, Grading & Media Upload"""
from datetime import timedelta
import io
from django.urls import reverse
from django.utils import timezone
from django.core.files.uploadedfile import SimpleUploadedFile
from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.students.models import StudentProfile
from apps.exams.models import Exam, ExamSubmission
from apps.exams.sanitizer import sanitize_exam_html

User = get_user_model()


class ExamSanitizerTests(APITestCase):
    def test_strips_malicious_scripts_and_handlers(self):
        malicious = (
            '<p>Solve equation:</p>'
            '<script>alert("xss")</script>'
            '<img src="https://example.com/math.png" onerror="stealCookie()" />'
            '<a href="javascript:alert(1)">Click me</a>'
        )
        cleaned = sanitize_exam_html(malicious)
        self.assertNotIn('<script>', cleaned)
        self.assertNotIn('alert("xss")', cleaned)
        self.assertNotIn('onerror', cleaned)
        self.assertNotIn('javascript:', cleaned)
        self.assertIn('<p>Solve equation:</p>', cleaned)
        self.assertIn('<img', cleaned)

    def test_preserves_tables_and_math_attributes(self):
        rich_html = (
            '<table>'
            '<thead><tr><th>x</th><th>f(x)</th></tr></thead>'
            '<tbody><tr><td>1</td><td><span class="math-inline" data-latex="x^2">x^2</span></td></tr></tbody>'
            '</table>'
        )
        cleaned = sanitize_exam_html(rich_html)
        self.assertIn('<table>', cleaned)
        self.assertIn('<th>x</th>', cleaned)
        self.assertIn('data-latex="x^2"', cleaned)


class ExamLifecycleTests(APITestCase):
    def setUp(self):
        # Tutor 1
        self.tutor1 = User.objects.create_user(
            username='exam_tutor1',
            password='password123',
            email='tutor1@example.com',
            role=User.Role.TUTOR,
            first_name='Exam',
            last_name='Tutor'
        )
        # Student 1 under Tutor 1
        self.student1 = User.objects.create_user(
            username='exam_student1',
            password='password123',
            email='student1@example.com',
            role=User.Role.STUDENT,
            tutor=self.tutor1,
            first_name='Student',
            last_name='One'
        )
        StudentProfile.objects.create(user=self.student1, tuition_fee=5000, cycle_length=12)

        # Tutor 2 (for multi-tenant isolation tests)
        self.tutor2 = User.objects.create_user(
            username='exam_tutor2',
            password='password123',
            email='tutor2@example.com',
            role=User.Role.TUTOR,
        )

        self.list_create_url = reverse('exam-list')

    def test_tutor_creates_exam_with_sanitized_html(self):
        self.client.force_authenticate(user=self.tutor1)
        start = timezone.now() + timedelta(hours=1)
        end = timezone.now() + timedelta(hours=3)

        payload = {
            'title': 'Calculus Midterm',
            'student_id': str(self.student1.id),
            'content_html': '<h1>Exam</h1><script>alert(1)</script><p>Find dy/dx.</p>',
            'total_marks': '100.00',
            'start_time': start.isoformat(),
            'end_time': end.isoformat(),
            'grace_period_minutes': 5,
        }
        resp = self.client.post(self.list_create_url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

        exam = Exam.objects.get(title='Calculus Midterm')
        self.assertEqual(exam.tutor, self.tutor1)
        self.assertEqual(exam.student, self.student1)
        # Verify script stripped
        self.assertNotIn('<script>', exam.content_html)
        self.assertIn('<p>Find dy/dx.</p>', exam.content_html)

    def test_cannot_schedule_exam_with_end_before_start(self):
        self.client.force_authenticate(user=self.tutor1)
        now = timezone.now()
        payload = {
            'title': 'Invalid Exam',
            'student_id': str(self.student1.id),
            'content_html': '<p>Question</p>',
            'total_marks': '50.00',
            'start_time': (now + timedelta(hours=2)).isoformat(),
            'end_time': (now + timedelta(hours=1)).isoformat(),  # invalid: before start
        }
        resp = self.client.post(self.list_create_url, payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_dynamic_status_states(self):
        now = timezone.now()
        # Scheduled exam
        exam_future = Exam.objects.create(
            tutor=self.tutor1,
            student=self.student1,
            title='Future Exam',
            content_html='<p>Q</p>',
            start_time=now + timedelta(hours=1),
            end_time=now + timedelta(hours=2),
            grace_period_minutes=5
        )
        self.assertEqual(exam_future.get_dynamic_status(), Exam.DynamicStatus.SCHEDULED)

        # Running exam
        exam_running = Exam.objects.create(
            tutor=self.tutor1,
            student=self.student1,
            title='Running Exam',
            content_html='<p>Q</p>',
            start_time=now - timedelta(minutes=30),
            end_time=now + timedelta(minutes=30),
            grace_period_minutes=5
        )
        self.assertEqual(exam_running.get_dynamic_status(), Exam.DynamicStatus.RUNNING)

        # Missed exam
        exam_missed = Exam.objects.create(
            tutor=self.tutor1,
            student=self.student1,
            title='Missed Exam',
            content_html='<p>Q</p>',
            start_time=now - timedelta(hours=3),
            end_time=now - timedelta(hours=2),
            grace_period_minutes=5
        )
        self.assertEqual(exam_missed.get_dynamic_status(), Exam.DynamicStatus.MISSED)

    def test_student_submits_exam_on_time_and_prevent_duplicate(self):
        now = timezone.now()
        exam = Exam.objects.create(
            tutor=self.tutor1,
            student=self.student1,
            title='Active Exam',
            content_html='<p>Question</p>',
            start_time=now - timedelta(minutes=30),
            end_time=now + timedelta(minutes=30),
            grace_period_minutes=5
        )
        submit_url = reverse('exam-submit', kwargs={'pk': exam.id})

        # Submit as student
        self.client.force_authenticate(user=self.student1)
        sub_payload = {
            'answers_data': {'q1': 'B', 'q2': 'C'},
            'image_urls': ['/media/uploads/2026/10/cq_sheet1.jpg']
        }
        resp = self.client.post(submit_url, sub_payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

        submission = ExamSubmission.objects.get(exam=exam, student=self.student1)
        self.assertEqual(submission.status, ExamSubmission.Status.SUBMITTED)
        self.assertEqual(submission.answers_data['q1'], 'B')

        # Attempt duplicate submission
        resp_dup = self.client.post(submit_url, sub_payload, format='json')
        self.assertEqual(resp_dup.status_code, status.HTTP_400_BAD_REQUEST)

    def test_student_late_submission_in_grace_period_marked_delayed(self):
        now = timezone.now()
        # Ended 2 minutes ago, but within 5 minute grace period
        exam = Exam.objects.create(
            tutor=self.tutor1,
            student=self.student1,
            title='Grace Period Exam',
            content_html='<p>Question</p>',
            start_time=now - timedelta(minutes=60),
            end_time=now - timedelta(minutes=2),
            grace_period_minutes=5
        )
        submit_url = reverse('exam-submit', kwargs={'pk': exam.id})

        self.client.force_authenticate(user=self.student1)
        resp = self.client.post(submit_url, {'answers_data': {'q1': 'A'}}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

        submission = ExamSubmission.objects.get(exam=exam, student=self.student1)
        self.assertEqual(submission.status, ExamSubmission.Status.DELAYED)

    def test_submission_rejected_after_grace_period_expired(self):
        now = timezone.now()
        exam = Exam.objects.create(
            tutor=self.tutor1,
            student=self.student1,
            title='Expired Exam',
            content_html='<p>Question</p>',
            start_time=now - timedelta(minutes=60),
            end_time=now - timedelta(minutes=10),
            grace_period_minutes=5
        )
        submit_url = reverse('exam-submit', kwargs={'pk': exam.id})

        self.client.force_authenticate(user=self.student1)
        resp = self.client.post(submit_url, {'answers_data': {'q1': 'A'}}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_tutor_grades_submission(self):
        now = timezone.now()
        exam = Exam.objects.create(
            tutor=self.tutor1,
            student=self.student1,
            title='Exam for Grading',
            content_html='<p>Q</p>',
            total_marks=50.00,
            start_time=now - timedelta(minutes=60),
            end_time=now - timedelta(minutes=10),
        )
        submission = ExamSubmission.objects.create(
            exam=exam,
            student=self.student1,
            submitted_at=now - timedelta(minutes=15),
            answers_data={'q1': 'A'},
            status=ExamSubmission.Status.SUBMITTED
        )

        grade_url = reverse('grade-submission', kwargs={'pk': submission.id})

        # Tutor 2 cannot grade (multi-tenancy check)
        self.client.force_authenticate(user=self.tutor2)
        resp_unauth = self.client.patch(grade_url, {'obtained_marks': '45.00'}, format='json')
        self.assertEqual(resp_unauth.status_code, status.HTTP_404_NOT_FOUND)

        # Tutor 1 grades successfully
        self.client.force_authenticate(user=self.tutor1)
        resp_grade = self.client.patch(
            grade_url,
            {'obtained_marks': '42.50', 'tutor_feedback': 'Well explained!'},
            format='json'
        )
        self.assertEqual(resp_grade.status_code, status.HTTP_200_OK)

        submission.refresh_from_db()
        self.assertTrue(submission.is_graded)
        self.assertEqual(float(submission.obtained_marks), 42.50)
        self.assertEqual(submission.tutor_feedback, 'Well explained!')
        self.assertIsNotNone(submission.graded_at)

    def test_media_upload_endpoint(self):
        upload_url = reverse('media-upload')
        self.client.force_authenticate(user=self.student1)

        # Valid image upload
        image_content = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' + b'mock png content'
        test_file = SimpleUploadedFile('cq_answer.png', image_content, content_type='image/png')
        resp = self.client.post(upload_url, {'file': test_file}, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertIn('url', resp.data)
        self.assertTrue(resp.data['url'].endswith('.png'))

        # Disallowed file format (.exe)
        bad_file = SimpleUploadedFile('virus.exe', b'bad', content_type='application/x-msdownload')
        resp_bad = self.client.post(upload_url, {'file': bad_file}, format='multipart')
        self.assertEqual(resp_bad.status_code, status.HTTP_400_BAD_REQUEST)

    def test_tuition_batch_mcq_auto_grading_and_leaderboard(self):
        from apps.students.models import Tuition, TuitionEnrollment

        # Create another student under tutor1
        student2 = User.objects.create_user(
            username='exam_student2',
            password='password123',
            email='student2@example.com',
            role=User.Role.STUDENT,
            tutor=self.tutor1,
            first_name='Second',
            last_name='Student'
        )

        # Create tuition
        tuition = Tuition.objects.create(
            tutor=self.tutor1,
            title='Physics Batch Alpha',
            subject='Physics',
            routine=[{'day': 'Monday', 'start_time': '16:00', 'end_time': '17:30'}],
            total_fee=5000.00,
            cycle_length=12
        )
        TuitionEnrollment.objects.create(tuition=tuition, student=self.student1)
        TuitionEnrollment.objects.create(tuition=tuition, student=student2)

        # Create MCQ Exam for this tuition
        mcqs = [
            {
                'id': 'mcq-1',
                'question': 'What is the SI unit of force?',
                'options': ['Joule', 'Newton', 'Watt', 'Pascal'],
                'correct_answer': 1,
                'explanation': 'Newton is SI unit of force.',
                'points': 5.0
            },
            {
                'id': 'mcq-2',
                'question': 'What is the unit of energy?',
                'options': ['Joule', 'Newton', 'Volt', 'Ampere'],
                'correct_answer': 0,
                'explanation': 'Joule is unit of energy.',
                'points': 5.0
            }
        ]

        now = timezone.now()
        exam = Exam.objects.create(
            tutor=self.tutor1,
            tuition=tuition,
            title='Mechanics MCQ Assessment',
            exam_type=Exam.ExamType.MCQ,
            total_marks=10.00,
            start_time=now - timedelta(minutes=10),
            end_time=now + timedelta(minutes=50),
            grace_period_minutes=5,
            mcq_data=mcqs,
            is_published=True,
            is_results_published=True
        )

        submit_url = reverse('exam-submit', kwargs={'pk': exam.id})

        # Student 1 gets both correct: score = 10.0
        self.client.force_authenticate(user=self.student1)
        resp1 = self.client.post(submit_url, {
            'answers_data': {'mcq-1': 1, 'mcq-2': 0},
            'image_urls': []
        }, format='json')
        self.assertEqual(resp1.status_code, status.HTTP_201_CREATED)
        # Marks withheld from student during active exam window per P0 security invariant
        self.assertIsNone(resp1.data['submission']['mcq_score'])
        sub1 = ExamSubmission.objects.get(exam=exam, student=self.student1)
        self.assertEqual(float(sub1.mcq_score), 10.0)

        # Student 2 gets only 1 correct: score = 5.0
        self.client.force_authenticate(user=student2)
        resp2 = self.client.post(submit_url, {
            'answers_data': {'mcq-1': 1, 'mcq-2': 2},
            'image_urls': []
        }, format='json')
        self.assertEqual(resp2.status_code, status.HTTP_201_CREATED)
        self.assertIsNone(resp2.data['submission']['mcq_score'])
        sub2 = ExamSubmission.objects.get(exam=exam, student=student2)
        self.assertEqual(float(sub2.mcq_score), 5.0)

        # Fetch Leaderboard
        leaderboard_url = reverse('exam-leaderboard', kwargs={'pk': exam.id})
        self.client.force_authenticate(user=self.tutor1)
        resp_lb = self.client.get(leaderboard_url)
        self.assertEqual(resp_lb.status_code, status.HTTP_200_OK)

        lb = resp_lb.data['leaderboard']
        self.assertEqual(len(lb), 2)
        # Student 1 is Rank 1 with 10.0 marks (100.0%)
        self.assertEqual(lb[0]['rank'], 1)
        self.assertEqual(lb[0]['student_name'], self.student1.get_full_name())
        self.assertEqual(lb[0]['obtained_marks'], 10.0)
        self.assertEqual(lb[0]['percentage'], 100.0)

        # Student 2 is Rank 2 with 5.0 marks (50.0%)
        self.assertEqual(lb[1]['rank'], 2)
        self.assertEqual(lb[1]['student_name'], student2.get_full_name())
        self.assertEqual(lb[1]['obtained_marks'], 5.0)
        self.assertEqual(lb[1]['percentage'], 50.0)



class ExamWorkflowUpgradeTests(APITestCase):
    """Drafts, editing, timed attempts, late work, negative marking, roster and grading."""

    def setUp(self):
        from apps.students.models import Tuition
        from apps.students.services import enroll_student
        self.tutor = User.objects.create_user(username='x_tutor', password='password123', role=User.Role.TUTOR)
        self.s1 = User.objects.create_user(username='x_s1', password='password123', role=User.Role.STUDENT, tutor=self.tutor, email='s1@example.com')
        self.s2 = User.objects.create_user(username='x_s2', password='password123', role=User.Role.STUDENT, tutor=self.tutor)
        self.tuition = Tuition.objects.create(tutor=self.tutor, title='Group X', total_fee=1000, cycle_length=4)
        enroll_student(self.tuition, self.s1)
        enroll_student(self.tuition, self.s2)
        self.now = timezone.now()

    def _payload(self, **extra):
        data = {
            'title': 'Quiz', 'exam_type': 'HYBRID', 'category': 'EXAM', 'tuition_id': str(self.tuition.id),
            'total_marks': '10', 'content_html': '<p>Explain.</p>',
            'start_time': (self.now - timedelta(minutes=10)).isoformat(),
            'end_time': (self.now + timedelta(hours=2)).isoformat(),
            'duration_minutes': None,
            'mcq_data': [
                {'question': 'q1', 'options': ['a', 'b', 'c', 'd'], 'correct_answer': 1, 'points': 2},
                {'question': 'q2', 'options': ['a', 'b', 'c', 'd'], 'correct_answer': 0, 'points': 2},
            ],
        }
        data.update(extra)
        return data

    def _create(self, **extra):
        self.client.force_authenticate(user=self.tutor)
        resp = self.client.post(reverse('exam-list'), self._payload(**extra), format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        return resp.data['exam']

    def _student_rows(self, user):
        self.client.force_authenticate(user=user)
        data = self.client.get(reverse('exam-list')).data
        return data if isinstance(data, list) else data['results']

    def test_draft_is_hidden_then_published_and_emailed(self):
        from django.core import mail
        exam = self._create(is_published=False)
        self.assertEqual(len(mail.outbox), 0)
        self.assertEqual(self._student_rows(self.s1), [])

        self.client.force_authenticate(user=self.tutor)
        rows = self.client.get(reverse('exam-list')).data
        rows = rows if isinstance(rows, list) else rows['results']
        self.assertEqual(rows[0]['dynamic_status'], 'Draft')

        resp = self.client.patch(reverse('exam-detail', kwargs={'pk': exam['id']}), {'is_published': True}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        self.assertEqual(len(mail.outbox), 1)
        self.assertEqual(mail.outbox[0].to, ['s1@example.com'])
        self.assertEqual(len(self._student_rows(self.s1)), 1)

    def test_edit_regrades_and_delete(self):
        exam = self._create()
        q = exam['mcq_data']
        self.client.force_authenticate(user=self.s1)
        sub = self.client.post(reverse('exam-submit', kwargs={'pk': exam['id']}), {'answers_data': {q[0]['id']: '1', q[1]['id']: '1'}}, format='json')
        self.assertEqual(sub.status_code, status.HTTP_201_CREATED, sub.data)
        submission = ExamSubmission.objects.get(exam_id=exam['id'], student=self.s1)
        self.assertEqual(float(submission.mcq_score), 2.0)

        # Tutor fixes the key of q2 (was A, should be B) -> the submission is re-marked.
        self.client.force_authenticate(user=self.tutor)
        fixed = [dict(q[0]), dict(q[1], correct_answer=1)]
        resp = self.client.patch(reverse('exam-detail', kwargs={'pk': exam['id']}), {'title': 'Quiz (fixed)', 'mcq_data': fixed}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        submission.refresh_from_db()
        self.assertEqual(float(submission.mcq_score), 4.0)

        self.assertEqual(self.client.delete(reverse('exam-detail', kwargs={'pk': exam['id']})).status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(Exam.objects.filter(id=exam['id']).exists())

    def test_negative_marking(self):
        exam = self._create(negative_marks_per_wrong='0.5')
        q = exam['mcq_data']
        self.client.force_authenticate(user=self.s1)
        self.client.post(reverse('exam-submit', kwargs={'pk': exam['id']}), {'answers_data': {q[0]['id']: '1', q[1]['id']: '3'}}, format='json')
        self.assertEqual(float(ExamSubmission.objects.get(exam_id=exam['id'], student=self.s1).mcq_score), 1.5)
        # Blank answers cost nothing.
        self.client.force_authenticate(user=self.s2)
        self.client.post(reverse('exam-submit', kwargs={'pk': exam['id']}), {'answers_data': {q[0]['id']: '1'}, 'text_answer': 'typed'}, format='json')
        s2 = ExamSubmission.objects.get(exam_id=exam['id'], student=self.s2)
        self.assertEqual(float(s2.mcq_score), 2.0)
        self.assertEqual(s2.text_answer, 'typed')

    def test_timed_exam_hides_questions_until_start_and_enforces_personal_timer(self):
        from apps.exams.models import ExamAttempt
        exam = self._create(duration_minutes=30)
        self.client.force_authenticate(user=self.s1)
        detail = self.client.get(reverse('exam-detail', kwargs={'pk': exam['id']})).data
        self.assertTrue(detail['requires_start'])
        self.assertEqual(detail['mcq_data'], [])
        self.assertEqual(detail['content_html'], '')

        started = self.client.post(reverse('exam-start', kwargs={'pk': exam['id']}))
        self.assertEqual(started.status_code, status.HTTP_200_OK, started.data)
        self.assertEqual(len(started.data['exam']['mcq_data']), 2)
        self.assertNotIn('correct_answer', started.data['exam']['mcq_data'][0])
        first_start = started.data['started_at']
        # Starting again never restarts the clock.
        self.assertEqual(self.client.post(reverse('exam-start', kwargs={'pk': exam['id']})).data['started_at'], first_start)

        # 30 min timer + 5 min grace ran out 10 minutes ago -> refused, although the exam window is still open.
        ExamAttempt.objects.filter(exam_id=exam['id'], student=self.s1).update(started_at=self.now - timedelta(minutes=45))
        late = self.client.post(reverse('exam-submit', kwargs={'pk': exam['id']}), {'answers_data': {}}, format='json')
        self.assertEqual(late.status_code, status.HTTP_400_BAD_REQUEST)

        # Inside the grace period it is accepted but flagged.
        ExamAttempt.objects.filter(exam_id=exam['id'], student=self.s1).update(started_at=self.now - timedelta(minutes=32))
        ok = self.client.post(reverse('exam-submit', kwargs={'pk': exam['id']}), {'answers_data': {}}, format='json')
        self.assertEqual(ok.status_code, status.HTTP_201_CREATED, ok.data)
        self.assertEqual(ExamSubmission.objects.get(exam_id=exam['id'], student=self.s1).status, 'DELAYED')

    def test_assignment_accepts_late_work_until_cutoff(self):
        exam = self._create(category='ASSIGNMENT', exam_type='CQ', mcq_data=[], duration_minutes=45,
                            late_submission_until=(self.now + timedelta(days=3)).isoformat())
        self.assertIsNone(Exam.objects.get(id=exam['id']).duration_minutes)
        # Deadline (and grace) passed an hour ago, late window still open.
        Exam.objects.filter(id=exam['id']).update(end_time=self.now - timedelta(hours=1))
        rows = self._student_rows(self.s1)
        self.assertEqual(rows[0]['dynamic_status'], 'Late')
        self.assertTrue(rows[0]['can_submit'])
        resp = self.client.post(reverse('exam-submit', kwargs={'pk': exam['id']}), {'text_answer': 'my essay'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        self.assertEqual(ExamSubmission.objects.get(exam_id=exam['id'], student=self.s1).status, 'DELAYED')

        # After the cutoff it is refused.
        Exam.objects.filter(id=exam['id']).update(late_submission_until=self.now - timedelta(minutes=1))
        self.client.force_authenticate(user=self.s2)
        self.assertEqual(
            self.client.post(reverse('exam-submit', kwargs={'pk': exam['id']}), {'text_answer': 'x'}, format='json').status_code,
            status.HTTP_400_BAD_REQUEST,
        )

    def test_roster_and_written_marks_grading(self):
        exam = self._create()
        q = exam['mcq_data']
        self.client.force_authenticate(user=self.s1)
        self.client.post(reverse('exam-submit', kwargs={'pk': exam['id']}), {'answers_data': {q[0]['id']: '1'}}, format='json')

        self.client.force_authenticate(user=self.tutor)
        data = self.client.get(reverse('exam-submissions', kwargs={'pk': exam['id']})).data
        self.assertEqual(data['assigned_count'], 2)
        states = {row['username']: row['state'] for row in data['roster']}
        self.assertEqual(states, {'x_s1': 'submitted', 'x_s2': 'not_submitted'})

        sub_id = next(r for r in data['roster'] if r['username'] == 'x_s1')['submission']['id']
        graded = self.client.patch(reverse('grade-submission', kwargs={'pk': sub_id}), {'cq_score': '5', 'tutor_feedback': 'Good'}, format='json')
        self.assertEqual(graded.status_code, status.HTTP_200_OK, graded.data)
        self.assertEqual(float(graded.data['submission']['obtained_marks']), 7.0)
        self.assertEqual(float(graded.data['submission']['cq_score']), 5.0)

        # Leaderboard read no longer writes "missed" rows.
        self.client.get(reverse('exam-leaderboard', kwargs={'pk': exam['id']}))
        self.assertEqual(ExamSubmission.objects.filter(exam_id=exam['id']).count(), 1)

    def test_shuffle_is_stable_per_student(self):
        many = [{'question': f'q{i}', 'options': ['a', 'b'], 'correct_answer': 0, 'points': 1} for i in range(8)]
        exam = self._create(mcq_data=many, shuffle_questions=True)
        url = reverse('exam-detail', kwargs={'pk': exam['id']})
        self.client.force_authenticate(user=self.s1)
        first = [q['question'] for q in self.client.get(url).data['mcq_data']]
        again = [q['question'] for q in self.client.get(url).data['mcq_data']]
        self.assertEqual(first, again)
        self.assertEqual(sorted(first), sorted(f'q{i}' for i in range(8)))


class ExamCreateRegressionTests(APITestCase):
    """What the exam form actually sends: both id names, and an uploaded image in the paper."""

    def setUp(self):
        from apps.students.models import Tuition
        self.tutor = User.objects.create_user(username='reg_tutor', password='password123', role=User.Role.TUTOR)
        self.tuition = Tuition.objects.create(tutor=self.tutor, title='Reg group', total_fee=1000, cycle_length=4)
        self.client.force_authenticate(user=self.tutor)

    def test_create_with_both_tuition_id_and_batch_id_and_an_image(self):
        now = timezone.now()
        image = '<p><img src="/media/uploads/2026/10/abc_note.jpg" alt="note.jpg"></p>'
        resp = self.client.post(reverse('exam-list'), {
            'title': 'Polynomial', 'category': 'EXAM', 'exam_type': 'HYBRID',
            'student_id': None, 'batch_id': str(self.tuition.id), 'tuition_id': str(self.tuition.id),
            'content_html': image, 'total_marks': 100,
            'mcq_data': [{'id': 'mcq-1', 'question': 'If \\(P(1)\\) is', 'options': ['-4', '-3', '-2', '0'], 'correct_answer': 0, 'points': 1, 'marks': 1}],
            'written_scheme': [{'label': 'Q1', 'marks': 10}],
            'start_time': (now + timedelta(minutes=2)).isoformat(), 'end_time': (now + timedelta(hours=1)).isoformat(),
            'duration_minutes': None, 'is_published': True,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        exam = Exam.objects.get(id=resp.data['exam']['id'])
        self.assertEqual(exam.tuition_id, self.tuition.id)
        # The uploaded image survives sanitizing (which runs in the serializer and again on save).
        self.assertEqual(exam.content_html, image)

    def test_sanitizer_keeps_media_urls_and_is_idempotent(self):
        html = '<p><img src="/media/uploads/a.jpg" alt="a"> <a href="/media/uploads/b.pdf">b</a></p>'
        once = sanitize_exam_html(html)
        self.assertIn('src="/media/uploads/a.jpg"', once)
        self.assertIn('href="/media/uploads/b.pdf"', once)
        self.assertNotIn('src="src=', once)
        self.assertEqual(sanitize_exam_html(once), once)
