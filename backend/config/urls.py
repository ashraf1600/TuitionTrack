"""TuitionTrack Backend — Root URL Configuration"""
from django.contrib import admin
from django.urls import path, include, re_path
from django.conf import settings
from django.conf.urls.static import static

from config.api import api_not_found
from config.meta import MetaView

handler500 = 'config.api.server_error'

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/v1/auth/', include('apps.authentication.urls')),
    path('api/v1/', include('apps.students.urls')),
    path('api/v1/', include('apps.cycles.urls')),
    path('api/v1/', include('apps.analytics.urls')),
    path('api/v1/', include('apps.exams.urls')),
    path('api/v1/meta/', MetaView.as_view(), name='api-meta'),
    # Anything else under /api/ is a JSON 404, in DEBUG too.
    re_path(r'^api/', api_not_found),
]

# Serve media via Django only in DEBUG. In production serve via Nginx/S3
# with authenticated views — never expose answer-sheet uploads publicly.
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
