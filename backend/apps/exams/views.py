"""
Exams App Views

Endpoints:
  GET    /api/v1/exams/                  — Scoped list of exams (Tutor: authored; Student: assigned individually or via batch)
  POST   /api/v1/exams/                  — Tutor creates exam (sanitizes HTML & triggers emails)
  GET    /api/v1/exams/<id>/             — Scoped detail view
  PATCH  /api/v1/exams/<id>/             — Tutor edits exam
  POST   /api/v1/exams/<id>/submit/      — Student submits answers/images (auto-grades MCQs, time-validated)
  GET    /api/v1/exams/<id>/leaderboard/ — Dynamic leaderboard ranking for tuition batch / exam
  PATCH  /api/v1/submissions/<id>/grade/ — Tutor marks and grades submission
  POST   /api/v1/media/upload/           — Multipart file upload for diagrams and answer sheets
"""
import os
import uuid
import logging
from datetime import timedelta
from django.utils import timezone
from django.db import models
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
from rest_framework.parsers import MultiPartParser, FormParser

from apps.authentication.permissions import IsTutor, IsStudent, IsTutorOrStudent
from .models import Exam, ExamSubmission
from .serializers import (
    ExamListSerializer,
    ExamDetailSerializer,
    ExamCreateUpdateSerializer,
    ExamSubmissionSerializer,
    SubmitExamSerializer,
    GradeSubmissionSerializer,
    LeaderboardEntrySerializer,
)

logger = logging.getLogger(__name__)


