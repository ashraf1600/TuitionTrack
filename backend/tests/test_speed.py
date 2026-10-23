"""Speed work: compressed API answers and notifications that only read what they need."""
from datetime import timedelta

from django.utils import timezone
from rest_framework.test import APITestCase

from apps.exams.models import Exam, ExamSubmission
from tests.test_audit_fixes import AuditBase


class CompressionTests(AuditBase):
    def test_api_lists_are_gzipped_when_the_app_accepts_it(self):
        for n in range(40):
            Exam.objects.create(tutor=self.tutor, tuition=self.tuition, title=f'Quiz {n} ' + 'x' * 40, exam_type='CQ',
                                start_time=timezone.now(), end_time=timezone.now() + timedelta(hours=1))
        self.as_user(self.tutor)
        resp = self.client.get('/api/v1/exams/', HTTP_ACCEPT_ENCODING='gzip')
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.get('Content-Encoding'), 'gzip')

    def test_sign_in_answers_are_never_compressed(self):
        self.tutor.set_password('Pass-1234-word')
        self.tutor.save()
        resp = self.client.post('/api/v1/auth/token/', {'username': 'tutor_a', 'password': 'Pass-1234-word'},
                                format='json', HTTP_ACCEPT_ENCODING='gzip')
        self.assertEqual(resp.status_code, 200)
        self.assertIsNone(resp.get('Content-Encoding'))


class LeanNotificationTests(AuditBase):
    def _exam(self, **extra):
        now = timezone.now()
        fields = dict(tutor=self.tutor, tuition=self.tuition, title='Quiz', exam_type='CQ', is_published=True,
                      start_time=now - timedelta(hours=2), end_time=now - timedelta(hours=1))
        fields.update(extra)
        return Exam.objects.create(**fields)

    def test_tutor_sees_only_exams_with_ungraded_work_counted_correctly(self):
        busy = self._exam(title='Busy')
        self._exam(title='Quiet')
        ExamSubmission.objects.create(exam=busy, student=self.student, submitted_at=timezone.now())
        ExamSubmission.objects.create(exam=busy, student=self.classmate, submitted_at=timezone.now())
        self.as_user(self.tutor)
        grades = [n for n in self.client.get('/api/v1/notifications/').data['notifications'] if n['kind'] == 'grade']
        self.assertEqual(len(grades), 1)
        self.assertEqual(grades[0]['title'], '2 submissions to grade')
        self.assertEqual(grades[0]['body'], 'Busy')

    def test_student_is_not_told_about_long_finished_exams(self):
        now = timezone.now()
        self._exam(title='Ancient', start_time=now - timedelta(days=60), end_time=now - timedelta(days=59))
        self._exam(title='Open', start_time=now - timedelta(minutes=5), end_time=now + timedelta(hours=1))
        self.as_user(self.student)
        titles = [n['title'] for n in self.client.get('/api/v1/notifications/').data['notifications']]
        self.assertTrue(any('Open' in t for t in titles))
        self.assertFalse(any('Ancient' in t for t in titles))
