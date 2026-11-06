"""The live connection (/ws/), push notifications to closed apps, and the nudge after a save."""
from datetime import timedelta
from unittest import mock

from asgiref.sync import sync_to_async
from channels.testing import WebsocketCommunicator
from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import AccessToken

from apps.messaging import push
from apps.messaging.models import Conversation, PushDevice
from apps.students.models import Tuition, TuitionEnrollment
from config.asgi import application

User = get_user_model()
TOKEN_A = 'fcm-token-' + 'a' * 40
TOKEN_B = 'fcm-token-' + 'b' * 40


def make_user(username, role, **extra):
    return User.objects.create_user(username=username, password='Password123!', role=role, **extra)


class Base(TestCase):
    def setUp(self):
        self.tutor = make_user('live_tutor', User.Role.TUTOR, first_name='Ashraf', last_name='Islam')
        self.student = make_user('live_student', User.Role.STUDENT, first_name='Rafi', last_name='Hasan')
        self.stranger = make_user('live_stranger', User.Role.STUDENT, first_name='Sami')
        self.tuition = Tuition.objects.create(tutor=self.tutor, title='SSC Physics Batch A', total_fee=1200, cycle_length=12)
        TuitionEnrollment.objects.create(tuition=self.tuition, student=self.student)
        self.conv = Conversation.objects.create(tutor=self.tutor, student=self.student)
        self.api = APIClient()

    def post_as(self, user, url, data):
        self.api.force_authenticate(user)
        with self.captureOnCommitCallbacks(execute=True):
            return self.api.post(url, data, format='json')

    async def socket(self, user):
        comm = WebsocketCommunicator(application, '/ws/')
        connected, _ = await comm.connect()
        self.assertTrue(connected)
        await comm.send_json_to({'type': 'auth', 'token': str(AccessToken.for_user(user))})
        self.assertEqual((await comm.receive_json_from(timeout=3))['type'], 'ready')
        return comm


class LiveSocketTests(Base):
    async def test_bad_token_is_refused(self):
        comm = WebsocketCommunicator(application, '/ws/')
        await comm.connect()
        await comm.send_json_to({'type': 'auth', 'token': 'not-a-token'})
        self.assertEqual((await comm.receive_json_from(timeout=3))['type'], 'auth_failed')
        self.assertEqual((await comm.receive_output(timeout=3))['code'], 4401)

    async def test_anything_before_auth_is_refused(self):
        comm = WebsocketCommunicator(application, '/ws/')
        await comm.connect()
        await comm.send_json_to({'type': 'typing', 'conversation_id': str(self.conv.id)})
        self.assertEqual((await comm.receive_json_from(timeout=3))['type'], 'auth_failed')

    async def test_ping(self):
        comm = await self.socket(self.student)
        await comm.send_json_to({'type': 'ping'})
        self.assertEqual(await comm.receive_json_from(timeout=3), {'type': 'pong'})
        await comm.disconnect()

    async def test_new_message_reaches_both_sides_live(self):
        tutor_ws = await self.socket(self.tutor)
        student_ws = await self.socket(self.student)
        url = reverse('chat-messages', kwargs={'pk': self.conv.id})
        response = await sync_to_async(self.post_as)(self.tutor, url, {'body': 'Solve 3.2 tonight', 'client_ref': 'r1'})
        self.assertEqual(response.status_code, 201)

        to_student = await student_ws.receive_json_from(timeout=3)
        self.assertEqual(to_student['type'], 'message')
        self.assertEqual(to_student['conversation_id'], str(self.conv.id))
        self.assertEqual(to_student['message']['body'], 'Solve 3.2 tonight')
        self.assertFalse(to_student['message']['mine'])
        to_tutor = await tutor_ws.receive_json_from(timeout=3)
        self.assertTrue(to_tutor['message']['mine'])
        await tutor_ws.disconnect()
        await student_ws.disconnect()

    async def test_read_and_typing_go_to_the_other_person_only(self):
        tutor_ws = await self.socket(self.tutor)
        student_ws = await self.socket(self.student)
        stranger_ws = await self.socket(self.stranger)

        await student_ws.send_json_to({'type': 'typing', 'conversation_id': str(self.conv.id)})
        self.assertEqual(await tutor_ws.receive_json_from(timeout=3), {'type': 'typing', 'conversation_id': str(self.conv.id)})

        # Typing into someone else's conversation reaches nobody.
        await stranger_ws.send_json_to({'type': 'typing', 'conversation_id': str(self.conv.id)})
        self.assertTrue(await tutor_ws.receive_nothing(timeout=0.3))
        self.assertTrue(await student_ws.receive_nothing(timeout=0.3))

        url = reverse('chat-read', kwargs={'pk': self.conv.id})
        await sync_to_async(self.post_as)(self.student, url, {})
        read = await tutor_ws.receive_json_from(timeout=3)
        self.assertEqual(read['type'], 'read')
        self.assertEqual(read['conversation_id'], str(self.conv.id))
        for comm in (tutor_ws, student_ws, stranger_ws):
            await comm.disconnect()

    async def test_tutor_save_nudges_their_students(self):
        student_ws = await self.socket(self.student)
        stranger_ws = await self.socket(self.stranger)
        due = (timezone.now() + timedelta(days=2)).isoformat()
        response = await sync_to_async(self.post_as)(
            self.tutor, '/api/v1/homework/', {'title': 'Exercise 3.2', 'tuition': str(self.tuition.id), 'due_date': due},
        )
        self.assertIn(response.status_code, (200, 201), getattr(response, 'data', None))
        self.assertEqual(await student_ws.receive_json_from(timeout=3), {'type': 'nudge'})
        self.assertTrue(await stranger_ws.receive_nothing(timeout=0.3))
        await student_ws.disconnect()
        await stranger_ws.disconnect()


