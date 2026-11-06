"""
"Something changed for you": after a tutor saves anything (a class marked done,
homework set, an exam published, a payment recorded…), their students' apps
are told to check their notifications; after a student does (homework done, a
test handed in), their tutor's are.

Open apps hear it over /ws/ and refresh the bell; closed ones get a silent push
that makes them fetch /notifications/ and show what is new. The server already
works out *what* is new, so this only says *when* to look.

Open apps hear about every save at once. For closed apps, saves close together
are gathered: one silent push goes out a few seconds after the first.
"""
import logging
import threading

from django.conf import settings
from django.core.cache import cache

logger = logging.getLogger(__name__)

WRITE_METHODS = ('POST', 'PUT', 'PATCH', 'DELETE')
SKIP_PREFIXES = ('/api/v1/auth/', '/api/v1/chats/', '/api/v1/push/', '/api/v1/meta/')
GATHER_SECONDS = 6


def _targets(user_id):
    from django.contrib.auth import get_user_model

    from .links import linked_ids
    user = get_user_model().objects.filter(pk=user_id, is_active=True).first()
    return list(linked_ids(user)) if user is not None else []


def _push_nudge(user_id):
    """The silent push to closed apps, sent once at the end of the gathering window."""
    from django.db import close_old_connections

    from . import push
    try:
        targets = _targets(user_id)
        if targets:
            push.send(targets, data={'kind': 'sync'})
    except Exception:  # noqa: BLE001 - nudges are best effort; the apps also check on their own
        logger.exception('Nudge push for %s failed', user_id)
    finally:
        close_old_connections()


def nudge(user_id):
    from . import push
    from .live import _send_now

    # Open apps: right away. This runs on the request's own thread, which is what lets
    # the in-memory channel layer reach the sockets.
    targets = _targets(user_id)
    if not targets:
        return
    _send_now([(target, {'type': 'nudge'}) for target in targets])
    if not push.enabled():
        return
    if getattr(settings, 'BACKGROUND_TASKS_INLINE', False):
        _push_nudge(user_id)
        return
    # Closed apps: one silent push per person per few seconds, covering every save in between.
    if cache.add(f'nudge:{user_id}', 1, timeout=GATHER_SECONDS):
        timer = threading.Timer(GATHER_SECONDS, _push_nudge, args=(user_id,))
        timer.daemon = True
        timer.start()


class NudgeMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        if (
            request.method in WRITE_METHODS
            and 200 <= response.status_code < 300
            and request.path.startswith('/api/v1/')
            and not request.path.startswith(SKIP_PREFIXES)
        ):
            # DRF sets the signed-in user on the underlying request once the view has authenticated it.
            user = getattr(request, 'user', None)
            if user is not None and user.is_authenticated:
                try:
                    nudge(user.pk)
                except Exception:  # noqa: BLE001
                    logger.exception('Nudge not scheduled')
        return response
