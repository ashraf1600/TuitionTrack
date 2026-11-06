"""
Push notifications through Firebase Cloud Messaging (FCM HTTP v1), so a phone
hears about a new message even when the app is closed.

Turned on by the FCM_SERVICE_ACCOUNT setting: the Firebase service account key
(Firebase console → Project settings → Service accounts → Generate new private
key), as the JSON text or that text base64-encoded. Without it nothing is sent
and the apps keep checking on their own every 15 minutes.

Two kinds of push:
- a chat message: a visible notification ("Ashraf Sir", "Solve 3.2 tonight"),
  shown by Android itself even when the app is not running;
- "sync": a silent nudge. The app wakes up, asks the server for its
  notifications and shows the new ones (homework, results, payments…).
"""
import base64
import json
import logging
import threading

import requests
from django.conf import settings

from .models import PushDevice

logger = logging.getLogger(__name__)

SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'
_lock = threading.Lock()
_credentials = None
_project_id = None


def _service_account():
    raw = (getattr(settings, 'FCM_SERVICE_ACCOUNT', '') or '').strip()
    if not raw:
        return None
    if not raw.startswith('{'):
        try:
            raw = base64.b64decode(raw).decode('utf-8')
        except (ValueError, UnicodeDecodeError):
            logger.error('FCM_SERVICE_ACCOUNT is neither JSON nor base64 JSON')
            return None
    try:
        return json.loads(raw)
    except ValueError:
        logger.error('FCM_SERVICE_ACCOUNT is not valid JSON')
        return None


def enabled():
    return _service_account() is not None


def _access_token():
    global _credentials, _project_id
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account

    with _lock:
        if _credentials is None:
            info = _service_account()
            if info is None:
                return None, None
            _credentials = service_account.Credentials.from_service_account_info(info, scopes=[SCOPE])
            _project_id = info.get('project_id')
        if not _credentials.valid:
            _credentials.refresh(Request())
        return _credentials.token, _project_id


def _post(token, project_id, message):
    return requests.post(
        f'https://fcm.googleapis.com/v1/projects/{project_id}/messages:send',
        json={'message': message},
        headers={'Authorization': f'Bearer {token}'},
        timeout=10,
    )


def _gone(response):
    """True when FCM says this phone token no longer exists (app removed, data cleared)."""
    if response.status_code == 404:
        return True
    if response.status_code == 400:
        try:
            details = response.json().get('error', {}).get('details', [])
        except ValueError:
            return False
        return any(d.get('errorCode') in ('UNREGISTERED', 'INVALID_ARGUMENT') for d in details)
    return False


def send(user_ids, *, data, title=None, body=None, tag=None, channel='messages'):
    """Sends one push to every phone of [user_ids]. data values must be strings."""
    if not enabled():
        return 0
    devices = list(
        PushDevice.objects.filter(user_id__in=list(user_ids), user__is_active=True).values_list('id', 'token')
    )
    if not devices:
        return 0
    try:
        access, project_id = _access_token()
    except Exception:  # noqa: BLE001 - a bad key must not break anything else
        logger.exception('FCM sign-in failed')
        return 0
    if not access or not project_id:
        return 0
    data = {k: str(v) for k, v in data.items()}
    sent = 0
    for device_id, token in devices:
        message = {'token': token, 'data': data, 'android': {'priority': 'high'}}
        if title is not None:
            message['notification'] = {'title': title[:100], 'body': (body or '')[:240]}
            message['android']['notification'] = {
                'channel_id': channel,
                'icon': 'ic_stat_tt',
                'color': '#3F7CB5',
                **({'tag': tag} if tag else {}),
            }
        else:
            # Silent nudges replace each other while waiting on a phone that is offline.
            message['android']['collapse_key'] = data.get('kind', 'sync')
            message['android']['ttl'] = '3600s'
        try:
            response = _post(access, project_id, message)
        except requests.RequestException:
            logger.warning('FCM unreachable', exc_info=True)
            break
        if response.status_code == 200:
            sent += 1
        elif _gone(response):
            PushDevice.objects.filter(pk=device_id).delete()
        else:
            logger.warning('FCM refused a push: %s %s', response.status_code, response.text[:300])
    return sent