@override_settings(FCM_SERVICE_ACCOUNT='{"project_id": "tt-test"}')
class PushTests(Base):
    def setUp(self):
        super().setUp()
        patcher = mock.patch.object(push, '_access_token', return_value=('google-token', 'tt-test'))
        patcher.start()
        self.addCleanup(patcher.stop)

    def register(self, user, token):
        self.api.force_authenticate(user)
        return self.api.post(reverse('push-devices'), {'token': token, 'platform': 'android'}, format='json')

    def test_register_moves_the_token_to_whoever_signs_in(self):
        self.assertEqual(self.register(self.student, TOKEN_A).status_code, 201)
        self.assertEqual(self.register(self.stranger, TOKEN_A).status_code, 201)
        self.assertEqual(PushDevice.objects.get(token=TOKEN_A).user, self.stranger)
        self.assertEqual(self.register(self.student, 'short').status_code, 400)

    def test_signed_out_phone_can_remove_its_token(self):
        self.register(self.student, TOKEN_A)
        self.api.force_authenticate(None)
        response = self.api.delete(reverse('push-devices'), {'token': TOKEN_A}, format='json')
        self.assertEqual(response.status_code, 204)
        self.assertFalse(PushDevice.objects.exists())

    def test_message_pushes_a_visible_notification_to_the_recipient(self):
        self.register(self.student, TOKEN_A)
        self.register(self.tutor, TOKEN_B)
        ok = mock.Mock(status_code=200)
        with mock.patch.object(push, '_post', return_value=ok) as post:
            response = self.post_as(self.tutor, reverse('chat-messages', kwargs={'pk': self.conv.id}),
                                    {'body': 'Class at 5 today', 'client_ref': 'p1'})
        self.assertEqual(response.status_code, 201)
        chat_pushes = [c for c in post.call_args_list if c.args[2]['data']['kind'] == 'message']
        self.assertEqual(len(chat_pushes), 1)
        message = chat_pushes[0].args[2]
        self.assertEqual(message['token'], TOKEN_A)
        # Students see their tutor as "Ashraf Sir".
        self.assertEqual(message['notification'], {'title': 'Ashraf Sir', 'body': 'Class at 5 today'})
        self.assertEqual(message['data']['link'], f'/chats/{self.conv.id}')
        self.assertEqual(message['android']['notification']['tag'], f'chat-{self.conv.id}')

    def test_a_save_sends_a_silent_sync_push(self):
        self.register(self.student, TOKEN_A)
        with mock.patch.object(push, '_post', return_value=mock.Mock(status_code=200)) as post:
            due = (timezone.now() + timedelta(days=2)).isoformat()
            self.post_as(self.tutor, '/api/v1/homework/', {'title': 'Ex 1', 'tuition': str(self.tuition.id), 'due_date': due})
        syncs = [c.args[2] for c in post.call_args_list if c.args[2]['data']['kind'] == 'sync']
        self.assertEqual(len(syncs), 1)
        self.assertNotIn('notification', syncs[0])
        self.assertEqual(syncs[0]['token'], TOKEN_A)

    def test_uninstalled_phone_is_forgotten(self):
        self.register(self.student, TOKEN_A)
        with mock.patch.object(push, '_post', return_value=mock.Mock(status_code=404)):
            push.send([self.student.id], data={'kind': 'sync'})
        self.assertFalse(PushDevice.objects.exists())

    @override_settings(FCM_SERVICE_ACCOUNT='')
    def test_nothing_is_sent_without_a_key(self):
        self.register(self.student, TOKEN_A)
        with mock.patch.object(push, '_post') as post:
            self.assertEqual(push.send([self.student.id], data={'kind': 'sync'}), 0)
        post.assert_not_called()
