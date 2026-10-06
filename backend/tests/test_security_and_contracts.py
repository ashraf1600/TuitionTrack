"""
Regression & Security Tests for TuitionTrack.
Covers:
1. Student role permission restrictions on ExamViewSet, TuitionViewSet, AttendanceCycleViewSet.
2. Cross-tenant isolation (Tutor A targeting Tutor B's student).
3. Pre-start time exam content leakage prevention.
4. Concurrency test on toggle_class verifying atomic locks and no lost updates.
5. Financial accounting Decimal precision.
"""
from decimal import Decimal
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from django.utils import timezone
from django.contrib.auth import get_user_model
from django.db import connection
from rest_framework import status
from rest_framework.test import APITestCase, APITransactionTestCase, APIClient

from apps.students.models import Tuition, TuitionEnrollment
from apps.cycles.models import AttendanceCycle
from apps.exams.models import Exam

User = get_user_model()


class SecurityAndPermissionsTests(APITestCase):
    def setUp(self):
        # Tutor A & Student A
        self.tutor_a = User.objects.create_user(
            username='tutor_a',
            email='tutor_a@example.com',
            password='StrongPassword123!',
            role=User.Role.TUTOR,
        )
        self.student_a = User.objects.create_user(
            username='student_a',
            email='student_a@example.com',
            password='StrongPassword123!',
            role=User.Role.STUDENT,
            tutor=self.tutor_a,
        )

        # Tutor B & Student B
        self.tutor_b = User.objects.create_user(
            username='tutor_b',
            email='tutor_b@example.com',
            password='StrongPassword123!',
            role=User.Role.TUTOR,
        )
        self.student_b = User.objects.create_user(
            username='student_b',
            email='student_b@example.com',
            password='StrongPassword123!',
            role=User.Role.STUDENT,
            tutor=self.tutor_b,
        )

        # Tuition for Tutor A
        self.tuition_a = Tuition.objects.create(
            tutor=self.tutor_a,
            title='Physics Batch A',
            total_fee=Decimal('5000.00'),
            cycle_length=12,
        )
        self.enrollment_a = TuitionEnrollment.objects.create(
            tuition=self.tuition_a,
            student=self.student_a,
            is_active=True,
        )
        self.cycle_a = AttendanceCycle.objects.create(
            tuition=self.tuition_a,
            tutor=self.tutor_a,
            fee_snapshot=Decimal('5000.00'),
            total_classes=12,
            cycle_number=1,
            classes_data=AttendanceCycle.build_fresh_classes_data(12),
            status=AttendanceCycle.Status.ACTIVE,
        )

        # Exam for Tutor A
        now = timezone.now()
        self.future_exam = Exam.objects.create(
            tutor=self.tutor_a,
            tuition=self.tuition_a,
            student=self.student_a,
            title='Upcoming Finals',
            start_time=now + timedelta(days=1),
            end_time=now + timedelta(days=1, hours=2),
            duration_minutes=120,
            total_marks=100,
            content_html='<p>Top secret questions that cannot be leaked</p>',
            mcq_data=[{
                'id': 'q1',
                'question': 'What is 2+2?',
                'options': ['3', '4', '5'],
                'correct_answer': 1,
                'explanation': '2+2 is 4',
                'points': 5,
            }],
            is_published=True,
        )

    # ──────────────────────────────────────────────────────────────────────────
    # 1. Student Role Permissions on ViewSets
    # ──────────────────────────────────────────────────────────────────────────
    def test_student_cannot_post_patch_delete_on_exam_viewset(self):
        self.client.force_authenticate(user=self.student_a)

        # Attempt POST create
        post_resp = self.client.post('/api/v1/exams/', {
            'title': 'Hacked Exam',
            'tuition_id': str(self.tuition_a.id),
            'start_time': (timezone.now() + timedelta(days=2)).isoformat(),
            'end_time': (timezone.now() + timedelta(days=2, hours=1)).isoformat(),
            'total_marks': 50,
        }, format='json')
        self.assertEqual(post_resp.status_code, status.HTTP_403_FORBIDDEN)

        # Attempt PATCH
        patch_resp = self.client.patch(f'/api/v1/exams/{self.future_exam.id}/', {
            'total_marks': 10,
        }, format='json')
        self.assertEqual(patch_resp.status_code, status.HTTP_403_FORBIDDEN)

        # Attempt DELETE
        del_resp = self.client.delete(f'/api/v1/exams/{self.future_exam.id}/')
        self.assertEqual(del_resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_student_cannot_post_patch_delete_on_tuition_viewset(self):
        self.client.force_authenticate(user=self.student_a)

        # Attempt POST create
        post_resp = self.client.post('/api/v1/tuitions/', {
            'title': 'Student Created Tuition',
            'tuition_fee': 100,
            'cycle_length': 10,
        }, format='json')
        self.assertEqual(post_resp.status_code, status.HTTP_403_FORBIDDEN)

        # Attempt PATCH
        patch_resp = self.client.patch(f'/api/v1/tuitions/{self.tuition_a.id}/', {
            'tuition_fee': 1,
        }, format='json')
        self.assertEqual(patch_resp.status_code, status.HTTP_403_FORBIDDEN)

        # Attempt DELETE
        del_resp = self.client.delete(f'/api/v1/tuitions/{self.tuition_a.id}/')
        self.assertEqual(del_resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_student_cannot_post_patch_delete_on_attendance_cycle_viewset(self):
        self.client.force_authenticate(user=self.student_a)

        # Attempt POST
        post_resp = self.client.post('/api/v1/attendance-cycles/', {
            'enrollment_id': str(self.enrollment_a.id),
        }, format='json')
        self.assertIn(post_resp.status_code, [status.HTTP_403_FORBIDDEN, status.HTTP_405_METHOD_NOT_ALLOWED])

        # Attempt PATCH
        patch_resp = self.client.patch(f'/api/v1/attendance-cycles/{self.cycle_a.id}/', {
            'classes_data': [],
        }, format='json')
        self.assertEqual(patch_resp.status_code, status.HTTP_403_FORBIDDEN)

        # Attempt DELETE
        del_resp = self.client.delete(f'/api/v1/attendance-cycles/{self.cycle_a.id}/')
        self.assertIn(del_resp.status_code, [status.HTTP_403_FORBIDDEN, status.HTTP_405_METHOD_NOT_ALLOWED])

        # Attempt toggle_class
        toggle_resp = self.client.patch(f'/api/v1/attendance-cycles/{self.cycle_a.id}/toggle_class/', {
            'class_no': 1,
            'completed': True,
        }, format='json')
        self.assertEqual(toggle_resp.status_code, status.HTTP_403_FORBIDDEN)

    # ──────────────────────────────────────────────────────────────────────────
    # 2. Cross-Tenant Isolation
    # ──────────────────────────────────────────────────────────────────────────
    def test_tutor_cannot_enroll_student_belonging_to_another_tutor(self):
        self.client.force_authenticate(user=self.tutor_a)

        # Tutor A attempts to enroll Student B (owned by Tutor B)
        resp = self.client.post(f'/api/v1/tuitions/{self.tuition_a.id}/enroll/', {
            'student_id': str(self.student_b.id),
        }, format='json')
        self.assertIn(resp.status_code, [status.HTTP_400_BAD_REQUEST, status.HTTP_403_FORBIDDEN])

    def test_tutor_cannot_target_another_tutors_student_in_exam(self):
        self.client.force_authenticate(user=self.tutor_a)

        # Tutor A attempts to create an exam targeting Student B
        resp = self.client.post('/api/v1/exams/', {
            'title': 'Stolen Exam',
            'student_id': str(self.student_b.id),
            'start_time': (timezone.now() + timedelta(days=2)).isoformat(),
            'end_time': (timezone.now() + timedelta(days=2, hours=1)).isoformat(),
            'total_marks': 50,
            'is_published': True,
        }, format='json')
        self.assertIn(resp.status_code, [status.HTTP_400_BAD_REQUEST, status.HTTP_403_FORBIDDEN])

    def test_tutor_cannot_create_tuition_with_another_tutors_student(self):
        self.client.force_authenticate(user=self.tutor_a)

        resp = self.client.post('/api/v1/tuitions/', {
            'title': 'Poaching Tuition',
            'tuition_fee': 2000,
            'cycle_length': 8,
            'student_ids': [str(self.student_b.id)],
        }, format='json')
        self.assertIn(resp.status_code, [status.HTTP_400_BAD_REQUEST, status.HTTP_403_FORBIDDEN])

    # ──────────────────────────────────────────────────────────────────────────
    # 3. Pre-Start Time Exam Leak Protection
    # ──────────────────────────────────────────────────────────────────────────
    def test_student_fetching_exam_before_start_time_does_not_leak_content(self):
        self.client.force_authenticate(user=self.student_a)

        resp = self.client.get(f'/api/v1/exams/{self.future_exam.id}/')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        data = resp.data

        # Verify title, times and format are present
        self.assertEqual(data.get('title'), 'Upcoming Finals')
        self.assertIn('start_time', data)
        self.assertIn('end_time', data)

        # Content HTML must be stripped / empty / omitted
        content_html = data.get('content_html')
        self.assertTrue(not content_html, f"Expected empty content_html but got: {content_html}")

        # Questions / MCQ data / options must be omitted or empty
        mcq_data = data.get('mcq_data')
        self.assertTrue(not mcq_data or len(mcq_data) == 0, f"Expected empty mcq_data but got: {mcq_data}")

        # Solution must be stripped
        self.assertTrue(not data.get('solution_html'))

    # ──────────────────────────────────────────────────────────────────────────
    # 5. Cycle Fee Decimal Precision
    # ──────────────────────────────────────────────────────────────────────────
    def test_cycle_fee_calculation_exact_decimal_precision(self):
        cycle = self.cycle_a
        cycle.fee_snapshot = Decimal('5000.00')
        cycle.total_classes = 12

        classes = AttendanceCycle.build_fresh_classes_data(12)
        for c in classes:
            c['completed'] = True
        cycle.classes_data = classes
        cycle.save()

        earned = cycle.earned_revenue
        pending = cycle.pending_balance

        self.assertIsInstance(earned, Decimal, f"earned_revenue should be Decimal, got {type(earned)}")
        self.assertIsInstance(pending, Decimal, f"pending_balance should be Decimal, got {type(pending)}")
        self.assertEqual(earned, Decimal('5000.00'))
        self.assertEqual(pending, Decimal('0.00'))



class ConcurrencyAttendanceToggleTests(APITransactionTestCase):
    def test_rapid_concurrent_patch_requests_on_toggle_class_no_lost_updates(self):
        tutor = User.objects.create_user(
            username='conc_tutor',
            email='conc_tutor@example.com',
            password='StrongPassword123!',
            role=User.Role.TUTOR,
        )
        student = User.objects.create_user(
            username='conc_student',
            email='conc_student@example.com',
            password='StrongPassword123!',
            role=User.Role.STUDENT,
            tutor=tutor,
        )
        tuition = Tuition.objects.create(
            tutor=tutor,
            title='Concurrency Tuition',
            total_fee=Decimal('5000.00'),
            cycle_length=12,
        )
        enrollment = TuitionEnrollment.objects.create(
            tuition=tuition,
            student=student,
            is_active=True,
        )
        cycle = AttendanceCycle.objects.create(
            tuition=tuition,
            tutor=tutor,
            fee_snapshot=Decimal('5000.00'),
            total_classes=12,
            cycle_number=1,
            classes_data=AttendanceCycle.build_fresh_classes_data(12),
            status=AttendanceCycle.Status.ACTIVE,
        )

        from rest_framework_simplejwt.tokens import RefreshToken
        refresh = RefreshToken.for_user(tutor)
        access_token = str(refresh.access_token)

        def make_toggle_request(class_no):
            from django.db import connection as db_conn
            import time
            for attempt in range(10):
                try:
                    cl = APIClient()
                    cl.credentials(HTTP_AUTHORIZATION=f'Bearer {access_token}')
                    return cl.patch(
                        f'/api/v1/attendance-cycles/{cycle.id}/toggle_class/',
                        {'class_no': class_no, 'completed': True, 'topic': f'Topic {class_no}'},
                        format='json'
                    )
                except Exception as e:
                    if 'locked' in str(e).lower() and attempt < 9:
                        time.sleep(0.1 * (attempt + 1))
                        continue
                    raise
                finally:
                    db_conn.close()

        classes_to_toggle = [1, 2, 3, 4]
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(make_toggle_request, classes_to_toggle))


        for r in results:
            self.assertEqual(r.status_code, status.HTTP_200_OK)

        cycle.refresh_from_db()
        completed_classes = [
            c['class_no'] for c in cycle.classes_data
            if c.get('completed') is True
        ]

        for class_no in classes_to_toggle:
            self.assertIn(class_no, completed_classes, f"Class {class_no} lost due to race condition!")

