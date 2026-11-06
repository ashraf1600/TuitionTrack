"""
Live updates to open apps over the WebSocket at /ws/ (see consumers.py).

Every signed-in connection joins the group ``user.<id>``. Server code calls
``send_to_users`` once its database change has committed, and each open app of
those people gets the event right away:

    {"type": "message", "conversation_id": ..., "message": {...}}   a new chat message
    {"type": "read", "conversation_id": ..., "read_at": ...}         the other side has read the chat
    {"type": "typing", "conversation_id": ...}                       the other side is typing
    {"type": "nudge"}                                                 something changed: refresh notifications

A failure here never breaks the request: the apps also check every so often.
"""
import logging

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.db import transaction

logger = logging.getLogger(__name__)


def group_for(user_id):
    return f'user.{user_id}'


def _send_now(events):
    layer = get_channel_layer()
    if layer is None:
        return
    for user_id, payload in events:
        try:
            async_to_sync(layer.group_send)(group_for(user_id), {'type': 'live.event', 'payload': payload})
        except Exception:  # noqa: BLE001 - live updates are best effort
            logger.warning('Live update to %s not sent', user_id, exc_info=True)


def send_to_users(events):
    """events: [(user_id, payload), ...], sent once the current transaction commits."""
    events = list(events)
    if events:
        transaction.on_commit(lambda: _send_now(events))
