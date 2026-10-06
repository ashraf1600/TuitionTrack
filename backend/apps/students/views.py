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
from rest_framework import generics, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated
from django.contrib.auth import get_user_model
from django.db.models import Q
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

        from apps.students.models import TuitionEnrollment
        from apps.cycles.models import AttendanceCycle
        TuitionEnrollment.objects.filter(student=student).update(is_active=False)
        AttendanceCycle.objects.filter(enrollment__student=student, status=AttendanceCycle.Status.ACTIVE).update(
            status=AttendanceCycle.Status.ARCHIVED
        )

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

        from apps.students.models import TuitionEnrollment
        from apps.cycles.models import AttendanceCycle
        if not student.is_active:
            TuitionEnrollment.objects.filter(student=student).update(is_active=False)
            AttendanceCycle.objects.filter(enrollment__student=student, status=AttendanceCycle.Status.ACTIVE).update(
                status=AttendanceCycle.Status.ARCHIVED
            )
        else:
            TuitionEnrollment.objects.filter(student=student).update(is_active=True)

        action_taken = 'activated' if student.is_active else 'deactivated'
        return Response(
            {
                'message': f'Student "{student.get_full_name() or student.username}" has been {action_taken}.',
                'is_active': student.is_active,
            },
            status=status.HTTP_200_OK
        )


class TuitionBatchViewSet(generics.ListCreateAPIView, viewsets.GenericViewSet):
    """
    ViewSet for TuitionBatches (Tuitions).
    - Tutors can create, list, view, update, and manage student enrollments.
    - Students can list batches they are enrolled in and view weekly routines.
    """
    from apps.authentication.permissions import IsTutorOrStudent, IsTutor
    permission_classes = [IsAuthenticated, IsTutorOrStudent]

    def get_permissions(self):
        if self.action in ['create', 'update', 'partial_update', 'destroy', 'add_student', 'remove_student']:
            return [IsAuthenticated(), IsTutor()]
        return [IsAuthenticated(), IsTutorOrStudent()]

    def get_queryset(self):
        from .models import TuitionBatch
        user = self.request.user
        if user.role == 'TUTOR':
            return TuitionBatch.objects.filter(tutor=user).prefetch_related('students')
        elif user.role == 'STUDENT':
            return TuitionBatch.objects.filter(students=user, is_active=True).prefetch_related('students')
        return TuitionBatch.objects.none()

    def get_serializer_class(self):
        from .serializers import TuitionBatchSerializer, TuitionBatchCreateUpdateSerializer
        if self.request.method in ['POST', 'PUT', 'PATCH']:
            return TuitionBatchCreateUpdateSerializer
        return TuitionBatchSerializer

    def create(self, request, *args, **kwargs):
        if request.user.role != 'TUTOR':
            return Response({'error': 'Only tutors can create batches.'}, status=status.HTTP_403_FORBIDDEN)
        return super().create(request, *args, **kwargs)

    def retrieve(self, request, pk=None):
        from .serializers import TuitionBatchSerializer
        batch = get_object_or_404(self.get_queryset(), pk=pk)
        return Response(TuitionBatchSerializer(batch).data)

    def partial_update(self, request, pk=None):
        from .serializers import TuitionBatchSerializer, TuitionBatchCreateUpdateSerializer
        batch = get_object_or_404(self.get_queryset(), pk=pk)
        if request.user.role != 'TUTOR':
            return Response({'error': 'Only tutors can edit batches.'}, status=status.HTTP_403_FORBIDDEN)
        serializer = TuitionBatchCreateUpdateSerializer(batch, data=request.data, partial=True, context={'request': request})
        serializer.is_valid(raise_exception=True)
        updated_batch = serializer.save()
        return Response(TuitionBatchSerializer(updated_batch).data)

    def destroy(self, request, pk=None):
        batch = get_object_or_404(self.get_queryset(), pk=pk)
        if request.user.role != 'TUTOR':
            return Response({'error': 'Only tutors can delete batches.'}, status=status.HTTP_403_FORBIDDEN)
        batch.delete()
        return Response({'message': 'Tuition batch deleted.'}, status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsTutor])
    def add_student(self, request, pk=None):
        from .serializers import TuitionBatchSerializer
        batch = get_object_or_404(self.get_queryset(), pk=pk)
        student_id = request.data.get('student_id')
        student = get_object_or_404(User, id=student_id, role=User.Role.STUDENT, tutor=request.user)
        batch.students.add(student)
        return Response({
            'message': f'Student "{student.get_full_name() or student.username}" added to batch.',
            'batch': TuitionBatchSerializer(batch).data
        })

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsTutor])
    def remove_student(self, request, pk=None):
        from .serializers import TuitionBatchSerializer
        batch = get_object_or_404(self.get_queryset(), pk=pk)
        student_id = request.data.get('student_id')
        student = get_object_or_404(User, id=student_id, role=User.Role.STUDENT, tutor=request.user)
        batch.students.remove(student)
        return Response({
            'message': f'Student "{student.get_full_name() or student.username}" removed from batch.',
            'batch': TuitionBatchSerializer(batch).data
        })


