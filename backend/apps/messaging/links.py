"""Who may message whom: a tutor and the students who belong to them."""
from django.contrib.auth import get_user_model


def tutor_ids_of(student):
    """Accepted requests, the tutor who made the account, and tutors whose tuition the student is in."""
    from apps.students.views import _my_tutor_ids
    return _my_tutor_ids(student)


def student_ids_of(tutor):
    """The same links, seen from the tutor's side."""
    from apps.students.models import ConnectionRequest, TuitionEnrollment
    User = get_user_model()
    ids = set(ConnectionRequest.objects.filter(
        tutor=tutor, status=ConnectionRequest.Status.ACCEPTED,
    ).values_list('student_id', flat=True))
    ids |= set(TuitionEnrollment.objects.filter(
        tuition__tutor=tutor, is_active=True,
    ).values_list('student_id', flat=True))
    ids |= set(User.objects.filter(tutor=tutor, role=User.Role.STUDENT).values_list('id', flat=True))
    return ids


def linked_ids(user):
    if user.role == 'TUTOR':
        return student_ids_of(user)
    if user.role == 'STUDENT':
        return tutor_ids_of(user)
    return set()


def are_linked(tutor, student):
    return student.id in student_ids_of(tutor)
