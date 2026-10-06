"""TuitionTrack Backend — Root URL Configuration"""
from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/v1/auth/', include('apps.authentication.urls')),
    path('api/v1/', include('apps.students.urls')),
    path('api/v1/', include('apps.cycles.urls')),
    path('api/v1/', include('apps.analytics.urls')),
    path('api/v1/', include('apps.exams.urls')),
]

# Serve media via Django only in DEBUG. In production serve via Nginx/S3
# with authenticated views — never expose answer-sheet uploads publicly.
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
