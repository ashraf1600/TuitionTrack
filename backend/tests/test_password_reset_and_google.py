"""
Forgot password (6-digit code and link) and Sign in with Google.
"""
import json
import re
from datetime import timedelta
from unittest import mock

from django.contrib.auth import get_user_model
from django.core import mail
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.authentication.models import PasswordResetCode
from apps.students.models import StudentProfile

User = get_user_model()
NEW_PASSWORD = 'BrandNew456!y'


def code_from_last_mail():
    return re.search(r'reset code is: (\d{6})', mail.outbox[-1].body).group(1)


class PasswordResetCodeTests(APITestCase):
    def setUp(self):
        self.tutor = User.objects.create_user(
            username='rk_tutor', password='OldPass123!x', role=User.Role.TUTOR, email='Tutor@Example.com',
        )

    def ask(self, identifier='tutor@example.com'):
        return self.client.post(reverse('password_reset'), {'identifier': identifier}, format='json')

    def verify(self, code, identifier='tutor@example.com'):
        return self.client.post(reverse('password_reset_verify'), {'identifier': identifier, 'code': code}, format='json')

    def test_full_code_flow_signs_out_everywhere_and_new_password_works(self):
        login = self.client.post(reverse('token_obtain_pair'), {'username': 'rk_tutor', 'password': 'OldPass123!x'}, format='json')
        old_refresh = login.data['refresh']

        self.assertEqual(self.ask().status_code, status.HTTP_200_OK)
        self.assertEqual(len(mail.outbox), 1)
        message = mail.outbox[0]
        self.assertEqual(message.to, [self.tutor.email])
        self.assertTrue(any(mimetype == 'text/html' for _, mimetype in message.alternatives))
        self.assertIn('/reset-password?uid=', message.body)
        code = code_from_last_mail()
        self.assertIn(code, message.subject)

        verified = self.verify(f' {code[:3]} {code[3:]} ')  # spaces and padding are forgiven
        self.assertEqual(verified.status_code, status.HTTP_200_OK, verified.data)
        self.assertEqual(verified.data['username'], 'rk_tutor')

        confirm = self.client.post(reverse('password_reset_confirm'), {
            'uid': verified.data['uid'], 'token': verified.data['token'], 'new_password': NEW_PASSWORD,
        }, format='json')
        self.assertEqual(confirm.status_code, status.HTTP_200_OK, confirm.data)
        self.tutor.refresh_from_db()
        self.assertTrue(self.tutor.check_password(NEW_PASSWORD))
        # Old sessions end; the code cannot be used again.
        refresh = self.client.post(reverse('token_refresh'), {'refresh': old_refresh}, format='json')
        self.assertEqual(refresh.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(self.verify(code).status_code, status.HTTP_400_BAD_REQUEST)

    def test_code_is_stored_hashed(self):
        self.ask()
        code = code_from_last_mail()
        self.assertFalse(PasswordResetCode.objects.filter(code_hash__contains=code).exists())

    def test_username_works_as_identifier_too(self):
        self.ask('RK_TUTOR')
        self.assertEqual(self.verify(code_from_last_mail(), identifier='rk_tutor').status_code, status.HTTP_200_OK)

    def test_wrong_code_and_lockout_after_five_tries(self):
        self.ask()
        code = code_from_last_mail()
        wrong = '000000' if code != '000000' else '111111'
        for _ in range(5):
            bad = self.verify(wrong)
            self.assertEqual(bad.status_code, status.HTTP_400_BAD_REQUEST)
            self.assertEqual(bad.data['code'], 'invalid_reset_code')
        locked = self.verify(code)
        self.assertEqual(locked.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Too many', locked.data['message'])

    def test_expired_code_is_refused(self):
        self.ask()
        code = code_from_last_mail()
        PasswordResetCode.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
        self.assertEqual(self.verify(code).status_code, status.HTTP_400_BAD_REQUEST)

    def test_new_code_replaces_old_and_resend_is_rate_limited(self):
        self.ask()
        first = code_from_last_mail()
        self.ask()  # within the cooldown: no second e-mail
        self.assertEqual(len(mail.outbox), 1)
        PasswordResetCode.objects.update(created_at=timezone.now() - timedelta(minutes=2))
        self.ask()
        self.assertEqual(len(mail.outbox), 2)
        second = code_from_last_mail()
        if first != second:
            self.assertEqual(self.verify(first).status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.verify(second).status_code, status.HTTP_200_OK)

    def test_hourly_cap(self):
        for _ in range(8):
            PasswordResetCode.objects.update(created_at=timezone.now() - timedelta(minutes=2))
            self.ask()
        self.assertEqual(len(mail.outbox), 5)

    def test_unknown_account_same_answer_and_code_for_someone_else_fails(self):
        unknown = self.ask('nobody@example.com')
        known = self.ask()
        self.assertEqual(unknown.data, known.data)
        other = User.objects.create_user(username='rk_other', password='x', role=User.Role.TUTOR, email='other@example.com')
        self.assertTrue(other.pk)
        self.assertEqual(self.verify(code_from_last_mail(), identifier='other@example.com').status_code, status.HTTP_400_BAD_REQUEST)

    def test_deactivated_account_gets_no_mail(self):
        self.tutor.is_active = False
        self.tutor.save()
        self.ask()
        self.assertEqual(len(mail.outbox), 0)

    def test_garbage_input(self):
        for code in ('', 'abcdef', '12345', '1234567', None):
            resp = self.verify(code)
            self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)


GOOGLE_CLAIMS = {
    'iss': 'https://accounts.google.com', 'sub': '1098765', 'aud': 'web-client.apps.googleusercontent.com',
    'email': 'Rina@Gmail.com', 'email_verified': True, 'name': 'Rina Das', 'given_name': 'Rina', 'family_name': 'Das',
}


@override_settings(GOOGLE_CLIENT_ID='web-client.apps.googleusercontent.com')
class GoogleLoginTests(APITestCase):
    def post(self, claims=None, **body):
        payload = {'id_token': 'a.b.c', **body}
        with mock.patch('google.oauth2.id_token.verify_oauth2_token', return_value=dict(claims or GOOGLE_CLAIMS)) as verify:
            resp = self.client.post(reverse('google_login'), payload, format='json')
        return resp, verify

    def test_existing_account_matched_by_email_then_by_google_id(self):
        user = User.objects.create_user(username='rina', password='OldPass123!x', role=User.Role.TUTOR, email='rina@gmail.com')
        resp, verify = self.post()
        self.assertEqual(resp.status_code, status.HTTP_200_OK, resp.data)
        self.assertEqual(verify.call_args.kwargs['audience'], ['web-client.apps.googleusercontent.com'])
        self.assertEqual(resp.data['user']['username'], 'rina')
        self.assertFalse(resp.data['created'])
        self.assertTrue(resp.data['access'] and resp.data['refresh'])
        user.refresh_from_db()
        self.assertEqual(user.google_sub, '1098765')
        # Later the e-mail changes on our side: the linked Google account still finds them.
        user.email = 'new@example.com'
        user.save()
        resp, _ = self.post()
        self.assertEqual(resp.data['user']['id'], str(user.id))
        # The issued token works.
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {resp.data['access']}")
        me = self.client.get(reverse('user_me'))
        self.assertTrue(me.data['google_linked'])
        self.assertTrue(me.data['has_password'])

    def test_website_credential_field_is_accepted(self):
        User.objects.create_user(username='rina', password='x', role=User.Role.TUTOR, email='rina@gmail.com')
        with mock.patch('google.oauth2.id_token.verify_oauth2_token', return_value=dict(GOOGLE_CLAIMS)):
            resp = self.client.post(reverse('google_login'), {'credential': 'a.b.c'}, format='json')
        self.assertEqual(resp.status_code, status.HTTP_200_OK)

    def test_no_account_asks_for_role_then_creates_student(self):
        resp, _ = self.post()
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(resp.data['code'], 'google_account_not_found')
        self.assertEqual(resp.data['email'], 'Rina@Gmail.com')
        self.assertTrue(resp.data['signup_allowed'])
        self.assertFalse(User.objects.filter(email__iexact='rina@gmail.com').exists())

        resp, _ = self.post(role='STUDENT')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED, resp.data)
        self.assertTrue(resp.data['created'])
        user = User.objects.get(email__iexact='rina@gmail.com')
        self.assertEqual((user.role, user.username, user.first_name), ('STUDENT', 'Rina', 'Rina'))
        self.assertFalse(user.has_usable_password())
        self.assertTrue(StudentProfile.objects.filter(user=user).exists())
        self.assertFalse(resp.data['user']['has_password'])

    def test_google_user_sets_first_password_without_current_one(self):
        resp, _ = self.post(role='TUTOR')
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {resp.data['access']}")
        changed = self.client.post(reverse('change_password'), {'new_password': NEW_PASSWORD}, format='json')
        self.assertEqual(changed.status_code, status.HTTP_200_OK, changed.data)
        user = User.objects.get(email__iexact='rina@gmail.com')
        self.assertTrue(user.check_password(NEW_PASSWORD))
        self.assertTrue(user.tutor_code)
        # Now a current password is required.
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {changed.data['access']}")
        again = self.client.post(reverse('change_password'), {'new_password': 'Another789!z'}, format='json')
        self.assertEqual(again.status_code, status.HTTP_400_BAD_REQUEST)

    def test_username_collision_gets_a_number(self):
        User.objects.create_user(username='rina', password='x', role=User.Role.TUTOR, email='someone@else.com')
        resp, _ = self.post(role='TUTOR')
        self.assertEqual(resp.data['user']['username'], 'Rina2')

    def test_unverified_email_and_deactivated_account_are_refused(self):
        resp, _ = self.post({**GOOGLE_CLAIMS, 'email_verified': False})
        self.assertEqual((resp.status_code, resp.data['code']), (400, 'google_email_unverified'))
        User.objects.create_user(username='rina', password='x', role=User.Role.STUDENT, email='rina@gmail.com', is_active=False)
        resp, _ = self.post()
        self.assertEqual((resp.status_code, resp.data['code']), (403, 'account_inactive'))

    def test_two_accounts_with_same_email_are_not_guessed(self):
        User.objects.create_user(username='a1', password='x', role=User.Role.TUTOR, email='rina@gmail.com')
        User.objects.create_user(username='a2', password='x', role=User.Role.STUDENT, email='RINA@gmail.com')
        resp, _ = self.post()
        self.assertEqual((resp.status_code, resp.data['code']), (409, 'google_email_ambiguous'))

    def test_bad_token_and_wrong_issuer(self):
        with mock.patch('google.oauth2.id_token.verify_oauth2_token', side_effect=ValueError('bad signature')):
            resp = self.client.post(reverse('google_login'), {'id_token': 'a.b.c'}, format='json')
        self.assertEqual((resp.status_code, resp.data['code']), (400, 'google_auth_failed'))
        resp, _ = self.post({**GOOGLE_CLAIMS, 'iss': 'evil.example.com'})
        self.assertEqual(resp.status_code, 400)
        resp = self.client.post(reverse('google_login'), {'id_token': 'not-a-jwt'}, format='json')
        self.assertEqual(resp.status_code, 400)
        resp = self.client.post(reverse('google_login'), {}, format='json')
        self.assertEqual(resp.status_code, 400)

    def test_invalid_role_and_signup_disabled(self):
        resp, _ = self.post(role='ADMIN')
        self.assertEqual(resp.status_code, 400)
        with override_settings(GOOGLE_SIGNUP_ENABLED=False):
            resp, _ = self.post(role='TUTOR')
        self.assertEqual((resp.status_code, resp.data['code']), (403, 'google_signup_disabled'))

    @override_settings(GOOGLE_CLIENT_ID='')
    def test_not_configured(self):
        resp = self.client.post(reverse('google_login'), {'id_token': 'a.b.c'}, format='json')
        self.assertEqual((resp.status_code, resp.data['code']), (503, 'google_not_configured'))
        self.assertEqual(self.client.get('/api/v1/meta/').data['auth']['google_client_id'], '')

    def test_meta_advertises_client_id(self):
        auth = self.client.get('/api/v1/meta/').data['auth']
        self.assertEqual(auth['google_client_id'], 'web-client.apps.googleusercontent.com')
        self.assertTrue(auth['password_reset_email'])  # the test suite's in-memory mailbox


