"""
Result publication (IMMEDIATE / MANUAL / SCHEDULED), the guarantee that the
answer key never reaches a student before results are released, the evaluated
result page, and picture questions.
"""
import json
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.exams.models import Exam, ExamSubmission
from apps.exams.serializers import ExamDetailSerializer, ExamResultSerializer, StudentExamSerializer
from apps.students.models import Tuition
from apps.students.services import enroll_student

User = get_user_model()

SECRET_EXPLANATION = 'Because Dhaka is the capital (SECRET-EXPLANATION)'
SECRET_SOLUTION = '<p>SECRET-MODEL-SOLUTION</p>'
ANSWER_WORDS = ('correct_answer', 'explanation', 'SECRET-EXPLANATION', 'SECRET-MODEL-SOLUTION', 'solution_html', 'solution_media_url')


class ResultPublicationTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(username='rp_tutor', password='x', role=User.Role.TUTOR)
        self.student = User.objects.create_user(username='rp_s1', password='x', role=User.Role.STUDENT, tutor=self.tutor)
        self.late_student = User.objects.create_user(username='rp_s2', password='x', role=User.Role.STUDENT, tutor=self.tutor)
        self.group = Tuition.objects.create(tutor=self.tutor, title='Group', total_fee=1000, cycle_length=4)
        enroll_student(self.group, self.student)
        enroll_student(self.group, self.late_student)
        self.now = timezone.now()

    def make_exam(self, **extra):
        self.client.force_authenticate(user=self.tutor)
        payload = {
            'title': 'Quiz', 'exam_type': 'MCQ', 'tuition_id': str(self.group.id), 'total_marks': '10',
            'start_time': (self.now - timedelta(minutes=5)).isoformat(),
            'end_time': (self.now + timedelta(hours=1)).isoformat(),
            'solution_html': SECRET_SOLUTION,
            'negative_marks_per_wrong': '0.5',
            'mcq_data': [
                {'question': 'Capital of BD?', 'options': ['Dhaka', 'Khulna', 'Sylhet', 'Bogura'], 'correct_answer': 0,
                 'points': 2, 'explanation': SECRET_EXPLANATION, 'smuggled_answer': 'A'},
                {'question': r'Value of \(2^3\)?', 'options': ['6', '8', '9', '16'], 'correct_answer': 'B', 'points': 3},
                {'question': '', 'image_url': '/media/uploads/2026/10/graph.png', 'options': ['A', 'B', 'C', 'D'], 'correct_answer': 3, 'points': 1},
            ],
        }
        payload.update(extra)
        resp = self.client.post(reverse('exam-list'), payload, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        return resp.data['exam']

    def submit(self, exam, student, answers):
        self.client.force_authenticate(user=student)
        resp = self.client.post(reverse('exam-submit', kwargs={'pk': exam['id']}), {'answers_data': answers}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        return resp

    def assert_no_answers(self, response):
        body = json.dumps(response.data, default=str)
        for word in ANSWER_WORDS:
            self.assertNotIn(word, body, f'"{word}" leaked to a student')
        self.assertNotIn('smuggled_answer', body)

    def student_views(self, exam, student):
        """Every endpoint a student can read an exam through."""
        self.client.force_authenticate(user=student)
        return [
            self.client.get(reverse('exam-detail', kwargs={'pk': exam['id']})),
            self.client.get(reverse('exam-list')),
            self.client.get(reverse('exam-result', kwargs={'pk': exam['id']})),
        ]

    # ── storage ──────────────────────────────────────────────────────────────

    def test_questions_are_stored_in_a_fixed_shape(self):
        exam = self.make_exam(result_publish_mode='MANUAL')
        stored = Exam.objects.get(id=exam['id']).mcq_data
        self.assertEqual(
            sorted(stored[0].keys()),
            ['correct_answer', 'explanation', 'id', 'image_url', 'marks', 'options', 'points', 'question'],
        )
        self.assertEqual(stored[1]['correct_answer'], 1)          # letter normalised to an index
        self.assertEqual(stored[2]['image_url'], '/media/uploads/2026/10/graph.png')
        self.assertEqual(stored[2]['question'], '')                # a picture can be the whole question

    def test_question_validation_on_publish(self):
        self.client.force_authenticate(user=self.tutor)
        base = {
            'title': 'Bad', 'exam_type': 'MCQ', 'tuition_id': str(self.group.id), 'total_marks': '10',
            'start_time': (self.now + timedelta(minutes=5)).isoformat(), 'end_time': (self.now + timedelta(hours=1)).isoformat(),
        }
        bad_questions = [
            {'question': '', 'options': ['a', 'b'], 'correct_answer': 0},                                      # no text, no picture
            {'question': 'q', 'options': ['a', ''], 'correct_answer': 0},                                      # empty option
            {'question': 'q', 'options': ['a', 'b'], 'correct_answer': 0, 'image_url': 'javascript:alert(1)'},  # unsafe picture
            {'question': 'q', 'options': ['a', 'b'], 'correct_answer': 0, 'image_url': 'data:image/png;base64,AAAA'},
            {'question': 'q', 'options': ['a', 'b'], 'correct_answer': 0, 'points': 0},
            {'question': 'q', 'options': ['a', 'b', 'c', 'd', 'e', 'f'], 'correct_answer': 0},
            {'question': 'q', 'options': ['a', 'b']},                                                         # no answer
        ]
        for question in bad_questions:
            resp = self.client.post(reverse('exam-list'), {**base, 'mcq_data': [question]}, format='json')
            self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST, question)
        # A draft may be unfinished (but never with an unsafe picture address).
        draft = self.client.post(reverse('exam-list'), {**base, 'is_published': False, 'mcq_data': [bad_questions[1], bad_questions[6]]}, format='json')
        self.assertEqual(draft.status_code, status.HTTP_201_CREATED, draft.data)
        unsafe = self.client.post(reverse('exam-list'), {**base, 'is_published': False, 'mcq_data': [bad_questions[2]]}, format='json')
        self.assertEqual(unsafe.status_code, status.HTTP_400_BAD_REQUEST)

    # ── the answer key never leaks ───────────────────────────────────────────

    def test_manual_mode_hides_everything_until_published(self):
        exam = self.make_exam(result_publish_mode='MANUAL')
        self.assertFalse(Exam.objects.get(id=exam['id']).is_results_published)
        q = exam['mcq_data']

        # Before submitting: questions only.
        self.client.force_authenticate(user=self.student)
        started = self.client.post(reverse('exam-start', kwargs={'pk': exam['id']}))
        self.assert_no_answers(started)
        detail = self.client.get(reverse('exam-detail', kwargs={'pk': exam['id']}))
        self.assertEqual(sorted(detail.data['mcq_data'][0].keys()), ['id', 'image_url', 'options', 'points', 'question'])
        self.assertEqual(detail.data['mcq_data'][2]['image_url'], '/media/uploads/2026/10/graph.png')

        # After submitting: still nothing, and the marks are blank.
        submitted = self.submit(exam, self.student, {q[0]['id']: 0, q[1]['id']: 0})
        self.assert_no_answers(submitted)
        self.assertFalse(submitted.data['results_released'])
        self.assertIsNone(submitted.data['submission']['mcq_score'])
        self.assertIsNone(submitted.data['submission']['obtained_marks'])
        for resp in self.student_views(exam, self.student):
            self.assertEqual(resp.status_code, status.HTTP_200_OK)
            self.assert_no_answers(resp)
        result = self.client.get(reverse('exam-result', kwargs={'pk': exam['id']}))
        self.assertEqual(result.data, {
            'available': False, 'submitted': True, 'mode': 'MANUAL', 'publish_at': None,
            'submitted_at': result.data['submitted_at'],
        })
        self.assertEqual(self.client.get(reverse('exam-leaderboard', kwargs={'pk': exam['id']})).status_code, status.HTTP_403_FORBIDDEN)

        # The serializer itself refuses, whoever calls it.
        submission = ExamSubmission.objects.get(exam_id=exam['id'], student=self.student)
        request = detail.wsgi_request
        request.user = self.student
        with self.assertRaises(Exception):
            ExamResultSerializer(submission, context={'request': request}).data

        # Tutor publishes: the evaluated paper appears.
        self.client.force_authenticate(user=self.tutor)
        published = self.client.post(reverse('exam-publish-results', kwargs={'pk': exam['id']}), {'publish': True}, format='json')
        self.assertEqual(published.status_code, status.HTTP_200_OK, published.data)
        self.assertTrue(published.data['exam']['results_released'])

        self.client.force_authenticate(user=self.student)
        result = self.client.get(reverse('exam-result', kwargs={'pk': exam['id']}))
        self.assertTrue(result.data['available'])
        paper = result.data['result']
        self.assertEqual(paper['summary'], {'correct': 1, 'wrong': 1, 'skipped': 1})
        self.assertEqual([x['outcome'] for x in paper['questions']], ['correct', 'wrong', 'skipped'])
        self.assertEqual([x['correct_answer'] for x in paper['questions']], [0, 1, 3])
        self.assertEqual([x['selected'] for x in paper['questions']], [0, 0, None])
        self.assertEqual([x['awarded'] for x in paper['questions']], [2.0, -0.5, 0.0])
        self.assertEqual(paper['mcq_score'], 1.5)
        self.assertEqual(paper['obtained_marks'], 1.5)
        self.assertEqual(paper['mcq_total'], 6.0)
        self.assertEqual(paper['questions'][0]['explanation'], SECRET_EXPLANATION)
        self.assertIn('SECRET-MODEL-SOLUTION', paper['solution_html'])
        self.assertEqual(self.client.get(reverse('exam-leaderboard', kwargs={'pk': exam['id']})).status_code, status.HTTP_200_OK)
        listed = next(e for e in self.client.get(reverse('exam-list')).data['results'] if e['id'] == exam['id'])
        self.assertTrue(listed['results_released'])
        self.assertEqual(float(listed['my_result']['obtained_marks']), 1.5)

        # Even with results out, the exam detail a student loads never carries the key,
        # and a classmate who has not submitted yet gets nothing at all.
        self.assert_no_answers(self.client.get(reverse('exam-detail', kwargs={'pk': exam['id']})))
        for resp in self.student_views(exam, self.late_student):
            self.assert_no_answers(resp)
        self.assertFalse(self.client.get(reverse('exam-result', kwargs={'pk': exam['id']})).data['available'])

        # Tutor takes the results back.
        self.client.force_authenticate(user=self.tutor)
        self.client.post(reverse('exam-publish-results', kwargs={'pk': exam['id']}), {'publish': False}, format='json')
        for resp in self.student_views(exam, self.student):
            self.assert_no_answers(resp)

    def test_immediate_mode_releases_to_each_student_on_submission(self):
        exam = self.make_exam(result_publish_mode='IMMEDIATE')
        q = exam['mcq_data']
        for resp in self.student_views(exam, self.student):
            self.assert_no_answers(resp)

        submitted = self.submit(exam, self.student, {q[0]['id']: 0, q[1]['id']: 1, q[2]['id']: 3})
        self.assertTrue(submitted.data['results_released'])
        self.assertEqual(float(submitted.data['submission']['obtained_marks']), 6.0)
        result = self.client.get(reverse('exam-result', kwargs={'pk': exam['id']}))
        self.assertTrue(result.data['available'])
        self.assertEqual(result.data['result']['percentage'], 60.0)

        # The other student is still sitting the exam and must not get the key.
        for resp in self.student_views(exam, self.late_student):
            self.assert_no_answers(resp)

    def test_scheduled_mode_follows_the_clock(self):
        publish_at = self.now + timedelta(hours=3)
        exam = self.make_exam(result_publish_mode='SCHEDULED', publish_time=publish_at.isoformat())
        q = exam['mcq_data']
        self.submit(exam, self.student, {q[0]['id']: 0})
        pending = self.client.get(reverse('exam-result', kwargs={'pk': exam['id']}))
        self.assertFalse(pending.data['available'])
        self.assertEqual(pending.data['mode'], 'SCHEDULED')
        self.assertEqual(pending.data['publish_at'], publish_at)
        self.assert_no_answers(pending)

        Exam.objects.filter(id=exam['id']).update(publish_time=self.now - timedelta(minutes=1))
        released = self.client.get(reverse('exam-result', kwargs={'pk': exam['id']}))
        self.assertTrue(released.data['available'])

    def test_scheduled_without_a_time_means_when_the_exam_closes(self):
        exam = self.make_exam(result_publish_mode='SCHEDULED')
        q = exam['mcq_data']
        self.submit(exam, self.student, {q[0]['id']: 0})
        pending = self.client.get(reverse('exam-result', kwargs={'pk': exam['id']}))
        self.assertFalse(pending.data['available'])
        self.assertIsNotNone(pending.data['publish_at'])

        Exam.objects.filter(id=exam['id']).update(end_time=self.now - timedelta(minutes=30))
        self.assertTrue(self.client.get(reverse('exam-result', kwargs={'pk': exam['id']})).data['available'])

    def test_publication_settings_validation_and_legacy_switch(self):
        self.client.force_authenticate(user=self.tutor)
        url = reverse('exam-list')
        base = {
            'title': 'T', 'exam_type': 'CQ', 'tuition_id': str(self.group.id), 'total_marks': '10', 'content_html': '<p>Q</p>',
            'start_time': (self.now + timedelta(minutes=5)).isoformat(), 'end_time': (self.now + timedelta(hours=1)).isoformat(),
        }
        early = self.client.post(url, {**base, 'result_publish_mode': 'SCHEDULED', 'publish_time': (self.now - timedelta(days=1)).isoformat()}, format='json')
        self.assertEqual(early.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.client.post(url, {**base, 'result_publish_mode': 'WHENEVER'}, format='json').status_code, status.HTTP_400_BAD_REQUEST)

        # A time is only kept for SCHEDULED.
        immediate = self.client.post(url, {**base, 'result_publish_mode': 'IMMEDIATE', 'publish_time': (self.now + timedelta(days=1)).isoformat()}, format='json')
        self.assertIsNone(Exam.objects.get(id=immediate.data['exam']['id']).publish_time)

        # Older clients that only send the switch keep their old meaning.
        off = Exam.objects.get(id=self.client.post(url, {**base, 'is_results_published': False}, format='json').data['exam']['id'])
        on = Exam.objects.get(id=self.client.post(url, {**base, 'is_results_published': True}, format='json').data['exam']['id'])
        self.assertEqual((off.result_publish_mode, off.is_results_published), ('MANUAL', False))
        self.assertEqual((on.result_publish_mode, on.publish_time), ('SCHEDULED', None))

        # Switching an exam to MANUAL starts it unpublished; saving it again keeps a published state.
        detail = reverse('exam-detail', kwargs={'pk': on.id})
        self.client.patch(detail, {'result_publish_mode': 'MANUAL'}, format='json')
        on.refresh_from_db()
        self.assertFalse(on.is_results_published)
        self.client.post(reverse('exam-publish-results', kwargs={'pk': on.id}), {'publish': True}, format='json')
        self.client.patch(detail, {'result_publish_mode': 'MANUAL', 'title': 'Renamed'}, format='json')
        on.refresh_from_db()
        self.assertTrue(on.is_results_published)

    def test_only_the_owning_tutor_can_publish_results(self):
        exam = self.make_exam(result_publish_mode='MANUAL')
        url = reverse('exam-publish-results', kwargs={'pk': exam['id']})
        self.client.force_authenticate(user=self.student)
        self.assertEqual(self.client.post(url, {'publish': True}, format='json').status_code, status.HTTP_403_FORBIDDEN)
        other = User.objects.create_user(username='rp_other', password='x', role=User.Role.TUTOR)
        self.client.force_authenticate(user=other)
        self.assertEqual(self.client.post(url, {'publish': True}, format='json').status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(Exam.objects.get(id=exam['id']).is_results_published)
        # A tutor cannot read a student result endpoint either.
        self.client.force_authenticate(user=self.tutor)
        self.assertEqual(self.client.get(reverse('exam-result', kwargs={'pk': exam['id']})).status_code, status.HTTP_403_FORBIDDEN)

    def test_written_part_awaits_marking_in_the_result(self):
        exam = self.make_exam(
            exam_type='HYBRID', result_publish_mode='IMMEDIATE', content_html='<p>Explain.</p>',
            written_scheme=[{'label': 'Q1', 'marks': 4}],
        )
        q = exam['mcq_data']
        self.client.force_authenticate(user=self.student)
        self.client.post(reverse('exam-submit', kwargs={'pk': exam['id']}), {'answers_data': {q[0]['id']: 0}, 'text_answer': 'my answer'}, format='json')
        paper = self.client.get(reverse('exam-result', kwargs={'pk': exam['id']})).data['result']
        self.assertTrue(paper['written']['awaiting_marking'])
        self.assertEqual(paper['written']['text_answer'], 'my answer')
        self.assertEqual(paper['written']['scheme'][0]['awarded'], None)
        self.assertFalse(paper['is_graded'])

        submission = ExamSubmission.objects.get(exam_id=exam['id'], student=self.student)
        self.client.force_authenticate(user=self.tutor)
        scheme_id = exam['written_scheme'][0]['id']
        graded = self.client.patch(reverse('grade-submission', kwargs={'pk': submission.id}), {'cq_breakdown': {scheme_id: 3}, 'tutor_feedback': 'Good'}, format='json')
        self.assertEqual(graded.status_code, status.HTTP_200_OK, graded.data)

        self.client.force_authenticate(user=self.student)
        paper = self.client.get(reverse('exam-result', kwargs={'pk': exam['id']})).data['result']
        self.assertFalse(paper['written']['awaiting_marking'])
        self.assertEqual(paper['written']['scheme'][0]['awarded'], 3)
        self.assertEqual(paper['obtained_marks'], 5.0)
        self.assertEqual(paper['tutor_feedback'], 'Good')

    def test_student_serializer_has_no_answer_fields_by_construction(self):
        fields = set(StudentExamSerializer().fields)
        self.assertFalse(fields & {'solution_html', 'solution_media_url', 'submissions', 'is_results_published'})
        # The tutor serializer, if ever handed a student request by mistake, still strips the key.
        exam = self.make_exam(result_publish_mode='IMMEDIATE')
        self.submit(exam, self.student, {exam['mcq_data'][0]['id']: 0})
        request = self.client.get(reverse('exam-list')).wsgi_request
        request.user = self.student
        data = ExamDetailSerializer(Exam.objects.get(id=exam['id']), context={'request': request}).data
        body = json.dumps(data, default=str)
        self.assertNotIn('correct_answer', body)
        self.assertNotIn('SECRET', body)

    def test_duplicate_keeps_the_rule_but_not_a_manual_publication(self):
        exam = self.make_exam(result_publish_mode='MANUAL')
        self.client.post(reverse('exam-publish-results', kwargs={'pk': exam['id']}), {'publish': True}, format='json')
        copy = self.client.post(reverse('exam-duplicate', kwargs={'pk': exam['id']}), {}, format='json')
        self.assertEqual(copy.status_code, status.HTTP_201_CREATED, copy.data)
        clone = Exam.objects.get(id=copy.data['exam']['id'])
        self.assertEqual(clone.result_publish_mode, 'MANUAL')
        self.assertFalse(clone.is_results_published)
        self.assertEqual(clone.mcq_data[2]['image_url'], '/media/uploads/2026/10/graph.png')