class ExamViewSet(viewsets.ModelViewSet):
    """
    ViewSet for managing and participating in Exams.
    Tutors can create, view, and update exams.
    Students can view their assigned exams (1-on-1 or Batch) and submit them.
    """
    permission_classes = [IsAuthenticated, IsTutorOrStudent]
    http_method_names = ['get', 'post', 'patch', 'delete', 'head', 'options']

    def get_queryset(self):
        user = self.request.user
        qs = Exam.objects.select_related('tutor', 'student', 'batch', 'tuition').prefetch_related('submissions')

        if user.role == 'TUTOR':
            qs = qs.filter(models.Q(tutor=user) | models.Q(tuition__tutor=user))
            student_id = self.request.query_params.get('student_id')
            batch_id = self.request.query_params.get('batch_id')
            tuition_id = self.request.query_params.get('tuition_id')
            if student_id:
                qs = qs.filter(student_id=student_id)
            if batch_id:
                qs = qs.filter(batch_id=batch_id)
            if tuition_id:
                qs = qs.filter(tuition_id=tuition_id)
        elif user.role == 'STUDENT':
            qs = qs.filter(is_published=True).filter(
                models.Q(student=user) |
                models.Q(tuition__enrollments__student=user) |
                models.Q(batch__students=user)
            ).distinct()
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

        # Collect recipient emails (individual student, tuition enrollments, or batch)
        recipients = []
        if exam.student and exam.student.email:
            recipients.append(exam.student.email)
        elif exam.tuition:
            recipients = [
                enr.student.email
                for enr in exam.tuition.enrollments.select_related('student').all()
                if enr.student.email
            ]
        elif exam.batch:
            recipients = [s.email for s in exam.batch.students.all() if s.email]

        if recipients:
            try:
                subject = f'[TuitionTrack] New {exam.category.capitalize()}: {exam.title}'
                start_str = exam.start_time.strftime('%Y-%m-%d %H:%M UTC')
                end_str = exam.end_time.strftime('%Y-%m-%d %H:%M UTC')
                target_desc = f'Tuition: {exam.tuition.title}' if exam.tuition else (f'Batch: {exam.batch.name}' if exam.batch else f'Student: {exam.student.get_full_name() or exam.student.username}')
                body = (
                    f"Hello,\n\n"
                    f"A new assessment has been published by {exam.tutor.get_full_name() or exam.tutor.username}.\n\n"
                    f"Title: {exam.title}\n"
                    f"Category: {exam.category}\n"
                    f"Type: {exam.get_exam_type_display()}\n"
                    f"Target: {target_desc}\n"
                    f"Total Marks: {exam.total_marks}\n"
                    f"Start Time: {start_str}\n"
                    f"End / Deadline: {end_str}\n"
                    f"Grace Period: {exam.grace_period_minutes} minutes\n\n"
                    f"Please log in to TuitionTrack before the deadline.\n\n"
                    f"— TuitionTrack Team"
                )
                send_mail(
                    subject=subject,
                    message=body,
                    from_email=settings.DEFAULT_FROM_EMAIL,
                    recipient_list=recipients,
                    fail_silently=True,
                )
            except Exception as exc:
                logger.warning(f'Failed to send exam notification email: {exc}')

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
        Auto-grades MCQs immediately and calculates score.
        Validates against server UTC time + grace period.
        """
        exam = get_object_or_404(Exam, id=pk)

        # Tenant check: Student must be 1-on-1, enrolled in tuition, or enrolled in batch
        is_assigned = (
            (exam.student == request.user) or
            (exam.tuition and exam.tuition.enrollments.filter(student=request.user).exists()) or
            (exam.batch and exam.batch.students.filter(id=request.user.id).exists())
        )
        if not is_assigned:
            return Response(
                {'error': 'You are not assigned to this exam or tuition.'},
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

        images_val = serializer.validated_data.get('uploaded_images') or serializer.validated_data.get('image_urls') or []

        submission = ExamSubmission.objects.create(
            exam=exam,
            student=request.user,
            submitted_at=now,
            answers_data=serializer.validated_data.get('answers_data', {}),
            uploaded_images=images_val,
            image_urls=images_val,
            status=sub_status,
        )

        # Automatically grade MCQs
        submission.calculate_mcq_score()
        submission.save(update_fields=['mcq_score', 'obtained_marks', 'is_graded', 'graded_at', 'updated_at'])

        return Response(
            {
                'message': f'Exam submitted successfully ({sub_status.capitalize()}). MCQs auto-graded: {submission.mcq_score} marks.',
                'submission': ExamSubmissionSerializer(submission).data,
            },
            status=status.HTTP_201_CREATED
        )

    @action(detail=True, methods=['get'])
    def leaderboard(self, request, pk=None):
        """
        GET /api/v1/exams/<id>/leaderboard/
        Returns ranked leaderboard of student submissions for this exam.
        Accessible by the tutor and assigned students.
        """
        exam = get_object_or_404(Exam, id=pk)

        # Check access permission
        user = request.user
        if user.role == 'TUTOR' and (exam.tutor != user and (not exam.tuition or exam.tuition.tutor != user)):
            return Response({'error': 'Unauthorized'}, status=status.HTTP_403_FORBIDDEN)
        if user.role == 'STUDENT':
            is_assigned = (
                (exam.student == user) or
                (exam.tuition and exam.tuition.enrollments.filter(student=user).exists()) or
                (exam.batch and exam.batch.students.filter(id=user.id).exists())
            )
            if not is_assigned:
                return Response({'error': 'Unauthorized'}, status=status.HTTP_403_FORBIDDEN)

        submissions = exam.submissions.select_related('student').order_by(
            models.F('obtained_marks').desc(nulls_last=True),
            'submitted_at'
        )

        total_marks = float(exam.total_marks)
        leaderboard_data = []

        for idx, sub in enumerate(submissions, start=1):
            obtained = float(sub.obtained_marks) if sub.obtained_marks is not None else 0.0
            pct = round((obtained / total_marks) * 100, 1) if total_marks > 0 else 0.0

            leaderboard_data.append({
                'rank': idx,
                'student_id': sub.student.id,
                'student_name': sub.student.get_full_name() or sub.student.username,
                'obtained_marks': obtained,
                'total_marks': total_marks,
                'percentage': pct,
                'mcq_score': float(sub.mcq_score or 0.0),
                'cq_score': float(sub.cq_score) if sub.cq_score is not None else None,
                'status': sub.status,
                'submitted_at': sub.submitted_at,
                'is_graded': sub.is_graded,
            })

        target_title = exam.tuition.title if exam.tuition else (exam.batch.name if exam.batch else None)

        return Response({
            'exam_id': str(exam.id),
            'exam_title': exam.title,
            'exam_type': exam.exam_type,
            'batch_name': target_title,
            'tuition_title': target_title,
            'total_marks': total_marks,
            'is_results_published': exam.is_results_published,
            'leaderboard': leaderboard_data,
        })


class GradeSubmissionView(APIView):
    """
    PATCH /api/v1/submissions/<uuid:pk>/grade/
    Tutor reviews student submission, inputs obtained marks, CQ score, and feedback.
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

        cq_val = serializer.validated_data.get('cq_score')
        obtained_val = serializer.validated_data.get('obtained_marks')

        if cq_val is not None:
            submission.cq_score = cq_val
            submission.obtained_marks = float(submission.mcq_score or 0) + float(cq_val)
        elif obtained_val is not None:
            submission.obtained_marks = obtained_val

        submission.tutor_feedback = serializer.validated_data.get('tutor_feedback', submission.tutor_feedback)
        submission.is_graded = True
        submission.graded_at = timezone.now()
        submission.save(update_fields=['cq_score', 'obtained_marks', 'tutor_feedback', 'is_graded', 'graded_at', 'updated_at'])

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
    Multipart image/document upload for exam questions, solution sheets, and CQ scripts.
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
