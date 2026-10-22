"""
E-mail backends that send over HTTPS instead of SMTP.

Render's free web services block outgoing SMTP (ports 25, 465 and 587), so
Django's SMTP backend cannot deliver mail there. These backends call an
e-mail provider's HTTPS API (port 443) instead. Pick one with EMAIL_BACKEND:

    EMAIL_BACKEND=config.email_backends.BrevoEmailBackend    # BREVO_API_KEY
    EMAIL_BACKEND=config.email_backends.ResendEmailBackend   # RESEND_API_KEY

Brevo (brevo.com) works with a single verified sender address — a Gmail
address is fine — so it needs no domain of your own. Resend needs a verified
domain before it will deliver to anyone but the account owner.

DEFAULT_FROM_EMAIL must be the sender address verified with the provider.
Only the standard library is used, so there is nothing extra to install.
"""
import json
import logging
import urllib.error
import urllib.request
from email.utils import parseaddr

from django.conf import settings
from django.core.mail.backends.base import BaseEmailBackend

logger = logging.getLogger(__name__)

TIMEOUT_SECONDS = 15


class EmailDeliveryError(Exception):
    """The provider refused the message or could not be reached."""


def _split_address(value):
    name, address = parseaddr(value or '')
    return name, address


def _html_body(message):
    for content, mimetype in getattr(message, 'alternatives', None) or []:
        if mimetype == 'text/html':
            return content
    if getattr(message, 'content_subtype', '') == 'html':
        return message.body
    return None


class _HttpEmailBackend(BaseEmailBackend):
    """Shared plumbing: one HTTPS POST per message, failures raised unless fail_silently."""

    endpoint = ''
    api_key_setting = ''

    def __init__(self, fail_silently=False, **kwargs):
        super().__init__(fail_silently=fail_silently, **kwargs)
        self.api_key = getattr(settings, self.api_key_setting, '') or ''

    def headers(self):
        raise NotImplementedError

    def payload(self, message):
        raise NotImplementedError

    def send_messages(self, email_messages):
        if not email_messages:
            return 0
        if not self.api_key:
            error = EmailDeliveryError(f'{self.api_key_setting} is not set, so no e-mail can be sent.')
            if self.fail_silently:
                logger.error(str(error))
                return 0
            raise error
        sent = 0
        for message in email_messages:
            if not message.recipients():
                continue
            try:
                self._post(self.payload(message))
                sent += 1
            except EmailDeliveryError:
                if not self.fail_silently:
                    raise
                logger.exception('E-mail to %s was not sent', ', '.join(message.recipients()))
        return sent

    def _post(self, payload):
        request = urllib.request.Request(
            self.endpoint,
            data=json.dumps(payload).encode('utf-8'),
            headers={'Content-Type': 'application/json', 'Accept': 'application/json', **self.headers()},
            method='POST',
        )
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:  # noqa: S310 - fixed https URL
                response.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode('utf-8', 'replace')[:500]
            raise EmailDeliveryError(f'{type(self).__name__}: HTTP {exc.code}: {detail}') from exc
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise EmailDeliveryError(f'{type(self).__name__}: could not reach the e-mail service: {exc}') from exc


class BrevoEmailBackend(_HttpEmailBackend):
    """Brevo transactional e-mail API (free plan: 300 e-mails a day)."""

    endpoint = 'https://api.brevo.com/v3/smtp/email'
    api_key_setting = 'BREVO_API_KEY'

    def headers(self):
        return {'api-key': self.api_key}

    def payload(self, message):
        name, address = _split_address(message.from_email or settings.DEFAULT_FROM_EMAIL)
        sender = {'email': address}
        if name:
            sender['name'] = name
        payload = {
            'sender': sender,
            'to': [{'email': _split_address(r)[1]} for r in message.to],
            'subject': message.subject,
            'textContent': message.body,
        }
        if message.cc:
            payload['cc'] = [{'email': _split_address(r)[1]} for r in message.cc]
        if message.bcc:
            payload['bcc'] = [{'email': _split_address(r)[1]} for r in message.bcc]
        if message.reply_to:
            payload['replyTo'] = {'email': _split_address(message.reply_to[0])[1]}
        html = _html_body(message)
        if html:
            payload['htmlContent'] = html
        return payload


class ResendEmailBackend(_HttpEmailBackend):
    """Resend e-mail API (needs a verified domain to send to other people)."""

    endpoint = 'https://api.resend.com/emails'
    api_key_setting = 'RESEND_API_KEY'

    def headers(self):
        return {'Authorization': f'Bearer {self.api_key}'}

    def payload(self, message):
        payload = {
            'from': message.from_email or settings.DEFAULT_FROM_EMAIL,
            'to': list(message.to),
            'subject': message.subject,
            'text': message.body,
        }
        if message.cc:
            payload['cc'] = list(message.cc)
        if message.bcc:
            payload['bcc'] = list(message.bcc)
        if message.reply_to:
            payload['reply_to'] = list(message.reply_to)
        html = _html_body(message)
        if html:
            payload['html'] = html
        return payload


def email_is_configured():
    """True when mail actually leaves the server (not the console or memory backends)."""
    backend = getattr(settings, 'EMAIL_BACKEND', '')
    if backend.endswith('console.EmailBackend') or backend.endswith('dummy.EmailBackend'):
        return False
    if backend.endswith('locmem.EmailBackend'):
        return True  # the test suite
    if backend == 'config.email_backends.BrevoEmailBackend':
        return bool(getattr(settings, 'BREVO_API_KEY', ''))
    if backend == 'config.email_backends.ResendEmailBackend':
        return bool(getattr(settings, 'RESEND_API_KEY', ''))
    if backend.endswith('smtp.EmailBackend'):
        return bool(getattr(settings, 'EMAIL_HOST_USER', '') and getattr(settings, 'EMAIL_HOST_PASSWORD', ''))
    return True
