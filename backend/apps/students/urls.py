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
)

router = DefaultRouter()
router.register(r'batches', TuitionBatchViewSet, basename='tuition-batch')
router.register(r'tuitions', TuitionViewSet, basename='tuition')
router.register(r'connections', ConnectionRequestViewSet, basename='connection')

urlpatterns = [
    path('students/', StudentListCreateView.as_view(), name='student-list-create'),
    path('students/unassigned/', UnassignedStudentsView.as_view(), name='student-unassigned'),
    path('students/<uuid:pk>/', StudentDetailView.as_view(), name='student-detail'),
    path('students/<uuid:pk>/toggle_active/', StudentToggleActiveView.as_view(), name='student-toggle-active'),
    path('students/<uuid:pk>/reset_password/', StudentResetPasswordView.as_view(), name='student-reset-password'),
    path('', include(router.urls)),
]
