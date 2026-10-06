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
    UserProfileSerializer,
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


class MeView(APIView):
    """Returns the currently authenticated user's profile."""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        serializer = UserProfileSerializer(request.user)
        return Response(serializer.data)
