"""
Students App Views

Tuition groups:
  GET/POST   /api/v1/tuitions/                       — List / create tuition groups
  GET/PATCH/DELETE /api/v1/tuitions/<id>/            — Detail / edit / delete
  POST   /api/v1/tuitions/<id>/enroll/               — Add one or many students to the group
  POST   /api/v1/tuitions/<id>/unenroll/             — Remove a student from the group
  PATCH  /api/v1/tuitions/<id>/mark_class/           — Mark a class done for the whole group

Connection requests (student asks to join a tutor):
  GET/POST   /api/v1/connections/                    — Student: my requests / send one. Tutor: inbox
  POST   /api/v1/connections/<id>/accept/            — Tutor accepts (optionally straight into a tuition)
  POST   /api/v1/connections/<id>/reject/            — Tutor declines
  DELETE /api/v1/connections/<id>/                   — Student withdraws a pending request

Students:
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
from django.utils import timezone

from apps.authentication.permissions import IsTutor, IsTutorOrStudent
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
        """Tutor only sees their own students or prospective students who chose them."""
        from .services import manageable_students
        return manageable_students(self.request.user).select_related(
            'student_profile'
        ).order_by('first_name', 'last_name')

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

        # Return the created student in list format with tutor-scoped initial_password
        response_serializer = StudentDetailSerializer(student_user, context={'request': request})
        return Response(
            {
                'message': 'Student created successfully.',
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
        from apps.authentication.sessions import revoke_all_sessions
        student = self.get_object()
        student.is_active = False
        student.save(update_fields=['is_active'])
        revoke_all_sessions(student)

        # The shared cycle belongs to the tuition group, so it carries on without them.
        from apps.students.models import TuitionEnrollment
        TuitionEnrollment.objects.filter(student=student, tuition__tutor=request.user).update(is_active=False)

        return Response(
            {'message': f'Student "{student.get_full_name() or student.username}" has been deactivated.'},
            status=status.HTTP_200_OK
        )


class StudentResetPasswordView(APIView):
    """
    POST /api/v1/students/<id>/reset_password/
    For a student who is locked out: sets a new temporary password and returns
    it ONCE in this response (it is not stored anywhere readable). The student
    must choose their own password the next time they sign in.
    """
    permission_classes = [IsAuthenticated, IsTutor]

    def post(self, request, pk):
        import secrets
        student = get_object_or_404(User, id=pk, role='STUDENT', tutor=request.user)
        alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
        temporary = ''.join(secrets.choice(alphabet) for _ in range(10))
        student.set_password(temporary)
        student.must_change_password = True
        student.save(update_fields=['password', 'must_change_password', 'updated_at'])
        # Whoever was signed in with the old password is signed out.
        from apps.authentication.sessions import revoke_all_sessions
        revoke_all_sessions(student)
        return Response({
            'message': f'New temporary password set for {student.get_full_name() or student.username}.',
            'username': student.username,
            'temporary_password': temporary,
        })


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
        if not student.is_active:
            from apps.authentication.sessions import revoke_all_sessions
            revoke_all_sessions(student)

        from apps.students.models import TuitionEnrollment
        TuitionEnrollment.objects.filter(
            student=student, tuition__tutor=request.user, left_at__isnull=True
        ).update(is_active=student.is_active)

        action_taken = 'activated' if student.is_active else 'deactivated'
        return Response(
            {
                'message': f'Student "{student.get_full_name() or student.username}" has been {action_taken}.',
                'is_active': student.is_active,
            },
            status=status.HTTP_200_OK
        )



# ── Tuition Groups ───────────────────────────────────────────────────────

class TuitionViewSet(viewsets.ModelViewSet):
    """
    Tuition groups (batches).

    Tutors create and manage their groups, the roster, and the shared cycle.
    Students get a read-only view of the groups they are enrolled in, through
    StudentTuitionSerializer — which has no fee or wallet fields.
    """
    permission_classes = [IsAuthenticated, IsTutorOrStudent]
    http_method_names = ['get', 'post', 'patch', 'delete', 'head', 'options']

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated(), IsTutorOrStudent()]
        return [IsAuthenticated(), IsTutor()]

    def get_queryset(self):
        from .models import Tuition
        user = self.request.user
        qs = Tuition.objects.select_related('tutor').prefetch_related('cycles')
        if user.role == 'TUTOR':
            return qs.filter(tutor=user)
        if user.role == 'STUDENT':
            return qs.filter(enrollments__student=user, enrollments__is_active=True).distinct()
        return Tuition.objects.none()

    def get_serializer_class(self):
        from .serializers import TuitionSerializer, StudentTuitionSerializer, TuitionCreateUpdateSerializer
        if self.action in ('create', 'partial_update', 'update'):
            return TuitionCreateUpdateSerializer
        if getattr(self.request.user, 'role', None) == 'TUTOR':
            return TuitionSerializer
        return StudentTuitionSerializer

    def _detail(self, tuition):
        from .serializers import TuitionSerializer
        return TuitionSerializer(tuition, context=self.get_serializer_context()).data

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        tuition = serializer.save(tutor=request.user)
        return Response(self._detail(tuition), status=status.HTTP_201_CREATED)

    def partial_update(self, request, *args, **kwargs):
        tuition = self.get_object()
        serializer = self.get_serializer(tuition, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        tuition = serializer.save()
        return Response(self._detail(tuition))

    def perform_destroy(self, instance):
        """
        Deleting a group removes its roster and exams, but what it already
        earned is history: the current cycle is archived, not deleted, and stays
        in the tutor's lifetime earnings.
        """
        from django.db import transaction
        from apps.cycles.models import AttendanceCycle
        with transaction.atomic():
            AttendanceCycle.objects.filter(
                tuition=instance, status=AttendanceCycle.Status.ACTIVE
            ).update(status=AttendanceCycle.Status.ARCHIVED)
            instance.delete()

    def _students_from_request(self, request):
        """Accepts {student_id} or {student_ids: [...]}; all must be this tutor's students."""
        import uuid
        from rest_framework.exceptions import PermissionDenied, ValidationError
        from .services import manageable_students

        raw = request.data.get('student_ids')
        if raw is None:
            raw = [request.data.get('student_id')]
        if not isinstance(raw, (list, tuple)) or not raw or not all(raw):
            raise ValidationError({'student_id': 'student_id is required.'})
        try:
            ids = {uuid.UUID(str(value)) for value in raw}
        except (ValueError, TypeError, AttributeError):
            raise ValidationError({'student_id': 'Invalid student id.'})

        existing = User.objects.filter(id__in=ids, role=User.Role.STUDENT)
        if existing.count() != len(ids):
            raise ValidationError({'student_id': 'Student does not exist.'})
        students = list(manageable_students(request.user).filter(id__in=ids))
        if len(students) != len(ids):
            raise PermissionDenied('Unauthorized: Student belongs to another tutor.')
        return students

    @action(detail=True, methods=['post'])
    def enroll(self, request, pk=None):
        """
        POST /api/v1/tuitions/<id>/enroll/   {student_id} or {student_ids: [...]}
        Adds students to the group. They join the group's current shared cycle;
        any pending connection request from them is accepted.
        """
        from django.db import transaction
        from .services import enroll_student

        tuition = self.get_object()
        students = self._students_from_request(request)
        with transaction.atomic():
            for student in students:
                enroll_student(tuition, student)

        names = ', '.join(s.get_full_name() or s.username for s in students)
        return Response({
            'message': f'Enrolled into {tuition.title}: {names}.',
            'tuition': self._detail(tuition),
        }, status=status.HTTP_200_OK)

    @action(detail=True, methods=['post'])
    def unenroll(self, request, pk=None):
        """
        POST /api/v1/tuitions/<id>/unenroll/   {student_id}
        Removes a student from the group. The shared cycle and its earnings stay.
        """
        from .services import unenroll_student

        tuition = self.get_object()
        student = self._students_from_request(request)[0]
        if not tuition.enrollments.filter(student=student).exists():
            return Response({'error': 'Student is not enrolled in this tuition.'}, status=status.HTTP_404_NOT_FOUND)
        unenroll_student(tuition, student)

        return Response({
            'message': f'Student "{student.get_full_name() or student.username}" removed from {tuition.title}.',
            'tuition': self._detail(tuition),
        }, status=status.HTTP_200_OK)

    @action(detail=True, methods=['post'])
    def add_student(self, request, pk=None):
        return self.enroll(request, pk)

    @action(detail=True, methods=['post'])
    def remove_student(self, request, pk=None):
        return self.unenroll(request, pk)

    @action(detail=True, methods=['patch', 'post'])
    def mark_class(self, request, pk=None):
        """
        PATCH /api/v1/tuitions/<id>/mark_class/   {class_no, completed, date?, topic?}
        Marks a class of the group's current cycle. One call updates the
        dashboard of every enrolled student, and the tutor's Tuition Wallet:
        earned = (total_fee / cycle_length) * completed_classes.
        """
        from apps.cycles.models import AttendanceCycle
        from apps.cycles.serializers import ToggleClassSerializer
        from apps.cycles.views import toggle_shared_class

        tuition = self.get_object()
        serializer = ToggleClassSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        cycle = AttendanceCycle.ensure_active(tuition)
        cycle, error = toggle_shared_class(cycle.id, serializer.validated_data)
        if error:
            return Response({'error': error}, status=status.HTTP_400_BAD_REQUEST)

        detail = self._detail(tuition)
        return Response({
            'message': f'Class #{serializer.validated_data["resolved_class_no"]} updated for the whole group.',
            'cycle': detail['active_cycle'],
            'wallet_summary': detail['wallet_summary'],
        }, status=status.HTTP_200_OK)


