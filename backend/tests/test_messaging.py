"""Chat between a tutor and their students: who may talk, sending, polling, unread counts."""
import io
import shutil
import tempfile

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.urls import reverse
from PIL import Image
from rest_framework import status
from rest_framework.test import APITestCase

from apps.messaging.models import Conversation, Message
from apps.students.models import ConnectionRequest, Tuition, TuitionEnrollment

User = get_user_model()
MEDIA = tempfile.mkdtemp(prefix='tt-chat-media-')


def make_user(username, role, **extra):
    return User.objects.create_user(username=username, password='Password123!', role=role, **extra)


def png(name='photo.png'):
    buffer = io.BytesIO()
    Image.new('RGB', (8, 8), (5, 150, 105)).save(buffer, format='PNG')
    return SimpleUploadedFile(name, buffer.getvalue(), content_type='image/png')


@override_settings(MEDIA_ROOT=MEDIA, STORAGES={
    'default': {'BACKEND': 'django.core.files.storage.FileSystemStorage'},
    'staticfiles': {'BACKEND': 'django.contrib.staticfiles.storage.StaticFilesStorage'},
})
class MessagingTests(APITestCase):
    @classmethod
    def tearDownClass(cls):
        super().tearDownClass()
        shutil.rmtree(MEDIA, ignore_errors=True)

    def setUp(self):
        self.tutor = make_user('tutor_a', User.Role.TUTOR, first_name='Ashraf', last_name='Islam')
        self.other_tutor = make_user('tutor_b', User.Role.TUTOR, first_name='Nusrat')
        # Linked three ways: in a tuition, by an accepted request, and as the account's creator.
        self.enrolled = make_user('stu_a', User.Role.STUDENT, first_name='Rafi', last_name='Hasan')
        self.requested = make_user('stu_b', User.Role.STUDENT, first_name='Nila')
        self.created = make_user('stu_c', User.Role.STUDENT, first_name='Omar', tutor=self.tutor)
        self.stranger = make_user('stu_d', User.Role.STUDENT, first_name='Sami')
        tuition = Tuition.objects.create(tutor=self.tutor, title='SSC Physics Batch A', total_fee=1200, cycle_length=12)
        self.enrollment = TuitionEnrollment.objects.create(tuition=tuition, student=self.enrolled)
        ConnectionRequest.objects.create(
            tutor=self.tutor, student=self.requested, status=ConnectionRequest.Status.ACCEPTED,
        )

    def start(self, me, other):
        self.client.force_authenticate(me)
        return self.client.post(reverse('chat-start'), {'user_id': str(other.id)}, format='json')

    def send(self, me, conv_id, body='Hello', **extra):
        self.client.force_authenticate(me)
        return self.client.post(
            reverse('chat-messages', args=[conv_id]), {'body': body, **extra}, format='json',
        )

    # ── Who may message whom ────────────────────────────────────────────────

    def test_contacts_are_my_own_tutors_and_students(self):
        self.client.force_authenticate(self.tutor)
        names = {c['name'] for c in self.client.get(reverse('chat-contacts')).data['results']}
        self.assertEqual(names, {'Rafi Hasan', 'Nila', 'Omar'})

        self.client.force_authenticate(self.enrolled)
        contacts = self.client.get(reverse('chat-contacts')).data['results']
        self.assertEqual([c['name'] for c in contacts], ['Ashraf Sir'], 'students see their tutor as "X Sir"')

    def test_any_link_lets_them_start_a_chat_from_either_side(self):
        for student in (self.enrolled, self.requested, self.created):
            self.assertEqual(self.start(self.tutor, student).status_code, status.HTTP_200_OK)
        resp = self.start(self.enrolled, self.tutor)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['other']['name'], 'Ashraf Sir')
        # Starting twice gives the same conversation.
        self.assertEqual(Conversation.objects.filter(tutor=self.tutor, student=self.enrolled).count(), 1)

    def test_strangers_and_same_role_pairs_cannot_chat(self):
        self.assertEqual(self.start(self.tutor, self.stranger).status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.start(self.enrolled, self.other_tutor).status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.start(self.tutor, self.other_tutor).status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(self.start(self.enrolled, self.requested).status_code, status.HTTP_403_FORBIDDEN)
        self.client.force_authenticate(self.tutor)
        bad = self.client.post(reverse('chat-start'), {'user_id': 'not-a-uuid'}, format='json')
        self.assertEqual(bad.status_code, status.HTTP_404_NOT_FOUND)

    def test_outsiders_cannot_read_or_post_in_a_conversation(self):
        conv_id = self.start(self.tutor, self.enrolled).data['id']
        self.send(self.tutor, conv_id, 'Private')
        self.client.force_authenticate(self.other_tutor)
        self.assertEqual(self.client.get(reverse('chat-messages', args=[conv_id])).status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(self.send(self.other_tutor, conv_id).status_code, status.HTTP_404_NOT_FOUND)
        self.client.force_authenticate(None)
        self.assertEqual(self.client.get(reverse('chat-list')).status_code, status.HTTP_401_UNAUTHORIZED)

    def test_after_leaving_the_old_chat_stays_readable_but_closed(self):
        conv_id = self.start(self.tutor, self.enrolled).data['id']
        self.send(self.tutor, conv_id, 'See you Sunday')
        self.enrollment.is_active = False
        self.enrollment.save()
        self.assertEqual(self.send(self.tutor, conv_id, 'Hello?').status_code, status.HTTP_403_FORBIDDEN)
        self.client.force_authenticate(self.enrolled)
        page = self.client.get(reverse('chat-messages', args=[conv_id])).data
        self.assertEqual([m['body'] for m in page['results']], ['See you Sunday'])
        self.assertFalse(page['can_send'])

    # ── Sending and reading ─────────────────────────────────────────────────

    def test_send_poll_and_page_back(self):
        conv_id = self.start(self.enrolled, self.tutor).data['id']
        first = self.send(self.enrolled, conv_id, 'Sir, is class on tomorrow?')
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)
        self.assertTrue(first.data['mine'])
        for i in range(5):
            self.send(self.tutor, conv_id, f'Reply {i}')

        self.client.force_authenticate(self.enrolled)
        url = reverse('chat-messages', args=[conv_id])
        newest = self.client.get(url, {'limit': 3}).data
        self.assertEqual([m['body'] for m in newest['results']], ['Reply 2', 'Reply 3', 'Reply 4'])
        self.assertTrue(newest['has_more'])
        older = self.client.get(url, {'before': newest['results'][0]['id'], 'limit': 50}).data
        self.assertEqual(older['results'][0]['body'], 'Sir, is class on tomorrow?')
        self.assertFalse(older['has_more'])
        self.assertEqual(self.client.get(url, {'after': newest['results'][-1]['id']}).data['results'], [])
        self.assertEqual(self.client.get(url, {'after': 'x'}).status_code, status.HTTP_400_BAD_REQUEST)

    def test_empty_and_too_long_messages_are_refused(self):
        conv_id = self.start(self.tutor, self.enrolled).data['id']
        self.assertEqual(self.send(self.tutor, conv_id, '   ').status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.send(self.tutor, conv_id, 'x' * 4001).status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_retried_send_is_kept_once(self):
        conv_id = self.start(self.tutor, self.enrolled).data['id']
        a = self.send(self.tutor, conv_id, 'Bring your copy', client_ref='phone-1')
        b = self.send(self.tutor, conv_id, 'Bring your copy', client_ref='phone-1')
        self.assertEqual(a.status_code, status.HTTP_201_CREATED)
        self.assertEqual(b.status_code, status.HTTP_200_OK)
        self.assertEqual(a.data['id'], b.data['id'])
        self.assertEqual(Message.objects.count(), 1)

    def test_photos_are_checked_and_sent(self):
        conv_id = self.start(self.enrolled, self.tutor).data['id']
        self.client.force_authenticate(self.enrolled)
        url = reverse('chat-messages', args=[conv_id])
        ok = self.client.post(url, {'image': png(), 'body': 'Q5 please'}, format='multipart')
        self.assertEqual(ok.status_code, status.HTTP_201_CREATED, ok.data)
        self.assertTrue(ok.data['image'])
        fake = SimpleUploadedFile('x.png', b'<html>no</html>', content_type='image/png')
        self.assertEqual(self.client.post(url, {'image': fake}, format='multipart').status_code, status.HTTP_400_BAD_REQUEST)

    # ── Unread, seen and the list ───────────────────────────────────────────

    def test_unread_counts_seen_and_list_order(self):
        conv_a = self.start(self.tutor, self.enrolled).data['id']
        conv_b = self.start(self.tutor, self.requested).data['id']
        self.send(self.enrolled, conv_a, 'One')
        self.send(self.enrolled, conv_a, 'Two')
        self.send(self.requested, conv_b, 'Hi Sir')

        self.client.force_authenticate(self.tutor)
        self.assertEqual(self.client.get(reverse('chat-unread')).data, {'unread': 3, 'conversations': 2})
        chats = self.client.get(reverse('chat-list')).data
        self.assertEqual(chats['unread_total'], 3)
        self.assertEqual([c['other']['name'] for c in chats['results']], ['Nila', 'Rafi Hasan'], 'newest first')
        self.assertEqual(chats['results'][1]['last_message']['body'], 'Two')

        # The tutor opens Rafi's chat: those two are read, and Rafi sees "Seen".
        self.client.post(reverse('chat-read', args=[conv_a]))
        self.assertEqual(self.client.get(reverse('chat-unread')).data['unread'], 1)
        self.client.force_authenticate(self.enrolled)
        page = self.client.get(reverse('chat-messages', args=[conv_a])).data
        self.assertIsNotNone(page['other_read_at'])

        # Replying also counts as reading.
        self.send(self.tutor, conv_b, 'Hello Nila')
        self.client.force_authenticate(self.tutor)
        self.assertEqual(self.client.get(reverse('chat-unread')).data['unread'], 0)

    def test_new_messages_reach_the_notification_feed(self):
        conv_id = self.start(self.enrolled, self.tutor).data['id']
        self.send(self.tutor, conv_id, 'Class moved to 6 PM')
        self.client.force_authenticate(self.enrolled)
        feed = self.client.get(reverse('notifications')).data['notifications']
        messages = [n for n in feed if n['kind'] == 'message']
        self.assertEqual(len(messages), 1)
        self.assertEqual(messages[0]['title'], 'Ashraf Sir')
        self.assertEqual(messages[0]['body'], 'Class moved to 6 PM')
        self.assertEqual(messages[0]['link'], f'/chats/{conv_id}')
        self.client.post(reverse('chat-read', args=[conv_id]))
        feed = self.client.get(reverse('notifications')).data['notifications']
        self.assertFalse([n for n in feed if n['kind'] == 'message'])

    def test_empty_conversations_stay_out_of_the_list(self):
        self.start(self.tutor, self.enrolled)
        self.client.force_authenticate(self.tutor)
        self.assertEqual(self.client.get(reverse('chat-list')).data['results'], [])

    # ── Replies, last active, phone, whole-tuition messages ────────────────

    def test_reply_quotes_the_original_from_the_same_chat_only(self):
        conv_id = self.start(self.enrolled, self.tutor).data['id']
        question = self.send(self.enrolled, conv_id, 'In Q3, how do I use v^2 = u^2 + 2as?').data
        answer = self.send(self.tutor, conv_id, 'Put v = 0.', reply_to=question['id'])
        self.assertEqual(answer.status_code, status.HTTP_201_CREATED)
        self.assertEqual(answer.data['reply_to']['id'], question['id'])
        self.assertFalse(answer.data['reply_to']['mine'])
        other = self.start(self.tutor, self.requested).data['id']
        foreign = self.send(self.tutor, other, 'Elsewhere').data
        self.assertEqual(self.send(self.tutor, conv_id, 'x', reply_to=foreign['id']).status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.send(self.tutor, conv_id, 'x', reply_to='abc').status_code, status.HTTP_400_BAD_REQUEST)

    def test_last_active_and_phone_only_for_tutors(self):
        self.enrolled.phone = '01700000000'
        self.enrolled.save()
        self.tutor.phone = '01811111111'
        self.tutor.save()
        self.client.force_authenticate(self.enrolled)
        self.client.get(reverse('chat-unread'))
        self.client.force_authenticate(self.tutor)
        contacts = {c['name']: c for c in self.client.get(reverse('chat-contacts')).data['results']}
        self.assertIsNotNone(contacts['Rafi Hasan']['last_seen'])
        self.assertEqual(contacts['Rafi Hasan']['phone'], '01700000000')
        self.client.force_authenticate(self.enrolled)
        tutor_card = self.client.get(reverse('chat-contacts')).data['results'][0]
        self.assertIsNone(tutor_card['phone'], "a tutor's number is not handed to students")

    def test_message_a_whole_tuition(self):
        classmate = make_user('stu_e', User.Role.STUDENT, first_name='Mitu')
        TuitionEnrollment.objects.create(tuition=self.enrollment.tuition, student=classmate)
        self.client.force_authenticate(self.tutor)
        url = reverse('chat-broadcast')
        body = {'tuition_id': str(self.enrollment.tuition.id), 'body': 'No class today.', 'client_ref': 'b1'}
        resp = self.client.post(url, body, format='json')
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data, {'sent': 2, 'students': 2})
        # Sent again (bad connection): kept once.
        self.assertEqual(self.client.post(url, body, format='json').data['sent'], 0)
        self.client.force_authenticate(classmate)
        chats = self.client.get(reverse('chat-list')).data['results']
        self.assertEqual(chats[0]['last_message']['body'], 'No class today.')
        self.assertEqual(chats[0]['unread'], 1)
        # Students, other tutors' tuitions and empty messages are refused.
        self.assertEqual(self.client.post(url, body, format='json').status_code, status.HTTP_403_FORBIDDEN)
        self.client.force_authenticate(self.other_tutor)
        self.assertEqual(self.client.post(url, body, format='json').status_code, status.HTTP_404_NOT_FOUND)
        self.client.force_authenticate(self.tutor)
        self.assertEqual(self.client.post(url, {**body, 'body': ' '}, format='json').status_code, status.HTTP_400_BAD_REQUEST)
