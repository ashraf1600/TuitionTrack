"""Analytics URL patterns"""
from django.urls import path
from .views import WalletAnalyticsView

urlpatterns = [
    path('analytics/wallet/', WalletAnalyticsView.as_view(), name='wallet-analytics'),
]
