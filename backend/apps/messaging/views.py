"""
Chat between a tutor and their students.

GET  /api/v1/chats/                       my conversations, newest first, with unread counts
GET  /api/v1/chats/unread/                {unread, conversations} for the badge
GET  /api/v1/chats/contacts/              everyone I may message (with their conversation, if any)
POST /api/v1/chats/start/                 {user_id} -> the conversation with that person (made if new)
GET  /api/v1/chats/<id>/                  one conversation
GET  /api/v1/chats/<id>/messages/         ?after=<id> (new ones) | ?before=<id> (older), &limit=
POST /api/v1/chats/<id>/messages/         {body, client_ref} or multipart {image, body, client_ref}
POST /api/v1/chats/<id>/read/             everything up to now has been seen

Students see their tutor as "Ashraf Sir". Sending needs the tutor and student
to still be linked; reading an old conversation does not.
"""
import os
import uuid

from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from django.db.models import Count, F, Max, Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from apps.authentication.naming import sir_name
from config.api import ObjectJSONParser

from .links import are_linked, linked_ids
from .models import Conversation, Message

MAX_PAGE = 100


def _iso(value):
    return value.strftime('%Y-%m-%dT%H:%M:%S.%fZ') if value else None


def _abs(request, url):
    return request.build_absolute_uri(url) if request else url


def display_name(person, viewer):
    """A tutor is "Ashraf Sir" to students; students go by their full name."""
    if person.role == 'TUTOR' and viewer.role == 'STUDENT':
        return sir_name(person)
    return person.get_full_name() or person.username


def person_json(person, viewer, request):
    return {
        'id': str(person.id),
        'name': display_name(person, viewer),
        'username': person.username,
        'role': person.role,
        'photo': _abs(request, person.profile_picture.url) if person.profile_picture else None,
    }


def message_json(message, viewer, request):
    return {
        'id': message.id,
        'body': message.body,
        'image': _abs(request, message.image.url) if message.image else None,
        'mine': message.sender_id == viewer.id,
        'sender_id': str(message.sender_id),
        'client_ref': message.client_ref,
        'created_at': _iso(message.created_at),
    }


def _my_conversations(user):
    if user.role == 'TUTOR':
        return Conversation.objects.filter(tutor=user)
    return Conversation.objects.filter(student=user)


def _with_unread(qs, user):
    read_at = F(Conversation.read_field(user))
    from_other = ~Q(messages__sender=user)
    unseen = Q(**{f'{Conversation.read_field(user)}__isnull': True}) | Q(messages__created_at__gt=read_at)
    return qs.annotate(unread=Count('messages', filter=from_other & unseen), last_id=Max('messages__id'))


def conversation_json(conv, user, request, last=None, linked=None):
    other = conv.other(user)
    return {
        'id': str(conv.id),
        'other': person_json(other, user, request),
        'last_message': message_json(last, user, request) if last else None,
        'last_message_at': _iso(conv.last_message_at),
        'unread': getattr(conv, 'unread', 0),
        'other_read_at': _iso(conv.other_read_at(user)),
        'can_send': (other.id in linked) if linked is not None else True,
    }


def _conversation_for(request, pk):
    conv = get_object_or_404(Conversation.objects.select_related('tutor', 'student'), pk=pk)
    if not conv.has_member(request.user):
        # Someone else's conversation looks the same as one that does not exist.
        from django.http import Http404
        raise Http404
    return conv


class ChatListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        convs = list(
            _with_unread(_my_conversations(user), user)
            .filter(last_message_at__isnull=False)
            .select_related('tutor', 'student')
            .order_by('-last_message_at')[:200]
        )
        lasts = Message.objects.in_bulk([c.last_id for c in convs if c.last_id])
        linked = linked_ids(user)
        results = [conversation_json(c, user, request, lasts.get(c.last_id), linked) for c in convs]
        return Response({'results': results, 'unread_total': sum(c.unread for c in convs)})


