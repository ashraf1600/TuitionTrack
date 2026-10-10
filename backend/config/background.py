"""
Work that must not hold up the request: e-mails today.

`run_after_commit(fn, ...)` runs `fn` once the current database transaction has
committed (so it never acts on data that was rolled back), on a short-lived
background thread, and logs any failure instead of raising. With
BACKGROUND_TASKS_INLINE (the test suite) it runs straight away on the caller's
thread, so tests can assert on the result.

A thread is enough for a few e-mails on one web process. If the work grows
(many recipients, retries), move it to a real queue such as Django-Q or Celery.
"""
import logging
import threading

from django.conf import settings
from django.db import transaction

logger = logging.getLogger(__name__)


def run_after_commit(fn, *args, **kwargs):
    name = getattr(fn, '__name__', 'task')

    def safe_run():
        try:
            fn(*args, **kwargs)
        except Exception:  # noqa: BLE001 - a background failure is logged, never raised into a request
            logger.exception('Background task %s failed', name)

    if getattr(settings, 'BACKGROUND_TASKS_INLINE', False):
        safe_run()
        return

    def start():
        threading.Thread(target=safe_run, name=f'bg-{name}', daemon=True).start()

    transaction.on_commit(start)
