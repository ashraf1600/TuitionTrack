"""
ASGI entry point: the REST API (HTTP) and the live connection (WebSocket at /ws/).

Run with:  uvicorn config.asgi:application --host 0.0.0.0 --port 8000
The live connection signs in with its first message, not a cookie, so no origin check is needed.
"""
import os

from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django_http = get_asgi_application()

from channels.routing import ProtocolTypeRouter, URLRouter  # noqa: E402 - Django must be set up first

from apps.messaging.routing import websocket_urlpatterns  # noqa: E402

application = ProtocolTypeRouter({
    'http': django_http,
    'websocket': URLRouter(websocket_urlpatterns),
})
