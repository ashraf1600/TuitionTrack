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


class TuitionBatch(models.Model):
    """
    Represents a tuition group / batch created by a tutor.
    Can contain single or multiple students with a recurring weekly routine.
    """
    id = models.UUIDField(
        primary_key=True, default=uuid.uuid4, editable=False
    )
    tutor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='tuition_batches',
        limit_choices_to={'role': 'TUTOR'},
        db_index=True,
        verbose_name='Tutor',
    )
    name = models.CharField(max_length=255, verbose_name='Tuition / Batch Name')
    subject = models.CharField(max_length=150, blank=True, verbose_name='Subject')
    description = models.TextField(blank=True, verbose_name='Description')
    students = models.ManyToManyField(
        settings.AUTH_USER_MODEL,
        related_name='enrolled_batches',
        limit_choices_to={'role': 'STUDENT'},
        blank=True,
        verbose_name='Enrolled Students',
    )
    # Weekly Routine: [{"day": "Sunday", "time": "18:00"}, {"day": "Tuesday", "time": "18:00"}]
    weekly_routine = models.JSONField(
        default=list,
        verbose_name='Weekly Routine',
        help_text='JSON array of schedule slots: [{"day": "Sunday", "time": "18:00"}]',
    )
    monthly_fee = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=0.00,
        validators=[MinValueValidator(0)],
        verbose_name='Monthly Fee per Student',
    )
    is_active = models.BooleanField(default=True, verbose_name='Is Active')

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Tuition Batch'
        verbose_name_plural = 'Tuition Batches'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.name} ({self.subject}) — Tutor: {self.tutor.username}'


class Tuition(models.Model):
    """
    Tuition-Centric model: represents a distinct tuition or coaching group.
    Defines title, dynamic cycle_length, fee per student per cycle, and weekly routine.
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
    tuition_fee = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=0.00,
        validators=[MinValueValidator(0)],
        verbose_name='Tuition Fee per Student per Cycle'
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
        return self.enrollments.filter(is_active=True).count()


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
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = 'Tuition Enrollment'
        verbose_name_plural = 'Tuition Enrollments'
        unique_together = ('tuition', 'student')
        ordering = ['-joined_at']

    def __str__(self):
        return f'{self.student.get_full_name() or self.student.username} in {self.tuition.title}'

