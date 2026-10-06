"""
Authentication Views
"""
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView

from .serializers import (
    ChangePasswordSerializer,
    PasswordResetConfirmSerializer,
    PasswordResetRequestSerializer,
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


class TutorRegisterView(generics.CreateAPIView):
    """Tutor self-registration endpoint."""
    serializer_class = TutorRegistrationSerializer
    permission_classes = [AllowAny]

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
        serializer = UserProfileSerializer(request.user)
        return Response(serializer.data)

    def patch(self, request):
        """PATCH /api/v1/auth/me/ — a user edits their own name, contact and (students) school details."""
        serializer = ProfileUpdateSerializer(request.user, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return Response(UserProfileSerializer(user).data)


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
        return Response({'message': 'Your password has been changed.'})


class PasswordResetRequestView(APIView):
    """
    POST /api/v1/auth/password-reset/   {identifier: username or email}
    Emails a one-time reset link. The answer is the same whether or not the
    account exists, so it cannot be used to discover usernames.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        from django.conf import settings
        from django.contrib.auth import get_user_model
        from django.contrib.auth.tokens import default_token_generator
        from django.core.mail import send_mail
        from django.db.models import Q
        from django.utils.encoding import force_bytes
        from django.utils.http import urlsafe_base64_encode

        serializer = PasswordResetRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        identifier = serializer.validated_data['identifier'].strip()

        User = get_user_model()
        users = User.objects.filter(is_active=True).filter(
            Q(username__iexact=identifier) | Q(email__iexact=identifier)
        ).exclude(email='')[:3]

        for user in users:
            uid = urlsafe_base64_encode(force_bytes(user.pk))
            token = default_token_generator.make_token(user)
            link = f"{settings.FRONTEND_URL.rstrip('/')}/reset-password?uid={uid}&token={token}"
            send_mail(
                subject='[TuitionTrack] Reset your password',
                message=(
                    f'Hello {user.get_full_name() or user.username},\n\n'
                    f'Use this link to choose a new password for your TuitionTrack account '
                    f'(username: {user.username}):\n\n{link}\n\n'
                    f'If you did not ask for this, you can ignore this email.'
                ),
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[user.email],
                fail_silently=True,
            )

        return Response({
            'message': 'If that account has an email address, a reset link has been sent to it. '
                       'Students without an email can ask their tutor to reset the password.'
        })


class PasswordResetConfirmView(APIView):
    """POST /api/v1/auth/password-reset/confirm/   {uid, token, new_password}"""
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data['user']
        user.set_password(serializer.validated_data['new_password'])
        user.must_change_password = False
        user.save(update_fields=['password', 'must_change_password', 'updated_at'])
        return Response({'message': 'Your password has been reset. You can sign in now.'})


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
                Q(tuitions__title__icontains=search)
            ).distinct()
        return qs.order_by('first_name', 'last_name')
