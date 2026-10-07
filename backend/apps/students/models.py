"""
Students App — StudentProfile Model

Stores per-student academic and financial configuration.
Each StudentProfile is tied to a User with role='STUDENT'.
"""
import uuid
from django.db import models
from django.core.validators import MinValueValidator
from django.conf import settings


class StudentProfile(models.Model):
    """
    Extended profile for student users containing tuition and cycle configuration.
    Financial fields here are the *current* settings; Cycle models snapshot these
    values at creation time to prevent retroactive earnings distortion.
    """
    id = models.UUIDField(
        primary_key=True, default=uuid.uuid4, editable=False
    )
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='student_profile',
        limit_choices_to={'role': 'STUDENT'},
    )
    grade_level = models.CharField(
        max_length=50, blank=True,
        verbose_name='Grade / Class Level',
        help_text='e.g., Grade 10, A-Level, University Year 2'
    )
    institution = models.CharField(max_length=150, blank=True, verbose_name='School / College')
    parent_name = models.CharField(max_length=100, blank=True, verbose_name="Parent's Name")
    parent_phone = models.CharField(max_length=20, blank=True, verbose_name="Parent's Phone")
    address = models.CharField(max_length=255, blank=True, default='', verbose_name='Address')
    tuition_fee = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=0.00,
        validators=[MinValueValidator(0)],
        verbose_name='Monthly Tuition Fee',
        help_text='Fee per complete cycle (not monthly). Snapshotted into each Cycle on creation.'
    )
    cycle_length = models.PositiveIntegerField(
        default=12,
        validators=[MinValueValidator(1)],
        verbose_name='Cycle Length (Classes)',
        help_text='Number of classes per payment cycle (min 1). e.g., 8, 12, 16.'
    )
    notes = models.TextField(blank=True, verbose_name='Tutor Notes')

    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Student Profile'
        verbose_name_plural = 'Student Profiles'
        ordering = ['user__first_name', 'user__last_name']

    def __str__(self):
        return f'{self.user.get_full_name() or self.user.username} — Profile'



class Tuition(models.Model):
    """
    A tuition group (batch) run by one tutor for one or many students.

    The group — not the individual student — owns the billing cycle: every
    enrolled student shares the same AttendanceCycle, and `total_fee` is what
    the tutor earns for one complete cycle of the whole group.
    """
    id = models.UUIDField(
        primary_key=True, default=uuid.uuid4, editable=False
    )
    tutor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='tuitions',
        limit_choices_to={'role': 'TUTOR'},
        db_index=True,
        verbose_name='Tutor',
    )
    title = models.CharField(max_length=200, verbose_name='Tuition Title')
    subject = models.CharField(max_length=150, blank=True, verbose_name='Subject')
    description = models.TextField(blank=True, verbose_name='Description')
    cycle_length = models.PositiveIntegerField(
        default=12,
        validators=[MinValueValidator(1)],
        verbose_name='Cycle Length (Classes)',
        help_text='Dynamic class count per cycle (e.g., 8, 12, 16).'
    )
    total_fee = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=0.00,
        validators=[MinValueValidator(0)],
        verbose_name='Total Fee per Cycle (whole group)',
        help_text='What the tutor earns for one complete cycle of this tuition.'
    )
    routine = models.JSONField(
        default=list,
        verbose_name='Weekly Routine',
        help_text='List of {"day": str, "start_time": str, "end_time": str}'
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Tuition'
        verbose_name_plural = 'Tuitions'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.title} — Tutor: {self.tutor.username}'

    @property
    def enrolled_students_count(self):
        return self.enrollments.filter(is_active=True, student__is_active=True).count()

    @property
    def active_cycle(self):
        """The single shared cycle every enrolled student currently sees."""
        return self.cycles.filter(status='ACTIVE').first()


class TuitionEnrollment(models.Model):
    """
    Connects a Student to a Tuition.
    A student can be enrolled in multiple tuitions under one or more tutors.
    """
    id = models.UUIDField(
        primary_key=True, default=uuid.uuid4, editable=False
    )
    tuition = models.ForeignKey(
        Tuition,
        on_delete=models.CASCADE,
        related_name='enrollments',
        verbose_name='Tuition'
    )
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='enrolled_tuitions',
        limit_choices_to={'role': 'STUDENT'},
        verbose_name='Student'
    )
    is_active = models.BooleanField(
        default=True,
        verbose_name='Is Active Enrollment'
    )
    left_at = models.DateTimeField(
        null=True,
        blank=True,
        verbose_name='Left At'
    )
    joined_at = models.DateTimeField(auto_now_add=True)


    class Meta:
        verbose_name = 'Tuition Enrollment'
        verbose_name_plural = 'Tuition Enrollments'
        unique_together = ('tuition', 'student')
        ordering = ['-joined_at']

    def __str__(self):
        return f'{self.student.get_full_name() or self.student.username} in {self.tuition.title}'


class ConnectionRequest(models.Model):
    """
    A student's request to study with a tutor.

    Created when a student picks a tutor (at registration or later). It sits
    in the tutor's inbox as PENDING until the tutor accepts it — usually by
    assigning the student to a tuition — or rejects it.
    """

    class Status(models.TextChoices):
        PENDING = 'PENDING', 'Pending'
        ACCEPTED = 'ACCEPTED', 'Accepted'
        REJECTED = 'REJECTED', 'Rejected'

    id = models.UUIDField(
        primary_key=True, default=uuid.uuid4, editable=False
    )
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='connection_requests',
        limit_choices_to={'role': 'STUDENT'},
        verbose_name='Student'
    )
    tutor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='incoming_connection_requests',
        limit_choices_to={'role': 'TUTOR'},
        verbose_name='Tutor'
    )
    status = models.CharField(
        max_length=10,
        choices=Status.choices,
        default=Status.PENDING,
        db_index=True,
        verbose_name='Status'
    )
    message = models.CharField(max_length=500, blank=True, default='', verbose_name='Message to Tutor')
    created_at = models.DateTimeField(auto_now_add=True)
    responded_at = models.DateTimeField(null=True, blank=True, verbose_name='Responded At')

    class Meta:
        verbose_name = 'Connection Request'
        verbose_name_plural = 'Connection Requests'
        ordering = ['-created_at']
        constraints = [
            models.UniqueConstraint(
                fields=['student', 'tutor'],
                name='unique_connection_request_per_student_tutor'
            )
        ]

    def __str__(self):
        return f'{self.student.username} -> {self.tutor.username} ({self.status})'


