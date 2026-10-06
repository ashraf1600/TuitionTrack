"""
Custom DRF Permission Classes for TuitionTrack

These permissions enforce role-based access control (RBAC) at the view level.
They work in conjunction with the TenantScopedViewSet to enforce multi-tenancy.
"""
from rest_framework.permissions import BasePermission


class IsTutor(BasePermission):
    """
    Grants access only to authenticated users with role='TUTOR'.
    Used for: student management, cycle control, exam authoring, grading.
    """
    message = 'Access denied. Only tutors can perform this action.'

    def has_permission(self, request, view):
        return (
            request.user
            and request.user.is_authenticated
            and request.user.role == 'TUTOR'
        )


class IsStudent(BasePermission):
    """
    Grants access only to authenticated users with role='STUDENT'.
    Used for: taking exams, viewing own progress.
    """
    message = 'Access denied. Only students can perform this action.'

    def has_permission(self, request, view):
        return (
            request.user
            and request.user.is_authenticated
            and request.user.role == 'STUDENT'
        )


class IsTutorOrStudent(BasePermission):
    """
    Grants access to both tutors and students. Used on read endpoints
    that serve different data depending on the caller's role.
    """
    message = 'Access denied. Authentication required.'

    def has_permission(self, request, view):
        return (
            request.user
            and request.user.is_authenticated
            and request.user.role in ('TUTOR', 'STUDENT')
        )


class IsOwnerTutor(BasePermission):
    """
    Object-level permission: grants access only if the requesting tutor
    owns the object being accessed. Requires the model to have a `tutor` field.
    """
    message = 'Access denied. You do not own this resource.'

    def has_object_permission(self, request, view, obj):
        if not request.user.is_authenticated:
            return False
        if request.user.role == 'TUTOR':
            return getattr(obj, 'tutor_id', None) == request.user.id
        return False


class IsAssignedStudent(BasePermission):
    """
    Object-level permission: grants access if the student is the one
    the resource is assigned to. Requires the model to have a `student` field.
    """
    message = 'Access denied. This resource is not assigned to you.'

    def has_object_permission(self, request, view, obj):
        if not request.user.is_authenticated:
            return False
        if request.user.role == 'STUDENT':
            return getattr(obj, 'student_id', None) == request.user.id
        return False
