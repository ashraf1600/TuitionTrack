"""Analytics URL patterns — stubs for Phase 3 implementation."""
from django.urls import path, include
from rest_framework.routers import DefaultRouter

router = DefaultRouter()

urlpatterns = [
    path('analytics/', include(router.urls)),
]
