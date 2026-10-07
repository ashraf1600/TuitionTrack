"""GET /api/v1/meta/ — what a client needs to know before it signs anyone in."""
from django.conf import settings
from django.utils import timezone
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

API_VERSION = 'v1'


class MetaView(APIView):
    """
    GET /api/v1/meta/   (public)
    What a client needs before it signs anyone in: the server clock (exam
    timers must follow the server, not the phone), where uploaded files live,
    and the upload limits.
    """
    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request):
        from apps.exams.models import Exam
        from apps.exams.views import MediaUploadView
        return Response({
            'api_version': API_VERSION,
            'server_time': timezone.now(),
            'display_time_zone': settings.DISPLAY_TIME_ZONE,
            # Stored file paths ("/media/…", also inside exam HTML) are relative to this origin.
            'media_base_url': request.build_absolute_uri('/').rstrip('/'),
            'media_url': settings.MEDIA_URL,
            'uploads': {
                'max_size_mb': getattr(settings, 'MAX_UPLOAD_SIZE_MB', 10),
                'extensions': sorted(MediaUploadView.ALLOWED_EXTENSIONS),
                'content_types': sorted(MediaUploadView.ALLOWED_CONTENT_TYPES),
            },
            'result_publish_modes': [choice for choice, _ in Exam.ResultPublishMode.choices],
            'page_size': {'default': 20, 'max': 1000, 'query_param': 'page_size'},
        })
