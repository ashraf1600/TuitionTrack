"""
What a second client (the mobile app) relies on: forgiving sign-in, sessions
that can really be ended, one date format, the meta endpoint and absolute
upload addresses.
"""
import re
from datetime import timedelta
from unittest import mock

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework.throttling import SimpleRateThrottle

from apps.exams.models import Exam
from apps.students.models import StudentProfile, Tuition

User = get_user_model()
PASSWORD = 'Str0ng-Passphrase-91'
ISO_UTC = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$')


class SignInTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(username='Rahim_Sir', password=PASSWORD, role=User.Role.TUTOR, email='rahim@example.com')
        self.student = User.objects.create_user(username='rafi', password=PASSWORD, role=User.Role.STUDENT, tutor=self.tutor)
        StudentProfile.objects.create(user=self.student)

    def login(self, username, password=PASSWORD):
        return self.client.post(reverse('token_obtain_pair'), {'username': username, 'password': password}, format='json')

    def test_username_in_any_capitalisation_or_email(self):
        for typed in ('Rahim_Sir', 'rahim_sir', ' RAHIM_SIR ', 'rahim@example.com', 'Rahim@Example.com'):
            resp = self.login(typed)
            self.assertEqual(resp.status_code, status.HTTP_200_OK, typed)
            self.assertEqual(resp.data['user']['username'], 'Rahim_Sir')
        wrong = self.login('rahim_sir', 'not-the-password')
        self.assertEqual(wrong.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(self.login('nobody').status_code, status.HTTP_401_UNAUTHORIZED)

    def test_usernames_and_emails_are_unique_ignoring_case(self):
        base = {'first_name': 'A', 'password': PASSWORD, 'password_confirm': PASSWORD}
        for url in (reverse('tutor_register'), reverse('student_register')):
            taken_name = self.client.post(url, {**base, 'username': 'RAFI'}, format='json')
            self.assertEqual(taken_name.status_code, status.HTTP_400_BAD_REQUEST)
            self.assertIn('username', taken_name.data)
            taken_email = self.client.post(url, {**base, 'username': 'fresh_name', 'email': 'RAHIM@example.com'}, format='json')
            self.assertEqual(taken_email.status_code, status.HTTP_400_BAD_REQUEST)
            self.assertIn('email', taken_email.data)
        # Changing my own email to someone else's is refused; keeping my own is fine.
        self.client.force_authenticate(user=self.student)
        self.assertEqual(self.client.patch(reverse('user_me'), {'email': 'rahim@example.com'}, format='json').status_code, 400)
        self.client.force_authenticate(user=self.tutor)
        self.assertEqual(self.client.patch(reverse('user_me'), {'email': 'Rahim@example.com'}, format='json').status_code, 200)
        # A tutor cannot create a student whose username differs only by case, or re-use an email.
        clash = self.client.post(reverse('student-list-create'), {'username': 'Rafi', 'password': 'temp-pass-1', 'first_name': 'R'}, format='json')
        self.assertEqual(clash.status_code, status.HTTP_400_BAD_REQUEST)
        email_clash = self.client.post(reverse('student-list-create'), {
            'username': 'brand_new', 'password': 'temp-pass-1', 'first_name': 'R', 'email': 'rahim@example.com',
        }, format='json')
        self.assertEqual(email_clash.status_code, status.HTTP_400_BAD_REQUEST)

    def test_sign_up_refuses_weak_passwords(self):
        for url in (reverse('tutor_register'), reverse('student_register')):
            for weak in ('password123', '12345678', 'newperson1'):
                resp = self.client.post(url, {
                    'username': 'newperson1', 'first_name': 'New', 'password': weak, 'password_confirm': weak,
                }, format='json')
                self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST, weak)
                self.assertIn('password', resp.data)
        ok = self.client.post(reverse('student_register'), {
            'username': 'newperson1', 'first_name': 'New', 'password': PASSWORD, 'password_confirm': PASSWORD,
        }, format='json')
        self.assertEqual(ok.status_code, status.HTTP_201_CREATED, ok.data)

    def test_sign_in_is_rate_limited(self):
        from django.core.cache import cache
        cache.clear()  # earlier sign-ins in this run must not count against the limit
        self.addCleanup(cache.clear)
        with mock.patch.dict(SimpleRateThrottle.THROTTLE_RATES, {'auth': '3/min'}):
            codes = [self.login('rafi', 'wrong-guess').status_code for _ in range(5)]
        self.assertEqual(codes[:3], [401, 401, 401])
        self.assertEqual(codes[3:], [429, 429])


class SessionTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(username='ses_tutor', password=PASSWORD, role=User.Role.TUTOR)
        self.student = User.objects.create_user(username='ses_student', password=PASSWORD, role=User.Role.STUDENT, tutor=self.tutor)
        StudentProfile.objects.create(user=self.student)

    def login(self, username, password=PASSWORD):
        resp = self.client.post(reverse('token_obtain_pair'), {'username': username, 'password': password}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        return resp.data

    def refresh(self, token):
        return self.client.post(reverse('token_refresh'), {'refresh': token}, format='json')

    def test_logout_ends_only_that_device(self):
        phone, laptop = self.login('ses_student'), self.login('ses_student')
        self.assertEqual(self.refresh(phone['refresh']).status_code, status.HTTP_200_OK)

        out = self.client.post(reverse('logout'), {'refresh': phone['refresh']}, format='json')
        self.assertEqual(out.status_code, status.HTTP_200_OK)
        self.assertEqual(self.refresh(phone['refresh']).status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(self.refresh(laptop['refresh']).status_code, status.HTTP_200_OK)
        # Signing out twice, or with rubbish, is not an error; sending nothing is.
        self.assertEqual(self.client.post(reverse('logout'), {'refresh': phone['refresh']}, format='json').status_code, 200)
        self.assertEqual(self.client.post(reverse('logout'), {'refresh': 'rubbish'}, format='json').status_code, 200)
        self.assertEqual(self.client.post(reverse('logout'), {}, format='json').status_code, 400)

    def test_logout_all(self):
        phone, laptop = self.login('ses_student'), self.login('ses_student')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {phone["access"]}')
        self.assertEqual(self.client.post(reverse('logout_all')).status_code, status.HTTP_200_OK)
        self.client.credentials()
        for session in (phone, laptop):
            self.assertEqual(self.refresh(session['refresh']).status_code, status.HTTP_401_UNAUTHORIZED)

    def test_changing_the_password_signs_other_devices_out(self):
        phone, laptop = self.login('ses_student'), self.login('ses_student')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {phone["access"]}')
        changed = self.client.post(reverse('change_password'), {'current_password': PASSWORD, 'new_password': 'An0ther-Passphrase-7'}, format='json')
        self.client.credentials()
        self.assertEqual(changed.status_code, status.HTTP_200_OK, changed.data)
        for old in (phone, laptop):
            self.assertEqual(self.refresh(old['refresh']).status_code, status.HTTP_401_UNAUTHORIZED)
        # The device that changed it carries on with the session it was handed back.
        self.assertEqual(self.refresh(changed.data['refresh']).status_code, status.HTTP_200_OK)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {changed.data["access"]}')
        self.assertEqual(self.client.get(reverse('user_me')).status_code, status.HTTP_200_OK)

    def test_tutor_reset_and_deactivation_end_the_students_sessions(self):
        session = self.login('ses_student')
        self.client.force_authenticate(user=self.tutor)
        reset = self.client.post(reverse('student-reset-password', kwargs={'pk': self.student.id}))
        self.assertEqual(reset.status_code, status.HTTP_200_OK)
        self.client.force_authenticate(user=None)
        self.assertEqual(self.refresh(session['refresh']).status_code, status.HTTP_401_UNAUTHORIZED)

        session = self.login('ses_student', reset.data['temporary_password'])
        self.client.force_authenticate(user=self.tutor)
        self.client.post(reverse('student-toggle-active', kwargs={'pk': self.student.id}))
        self.client.force_authenticate(user=None)
        self.assertEqual(self.refresh(session['refresh']).status_code, status.HTTP_401_UNAUTHORIZED)
        # A deactivated account cannot use an access token it still holds either.
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {session["access"]}')
        self.assertEqual(self.client.get(reverse('user_me')).status_code, status.HTTP_401_UNAUTHORIZED)


class ContractTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(username='ct_tutor', password=PASSWORD, role=User.Role.TUTOR)
        self.tuition = Tuition.objects.create(tutor=self.tutor, title='G', total_fee=1000, cycle_length=4)
        now = timezone.now()
        self.exam = Exam.objects.create(
            tutor=self.tutor, tuition=self.tuition, title='E', total_marks=10,
            start_time=now, end_time=now + timedelta(hours=1),
        )

    def test_meta_is_public_and_gives_the_server_clock(self):
        resp = self.client.get(reverse('api-meta'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['api_version'], 'v1')
        self.assertLess(abs((timezone.now() - resp.data['server_time']).total_seconds()), 5)
        self.assertEqual(resp.data['media_base_url'], 'http://testserver')
        self.assertEqual(resp.data['uploads']['max_size_mb'], 10)
        self.assertIn('IMMEDIATE', resp.data['result_publish_modes'])

    def test_every_datetime_is_iso_utc(self):
        self.client.force_authenticate(user=self.tutor)
        found = []

        def collect(value, key=''):
            if isinstance(value, dict):
                for k, v in value.items():
                    collect(v, k)
            elif isinstance(value, list):
                for item in value:
                    collect(item, key)
            elif isinstance(value, str) and (key.endswith('_at') or key.endswith('_time')):
                found.append((key, value))

        for url in (
            reverse('exam-list'), reverse('exam-detail', kwargs={'pk': self.exam.id}), reverse('tuition-list'),
            reverse('user_me'), reverse('api-meta'), reverse('notifications'),
            reverse('exam-submissions', kwargs={'pk': self.exam.id}),
        ):
            collect(self.client.get(url).json())
        self.assertGreater(len(found), 8)
        for key, value in found:
            self.assertRegex(value, ISO_UTC, key)

    def test_upload_returns_an_absolute_address(self):
        self.client.force_authenticate(user=self.tutor)
        png = b'\x89PNG\r\n\x1a\n' + b'\x00' * 32
        with mock.patch('apps.exams.views.default_storage.save', return_value='uploads/2026/10/x_test.png'):
            resp = self.client.post(reverse('media-upload'), {'file': SimpleUploadedFile('test.png', png, content_type='image/png')}, format='multipart')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        self.assertEqual(resp.data['url'], '/media/uploads/2026/10/x_test.png')
        self.assertEqual(resp.data['absolute_url'], 'http://testserver/media/uploads/2026/10/x_test.png')

    def test_a_json_list_body_is_a_400_not_a_crash(self):
        self.client.force_authenticate(user=self.tutor)
        resp = self.client.post(reverse('exam-publish-results', kwargs={'pk': self.exam.id}), [], format='json')
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp.json()['code'], 'parse_error')
        self.assertEqual(resp.json()['message'], 'The request body must be a JSON object.')

    def test_editing_a_student_returns_the_saved_profile(self):
        """The response must show what was just saved, not the values from before the edit."""
        student = User.objects.create_user(username='ct_student', password=PASSWORD, role=User.Role.STUDENT, tutor=self.tutor)
        StudentProfile.objects.create(user=student, institution='Old School')
        self.client.force_authenticate(user=self.tutor)
        resp = self.client.patch(reverse('student-detail', kwargs={'pk': student.id}), {
            'first_name': 'Renamed', 'profile': {'institution': 'New School', 'notes': 'private'},
        }, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        self.assertEqual(resp.data['first_name'], 'Renamed')
        self.assertEqual(resp.data['profile']['institution'], 'New School')
        self.assertEqual(resp.data['profile']['notes'], 'private')
