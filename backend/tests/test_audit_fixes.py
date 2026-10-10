"""
Regression tests for the full-stack audit (branch audit/full-stack-fixes).

Each test pins one fixed defect: tenant isolation on routines, schedules and
homework, shared group homework, upload checks, money privacy in student
notifications, routine validation and query counts.
"""
from datetime import timedelta

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.cycles.models import AttendanceCycle
from apps.exams.models import Exam
from apps.students.models import (
    ClassSchedule, ConnectionRequest, Homework, Tuition, TuitionEnrollment, WeeklyRoutine,
)

User = get_user_model()

PNG = b'\x89PNG\r\n\x1a\n' + b'\x00' * 24
PDF = b'%PDF-1.4\n' + b'\x00' * 24


def make_user(username, role, **extra):
    return User.objects.create_user(username=username, password='Password123!', role=role, **extra)


class AuditBase(APITestCase):
    def setUp(self):
        self.tutor = make_user('tutor_a', User.Role.TUTOR, first_name='Amin')
        self.other_tutor = make_user('tutor_b', User.Role.TUTOR, first_name='Bashir')
        self.student = make_user('stu_a', User.Role.STUDENT, tutor=self.tutor, first_name='Rafi')
        self.classmate = make_user('stu_b', User.Role.STUDENT, tutor=self.tutor, first_name='Nila')
        self.outsider = make_user('stu_c', User.Role.STUDENT, tutor=self.other_tutor, first_name='Omar')
        self.tuition = Tuition.objects.create(tutor=self.tutor, title='Physics', total_fee=1200, cycle_length=12)
        self.other_tuition = Tuition.objects.create(tutor=self.other_tutor, title='Chemistry', total_fee=900)
        for s in (self.student, self.classmate):
            TuitionEnrollment.objects.create(tuition=self.tuition, student=s)
        TuitionEnrollment.objects.create(tuition=self.other_tuition, student=self.outsider)

    def as_user(self, user):
        self.client.force_authenticate(user=user)