# ── Tuition-Centric ViewSet & Unassigned Students ────────────────────────

class TuitionViewSet(viewsets.ModelViewSet):
    """
    ViewSet for Tuition-Centric domain model.
    Tutors can create, list, update, and delete tuitions.
    Students can list all tuitions they are enrolled in.
    """
    from apps.authentication.permissions import IsTutorOrStudent, IsTutor
    permission_classes = [IsAuthenticated, IsTutorOrStudent]
    http_method_names = ['get', 'post', 'patch', 'delete', 'head', 'options']

    def get_permissions(self):
        if self.action in ['create', 'update', 'partial_update', 'destroy', 'enroll', 'unenroll']:
            return [IsAuthenticated(), IsTutor()]
        return [IsAuthenticated(), IsTutorOrStudent()]

    def get_queryset(self):
        from .models import Tuition
        user = self.request.user
        if user.role == 'TUTOR':
            return Tuition.objects.filter(tutor=user).prefetch_related('enrollments__student', 'enrollments__cycles')
        elif user.role == 'STUDENT':
            return Tuition.objects.filter(enrollments__student=user).distinct().prefetch_related('enrollments__student', 'enrollments__cycles')
        return Tuition.objects.none()

    def get_serializer_class(self):
        from .serializers import TuitionSerializer, TuitionCreateUpdateSerializer
        if self.action in ['create', 'partial_update', 'update']:
            return TuitionCreateUpdateSerializer
        return TuitionSerializer

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context['request'] = self.request
        return context

    def _scoped_student_or_404(self, student_id):
        """Only students owned by this tutor, or orphans who selected this tutor."""
        return get_object_or_404(
            User.objects.filter(
                Q(tutor=self.request.user)
                | Q(tutor__isnull=True, selected_tutor=self.request.user)
            ),
            id=student_id,
            role=User.Role.STUDENT,
        )

    def create(self, request, *args, **kwargs):
        if request.user.role != 'TUTOR':
            return Response({'error': 'Only tutors can create tuitions.'}, status=status.HTTP_403_FORBIDDEN)
        return super().create(request, *args, **kwargs)

    def update(self, request, *args, **kwargs):
        if request.user.role != 'TUTOR':
            return Response({'error': 'Only tutors can edit tuitions.'}, status=status.HTTP_403_FORBIDDEN)
        return super().update(request, *args, **kwargs)

    def partial_update(self, request, *args, **kwargs):
        if request.user.role != 'TUTOR':
            return Response({'error': 'Only tutors can edit tuitions.'}, status=status.HTTP_403_FORBIDDEN)
        return super().partial_update(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        if request.user.role != 'TUTOR':
            return Response({'error': 'Only tutors can delete tuitions.'}, status=status.HTTP_403_FORBIDDEN)
        return super().destroy(request, *args, **kwargs)

    def perform_create(self, serializer):
        if self.request.user.role != 'TUTOR':
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied('Only tutors can create tuitions.')
        serializer.save(tutor=self.request.user)

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsTutor])
    def enroll(self, request, pk=None):
        """
        POST /api/v1/tuitions/<id>/enroll/
        Enrolls a student (e.g. from the unassigned list or existing roster)
        and initializes active AttendanceCycle #1.
        """
        from .models import TuitionEnrollment
        from .serializers import TuitionSerializer
        from apps.cycles.models import AttendanceCycle

        tuition = self.get_object()
        student_id = request.data.get('student_id')
        student = self._scoped_student_or_404(student_id)

        enrollment, created = TuitionEnrollment.objects.get_or_create(
            tuition=tuition,
            student=student
        )
        if not enrollment.is_active:
            enrollment.is_active = True
            enrollment.save(update_fields=['is_active'])

        # Max cycle_number across ALL cycles (active+archived) avoids duplicate #1
        from django.db.models import Max
        max_no = AttendanceCycle.objects.filter(enrollment=enrollment).aggregate(
            m=Max('cycle_number'))['m'] or 0
        cycle, cycle_created = AttendanceCycle.objects.get_or_create(
            enrollment=enrollment,
            status=AttendanceCycle.Status.ACTIVE,
            defaults={
                'tutor': request.user,
                'fee_snapshot': tuition.tuition_fee,
                'total_classes': tuition.cycle_length,
                'cycle_number': max_no + 1,
                'classes_data': AttendanceCycle.build_fresh_classes_data(tuition.cycle_length),
            }
        )

        return Response({
            'message': f'Student "{student.get_full_name() or student.username}" enrolled into {tuition.title}.',
            'tuition': TuitionSerializer(tuition, context={'request': request}).data
        }, status=status.HTTP_200_OK)

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsTutor])
    def unenroll(self, request, pk=None):
        """
        POST /api/v1/tuitions/<id>/unenroll/
        Removes student enrollment from this tuition while preserving historical cycle ledger.
        """
        from .serializers import TuitionSerializer
        from apps.cycles.models import AttendanceCycle
        tuition = self.get_object()
        student_id = request.data.get('student_id')
        student = self._scoped_student_or_404(student_id)

        enrollment = tuition.enrollments.filter(student=student).first()
        if not enrollment:
            return Response({'error': 'Student is not enrolled in this tuition.'}, status=status.HTTP_404_NOT_FOUND)

        enrollment.is_active = False
        enrollment.save(update_fields=['is_active'])
        AttendanceCycle.objects.filter(enrollment=enrollment, status=AttendanceCycle.Status.ACTIVE).update(
            status=AttendanceCycle.Status.ARCHIVED
        )

        return Response({
            'message': f'Student "{student.get_full_name() or student.username}" removed from {tuition.title}.',
            'tuition': TuitionSerializer(tuition, context={'request': request}).data
        }, status=status.HTTP_200_OK)


