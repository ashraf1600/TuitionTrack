"""
Sign-in sessions.

A session is a refresh token. These helpers issue one, revoke one (sign out)
and revoke all of a user's (password change, reset, deactivation), and resolve
what a person typed on the sign-in screen to an account.
"""
from django.contrib.auth import get_user_model
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.token_blacklist.models import BlacklistedToken, OutstandingToken
from rest_framework_simplejwt.tokens import RefreshToken

User = get_user_model()


def issue_tokens(user):
    """A fresh access/refresh pair carrying the same claims as a normal sign-in."""
    from .serializers import CustomTokenObtainPairSerializer
    refresh = CustomTokenObtainPairSerializer.get_token(user)
    return {'access': str(refresh.access_token), 'refresh': str(refresh)}


def revoke_refresh_token(raw_token):
    """Sign one device out. Returns False when the token was already unusable."""
    try:
        RefreshToken(raw_token).blacklist()
        return True
    except (TokenError, TypeError, ValueError):
        return False


def revoke_all_sessions(user):
    """Sign the user out everywhere: every refresh token issued so far stops working."""
    for token in OutstandingToken.objects.filter(user=user, blacklistedtoken__isnull=True):
        BlacklistedToken.objects.get_or_create(token=token)


def resolve_login_name(identifier):
    """
    Turn what was typed into a username. Phone keyboards capitalise the first
    letter, and people often type their email instead, so an exact match is
    tried first, then a case-insensitive one, then an email address — each
    only when it points at exactly one account.
    """
    typed = (identifier or '').strip()
    if not typed or User.objects.filter(username=typed).exists():
        return typed
    matches = list(User.objects.filter(username__iexact=typed).values_list('username', flat=True)[:2])
    if len(matches) == 1:
        return matches[0]
    if '@' in typed:
        matches = list(User.objects.filter(email__iexact=typed, is_active=True).values_list('username', flat=True)[:2])
        if len(matches) == 1:
            return matches[0]
    return typed
