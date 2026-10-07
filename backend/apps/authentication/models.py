"""
Authentication App — Custom User Model

Extends AbstractUser to support two roles: TUTOR and STUDENT.
- Tutors self-register and are the top-level tenant.
- Students are created by tutors and scoped strictly to their tutor.
"""
import uuid
import secrets
import string
from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils.translation import gettext_lazy as _


def _generate_tutor_code():
    """Generate a unique, human-readable 6-character alphanumeric tutor code."""
    alphabet = string.ascii_uppercase + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(6))


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
    must_change_password = models.BooleanField(
        default=False,
        verbose_name='Must Change Password',
        help_text='Set when someone else chose the password (tutor-created account or tutor reset). '
                  'The user is asked for a new one at next sign-in.',
    )
    # Unique invite code for tutors; students enter this code to send a connection request.
    tutor_code = models.CharField(
        max_length=8,
        unique=True,
        null=True,
        blank=True,
        db_index=True,
        verbose_name='Tutor Code',
        help_text='Auto-generated 6-char invite code for tutors. Students use this to connect.',
    )
    # Profile picture (stored via MEDIA_ROOT; Pillow required).
    profile_picture = models.ImageField(
        upload_to='profile_pictures/',
        null=True,
        blank=True,
        verbose_name='Profile Picture',
    )

    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'User'
        verbose_name_plural = 'Users'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.get_full_name() or self.username} ({self.role})'

    def save(self, *args, **kwargs):
        # Auto-assign a unique tutor_code when a Tutor account is first created.
        if self.role == self.Role.TUTOR and not self.tutor_code:
            for _ in range(20):  # retry up to 20 times to avoid collision
                candidate = _generate_tutor_code()
                if not CustomUser.objects.filter(tutor_code=candidate).exists():
                    self.tutor_code = candidate
                    break
        super().save(*args, **kwargs)

    @property
    def is_tutor(self):
        return self.role == self.Role.TUTOR

    @property
    def is_student(self):
        return self.role == self.Role.STUDENT

    @property
    def profile_picture_url(self):
        """Returns an absolute URL for the profile picture, or None."""
        if self.profile_picture:
            return self.profile_picture.url
        return None