class RoutineAndScheduleTenancyTests(AuditBase):
    def setUp(self):
        super().setUp()
        self.routine = WeeklyRoutine.objects.create(
            tutor=self.tutor, tuition=self.tuition, day_of_week='SUNDAY',
            start_time='17:00', end_time='18:00', subject='Physics',
        )
        self.schedule = ClassSchedule.objects.create(
            tutor=self.tutor, tuition=self.tuition, scheduled_at=timezone.now() + timedelta(days=1), topic='Optics',
        )

    def test_student_can_read_but_never_change_routines_or_classes(self):
        self.as_user(self.student)
        self.assertEqual(self.client.get('/api/v1/routines/').status_code, status.HTTP_200_OK)
        for url in (f'/api/v1/routines/{self.routine.id}/', f'/api/v1/schedules/{self.schedule.id}/'):
            self.assertEqual(self.client.patch(url, {'subject': 'x', 'topic': 'x'}, format='json').status_code,
                             status.HTTP_403_FORBIDDEN)
            self.assertEqual(self.client.delete(url).status_code, status.HTTP_403_FORBIDDEN)
        self.assertTrue(WeeklyRoutine.objects.filter(pk=self.routine.pk).exists())
        self.assertTrue(ClassSchedule.objects.filter(pk=self.schedule.pk).exists())

    def test_tutor_cannot_attach_routine_or_class_to_another_tutors_group_or_student(self):
        self.as_user(self.tutor)
        bad = [
            ('/api/v1/routines/', {'day_of_week': 'MONDAY', 'start_time': '10:00', 'end_time': '11:00',
                                   'tuition': str(self.other_tuition.id)}),
            ('/api/v1/routines/', {'day_of_week': 'MONDAY', 'start_time': '10:00', 'end_time': '11:00',
                                   'student': str(self.outsider.id)}),
            ('/api/v1/schedules/', {'scheduled_at': '2030-01-01T10:00:00Z', 'tuition': str(self.other_tuition.id)}),
        ]
        for url, payload in bad:
            self.assertEqual(self.client.post(url, payload, format='json').status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(WeeklyRoutine.objects.filter(tutor=self.tutor).count(), 1)

    def test_partial_update_keeps_the_target(self):
        self.as_user(self.tutor)
        resp = self.client.patch(f'/api/v1/routines/{self.routine.id}/', {'subject': 'Mechanics'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        self.routine.refresh_from_db()
        self.assertEqual((self.routine.subject, self.routine.tuition_id), ('Mechanics', self.tuition.id))

    def test_student_routine_list_has_no_duplicates_and_ignores_left_groups(self):
        enr = TuitionEnrollment.objects.get(tuition=self.tuition, student=self.student)
        self.as_user(self.student)
        rows = self.client.get('/api/v1/routines/').data['results']
        self.assertEqual([r['id'] for r in rows], [str(self.routine.id)])
        enr.is_active = False
        enr.save()
        self.assertEqual(self.client.get('/api/v1/routines/').data['results'], [])


class HomeworkTenancyTests(AuditBase):
    def _homework(self, **target):
        return Homework.objects.create(tutor=self.tutor, title='Ch 1', due_date=timezone.now() + timedelta(days=2), **target)

    def test_partial_update_of_title_only_works(self):
        hw = self._homework(student=self.student)
        self.as_user(self.tutor)
        resp = self.client.patch(f'/api/v1/homework/{hw.id}/', {'title': 'Chapter 1'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        hw.refresh_from_db()
        self.assertEqual((hw.title, hw.student_id), ('Chapter 1', self.student.id))

    def test_cannot_move_homework_to_another_tutors_student_or_group(self):
        hw = self._homework(student=self.student)
        self.as_user(self.tutor)
        for payload in ({'student': str(self.outsider.id)},
                        {'student': None, 'tuition': str(self.other_tuition.id)}):
            resp = self.client.patch(f'/api/v1/homework/{hw.id}/', payload, format='json')
            self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST, payload)
        hw.refresh_from_db()
        self.assertEqual(hw.student_id, self.student.id)

    def test_can_assign_to_a_connected_student_whose_account_another_tutor_owns(self):
        ConnectionRequest.objects.create(student=self.outsider, tutor=self.tutor,
                                         status=ConnectionRequest.Status.ACCEPTED)
        self.as_user(self.tutor)
        resp = self.client.post('/api/v1/homework/', {
            'title': 'Welcome task', 'due_date': '2030-01-01T10:00:00Z', 'student': str(self.outsider.id),
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)

    def test_invalid_tutor_filter_is_a_400_not_a_crash(self):
        self.as_user(self.student)
        self.assertEqual(self.client.get('/api/v1/homework/?tutor_id=nope').status_code, status.HTTP_400_BAD_REQUEST)

    def test_submitting_a_group_task_makes_a_personal_copy(self):
        group = self._homework(tuition=self.tuition)
        self.as_user(self.student)
        resp = self.client.post(f'/api/v1/homework/{group.id}/submit/',
                                {'submitted_online_url': 'https://docs.example.com/rafi'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        copy_id = resp.data['homework']['id']
        self.assertNotEqual(copy_id, str(group.id))
        self.assertEqual(resp.data['homework']['group_source_id'], group.id)

        group.refresh_from_db()
        self.assertEqual(group.submitted_online_url, '')  # the shared row is untouched

        mine = [h['id'] for h in self.client.get('/api/v1/homework/').data['results']]
        self.assertEqual(mine, [copy_id])  # the copy replaces the shared row for this student

        self.as_user(self.classmate)
        theirs = self.client.get('/api/v1/homework/').data['results']
        self.assertEqual([h['id'] for h in theirs], [str(group.id)])
        self.assertFalse(theirs[0]['is_submitted'])

        # Submitting again updates the same copy.
        self.as_user(self.student)
        again = self.client.post(f'/api/v1/homework/{copy_id}/submit/',
                                 {'submitted_online_url': 'https://docs.example.com/rafi-v2'}, format='json')
        self.assertEqual(again.data['homework']['id'], copy_id)
        self.assertEqual(Homework.objects.filter(group_source=group).count(), 1)

    def test_tutor_detail_shows_the_copy_instead_of_the_shared_row(self):
        group = self._homework(tuition=self.tuition)
        ConnectionRequest.objects.create(student=self.student, tutor=self.tutor,
                                         status=ConnectionRequest.Status.ACCEPTED)
        self.as_user(self.student)
        self.client.post(f'/api/v1/homework/{group.id}/submit/', {'submitted_online_url': 'https://x.io'}, format='json')
        detail = self.client.get(f'/api/v1/my-tutors/{self.tutor.id}/').data
        self.assertEqual([h['group_source_id'] for h in detail['homework']], [group.id])

    def test_split_is_one_atomic_server_step_and_keeps_existing_work(self):
        group = self._homework(tuition=self.tuition)
        group.personal_copy_for(self.student)
        Homework.objects.filter(group_source=group, student=self.student).update(submitted_online_url='https://x.io')
        self.as_user(self.tutor)
        resp = self.client.post(f'/api/v1/homework/{group.id}/split/')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        self.assertFalse(Homework.objects.filter(pk=group.pk).exists())
        rows = {h['student_id']: h for h in resp.data['homework']}
        self.assertEqual(set(rows), {self.student.id, self.classmate.id})
        self.assertEqual(rows[self.student.id]['submitted_online_url'], 'https://x.io')

    def test_split_refuses_individual_homework(self):
        hw = self._homework(student=self.student)
        self.as_user(self.tutor)
        self.assertEqual(self.client.post(f'/api/v1/homework/{hw.id}/split/').status_code, status.HTTP_400_BAD_REQUEST)

    def test_submission_files_are_checked_like_any_upload(self):
        hw = self._homework(student=self.student)
        self.as_user(self.student)
        evil = SimpleUploadedFile('answer.html', b'<script>alert(1)</script>', content_type='text/html')
        resp = self.client.post(f'/api/v1/homework/{hw.id}/submit/', {'submission_file': evil}, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        fake = SimpleUploadedFile('answer.png', b'<html>' + b'\x00' * 20, content_type='image/png')
        resp = self.client.post(f'/api/v1/homework/{hw.id}/submit/', {'submission_file': fake}, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        good = SimpleUploadedFile('answer.png', PNG, content_type='image/png')
        resp = self.client.post(f'/api/v1/homework/{hw.id}/submit/', {'submission_file': good}, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        self.assertTrue(resp.data['homework']['submission_file_url'])

    def test_link_must_be_a_web_address(self):
        hw = self._homework(student=self.student)
        self.as_user(self.student)
        resp = self.client.post(f'/api/v1/homework/{hw.id}/submit/',
                                {'submitted_online_url': 'ftp://files.example.com/a'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_checked_homework_cannot_be_resubmitted(self):
        hw = self._homework(student=self.student, is_evaluated=True)
        self.as_user(self.student)
        resp = self.client.post(f'/api/v1/homework/{hw.id}/submit/', {}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)


class UploadContentTests(AuditBase):
    def upload(self, name, data, content_type):
        self.as_user(self.tutor)
        return self.client.post('/api/v1/media/upload/', {'file': SimpleUploadedFile(name, data, content_type)},
                                format='multipart')

    def test_content_must_match_the_extension(self):
        self.assertEqual(self.upload('a.png', PDF, 'image/png').status_code, status.HTTP_400_BAD_REQUEST)
        riff_wav = b'RIFF\x00\x00\x00\x00WAVEfmt ' + b'\x00' * 16
        self.assertEqual(self.upload('a.webp', riff_wav, 'image/webp').status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.upload('a.png', PNG, 'image/png').status_code, status.HTTP_201_CREATED)
        self.assertEqual(self.upload('a.pdf', PDF, 'application/octet-stream').status_code, status.HTTP_201_CREATED)


class StudentNotificationPrivacyTests(AuditBase):
    def test_completed_group_cycle_notice_has_no_group_fee(self):
        cycle = AttendanceCycle.ensure_active(self.tuition)
        for n in range(1, cycle.total_classes + 1):
            cycle.mark_class(n, True)
        cycle.save()
        self.as_user(self.student)
        items = self.client.get('/api/v1/notifications/').data['notifications']
        due = [i for i in items if i['id'] == f'cycle-due-{cycle.id}']
        self.assertEqual(len(due), 1)
        self.assertNotIn('1,200', due[0]['body'])
        self.assertNotIn('৳', due[0]['body'])


class ExamSubmitImageUrlTests(AuditBase):
    def test_only_web_or_media_paths_are_accepted(self):
        now = timezone.now()
        exam = Exam.objects.create(tutor=self.tutor, tuition=self.tuition, title='Quiz', exam_type='CQ',
                                   start_time=now - timedelta(minutes=5), end_time=now + timedelta(hours=1))
        self.as_user(self.student)
        url = f'/api/v1/exams/{exam.id}/submit/'
        for bad in ('ftp://host/a.png', '//evil.example/a.png', 'data:image/png;base64,AAAA'):
            self.assertEqual(self.client.post(url, {'uploaded_images': [bad]}, format='json').status_code,
                             status.HTTP_400_BAD_REQUEST, bad)
        ok = self.client.post(url, {'uploaded_images': ['/media/uploads/2026/10/a.png']}, format='json')
        self.assertEqual(ok.status_code, status.HTTP_201_CREATED, ok.data)

    def test_exam_html_is_sanitized_on_save(self):
        now = timezone.now()
        exam = Exam.objects.create(tutor=self.tutor, tuition=self.tuition, title='Quiz',
                                   content_html='<p onclick="x()">Hi</p><script>bad()</script>',
                                   start_time=now, end_time=now + timedelta(hours=1))
        self.assertNotIn('script', exam.content_html)
        self.assertNotIn('onclick', exam.content_html)


class TuitionRoutineValidationTests(AuditBase):
    def test_routine_is_normalized(self):
        self.as_user(self.tutor)
        resp = self.client.patch(f'/api/v1/tuitions/{self.tuition.id}/', {'routine': [
            {'day': 'tuesday', 'time': '7:05', 'end_time': '08:30:00'},
            {'day': 'Sat', 'start_time': '18:00', 'end_time': '19:30'},
        ]}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        self.assertEqual(resp.data['routine'], [
            {'day': 'Saturday', 'start_time': '18:00', 'end_time': '19:30'},
            {'day': 'Tuesday', 'start_time': '07:05', 'end_time': '08:30'},
        ])

    def test_bad_routines_are_refused(self):
        self.as_user(self.tutor)
        for routine in ('Sunday 5pm', [{'day': 'Funday', 'start_time': '10:00', 'end_time': '11:00'}],
                        [{'day': 'Sunday', 'start_time': '25:00', 'end_time': '26:00'}],
                        [{'day': 'Sunday', 'start_time': '11:00', 'end_time': '10:00'}]):
            resp = self.client.patch(f'/api/v1/tuitions/{self.tuition.id}/', {'routine': routine}, format='json')
            self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST, routine)


class TuitionResponsesAreFreshAndCheapTests(AuditBase):
    def test_mark_class_returns_the_new_wallet(self):
        self.as_user(self.tutor)
        AttendanceCycle.ensure_active(self.tuition)
        resp = self.client.patch(f'/api/v1/tuitions/{self.tuition.id}/mark_class/',
                                 {'class_no': 1, 'completed': True}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        self.assertEqual(resp.data['wallet_summary']['completed_classes'], 1)
        self.assertEqual(resp.data['wallet_summary']['earned_revenue'], 100.0)

    def test_tuition_list_query_count_does_not_grow_with_groups(self):
        self.as_user(self.tutor)
        with CaptureQueriesContext(connection) as few:
            self.client.get('/api/v1/tuitions/')
        for n in range(5):
            extra = Tuition.objects.create(tutor=self.tutor, title=f'Group {n}', total_fee=100)
            AttendanceCycle.ensure_active(extra)
            TuitionEnrollment.objects.create(tuition=extra, student=self.student)
        with CaptureQueriesContext(connection) as many:
            resp = self.client.get('/api/v1/tuitions/')
        self.assertEqual(resp.data['count'], 6)
        self.assertLessEqual(len(many), len(few) + 2)


class StudentVisibilityTests(AuditBase):
    def test_connected_tutor_card_lists_only_the_students_own_groups(self):
        Tuition.objects.create(tutor=self.tutor, title='Private group', routine=[])
        ConnectionRequest.objects.create(student=self.student, tutor=self.tutor,
                                         status=ConnectionRequest.Status.ACCEPTED)
        self.as_user(self.student)
        cards = self.client.get('/api/v1/my-tutors/').data
        self.assertEqual([t['title'] for t in cards[0]['tuitions']], ['Physics'])

    def test_owner_notes_and_fee_are_hidden_from_a_second_tutor(self):
        from apps.students.models import StudentProfile
        StudentProfile.objects.create(user=self.outsider, notes='Pays late', tuition_fee=1500)
        ConnectionRequest.objects.create(student=self.outsider, tutor=self.tutor,
                                         status=ConnectionRequest.Status.ACCEPTED)
        self.as_user(self.tutor)
        row = next(s for s in self.client.get('/api/v1/students/').data['results'] if s['id'] == str(self.outsider.id))
        self.assertNotIn('notes', row['profile'])
        self.assertNotIn('tuition_fee', row['profile'])
        self.as_user(self.other_tutor)
        own = self.client.get(f'/api/v1/students/{self.outsider.id}/').data
        self.assertEqual(own['profile']['notes'], 'Pays late')

    def test_second_tutor_can_open_but_not_edit_a_connected_student(self):
        ConnectionRequest.objects.create(student=self.outsider, tutor=self.tutor,
                                         status=ConnectionRequest.Status.ACCEPTED)
        self.as_user(self.tutor)
        url = f'/api/v1/students/{self.outsider.id}/'
        self.assertEqual(self.client.get(url).status_code, status.HTTP_200_OK)
        self.assertEqual(self.client.patch(url, {'first_name': 'X'}, format='json').status_code,
                         status.HTTP_404_NOT_FOUND)
        self.assertEqual(self.client.delete(url).status_code, status.HTTP_404_NOT_FOUND)


class CycleRaceTests(AuditBase):
    def test_ensure_active_returns_the_existing_cycle_when_creation_loses_a_race(self):
        from unittest import mock

        from django.db import IntegrityError, transaction
        from django.db.models.query import QuerySet

        first = AttendanceCycle.ensure_active(self.tuition)
        # The losing request: its pre-check saw no cycle, then its insert collided.
        with transaction.atomic(), \
                mock.patch.object(QuerySet, 'first', return_value=None), \
                mock.patch.object(AttendanceCycle, 'start_for', side_effect=IntegrityError('duplicate')):
            again = AttendanceCycle.ensure_active(self.tuition)
            # The surrounding transaction is still usable.
            self.assertTrue(Tuition.objects.filter(pk=self.tuition.pk).exists())
        self.assertEqual(again.pk, first.pk)


class SettingsHardeningTests(AuditBase):
    def test_no_blanket_onrender_cors_or_cookies(self):
        self.assertFalse(any('onrender' in r for r in settings.CORS_ALLOWED_ORIGIN_REGEXES))
        self.assertNotIn('https://*.onrender.com', settings.CSRF_TRUSTED_ORIGINS)
        self.assertFalse(settings.CORS_ALLOW_CREDENTIALS)

    def test_meta_lists_the_shared_upload_rules(self):
        self.client.force_authenticate(user=None)
        data = self.client.get('/api/v1/meta/').data
        self.assertEqual(data['uploads']['extensions'], ['.jpeg', '.jpg', '.pdf', '.png', '.webp'])



class SolutionLinkTests(AuditBase):
    def test_solution_link_must_be_a_file_or_web_address(self):
        self.as_user(self.tutor)
        now = timezone.now()
        payload = {
            'title': 'Quiz', 'exam_type': 'CQ', 'tuition_id': str(self.tuition.id),
            'start_time': (now + timedelta(hours=1)).isoformat(), 'end_time': (now + timedelta(hours=2)).isoformat(),
        }
        bad = self.client.post('/api/v1/exams/', {**payload, 'solution_media_url': 'javascript:alert(1)'}, format='json')
        self.assertEqual(bad.status_code, status.HTTP_400_BAD_REQUEST)
        good = self.client.post('/api/v1/exams/', {**payload, 'solution_media_url': '/media/uploads/a.pdf'}, format='json')
        self.assertEqual(good.status_code, status.HTTP_201_CREATED, good.data)


class OfflineSyncSupportTests(AuditBase):
    def test_homework_create_with_the_same_client_ref_is_made_once(self):
        self.as_user(self.tutor)
        payload = {'title': 'Ch 5', 'due_date': '2030-01-01T10:00:00Z', 'tuition': str(self.tuition.id),
                   'client_ref': 'phone-1234'}
        first = self.client.post('/api/v1/homework/', payload, format='json')
        again = self.client.post('/api/v1/homework/', payload, format='json')
        self.assertEqual(first.status_code, status.HTTP_201_CREATED, first.data)
        self.assertEqual(again.status_code, status.HTTP_200_OK)
        self.assertEqual(first.data['id'], again.data['id'])
        self.assertEqual(first.data['client_ref'], 'phone-1234')
        self.assertEqual(Homework.objects.filter(tutor=self.tutor, client_ref='phone-1234').count(), 1)
        # Another tutor may use the same key for their own homework.
        self.as_user(self.other_tutor)
        other = self.client.post('/api/v1/homework/', {**payload, 'tuition': str(self.other_tuition.id)}, format='json')
        self.assertEqual(other.status_code, status.HTTP_201_CREATED, other.data)

    def test_marking_a_class_twice_is_harmless(self):
        self.as_user(self.tutor)
        AttendanceCycle.ensure_active(self.tuition)
        url = f'/api/v1/tuitions/{self.tuition.id}/mark_class/'
        body = {'class_no': 2, 'completed': True, 'date': '2026-10-01T12:00:00Z', 'topic': 'Optics'}
        self.assertEqual(self.client.patch(url, body, format='json').status_code, status.HTTP_200_OK)
        again = self.client.patch(url, body, format='json')
        self.assertEqual(again.status_code, status.HTTP_200_OK)
        self.assertEqual(again.data['cycle']['completed_classes'], 1)

    def test_homework_and_connection_lists_are_paged(self):
        for n in range(3):
            Homework.objects.create(tutor=self.tutor, student=self.student, title=f'H{n}',
                                    due_date=timezone.now() + timedelta(days=n + 1))
        self.as_user(self.tutor)
        page = self.client.get('/api/v1/homework/?page_size=2').data
        self.assertEqual((page['count'], len(page['results'])), (3, 2))
        self.assertIsNotNone(page['next'])
        self.assertIn('results', self.client.get('/api/v1/connections/').data)


class BackgroundEmailTests(AuditBase):
    def test_password_reset_mail_is_still_sent(self):
        from django.core import mail
        self.tutor.email = 'amin@example.com'
        self.tutor.save()
        self.client.post('/api/v1/auth/password-reset/', {'identifier': 'amin@example.com'}, format='json')
        self.assertEqual(len(mail.outbox), 1)

    def test_a_failing_background_task_is_logged_not_raised(self):
        from config.background import run_after_commit

        def boom():
            raise RuntimeError('mail server down')

        with self.assertLogs('config.background', level='ERROR'):
            run_after_commit(boom)


class ApiSchemaTests(AuditBase):
    def test_schema_is_staff_only_and_builds(self):
        self.assertIn(self.client.get('/api/v1/schema/').status_code, (401, 403))
        admin = User.objects.create_user(username='boss', password='Passw0rd!x', role=User.Role.TUTOR, is_staff=True)
        self.client.force_authenticate(user=admin)
        resp = self.client.get('/api/v1/schema/?format=json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
