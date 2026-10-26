"""
Exam paper fields (instructions, structured creative questions, answer link)
and keeping a student's tuitions with one tutor apart (homework class_id).
"""
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.exams.models import ExamSubmission
from apps.students.models import Homework, Tuition
from apps.students.services import enroll_student

User = get_user_model()


class ExamPaperTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(username='pp_tutor', password='x', role=User.Role.TUTOR)
        self.student = User.objects.create_user(username='pp_s1', password='x', role=User.Role.STUDENT, tutor=self.tutor)
        self.group = Tuition.objects.create(tutor=self.tutor, title='Physics A', subject='Physics', total_fee=1000)
        enroll_student(self.group, self.student)
        now = timezone.now()
        self.client.force_authenticate(user=self.tutor)
        resp = self.client.post(reverse('exam-list'), {
            'title': 'Chapter 2 test', 'exam_type': 'HYBRID', 'tuition_id': str(self.group.id), 'total_marks': '12',
            'instructions': 'Answer every question.',
            'content_html': '<p>1. Stem</p>',
            'cq_data': [{
                'stem': 'A car moves at 10 m/s.',
                'parts': [
                    {'label': 'ক', 'text': 'What is speed?', 'marks': 1},
                    {'label': 'খ', 'text': 'Explain.', 'marks': 2},
                    {'label': 'গ', 'text': 'Find distance.', 'marks': 3},
                    {'label': 'ঘ', 'text': 'Analyse.', 'marks': 4},
                ],
            }],
            'written_scheme': [{'label': '1', 'marks': 10}],
            'mcq_data': [{'question': '2+2?', 'options': ['3', '4'], 'correct_answer': 1, 'points': 2}],
            'start_time': (now - timedelta(minutes=5)).isoformat(),
            'end_time': (now + timedelta(hours=1)).isoformat(),
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        self.exam = resp.data['exam']

    def test_paper_fields_reach_the_student(self):
        self.assertEqual(self.exam['instructions'], 'Answer every question.')
        cq = self.exam['cq_data']
        self.assertEqual(len(cq), 1)
        self.assertEqual([p['label'] for p in cq[0]['parts']], ['ক', 'খ', 'গ', 'ঘ'])
        self.assertTrue(cq[0]['id'])  # server gives each question an id

        self.client.force_authenticate(user=self.student)
        started = self.client.post(reverse('exam-start', kwargs={'pk': self.exam['id']}), {}, format='json')
        self.assertEqual(started.status_code, status.HTTP_200_OK, started.data)
        paper = started.data['exam']
        self.assertEqual(paper['instructions'], 'Answer every question.')
        self.assertEqual(paper['cq_data'][0]['stem'], 'A car moves at 10 m/s.')
        self.assertNotIn('correct_answer', paper['mcq_data'][0])

    def test_bad_cq_data_is_refused(self):
        resp = self.client.patch(reverse('exam-detail', kwargs={'pk': self.exam['id']}), {
            'cq_data': [{'stem': 'x', 'image_url': 'javascript:alert(1)', 'parts': []}],
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_student_hands_in_a_link_for_the_written_part(self):
        q = self.exam['mcq_data'][0]
        self.client.force_authenticate(user=self.student)
        bad = self.client.post(reverse('exam-submit', kwargs={'pk': self.exam['id']}), {
            'answers_data': {q['id']: '1'}, 'answer_link': 'drive.google.com/abc',
        }, format='json')
        self.assertEqual(bad.status_code, status.HTTP_400_BAD_REQUEST)

        link = 'https://drive.google.com/file/d/abc/view'
        ok = self.client.post(reverse('exam-submit', kwargs={'pk': self.exam['id']}), {
            'answers_data': {q['id']: '1'}, 'answer_link': link,
        }, format='json')
        self.assertEqual(ok.status_code, status.HTTP_201_CREATED, ok.data)
        self.assertEqual(ok.data['submission']['answer_link'], link)
        self.assertEqual(ExamSubmission.objects.get(exam_id=self.exam['id']).answer_link, link)

        # The tutor sees the link with the submissions.
        self.client.force_authenticate(user=self.tutor)
        subs = self.client.get(reverse('exam-submissions', kwargs={'pk': self.exam['id']}))
        self.assertEqual(subs.status_code, status.HTTP_200_OK)
        self.assertIn(link, str(subs.data))

    def test_duplicate_keeps_the_paper(self):
        resp = self.client.post(reverse('exam-duplicate', kwargs={'pk': self.exam['id']}), {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        copy = resp.data.get('exam', resp.data)
        self.assertEqual(copy['instructions'], 'Answer every question.')
        self.assertEqual(len(copy['cq_data']), 1)


class SeparateClassesTests(APITestCase):
    """One student in two tuitions of the same tutor: each homework says which one it is for."""

    def setUp(self):
        self.tutor = User.objects.create_user(username='sc_tutor', password='x', role=User.Role.TUTOR)
        self.student = User.objects.create_user(username='sc_s1', password='x', role=User.Role.STUDENT, tutor=self.tutor)
        self.physics = Tuition.objects.create(tutor=self.tutor, title='Batch P', subject='Physics', total_fee=1000)
        self.math = Tuition.objects.create(tutor=self.tutor, title='Batch M', subject='Math', total_fee=1000)
        enroll_student(self.physics, self.student)
        enroll_student(self.math, self.student)
        due = timezone.now() + timedelta(days=2)
        self.hw_p = Homework.objects.create(tutor=self.tutor, tuition=self.physics, title='Physics HW', due_date=due)
        self.hw_m = Homework.objects.create(tutor=self.tutor, tuition=self.math, title='Math HW', due_date=due)

    def test_homework_carries_its_class(self):
        self.client.force_authenticate(user=self.student)
        detail = self.client.get(f'/api/v1/my-tutors/{self.tutor.id}/')
        self.assertEqual(detail.status_code, status.HTTP_200_OK, detail.data)
        by_title = {h['title']: h['class_id'] for h in detail.data['homework']}
        self.assertEqual(by_title['Physics HW'], str(self.physics.id))
        self.assertEqual(by_title['Math HW'], str(self.math.id))
        # Both classes are listed for the student, each with its own cycle.
        tuitions = self.client.get('/api/v1/tuitions/').data
        rows = tuitions['results'] if isinstance(tuitions, dict) else tuitions
        self.assertEqual({r['subject'] for r in rows}, {'Physics', 'Math'})

    def test_personal_copy_keeps_the_class(self):
        copy = self.hw_p.personal_copy_for(self.student)
        self.client.force_authenticate(user=self.student)
        detail = self.client.get(f'/api/v1/my-tutors/{self.tutor.id}/')
        row = next(h for h in detail.data['homework'] if h['id'] == str(copy.id))
        self.assertEqual(row['class_id'], str(self.physics.id))