class UnreadView(APIView):
    """Small and cheap: polled for the badge on the chat button."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        counts = [c.unread for c in _with_unread(_my_conversations(user), user).only('id')]
        return Response({'unread': sum(counts), 'conversations': sum(1 for n in counts if n)})


class ContactsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        from django.contrib.auth import get_user_model
        user = request.user
        people = get_user_model().objects.filter(id__in=linked_ids(user), is_active=True)
        existing = {
            (c.student_id if user.role == 'TUTOR' else c.tutor_id): str(c.id)
            for c in _my_conversations(user).only('id', 'tutor_id', 'student_id')
        }
        results = [
            {**person_json(p, user, request), 'conversation_id': existing.get(p.id)}
            for p in people
        ]
        results.sort(key=lambda r: r['name'].lower())
        return Response({'results': results})


class StartChatView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        from django.contrib.auth import get_user_model
        User = get_user_model()
        user = request.user
        try:
            other = User.objects.get(pk=request.data.get('user_id'), is_active=True)
        except (User.DoesNotExist, ValueError, TypeError, DjangoValidationError):
            return Response({'message': 'That person was not found.'}, status=status.HTTP_404_NOT_FOUND)
        if {user.role, other.role} != {'TUTOR', 'STUDENT'}:
            return Response({'message': 'Chats are between a tutor and their students.'}, status=status.HTTP_403_FORBIDDEN)
        tutor, student = (user, other) if user.role == 'TUTOR' else (other, user)
        if not are_linked(tutor, student):
            return Response({'message': 'You can message only your own tutors and students.'}, status=status.HTTP_403_FORBIDDEN)
        conv, _ = Conversation.objects.get_or_create(tutor=tutor, student=student)
        conv = _with_unread(Conversation.objects.filter(pk=conv.pk), user).select_related('tutor', 'student').get()
        last = Message.objects.filter(pk=conv.last_id).first() if conv.last_id else None
        return Response(conversation_json(conv, user, request, last, {other.id}))


class ConversationView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        user = request.user
        conv = _conversation_for(request, pk)
        conv = _with_unread(Conversation.objects.filter(pk=conv.pk), user).select_related('tutor', 'student').get()
        last = Message.objects.filter(pk=conv.last_id).first() if conv.last_id else None
        return Response(conversation_json(conv, user, request, last, linked_ids(user)))


class MessagesView(APIView):
    permission_classes = [IsAuthenticated]
    # The API's own JSON parser: a body that is not a JSON object is a clean 400.
    parser_classes = [ObjectJSONParser, MultiPartParser, FormParser]
    throttle_scope = 'chat'
    MAX_IMAGE_BYTES = 8 * 1024 * 1024

    def get_throttles(self):
        # Only sending is limited; reading and polling are not.
        return [ScopedRateThrottle()] if self.request.method == 'POST' else super().get_throttles()

    def get(self, request, pk):
        user = request.user
        conv = _conversation_for(request, pk)
        qs = conv.messages.all()
        try:
            limit = max(1, min(int(request.query_params.get('limit', 50)), MAX_PAGE))
            after = request.query_params.get('after')
            before = request.query_params.get('before')
            after = int(after) if after not in (None, '') else None
            before = int(before) if before not in (None, '') else None
        except ValueError:
            return Response({'message': 'after, before and limit must be numbers.'}, status=status.HTTP_400_BAD_REQUEST)

        if after is not None:
            rows = list(qs.filter(id__gt=after).order_by('id')[:limit + 1])
            has_more = len(rows) > limit
            rows = rows[:limit]
        else:
            if before is not None:
                qs = qs.filter(id__lt=before)
            rows = list(qs.order_by('-id')[:limit + 1])
            has_more = len(rows) > limit
            rows = list(reversed(rows[:limit]))
        return Response({
            'results': [message_json(m, user, request) for m in rows],
            'has_more': has_more,
            'other_read_at': _iso(conv.other_read_at(user)),
            'can_send': conv.other(user).id in linked_ids(user),
        })

    def post(self, request, pk):
        user = request.user
        conv = _conversation_for(request, pk)
        tutor, student = conv.tutor, conv.student
        if not (tutor.is_active and student.is_active and are_linked(tutor, student)):
            return Response(
                {'message': 'You are no longer connected, so new messages cannot be sent.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        body = str(request.data.get('body') or '').strip()
        client_ref = str(request.data.get('client_ref') or '')[:64]
        image = request.FILES.get('image')
        if not body and not image:
            return Response({'message': 'Write a message or add a photo.'}, status=status.HTTP_400_BAD_REQUEST)
        if len(body) > Message.MAX_LENGTH:
            return Response(
                {'message': f'A message can be at most {Message.MAX_LENGTH} characters.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if client_ref:
            already = Message.objects.filter(sender=user, client_ref=client_ref, conversation=conv).first()
            if already:
                return Response(message_json(already, user, request), status=status.HTTP_200_OK)
        if image is not None:
            error = self._check_image(image)
            if error:
                return Response({'image': [error], 'message': error}, status=status.HTTP_400_BAD_REQUEST)

        try:
            with transaction.atomic():
                message = Message(conversation=conv, sender=user, body=body, client_ref=client_ref)
                if image is not None:
                    ext = os.path.splitext(image.name or '')[1].lower() or '.jpg'
                    message.image.save(f'{conv.pk}-{uuid.uuid4().hex[:10]}{ext}', image, save=False)
                message.save()
                # Sending counts as having read everything before it.
                Conversation.objects.filter(pk=conv.pk).update(
                    last_message_at=message.created_at, **{Conversation.read_field(user): message.created_at},
                )
        except IntegrityError:
            # The same client_ref arrived twice at once: answer with the one that was kept.
            message = Message.objects.get(sender=user, client_ref=client_ref)
            return Response(message_json(message, user, request), status=status.HTTP_200_OK)
        return Response(message_json(message, user, request), status=status.HTTP_201_CREATED)

    def _check_image(self, image):
        from PIL import Image, UnidentifiedImageError
        from apps.exams.uploads import UploadRejected, validate_upload
        try:
            validate_upload(image)
            if os.path.splitext(image.name or '')[1].lower() == '.pdf':
                raise UploadRejected('Send a picture (PNG, JPEG or WebP).')
            if image.size > self.MAX_IMAGE_BYTES:
                raise UploadRejected('The picture is larger than 8 MB.')
            try:
                Image.open(image).verify()
            except (UnidentifiedImageError, OSError, SyntaxError, ValueError) as exc:
                raise UploadRejected('This file is not a picture that can be opened.') from exc
            image.seek(0)
        except UploadRejected as exc:
            return str(exc)
        return None


class ReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, pk):
        user = request.user
        conv = _conversation_for(request, pk)
        now = timezone.now()
        Conversation.objects.filter(pk=conv.pk).update(**{Conversation.read_field(user): now})
        return Response({'read_at': _iso(now)})


def unread_notifications(user, request=None):
    """Notification-feed items: one per conversation with unread messages (newest unread message as id)."""
    convs = (
        _with_unread(_my_conversations(user), user)
        .filter(unread__gt=0)
        .select_related('tutor', 'student')
    )
    items = []
    for conv in convs:
        other = conv.other(user)
        newest = conv.messages.exclude(sender=user).order_by('-id').first()
        if newest is None:
            continue
        text = newest.body.strip() or '📷 Photo'
        if conv.unread > 1:
            text = f'{text[:100]} (+{conv.unread - 1} more)'
        items.append({
            'id': f'msg-{newest.id}',
            'kind': 'message',
            'title': display_name(other, user),
            'body': text[:140],
            'when': newest.created_at,
            'link': f'/chats/{conv.id}',
        })
    return items
