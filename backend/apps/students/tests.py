"""Tests for Students app and Multi-Tenancy Guard"""
from decimal import Decimal
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

        # Verify no ghost legacy cycle created per P1 architecture (cycles are initialized on tuition enrollment)
        self.assertFalse(Cycle.objects.filter(student=student).exists())

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
        # Picking a tutor at registration leaves a pending request in their inbox.
        from apps.students.models import ConnectionRequest
        self.connection = ConnectionRequest.objects.create(student=self.student, tutor=self.tutor)

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
        self.assertEqual(u_resp.data[0]['request_status'], 'PENDING')

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
        cycle = AttendanceCycle.objects.filter(tuition_id=tuition_id).first()
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



class GroupTuitionWorkflowTests(APITestCase):
    """Tutor -> Tuition group -> many students, with one shared cycle."""

    def setUp(self):
        from apps.students.models import ConnectionRequest
        self.tutor = User.objects.create_user(username='g_tutor', password='password123', role=User.Role.TUTOR)
        self.other_tutor = User.objects.create_user(username='g_other', password='password123', role=User.Role.TUTOR)
        self.students = [
            User.objects.create_user(username=f'g_student{i}', password='password123', role=User.Role.STUDENT)
            for i in range(3)
        ]
        for s in self.students:
            ConnectionRequest.objects.create(student=s, tutor=self.tutor)

    def _create_group(self):
        self.client.force_authenticate(user=self.tutor)
        resp = self.client.post(reverse('tuition-list'), {
            'title': 'Class 10 Math Batch',
            'cycle_length': 8,
            'total_fee': '12000.00',
            'student_ids': [str(s.id) for s in self.students],
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        return resp.data

    def test_registration_creates_pending_request_not_a_link(self):
        from apps.students.models import ConnectionRequest
        self.client.force_authenticate(user=None)
        resp = self.client.post(reverse('student_register'), {
            'username': 'fresh_student', 'password': 'StrongPass123!', 'password_confirm': 'StrongPass123!',
            'first_name': 'Fresh', 'grade_level': 'Class 10', 'address': 'Dhaka', 'phone': '017',
            'selected_tutor_id': str(self.tutor.id),
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        student = User.objects.get(username='fresh_student')
        self.assertIsNone(student.tutor_id)
        self.assertEqual(student.student_profile.address, 'Dhaka')
        self.assertEqual(
            ConnectionRequest.objects.get(student=student, tutor=self.tutor).status,
            ConnectionRequest.Status.PENDING,
        )

    def test_student_requests_tutor_then_tutor_accepts_into_group(self):
        from apps.students.models import ConnectionRequest
        newcomer = User.objects.create_user(username='g_new', password='password123', role=User.Role.STUDENT)
        group = self._create_group()

        self.client.force_authenticate(user=newcomer)
        resp = self.client.post(reverse('connection-list'), {'tutor_id': str(self.tutor.id), 'message': 'Hi'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        request_id = resp.data['id']
        # Duplicate pending request is refused
        dup = self.client.post(reverse('connection-list'), {'tutor_id': str(self.tutor.id)}, format='json')
        self.assertEqual(dup.status_code, status.HTTP_400_BAD_REQUEST)

        # Another tutor cannot see or act on it
        self.client.force_authenticate(user=self.other_tutor)
        self.assertEqual(len(self.client.get(reverse('connection-list')).data), 0)
        self.assertEqual(
            self.client.post(reverse('connection-accept', kwargs={'pk': request_id})).status_code,
            status.HTTP_404_NOT_FOUND,
        )

        self.client.force_authenticate(user=self.tutor)
        inbox = self.client.get(reverse('connection-list'), {'status': 'PENDING'})
        self.assertIn(request_id, [r['id'] for r in inbox.data])
        acc = self.client.post(reverse('connection-accept', kwargs={'pk': request_id}), {'tuition_id': group['id']}, format='json')
        self.assertEqual(acc.status_code, status.HTTP_200_OK, acc.data)
        self.assertEqual(ConnectionRequest.objects.get(id=request_id).status, ConnectionRequest.Status.ACCEPTED)
        newcomer.refresh_from_db()
        self.assertEqual(newcomer.tutor_id, self.tutor.id)

        self.client.force_authenticate(user=newcomer)
        mine = self.client.get(reverse('tuition-list'))
        rows = mine.data if isinstance(mine.data, list) else mine.data['results']
        self.assertEqual([t['title'] for t in rows], ['Class 10 Math Batch'])

    def test_rejected_request_gives_tutor_no_access(self):
        newcomer = User.objects.create_user(username='g_rej', password='password123', role=User.Role.STUDENT)
        group = self._create_group()
        self.client.force_authenticate(user=newcomer)
        request_id = self.client.post(reverse('connection-list'), {'tutor_username': 'g_tutor'}, format='json').data['id']

        self.client.force_authenticate(user=self.tutor)
        self.assertEqual(self.client.post(reverse('connection-reject', kwargs={'pk': request_id})).status_code, 200)
        enroll = self.client.post(reverse('tuition-enroll', kwargs={'pk': group['id']}), {'student_id': str(newcomer.id)}, format='json')
        self.assertEqual(enroll.status_code, status.HTTP_403_FORBIDDEN)

    def test_one_shared_cycle_for_the_whole_group(self):
        from apps.cycles.models import AttendanceCycle
        group = self._create_group()
        self.assertEqual(group['enrolled_count'], 3)
        self.assertEqual(AttendanceCycle.objects.filter(tuition_id=group['id']).count(), 1)

        # One tick by the tutor...
        resp = self.client.patch(reverse('tuition-mark-class', kwargs={'pk': group['id']}), {
            'class_no': 1, 'completed': True, 'topic': 'Algebra',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        # Wallet: (12000 / 8) * 1 — for the group, not per student
        self.assertEqual(resp.data['wallet_summary']['earned_revenue'], 1500.0)
        self.assertEqual(resp.data['wallet_summary']['pending_balance'], 10500.0)

        wallet = self.client.get(reverse('wallet-analytics')).data
        self.assertEqual(wallet['total_earned'], 1500.0)
        self.assertEqual(wallet['total_pending'], 10500.0)
        self.assertEqual(wallet['total_students'], 3)

        # ...is what every student in the group sees, date-stamped, with no money.
        for student in self.students:
            self.client.force_authenticate(user=student)
            rows = self.client.get(reverse('attendance-cycle-list')).data
            rows = rows if isinstance(rows, list) else rows['results']
            self.assertEqual(len(rows), 1)
            cycle = rows[0]
            self.assertEqual(cycle['completed_classes'], 1)
            self.assertTrue(cycle['classes_data'][0]['completed'])
            self.assertTrue(cycle['classes_data'][0]['date'])

            tuition = self.client.get(reverse('tuition-detail', kwargs={'pk': group['id']})).data
            self.assertEqual(tuition['active_cycle']['completed_classes'], 1)
            for payload in (cycle, tuition, tuition['active_cycle']):
                for key in ('total_fee', 'tuition_fee', 'monthly_fee', 'per_class_rate', 'earned_revenue',
                            'pending_balance', 'fee_snapshot', 'wallet_summary', 'enrollments', 'students_detail'):
                    self.assertNotIn(key, payload)

            self.assertEqual(self.client.get(reverse('wallet-analytics')).status_code, status.HTTP_403_FORBIDDEN)
            self.assertEqual(
                self.client.patch(reverse('tuition-mark-class', kwargs={'pk': group['id']}), {'class_no': 2, 'completed': True}, format='json').status_code,
                status.HTTP_403_FORBIDDEN,
            )

    def test_roster_changes_do_not_touch_the_cycle_or_earnings(self):
        from apps.cycles.models import AttendanceCycle
        group = self._create_group()
        cycle = AttendanceCycle.objects.get(tuition_id=group['id'])
        for n in (1, 2):
            self.client.patch(reverse('attendance-cycle-toggle-class', kwargs={'pk': cycle.id}), {'class_no': n, 'completed': True}, format='json')

        resp = self.client.post(reverse('tuition-unenroll', kwargs={'pk': group['id']}), {'student_id': str(self.students[0].id)}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['tuition']['enrolled_count'], 2)
        self.assertEqual(resp.data['tuition']['wallet_summary']['earned_revenue'], 3000.0)
        cycle.refresh_from_db()
        self.assertEqual(cycle.status, AttendanceCycle.Status.ACTIVE)
        self.assertEqual(cycle.completed_classes, 2)

        # The removed student no longer sees the group
        self.client.force_authenticate(user=self.students[0])
        rows = self.client.get(reverse('attendance-cycle-list')).data
        self.assertEqual(len(rows if isinstance(rows, list) else rows['results']), 0)

    def test_editing_group_updates_current_cycle_but_not_history(self):
        from apps.cycles.models import AttendanceCycle
        group = self._create_group()
        cycle = AttendanceCycle.objects.get(tuition_id=group['id'])
        for n in range(1, 9):
            self.client.patch(reverse('attendance-cycle-toggle-class', kwargs={'pk': cycle.id}), {'class_no': n, 'completed': True}, format='json')
        reset = self.client.post(reverse('attendance-cycle-reset', kwargs={'pk': cycle.id}))
        self.assertEqual(reset.status_code, status.HTTP_201_CREATED, reset.data)
        new_cycle_id = reset.data['cycle']['id']
        self.client.patch(reverse('attendance-cycle-toggle-class', kwargs={'pk': new_cycle_id}), {'class_no': 5, 'completed': True}, format='json')

        # Cannot shrink below a completed class
        bad = self.client.patch(reverse('tuition-detail', kwargs={'pk': group['id']}), {'cycle_length': 4}, format='json')
        self.assertEqual(bad.status_code, status.HTTP_400_BAD_REQUEST)

        ok = self.client.patch(reverse('tuition-detail', kwargs={'pk': group['id']}), {'cycle_length': 16, 'total_fee': '16000.00'}, format='json')
        self.assertEqual(ok.status_code, status.HTTP_200_OK, ok.data)
        self.assertEqual(ok.data['active_cycle']['total_classes'], 16)
        self.assertEqual(len(ok.data['active_cycle']['classes_data']), 16)
        self.assertEqual(ok.data['active_cycle']['completed_classes'], 1)
        self.assertEqual(ok.data['wallet_summary']['earned_revenue'], 1000.0)
        self.assertEqual(ok.data['wallet_summary']['archived_earnings'], 12000.0)

        cycle.refresh_from_db()
        self.assertEqual(cycle.total_classes, 8)
        self.assertEqual(cycle.earned_revenue, Decimal('12000.00'))

    def test_deleting_group_keeps_lifetime_earnings(self):
        from apps.cycles.models import AttendanceCycle
        group = self._create_group()
        cycle = AttendanceCycle.objects.get(tuition_id=group['id'])
        self.client.patch(reverse('attendance-cycle-toggle-class', kwargs={'pk': cycle.id}), {'class_no': 1, 'completed': True}, format='json')
        self.assertEqual(self.client.delete(reverse('tuition-detail', kwargs={'pk': group['id']})).status_code, status.HTTP_204_NO_CONTENT)
        wallet = self.client.get(reverse('wallet-analytics')).data
        self.assertEqual(wallet['total_earned'], 0.0)
        self.assertEqual(wallet['lifetime_archived_earnings'], 1500.0)

    def test_tutor_cannot_take_over_unrelated_student_account_by_username(self):
        stranger = User.objects.create_user(username='g_stranger', password='OriginalPass123!', role=User.Role.STUDENT)
        self.client.force_authenticate(user=self.tutor)
        resp = self.client.post(reverse('student-list-create'), {
            'username': 'g_stranger', 'password': 'HijackedPass123!', 'first_name': 'X',
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        stranger.refresh_from_db()
        self.assertTrue(stranger.check_password('OriginalPass123!'))
        self.assertIsNone(stranger.tutor_id)
