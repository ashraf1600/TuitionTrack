"""Compression for API responses."""
from django.middleware.gzip import GZipMiddleware


class ApiGZipMiddleware(GZipMiddleware):
    """
    gzip for API answers, which are mostly long JSON lists (homework, exams,
    cycles) and shrink 5-10x. Answers under /api/v1/auth/ carry tokens, and
    compressing secrets next to attacker-influenced text is what the BREACH
    attack needs, so those are sent as they are.
    """

    def process_response(self, request, response):
        if request.path.startswith('/api/v1/auth/'):
            return response
        return super().process_response(request, response)
