"""
Exams App Views

Endpoints:
  GET    /api/v1/exams/                  — Scoped list of exams (Tutor: authored; Student: assigned individually or via batch)
  POST   /api/v1/exams/                  — Tutor creates exam (sanitizes HTML & triggers emails)
  GET    /api/v1/exams/<id>/             — Scoped detail view
  PATCH  /api/v1/exams/<id>/             — Tutor edits exam
  POST   /api/v1/exams/<id>/submit/      — Student submits answers/images (auto-grades MCQs, time-validated)
  GET    /api/v1/exams/<id>/result/      — Student's evaluated paper, only once results are released
  POST   /api/v1/exams/<id>/publish_results/ — Tutor publishes or hides results by hand
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
from .models import Exam, ExamAttempt, ExamSubmission
from .serializers import (
    ExamListSerializer,
    ExamDetailSerializer,
    StudentExamSerializer,
    ExamResultSerializer,
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

    def get_permissions(self):
        if self.action in [
            'create', 'update', 'partial_update', 'destroy', 'submissions', 'duplicate', 'question_bank', 'publish_results',
        ]:
            return [IsAuthenticated(), IsTutor()]
        if self.action in ('submit', 'start', 'result'):
            return [IsAuthenticated(), IsStudent()]
        return [IsAuthenticated(), IsTutorOrStudent()]


    def get_queryset(self):
        import uuid as _uuid
        user = self.request.user
        qs = Exam.objects.select_related('tutor', 'student', 'tuition').prefetch_related('submissions')

        if user.role == 'TUTOR':
            qs = qs.filter(models.Q(tutor=user) | models.Q(tuition__tutor=user))
            student_id = self.request.query_params.get('student_id')
            batch_id = self.request.query_params.get('batch_id')
            tuition_id = self.request.query_params.get('tuition_id')
            if student_id:
                try:
                    _uuid.UUID(str(student_id))
                except (ValueError, AttributeError, TypeError):
                    return qs.none()
                qs = qs.filter(student_id=student_id)
            if batch_id:
                try:
                    _uuid.UUID(str(batch_id))
                except (ValueError, AttributeError, TypeError):
                    return qs.none()
                qs = qs.filter(tuition_id=batch_id)
            if tuition_id:
                try:
                    _uuid.UUID(str(tuition_id))
                except (ValueError, AttributeError, TypeError):
                    return qs.none()
                qs = qs.filter(tuition_id=tuition_id)
        elif user.role == 'STUDENT':
            qs = qs.filter(is_published=True).filter(
                models.Q(student=user) |
                models.Q(tuition__enrollments__student=user, tuition__enrollments__is_active=True)
            ).distinct()
        else:
            qs = qs.none()

        return qs.order_by('-start_time')

    def get_serializer_class(self):
        if self.action in ['create', 'partial_update', 'update']:
            return ExamCreateUpdateSerializer
        elif self.action == 'retrieve':
            # Students get a serializer that has no answer-bearing field at all.
            return ExamDetailSerializer if self.request.user.role == 'TUTOR' else StudentExamSerializer
        return ExamListSerializer

    def perform_create(self, serializer):
        exam = serializer.save(tutor=self.request.user)
        if exam.is_published:
            self._notify_students(exam)

    def perform_update(self, serializer):
        was_published = serializer.instance.is_published
        exam = serializer.save()
        # A draft that has just been published is news to the students.
        if exam.is_published and not was_published:
            self._notify_students(exam)

    def _assigned_students(self, exam):
        """Active students this exam is for."""
        students = {}
        if exam.student_id and exam.student.is_active:
            students[exam.student_id] = exam.student
        if exam.tuition_id:
            for enr in exam.tuition.enrollments.filter(is_active=True, student__is_active=True).select_related('student'):
                students[enr.student_id] = enr.student
        return list(students.values())

    def _notify_students(self, exam):
        """Email each assigned student separately (never exposes other addresses)."""
        # Collect recipient emails (individual student, tuition enrollments, or batch)
        # active students only; sending individual emails avoids exposing recipient addresses.
        recipients = []
        if exam.student_id and exam.student and exam.student.email and exam.student.is_active:
            recipients.append(exam.student.email)
        if exam.tuition_id:
            recipients += [
                enr.student.email
                for enr in exam.tuition.enrollments.filter(is_active=True, student__is_active=True).select_related('student')
                if enr.student.email and enr.student.is_active
            ]
        # Dedupe while preserving order
        recipients = list(dict.fromkeys(recipients))

        if recipients:
            subject = f'[TuitionTrack] New {exam.category.capitalize()}: {exam.title}'
            from zoneinfo import ZoneInfo
            try:
                zone = ZoneInfo(settings.DISPLAY_TIME_ZONE)
            except Exception:
                zone = ZoneInfo('UTC')
            time_format = f'%a %d %b %Y, %I:%M %p ({zone.key})'
            start_str = exam.start_time.astimezone(zone).strftime(time_format)
            end_str = exam.end_time.astimezone(zone).strftime(time_format)
            target_desc = f'Tuition: {exam.tuition.title}' if exam.tuition else f'Student: {exam.student.get_full_name() or exam.student.username}'
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
            html_body = f"""
            <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; background: #0f172a; color: #f8fafc; border-radius: 16px; padding: 24px; border: 1px solid #334155;">
                <div style="text-align: center; margin-bottom: 20px;">
                    <h2 style="color: #818cf8; margin: 0;">TuitionTrack Assessment Alert</h2>
                    <p style="color: #94a3b8; font-size: 13px; margin: 4px 0 0 0;">New Assessment Published by {exam.tutor.get_full_name() or exam.tutor.username}</p>
                </div>
                <div style="background: #1e293b; border-radius: 12px; padding: 20px; border: 1px solid #334155; margin-bottom: 20px;">
                    <h3 style="color: #ffffff; margin-top: 0; font-size: 18px;">{exam.title}</h3>
                    <table style="width: 100%; border-collapse: collapse; font-size: 13px; color: #cbd5e1;">
                        <tr><td style="padding: 6px 0; color: #94a3b8;"><strong>Category:</strong></td><td style="color: #818cf8;">{exam.category}</td></tr>
                        <tr><td style="padding: 6px 0; color: #94a3b8;"><strong>Target:</strong></td><td style="color: #ffffff;">{target_desc}</td></tr>
                        <tr><td style="padding: 6px 0; color: #94a3b8;"><strong>Type:</strong></td><td>{exam.get_exam_type_display()}</td></tr>
                        <tr><td style="padding: 6px 0; color: #94a3b8;"><strong>Total Marks:</strong></td><td style="color: #34d399; font-weight: bold;">{exam.total_marks}</td></tr>
                        <tr><td style="padding: 6px 0; color: #94a3b8;"><strong>Start Window:</strong></td><td>{start_str}</td></tr>
                        <tr><td style="padding: 6px 0; color: #94a3b8;"><strong>End / Deadline:</strong></td><td style="color: #f87171;">{end_str}</td></tr>
                        <tr><td style="padding: 6px 0; color: #94a3b8;"><strong>Grace Period:</strong></td><td>{exam.grace_period_minutes} min</td></tr>
                    </table>
                </div>
                <p style="font-size: 13px; color: #94a3b8; line-height: 1.5;">
                    Please log in to your TuitionTrack Student Portal before the scheduled window. Questions and assessments will unlock automatically at the start time.
                </p>
            </div>
            """
            for recipient in recipients:
                try:
                    send_mail(
                        subject=subject,
                        message=body,
                        from_email=settings.DEFAULT_FROM_EMAIL,
                        recipient_list=[recipient],
                        html_message=html_body,
                        fail_silently=True,
                    )
                except Exception as exc:
                    logger.warning(f'Failed to send exam notification email to {recipient}: {exc}')

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

    def update(self, request, *args, **kwargs):
        if request.user.role != 'TUTOR':
            return Response({'error': 'Only tutors can edit exams.'}, status=status.HTTP_403_FORBIDDEN)
        return super().update(request, *args, **kwargs)

    def partial_update(self, request, *args, **kwargs):
        if request.user.role != 'TUTOR':
            return Response({'error': 'Only tutors can edit exams.'}, status=status.HTTP_403_FORBIDDEN)
        return super().partial_update(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        if request.user.role != 'TUTOR':
            return Response({'error': 'Only tutors can delete exams.'}, status=status.HTTP_403_FORBIDDEN)
        return super().destroy(request, *args, **kwargs)

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsStudent])
    def submit(self, request, pk=None):
        """
        POST /api/v1/exams/<id>/submit/
        Student submits answers and/or CQ answer sheet photo links.
        Auto-grades MCQs immediately and calculates score.
        Validates against server UTC time + grace period.
        """
        # Scoped lookup: students see only published, assigned exams (no oracle).
        exam = get_object_or_404(self.get_queryset(), id=pk)

        # Tenant check: Student must be 1-on-1 or enrolled in tuition
        is_assigned = (
            (exam.student_id == request.user.id) or
            (exam.tuition_id and exam.tuition.enrollments.filter(student=request.user, is_active=True).exists())
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

        # One real submission per student. An old auto-created "missed" placeholder does not count.
        existing = ExamSubmission.objects.filter(exam=exam, student=request.user).first()
        if existing and existing.status != ExamSubmission.Status.MISSED:
            return Response(
                {'error': 'You have already submitted this exam.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        now = timezone.now()
        if now < exam.start_time:
            return Response(
                {'error': 'Exam has not started yet.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # On time, late (grace period or the late-work window), or refused.
        attempt = ExamAttempt.objects.filter(exam=exam, student=request.user).first()
        started_at = attempt.started_at if attempt else now
        sub_status = exam.submission_status_at(now, started_at)
        if sub_status is None:
            return Response(
                {'error': 'Submission window is closed. Exam deadline and grace period have expired.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        serializer = SubmitExamSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        images_val = serializer.validated_data.get('uploaded_images') or serializer.validated_data.get('image_urls') or []

        from django.db import IntegrityError, transaction
        try:
            with transaction.atomic():
                if existing:
                    existing.delete()
                submission = ExamSubmission.objects.create(
                    exam=exam,
                    student=request.user,
                    submitted_at=now,
                    started_at=started_at,
                    answers_data=serializer.validated_data.get('answers_data', {}),
                    text_answer=serializer.validated_data.get('text_answer', ''),
                    uploaded_images=images_val,
                    image_urls=images_val,
                    status=sub_status,
                )
        except IntegrityError:
            return Response(
                {'error': 'You have already submitted this exam.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Automatically grade MCQs
        submission.calculate_mcq_score()
        submission.save(update_fields=['mcq_score', 'obtained_marks', 'is_graded', 'graded_at', 'updated_at'])

        released = exam.results_released(submission)
        if released and exam.mcq_data:
            msg = f'Exam submitted successfully ({sub_status.capitalize()}). MCQs auto-graded: {submission.mcq_score} marks.'
        else:
            msg = f'Exam submitted successfully ({sub_status.capitalize()}).'

        return Response(
            {
                'message': msg,
                # The marks inside `submission` stay blank until results are released.
                'submission': ExamSubmissionSerializer(submission, context={'request': request}).data,
                'results_released': released,
                'result_status': {
                    'released': released,
                    'mode': exam.result_publish_mode,
                    'publish_at': exam.results_release_time,
                },
            },
            status=status.HTTP_201_CREATED
        )

    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, IsStudent])
    def result(self, request, pk=None):
        """
        GET /api/v1/exams/<id>/result/
        The student's evaluated paper. Until results are released for them this
        returns only `available: false` and when to expect them — no marks, no
        answer key.
        """
        exam = get_object_or_404(self.get_queryset(), id=pk)
        submission = ExamSubmission.objects.filter(exam=exam, student=request.user).exclude(
            status=ExamSubmission.Status.MISSED
        ).select_related('exam').first()

        base = {
            'submitted': submission is not None,
            'mode': exam.result_publish_mode,
            'publish_at': exam.results_release_time,
        }
        if not exam.results_released(submission):
            return Response({'available': False, **base, 'submitted_at': submission.submitted_at if submission else None})
        submission.exam = exam
        return Response({
            'available': True,
            **base,
            'result': ExamResultSerializer(submission, context={'request': request}).data,
        })

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsTutor])
    def publish_results(self, request, pk=None):
        """
        POST /api/v1/exams/<id>/publish_results/   {publish: true|false}
        Publish results now, or take them back. Either way the exam moves to
        manual control, so a schedule cannot undo what the tutor just decided.
        """
        exam = get_object_or_404(self.get_queryset(), id=pk)
        publish = request.data.get('publish', True)
        if isinstance(publish, str):
            publish = publish.strip().lower() not in ('false', '0', 'no', '')
        exam.result_publish_mode = Exam.ResultPublishMode.MANUAL
        exam.publish_time = None
        exam.is_results_published = bool(publish)
        exam.save(update_fields=['result_publish_mode', 'publish_time', 'is_results_published', 'updated_at'])
        return Response({
            'message': 'Results are now visible to students who submitted.' if publish else 'Results are hidden from students.',
            'exam': ExamListSerializer(exam, context={'request': request}).data,
        })

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsTutor])
    def duplicate(self, request, pk=None):
        """
        POST /api/v1/exams/<id>/duplicate/   {tuition_id?}
        Copies an exam — questions, marking scheme, solutions and settings — as a
        DRAFT, optionally for another of the tutor's groups. The copy is scheduled
        for the same time of day one week after today so nothing goes out by accident;
        the tutor adjusts the dates and publishes.
        """
        import copy
        from apps.students.models import Tuition

        source = get_object_or_404(self.get_queryset(), id=pk)
        tuition, student = source.tuition, source.student
        tuition_id = request.data.get('tuition_id')
        if tuition_id:
            try:
                tuition = Tuition.objects.filter(id=tuition_id, tutor=request.user).first()
            except Exception:
                tuition = None
            if not tuition:
                return Response({'tuition_id': ['Selected tuition does not exist.']}, status=status.HTTP_400_BAD_REQUEST)
            student = None

        now = timezone.now()
        window = source.end_time - source.start_time
        start = source.start_time.replace(year=now.year, month=now.month, day=now.day) + timedelta(days=7)
        late_gap = (source.late_submission_until - source.end_time) if source.late_submission_until else None

        clone = Exam.objects.create(
            tutor=request.user,
            tuition=tuition,
            student=student,
            category=source.category,
            exam_type=source.exam_type,
            title=f'{source.title} (copy)'[:255],
            content_html=source.content_html,
            mcq_data=copy.deepcopy(source.mcq_data),
            written_scheme=copy.deepcopy(source.written_scheme),
            solution_html=source.solution_html,
            solution_media_url=source.solution_media_url,
            # Same rule for results; a manually published original starts unpublished again.
            result_publish_mode=source.result_publish_mode,
            is_results_published=False if source.result_publish_mode == Exam.ResultPublishMode.MANUAL else source.is_results_published,
            publish_time=(start + window + (source.publish_time - source.end_time)) if source.publish_time else None,
            total_marks=source.total_marks,
            start_time=start,
            end_time=start + window,
            duration_minutes=source.duration_minutes,
            grace_period_minutes=source.grace_period_minutes,
            late_submission_until=(start + window + late_gap) if late_gap else None,
            shuffle_questions=source.shuffle_questions,
            negative_marks_per_wrong=source.negative_marks_per_wrong,
            is_published=False,
        )
        return Response({
            'message': 'Copied as a draft. Check the dates, then publish.',
            'exam': ExamDetailSerializer(clone, context={'request': request}).data,
        }, status=status.HTTP_201_CREATED)

    @action(detail=False, methods=['get'], permission_classes=[IsAuthenticated, IsTutor])
    def question_bank(self, request):
        """
        GET /api/v1/exams/question_bank/?search=...
        Every MCQ the tutor has written in any of their exams, newest first and
        de-duplicated, so questions can be reused instead of retyped.
        """
        search = (request.query_params.get('search') or '').strip().lower()
        seen, items = set(), []
        for exam in self.get_queryset().order_by('-created_at'):
            for q in (exam.mcq_data or []):
                question = str(q.get('question', '')).strip()
                options = [str(o) for o in (q.get('options') or [])]
                if not question:
                    continue
                key = (question.lower(), tuple(o.lower() for o in options))
                if key in seen:
                    continue
                if search and search not in question.lower() and not any(search in o.lower() for o in options):
                    continue
                seen.add(key)
                items.append({
                    'question': question,
                    'options': options,
                    'correct_answer': q.get('correct_answer'),
                    'points': q.get('points') if q.get('points') is not None else q.get('marks', 1),
                    'explanation': q.get('explanation', ''),
                    'image_url': q.get('image_url', ''),
                    'source_exam': exam.title,
                })
                if len(items) >= 200:
                    break
            if len(items) >= 200:
                break
        return Response({'count': len(items), 'questions': items})

    @action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsStudent])
    def start(self, request, pk=None):
        """
        POST /api/v1/exams/<id>/start/
        The student opens the exam. Records when they started — for a timed exam
        this starts their personal countdown — and returns the questions.
        Calling it again never restarts the clock.
        """
        exam = get_object_or_404(self.get_queryset(), id=pk)
        now = timezone.now()
        if now < exam.start_time:
            return Response({'error': 'Exam has not started yet.'}, status=status.HTTP_400_BAD_REQUEST)
        if ExamSubmission.objects.filter(exam=exam, student=request.user).exclude(
            status=ExamSubmission.Status.MISSED
        ).exists():
            return Response({'error': 'You have already submitted this exam.'}, status=status.HTTP_400_BAD_REQUEST)

        attempt = ExamAttempt.objects.filter(exam=exam, student=request.user).first()
        if exam.submission_status_at(now, attempt.started_at if attempt else now) is None:
            return Response(
                {'error': 'Submission window is closed. Exam deadline and grace period have expired.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        if not attempt:
            attempt, _ = ExamAttempt.objects.get_or_create(exam=exam, student=request.user, defaults={'started_at': now})

        return Response({
            'started_at': attempt.started_at,
            'deadline': exam.personal_deadline(attempt.started_at),
            'exam': StudentExamSerializer(exam, context={'request': request}).data,
        })

    @action(detail=True, methods=['get'], permission_classes=[IsAuthenticated, IsTutor])
    def submissions(self, request, pk=None):
        """
        GET /api/v1/exams/<id>/submissions/
        Everything a tutor needs to follow up and grade: one row per assigned
        student — submitted, late, graded, in progress, not submitted or missing.
        """
        exam = get_object_or_404(self.get_queryset(), id=pk)

        submissions = {
            sub.student_id: sub
            for sub in exam.submissions.select_related('student').exclude(status=ExamSubmission.Status.MISSED)
        }
        attempts = {a.student_id: a for a in exam.attempts.all()}
        students = {s.id: s for s in self._assigned_students(exam)}
        # Keep students who submitted and later left the group.
        for sub in submissions.values():
            students.setdefault(sub.student_id, sub.student)

        closed = timezone.now() > exam.final_deadline
        roster = []
        for student in sorted(students.values(), key=lambda u: (u.get_full_name() or u.username).lower()):
            sub = submissions.get(student.id)
            attempt = attempts.get(student.id)
            if sub:
                state = 'graded' if sub.is_graded else ('late' if sub.status == ExamSubmission.Status.DELAYED else 'submitted')
            elif closed:
                state = 'missing'
            elif attempt:
                state = 'in_progress'
            else:
                state = 'not_submitted'
            roster.append({
                'student_id': str(student.id),
                'student_name': student.get_full_name() or student.username,
                'username': student.username,
                'state': state,
                'is_late': bool(sub and sub.status == ExamSubmission.Status.DELAYED),
                'started_at': attempt.started_at if attempt else (sub.started_at if sub else None),
                'submission': ExamSubmissionSerializer(sub, context={'request': request}).data if sub else None,
            })

        subs = sorted(submissions.values(), key=lambda x: x.submitted_at or timezone.now(), reverse=True)
        return Response({
            'exam_id': str(exam.id),
            'exam_title': exam.title,
            'total_marks': float(exam.total_marks),
            'count': len(subs),
            'assigned_count': len(students),
            'graded_count': sum(1 for x in subs if x.is_graded),
            'is_closed': closed,
            'roster': roster,
            'submissions': ExamSubmissionSerializer(subs, many=True, context={'request': request}).data,
        })

    @action(detail=True, methods=['get'])
    def leaderboard(self, request, pk=None):
        """
        GET /api/v1/exams/<id>/leaderboard/
        Returns ranked leaderboard of student submissions for this exam.
        Accessible by the tutor and assigned students (only after results published).
        """
        # Tutors: scoped to own exams; students: scoped to assigned exams.
        exam = get_object_or_404(self.get_queryset(), id=pk)

        # Check access permission (get_queryset already scopes, keep explicit guard)
        user = request.user
        if user.role == 'TUTOR' and (exam.tutor_id != user.id and (not exam.tuition_id or exam.tuition.tutor_id != user.id)):
            return Response({'error': 'Unauthorized'}, status=status.HTTP_403_FORBIDDEN)
        if user.role == 'STUDENT':
            is_assigned = (
                (exam.student_id == user.id) or
                (exam.tuition_id and exam.tuition.enrollments.filter(student=user, is_active=True).exists())
            )
            if not is_assigned:
                return Response({'error': 'Unauthorized'}, status=status.HTTP_403_FORBIDDEN)
            own = ExamSubmission.objects.filter(exam=exam, student=user).first()
            if not (exam.results_released(own) or exam.results_public()):
                return Response({'error': 'Results are not published yet.'}, status=status.HTTP_403_FORBIDDEN)

        submissions = list(exam.submissions.select_related('student').exclude(
            status=ExamSubmission.Status.MISSED
        ).order_by(models.F('obtained_marks').desc(nulls_last=True), 'submitted_at'))

        total_marks = float(exam.total_marks)
        leaderboard_data = []
        last_score = None
        current_rank = 0

        for idx, sub in enumerate(submissions, start=1):
            obtained = float(sub.obtained_marks) if sub.obtained_marks is not None else 0.0
            pct = round((obtained / total_marks) * 100, 1) if total_marks > 0 else 0.0
            # Dense ranking with ties: equal scores share rank.
            if last_score is None or obtained != last_score:
                current_rank = idx
                last_score = obtained

            leaderboard_data.append({
                'rank': current_rank,
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

        # Once nobody can submit any more, students who never did are shown at the bottom with zero.
        if timezone.now() > exam.final_deadline:
            submitted_ids = {sub.student_id for sub in submissions}
            for student in sorted(self._assigned_students(exam), key=lambda u: (u.get_full_name() or u.username).lower()):
                if student.id not in submitted_ids:
                    leaderboard_data.append({
                        'rank': len(submissions) + 1,
                        'student_id': student.id,
                        'student_name': student.get_full_name() or student.username,
                        'obtained_marks': 0.0,
                        'total_marks': total_marks,
                        'percentage': 0.0,
                        'mcq_score': 0.0,
                        'cq_score': None,
                        'status': ExamSubmission.Status.MISSED,
                        'submitted_at': None,
                        'is_graded': True,
                    })

        target_title = exam.tuition.title if exam.tuition_id else None

        return Response({
            'exam_id': str(exam.id),
            'exam_title': exam.title,
            'exam_type': exam.exam_type,
            'batch_name': target_title,
            'tuition_title': target_title,
            'total_marks': total_marks,
            'is_results_published': exam.results_public(),
            'result_publish_mode': exam.result_publish_mode,
            'leaderboard': leaderboard_data,
        })


class GradeSubmissionView(APIView):
    """
    PATCH /api/v1/submissions/<uuid:pk>/grade/
    Tutor reviews student submission, inputs obtained marks, CQ score, and feedback.
    """
    permission_classes = [IsAuthenticated, IsTutor]

    def patch(self, request, pk):
        from django.db.models import Q
        submission = get_object_or_404(
            ExamSubmission.objects.select_related('exam', 'exam__tuition'),
            Q(exam__tutor=request.user) | Q(exam__tuition__tutor=request.user),
            id=pk,
        )

        serializer = GradeSubmissionSerializer(
            data=request.data,
            context={'submission': submission}
        )
        serializer.is_valid(raise_exception=True)

        cq_val = serializer.validated_data.get('cq_score')
        obtained_val = serializer.validated_data.get('obtained_marks')
        if 'cq_breakdown' in serializer.validated_data:
            submission.cq_breakdown = serializer.validated_data['cq_breakdown']

        from decimal import Decimal
        total = Decimal(str(submission.exam.total_marks))
        mcq = Decimal(str(submission.mcq_score or 0))
        if cq_val is not None and obtained_val is not None:
            # Both supplied: obtained must equal mcq+cq and respect total.
            combined = mcq + Decimal(str(cq_val))
            if Decimal(str(obtained_val)) != combined:
                return Response(
                    {'error': 'obtained_marks must equal mcq_score + cq_score when both are supplied.'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            if combined > total:
                return Response(
                    {'error': f'Combined marks ({combined}) cannot exceed exam total marks ({total}).'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            submission.cq_score = cq_val
            submission.obtained_marks = combined
        elif cq_val is not None:
            combined = mcq + Decimal(str(cq_val))
            if combined > total:
                return Response(
                    {'error': f'Combined marks ({combined}) cannot exceed exam total marks ({total}).'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            submission.cq_score = cq_val
            submission.obtained_marks = combined
        elif obtained_val is not None:
            if Decimal(str(obtained_val)) > total:
                return Response(
                    {'error': f'Obtained marks ({obtained_val}) cannot exceed exam total marks ({total}).'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            submission.obtained_marks = obtained_val

        submission.tutor_feedback = serializer.validated_data.get('tutor_feedback', submission.tutor_feedback)
        submission.is_graded = True
        submission.graded_at = timezone.now()
        submission.save(update_fields=['cq_score', 'cq_breakdown', 'obtained_marks', 'tutor_feedback', 'is_graded', 'graded_at', 'updated_at'])

        return Response(
            {
                'message': 'Submission graded successfully.',
                'submission': ExamSubmissionSerializer(submission, context={'request': request}).data,
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
    ALLOWED_CONTENT_TYPES = {'image/png', 'image/jpeg', 'image/webp', 'application/pdf'}

    def post(self, request):
        uploaded_file = request.FILES.get('file')
        if not uploaded_file:
            return Response({'error': 'No file provided.'}, status=status.HTTP_400_BAD_REQUEST)

        max_mb = getattr(settings, 'MAX_UPLOAD_SIZE_MB', 10)
        max_bytes = max_mb * 1024 * 1024
        # Validate file size (reject empty too)
        if uploaded_file.size == 0:
            return Response({'error': 'Empty file is not allowed.'}, status=status.HTTP_400_BAD_REQUEST)
        if uploaded_file.size > max_bytes:
            return Response(
                {'error': f'File exceeds maximum size limit of {max_mb}MB ({uploaded_file.size} bytes).'},
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
        # Validate MIME type + magic bytes (blocks polyglot HTML/JS in .png/.pdf)
        content_type = getattr(uploaded_file, 'content_type', '')
        if content_type and content_type not in self.ALLOWED_CONTENT_TYPES:
            return Response(
                {'error': f'Invalid content type "{content_type}".'},
                status=status.HTTP_400_BAD_REQUEST
            )
        header = uploaded_file.read(12)
        uploaded_file.seek(0)
        valid_magic = (
            header.startswith(b'\x89PNG') or header.startswith(b'\xff\xd8\xff')
            or header.startswith(b'RIFF') or header.startswith(b'%PDF')
        )
        if not valid_magic:
            return Response(
                {'error': 'File content does not match its extension.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Generate unique filename to avoid overwrites (sanitized, no traversal)
        from django.utils.text import get_valid_filename
        safe_base = get_valid_filename(os.path.basename(uploaded_file.name))[-80:] or 'upload'
        unique_name = f'{uuid.uuid4().hex[:12]}_{safe_base}'
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
