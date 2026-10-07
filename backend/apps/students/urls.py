"""Students & Tuition Batches URL Patterns"""
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    StudentListCreateView,
    StudentDetailView,
    StudentToggleActiveView,
    StudentResetPasswordView,
    TuitionBatchViewSet,
    TuitionViewSet,
    ConnectionRequestViewSet,
    UnassignedStudentsView,
    # New: tutor-code invite & student dashboard
    TutorCodeConnectView,
    ConnectedTutorsView,
    TutorDetailForStudentView,
    HomeworkViewSet,
)

router = DefaultRouter()
router.register(r'batches', TuitionBatchViewSet, basename='tuition-batch')
router.register(r'tuitions', TuitionViewSet, basename='tuition')
router.register(r'connections', ConnectionRequestViewSet, basename='connection')
router.register(r'homework', HomeworkViewSet, basename='homework')

urlpatterns = [
    # Students (tutor-managed)
    path('students/', StudentListCreateView.as_view(), name='student-list-create'),
    path('students/unassigned/', UnassignedStudentsView.as_view(), name='student-unassigned'),
    path('students/<uuid:pk>/', StudentDetailView.as_view(), name='student-detail'),
    path('students/<uuid:pk>/toggle_active/', StudentToggleActiveView.as_view(), name='student-toggle-active'),
    path('students/<uuid:pk>/reset_password/', StudentResetPasswordView.as_view(), name='student-reset-password'),

    # Student → Tutor connection via invite code
    path('connections/by-code/', TutorCodeConnectView.as_view(), name='connect-by-code'),

    # Student dashboard: connected tutors
    path('my-tutors/', ConnectedTutorsView.as_view(), name='my-tutors'),
    path('my-tutors/<uuid:tutor_id>/', TutorDetailForStudentView.as_view(), name='tutor-detail-for-student'),

    path('', include(router.urls)),
]