# Unified alias for backwards compatibility
TuitionBatchViewSet = TuitionViewSet


# ── Connection Requests ──────────────────────────────────────────────────

class ConnectionRequestViewSet(viewsets.GenericViewSet):
    """
    Student -> tutor connection requests.

    A student sends a request to a tutor they found in the directory. It shows
    up in that tutor's inbox as PENDING until the tutor accepts it (optionally
    placing the student straight into a tuition) or rejects it.
    """
    permission_classes = [IsAuthenticated, IsTutorOrStudent]

    def get_serializer_class(self):
        from .serializers import ConnectionRequestSerializer
        return ConnectionRequestSerializer

    def get_queryset(self):
        from .models import ConnectionRequest
        user = self.request.user
        qs = ConnectionRequest.objects.select_related('student', 'student__student_profile', 'tutor')
        if user.role == 'TUTOR':
            qs = qs.filter(tutor=user, student__is_active=True)
        elif user.role == 'STUDENT':
            qs = qs.filter(student=user)
        else:
            return qs.none()
        status_param = (self.request.query_params.get('status') or '').upper()
        if status_param:
            if status_param not in ConnectionRequest.Status.values:
                return qs.none()
            qs = qs.filter(status=status_param)
        return qs

    def list(self, request):
        serializer = self.get_serializer(self.get_queryset(), many=True)
        return Response(serializer.data)

    def create(self, request):
        """Student sends (or re-sends after a rejection) a request to a tutor."""
        from .models import ConnectionRequest
        from .serializers import ConnectionRequestCreateSerializer
        if request.user.role != 'STUDENT':
            return Response({'error': 'Only students can send connection requests.'}, status=status.HTTP_403_FORBIDDEN)

        payload = ConnectionRequestCreateSerializer(data=request.data)
        payload.is_valid(raise_exception=True)
        tutor = payload.validated_data['tutor']
        message = payload.validated_data.get('message', '')

        connection, created = ConnectionRequest.objects.get_or_create(
            student=request.user, tutor=tutor, defaults={'message': message}
        )
        if not created:
            if connection.status == ConnectionRequest.Status.ACCEPTED:
                return Response({'error': 'You are already connected to this tutor.'}, status=status.HTTP_400_BAD_REQUEST)
            if connection.status == ConnectionRequest.Status.PENDING:
                return Response({'error': 'Your request to this tutor is already pending.'}, status=status.HTTP_400_BAD_REQUEST)
            connection.status = ConnectionRequest.Status.PENDING
            connection.message = message
            connection.responded_at = None
            connection.save(update_fields=['status', 'message', 'responded_at'])

        return Response(self.get_serializer(connection).data, status=status.HTTP_201_CREATED)

    def destroy(self, request, pk=None):
        """Student withdraws a request that has not been answered yet."""
        from .models import ConnectionRequest
        connection = get_object_or_404(self.get_queryset(), pk=pk)
        if request.user.role != 'STUDENT':
            return Response({'error': 'Use reject to decline a request.'}, status=status.HTTP_403_FORBIDDEN)
        if connection.status != ConnectionRequest.Status.PENDING:
            return Response({'error': 'Only pending requests can be withdrawn.'}, status=status.HTTP_400_BAD_REQUEST)
        connection.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsTutor])
    def accept(self, request, pk=None):
        """
        POST /api/v1/connections/<id>/accept/   {tuition_id?}
        Accepts the student. With tuition_id they are enrolled in that group
        in the same step; without it they wait in the tutor's unassigned list.
        """
        from django.db import transaction
        from .models import ConnectionRequest, Tuition
        from .services import accept_connection, enroll_student

        connection = get_object_or_404(self.get_queryset(), pk=pk)
        if connection.status == ConnectionRequest.Status.REJECTED:
            return Response({'error': 'This request was already rejected.'}, status=status.HTTP_400_BAD_REQUEST)

        tuition = None
        tuition_id = request.data.get('tuition_id')
        if tuition_id:
            try:
                tuition = Tuition.objects.filter(id=tuition_id, tutor=request.user).first()
            except (ValueError, TypeError, Exception):
                tuition = None
            if not tuition:
                return Response({'tuition_id': ['Selected tuition does not exist.']}, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            accept_connection(request.user, connection.student)
            if tuition:
                enroll_student(tuition, connection.student)
        connection.refresh_from_db()

        name = connection.student.get_full_name() or connection.student.username
        return Response({
            'message': f'{name} accepted' + (f' and added to {tuition.title}.' if tuition else '.'),
            'connection': self.get_serializer(connection).data,
        })

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsTutor])
    def reject(self, request, pk=None):
        """POST /api/v1/connections/<id>/reject/ — decline a pending request."""
        from .models import ConnectionRequest
        connection = get_object_or_404(self.get_queryset(), pk=pk)
        if connection.status != ConnectionRequest.Status.PENDING:
            return Response({'error': 'Only pending requests can be rejected.'}, status=status.HTTP_400_BAD_REQUEST)
        connection.status = ConnectionRequest.Status.REJECTED
        connection.responded_at = timezone.now()
        connection.save(update_fields=['status', 'responded_at'])
        return Response({
            'message': 'Request rejected.',
            'connection': self.get_serializer(connection).data,
        })


