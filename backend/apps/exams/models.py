"""
Exams App — Exam & ExamSubmission Models

Key design principles:
- content_html is ALWAYS sanitized via nh3 before saving (see signals.py).
- Dynamic exam status is computed in Python (not stored) using server UTC time.
- ExamSubmission has a unique constraint (exam, student) to prevent duplicates.
- Grace period allows late CQ image upload submissions to be marked DELAYED.
"""
import uuid
from django.db import models
from django.core.validators import MinValueValidator
from django.utils import timezone
from django.conf import settings


class Exam(models.Model):
    """
    Represents a scheduled examination assigned to a student by a tutor.
    """

    id = models.UUIDField(
        primary_key=True, default=uuid.uuid4, editable=False
    )
    tutor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='created_exams',
        limit_choices_to={'role': 'TUTOR'},
        db_index=True,
        verbose_name='Tutor',
    )
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='assigned_exams',
        limit_choices_to={'role': 'STUDENT'},
        db_index=True,
        verbose_name='Student',
    )

    title = models.CharField(max_length=255, verbose_name='Exam Title')

    # Sanitized rich text from TipTap editor.
    # Raw HTML is NEVER stored directly — it passes through nh3 sanitizer first.
    content_html = models.TextField(
        verbose_name='Exam Content (Sanitized HTML)',
        help_text=(
            'Stores sanitized HTML from the TipTap rich-text editor. '
            'Includes formatted text, tables, and KaTeX math delimiters. '
            'NEVER stored raw — always sanitized via nh3 before persistence.'
        )
    )

    total_marks = models.DecimalField(
        max_digits=6,
        decimal_places=2,
        default=100.00,
        validators=[MinValueValidator(0)],
        verbose_name='Total Marks'
    )
    start_time = models.DateTimeField(db_index=True, verbose_name='Start Time (UTC)')
    end_time = models.DateTimeField(db_index=True, verbose_name='End Time (UTC)')
    duration_minutes = models.PositiveIntegerField(
        null=True, blank=True,
        verbose_name='Duration (Minutes)',
        help_text='Informational. If set, displayed to student as exam duration.'
    )
    grace_period_minutes = models.PositiveIntegerField(
        default=5,
        verbose_name='Grace Period (Minutes)',
        help_text=(
            'Extra time beyond end_time during which a submission is still accepted '
            'but marked as DELAYED. Accounts for mobile upload latency. Default: 5 min.'
        )
    )
    is_published = models.BooleanField(
        default=True,
        verbose_name='Is Published',
        help_text='Unpublished exams are hidden from students.'
    )

    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Exam'
        verbose_name_plural = 'Exams'
        ordering = ['-start_time']
        indexes = [
            models.Index(fields=['tutor', 'start_time']),
            models.Index(fields=['student', 'start_time']),
        ]

    def __str__(self):
        student_name = self.student.get_full_name() or self.student.username
        return f'{self.title} — {student_name}'

    # ── Dynamic Status Computation ───────────────────────────────────────────
    # Status is NEVER stored in the DB — always evaluated against server time.
    # This prevents stale status values and ensures server-authoritative accuracy.

    class DynamicStatus:
        SCHEDULED = 'Scheduled'
        RUNNING = 'Running'
        SUBMITTED = 'Submitted'
        DELAYED = 'Delayed'
        MISSED = 'Missed'

    def get_dynamic_status(self, submission=None) -> str:
        """
        Evaluate and return the current exam status based on server UTC time.

        Args:
            submission: Optional ExamSubmission object (pre-fetched to avoid N+1).

        Returns:
            One of: Scheduled, Running, Submitted, Delayed, Missed
        """
        from django.utils import timezone
        from datetime import timedelta

        now = timezone.now()
        grace_end = self.end_time + timedelta(minutes=self.grace_period_minutes)

        if submission:
            return (
                self.DynamicStatus.SUBMITTED
                if submission.status == ExamSubmission.Status.SUBMITTED
                else self.DynamicStatus.DELAYED
            )

        if now < self.start_time:
            return self.DynamicStatus.SCHEDULED
        elif self.start_time <= now <= self.end_time:
            return self.DynamicStatus.RUNNING
        elif self.end_time < now <= grace_end:
            return self.DynamicStatus.RUNNING   # Still accepting during grace
        else:
            return self.DynamicStatus.MISSED

    def can_submit(self) -> bool:
        """Returns True if the student can still submit (within window + grace)."""
        from datetime import timedelta
        now = timezone.now()
        grace_end = self.end_time + timedelta(minutes=self.grace_period_minutes)
        return self.start_time <= now <= grace_end


class ExamSubmission(models.Model):
    """
    Tracks a student's submission for an exam.
    Enforces uniqueness: one submission per (exam, student) pair.
    """

    class Status(models.TextChoices):
        SUBMITTED = 'SUBMITTED', 'Submitted'
        DELAYED = 'DELAYED', 'Delayed'
        MISSED = 'MISSED', 'Missed'

    id = models.UUIDField(
        primary_key=True, default=uuid.uuid4, editable=False
    )
    exam = models.ForeignKey(
        Exam,
        on_delete=models.CASCADE,
        related_name='submissions',
        db_index=True,
        verbose_name='Exam',
    )
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='exam_submissions',
        limit_choices_to={'role': 'STUDENT'},
        db_index=True,
        verbose_name='Student',
    )
    submitted_at = models.DateTimeField(
        null=True, blank=True,
        verbose_name='Submitted At (UTC)',
        help_text='Server-recorded UTC time of submission.'
    )

    # Student answer data
    answers_data = models.JSONField(
        default=dict,
        verbose_name='MCQ Answers',
        help_text='Dict of question_id -> selected_answer. e.g., {"q1": "A", "q2": "D"}'
    )
    image_urls = models.JSONField(
        default=list,
        verbose_name='CQ Image Uploads',
        help_text='List of uploaded CQ answer sheet image file paths.'
    )
    status = models.CharField(
        max_length=10,
        choices=Status.choices,
        default=Status.SUBMITTED,
        db_index=True,
        verbose_name='Submission Status',
    )

    # Grading fields (filled by tutor after reviewing submission)
    obtained_marks = models.DecimalField(
        max_digits=6,
        decimal_places=2,
        null=True,
        blank=True,
        validators=[MinValueValidator(0)],
        verbose_name='Obtained Marks',
    )
    tutor_feedback = models.TextField(
        blank=True,
        verbose_name='Tutor Feedback',
        help_text='Written feedback from the tutor after grading.'
    )
    is_graded = models.BooleanField(
        default=False,
        db_index=True,
        verbose_name='Is Graded',
    )
    graded_at = models.DateTimeField(
        null=True, blank=True,
        verbose_name='Graded At (UTC)',
    )

    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Exam Submission'
        verbose_name_plural = 'Exam Submissions'
        ordering = ['-submitted_at']
        constraints = [
            # Prevents duplicate submissions via double-tap or refresh
            models.UniqueConstraint(
                fields=['exam', 'student'],
                name='unique_student_submission_per_exam'
            )
        ]

    def __str__(self):
        student_name = self.student.get_full_name() or self.student.username
        return f'{self.exam.title} — {student_name} ({self.status})'
