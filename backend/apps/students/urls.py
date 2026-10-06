"""Students & Tuition Batches URL Patterns"""
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    StudentListCreateView,
    StudentDetailView,
    StudentToggleActiveView,
    TuitionBatchViewSet,
    TuitionViewSet,
    UnassignedStudentsView,
)

router = DefaultRouter()
router.register(r'batches', TuitionBatchViewSet, basename='tuition-batch')
router.register(r'tuitions', TuitionViewSet, basename='tuition')

urlpatterns = [
    path('students/', StudentListCreateView.as_view(), name='student-list-create'),
    path('students/unassigned/', UnassignedStudentsView.as_view(), name='student-unassigned'),
    path('students/<uuid:pk>/', StudentDetailView.as_view(), name='student-detail'),
    path('students/<uuid:pk>/toggle_active/', StudentToggleActiveView.as_view(), name='student-toggle-active'),
    path('', include(router.urls)),
]
