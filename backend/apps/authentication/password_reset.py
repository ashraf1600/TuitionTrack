"""
Password reset by e-mail.

One e-mail carries both a 6-digit code (typed in the mobile app or on the
website) and a link (opened in a browser). Either way the client ends up with
Django's own reset token (uid + token) and sets the new password through
POST /auth/password-reset/confirm/.

    request_reset(identifier)        -> e-mails every matching account that has an address
    redeem_code(identifier, code)    -> the user, once, for a correct and fresh code
"""
import secrets
from datetime import timedelta
from html import escape

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.tokens import default_token_generator
from django.core.mail import EmailMultiAlternatives
from django.db.models import F, Q
from django.utils import timezone
from django.utils.crypto import constant_time_compare, salted_hmac
from django.utils.encoding import force_bytes
from django.utils.http import urlsafe_base64_encode

from config.background import run_after_commit

from .models import PasswordResetCode

User = get_user_model()

CODE_LENGTH = 6
# A new code is not e-mailed more often than this, and not more than MAX_PER_HOUR an hour,
# so the form cannot be used to flood someone's inbox.
RESEND_COOLDOWN = timedelta(seconds=60)
MAX_PER_HOUR = 5

GENERIC_MESSAGE = (
    'If that account has an email address, we have sent it a 6-digit code and a reset link. '
    'Check your inbox and spam folder. Students without an email can ask their tutor to reset the password.'
)


def _hash(user, code):
    return salted_hmac('tuitiontrack.password-reset-code', f'{user.pk}:{code}').hexdigest()


def matching_users(identifier):
    """Active accounts with an e-mail address whose username or e-mail is `identifier`."""
    typed = (identifier or '').strip()
    if not typed:
        return []
    return list(
        User.objects.filter(is_active=True)
        .filter(Q(username__iexact=typed) | Q(email__iexact=typed))
        .exclude(email='')[:3]
    )


def reset_link(user):
    uid = urlsafe_base64_encode(force_bytes(user.pk))
    token = default_token_generator.make_token(user)
    return uid, token, f"{settings.FRONTEND_URL.rstrip('/')}/reset-password?uid={uid}&token={token}"


def link_tokens(user):
    uid, token, _ = reset_link(user)
    return {'uid': uid, 'token': token}


def _may_send(user, now):
    recent = PasswordResetCode.objects.filter(user=user, created_at__gte=now - timedelta(hours=1))
    if recent.count() >= MAX_PER_HOUR:
        return False
    return not recent.filter(created_at__gte=now - RESEND_COOLDOWN).exists()


def _new_code(user, now):
    """Replaces any earlier unused code with a fresh one and returns the plain digits."""
    PasswordResetCode.objects.filter(user=user, used_at__isnull=True).update(used_at=now)
    code = ''.join(secrets.choice('0123456789') for _ in range(CODE_LENGTH))
    PasswordResetCode.objects.create(
        user=user,
        code_hash=_hash(user, code),
        expires_at=now + timedelta(minutes=settings.PASSWORD_RESET_CODE_MINUTES),
    )
    return code


def build_email(user, code, link):
    name = user.get_full_name() or user.username
    minutes = settings.PASSWORD_RESET_CODE_MINUTES
    subject = f'{code} is your TuitionTrack password reset code'
    text = (
        f'Hello {name},\n\n'
        f'Your password reset code is: {code}\n'
        f'Type it in the TuitionTrack app or website. It works once and expires in {minutes} minutes.\n\n'
        f'Or open this link to choose a new password in your browser:\n{link}\n\n'
        f'Your username is: {user.username}\n\n'
        f'If you did not ask for this, ignore this email — your password stays the same.\n\n'
        f'— TuitionTrack'
    )
    spaced = ' '.join(code)
    html = f"""<!doctype html>
<html><body style="margin:0;padding:0;background:#f1f5f9;font-family:Arial,Helvetica,sans-serif;color:#0f172a">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f1f5f9;padding:24px 12px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:16px;padding:28px">
        <tr><td style="font-size:20px;font-weight:700;color:#4f46e5">TuitionTrack</td></tr>
        <tr><td style="padding-top:18px;font-size:15px;line-height:1.5">Hello {escape(name)},<br>
          use this code to reset your password:</td></tr>
        <tr><td align="center" style="padding:20px 0">
          <div style="display:inline-block;font-size:32px;letter-spacing:6px;font-weight:700;background:#eef2ff;color:#3730a3;border-radius:12px;padding:14px 22px;font-family:'Courier New',monospace">{spaced}</div>
        </td></tr>
        <tr><td style="font-size:13px;color:#475569;line-height:1.5">It works once and expires in {minutes} minutes.
          Type it in the TuitionTrack app or website.</td></tr>
        <tr><td align="center" style="padding:22px 0 8px">
          <a href="{escape(link)}" style="display:inline-block;background:#4f46e5;color:#ffffff;text-decoration:none;font-weight:600;font-size:14px;border-radius:10px;padding:12px 22px">Choose a new password</a>
        </td></tr>
        <tr><td style="padding-top:14px;font-size:13px;color:#475569">Your username: <b>{escape(user.username)}</b></td></tr>
        <tr><td style="padding-top:18px;font-size:12px;color:#94a3b8;line-height:1.5">If you did not ask for this, ignore this email — your password stays the same.</td></tr>
      </table>
    </td></tr>
  </table>
</body></html>"""
    message = EmailMultiAlternatives(
        subject=subject, body=text, from_email=settings.DEFAULT_FROM_EMAIL, to=[user.email],
    )
    message.attach_alternative(html, 'text/html')
    return message


def request_reset(identifier):
    """E-mails a code and link to each matching account. Silent about who exists."""
    now = timezone.now()
    messages = []
    for user in matching_users(identifier):
        if not _may_send(user, now):
            continue
        code = _new_code(user, now)
        _, _, link = reset_link(user)
        messages.append(build_email(user, code, link))

    def send_all():
        for message in messages:
            # Raised failures are logged by run_after_commit (and reach Sentry when set up).
            message.send(fail_silently=False)

    # Off the request, so the answer does not reveal (by its timing) whether an e-mail went out.
    if messages:
        run_after_commit(send_all)


class CodeError(Exception):
    """The code cannot be accepted; the message is safe to show."""


def redeem_code(identifier, code):
    """
    The account whose newest code is `code`. The code is then used up.
    Wrong guesses count against the code; after too many it stops working.
    """
    code = ''.join(ch for ch in str(code or '') if ch.isdigit())
    invalid = CodeError('That code is not correct or has expired. Check the email or ask for a new code.')
    if len(code) != CODE_LENGTH:
        raise invalid
    now = timezone.now()
    for user in matching_users(identifier):
        latest = (
            PasswordResetCode.objects.filter(user=user, used_at__isnull=True, expires_at__gt=now)
            .order_by('-created_at').first()
        )
        if latest is None:
            continue
        if latest.attempts >= settings.PASSWORD_RESET_CODE_ATTEMPTS:
            raise CodeError('Too many wrong tries. Ask for a new code.')
        if constant_time_compare(latest.code_hash, _hash(user, code)):
            # Only one caller can use a code, even if two arrive at once.
            if PasswordResetCode.objects.filter(pk=latest.pk, used_at__isnull=True).update(used_at=now) == 1:
                return user
            raise invalid
        PasswordResetCode.objects.filter(pk=latest.pk).update(attempts=F('attempts') + 1)
    raise invalid