class UnassignedStudentsView(APIView):
    """
    GET /api/v1/students/unassigned/
    The tutor's "to place" list: students who requested this tutor (pending or
    accepted) or were created by them, and are not in any of their tuitions yet.
    """
    permission_classes = [IsAuthenticated, IsTutor]

    def get(self, request):
        from .models import ConnectionRequest, TuitionEnrollment
        from .services import manageable_students
        tutor = request.user

        enrolled_ids = TuitionEnrollment.objects.filter(
            tuition__tutor=tutor, is_active=True
        ).values_list('student_id', flat=True)

        unassigned = manageable_students(tutor).filter(is_active=True).exclude(
            id__in=enrolled_ids
        ).select_related('student_profile').order_by('-created_at')

        requests_by_student = {
            c.student_id: c for c in ConnectionRequest.objects.filter(tutor=tutor, student__in=unassigned)
        }

        results = []
        for s in unassigned:
            prof = getattr(s, 'student_profile', None)
            connection = requests_by_student.get(s.id)
            results.append({
                'id': str(s.id),
                'student_id': str(s.id),
                'username': s.username,
                'full_name': s.get_full_name() or s.username,
                'email': s.email,
                'phone': s.phone,
                'grade_level': prof.grade_level if prof else '',
                'institution': prof.institution if prof else '',
                'address': prof.address if prof else '',
                'parent_name': prof.parent_name if prof else '',
                'parent_phone': prof.parent_phone if prof else '',
                'request_id': str(connection.id) if connection else None,
                'request_status': connection.status if connection else None,
                'message': connection.message if connection else '',
                'created_at': connection.created_at if connection else s.created_at,
            })

        return Response(results, status=status.HTTP_200_OK)


