"""
Authentication Views
"""
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView

from .sessions import issue_tokens, revoke_all_sessions, revoke_refresh_token

from .serializers import (
    ChangePasswordSerializer,
    GoogleLoginSerializer,
    PasswordResetConfirmSerializer,
    PasswordResetRequestSerializer,
    PasswordResetVerifySerializer,
    ProfileUpdateSerializer,
    CustomTokenObtainPairSerializer,
    TutorRegistrationSerializer,
    StudentSelfRegistrationSerializer,
    UserProfileSerializer,
    TutorDirectorySerializer,
)


class CustomTokenObtainPairView(TokenObtainPairView):
    """JWT Login endpoint — returns access, refresh tokens + user profile."""
    serializer_class = CustomTokenObtainPairSerializer
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'auth'


class LogoutView(APIView):
    """
    POST /api/v1/auth/logout/   {refresh}
    Signs this device out: the refresh token can no longer be used. Holding
    the token is the proof of identity, so it works even after the access
    token has expired, and signing out twice is not an error.
    """
    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        token = request.data.get('refresh')
        if not token or not isinstance(token, str):
            return Response({'refresh': ['This field is required.']}, status=status.HTTP_400_BAD_REQUEST)
        revoke_refresh_token(token)
        return Response({'message': 'Signed out.'})


class LogoutAllView(APIView):
    """POST /api/v1/auth/logout-all/ — signs the user out on every device."""
    permission_classes = [IsAuthenticated]

    def post(self, request):
        revoke_all_sessions(request.user)
        return Response({'message': 'Signed out on all devices.'})


class TutorRegisterView(generics.CreateAPIView):
    """Tutor self-registration endpoint."""
    serializer_class = TutorRegistrationSerializer
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'auth'

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return Response(
            {
                'message': 'Tutor account created successfully.',
                'user': {
                    'id': str(user.id),
                    'username': user.username,
                    'name': user.get_full_name() or user.username,
                    'role': user.role,
                }
            },
            status=status.HTTP_201_CREATED
        )


class StudentRegisterView(generics.CreateAPIView):
    """Student self-registration endpoint."""
    serializer_class = StudentSelfRegistrationSerializer
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'auth'

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return Response(
            {
                'message': 'Student account created successfully.',
                'user': {
                    'id': str(user.id),
                    'username': user.username,
                    'name': user.get_full_name() or user.username,
                    'role': user.role,
                    'tutor_id': str(user.tutor_id) if user.tutor_id else None,
                }
            },
            status=status.HTTP_201_CREATED
        )


