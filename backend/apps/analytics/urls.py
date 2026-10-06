"""Analytics URL patterns"""
from django.urls import path
from .views import WalletAnalyticsView, NotificationsView

urlpatterns = [
    path('analytics/wallet/', WalletAnalyticsView.as_view(), name='wallet-analytics'),
    path('notifications/', NotificationsView.as_view(), name='notifications'),
]
