"""Exams URL patterns"""
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import ExamViewSet, GradeSubmissionView, MediaUploadView

router = DefaultRouter()
router.register(r'exams', ExamViewSet, basename='exam')

urlpatterns = [
    path('', include(router.urls)),
    path('submissions/<uuid:pk>/grade/', GradeSubmissionView.as_view(), name='grade-submission'),
    path('media/upload/', MediaUploadView.as_view(), name='media-upload'),
]
