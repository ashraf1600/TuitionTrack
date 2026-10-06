"""
Students App — shared business rules

One place for the rules several views and serializers must agree on:
which students a tutor may manage, and what enrolling / unenrolling does.
"""
from django.contrib.auth import get_user_model
from django.db.models import Q
from django.utils import timezone

from .models import ConnectionRequest, TuitionEnrollment

User = get_user_model()

OPEN_REQUEST_STATUSES = (ConnectionRequest.Status.PENDING, ConnectionRequest.Status.ACCEPTED)


def manageable_students(tutor):
    """
    Students a tutor may enrol, examine or list: the ones they created or
    accepted, plus students with a pending or accepted connection request.
    A rejected request gives no access.
    """
    return User.objects.filter(role=User.Role.STUDENT).filter(
        Q(tutor=tutor)
        | Q(connection_requests__tutor=tutor, connection_requests__status__in=OPEN_REQUEST_STATUSES)
    ).distinct()


def can_manage(tutor, student) -> bool:
    return manageable_students(tutor).filter(pk=student.pk).exists()


def accept_connection(tutor, student):
    """Mark the student's request to this tutor as accepted (if there is one)."""
    ConnectionRequest.objects.filter(
        tutor=tutor, student=student, status=ConnectionRequest.Status.PENDING
    ).update(status=ConnectionRequest.Status.ACCEPTED, responded_at=timezone.now())
    if student.tutor_id is None:
        student.tutor = tutor
        student.save(update_fields=['tutor'])


def enroll_student(tuition, student):
    """
    Put a student into a tuition group. They immediately share the group's
    current cycle — no per-student cycle is created.
    """
    from apps.cycles.models import AttendanceCycle

    enrollment, _ = TuitionEnrollment.objects.get_or_create(tuition=tuition, student=student)
    if not enrollment.is_active or enrollment.left_at:
        enrollment.is_active = True
        enrollment.left_at = None
        enrollment.save(update_fields=['is_active', 'left_at'])
    accept_connection(tuition.tutor, student)
    AttendanceCycle.ensure_active(tuition)
    return enrollment


def unenroll_student(tuition, student):
    """
    Take a student out of a tuition group. The group's cycle and its earnings
    history are untouched — they belong to the tuition, not the student.
    """
    enrollment = TuitionEnrollment.objects.filter(tuition=tuition, student=student).first()
    if enrollment and enrollment.is_active:
        enrollment.is_active = False
        enrollment.left_at = timezone.now()
        enrollment.save(update_fields=['is_active', 'left_at'])
    return enrollment
