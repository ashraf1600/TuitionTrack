"""
Students App Views

Endpoints:
  GET    /api/v1/students/           — Tutor lists all their students
  POST   /api/v1/students/           — Tutor creates student (User + Profile + Cycle#1)
  GET    /api/v1/students/<id>/      — Tutor views student detail
  PATCH  /api/v1/students/<id>/      — Tutor updates student info / profile
  DELETE /api/v1/students/<id>/      — Tutor deactivates student (soft delete)
  POST   /api/v1/students/<id>/toggle_active/ — Reactivate/deactivate student
"""
from rest_framework import generics, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated
from django.contrib.auth import get_user_model
from django.shortcuts import get_object_or_404

from apps.authentication.permissions import IsTutor
from .serializers import (
    StudentCreateSerializer,
    StudentListSerializer,
    StudentDetailSerializer,
)

User = get_user_model()


class StudentListCreateView(generics.ListCreateAPIView):
    """
    GET  /api/v1/students/ — Returns all students belonging to the logged-in tutor.
    POST /api/v1/students/ — Atomically creates User + StudentProfile + Cycle #1.
    """
    permission_classes = [IsAuthenticated, IsTutor]

    def get_queryset(self):
        """Tutor only sees their own students."""
        return User.objects.filter(
            role='STUDENT',
            tutor=self.request.user
        ).select_related('student_profile').order_by('first_name', 'last_name')

    def get_serializer_class(self):
        if self.request.method == 'POST':
            return StudentCreateSerializer
        return StudentListSerializer

    def create(self, request, *args, **kwargs):
        serializer = StudentCreateSerializer(
            data=request.data,
            context={'request': request}
        )
        serializer.is_valid(raise_exception=True)
        student_user = serializer.save()

        # Return the created student in list format
        response_serializer = StudentDetailSerializer(student_user)
        return Response(
            {
                'message': 'Student created successfully. Cycle #1 has been initialized.',
                'student': response_serializer.data,
            },
            status=status.HTTP_201_CREATED
        )


class StudentDetailView(generics.RetrieveUpdateDestroyAPIView):
    """
    GET    /api/v1/students/<id>/ — View student detail.
    PATCH  /api/v1/students/<id>/ — Update student user + profile.
    DELETE /api/v1/students/<id>/ — Soft-delete (deactivate) the student.
    """
    permission_classes = [IsAuthenticated, IsTutor]
    serializer_class = StudentDetailSerializer
    http_method_names = ['get', 'patch', 'delete', 'head', 'options']

    def get_queryset(self):
        return User.objects.filter(
            role='STUDENT',
            tutor=self.request.user
        ).select_related('student_profile')

    def destroy(self, request, *args, **kwargs):
        """
        Soft delete — deactivates the student account instead of hard deleting.
        This preserves all historical cycle and exam data.
        """
        student = self.get_object()
        student.is_active = False
        student.save(update_fields=['is_active'])
        return Response(
            {'message': f'Student "{student.get_full_name() or student.username}" has been deactivated.'},
            status=status.HTTP_200_OK
        )


class StudentToggleActiveView(APIView):
    """
    POST /api/v1/students/<id>/toggle_active/
    Re-activates or deactivates a student account.
    """
    permission_classes = [IsAuthenticated, IsTutor]

    def post(self, request, pk):
        student = get_object_or_404(
            User,
            id=pk,
            role='STUDENT',
            tutor=request.user
        )
        student.is_active = not student.is_active
        student.save(update_fields=['is_active'])

        action_taken = 'activated' if student.is_active else 'deactivated'
        return Response(
            {
                'message': f'Student "{student.get_full_name() or student.username}" has been {action_taken}.',
                'is_active': student.is_active,
            },
            status=status.HTTP_200_OK
        )