class HttpEmailBackendTests(APITestCase):
    def send_with(self, backend, **settings_kwargs):
        from django.core.mail import EmailMultiAlternatives, get_connection
        captured = {}

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self):
                return b'{}'

        def fake_urlopen(request, timeout):
            captured['url'] = request.full_url
            captured['headers'] = dict(request.header_items())
            captured['body'] = json.loads(request.data)
            return FakeResponse()

        with override_settings(**settings_kwargs), mock.patch('urllib.request.urlopen', fake_urlopen):
            message = EmailMultiAlternatives('Subject', 'Text body', 'TuitionTrack <me@gmail.com>', ['Rina <r@example.com>'],
                                             connection=get_connection(backend))
            message.attach_alternative('<b>Html</b>', 'text/html')
            self.assertEqual(message.send(), 1)
        return captured

    def test_brevo_payload(self):
        sent = self.send_with('config.email_backends.BrevoEmailBackend', BREVO_API_KEY='key-1')
        self.assertEqual(sent['url'], 'https://api.brevo.com/v3/smtp/email')
        self.assertEqual(sent['headers']['Api-key'], 'key-1')
        self.assertEqual(sent['body']['sender'], {'email': 'me@gmail.com', 'name': 'TuitionTrack'})
        self.assertEqual(sent['body']['to'], [{'email': 'r@example.com'}])
        self.assertEqual(sent['body']['htmlContent'], '<b>Html</b>')

    def test_resend_payload(self):
        sent = self.send_with('config.email_backends.ResendEmailBackend', RESEND_API_KEY='key-2')
        self.assertEqual(sent['url'], 'https://api.resend.com/emails')
        self.assertEqual(sent['headers']['Authorization'], 'Bearer key-2')
        self.assertEqual(sent['body']['html'], '<b>Html</b>')

    def test_missing_key_raises_and_provider_error_raises(self):
        import urllib.error
        from django.core.mail import EmailMessage, get_connection
        from config.email_backends import EmailDeliveryError
        with override_settings(BREVO_API_KEY=''):
            conn = get_connection('config.email_backends.BrevoEmailBackend')
            with self.assertRaises(EmailDeliveryError):
                EmailMessage('s', 'b', 'a@b.com', ['c@d.com'], connection=conn).send()
        error = urllib.error.HTTPError('u', 401, 'Unauthorized', {}, None)
        error.read = lambda: b'{"message":"Key not found"}'
        with override_settings(BREVO_API_KEY='bad'), mock.patch('urllib.request.urlopen', side_effect=error):
            conn = get_connection('config.email_backends.BrevoEmailBackend')
            with self.assertRaisesMessage(EmailDeliveryError, 'Key not found'):
                EmailMessage('s', 'b', 'a@b.com', ['c@d.com'], connection=conn).send()

    def test_console_backend_counts_as_not_configured(self):
        from config.email_backends import email_is_configured
        with override_settings(EMAIL_BACKEND='django.core.mail.backends.console.EmailBackend'):
            self.assertFalse(email_is_configured())
        with override_settings(EMAIL_BACKEND='config.email_backends.BrevoEmailBackend', BREVO_API_KEY='k'):
            self.assertTrue(email_is_configured())
