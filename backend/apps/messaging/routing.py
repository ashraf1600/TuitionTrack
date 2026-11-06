from django.urls import path

from .consumers import LiveConsumer

websocket_urlpatterns = [
    path('ws/', LiveConsumer.as_asgi()),
]
