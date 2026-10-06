"""
Cycles App — Cycle Model

Tracks dynamic class attendance per student per billing cycle.
Key design decisions:
- fee_snapshot & total_classes snapshot values at cycle creation so that
  profile edits don't retroactively alter historical financial data.
- Partial UniqueConstraint ensures exactly ONE active cycle per student.
- classes_data is a structured JSON array, one entry per class.
"""
import uuid
from django.db import models
from django.core.validators import MinValueValidator
from django.conf import settings


class Cycle(models.Model):
    """
    Represents a single billing cycle for a student.
    """

    class Status(models.TextChoices):
        ACTIVE = 'ACTIVE', 'Active'
        ARCHIVED = 'ARCHIVED', 'Archived'

    id = models.UUIDField(
        primary_key=True, default=uuid.uuid4, editable=False
    )
    tutor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='tutor_cycles',
        limit_choices_to={'role': 'TUTOR'},
        db_index=True,
        verbose_name='Tutor',
    )
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='student_cycles',
        limit_choices_to={'role': 'STUDENT'},
        db_index=True,
        verbose_name='Student',
    )
    cycle_number = models.PositiveIntegerField(
        default=1,
        verbose_name='Cycle Number',
        help_text='Auto-incremented on each reset. Cycle #1 is the first.'
    )

    # ── Financial Snapshots ─────────────────────────────────────────────────
    # These are immutable copies taken from StudentProfile at cycle creation.
    # Editing the student's profile fee/cycle_length later has NO effect here.
    fee_snapshot = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=0.00,
        validators=[MinValueValidator(0)],
        verbose_name='Fee Snapshot',
        help_text='Copy of tuition_fee at the time this cycle was created.'
    )
    total_classes = models.PositiveIntegerField(
        default=12,
        validators=[MinValueValidator(1)],
        verbose_name='Total Classes',
        help_text='Copy of cycle_length at the time this cycle was created.'
    )

    # ── Attendance Data ──────────────────────────────────────────────────────
    # Stored as a JSON array of class attendance records.
    # Schema: [{"classNo": 1, "completed": true, "date": "2026-10-06T10:00:00Z"}, ...]
    classes_data = models.JSONField(
        default=list,
        verbose_name='Classes Data',
        help_text='JSON array tracking completion status and date for each class.'
    )

    status = models.CharField(
        max_length=10,
        choices=Status.choices,
        default=Status.ACTIVE,
        db_index=True,
        verbose_name='Cycle Status',
    )
    notes = models.TextField(blank=True, verbose_name='Notes')

    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Cycle'
        verbose_name_plural = 'Cycles'
        ordering = ['student', '-cycle_number']
        constraints = [
            # Ensures only ONE active cycle per student at any time.
            # Prevents duplicate active cycles from race conditions or UI bugs.
            models.UniqueConstraint(
                fields=['student'],
                condition=models.Q(status='ACTIVE'),
                name='unique_active_cycle_per_student'
            )
        ]
        indexes = [
            models.Index(fields=['tutor', 'status']),
            models.Index(fields=['student', 'status']),
        ]

    def __str__(self):
        student_name = self.student.get_full_name() or self.student.username
        return f'{student_name} — Cycle #{self.cycle_number} ({self.status})'

    # ── Computed Properties ──────────────────────────────────────────────────

    @property
    def completed_classes(self):
        """Count of classes marked as completed. Handles unchecked classes correctly."""
        return sum(1 for c in self.classes_data if c.get('completed', False))

    @property
    def earned_amount(self):
        """
        Earned revenue based on completed classes.
        Formula: (fee_snapshot / total_classes) * completed_classes
        Guards against division by zero.
        """
        if not self.total_classes:
            return 0
        per_class_rate = self.fee_snapshot / self.total_classes
        return round(per_class_rate * self.completed_classes, 2)

    @property
    def pending_amount(self):
        """Revenue yet to be earned in this cycle."""
        return round(self.fee_snapshot - self.earned_amount, 2)

    @property
    def is_complete(self):
        """True when all classes in the cycle are checked off."""
        return self.completed_classes >= self.total_classes

    @classmethod
    def build_fresh_classes_data(cls, total_classes: int) -> list:
        """
        Factory method: generates a fresh classes_data array for a new cycle.
        Example output for total_classes=3:
        [
          {"classNo": 1, "completed": False, "date": None},
          {"classNo": 2, "completed": False, "date": None},
          {"classNo": 3, "completed": False, "date": None},
        ]
        """
        return [
            {"classNo": i, "completed": False, "date": None}
            for i in range(1, total_classes + 1)
        ]


