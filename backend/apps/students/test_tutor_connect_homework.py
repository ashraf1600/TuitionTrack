from django.urls import reverse
from django.utils import timezone
from datetime import timedelta
from rest_framework import status
from rest_framework.test import APITestCase
from django.contrib.auth import get_user_model
from apps.students.models import ConnectionRequest, Tuition, TuitionEnrollment, Homework

User = get_user_model()


class TutorCodeAndConnectionTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(
            username='ashraf_tutor',
            first_name='Ashraf',
            last_name='Khan',
            email='ashraf@example.com',
            password='Password123!',
            role=User.Role.TUTOR,
        )
        self.student = User.objects.create_user(
            username='student_rahim',
            first_name='Rahim',
            email='rahim@example.com',
            password='Password123!',
            role=User.Role.STUDENT,
        )

    def test_tutor_auto_generates_6_char_code(self):
        self.assertIsNotNone(self.tutor.tutor_code)
        self.assertEqual(len(self.tutor.tutor_code), 6)
        self.assertTrue(self.tutor.tutor_code.isalnum())
        self.assertTrue(self.tutor.tutor_code.isupper())

    def test_student_does_not_get_tutor_code(self):
        self.assertIsNone(self.student.tutor_code)

    def test_student_connects_via_tutor_code(self):
        self.client.force_authenticate(user=self.student)
        url = reverse('connect-by-code')
        resp = self.client.post(url, {
            'tutor_code': self.tutor.tutor_code,
            'message': 'Hello Sir, please connect!',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['status'], 'PENDING')
        self.assertEqual(resp.data['tutor_name'], 'Ashraf Khan')
        self.assertEqual(resp.data['tutor_display_name'], 'Ashraf Sir')

        # Check DB
        conn = ConnectionRequest.objects.get(student=self.student, tutor=self.tutor)
        self.assertEqual(conn.status, ConnectionRequest.Status.PENDING)

    def test_invalid_tutor_code_returns_400(self):
        self.client.force_authenticate(user=self.student)
        url = reverse('connect-by-code')
        resp = self.client.post(url, {'tutor_code': 'XXXXXX'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_connected_tutors_list_and_display_name_format(self):
        # Establish accepted connection
        ConnectionRequest.objects.create(
            student=self.student,
            tutor=self.tutor,
            status=ConnectionRequest.Status.ACCEPTED,
        )
        self.client.force_authenticate(user=self.student)
        resp = self.client.get(reverse('my-tutors'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        data = resp.data
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]['display_name'], 'Ashraf Sir')
        self.assertEqual(data[0]['username'], 'ashraf_tutor')


class HomeworkAndDetailViewTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(
            username='ashraf_tutor',
            first_name='Ashraf',
            email='ashraf@example.com',
            password='Password123!',
            role=User.Role.TUTOR,
        )
        self.other_tutor = User.objects.create_user(
            username='other_tutor',
            first_name='Other',
            email='other@example.com',
            password='Password123!',
            role=User.Role.TUTOR,
        )
        self.student = User.objects.create_user(
            username='student_rahim',
            first_name='Rahim',
            email='rahim@example.com',
            password='Password123!',
            role=User.Role.STUDENT,
            tutor=self.tutor,
        )
        self.tuition = Tuition.objects.create(
            tutor=self.tutor,
            title='Physics Batch 1',
            subject='Physics',
            routine=[{'day': 'Monday', 'start_time': '16:00', 'end_time': '17:30'}],
            total_fee=3000,
            cycle_length=12,
        )
        TuitionEnrollment.objects.create(
            tuition=self.tuition,
            student=self.student,
            is_active=True,
        )
        ConnectionRequest.objects.create(
            student=self.student,
            tutor=self.tutor,
            status=ConnectionRequest.Status.ACCEPTED,
        )

    def test_tutor_detail_for_connected_student(self):
        self.client.force_authenticate(user=self.student)
        url = reverse('tutor-detail-for-student', kwargs={'tutor_id': self.tutor.id})
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['tutor']['display_name'], 'Ashraf Sir')
        self.assertEqual(len(resp.data['tutor']['tuitions']), 1)
        self.assertEqual(resp.data['tutor']['tuitions'][0]['subject'], 'Physics')

    def test_tutor_creates_homework(self):
        self.client.force_authenticate(user=self.tutor)
        due = (timezone.now() + timedelta(days=2)).isoformat()
        resp = self.client.post('/api/v1/homework/', {
            'title': 'Chapter 5 Problems',
            'description': 'Solve problems 1 through 10 from textbook.',
            'due_date': due,
            'student': str(self.student.id),
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['title'], 'Chapter 5 Problems')
        self.assertEqual(resp.data['tutor_display_name'], 'Ashraf Sir')
        self.assertFalse(resp.data['is_evaluated'])

    def test_student_cannot_create_homework(self):
        self.client.force_authenticate(user=self.student)
        due = (timezone.now() + timedelta(days=2)).isoformat()
        resp = self.client.post('/api/v1/homework/', {
            'title': 'Hack Homework',
            'due_date': due,
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_student_submits_online_url(self):
        hw = Homework.objects.create(
            tutor=self.tutor,
            student=self.student,
            title='Math Assignment',
            due_date=timezone.now() + timedelta(days=1),
        )
        self.client.force_authenticate(user=self.student)
        resp = self.client.post(f'/api/v1/homework/{hw.id}/submit/', {
            'submitted_online_url': 'https://docs.google.com/document/d/12345/edit',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        hw.refresh_from_db()
        self.assertEqual(hw.submitted_online_url, 'https://docs.google.com/document/d/12345/edit')
        self.assertIsNotNone(hw.submitted_at)
        self.assertFalse(hw.is_evaluated)

    def test_only_tutor_can_mark_done(self):
        hw = Homework.objects.create(
            tutor=self.tutor,
            student=self.student,
            title='Essay',
            due_date=timezone.now() + timedelta(days=1),
        )

        # Student attempts to mark done -> 403 Forbidden
        self.client.force_authenticate(user=self.student)
        resp = self.client.post(f'/api/v1/homework/{hw.id}/mark_done/', {
            'feedback': 'I did it!',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

        # Tutor marks done -> 200 OK
        self.client.force_authenticate(user=self.tutor)
        resp = self.client.post(f'/api/v1/homework/{hw.id}/mark_done/', {
            'feedback': 'Excellent analysis and reasoning.',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        hw.refresh_from_db()
        self.assertTrue(hw.is_evaluated)
        self.assertEqual(hw.tutor_feedback, 'Excellent analysis and reasoning.')

    def test_cross_tenant_isolation_on_homework(self):
        hw = Homework.objects.create(
            tutor=self.tutor,
            student=self.student,
            title='Private Homework',
            due_date=timezone.now() + timedelta(days=1),
        )
        # Other tutor attempts to mark done -> 404 or not permitted
        self.client.force_authenticate(user=self.other_tutor)
        resp = self.client.post(f'/api/v1/homework/{hw.id}/mark_done/', format='json')
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)