class Homework(models.Model):
    """
    Homework assigned by a tutor to a student (or a tuition group).

    Business rules:
      - Only a TUTOR can create / edit / mark homework as evaluated.
      - A student can optionally submit an online URL.
      - `is_evaluated` is ONLY set to True by the tutor (physical review OR online check).
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    tutor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='assigned_homework',
        limit_choices_to={'role': 'TUTOR'},
        verbose_name='Tutor',
    )
    # Either student-level (individual) or tuition-level (whole group).
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='received_homework',
        limit_choices_to={'role': 'STUDENT'},
        verbose_name='Student',
        help_text='Null when assigned to an entire tuition group.',
    )
    tuition = models.ForeignKey(
        'Tuition',
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='homework_assignments',
        verbose_name='Tuition Group',
        help_text='Null when assigned to an individual student.',
    )

    title = models.CharField(max_length=255, verbose_name='Title')
    description = models.TextField(blank=True, verbose_name='Description / Instructions')
    due_date = models.DateTimeField(verbose_name='Due Date & Time', db_index=True)

    # Student-side optional submission.
    submitted_online_url = models.URLField(
        max_length=1000,
        blank=True,
        default='',
        verbose_name='Submitted Online URL',
        help_text='Student may paste a link (Google Doc, GitHub, etc.) as their submission.',
    )
    submission_file = models.FileField(
        upload_to='homework/%Y/%m/',
        null=True,
        blank=True,
        verbose_name='Submission File',
        help_text='Optional file upload as an alternative to a URL.',
    )
    submitted_at = models.DateTimeField(
        null=True, blank=True, verbose_name='Submitted At'
    )

    # Tutor-side evaluation flag — only the tutor can flip this.
    is_evaluated = models.BooleanField(
        default=False,
        verbose_name='Evaluated / Marked Done',
        help_text='Set True by the tutor after physical or online review.',
    )
    evaluated_at = models.DateTimeField(null=True, blank=True, verbose_name='Evaluated At')
    tutor_feedback = models.TextField(blank=True, verbose_name='Tutor Feedback')

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Homework'
        verbose_name_plural = 'Homework Assignments'
        ordering = ['due_date']

    def __str__(self):
        recipient = (
            self.student.get_full_name() or self.student.username
            if self.student
            else (self.tuition.title if self.tuition else 'Unknown')
        )
        return f'[{self.tutor.username}] {self.title} → {recipient}'


class WeeklyRoutine(models.Model):
    """Recurring weekly slot: Tutor -> Student or whole Tuition group."""
    class Day(models.TextChoices):
        SATURDAY = 'SATURDAY', 'Saturday'
        SUNDAY = 'SUNDAY', 'Sunday'
        MONDAY = 'MONDAY', 'Monday'
        TUESDAY = 'TUESDAY', 'Tuesday'
        WEDNESDAY = 'WEDNESDAY', 'Wednesday'
        THURSDAY = 'THURSDAY', 'Thursday'
        FRIDAY = 'FRIDAY', 'Friday'

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    tutor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='tutor_weekly_routines', limit_choices_to={'role': 'TUTOR'}, db_index=True)
    student = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        null=True, blank=True, related_name='student_weekly_routines',
        limit_choices_to={'role': 'STUDENT'})
    tuition = models.ForeignKey('students.Tuition', on_delete=models.CASCADE,
        null=True, blank=True, related_name='detailed_routines')
    day_of_week = models.CharField(max_length=10, choices=Day.choices, db_index=True)
    start_time = models.TimeField()
    end_time = models.TimeField()
    subject = models.CharField(max_length=150, blank=True)

    class Meta:
        ordering = ['day_of_week', 'start_time']
        constraints = [
            models.CheckConstraint(condition=models.Q(student__isnull=False) | models.Q(tuition__isnull=False),
                name='routine_requires_student_or_tuition'),
            models.CheckConstraint(condition=models.Q(end_time__gt=models.F('start_time')),
                name='routine_end_after_start'),
        ]

    def __str__(self):
        target = self.student.username if self.student else (self.tuition.title if self.tuition else '?')
        return f'{self.tutor.username}: {self.day_of_week} {self.start_time}-{self.end_time} -> {target}'


class ClassSchedule(models.Model):
    """Concrete dated class for the UpcomingClasses list."""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    tutor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        related_name='tutor_class_schedules', limit_choices_to={'role': 'TUTOR'}, db_index=True)
    tuition = models.ForeignKey('students.Tuition', on_delete=models.CASCADE,
        null=True, blank=True, related_name='scheduled_classes')
    student = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
        null=True, blank=True, related_name='student_class_schedules',
        limit_choices_to={'role': 'STUDENT'})
    scheduled_at = models.DateTimeField(db_index=True)
    topic = models.CharField(max_length=255, blank=True)
    is_cancelled = models.BooleanField(default=False)

    class Meta:
        ordering = ['scheduled_at']

    def __str__(self):
        return f'{self.tutor.username} @ {self.scheduled_at:%Y-%m-%d %H:%M}'