class AttendanceCycle(models.Model):
    """
    Per-Tuition Attendance & Dynamic Cycle model.
    Tracks class completions (1 to cycle_length) per student within a specific Tuition.
    Includes auto-reset, date stamping, and real-time Tuition Wallet / earnings calculations.
    """

    class Status(models.TextChoices):
        ACTIVE = 'ACTIVE', 'Active'
        ARCHIVED = 'ARCHIVED', 'Archived'

    id = models.UUIDField(
        primary_key=True, default=uuid.uuid4, editable=False
    )
    tutor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='tuition_cycles',
        limit_choices_to={'role': 'TUTOR'},
        db_index=True,
        verbose_name='Tutor',
    )
    enrollment = models.ForeignKey(
        'students.TuitionEnrollment',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='cycles',
        verbose_name='Tuition Enrollment'
    )
    cycle_number = models.PositiveIntegerField(
        default=1,
        verbose_name='Cycle Number',
        help_text='Auto-incremented on each reset. Cycle #1 is the first.'
    )
    fee_snapshot = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=0.00,
        validators=[MinValueValidator(0)],
        verbose_name='Fee Snapshot',
        help_text='Copy of tuition_fee at the time this cycle was created.'
    )
    total_classes = models.PositiveIntegerField(
        default=12,
        validators=[MinValueValidator(1)],
        verbose_name='Total Classes',
        help_text='Copy of cycle_length at the time this cycle was created.'
    )
    classes_data = models.JSONField(
        default=list,
        verbose_name='Classes Attendance Data',
        help_text='[{"class_no": 1, "completed": True, "date": "2026-10-06", "topic": "..."}]'
    )
    status = models.CharField(
        max_length=10,
        choices=Status.choices,
        default=Status.ACTIVE,
        db_index=True,
        verbose_name='Cycle Status'
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Attendance Cycle'
        verbose_name_plural = 'Attendance Cycles'
        ordering = ['enrollment', '-cycle_number']
        constraints = [
            models.UniqueConstraint(
                fields=['enrollment'],
                condition=models.Q(status='ACTIVE'),
                name='unique_active_attendance_cycle_per_enrollment'
            )
        ]

    def __str__(self):
        return f'{self.enrollment or "Archived"} — Cycle #{self.cycle_number} ({self.status})'

    def save(self, *args, **kwargs):
        # Snapshot only on creation so later Tuition fee edits never rewrite history.
        if self._state.adding and self.enrollment_id:
            try:
                tuition = self.enrollment.tuition
            except Exception:
                tuition = None
            if tuition is not None:
                if self.tutor_id is None:
                    self.tutor = tuition.tutor
                # fee_snapshot default 0.00 means "unset" -> snapshot live fee
                if self.fee_snapshot is None or float(self.fee_snapshot) == 0.0:
                    self.fee_snapshot = tuition.tuition_fee
                # total_classes default is 12; snapshot live length on creation
                # (explicit values passed by callers are already set before save)
                if not kwargs.get('update_fields'):
                    self.total_classes = tuition.cycle_length
        super().save(*args, **kwargs)

    @property
    def completed_classes(self):
        """Count of classes marked as completed."""
        return sum(1 for c in self.classes_data if c.get('completed', False))

    @property
    def tuition_fee(self):
        if self.fee_snapshot is not None and float(self.fee_snapshot) > 0:
            return self.fee_snapshot
        if self.enrollment_id and getattr(self, 'enrollment', None) and getattr(self.enrollment, 'tuition', None):
            return self.enrollment.tuition.tuition_fee
        return self.fee_snapshot or 0.00

    @property
    def per_class_rate(self):
        from decimal import Decimal
        if not self.total_classes:
            return 0.00
        return float(round(Decimal(str(self.tuition_fee)) / self.total_classes, 2))

    @property
    def earned_revenue(self):
        from decimal import Decimal
        if not self.total_classes:
            return 0.00
        fee = Decimal(str(self.tuition_fee))
        if self.completed_classes >= self.total_classes:
            return float(fee)
        return float(round((fee * self.completed_classes) / self.total_classes, 2))

    @property
    def pending_balance(self):
        from decimal import Decimal
        if not self.total_classes:
            return 0.00
        fee = Decimal(str(self.tuition_fee))
        earned = Decimal(str(self.earned_revenue))
        if self.completed_classes >= self.total_classes:
            return 0.00
        return float(round(fee - earned, 2))

    @property
    def progress_percent(self):
        if not self.total_classes:
            return 0
        return min(100, round((self.completed_classes / self.total_classes) * 100))

    @property
    def progress_percentage(self):
        return self.progress_percent

    @property
    def is_complete(self):
        return self.completed_classes >= self.total_classes

    @classmethod
    def build_fresh_classes_data(cls, total_classes: int) -> list:
        total_classes = int(total_classes or 0)
        if total_classes < 1:
            raise ValueError('total_classes must be >= 1')
        if total_classes > 500:
            raise ValueError('total_classes exceeds maximum of 500')
        return [
            {"class_no": i, "completed": False, "date": None, "topic": ""}
            for i in range(1, total_classes + 1)
        ]

