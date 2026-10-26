"""Student says "done", the tutor confirms it or sends it back as not done."""
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.students.models import Homework, Tuition
from apps.students.services import enroll_student

User = get_user_model()


class HomeworkDoneFlowTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(username='hd_tutor', password='pw123456', role=User.Role.TUTOR)
        self.student = User.objects.create_user(username='hd_s1', password='pw123456', role=User.Role.STUDENT, tutor=self.tutor)
        self.other = User.objects.create_user(username='hd_s2', password='pw123456', role=User.Role.STUDENT, tutor=self.tutor)
        self.tuition = Tuition.objects.create(tutor=self.tutor, title='HD group', total_fee=1000, cycle_length=4)
        enroll_student(self.tuition, self.student)
        enroll_student(self.tuition, self.other)
        self.hw = Homework.objects.create(
            tutor=self.tutor, student=self.student, title='Ex 3.2', due_date=timezone.now() + timedelta(days=1)
        )

    def _post(self, user, name, pk, data=None):
        self.client.force_authenticate(user=user)
        return self.client.post(reverse(f"homework-{name.replace('_', '-')}", kwargs={'pk': pk}), data or {}, format='json')

    def test_done_then_tutor_confirms(self):
        r = self._post(self.student, 'submit', self.hw.id)
        self.assertEqual(r.status_code, status.HTTP_200_OK, r.data)
        self.assertTrue(r.data['homework']['is_submitted'])
        r = self._post(self.tutor, 'evaluate', self.hw.id, {'is_evaluated': True})
        self.assertTrue(r.data['homework']['is_evaluated'])
        self.assertIsNone(r.data['homework']['returned_at'])

    def test_tutor_says_not_done_then_student_does_it_again(self):
        self._post(self.student, 'submit', self.hw.id)
        r = self._post(self.tutor, 'not_done', self.hw.id, {'tutor_feedback': 'Q4 is missing'})
        self.assertEqual(r.status_code, status.HTTP_200_OK, r.data)
        row = r.data['homework']
        self.assertFalse(row['is_submitted'])
        self.assertFalse(row['is_evaluated'])
        self.assertIsNotNone(row['returned_at'])
        self.assertEqual(row['tutor_feedback'], 'Q4 is missing')
        # Says done again: no longer "sent back".
        r = self._post(self.student, 'submit', self.hw.id)
        self.assertTrue(r.data['homework']['is_submitted'])
        self.assertIsNone(r.data['homework']['returned_at'])

    def test_student_can_undo_until_checked(self):
        self._post(self.student, 'submit', self.hw.id)
        r = self._post(self.student, 'undo_submit', self.hw.id)
        self.assertEqual(r.status_code, status.HTTP_200_OK, r.data)
        self.assertFalse(r.data['homework']['is_submitted'])
        self._post(self.student, 'submit', self.hw.id)
        self._post(self.tutor, 'evaluate', self.hw.id, {'is_evaluated': True})
        self.assertEqual(self._post(self.student, 'undo_submit', self.hw.id).status_code, status.HTTP_400_BAD_REQUEST)

    def test_only_the_right_people(self):
        self.assertEqual(self._post(self.student, 'not_done', self.hw.id).status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self._post(self.tutor, 'undo_submit', self.hw.id).status_code, status.HTTP_403_FORBIDDEN)
        # Another student never sees this row.
        self.assertEqual(self._post(self.other, 'undo_submit', self.hw.id).status_code, status.HTTP_404_NOT_FOUND)

    def test_group_task_done_goes_to_own_copy_and_can_be_sent_back(self):
        shared = Homework.objects.create(tutor=self.tutor, tuition=self.tuition, title='Group', due_date=timezone.now() + timedelta(days=1))
        r = self._post(self.student, 'submit', shared.id)
        copy_id = r.data['homework']['id']
        self.assertNotEqual(str(shared.id), copy_id)
        # The shared row itself cannot be sent back; the student's copy can.
        self.assertEqual(self._post(self.tutor, 'not_done', shared.id).status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self._post(self.tutor, 'not_done', copy_id).status_code, status.HTTP_200_OK)
        self.assertFalse(Homework.objects.get(id=copy_id).submitted_at)

    def test_student_is_told_when_sent_back(self):
        self._post(self.student, 'submit', self.hw.id)
        self._post(self.tutor, 'not_done', self.hw.id, {'tutor_feedback': 'Redo Q2'})
        self.client.force_authenticate(user=self.student)
        items = self.client.get('/api/v1/notifications/').data['notifications']
        titles = [i['title'] for i in items]
        self.assertTrue(any('says not done: Ex 3.2' in t for t in titles), titles)
