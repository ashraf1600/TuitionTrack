"""
Authentication Views
"""
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView

from .serializers import (
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