# ── Tutor Code Connection View ────────────────────────────────────────────

class TutorCodeConnectView(APIView):
    """
    POST /api/v1/connections/by-code/
    Student sends a connection request using the tutor's 6-char invite code.

    Request body: {tutor_code: "A3B7XZ", message?: "..."}
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        from .models import ConnectionRequest
        from .serializers import TutorCodeConnectionSerializer, ConnectionRequestSerializer

        if request.user.role != "STUDENT":
            return Response(
                {"error": "Only students can use invite codes."},
                status=status.HTTP_403_FORBIDDEN,
            )

        serializer = TutorCodeConnectionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        tutor = serializer.validated_data["tutor"]
        message = serializer.validated_data.get("message", "")

        connection, created = ConnectionRequest.objects.get_or_create(
            student=request.user,
            tutor=tutor,
            defaults={"message": message},
        )
        if not created:
            if connection.status == ConnectionRequest.Status.ACCEPTED:
                return Response(
                    {"error": "You are already connected to this tutor."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if connection.status == ConnectionRequest.Status.PENDING:
                return Response(
                    {"error": "Your request to this tutor is already pending."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            # Was REJECTED — allow re-send
            connection.status = ConnectionRequest.Status.PENDING
            connection.message = message
            connection.responded_at = None
            connection.save(update_fields=["status", "message", "responded_at"])

        return Response(
            ConnectionRequestSerializer(connection, context={"request": request}).data,
            status=status.HTTP_201_CREATED,
        )


class ConnectedTutorsView(APIView):
    """
    GET /api/v1/my-tutors/
    Returns tutors whose connection request to the logged-in student was ACCEPTED.
    Each record includes display_name ("Ashraf Sir"), profile picture, and tuition groups.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        from .models import ConnectionRequest
        from .serializers import ConnectedTutorSerializer

        if request.user.role != "STUDENT":
            return Response(
                {"error": "Only students can access this endpoint."},
                status=status.HTTP_403_FORBIDDEN,
            )

        accepted_tutor_ids = ConnectionRequest.objects.filter(
            student=request.user,
            status=ConnectionRequest.Status.ACCEPTED,
        ).values_list("tutor_id", flat=True)

        tutors = User.objects.filter(
            id__in=accepted_tutor_ids, is_active=True
        ).prefetch_related("tuitions")

        serializer = ConnectedTutorSerializer(
            tutors, many=True, context={"request": request}
        )
        return Response(serializer.data)


