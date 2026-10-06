"""
Exams App Views

Endpoints:
  GET    /api/v1/exams/                  — Scoped list of exams (Tutor: authored; Student: assigned)
  POST   /api/v1/exams/                  — Tutor creates exam (sanitizes HTML & triggers email)
  GET    /api/v1/exams/<id>/             — Scoped detail view
  PATCH  /api/v1/exams/<id>/             — Tutor edits exam
  POST   /api/v1/exams/<id>/submit/      — Student submits answers/images (time-validated)
  PATCH  /api/v1/submissions/<id>/grade/ — Tutor marks and grades submission
  POST   /api/v1/media/upload/           — Multipart file upload for diagrams and answer sheets
"""
import os
import uuid
import logging
from datetime import timedelta
from django.utils import timezone
from django.core.mail import send_mail
from django.core.files.storage import default_storage
from django.core.files.base import ContentFile
from django.conf import settings
from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.views import APIView
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser

from apps.authentication.permissions import IsTutor, IsStudent, IsTutorOrStudent
from .models import Exam, ExamSubmission
from .serializers import (
    ExamListSerializer,
    ExamDetailSerializer,
    ExamCreateUpdateSerializer,
    ExamSubmissionSerializer,
    SubmitExamSerializer,
    GradeSubmissionSerializer,
)

logger = logging.getLogger(__name__)


class ExamViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing and participating in Exams.
    Tutors can create, view, and update exams.
    Students can view their assigned exams and submit them.
    """
    permission_classes = [IsAuthenticated, IsTutorOrStudent]
    http_method_names = ['get', 'post', 'patch', 'delete', 'head', 'options']

    def get_queryset(self):
        user = self.request.user
        qs = Exam.objects.select_related('tutor', 'student').prefetch_related('submissions')

        if user.role == 'TUTOR':
            qs = qs.filter(tutor=user)
            student_id = self.request.query_params.get('student_id')
            if student_id:
                qs = qs.filter(student_id=student_id)
        elif user.role == 'STUDENT':
            qs = qs.filter(student=user, is_published=True)
        else:
            qs = qs.none()

        return qs.order_by('-start_time')

    def get_serializer_class(self):
        if self.action in ['create', 'partial_update', 'update']:
            return ExamCreateUpdateSerializer
        elif self.action == 'retrieve':
            return ExamDetailSerializer
        return ExamListSerializer

    def perform_create(self, serializer):
        """Create exam and dispatch email notification asynchronously/safely."""
        exam = serializer.save(tutor=self.request.user)

        # Send email alert to student
        student = exam.student
        if student.email:
            try:
                subject = f'[TuitionTrack] New Exam Scheduled: {exam.title}'
                start_str = exam.start_time.strftime('%Y-%m-%d %H:%M UTC')
                end_str = exam.end_time.strftime('%Y-%m-%d %H:%M UTC')
                body = (
                    f"Hi {student.first_name or student.username},\n\n"
                    f"A new exam has been scheduled by your tutor, {exam.tutor.get_full_name() or exam.tutor.username}.\n\n"
                    f"Exam: {exam.title}\n"
                    f"Total Marks: {exam.total_marks}\n"
                    f"Start Time: {start_str}\n"
                    f"End Time: {end_str}\n"
                    f"Grace Period: {exam.grace_period_minutes} minutes\n\n"
                    f"Please log in to your TuitionTrack student portal before the exam begins.\n\n"
                    f"— TuitionTrack Team"
                )
                send_mail(
                    subject=subject,
                    message=body,
                    from_email=settings.DEFAULT_FROM_EMAIL,
                    recipient_list=[student.email],
                    fail_silently=True,
                )
            except Exception as exc:
                logger.warning(f'Failed to send exam notification email to {student.email}: {exc}')

    def create(self, request, *args, **kwargs):
        if request.user.role != 'TUTOR':
            return Response({'error': 'Only tutors can schedule exams.'}, status=status.HTTP_403_FORBIDDEN)
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        self.perform_create(serializer)
        exam_instance = serializer.instance
        return Response(
            {
                'message': 'Exam created successfully and notification dispatched.',
                'exam': ExamDetailSerializer(exam_instance, context={'request': request}).data,
            },
            status=status.HTTP_201_CREATED
        )

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsStudent])
    def submit(self, request, pk=None):
        """
        POST /api/v1/exams/<id>/submit/
        Student submits answers and/or CQ answer sheet photo links.
        Validates against server UTC time + grace period.
        """
        exam = get_object_or_404(Exam, id=pk)

        # Tenant check: Student must be the assigned student
        if exam.student != request.user:
            return Response(
                {'error': 'You are not assigned to this exam.'},
                status=status.HTTP_403_FORBIDDEN
            )

        if not exam.is_published:
            return Response(
                {'error': 'This exam is not active.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Duplicate check
        if ExamSubmission.objects.filter(exam=exam, student=request.user).exists():
            return Response(
                {'error': 'You have already submitted this exam.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Time validation against server UTC time
        now = timezone.now()
        grace_limit = exam.end_time + timedelta(minutes=exam.grace_period_minutes)

        if now < exam.start_time:
            return Response(
                {'error': 'Exam has not started yet.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        if now > grace_limit:
            return Response(
                {'error': 'Submission window is closed. Exam deadline and grace period have expired.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Determine status: SUBMITTED (on time) or DELAYED (during grace period)
        if now <= exam.end_time:
            sub_status = ExamSubmission.Status.SUBMITTED
        else:
            sub_status = ExamSubmission.Status.DELAYED

        serializer = SubmitExamSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        submission = ExamSubmission.objects.create(
            exam=exam,
            student=request.user,
            submitted_at=now,
            answers_data=serializer.validated_data.get('answers_data', {}),
            image_urls=serializer.validated_data.get('image_urls', []),
            status=sub_status,
        )

        return Response(
            {
                'message': f'Exam submitted successfully ({sub_status.capitalize()}).',
                'submission': ExamSubmissionSerializer(submission).data,
            },
            status=status.HTTP_201_CREATED
        )


class GradeSubmissionView(APIView):
    """
    PATCH /api/v1/submissions/<uuid:pk>/grade/
    Tutor reviews student submission, inputs obtained marks and feedback.
    """
    permission_classes = [IsAuthenticated, IsTutor]

    def patch(self, request, pk):
        submission = get_object_or_404(
            ExamSubmission.objects.select_related('exam'),
            id=pk,
            exam__tutor=request.user
        )

        serializer = GradeSubmissionSerializer(
            data=request.data,
            context={'submission': submission}
        )
        serializer.is_valid(raise_exception=True)

        submission.obtained_marks = serializer.validated_data['obtained_marks']
        submission.tutor_feedback = serializer.validated_data.get('tutor_feedback', '')
        submission.is_graded = True
        submission.graded_at = timezone.now()
        submission.save(update_fields=['obtained_marks', 'tutor_feedback', 'is_graded', 'graded_at', 'updated_at'])

        return Response(
            {
                'message': 'Submission graded successfully.',
                'submission': ExamSubmissionSerializer(submission).data,
            },
            status=status.HTTP_200_OK
        )


class MediaUploadView(APIView):
    """
    POST /api/v1/media/upload/
    Multipart image/document upload for exam questions and CQ student scripts.
    Restricted to authenticated users, validated by size and extension.
    """
    permission_classes = [IsAuthenticated]
    parser_classes = [MultiPartParser, FormParser]

    ALLOWED_EXTENSIONS = {'.png', '.jpg', '.jpeg', '.webp', '.pdf'}
    MAX_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB

    def post(self, request):
        uploaded_file = request.FILES.get('file')
        if not uploaded_file:
            return Response({'error': 'No file provided.'}, status=status.HTTP_400_BAD_REQUEST)

        # Validate file size
        if uploaded_file.size > self.MAX_SIZE_BYTES:
            return Response(
                {'error': f'File exceeds maximum size limit of 10MB ({uploaded_file.size} bytes).'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Validate extension
        _, ext = os.path.splitext(uploaded_file.name)
        ext = ext.lower()
        if ext not in self.ALLOWED_EXTENSIONS:
            return Response(
                {'error': f'Invalid file format "{ext}". Allowed formats: {", ".join(self.ALLOWED_EXTENSIONS)}'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Generate unique filename to avoid overwrites
        unique_name = f'{uuid.uuid4().hex[:12]}_{uploaded_file.name}'
        save_path = f'uploads/{timezone.now().strftime("%Y/%m")}/{unique_name}'

        saved_path = default_storage.save(save_path, ContentFile(uploaded_file.read()))
        file_url = f'{settings.MEDIA_URL}{saved_path}'

        return Response(
            {
                'url': file_url,
                'filename': uploaded_file.name,
                'size': uploaded_file.size,
                'message': 'File uploaded successfully.',
            },
            status=status.HTTP_201_CREATED
        )
