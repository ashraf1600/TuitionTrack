"""Tests for Analytics app — Wallet metrics & financial aggregations"""
from django.urls import reverse
from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.students.models import StudentProfile
from apps.cycles.models import Cycle

User = get_user_model()


class AnalyticsTests(APITestCase):
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
        # Student 1 under Tutor 1 (tuition 12000, 12 classes, 3 completed -> earned 3000, pending 9000)
        self.student1 = User.objects.create_user(
            username='student1',
            password='password123',
            email='student1@example.com',
            role=User.Role.STUDENT,
            tutor=self.tutor1,
            first_name='Student',
            last_name='One'
        )
        StudentProfile.objects.create(
            user=self.student1,
            tuition_fee=12000.00,
            cycle_length=12
        )
        classes1 = Cycle.build_fresh_classes_data(12)
        for i in range(3):
            classes1[i]['completed'] = True
        self.cycle1 = Cycle.objects.create(
            tutor=self.tutor1,
            student=self.student1,
            cycle_number=1,
            fee_snapshot=12000.00,
            total_classes=12,
            classes_data=classes1,
            status=Cycle.Status.ACTIVE
        )

        # Student 2 under Tutor 1 (tuition 8000, 8 classes, 2 completed -> earned 2000, pending 6000)
        self.student2 = User.objects.create_user(
            username='student2',
            password='password123',
            email='student2@example.com',
            role=User.Role.STUDENT,
            tutor=self.tutor1,
            first_name='Student',
            last_name='Two'
        )
        StudentProfile.objects.create(
            user=self.student2,
            tuition_fee=8000.00,
            cycle_length=8
        )
        classes2 = Cycle.build_fresh_classes_data(8)
        for i in range(2):
            classes2[i]['completed'] = True
        self.cycle2 = Cycle.objects.create(
            tutor=self.tutor1,
            student=self.student2,
            cycle_number=1,
            fee_snapshot=8000.00,
            total_classes=8,
            classes_data=classes2,
            status=Cycle.Status.ACTIVE
        )

        # Archived cycle for student 1 (historical: 10000 fee, 10 completed -> earned 10000)
        classes_archived = Cycle.build_fresh_classes_data(10)
        for i in range(10):
            classes_archived[i]['completed'] = True
        self.cycle_archived = Cycle.objects.create(
            tutor=self.tutor1,
            student=self.student1,
            cycle_number=0,
            fee_snapshot=10000.00,
            total_classes=10,
            classes_data=classes_archived,
            status=Cycle.Status.ARCHIVED
        )

        # Tutor 2 with a different student to test multi-tenancy isolation
        self.tutor2 = User.objects.create_user(
            username='tutor2',
            password='password123',
            email='tutor2@example.com',
            role=User.Role.TUTOR,
            first_name='Tutor',
            last_name='Two'
        )

        self.wallet_url = reverse('wallet-analytics')

    def test_wallet_metrics_calculation(self):
        self.client.force_authenticate(user=self.tutor1)
        response = self.client.get(self.wallet_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        data = response.data
        self.assertEqual(data['total_students'], 2)
        # 3000 + 2000 = 5000 earned
        self.assertEqual(data['total_earned'], 5000.00)
        # 9000 + 6000 = 15000 pending
        self.assertEqual(data['total_pending'], 15000.00)
        # Lifetime archived: 10000
        self.assertEqual(data['lifetime_archived_earnings'], 10000.00)

        # Check chart data
        chart = {item['name']: item['value'] for item in data['chart_data']}
        self.assertEqual(chart['Earned'], 5000.00)
        self.assertEqual(chart['Pending'], 15000.00)

        # Check student breakdowns
        breakdowns = data['student_breakdowns']
        self.assertEqual(len(breakdowns), 2)

    def test_multi_tenant_isolation_in_wallet(self):
        # Tutor 2 has no students yet -> should have 0 across the board
        self.client.force_authenticate(user=self.tutor2)
        response = self.client.get(self.wallet_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['total_students'], 0)
        self.assertEqual(response.data['total_earned'], 0.0)
        self.assertEqual(response.data['total_pending'], 0.0)
        self.assertEqual(response.data['lifetime_archived_earnings'], 0.0)

    def test_student_cannot_access_wallet(self):
        self.client.force_authenticate(user=self.student1)
        response = self.client.get(self.wallet_url)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
