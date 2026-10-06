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
