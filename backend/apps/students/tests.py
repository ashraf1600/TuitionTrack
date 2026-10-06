"""Tests for Students app and Multi-Tenancy Guard"""
from django.urls import reverse
from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase
from apps.cycles.models import Cycle

User = get_user_model()


class StudentsTests(APITestCase):
    def setUp(self):
        # Tutor 1
        self.tutor1 = User.objects.create_user(
            username='tutor1',
            password='password123',
            email='tutor1@example.com',
            role=User.Role.TUTOR,
            first_name='Tutor',
            last_name='One'
        )

        # Tutor 2 (for multi-tenant isolation testing)
        self.tutor2 = User.objects.create_user(
            username='tutor2',
            password='password123',
            email='tutor2@example.com',
            role=User.Role.TUTOR,
            first_name='Tutor',
            last_name='Two'
        )

        self.list_create_url = reverse('student-list-create')

    def test_tutor_creates_student_with_atomic_cycle1(self):
        self.client.force_authenticate(user=self.tutor1)
        payload = {
            'username': 'student_alice',
            'password': 'studentpass123',
            'first_name': 'Alice',
            'last_name': 'Smith',
            'email': 'alice@example.com',
            'phone': '+8801700000001',
            'grade_level': 'Class 10',
            'institution': 'Dhaka City College',
            'parent_name': 'Bob Smith',
            'parent_phone': '+8801700000002',
            'tuition_fee': '5000.00',
            'cycle_length': 12,
            'notes': 'Math and Physics tutoring'
        }
        response = self.client.post(self.list_create_url, payload, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        # Check user created
        student = User.objects.get(username='student_alice')
        self.assertEqual(student.role, User.Role.STUDENT)
        self.assertEqual(student.tutor, self.tutor1)
        self.assertEqual(student.student_profile.grade_level, 'Class 10')
        self.assertEqual(float(student.student_profile.tuition_fee), 5000.00)

        # Check atomic cycle #1 created
        cycle = Cycle.objects.get(student=student, status=Cycle.Status.ACTIVE)
        self.assertEqual(cycle.cycle_number, 1)
        self.assertEqual(cycle.tutor, self.tutor1)
        self.assertEqual(float(cycle.fee_snapshot), 5000.00)
        self.assertEqual(cycle.total_classes, 12)
        self.assertEqual(len(cycle.classes_data), 12)
        self.assertFalse(cycle.classes_data[0]['completed'])

    def test_multi_tenancy_isolation_between_tutors(self):
        # Tutor 1 creates student Alice
        self.client.force_authenticate(user=self.tutor1)
        payload1 = {
            'username': 'student_alice',
            'password': 'password123',
            'first_name': 'Alice',
            'tuition_fee': '4000.00',
            'cycle_length': 8
        }
        resp = self.client.post(self.list_create_url, payload1, format='json')
        alice_id = resp.data['student']['student_id']

        # Tutor 2 creates student Bob
        self.client.force_authenticate(user=self.tutor2)
        payload2 = {
            'username': 'student_bob',
            'password': 'password123',
            'first_name': 'Bob',
            'tuition_fee': '6000.00',
            'cycle_length': 12
        }
        self.client.post(self.list_create_url, payload2, format='json')

        # Tutor 2 lists students -> Should only see Bob, NOT Alice!
        list_resp = self.client.get(self.list_create_url)
        self.assertEqual(list_resp.status_code, status.HTTP_200_OK)
        # Handle paginated or non-paginated results
        students = list_resp.data.get('results', list_resp.data) if isinstance(list_resp.data, dict) else list_resp.data
        usernames = [s['username'] for s in students]
        self.assertIn('student_bob', usernames)
        self.assertNotIn('student_alice', usernames)

        # Tutor 2 tries to GET Alice's detail -> Must be 404
        detail_url = reverse('student-detail', kwargs={'pk': alice_id})
        detail_resp = self.client.get(detail_url)
        self.assertEqual(detail_resp.status_code, status.HTTP_404_NOT_FOUND)

        # Tutor 2 tries to PATCH Alice -> Must be 404
        patch_resp = self.client.patch(detail_url, {'first_name': 'Hacked Alice'}, format='json')
        self.assertEqual(patch_resp.status_code, status.HTTP_404_NOT_FOUND)

    def test_soft_delete_and_toggle_active(self):
        self.client.force_authenticate(user=self.tutor1)
        resp = self.client.post(self.list_create_url, {
            'username': 'student_deleteme',
            'password': 'password123',
            'first_name': 'Charlie',
            'tuition_fee': '3000.00',
            'cycle_length': 10
        }, format='json')
        student_id = resp.data['student']['student_id']
        detail_url = reverse('student-detail', kwargs={'pk': student_id})

        # Soft delete
        del_resp = self.client.delete(detail_url)
        self.assertEqual(del_resp.status_code, status.HTTP_200_OK)
        student = User.objects.get(id=student_id)
        self.assertFalse(student.is_active)

        # Toggle active
        toggle_url = reverse('student-toggle-active', kwargs={'pk': student_id})
        tog_resp = self.client.post(toggle_url)
        self.assertEqual(tog_resp.status_code, status.HTTP_200_OK)
        self.assertTrue(tog_resp.data['is_active'])
        student.refresh_from_db()
        self.assertTrue(student.is_active)
