"""
Cycles App Views

Shared tuition cycles (one per tuition group, seen by every enrolled student):
  GET    /api/v1/attendance-cycles/?tuition_id=<uuid>      — Cycles of a tuition (active + history)
  PATCH  /api/v1/attendance-cycles/<id>/toggle_class/      — Tutor marks a class done for the whole group
  POST   /api/v1/attendance-cycles/<id>/reset/             — Tutor archives a finished cycle, starts the next

Legacy 1-on-1 cycles:
  GET    /api/v1/cycles/?student_id=<uuid> — Scoped active/history cycles
  GET    /api/v1/cycles/<uuid:pk>/        — Detailed cycle metrics & classes_data
  PATCH  /api/v1/cycles/<uuid:pk>/toggle_class/ — Check/uncheck attendance box
  POST   /api/v1/cycles/<uuid:pk>/reset/        — Archive cycle & start next active cycle
"""
from django.utils import timezone
from django.db import transaction
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from apps.authentication.permissions import IsTutor, IsTutorOrStudent
from apps.authentication.mixins import TenantScopedViewSet
from .models import Cycle
from .serializers import CycleSerializer, ToggleClassSerializer


class CycleViewSet(TenantScopedViewSet):
    """
    Multi-tenant ViewSet for billing cycles and class attendance.
    Tutors can view, toggle classes, and reset cycles for their students.
    Students can view their own cycles in read-only mode.
    """
    queryset = Cycle.objects.all().select_related('student', 'tutor')
    serializer_class = CycleSerializer
    http_method_names = ['get', 'post', 'patch', 'head', 'options']

    def create(self, request, *args, **kwargs):
        return Response(
            {'error': 'Cycles cannot be created directly. They are initialized via student provisioning or reset.'},
            status=status.HTTP_405_METHOD_NOT_ALLOWED
        )

    def partial_update(self, request, *args, **kwargs):
        if request.user.role != 'TUTOR':
            return Response({'error': 'Students cannot edit cycles.'}, status=status.HTTP_403_FORBIDDEN)
        return super().partial_update(request, *args, **kwargs)

    @staticmethod
    def _validate_uuid(value):
        import uuid as _uuid
        try:
            return str(_uuid.UUID(str(value)))
        except (ValueError, AttributeError, TypeError):
            return None

    def get_queryset(self):
        qs = super().get_queryset()

        # Support ?student_id=<uuid> filter
        student_id = self.request.query_params.get('student_id')
        if student_id:
            if not self._validate_uuid(student_id):
                return qs.none()
            qs = qs.filter(student_id=student_id)

        # Support ?status=ACTIVE or ARCHIVED filter
        cycle_status = self.request.query_params.get('status')
        if cycle_status:
            if cycle_status.upper() not in ('ACTIVE', 'ARCHIVED'):
                return qs.none()
            qs = qs.filter(status=cycle_status.upper())

        return qs.order_by('-cycle_number')

    @action(detail=True, methods=['patch'], permission_classes=[IsAuthenticated, IsTutor])
    def toggle_class(self, request, pk=None):
        """
        PATCH /api/v1/cycles/<id>/toggle_class/
        Toggles attendance for a specific class number within the active cycle.
        """
        cycle = self.get_object()

        if cycle.status != Cycle.Status.ACTIVE:
            return Response(
                {'error': 'Cannot toggle attendance on an archived cycle.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        serializer = ToggleClassSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        class_no = serializer.validated_data['resolved_class_no']
        completed = serializer.validated_data['completed']

        if class_no > cycle.total_classes:
            return Response(
                {'error': f'Class number {class_no} exceeds cycle length of {cycle.total_classes}.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Update classes_data JSON array (row-locked to prevent lost updates)
        with transaction.atomic():
            cycle = Cycle.objects.select_for_update().get(id=cycle.id)
            if cycle.status != Cycle.Status.ACTIVE:
                return Response(
                    {'error': 'Cannot toggle attendance on an archived cycle.'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            classes_data = list(cycle.classes_data)
            found = False
            now_iso = timezone.now().isoformat()
            custom_date = serializer.validated_data.get('date')
            date_iso = custom_date.isoformat() if custom_date else now_iso
            topic_val = serializer.validated_data.get('topic', '')

            for item in classes_data:
                num = item.get('classNo') or item.get('class_no')
                try:
                    match = int(num or 0) == int(class_no)
                except (TypeError, ValueError):
                    continue
                if match:
                    item['completed'] = completed
                    item['date'] = date_iso if completed else None
                    if completed and topic_val:
                        item['topic'] = topic_val
                    elif not completed:
                        item.pop('topic', None)
                    found = True
                    break

            if not found:
                if len(classes_data) >= cycle.total_classes:
                    return Response(
                        {'error': 'Cycle already has maximum number of class entries.'},
                        status=status.HTTP_400_BAD_REQUEST
                    )
                new_item = {
                    'classNo': class_no,
                    'completed': completed,
                    'date': date_iso if completed else None
                }
                if completed and topic_val:
                    new_item['topic'] = topic_val
                classes_data.append(new_item)

            cycle.classes_data = classes_data
            cycle.save(update_fields=['classes_data', 'updated_at'])


        return Response({
            'message': f'Class {class_no} marked as {"completed" if completed else "incomplete"}.',
            'cycle': CycleSerializer(cycle, context={'request': request}).data
        }, status=status.HTTP_200_OK)

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsTutor])
    def reset(self, request, pk=None):
        """
        POST /api/v1/cycles/<id>/reset/
        Archives current cycle and atomically initializes next cycle snapshotting profile fees.
        """
        with transaction.atomic():
            # Lock the current cycle
            cycle = Cycle.objects.select_for_update().get(id=self.get_object().id)

            if cycle.status != Cycle.Status.ACTIVE:
                return Response(
                    {'error': 'Cannot reset an already archived cycle.'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # 1. Archive current cycle
            cycle.status = Cycle.Status.ARCHIVED
            cycle.save(update_fields=['status', 'updated_at'])

            # 2. Read latest StudentProfile config
            profile = getattr(cycle.student, 'student_profile', None)
            new_fee = profile.tuition_fee if profile else cycle.fee_snapshot
            new_length = profile.cycle_length if profile else cycle.total_classes

            # 3. Create fresh active cycle
            next_cycle_number = cycle.cycle_number + 1
            new_cycle = Cycle.objects.create(
                tutor=request.user,
                student=cycle.student,
                cycle_number=next_cycle_number,
                fee_snapshot=new_fee,
                total_classes=new_length,
                classes_data=Cycle.build_fresh_classes_data(new_length),
                status=Cycle.Status.ACTIVE,
            )

        return Response({
            'message': f'Cycle #{cycle.cycle_number} archived. Cycle #{new_cycle.cycle_number} started successfully.',
            'previous_cycle_id': str(cycle.id),
            'cycle': CycleSerializer(new_cycle, context={'request': request}).data
        }, status=status.HTTP_201_CREATED)


def toggle_shared_class(cycle_id, validated_data):
    """
    Mark one class of a shared cycle complete / incomplete under a row lock.
    Returns (cycle, error_message). Because the cycle belongs to the tuition,
    this single write is what every student in the group sees.
    """
    import time
    from django.db.utils import OperationalError
    from .models import AttendanceCycle

    for attempt in range(5):
        try:
            with transaction.atomic():
                cycle = AttendanceCycle.objects.select_for_update().select_related('tuition').get(id=cycle_id)
                if cycle.status != AttendanceCycle.Status.ACTIVE:
                    return cycle, 'Cannot change attendance on an archived cycle.'
                try:
                    cycle.mark_class(
                        validated_data['resolved_class_no'],
                        validated_data['completed'],
                        date=validated_data.get('date'),
                        topic=validated_data.get('topic', ''),
                    )
                except ValueError as exc:
                    return cycle, str(exc)
                cycle.save(update_fields=['classes_data', 'updated_at'])
                return cycle, None
        except OperationalError as exc:
            # SQLite has no row locks; retry briefly when the database is busy.
            if 'locked' in str(exc).lower() and attempt < 4:
                time.sleep(0.05 * (attempt + 1))
                continue
            raise


class AttendanceCycleViewSet(viewsets.ReadOnlyModelViewSet):
    """
    The shared attendance cycle of a tuition group.

    Tutors see their tuitions' cycles with wallet figures and can mark classes
    and start the next cycle. Students see the cycles of the tuitions they are
    enrolled in — progress only, through a serializer with no money fields.
    """
    permission_classes = [IsAuthenticated, IsTutorOrStudent]

    def get_permissions(self):
        from rest_framework.permissions import SAFE_METHODS
        # Anything that is not a read is tutor-only, so a student gets a clear 403.
        if self.request.method not in SAFE_METHODS:
            return [IsAuthenticated(), IsTutor()]
        return super().get_permissions()

    def get_queryset(self):
        from .models import AttendanceCycle
        import uuid as _uuid
        user = self.request.user
        qs = AttendanceCycle.objects.select_related('tuition', 'tuition__tutor')

        if user.role == 'TUTOR':
            qs = qs.filter(tuition__tutor=user)
        elif user.role == 'STUDENT':
            qs = qs.filter(
                tuition__enrollments__student=user,
                tuition__enrollments__is_active=True,
            )
        else:
            return qs.none()

        def valid_uuid(value):
            try:
                _uuid.UUID(str(value))
                return True
            except (ValueError, AttributeError, TypeError):
                return False

        tuition_id = self.request.query_params.get('tuition_id')
        if tuition_id:
            if not valid_uuid(tuition_id):
                return qs.none()
            qs = qs.filter(tuition_id=tuition_id)

        # ?student_id narrows to the tuitions that student is enrolled in.
        student_id = self.request.query_params.get('student_id')
        if student_id:
            if not valid_uuid(student_id):
                return qs.none()
            if user.role == 'STUDENT' and str(student_id) != str(user.id):
                return qs.none()
            if user.role == 'TUTOR':
                qs = qs.filter(
                    tuition__enrollments__student_id=student_id,
                    tuition__enrollments__is_active=True,
                )

        status_param = self.request.query_params.get('status')
        if status_param:
            if status_param.upper() not in ('ACTIVE', 'ARCHIVED'):
                return qs.none()
            qs = qs.filter(status=status_param.upper())

        return qs.distinct().order_by('-cycle_number')

    def get_serializer_class(self):
        from .serializers import AttendanceCycleSerializer, StudentCycleSerializer
        if getattr(self.request.user, 'role', None) == 'TUTOR':
            return AttendanceCycleSerializer
        return StudentCycleSerializer

    @action(detail=True, methods=['patch'], permission_classes=[IsAuthenticated, IsTutor])
    def toggle_class(self, request, pk=None):
        """
        PATCH /api/v1/attendance-cycles/<id>/toggle_class/
        Body: {class_no, completed, date?, topic?}
        Marks the class for the whole group, date-stamps it, and returns the
        cycle with the updated wallet figures.
        """
        from .serializers import AttendanceCycleSerializer

        cycle = self.get_object()
        serializer = ToggleClassSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        cycle, error = toggle_shared_class(cycle.id, serializer.validated_data)
        if error:
            return Response({'error': error}, status=status.HTTP_400_BAD_REQUEST)

        class_no = serializer.validated_data['resolved_class_no']
        completed = serializer.validated_data['completed']
        return Response({
            'message': f'Class #{class_no} marked as {"completed" if completed else "incomplete"}.',
            'cycle': AttendanceCycleSerializer(cycle, context={'request': request}).data
        }, status=status.HTTP_200_OK)

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsTutor])
    def reset(self, request, pk=None):
        """
        POST /api/v1/attendance-cycles/<id>/reset/
        Archives a completed cycle (freezing its earnings) and starts the next
        one for the group from the tuition's current fee and cycle length.
        """
        from .models import AttendanceCycle
        from .serializers import AttendanceCycleSerializer

        with transaction.atomic():
            cycle = AttendanceCycle.objects.select_for_update().select_related('tuition').get(id=self.get_object().id)
            if cycle.status != AttendanceCycle.Status.ACTIVE:
                return Response(
                    {'error': 'Cannot reset an already archived cycle.'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            if not cycle.is_complete:
                return Response(
                    {'error': f'Cannot reset cycle before completion ({cycle.completed_classes}/{cycle.total_classes} classes completed).'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            cycle.status = AttendanceCycle.Status.ARCHIVED
            cycle.save(update_fields=['status', 'updated_at'])
            new_cycle = AttendanceCycle.start_for(cycle.tuition, cycle_number=cycle.cycle_number + 1)

        return Response({
            'message': f'Cycle #{cycle.cycle_number} archived. Cycle #{new_cycle.cycle_number} started.',
            'previous_cycle_id': str(cycle.id),
            'cycle': AttendanceCycleSerializer(new_cycle, context={'request': request}).data
        }, status=status.HTTP_201_CREATED)