class TutorDetailForStudentView(APIView):
    """
    GET /api/v1/my-tutors/<tutor_id>/
    Detailed view of one tutor: display_name + WeeklyRoutine + UpcomingClasses + homework.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, tutor_id):
        from .models import ConnectionRequest, Homework, WeeklyRoutine, ClassSchedule
        from .serializers import ConnectedTutorSerializer, HomeworkSerializer

        if request.user.role != "STUDENT":
            return Response({"error": "Students only."}, status=status.HTTP_403_FORBIDDEN)

        # Verify the student is actually connected to this tutor.
        connection = ConnectionRequest.objects.filter(
            student=request.user,
            tutor_id=tutor_id,
            status=ConnectionRequest.Status.ACCEPTED,
        ).first()
        if not connection:
            return Response(
                {"error": "You are not connected to this tutor."},
                status=status.HTTP_404_NOT_FOUND,
            )

        tutor = get_object_or_404(User, id=tutor_id, role="TUTOR", is_active=True)
        tutor_data = ConnectedTutorSerializer(tutor, context={"request": request}).data

        # Tuitions this student shares with this tutor (routine scope).
        from apps.students.models import TuitionEnrollment
        enrolled_tuition_ids = list(TuitionEnrollment.objects.filter(
            student=request.user, tuition__tutor=tutor, is_active=True
        ).values_list("tuition_id", flat=True))

        scope = Q(student=request.user) | Q(tuition_id__in=enrolled_tuition_ids)
        routines = WeeklyRoutine.objects.filter(tutor=tutor).filter(scope).order_by("day_of_week", "start_time")
        upcoming = ClassSchedule.objects.filter(
            tutor=tutor, scheduled_at__gte=timezone.now(), is_cancelled=False
        ).filter(scope).order_by("scheduled_at")[:20]

        # Homework assigned to this student (by this tutor) or their tuition groups.
        homework_qs = Homework.objects.filter(
            tutor=tutor,
        ).filter(
            Q(student=request.user) | Q(tuition_id__in=enrolled_tuition_ids)
        ).select_related("tutor", "student", "tuition").order_by("due_date")

        homework_data = HomeworkSerializer(
            homework_qs, many=True, context={"request": request}
        ).data

        return Response({
            "tutor": tutor_data,
            "weekly_routine": [
                {"day_of_week": r.day_of_week, "start_time": str(r.start_time),
                 "end_time": str(r.end_time), "subject": r.subject} for r in routines
            ],
            "upcoming_classes": [
                {"scheduled_at": c.scheduled_at.strftime("%Y-%m-%dT%H:%M:%SZ"), "topic": c.topic}
                for c in upcoming
            ],
            "homework": homework_data,
        })


# ── Homework ViewSet ──────────────────────────────────────────────────────

class HomeworkViewSet(viewsets.GenericViewSet):
    """
    Homework management.

    GET    /api/v1/homework/                    - List (student sees own, tutor sees all theirs)
    POST   /api/v1/homework/                    - Tutor creates homework
    GET    /api/v1/homework/<id>/               - Detail
    PATCH  /api/v1/homework/<id>/               - Tutor edits homework
    DELETE /api/v1/homework/<id>/               - Tutor deletes homework
    POST   /api/v1/homework/<id>/mark_done/     - Tutor marks as evaluated
    POST   /api/v1/homework/<id>/submit/        - Student submits online link
    """
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        from .models import Homework
        user = self.request.user
        qs = Homework.objects.select_related("tutor", "student", "tuition")
        if user.role == "TUTOR":
            return qs.filter(tutor=user)
        if user.role == "STUDENT":
            from .models import TuitionEnrollment
            enrolled_tuition_ids = TuitionEnrollment.objects.filter(
                student=user, is_active=True
            ).values_list("tuition_id", flat=True)
            return qs.filter(
                Q(student=user) | Q(tuition_id__in=enrolled_tuition_ids)
            )
        return Homework.objects.none()

    def list(self, request):
        from .serializers import HomeworkSerializer
        qs = self.get_queryset().order_by("due_date")

        # Optional query filters
        tutor_id = request.query_params.get("tutor_id")
        evaluated = request.query_params.get("evaluated")
        if tutor_id:
            qs = qs.filter(tutor_id=tutor_id)
        if evaluated is not None:
            qs = qs.filter(is_evaluated=(evaluated.lower() == "true"))

        return Response(HomeworkSerializer(qs, many=True, context={"request": request}).data)

    def retrieve(self, request, pk=None):
        from .serializers import HomeworkSerializer
        hw = get_object_or_404(self.get_queryset(), pk=pk)
        return Response(HomeworkSerializer(hw, context={"request": request}).data)

    def create(self, request):
        from .serializers import HomeworkCreateUpdateSerializer, HomeworkSerializer
        from .models import Homework
        if request.user.role != "TUTOR":
            return Response({"error": "Only tutors can create homework."}, status=status.HTTP_403_FORBIDDEN)

        serializer = HomeworkCreateUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        # Ensure the student / tuition belongs to this tutor.
        student = serializer.validated_data.get("student")
        tuition = serializer.validated_data.get("tuition")
        if student and student.tutor != request.user:
            return Response({"student": "This student does not belong to you."}, status=status.HTTP_400_BAD_REQUEST)
        if tuition and tuition.tutor != request.user:
            return Response({"tuition": "This tuition does not belong to you."}, status=status.HTTP_400_BAD_REQUEST)

        hw = serializer.save(tutor=request.user)
        return Response(HomeworkSerializer(hw, context={"request": request}).data, status=status.HTTP_201_CREATED)

    def partial_update(self, request, pk=None):
        from .serializers import HomeworkCreateUpdateSerializer, HomeworkSerializer
        if request.user.role != "TUTOR":
            return Response({"error": "Only tutors can edit homework."}, status=status.HTTP_403_FORBIDDEN)
        hw = get_object_or_404(self.get_queryset(), pk=pk)
        serializer = HomeworkCreateUpdateSerializer(hw, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        hw = serializer.save()
        return Response(HomeworkSerializer(hw, context={"request": request}).data)

    def destroy(self, request, pk=None):
        if request.user.role != "TUTOR":
            return Response({"error": "Only tutors can delete homework."}, status=status.HTTP_403_FORBIDDEN)
        from .models import Homework
        hw = get_object_or_404(Homework, pk=pk, tutor=request.user)
        hw.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=["post"], permission_classes=[IsAuthenticated, IsTutor])
    def mark_done(self, request, pk=None):
        """
        POST /api/v1/homework/<id>/mark_done/
        Tutor marks homework as evaluated. Optionally adds feedback.
        """
        from .serializers import HomeworkMarkDoneSerializer, HomeworkSerializer
        hw = get_object_or_404(self.get_queryset(), pk=pk)
        serializer = HomeworkMarkDoneSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        hw.is_evaluated = True
        hw.evaluated_at = timezone.now()
        if serializer.validated_data.get("feedback"):
            hw.tutor_feedback = serializer.validated_data["feedback"]
        hw.save(update_fields=["is_evaluated", "evaluated_at", "tutor_feedback"])

        return Response({
            "message": "Homework marked as done.",
            "homework": HomeworkSerializer(hw, context={"request": request}).data,
        })

    @action(detail=True, methods=["post"])
    def submit(self, request, pk=None):
        """
        POST /api/v1/homework/<id>/submit/ — STUDENT ONLY.
        May upload submission_file and/or submitted_online_url.
        Can NEVER touch is_evaluated (field not even in serializer).
        """
        from .serializers import StudentHomeworkSubmitSerializer, HomeworkSerializer
        if request.user.role != "STUDENT":
            return Response({"error": "Only students can submit homework."}, status=status.HTTP_403_FORBIDDEN)
        hw = get_object_or_404(self.get_queryset(), pk=pk)
        serializer = StudentHomeworkSubmitSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        hw.submitted_online_url = serializer.validated_data.get("submitted_online_url", hw.submitted_online_url)
        if serializer.validated_data.get("submission_file"):
            hw.submission_file = serializer.validated_data["submission_file"]
        hw.submitted_at = timezone.now()
        hw.save(update_fields=["submitted_online_url", "submission_file", "submitted_at"])

        return Response({
            "message": "Homework submission recorded.",
            "homework": HomeworkSerializer(hw, context={"request": request}).data,
        })

    @action(detail=True, methods=["post", "patch"], permission_classes=[IsAuthenticated, IsTutor],
            url_path="evaluate")
    def evaluate(self, request, pk=None):
        """POST/PATCH /api/v1/homework/<id>/evaluate/ — TUTOR ONLY writes is_evaluated."""
        from .serializers import TutorHomeworkEvaluateSerializer, HomeworkSerializer
        hw = get_object_or_404(self.get_queryset(), pk=pk)
        serializer = TutorHomeworkEvaluateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        hw.is_evaluated = serializer.validated_data["is_evaluated"]
        hw.evaluated_at = timezone.now() if hw.is_evaluated else None
        if serializer.validated_data.get("tutor_feedback"):
            hw.tutor_feedback = serializer.validated_data["tutor_feedback"]
        hw.save(update_fields=["is_evaluated", "evaluated_at", "tutor_feedback"])
        return Response({
            "message": "Homework evaluation updated.",
            "homework": HomeworkSerializer(hw, context={"request": request}).data,
        })


class WeeklyRoutineViewSet(viewsets.ModelViewSet):
    """Tutor manages slots; student reads own (scoped)."""
    permission_classes = [IsAuthenticated]
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]

    def get_queryset(self):
        from .models import WeeklyRoutine
        user = self.request.user
        qs = WeeklyRoutine.objects.select_related("tutor", "student", "tuition")
        if user.role == "TUTOR":
            return qs.filter(tutor=user).order_by("day_of_week", "start_time")
        if user.role == "STUDENT":
            return qs.filter(Q(student=user) | Q(tuition__enrollments__student=user)).order_by("day_of_week", "start_time")
        return WeeklyRoutine.objects.none()

    def get_serializer_class(self):
        from .serializers import WeeklyRoutineSerializer
        return WeeklyRoutineSerializer

    def perform_create(self, serializer):
        if self.request.user.role != "TUTOR":
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied("Only tutors can create routines.")
        serializer.save(tutor=self.request.user)


class ClassScheduleViewSet(viewsets.ModelViewSet):
    """Tutor manages dated classes; student reads upcoming own."""
    permission_classes = [IsAuthenticated]
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]

    def get_queryset(self):
        from .models import ClassSchedule
        user = self.request.user
        qs = ClassSchedule.objects.select_related("tutor", "student", "tuition")
        if user.role == "TUTOR":
            qs = qs.filter(tutor=user)
        elif user.role == "STUDENT":
            qs = qs.filter(Q(student=user) | Q(tuition__enrollments__student=user))
        else:
            return ClassSchedule.objects.none()
        upcoming = self.request.query_params.get("upcoming")
        if upcoming and upcoming.lower() == "true":
            qs = qs.filter(scheduled_at__gte=timezone.now(), is_cancelled=False)
        return qs.order_by("scheduled_at")

    def get_serializer_class(self):
        from .serializers import ClassScheduleSerializer
        return ClassScheduleSerializer

    def perform_create(self, serializer):
        if self.request.user.role != "TUTOR":
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied("Only tutors can schedule classes.")
        serializer.save(tutor=self.request.user)
