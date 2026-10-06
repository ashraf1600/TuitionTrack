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
    # Tuition FK (Primary tuition association)
    tuition = models.ForeignKey(
        'students.Tuition',
        on_delete=models.CASCADE,
        related_name='exams',
        null=True,
        blank=True,
        db_index=True,
        verbose_name='Tuition',
        help_text='The Tuition this exam is assigned to.',
    )
    # Target can be a single Student or an entire TuitionBatch (kept for backwards compatibility)
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='assigned_exams',
        limit_choices_to={'role': 'STUDENT'},
        null=True,
        blank=True,
        db_index=True,
        verbose_name='Student (1-on-1)',
        help_text='Set if this exam is assigned to a specific individual student.',
    )

    class ExamType(models.TextChoices):
        MCQ = 'MCQ', 'Multiple Choice'
        CQ = 'CQ', 'Creative / Written'
        MIXED = 'MIXED', 'Mixed'
        HYBRID = 'HYBRID', 'Hybrid (MCQ + CQ)'

    class AssessmentCategory(models.TextChoices):
        EXAM = 'EXAM', 'Exam'
        ASSIGNMENT = 'ASSIGNMENT', 'Assignment'

    category = models.CharField(
        max_length=20,
        choices=AssessmentCategory.choices,
        default=AssessmentCategory.EXAM,
        db_index=True,
        verbose_name='Assessment Category',
        help_text='Differentiates between timed Exams and Assignments with deadlines.'
    )

    exam_type = models.CharField(
        max_length=10,
        choices=ExamType.choices,
        default=ExamType.HYBRID,
        verbose_name='Exam Type',
    )


    title = models.CharField(max_length=255, verbose_name='Exam Title')

    # Sanitized rich text / CQ questions from TipTap editor
    content_html = models.TextField(
        blank=True,
        default='',
        verbose_name='Exam Content / CQ Questions (Sanitized HTML)',
        help_text='Stores sanitized HTML from the TipTap rich-text editor.',
    )

    # Structured MCQ Questions array
    # Schema: [{"id": 1, "question": "...", "options": ["A", "B", "C", "D"], "correct_answer": "B", "marks": 1, "explanation": "..."}]
    mcq_data = models.JSONField(
        default=list,
        blank=True,
        verbose_name='MCQ Questions Data',
        help_text='List of structured MCQs with 4 options and answers for auto-grading.',
    )

    # Model solutions & explanations for CQ & MCQ
    solution_html = models.TextField(
        blank=True,
        default='',
        verbose_name='Model Solution & Answer Keys (Sanitized HTML)',
        help_text='Detailed solutions, step-by-step derivations and answer explanations.',
    )
    solution_media_url = models.CharField(
        max_length=500,
        blank=True,
        default='',
        verbose_name='Solution Attachment / Image Sheet URL',
    )
    is_results_published = models.BooleanField(
        default=True,
        verbose_name='Are Results Published',
        help_text='When enabled, students can view marks, rankings, and solutions.',
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
        constraints = [
            models.CheckConstraint(
                condition=(
                    models.Q(tuition__isnull=False)
                    | models.Q(student__isnull=False)
                ),
                name='exam_requires_target',
            ),
        ]

    def __str__(self):
        if self.student:
            target = self.student.get_full_name() or self.student.username
        elif self.tuition:
            target = f'Tuition: {self.tuition.title}'
        else:
            target = 'Unassigned'
        return f'{self.title} — {target}'

    def save(self, *args, **kwargs):
        # Defence-in-depth: sanitize even on direct ORM/admin/shell writes
        # (serializers sanitize too, but must not be the only gate).
        try:
            from .sanitizer import sanitize_exam_html
            if self.content_html:
                self.content_html = sanitize_exam_html(self.content_html)
            if self.solution_html:
                self.solution_html = sanitize_exam_html(self.solution_html)
        except Exception:
            pass
        super().save(*args, **kwargs)

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
        if not self.is_published:
            return False
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
    uploaded_images = models.JSONField(
        default=list,
        blank=True,
        verbose_name='Uploaded Answer Images',
        help_text='List of uploaded CQ / written answer sheet photo URLs.'
    )
    image_urls = models.JSONField(
        default=list,
        blank=True,
        verbose_name='CQ Image Uploads (Legacy)',
        help_text='List of uploaded CQ answer sheet image file paths.'
    )
    feedback = models.TextField(
        blank=True,
        default='',
        verbose_name='Feedback',
        help_text='Feedback provided to the student.'
    )
    status = models.CharField(
        max_length=10,
        choices=Status.choices,
        default=Status.SUBMITTED,
        db_index=True,
        verbose_name='Submission Status',
    )

    # Grading fields
    mcq_score = models.DecimalField(
        max_digits=6,
        decimal_places=2,
        default=0.00,
        validators=[MinValueValidator(0)],
        verbose_name='MCQ Auto Score',
    )
    cq_score = models.DecimalField(
        max_digits=6,
        decimal_places=2,
        null=True,
        blank=True,
        validators=[MinValueValidator(0)],
        verbose_name='CQ Awarded Marks',
    )
    obtained_marks = models.DecimalField(
        max_digits=6,
        decimal_places=2,
        null=True,
        blank=True,
        validators=[MinValueValidator(0)],
        verbose_name='Total Obtained Marks',
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

    def calculate_mcq_score(self):
        """
        Automatically grades student MCQ answers against exam.mcq_data.
        Computes mcq_score and sets obtained_marks.
        Supports both 0-based indices and letters (A, B, C, D).
        If MCQ-only, marks is_graded=True immediately.
        """
        if not self.exam.mcq_data:
            return 0.0

        LETTER_MAP = {'0': 'A', '1': 'B', '2': 'C', '3': 'D', 'A': 'A', 'B': 'B', 'C': 'C', 'D': 'D'}

        total_mcq = 0.0
        for idx, q in enumerate(self.exam.mcq_data):
            q_id = str(q.get('id', f'mcq-{idx}'))
            raw_correct = str(q.get('correct_answer', '')).strip().upper()
            correct_norm = LETTER_MAP.get(raw_correct, raw_correct)

            # Check by specific ID or by index fallback safely (0 is not None)
            student_val = None
            for key in [q_id, f'mcq_{idx}', str(idx)]:
                if key in self.answers_data:
                    student_val = self.answers_data[key]
                    break

            student_raw = str(student_val).strip().upper() if student_val is not None else ''
            student_norm = LETTER_MAP.get(student_raw, student_raw)


            q_points = q.get('points')
            q_marks_raw = q.get('marks')
            if q_points is not None:
                q_marks = float(q_points)
            elif q_marks_raw is not None:
                q_marks = float(q_marks_raw)
            else:
                q_marks = 1.0

            if student_norm and student_norm == correct_norm:
                total_mcq += q_marks

        max_marks = float(self.exam.total_marks)
        self.mcq_score = min(total_mcq, max_marks)
        if self.exam.exam_type == Exam.ExamType.MCQ:
            self.obtained_marks = min(total_mcq, max_marks)
            self.is_graded = True
            self.graded_at = timezone.now()
        else:
            cq_val = float(self.cq_score) if self.cq_score is not None else 0.0
            self.obtained_marks = min(total_mcq + cq_val, max_marks)
        return self.mcq_score

