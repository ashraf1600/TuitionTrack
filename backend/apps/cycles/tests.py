"""Tests for Cycles app — attendance toggle and cycle reset engine"""
from django.urls import reverse
from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.students.models import StudentProfile
from apps.cycles.models import Cycle

User = get_user_model()


class CyclesTests(APITestCase):
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
        # Tutor 2
        self.tutor2 = User.objects.create_user(
            username='tutor2',
            password='password123',
            email='tutor2@example.com',
            role=User.Role.TUTOR,
            first_name='Tutor',
            last_name='Two'
        )
        # Student under Tutor 1
        self.student = User.objects.create_user(
            username='student1',
            password='password123',
            email='student1@example.com',
            role=User.Role.STUDENT,
            tutor=self.tutor1,
            first_name='Student',
            last_name='One'
        )
        self.profile = StudentProfile.objects.create(
            user=self.student,
            tuition_fee=6000.00,
            cycle_length=12
        )
        # Cycle 1
        self.cycle = Cycle.objects.create(
            tutor=self.tutor1,
            student=self.student,
            cycle_number=1,
            fee_snapshot=6000.00,
            total_classes=12,
            classes_data=Cycle.build_fresh_classes_data(12),
            status=Cycle.Status.ACTIVE
        )

    def test_list_and_filter_cycles(self):
        self.client.force_authenticate(user=self.tutor1)
        url = reverse('cycle-list')
        response = self.client.get(url, {'student_id': str(self.student.id)})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = response.data.get('results', response.data) if isinstance(response.data, dict) else response.data
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]['cycle_number'], 1)
        self.assertEqual(float(results[0]['fee_snapshot']), 6000.00)

    def test_toggle_class_check_and_uncheck(self):
        self.client.force_authenticate(user=self.tutor1)
        toggle_url = reverse('cycle-toggle-class', kwargs={'pk': self.cycle.id})

        # 1. Complete class 1
        resp1 = self.client.patch(toggle_url, {'class_no': 1, 'completed': True}, format='json')
        self.assertEqual(resp1.status_code, status.HTTP_200_OK)
        self.cycle.refresh_from_db()
        self.assertEqual(self.cycle.completed_classes, 1)
        self.assertEqual(float(self.cycle.earned_amount), 500.00)  # 6000 / 12 * 1
        self.assertEqual(float(self.cycle.pending_amount), 5500.00)
        self.assertIsNotNone(self.cycle.classes_data[0]['date'])

        # 2. Complete class 2
        resp2 = self.client.patch(toggle_url, {'classNo': 2, 'completed': True}, format='json')
        self.assertEqual(resp2.status_code, status.HTTP_200_OK)
        self.cycle.refresh_from_db()
        self.assertEqual(self.cycle.completed_classes, 2)
        self.assertEqual(float(self.cycle.earned_amount), 1000.00)

        # 3. Uncheck class 1
        resp3 = self.client.patch(toggle_url, {'class_no': 1, 'completed': False}, format='json')
        self.assertEqual(resp3.status_code, status.HTTP_200_OK)
        self.cycle.refresh_from_db()
        self.assertEqual(self.cycle.completed_classes, 1)
        self.assertIsNone(self.cycle.classes_data[0]['date'])

    def test_toggle_class_out_of_bounds(self):
        self.client.force_authenticate(user=self.tutor1)
        toggle_url = reverse('cycle-toggle-class', kwargs={'pk': self.cycle.id})
        resp = self.client.patch(toggle_url, {'class_no': 15, 'completed': True}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_tutor2_cannot_toggle_tutor1_student_cycle(self):
        self.client.force_authenticate(user=self.tutor2)
        toggle_url = reverse('cycle-toggle-class', kwargs={'pk': self.cycle.id})
        resp = self.client.patch(toggle_url, {'class_no': 1, 'completed': True}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)

    def test_student_cannot_toggle_class(self):
        self.client.force_authenticate(user=self.student)
        toggle_url = reverse('cycle-toggle-class', kwargs={'pk': self.cycle.id})
        resp = self.client.patch(toggle_url, {'class_no': 1, 'completed': True}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_cycle_reset_flow(self):
        self.client.force_authenticate(user=self.tutor1)
        reset_url = reverse('cycle-reset', kwargs={'pk': self.cycle.id})

        # Update profile fee before reset to verify snapshotting
        self.profile.tuition_fee = 7200.00
        self.profile.cycle_length = 8
        self.profile.save()

        resp = self.client.post(reset_url)
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

        # Check old cycle archived
        self.cycle.refresh_from_db()
        self.assertEqual(self.cycle.status, Cycle.Status.ARCHIVED)
        self.assertEqual(float(self.cycle.fee_snapshot), 6000.00)  # preserved snapshot

        # Check new cycle active with new snapshot
        new_cycle = Cycle.objects.get(student=self.student, status=Cycle.Status.ACTIVE)
        self.assertEqual(new_cycle.cycle_number, 2)
        self.assertEqual(float(new_cycle.fee_snapshot), 7200.00)
        self.assertEqual(new_cycle.total_classes, 8)
        self.assertEqual(len(new_cycle.classes_data), 8)

        # Attempting to reset the archived cycle again should fail
        resp_again = self.client.post(reset_url)
        self.assertEqual(resp_again.status_code, status.HTTP_400_BAD_REQUEST)


class SharedAttendanceCyclesTests(APITestCase):
    def setUp(self):
        from apps.students.models import Tuition, TuitionEnrollment
        from apps.cycles.models import AttendanceCycle

        self.tutor = User.objects.create_user(
            username='tutor_att',
            password='password123',
            email='tutor_att@example.com',
            role=User.Role.TUTOR,
            first_name='Tutor',
            last_name='Att'
        )
        self.student = User.objects.create_user(
            username='student_att',
            password='password123',
            email='student_att@example.com',
            role=User.Role.STUDENT,
            first_name='Student',
            last_name='Att'
        )
        self.tuition = Tuition.objects.create(
            tutor=self.tutor,
            title='Class 10 Advanced Math',
            subject='Math',
            cycle_length=12,
            total_fee=7000.00
        )
        TuitionEnrollment.objects.create(
            tuition=self.tuition,
            student=self.student,
            is_active=True
        )
        self.cycle = AttendanceCycle.start_for(self.tuition)

    def test_toggle_class_attendance_and_revert(self):
        self.client.force_authenticate(user=self.tutor)
        url = reverse('attendance-cycle-toggle-class', kwargs={'pk': str(self.cycle.id)})

        # Check Class 1
        resp = self.client.patch(url, {
            'class_no': 1,
            'completed': True,
            'date': '2026-10-09T12:00:00Z',
            'topic': 'Quadratic Equations'
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['cycle']['completed_classes'], 1)
        self.cycle.refresh_from_db()
        self.assertEqual(self.cycle.completed_classes, 1)

        # Uncheck Class 1
        resp2 = self.client.patch(url, {
            'class_no': 1,
            'completed': False
        }, format='json')
        self.assertEqual(resp2.status_code, status.HTTP_200_OK)
        self.assertEqual(resp2.data['cycle']['completed_classes'], 0)
        self.cycle.refresh_from_db()
        self.assertEqual(self.cycle.completed_classes, 0)

