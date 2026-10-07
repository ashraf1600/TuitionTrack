"""Authentication URL Patterns"""
from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .views import (
    CustomTokenObtainPairView, TutorRegisterView, StudentRegisterView, MeView, TutorDirectoryView,
    ChangePasswordView, PasswordResetRequestView, PasswordResetConfirmView, LogoutView, LogoutAllView,
)

urlpatterns = [
    path('token/', CustomTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('logout/', LogoutView.as_view(), name='logout'),
    path('logout-all/', LogoutAllView.as_view(), name='logout_all'),
    path('register/', TutorRegisterView.as_view(), name='tutor_register'),
    path('register/student/', StudentRegisterView.as_view(), name='student_register'),
    path('tutors/', TutorDirectoryView.as_view(), name='tutor_directory'),
    path('me/', MeView.as_view(), name='user_me'),
    path('change-password/', ChangePasswordView.as_view(), name='change_password'),
    path('password-reset/', PasswordResetRequestView.as_view(), name='password_reset'),
    path('password-reset/confirm/', PasswordResetConfirmView.as_view(), name='password_reset_confirm'),
]
