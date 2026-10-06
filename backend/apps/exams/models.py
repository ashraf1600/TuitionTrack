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

    # Optional marking scheme for the written part, so it can be marked question by question.
    # Schema: [{"id": "<uuid>", "label": "Q1 (a)", "marks": 5}]
    written_scheme = models.JSONField(
        default=list,
        blank=True,
        verbose_name='Written Marking Scheme',
        help_text='List of written questions with their maximum marks.',
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

    class ResultPublishMode(models.TextChoices):
        IMMEDIATE = 'IMMEDIATE', 'Right after each student submits'
        MANUAL = 'MANUAL', 'When the tutor publishes them'
        SCHEDULED = 'SCHEDULED', 'At a set time (or when the exam closes)'

    result_publish_mode = models.CharField(
        max_length=10,
        choices=ResultPublishMode.choices,
        default=ResultPublishMode.SCHEDULED,
        verbose_name='Result Publication Mode',
        help_text=(
            'IMMEDIATE: a student sees marks and answers as soon as they submit. '
            'MANUAL: only while is_results_published is on. '
            'SCHEDULED: from publish_time, or once the exam has closed if no time is set.'
        ),
    )
    publish_time = models.DateTimeField(
        null=True, blank=True,
        verbose_name='Publish Results At (UTC)',
        help_text='Only for SCHEDULED mode. Empty means "as soon as nobody can submit any more".',
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
        help_text=(
            'Time limit per student for timed exams. The clock starts when the student '
            'opens the exam and never runs past end_time. Ignored for assignments.'
        )
    )
    late_submission_until = models.DateTimeField(
        null=True, blank=True,
        verbose_name='Accept Late Work Until (UTC)',
        help_text='If set, submissions after the deadline are accepted until this time and flagged late.'
    )
    shuffle_questions = models.BooleanField(
        default=False,
        verbose_name='Shuffle MCQ Order',
        help_text='Each student gets the MCQs in a different (stable) order.'
    )
    negative_marks_per_wrong = models.DecimalField(
        max_digits=4,
        decimal_places=2,
        default=0,
        validators=[MinValueValidator(0)],
        verbose_name='Negative Marks per Wrong MCQ',
        help_text='Marks deducted for each wrong MCQ answer. Unanswered questions cost nothing.'
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
        DRAFT = 'Draft'
        SCHEDULED = 'Scheduled'
        RUNNING = 'Running'
        LATE = 'Late'          # deadline passed, late work still accepted
        SUBMITTED = 'Submitted'
        DELAYED = 'Delayed'
        MISSED = 'Missed'
        CLOSED = 'Closed'      # tutor-side word for a finished group exam

    # ── Time rules (single source of truth for views and serializers) ────────

    @property
    def grace_end(self):
        from datetime import timedelta
        return self.end_time + timedelta(minutes=self.grace_period_minutes)

    @property
    def final_deadline(self):
        """Last moment any submission is accepted (grace period or the late-work window)."""
        if self.late_submission_until and self.late_submission_until > self.grace_end:
            return self.late_submission_until
        return self.grace_end

    @property
    def is_timed(self):
        """True when each student gets their own countdown from the moment they start."""
        return bool(self.duration_minutes) and self.category == self.AssessmentCategory.EXAM

    def personal_deadline(self, started_at=None):
        """When this student's on-time window ends: their own timer, capped at end_time."""
        from datetime import timedelta
        if self.is_timed and started_at:
            return min(started_at + timedelta(minutes=self.duration_minutes), self.end_time)
        return self.end_time

    def submission_status_at(self, now, started_at=None):
        """
        'SUBMITTED' (on time), 'DELAYED' (grace period or late-work window), or
        None when a submission at `now` must be refused.
        """
        from datetime import timedelta
        deadline = self.personal_deadline(started_at)
        if now <= deadline:
            return ExamSubmission.Status.SUBMITTED
        if now <= deadline + timedelta(minutes=self.grace_period_minutes):
            return ExamSubmission.Status.DELAYED
        if self.late_submission_until and now <= self.late_submission_until:
            return ExamSubmission.Status.DELAYED
        return None

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

        if submission and submission.status == ExamSubmission.Status.MISSED:
            submission = None
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
        elif now <= self.final_deadline:
            return self.DynamicStatus.LATE
        else:
            return self.DynamicStatus.MISSED

    # ── Result publication (single source of truth for every serializer and view) ──

    @property
    def results_release_time(self):
        """When results come out by the clock; None when that is not decided by time."""
        if self.result_publish_mode == self.ResultPublishMode.SCHEDULED:
            return self.publish_time or self.final_deadline
        return None

    def results_public(self, now=None) -> bool:
        """True once results are out for the whole group (drives the leaderboard)."""
        now = now or timezone.now()
        mode = self.result_publish_mode
        if mode == self.ResultPublishMode.MANUAL:
            return bool(self.is_results_published)
        if mode == self.ResultPublishMode.IMMEDIATE:
            return now > self.final_deadline
        if self.publish_time:
            return now >= self.publish_time
        return now > self.final_deadline

    def results_released(self, submission, now=None) -> bool:
        """
        May this student see marks, correct answers and solutions?
        Never without a real submission of their own, so answers cannot reach
        someone who could still sit the exam.
        """
        if not submission or submission.status == ExamSubmission.Status.MISSED:
            return False
        if self.result_publish_mode == self.ResultPublishMode.IMMEDIATE:
            return True
        return self.results_public(now)

    def can_submit(self) -> bool:
        """Returns True if a student can still submit (window, grace, or late-work window)."""
        if not self.is_published:
            return False
        now = timezone.now()
        return self.start_time <= now <= self.final_deadline


class ExamAttempt(models.Model):
    """
    Records when a student opened an exam. For timed exams this starts their
    personal countdown; it also tells the tutor how long the student took.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    exam = models.ForeignKey(Exam, on_delete=models.CASCADE, related_name='attempts')
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='exam_attempts',
        limit_choices_to={'role': 'STUDENT'},
    )
    started_at = models.DateTimeField(default=timezone.now)

    class Meta:
        verbose_name = 'Exam Attempt'
        verbose_name_plural = 'Exam Attempts'
        constraints = [
            models.UniqueConstraint(fields=['exam', 'student'], name='unique_attempt_per_exam_student')
        ]

    def __str__(self):
        return f'{self.exam.title} — {self.student.username} started {self.started_at:%Y-%m-%d %H:%M}'


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
    text_answer = models.TextField(
        blank=True,
        default='',
        verbose_name='Typed Answer',
        help_text='Written answer typed by the student (alternative to photo uploads).'
    )
    started_at = models.DateTimeField(
        null=True, blank=True,
        verbose_name='Started At (UTC)',
        help_text='When the student opened the exam.'
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
    cq_breakdown = models.JSONField(
        default=dict,
        blank=True,
        verbose_name='Written Marks per Question',
        help_text='Marks per written_scheme item id, e.g. {"<id>": 4.5}. cq_score is their sum.',
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

    @staticmethod
    def _choice_key(value):
        """Canonical form of a chosen option: 'B' and 1 both become '1'. Blank stays ''."""
        if value is None:
            return ''
        text = str(value).strip().upper()
        if len(text) == 1 and 'A' <= text <= 'E':
            return str(ord(text) - ord('A'))
        return text

    def mcq_review(self):
        """
        Mark every MCQ: one row per question with the student's choice, the correct
        choice and the marks it earned. Used for the score and for the result page,
        so the two can never disagree. It contains the answers, so it must never be
        sent to a student before results are released.
        """
        answers = self.answers_data if isinstance(self.answers_data, dict) else {}
        penalty = float(self.exam.negative_marks_per_wrong or 0)
        rows = []
        for idx, q in enumerate(self.exam.mcq_data or []):
            q_id = str(q.get('id', f'mcq-{idx}'))
            correct = self._choice_key(q.get('correct_answer'))

            # Look up by question id, falling back to the older index-based keys (0 is a valid answer).
            student_val = None
            for key in [q_id, f'mcq_{idx}', str(idx)]:
                if key in answers:
                    student_val = answers[key]
                    break
            selected = self._choice_key(student_val)

            raw_points = q.get('points') if q.get('points') is not None else q.get('marks')
            try:
                points = float(raw_points) if raw_points is not None else 1.0
            except (TypeError, ValueError):
                points = 1.0

            if selected and selected == correct:
                outcome, awarded = 'correct', points
            elif selected:
                # Answered but wrong: optional negative marking. Blank answers cost nothing.
                outcome, awarded = 'wrong', -penalty
            else:
                outcome, awarded = 'skipped', 0.0
            rows.append({
                'id': q_id,
                'points': points,
                'correct_answer': int(correct) if correct.isdigit() else None,
                'selected': int(selected) if selected.isdigit() else None,
                'outcome': outcome,
                'awarded': awarded,
            })
        return rows

    def calculate_mcq_score(self):
        """
        Automatically grades student MCQ answers against exam.mcq_data.
        Computes mcq_score and sets obtained_marks.
        Supports both 0-based indices and letters (A, B, C, D).
        If MCQ-only, marks is_graded=True immediately.
        """
        if not self.exam.mcq_data:
            return 0.0

        total_mcq = sum(row['awarded'] for row in self.mcq_review())
        total_mcq = max(0.0, round(total_mcq, 2))
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