class UnassignedStudentsView(APIView):
    """
    GET /api/v1/students/unassigned/
    Returns prospective students who selected this tutor during self-registration
    and are not yet enrolled in any of this tutor's tuitions.
    """
    permission_classes = [IsAuthenticated, IsTutor]

    def get(self, request):
        from .models import TuitionEnrollment
        tutor = request.user

        from django.db.models import Q
        # Prospective or created students under this tutor (active only)
        prospective = User.objects.filter(
            role=User.Role.STUDENT,
            is_active=True,
        ).filter(
            Q(selected_tutor=tutor) | Q(tutor=tutor)
        ).select_related('student_profile')

        # Check which students are not enrolled in any of this tutor's tuitions
        enrolled_ids = TuitionEnrollment.objects.filter(
            tuition__tutor=tutor
        ).values_list('student_id', flat=True)

        unassigned = prospective.exclude(id__in=enrolled_ids).order_by('-created_at')

        results = []
        for s in unassigned:
            prof = getattr(s, 'student_profile', None)
            results.append({
                'id': str(s.id),
                'username': s.username,
                'full_name': s.get_full_name() or s.username,
                'email': s.email,
                'phone': s.phone,
                'grade_level': prof.grade_level if prof else '',
                'institution': prof.institution if prof else '',
                'parent_name': prof.parent_name if prof else '',
                'parent_phone': prof.parent_phone if prof else '',
                'created_at': s.created_at,
            })

        return Response(results, status=status.HTTP_200_OK)

