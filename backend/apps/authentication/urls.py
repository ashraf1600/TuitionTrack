"""Authentication URL Patterns"""
from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .views import CustomTokenObtainPairView, TutorRegisterView, MeView

urlpatterns = [
    path('token/', CustomTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('register/', TutorRegisterView.as_view(), name='tutor_register'),
    path('me/', MeView.as_view(), name='user_me'),
]
