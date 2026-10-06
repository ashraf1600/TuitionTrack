"""
Cycles App Views

Endpoints:
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

from apps.authentication.permissions import IsTutor
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
    http_method_names = ['get', 'patch', 'post', 'head', 'options']

    def get_queryset(self):
        qs = super().get_queryset()

        # Support ?student_id=<uuid> filter
        student_id = self.request.query_params.get('student_id')
        if student_id:
            qs = qs.filter(student_id=student_id)

        # Support ?status=ACTIVE or ARCHIVED filter
        cycle_status = self.request.query_params.get('status')
        if cycle_status:
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

        # Update classes_data JSON array
        classes_data = list(cycle.classes_data)
        found = False
        now_iso = timezone.now().isoformat()
        custom_date = serializer.validated_data.get('date')
        date_iso = custom_date.isoformat() if custom_date else now_iso
        topic_val = serializer.validated_data.get('topic', '')

        for item in classes_data:
            if item.get('classNo') == class_no:
                item['completed'] = completed
                item['date'] = date_iso if completed else None
                if completed and topic_val:
                    item['topic'] = topic_val
                elif not completed:
                    item.pop('topic', None)
                found = True
                break

        if not found:
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
            'cycle': CycleSerializer(cycle).data
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
            'cycle': CycleSerializer(new_cycle).data
        }, status=status.HTTP_201_CREATED)


class AttendanceCycleViewSet(viewsets.ModelViewSet):
    """
    ViewSet for Tuition-based AttendanceCycle.
    Manages class completions, date logs, and billing cycles per tuition enrollment.
    """
    from apps.authentication.permissions import IsTutorOrStudent
    permission_classes = [IsAuthenticated, IsTutorOrStudent]
    http_method_names = ['get', 'patch', 'post', 'head', 'options']

    def get_queryset(self):
        from .models import AttendanceCycle
        user = self.request.user
        qs = AttendanceCycle.objects.select_related(
            'enrollment__tuition',
            'enrollment__tuition__tutor',
            'enrollment__student'
        )

        if user.role == 'TUTOR':
            qs = qs.filter(enrollment__tuition__tutor=user)
        elif user.role == 'STUDENT':
            qs = qs.filter(enrollment__student=user)
        else:
            return qs.none()

        tuition_id = self.request.query_params.get('tuition_id')
        if tuition_id:
            qs = qs.filter(enrollment__tuition_id=tuition_id)

        student_id = self.request.query_params.get('student_id')
        if student_id:
            qs = qs.filter(enrollment__student_id=student_id)

        status_param = self.request.query_params.get('status')
        if status_param:
            qs = qs.filter(status=status_param.upper())

        return qs.order_by('-cycle_number')

    def get_serializer_class(self):
        from .serializers import AttendanceCycleSerializer
        return AttendanceCycleSerializer

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context['request'] = self.request
        return context

    @action(detail=True, methods=['patch'], permission_classes=[IsAuthenticated, IsTutor])
    def toggle_class(self, request, pk=None):
        """
        PATCH /api/v1/attendance-cycles/<id>/toggle_class/
        Marks a class as completed or incomplete with recorded date and topic.
        """
        from .models import AttendanceCycle
        from .serializers import AttendanceCycleSerializer

        cycle = self.get_object()
        if cycle.status != AttendanceCycle.Status.ACTIVE:
            return Response(
                {'error': 'Cannot toggle attendance on an archived cycle.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        serializer = ToggleClassSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        class_no = serializer.validated_data['resolved_class_no']
        completed = serializer.validated_data['completed']
        custom_date = serializer.validated_data.get('date')
        topic_val = serializer.validated_data.get('topic', '')

        if class_no > cycle.total_classes:
            return Response(
                {'error': f'Class number {class_no} exceeds cycle length of {cycle.total_classes}.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        classes_data = list(cycle.classes_data)
        found = False
        date_iso = custom_date.isoformat() if custom_date else timezone.now().isoformat()

        for item in classes_data:
            num = item.get('class_no') or item.get('classNo')
            if num == class_no:
                item['completed'] = completed
                item['date'] = date_iso if completed else None
                if completed and topic_val:
                    item['topic'] = topic_val
                elif not completed:
                    item.pop('topic', None)
                found = True
                break

        if not found:
            entry = {
                'class_no': class_no,
                'completed': completed,
                'date': date_iso if completed else None
            }
            if completed and topic_val:
                entry['topic'] = topic_val
            classes_data.append(entry)

        cycle.classes_data = classes_data
        cycle.save(update_fields=['classes_data', 'updated_at'])

        return Response({
            'message': f'Class #{class_no} marked as {"completed" if completed else "incomplete"}.',
            'cycle': AttendanceCycleSerializer(cycle, context={'request': request}).data
        }, status=status.HTTP_200_OK)

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsTutor])
    def reset(self, request, pk=None):
        """
        POST /api/v1/attendance-cycles/<id>/reset/
        Archives current cycle and starts a fresh active cycle.
        """
        from .models import AttendanceCycle
        from .serializers import AttendanceCycleSerializer

        with transaction.atomic():
            cycle = AttendanceCycle.objects.select_for_update().get(id=self.get_object().id)
            if cycle.status != AttendanceCycle.Status.ACTIVE:
                return Response(
                    {'error': 'Cannot reset an already archived cycle.'},
                    status=status.HTTP_400_BAD_REQUEST
                )

            cycle.status = AttendanceCycle.Status.ARCHIVED
            cycle.save(update_fields=['status', 'updated_at'])

            tuition = cycle.enrollment.tuition
            new_cycle = AttendanceCycle.objects.create(
                enrollment=cycle.enrollment,
                cycle_number=cycle.cycle_number + 1,
                classes_data=AttendanceCycle.build_fresh_classes_data(tuition.cycle_length),
                status=AttendanceCycle.Status.ACTIVE
            )

        return Response({
            'message': f'Cycle #{cycle.cycle_number} archived. Cycle #{new_cycle.cycle_number} started.',
            'previous_cycle_id': str(cycle.id),
            'cycle': AttendanceCycleSerializer(new_cycle, context={'request': request}).data
        }, status=status.HTTP_201_CREATED)
