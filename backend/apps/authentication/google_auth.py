"""
Sign in with Google.

The website (Google Identity Services button) and the Android app
(google_sign_in, with serverClientId = the web client ID) both get a Google
**ID token** and send it to POST /auth/google/. This module checks the token
with Google's public keys and finds — or, when asked, creates — the account.

Matching an account, in order:
  1. the Google account already linked to a user (google_sub);
  2. exactly one active user whose e-mail is the token's verified e-mail
     (then the Google account is linked for next time).
Having the verified mailbox is the same proof a password-reset e-mail relies on.
"""
import re
import threading
import time

from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction

User = get_user_model()

GOOGLE_ISSUERS = ('accounts.google.com', 'https://accounts.google.com')


class GoogleAuthError(Exception):
    """The token cannot be used to sign in. `code` is machine-readable; the message is safe to show."""

    def __init__(self, message, code='google_auth_failed', status=400, extra=None):
        super().__init__(message)
        self.code = code
        self.status = status
        self.extra = extra or {}


def audiences():
    return [cid for cid in [settings.GOOGLE_CLIENT_ID, *settings.GOOGLE_EXTRA_CLIENT_IDS] if cid]


def google_enabled():
    return bool(settings.GOOGLE_CLIENT_ID)


# ── Token verification ──────────────────────────────────────────────────────

_cache_lock = threading.Lock()
_cached = {}  # url -> (expires_at, response)


def _caching_request():
    """A google-auth transport that keeps Google's signing keys for an hour instead of fetching them per sign-in."""
    import google.auth.transport.requests as google_requests

    class CachingRequest(google_requests.Request):
        def __call__(self, url, method='GET', **kwargs):
            if method != 'GET':
                return super().__call__(url, method=method, **kwargs)
            now = time.monotonic()
            with _cache_lock:
                hit = _cached.get(url)
                if hit and hit[0] > now:
                    return hit[1]
            response = super().__call__(url, method=method, **kwargs)
            if response.status == 200:
                with _cache_lock:
                    _cached[url] = (now + 3600, response)
            return response

    return CachingRequest()


def verify_id_token(raw_token):
    """The checked claims of a Google ID token, or GoogleAuthError."""
    if not google_enabled():
        raise GoogleAuthError('Sign in with Google is not set up on this server.', 'google_not_configured', 503)
    if not isinstance(raw_token, str) or raw_token.count('.') != 2 or len(raw_token) > 8192:
        raise GoogleAuthError('The Google sign-in did not complete. Please try again.')

    from google.auth import exceptions as google_exceptions
    from google.oauth2 import id_token

    try:
        # Checks the signature, expiry, audience (our client IDs) and issuer.
        claims = id_token.verify_oauth2_token(raw_token, _caching_request(), audience=audiences(), clock_skew_in_seconds=30)
    except google_exceptions.TransportError as exc:
        raise GoogleAuthError('Could not reach Google to check the sign-in. Please try again.', 'google_unreachable', 503) from exc
    except (ValueError, google_exceptions.GoogleAuthError) as exc:
        raise GoogleAuthError('The Google sign-in could not be verified. Please try again.') from exc

    if claims.get('iss') not in GOOGLE_ISSUERS or not claims.get('sub'):
        raise GoogleAuthError('The Google sign-in could not be verified. Please try again.')
    email = (claims.get('email') or '').strip()
    if not email or claims.get('email_verified') not in (True, 'true'):
        raise GoogleAuthError('Your Google account has no verified email address.', 'google_email_unverified')
    return claims


# ── Accounts ────────────────────────────────────────────────────────────────

def find_user(claims):
    """The account for these claims, or None. Links the Google account on first use."""
    sub = str(claims['sub'])
    user = User.objects.filter(google_sub=sub).first()
    if user is None:
        matches = list(User.objects.filter(email__iexact=claims['email'], google_sub__isnull=True)[:2])
        if len(matches) > 1:
            raise GoogleAuthError(
                'More than one TuitionTrack account uses this email address. Sign in with your username and password.',
                'google_email_ambiguous', 409,
            )
        user = matches[0] if matches else None
        if user is not None:
            user.google_sub = sub
            user.save(update_fields=['google_sub', 'updated_at'])
    if user is not None and not user.is_active:
        raise GoogleAuthError('This account has been deactivated. Contact your tutor.', 'account_inactive', 403)
    return user


def _username_from(email):
    base = re.sub(r'[^\w.+-]', '', email.split('@')[0])[:30].strip('.') or 'user'
    candidate = base
    n = 1
    while User.objects.filter(username__iexact=candidate).exists():
        n += 1
        candidate = f'{base}{n}'
    return candidate


def create_user(claims, role):
    """A new tutor or student account for this Google account (no password until they set one)."""
    from apps.students.models import StudentProfile

    if not settings.GOOGLE_SIGNUP_ENABLED:
        raise GoogleAuthError('New accounts cannot be created with Google here. Ask for an account first.',
                              'google_signup_disabled', 403)
    if role not in (User.Role.TUTOR, User.Role.STUDENT):
        raise GoogleAuthError('Choose whether this is a tutor or a student account.', 'invalid_role')
    if User.objects.filter(email__iexact=claims['email']).exists():
        raise GoogleAuthError('An account with this email address already exists.', 'google_email_ambiguous', 409)

    for _ in range(3):
        try:
            with transaction.atomic():
                user = User(
                    username=_username_from(claims['email']),
                    email=claims['email'],
                    first_name=(claims.get('given_name') or claims.get('name') or '')[:150],
                    last_name=(claims.get('family_name') or '')[:150],
                    role=role,
                    google_sub=str(claims['sub']),
                )
                # They sign in with Google; "Forgot password" (to this same mailbox) can add a password later.
                user.set_unusable_password()
                user.save()
                if role == User.Role.STUDENT:
                    StudentProfile.objects.create(user=user, tuition_fee=0, cycle_length=12)
                return user
        except IntegrityError:
            continue  # someone took the same username at the same moment; pick another
    raise GoogleAuthError('Could not create the account. Please try again.', 'google_signup_failed', 500)
