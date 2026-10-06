"""Students & Tuition Batches URL Patterns"""
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import (
    StudentListCreateView,
    StudentDetailView,
    StudentToggleActiveView,
    TuitionBatchViewSet,
)

router = DefaultRouter()
router.register(r'batches', TuitionBatchViewSet, basename='tuition-batch')

urlpatterns = [
    path('students/', StudentListCreateView.as_view(), name='student-list-create'),
    path('students/<uuid:pk>/', StudentDetailView.as_view(), name='student-detail'),
    path('students/<uuid:pk>/toggle_active/', StudentToggleActiveView.as_view(), name='student-toggle-active'),
    path('', include(router.urls)),
]
