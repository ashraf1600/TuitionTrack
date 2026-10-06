"""Cycles URL patterns"""
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import CycleViewSet, AttendanceCycleViewSet

router = DefaultRouter()
router.register(r'cycles', CycleViewSet, basename='cycle')
router.register(r'attendance-cycles', AttendanceCycleViewSet, basename='attendance-cycle')

urlpatterns = [
    path('', include(router.urls)),
]