class MeView(APIView):
    """Returns the currently authenticated user's profile."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        serializer = UserProfileSerializer(request.user, context={'request': request})
        return Response(serializer.data)

    def patch(self, request):
        """PATCH /api/v1/auth/me/ — a user edits their own name, contact and (students) school details."""
        serializer = ProfileUpdateSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return Response(UserProfileSerializer(user, context={'request': request}).data)


class ProfilePhotoView(APIView):
    """
    POST   /api/v1/auth/me/photo/   multipart {photo}  — sets the signed-in user's photo
    DELETE /api/v1/auth/me/photo/                       — removes it
    Answers with the same profile as GET /auth/me/. Only PNG, JPEG or WebP
    pictures up to 5 MB whose content really is that picture are kept.
    """
    permission_classes = [IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]
    MAX_BYTES = 5 * 1024 * 1024

    def post(self, request):
        import os
        import uuid

        from PIL import Image, UnidentifiedImageError
        from apps.exams.uploads import UploadRejected, validate_upload

        photo = request.FILES.get('photo')
        try:
            validate_upload(photo)
            ext = os.path.splitext(photo.name or '')[1].lower()
            if ext == '.pdf':
                raise UploadRejected('Choose a picture (PNG, JPEG or WebP).')
            if photo.size > self.MAX_BYTES:
                raise UploadRejected('The picture is larger than 5 MB.')
            try:
                Image.open(photo).verify()
            except (UnidentifiedImageError, OSError, SyntaxError, ValueError) as exc:
                raise UploadRejected('This file is not a picture that can be opened.') from exc
            photo.seek(0)
        except UploadRejected as exc:
            return Response({'photo': [str(exc)]}, status=status.HTTP_400_BAD_REQUEST)

        user = request.user
        old = user.profile_picture.name if user.profile_picture else ''
        user.profile_picture.save(f'{user.pk}-{uuid.uuid4().hex[:8]}{ext}', photo, save=False)
        user.save(update_fields=['profile_picture', 'updated_at'])
        if old and old != user.profile_picture.name:
            user.profile_picture.storage.delete(old)
        return Response(UserProfileSerializer(user, context={'request': request}).data)

    def delete(self, request):
        user = request.user
        if user.profile_picture:
            user.profile_picture.delete(save=False)
            user.profile_picture = None
            user.save(update_fields=['profile_picture', 'updated_at'])
        return Response(UserProfileSerializer(user, context={'request': request}).data)


class ChangePasswordView(APIView):
    """POST /api/v1/auth/change-password/ — needs the current password; clears the forced-change flag."""
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = ChangePasswordSerializer(data=request.data, context={'request': request})
        serializer.is_valid(raise_exception=True)
        user = request.user
        user.set_password(serializer.validated_data['new_password'])
        user.must_change_password = False
        user.save(update_fields=['password', 'must_change_password', 'updated_at'])
        # Every other device is signed out; this one gets a new session to carry on with.
        revoke_all_sessions(user)
        return Response({'message': 'Your password has been changed.', **issue_tokens(user)})


class PasswordResetRequestView(APIView):
    """
    POST /api/v1/auth/password-reset/   {identifier: username or email}
    Emails a 6-digit code (for the app or website) and a one-time link. The
    answer is the same whether or not the account exists, so it cannot be used
    to discover usernames.
    """
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'auth'

    def post(self, request):
        from .password_reset import GENERIC_MESSAGE, request_reset

        serializer = PasswordResetRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        request_reset(serializer.validated_data['identifier'])
        return Response({'message': GENERIC_MESSAGE})


class PasswordResetVerifyView(APIView):
    """
    POST /api/v1/auth/password-reset/verify/   {identifier, code}
    Checks the 6-digit code from the email. A correct code is used up and
    answers {uid, token}, which /password-reset/confirm/ takes with the new
    password. Five wrong guesses end the code.
    """
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'auth'

    def post(self, request):
        from .password_reset import CodeError, link_tokens, redeem_code

        serializer = PasswordResetVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            user = redeem_code(serializer.validated_data['identifier'], serializer.validated_data['code'])
        except CodeError as exc:
            return Response({'message': str(exc), 'code': 'invalid_reset_code'}, status=status.HTTP_400_BAD_REQUEST)
        return Response({'message': 'Code accepted. Choose a new password.', **link_tokens(user), 'username': user.username})


class PasswordResetConfirmView(APIView):
    """POST /api/v1/auth/password-reset/confirm/   {uid, token, new_password}"""
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'auth'

    def post(self, request):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data['user']
        user.set_password(serializer.validated_data['new_password'])
        user.must_change_password = False
        user.save(update_fields=['password', 'must_change_password', 'updated_at'])
        revoke_all_sessions(user)
        return Response({'message': 'Your password has been reset. You can sign in now.', 'username': user.username})


class GoogleLoginView(APIView):
    """
    POST /api/v1/auth/google/   {id_token | credential, role?}
    Signs in with a Google ID token (website button: `credential`; app: `id_token`).
    Answers like /auth/token/: {access, refresh, user, created}.

    With no matching account the answer is 404 with code `google_account_not_found`
    and the Google name and email, so the client can ask "tutor or student?" and
    call again with `role` to create the account.
    """
    permission_classes = [AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'auth'

    def post(self, request):
        from django.contrib.auth.models import update_last_login

        from .google_auth import GoogleAuthError, create_user, find_user, verify_id_token
        from .serializers import login_user_payload

        serializer = GoogleLoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            claims = verify_id_token(serializer.validated_data['token'])
            user = find_user(claims)
            created = False
            if user is None:
                role = serializer.validated_data.get('role')
                if not role:
                    from django.conf import settings
                    return Response({
                        'message': 'No TuitionTrack account uses this Google email yet.',
                        'code': 'google_account_not_found',
                        'email': claims['email'],
                        'name': claims.get('name') or '',
                        'signup_allowed': settings.GOOGLE_SIGNUP_ENABLED,
                    }, status=status.HTTP_404_NOT_FOUND)
                user = create_user(claims, role)
                created = True
        except GoogleAuthError as exc:
            return Response({'message': str(exc), 'code': exc.code, **exc.extra}, status=exc.status)

        update_last_login(None, user)
        return Response(
            {**issue_tokens(user), 'user': login_user_payload(user, request), 'created': created},
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


class TutorDirectoryView(generics.ListAPIView):
    """
    Public directory of tutors for prospective students during registration.
    Allows searching by tutor name, username, or tuition subjects/titles.
    """
    permission_classes = [AllowAny]
    serializer_class = TutorDirectorySerializer

    def get_queryset(self):
        from django.db.models import Q
        from django.contrib.auth import get_user_model
        User = get_user_model()

        qs = User.objects.filter(role=User.Role.TUTOR, is_active=True).prefetch_related('tuitions')
        search = self.request.query_params.get('search', '').strip()
        if search:
            qs = qs.filter(
                Q(first_name__icontains=search) |
                Q(last_name__icontains=search) |
                Q(username__icontains=search) |
                Q(tuitions__title__icontains=search) |
                Q(tuitions__subject__icontains=search)
            ).distinct()
        return qs.order_by('first_name', 'last_name')
