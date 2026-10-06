"""
Authentication App — Custom User Model

Extends AbstractUser to support two roles: TUTOR and STUDENT.
- Tutors self-register and are the top-level tenant.
- Students are created by tutors and scoped strictly to their tutor.
"""
import uuid
from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils.translation import gettext_lazy as _


class CustomUser(AbstractUser):
    """
    Custom User model extending AbstractUser.
    Replaces the default integer PK with UUID for IDOR prevention.
    """

    class Role(models.TextChoices):
        TUTOR = 'TUTOR', _('Tutor')
        STUDENT = 'STUDENT', _('Student')

    id = models.UUIDField(
        primary_key=True,
        default=uuid.uuid4,
        editable=False,
        verbose_name='UUID'
    )
    email = models.EmailField(
        _('email address'),
        blank=True,
    )
    role = models.CharField(
        max_length=10,
        choices=Role.choices,
        default=Role.TUTOR,
        db_index=True,
        verbose_name='User Role'
    )
    # Self-referential FK: null for Tutors, set to tutor's user for Students.
    tutor = models.ForeignKey(
        'self',
        null=True,
        blank=True,
        on_delete=models.CASCADE,
        related_name='students',
        verbose_name='Parent Tutor',
        help_text='Null for Tutors. Required for Students, points to their managing tutor.'
    )
    # Selected tutor for students during self-registration (unassigned prospective students)
    selected_tutor = models.ForeignKey(
        'self',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='prospective_students',
        limit_choices_to={'role': Role.TUTOR},
        verbose_name='Selected Tutor',
        help_text='Selected tutor for students during self-registration.'
    )
    phone = models.CharField(max_length=20, blank=True, verbose_name='Phone Number')

    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'User'
        verbose_name_plural = 'Users'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.get_full_name() or self.username} ({self.role})'

    @property
    def is_tutor(self):
        return self.role == self.Role.TUTOR

    @property
    def is_student(self):
        return self.role == self.Role.STUDENT
