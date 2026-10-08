"""
Cycles App

AttendanceCycle — the shared billing/attendance cycle of a tuition group.
Cycle           — legacy per-student 1-on-1 cycle, kept read-compatible for old data.

Tracks dynamic class attendance per billing cycle.
Key design decisions:
- fee_snapshot & total_classes snapshot values at cycle creation so that
  profile edits don't retroactively alter historical financial data.
- Partial UniqueConstraint ensures exactly ONE active cycle per student.
- classes_data is a structured JSON array, one entry per class.
"""
import uuid
from decimal import Decimal
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
    The shared attendance & billing cycle of a tuition group.

    One ACTIVE cycle exists per tuition and every enrolled student sees the
    same one: marking class #3 complete marks it for the whole group.

    `fee_snapshot` / `total_classes` mirror the tuition while the cycle is
    active and are frozen once it is archived, so later edits to the tuition
    never rewrite earnings history.

    Earnings: (fee_snapshot / total_classes) * completed_classes
    """

    MAX_CLASSES = 500

    class Status(models.TextChoices):
        ACTIVE = 'ACTIVE', 'Active'
        ARCHIVED = 'ARCHIVED', 'Archived'

    id = models.UUIDField(
        primary_key=True, default=uuid.uuid4, editable=False
    )
    # Kept alongside `tuition` so archived earnings survive a deleted tuition.
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
    tuition = models.ForeignKey(
        'students.Tuition',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='cycles',
        verbose_name='Tuition',
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
        verbose_name='Total Fee Snapshot',
        help_text="The tuition's total_fee for this cycle (whole group)."
    )
    total_classes = models.PositiveIntegerField(
        default=12,
        validators=[MinValueValidator(1)],
        verbose_name='Total Classes',
        help_text="The tuition's cycle_length for this cycle."
    )
    classes_data = models.JSONField(
        default=list,
        verbose_name='Classes Attendance Data',
        help_text='[{"class_no": 1, "completed": true, "date": "2026-10-06T10:00:00Z", "topic": "..."}]'
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
        ordering = ['tuition', '-cycle_number']
        constraints = [
            models.UniqueConstraint(
                fields=['tuition'],
                condition=models.Q(status='ACTIVE'),
                name='unique_active_attendance_cycle_per_tuition'
            )
        ]

    def __str__(self):
        title = self.tuition.title if self.tuition_id else 'Deleted tuition'
        return f'{title} — Cycle #{self.cycle_number} ({self.status})'

    # ── Lifecycle ────────────────────────────────────────────────────────────

    @classmethod
    def build_fresh_classes_data(cls, total_classes: int) -> list:
        total_classes = int(total_classes or 0)
        if total_classes < 1:
            raise ValueError('total_classes must be >= 1')
        if total_classes > cls.MAX_CLASSES:
            raise ValueError(f'total_classes exceeds maximum of {cls.MAX_CLASSES}')
        return [
            {"class_no": i, "completed": False, "date": None, "topic": ""}
            for i in range(1, total_classes + 1)
        ]

    @classmethod
    def start_for(cls, tuition, cycle_number=None):
        """Create a fresh ACTIVE cycle for a tuition, snapshotting its fee and length."""
        if cycle_number is None:
            last = cls.objects.filter(tuition=tuition).aggregate(m=models.Max('cycle_number'))['m'] or 0
            cycle_number = last + 1
        return cls.objects.create(
            tuition=tuition,
            tutor=tuition.tutor,
            cycle_number=cycle_number,
            fee_snapshot=tuition.total_fee,
            total_classes=tuition.cycle_length,
            classes_data=cls.build_fresh_classes_data(tuition.cycle_length),
            status=cls.Status.ACTIVE,
        )

    @classmethod
    def ensure_active(cls, tuition):
        """Return the tuition's ACTIVE cycle, creating it if the group has none yet."""
        return cls.objects.filter(tuition=tuition, status=cls.Status.ACTIVE).first() or cls.start_for(tuition)

    @staticmethod
    def _class_no(item):
        try:
            return int(item.get('class_no') or item.get('classNo') or 0)
        except (TypeError, ValueError):
            return 0

    @property
    def highest_completed_class_no(self) -> int:
        return max((self._class_no(c) for c in self.classes_data if c.get('completed')), default=0)

    def sync_with_tuition(self, save=True):
        """
        Bring an ACTIVE cycle in line with its tuition after the tutor edits the
        fee or cycle length. Completed classes are never dropped: shrinking below
        the highest completed class raises ValueError.
        """
        if self.status != self.Status.ACTIVE or not self.tuition_id:
            return self
        tuition = self.tuition
        new_total = int(tuition.cycle_length)
        if new_total < self.highest_completed_class_no:
            raise ValueError(
                f'Cycle length cannot be less than {self.highest_completed_class_no}: '
                f'class #{self.highest_completed_class_no} is already completed in the current cycle.'
            )
        by_no = {self._class_no(c): c for c in self.classes_data}
        self.classes_data = [
            by_no.get(i) or {"class_no": i, "completed": False, "date": None, "topic": ""}
            for i in range(1, new_total + 1)
        ]
        self.total_classes = new_total
        self.fee_snapshot = tuition.total_fee
        if save:
            self.save(update_fields=['classes_data', 'total_classes', 'fee_snapshot', 'updated_at'])
        return self

    def mark_class(self, class_no, completed, date=None, topic=''):
        """
        Check or uncheck one class for the whole group and date-stamp it.
        Mutates classes_data in memory; the caller saves (inside a row lock).
        """
        from django.utils import timezone
        class_no = int(class_no)
        if class_no < 1 or class_no > self.total_classes:
            raise ValueError(f'Class number {class_no} exceeds cycle length of {self.total_classes}.')
        if completed:
            if hasattr(date, 'isoformat'):
                date_iso = date.isoformat()
            elif isinstance(date, str) and date:
                date_iso = date
            else:
                date_iso = timezone.now().isoformat()
        else:
            date_iso = None

        classes_data = list(self.classes_data or [])
        entry = next((c for c in classes_data if self._class_no(c) == class_no), None)
        if entry is None:
            entry = {'class_no': class_no, 'topic': ''}
            classes_data.append(entry)
            classes_data.sort(key=self._class_no)
        entry['completed'] = bool(completed)
        entry['date'] = date_iso
        if not completed:
            entry['topic'] = ''
        elif topic:
            entry['topic'] = topic
        self.classes_data = classes_data
        return entry

    # ── Progress (safe for students) ─────────────────────────────────────────

    @property
    def completed_classes(self):
        """Count of classes marked as completed."""
        return sum(1 for c in self.classes_data if c.get('completed', False))

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

    # ── Money (tutor only — never serialize these for students) ──────────────

    @property
    def total_fee(self):
        return Decimal(str(self.fee_snapshot or '0.00'))

    @property
    def per_class_rate(self):
        if not self.total_classes:
            return Decimal('0.00')
        return (self.total_fee / Decimal(self.total_classes)).quantize(Decimal('0.01'))

    @property
    def earned_revenue(self):
        """(total_fee / cycle_length) * completed_classes, capped at total_fee."""
        if not self.total_classes:
            return Decimal('0.00')
        completed = min(self.completed_classes, self.total_classes)
        return (self.total_fee * Decimal(completed) / Decimal(self.total_classes)).quantize(Decimal('0.01'))

    @property
    def pending_balance(self):
        return max(Decimal('0.00'), (self.total_fee - self.earned_revenue).quantize(Decimal('0.01')))
