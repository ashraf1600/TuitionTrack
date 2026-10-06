"""
Account self-service (profile, password change/reset, forced change),
tutor password reset for students, exam duplication, question bank,
per-question written marks and the notification bell.
"""
import re
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.core import mail
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.exams.models import Exam, ExamSubmission
from apps.students.models import ConnectionRequest, StudentProfile, Tuition
from apps.students.services import enroll_student

User = get_user_model()


class AccountSelfServiceTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(username='acc_tutor', password='OldPass123!x', role=User.Role.TUTOR, email='tutor@example.com')
        self.student = User.objects.create_user(username='acc_student', password='OldPass123!x', role=User.Role.STUDENT, tutor=self.tutor)
        StudentProfile.objects.create(user=self.student)

    def test_profile_edit_for_tutor_and_student(self):
        self.client.force_authenticate(user=self.student)
        resp = self.client.patch(reverse('user_me'), {
            'first_name': 'Rafi', 'phone': '0171', 'address': 'Dhaka', 'grade_level': 'Class 9',
            'role': 'TUTOR', 'username': 'hacker',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        self.assertEqual(resp.data['name'], 'Rafi')
        self.assertEqual(resp.data['profile']['address'], 'Dhaka')
        self.student.refresh_from_db()
        self.assertEqual(self.student.role, User.Role.STUDENT)
        self.assertEqual(self.student.username, 'acc_student')
        self.assertNotIn('tuition_fee', resp.data['profile'])

    def test_change_password_requires_current_and_clears_flag(self):
        self.student.must_change_password = True
        self.student.save()
        self.client.force_authenticate(user=self.student)
        url = reverse('change_password')
        bad = self.client.post(url, {'current_password': 'wrong', 'new_password': 'BrandNew456!y'}, format='json')
        self.assertEqual(bad.status_code, status.HTTP_400_BAD_REQUEST)
        weak = self.client.post(url, {'current_password': 'OldPass123!x', 'new_password': '12345678'}, format='json')
        self.assertEqual(weak.status_code, status.HTTP_400_BAD_REQUEST)
        ok = self.client.post(url, {'current_password': 'OldPass123!x', 'new_password': 'BrandNew456!y'}, format='json')
        self.assertEqual(ok.status_code, status.HTTP_200_OK, ok.data)
        self.student.refresh_from_db()
        self.assertTrue(self.student.check_password('BrandNew456!y'))
        self.assertFalse(self.student.must_change_password)

    def test_password_reset_by_email_link(self):
        url = reverse('password_reset')
        # Unknown account: same answer, no email.
        unknown = self.client.post(url, {'identifier': 'nobody'}, format='json')
        self.assertEqual(unknown.status_code, status.HTTP_200_OK)
        self.assertEqual(len(mail.outbox), 0)
        # Account without an email cannot be reset this way.
        self.client.post(url, {'identifier': 'acc_student'}, format='json')
        self.assertEqual(len(mail.outbox), 0)

        known = self.client.post(url, {'identifier': 'acc_tutor'}, format='json')
        self.assertEqual(known.data, unknown.data)
        self.assertEqual(len(mail.outbox), 1)
        match = re.search(r'uid=([^&\s]+)&token=([^\s]+)', mail.outbox[0].body)
        self.assertIsNotNone(match)
        uid, token = match.groups()

        confirm = reverse('password_reset_confirm')
        bad = self.client.post(confirm, {'uid': uid, 'token': 'nope', 'new_password': 'BrandNew456!y'}, format='json')
        self.assertEqual(bad.status_code, status.HTTP_400_BAD_REQUEST)
        ok = self.client.post(confirm, {'uid': uid, 'token': token, 'new_password': 'BrandNew456!y'}, format='json')
        self.assertEqual(ok.status_code, status.HTTP_200_OK, ok.data)
        self.tutor.refresh_from_db()
        self.assertTrue(self.tutor.check_password('BrandNew456!y'))
        # The link works once.
        again = self.client.post(confirm, {'uid': uid, 'token': token, 'new_password': 'Another789!z'}, format='json')
        self.assertEqual(again.status_code, status.HTTP_400_BAD_REQUEST)

    def test_tutor_created_student_must_change_password_and_nothing_readable_is_kept(self):
        self.client.force_authenticate(user=self.tutor)
        resp = self.client.post(reverse('student-list-create'), {
            'username': 'acc_new', 'password': 'TempPass123!x', 'first_name': 'New',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        self.assertNotIn('TempPass123!x', str(resp.data))
        self.assertTrue(User.objects.get(username='acc_new').must_change_password)
        listing = self.client.get(reverse('student-list-create')).data
        self.assertNotIn('initial_password', str(listing))

        login = self.client.post(reverse('token_obtain_pair'), {'username': 'acc_new', 'password': 'TempPass123!x'}, format='json')
        self.assertEqual(login.status_code, status.HTTP_200_OK)
        self.assertTrue(login.data['user']['must_change_password'])

    def test_tutor_resets_own_students_password_only(self):
        other_tutor = User.objects.create_user(username='acc_other', password='x', role=User.Role.TUTOR)
        self.client.force_authenticate(user=other_tutor)
        url = reverse('student-reset-password', kwargs={'pk': self.student.id})
        self.assertEqual(self.client.post(url).status_code, status.HTTP_404_NOT_FOUND)

        self.client.force_authenticate(user=self.tutor)
        resp = self.client.post(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        temporary = resp.data['temporary_password']
        self.student.refresh_from_db()
        self.assertTrue(self.student.check_password(temporary))
        self.assertTrue(self.student.must_change_password)
        self.assertFalse(self.student.check_password('OldPass123!x'))


class ExamExtrasTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(username='ex_tutor', password='x', role=User.Role.TUTOR)
        self.other = User.objects.create_user(username='ex_other', password='x', role=User.Role.TUTOR)
        self.student = User.objects.create_user(username='ex_s1', password='x', role=User.Role.STUDENT, tutor=self.tutor)
        self.group_a = Tuition.objects.create(tutor=self.tutor, title='Group A', total_fee=1000, cycle_length=4)
        self.group_b = Tuition.objects.create(tutor=self.tutor, title='Group B', total_fee=1000, cycle_length=4)
        enroll_student(self.group_a, self.student)
        self.now = timezone.now()
        self.client.force_authenticate(user=self.tutor)
        resp = self.client.post(reverse('exam-list'), {
            'title': 'Midterm', 'exam_type': 'HYBRID', 'tuition_id': str(self.group_a.id), 'total_marks': '20',
            'content_html': '<p>Q1. Prove it. Q2. Explain.</p>',
            'start_time': (self.now - timedelta(minutes=5)).isoformat(),
            'end_time': (self.now + timedelta(hours=1)).isoformat(),
            'mcq_data': [{'question': 'Capital of BD?', 'options': ['Dhaka', 'Khulna'], 'correct_answer': 0, 'points': 4}],
            'written_scheme': [{'label': 'Q1', 'marks': 10}, {'label': 'Q2', 'marks': 6}],
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        self.exam = resp.data['exam']

    def test_scheme_cannot_exceed_total(self):
        resp = self.client.patch(reverse('exam-detail', kwargs={'pk': self.exam['id']}), {
            'written_scheme': [{'label': 'Q1', 'marks': 10}, {'label': 'Q2', 'marks': 7}],
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_per_question_written_marks(self):
        scheme = self.exam['written_scheme']
        self.assertEqual([s['label'] for s in scheme], ['Q1', 'Q2'])
        q = self.exam['mcq_data'][0]
        self.client.force_authenticate(user=self.student)
        self.client.post(reverse('exam-submit', kwargs={'pk': self.exam['id']}), {'answers_data': {q['id']: '0'}, 'text_answer': 'answer'}, format='json')
        sub = ExamSubmission.objects.get(exam_id=self.exam['id'], student=self.student)

        self.client.force_authenticate(user=self.tutor)
        url = reverse('grade-submission', kwargs={'pk': sub.id})
        too_many = self.client.patch(url, {'cq_breakdown': {scheme[0]['id']: 11}}, format='json')
        self.assertEqual(too_many.status_code, status.HTTP_400_BAD_REQUEST)
        ok = self.client.patch(url, {'cq_breakdown': {scheme[0]['id']: 7.5, scheme[1]['id']: 4}}, format='json')
        self.assertEqual(ok.status_code, status.HTTP_200_OK, ok.data)
        self.assertEqual(float(ok.data['submission']['cq_score']), 11.5)
        self.assertEqual(float(ok.data['submission']['obtained_marks']), 15.5)
        self.assertEqual(ok.data['submission']['cq_breakdown'][scheme[0]['id']], 7.5)

        # The student does not see the breakdown while the exam is still open.
        self.client.force_authenticate(user=self.student)
        mine = self.client.get(reverse('exam-detail', kwargs={'pk': self.exam['id']})).data['submission']
        self.assertEqual(mine['cq_breakdown'], {})
        self.assertIsNone(mine['obtained_marks'])

    def test_duplicate_to_another_group_is_a_draft(self):
        url = reverse('exam-duplicate', kwargs={'pk': self.exam['id']})
        resp = self.client.post(url, {'tuition_id': str(self.group_b.id)}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        copy = Exam.objects.get(id=resp.data['exam']['id'])
        self.assertFalse(copy.is_published)
        self.assertEqual(copy.tuition_id, self.group_b.id)
        self.assertEqual(copy.title, 'Midterm (copy)')
        self.assertEqual(len(copy.mcq_data), 1)
        self.assertEqual(len(copy.written_scheme), 2)
        self.assertGreater(copy.start_time, self.now)
        self.assertEqual(copy.submissions.count(), 0)

        # Another tutor can neither copy it nor copy into this tutor's group.
        self.client.force_authenticate(user=self.other)
        self.assertEqual(self.client.post(url, {}, format='json').status_code, status.HTTP_404_NOT_FOUND)

    def test_question_bank_lists_own_questions_once(self):
        self.client.post(reverse('exam-duplicate', kwargs={'pk': self.exam['id']}), {}, format='json')
        data = self.client.get(reverse('exam-question-bank')).data
        self.assertEqual(data['count'], 1)
        self.assertEqual(data['questions'][0]['question'], 'Capital of BD?')
        self.assertEqual(self.client.get(reverse('exam-question-bank'), {'search': 'khulna'}).data['count'], 1)
        self.assertEqual(self.client.get(reverse('exam-question-bank'), {'search': 'zzz'}).data['count'], 0)

        self.client.force_authenticate(user=self.other)
        self.assertEqual(self.client.get(reverse('exam-question-bank')).data['count'], 0)
        self.client.force_authenticate(user=self.student)
        self.assertEqual(self.client.get(reverse('exam-question-bank')).status_code, status.HTTP_403_FORBIDDEN)

    def test_notifications_for_both_roles(self):
        newcomer = User.objects.create_user(username='ex_new', password='x', role=User.Role.STUDENT, first_name='Nila')
        ConnectionRequest.objects.create(student=newcomer, tutor=self.tutor)

        self.client.force_authenticate(user=self.student)
        kinds = [n['kind'] for n in self.client.get(reverse('notifications')).data['notifications']]
        self.assertEqual(kinds, ['open'])
        self.client.post(reverse('exam-submit', kwargs={'pk': self.exam['id']}), {'text_answer': 'a'}, format='json')
        self.assertEqual(self.client.get(reverse('notifications')).data['count'], 0)

        self.client.force_authenticate(user=self.tutor)
        notes = self.client.get(reverse('notifications')).data['notifications']
        self.assertEqual(sorted(n['kind'] for n in notes), ['grade', 'request'])
        self.assertIn('Nila', next(n['title'] for n in notes if n['kind'] == 'request'))

        self.client.force_authenticate(user=self.other)
        self.assertEqual(self.client.get(reverse('notifications')).data['count'], 0)
