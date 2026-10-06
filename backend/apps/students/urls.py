"""Students URL Patterns"""
from django.urls import path
from .views import StudentListCreateView, StudentDetailView, StudentToggleActiveView

urlpatterns = [
    path('students/', StudentListCreateView.as_view(), name='student-list-create'),
    path('students/<uuid:pk>/', StudentDetailView.as_view(), name='student-detail'),
    path('students/<uuid:pk>/toggle_active/', StudentToggleActiveView.as_view(), name='student-toggle-active'),
]
