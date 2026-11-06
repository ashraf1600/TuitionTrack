"""
The live connection at /ws/: chat messages, "seen" and "typing" as they happen.

The app opens the socket, then sends its access token as the first message
(never in the address, so it stays out of server logs):

    → {"type": "auth", "token": "<access token>"}
    ← {"type": "ready"}                          or {"type": "auth_failed"} and the socket closes (4401)
    → {"type": "typing", "conversation_id": "…"} tells the other person you are typing
    → {"type": "ping"}                            ← {"type": "pong"}

Everything else arrives from the server; see live.py for the events.
"""
import asyncio

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer

from .live import group_for

AUTH_TIMEOUT_SECONDS = 10
CLOSE_UNAUTHORIZED = 4401


@database_sync_to_async
def _user_for(raw_token):
    from rest_framework_simplejwt.authentication import JWTAuthentication
    from rest_framework_simplejwt.exceptions import AuthenticationFailed, InvalidToken, TokenError

    if not isinstance(raw_token, str) or not raw_token or len(raw_token) > 4096:
        return None
    auth = JWTAuthentication()
    try:
        user = auth.get_user(auth.get_validated_token(raw_token.encode()))
    except (InvalidToken, TokenError, AuthenticationFailed):
        return None
    return user if user.is_active else None


@database_sync_to_async
def _other_member(user, conversation_id):
    """The other person in a conversation of [user]'s, or None."""
    from django.core.exceptions import ValidationError

    from .models import Conversation
    try:
        conv = Conversation.objects.only('tutor_id', 'student_id').get(pk=conversation_id)
    except (Conversation.DoesNotExist, ValidationError, ValueError, TypeError):
        return None
    if user.id == conv.tutor_id:
        return conv.student_id
    if user.id == conv.student_id:
        return conv.tutor_id
    return None


@database_sync_to_async
def _touch_last_seen(user):
    from .views import touch_last_seen
    touch_last_seen(user)


class LiveConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        self.user = None
        self.group = None
        self.members = {}  # conversation id -> the other person's id
        await self.accept()
        self.auth_timer = asyncio.create_task(self._close_if_silent())

    async def _close_if_silent(self):
        await asyncio.sleep(AUTH_TIMEOUT_SECONDS)
        if self.user is None:
            await self.close(code=CLOSE_UNAUTHORIZED)

    async def disconnect(self, code):
        timer = getattr(self, 'auth_timer', None)
        if timer is not None:
            timer.cancel()
        if self.group:
            await self.channel_layer.group_discard(self.group, self.channel_name)

    async def receive_json(self, content, **kwargs):
        if not isinstance(content, dict):
            return
        kind = content.get('type')
        if self.user is None:
            user = await _user_for(content.get('token')) if kind == 'auth' else None
            if user is None:
                await self.send_json({'type': 'auth_failed'})
                await self.close(code=CLOSE_UNAUTHORIZED)
                return
            self.user = user
            self.auth_timer.cancel()
            self.group = group_for(user.id)
            await self.channel_layer.group_add(self.group, self.channel_name)
            await _touch_last_seen(user)
            await self.send_json({'type': 'ready'})
            return
        if kind == 'ping':
            await self.send_json({'type': 'pong'})
        elif kind == 'typing':
            conv_id = str(content.get('conversation_id') or '')[:64]
            if conv_id not in self.members:
                self.members[conv_id] = await _other_member(self.user, conv_id)
            other = self.members[conv_id]
            if other is not None:
                await self.channel_layer.group_send(
                    group_for(other),
                    {'type': 'live.event', 'payload': {'type': 'typing', 'conversation_id': conv_id}},
                )

    async def live_event(self, event):
        await self.send_json(event['payload'])
