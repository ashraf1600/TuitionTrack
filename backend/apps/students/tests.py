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


class TuitionArchitectureTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(
            username='main_tutor',
            password='password123',
            email='maintutor@example.com',
            role=User.Role.TUTOR,
            first_name='Main',
            last_name='Tutor'
        )
        self.student = User.objects.create_user(
            username='self_student',
            password='password123',
            email='student@example.com',
            role=User.Role.STUDENT,
            selected_tutor=self.tutor,
            first_name='Self',
            last_name='Student'
        )

    def test_tutor_directory_and_unassigned_prospective_student(self):
        tutors_url = reverse('tutor_directory')
        resp = self.client.get(tutors_url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        raw_list = resp.data if isinstance(resp.data, list) else resp.data.get('results', [])
        usernames = [t['username'] for t in raw_list]
        self.assertIn('main_tutor', usernames)

        # Tutor checks unassigned students
        self.client.force_authenticate(user=self.tutor)
        unassigned_url = reverse('student-unassigned')
        u_resp = self.client.get(unassigned_url)
        self.assertEqual(u_resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(u_resp.data), 1)
        self.assertEqual(u_resp.data[0]['username'], 'self_student')

    def test_tuition_crud_enrollment_and_attendance_cycle(self):
        self.client.force_authenticate(user=self.tutor)
        # 1. Create Tuition
        tuitions_url = reverse('tuition-list')
        routine_data = [
            {"day": "Monday", "start_time": "18:00", "end_time": "19:30"},
            {"day": "Wednesday", "start_time": "18:00", "end_time": "19:30"}
        ]
        t_resp = self.client.post(tuitions_url, {
            'title': 'HSC Physics 2026',
            'cycle_length': 12,
            'tuition_fee': '9000.00',
            'routine': routine_data,
        }, format='json')
        self.assertEqual(t_resp.status_code, status.HTTP_201_CREATED)
        tuition_id = t_resp.data['id']

        # 2. Enroll student
        enroll_url = reverse('tuition-enroll', kwargs={'pk': tuition_id})
        e_resp = self.client.post(enroll_url, {'student_id': str(self.student.id)}, format='json')
        self.assertEqual(e_resp.status_code, status.HTTP_200_OK)

        # Student is no longer unassigned
        u_resp = self.client.get(reverse('student-unassigned'))
        self.assertEqual(len(u_resp.data), 0)

        # Check AttendanceCycle was created
        from apps.cycles.models import AttendanceCycle
        cycle = AttendanceCycle.objects.filter(enrollment__tuition_id=tuition_id, enrollment__student=self.student).first()
        self.assertIsNotNone(cycle)
        self.assertEqual(cycle.total_classes, 12)
        self.assertEqual(cycle.completed_classes, 0)

        # 3. Toggle Class #1 with date & topic
        toggle_url = reverse('attendance-cycle-toggle-class', kwargs={'pk': str(cycle.id)})
        tog_resp = self.client.patch(toggle_url, {
            'class_no': 1,
            'completed': True,
            'date': '2026-10-06T10:00:00Z',
            'topic': 'Vectors and Kinematics'
        }, format='json')
        self.assertEqual(tog_resp.status_code, status.HTTP_200_OK)
        cycle.refresh_from_db()
        self.assertEqual(cycle.completed_classes, 1)
        self.assertEqual(float(cycle.earned_revenue), 750.00)
        self.assertEqual(float(cycle.pending_balance), 8250.00)

        # 4. Student views cycle -> ZERO billing or taka
        self.client.force_authenticate(user=self.student)
        s_cycle_resp = self.client.get(reverse('attendance-cycle-detail', kwargs={'pk': str(cycle.id)}))
        self.assertEqual(s_cycle_resp.status_code, status.HTTP_200_OK)
        self.assertNotIn('tuition_fee', s_cycle_resp.data)
        self.assertNotIn('per_class_rate', s_cycle_resp.data)
        self.assertNotIn('earned_revenue', s_cycle_resp.data)
        self.assertNotIn('pending_balance', s_cycle_resp.data)
        self.assertEqual(s_cycle_resp.data['completed_classes'], 1)

