"""
API-wide behaviour shared by every endpoint, so web and mobile clients can
rely on one contract:

  * a request body is always a JSON object (anything else is a clean 400);
  * every error, whatever produced it, carries a human `message` and a
    machine `code` (field errors are also collected under `errors`);
  * unknown /api/ paths and server faults answer in JSON, never HTML.

This module is named in REST_FRAMEWORK settings, so it must not import
rest_framework.views at the top (that would be a circular import).
"""
from django.http import JsonResponse
from rest_framework import exceptions
from rest_framework.parsers import JSONParser
from rest_framework.renderers import JSONRenderer

STATUS_CODES = {
    400: 'invalid_request',
    401: 'not_authenticated',
    403: 'permission_denied',
    404: 'not_found',
    405: 'method_not_allowed',
    406: 'not_acceptable',
    415: 'unsupported_media_type',
    429: 'throttled',
}
# Keys that describe the error itself rather than a field of the request.
GENERAL_KEYS = ('message', 'error', 'detail', 'non_field_errors')


class ObjectJSONParser(JSONParser):
    """JSON bodies must be objects. A bare list, string or number is a client mistake."""

    def parse(self, stream, media_type=None, parser_context=None):
        data = super().parse(stream, media_type=media_type, parser_context=parser_context)
        if not isinstance(data, dict):
            raise exceptions.ParseError('The request body must be a JSON object.')
        return data


def _first_text(value):
    """The first human-readable string inside nested error data."""
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        for key in GENERAL_KEYS:
            if key in value:
                found = _first_text(value[key])
                if found:
                    return found
        for key, item in value.items():
            found = _first_text(item)
            if found:
                return found if key in GENERAL_KEYS else f'{key}: {found}'
    if isinstance(value, (list, tuple)):
        for item in value:
            found = _first_text(item)
            if found:
                return found
    return ''


def error_body(data, status_code):
    """
    Give any error payload the common shape while keeping what was already
    there, so existing clients that read `error`, `detail` or a field name
    keep working:

        {"message": "...", "code": "...", "errors": {field: [...]}, ...original keys}
    """
    default_code = STATUS_CODES.get(status_code, 'server_error' if status_code >= 500 else 'error')
    if isinstance(data, (list, tuple)):
        data = {'non_field_errors': list(data)}
    elif not isinstance(data, dict):
        data = {'detail': str(data)} if data else {}

    body = dict(data)
    field_errors = {
        key: value for key, value in data.items()
        if key not in GENERAL_KEYS + ('code', 'errors', 'messages') and isinstance(value, (list, dict))
    }
    # A field that happens to be called "message" or "code" keeps its errors under `errors`.
    for key in ('message', 'code'):
        if key in data and not isinstance(data[key], str):
            field_errors[key] = data[key]

    if not isinstance(body.get('code'), str) or not body['code']:
        body['code'] = 'validation_error' if (status_code == 400 and field_errors) else default_code
    if not isinstance(body.get('message'), str) or not body['message']:
        body['message'] = _first_text(data) or 'The request could not be completed.'
    if field_errors:
        body['errors'] = field_errors
    return body


class ApiJSONRenderer(JSONRenderer):
    """Renders JSON; error responses are put into the common error shape on the way out."""

    def render(self, data, accepted_media_type=None, renderer_context=None):
        response = (renderer_context or {}).get('response')
        if response is not None and response.status_code >= 400:
            data = error_body(data, response.status_code)
        return super().render(data, accepted_media_type, renderer_context)


def api_exception_handler(exc, context):
    """DRF's handler, plus the precise error code DRF knows about (e.g. `authentication_failed`)."""
    # Imported here: rest_framework.views reads the settings that name this module.
    from rest_framework.views import exception_handler as drf_exception_handler
    response = drf_exception_handler(exc, context)
    if response is None or not isinstance(response.data, dict) or 'code' in response.data:
        return response
    if isinstance(exc, exceptions.ValidationError):
        code = 'validation_error'
    elif isinstance(exc, exceptions.APIException):
        codes = exc.get_codes()
        code = codes if isinstance(codes, str) else None
    else:
        code = None
    if code:
        response.data['code'] = code
    return response


def api_not_found(request, *args, **kwargs):
    """Any /api/ path that matches no route."""
    return JsonResponse(
        error_body({'detail': 'This API endpoint does not exist.'}, 404), status=404,
    )


def server_error(request, *args, **kwargs):
    """handler500: JSON for the API, Django's plain page for everything else."""
    if request.path.startswith('/api/'):
        return JsonResponse(
            error_body({'detail': 'Something went wrong on the server. Please try again.'}, 500), status=500,
        )
    from django.views.defaults import server_error as default_server_error
    return default_server_error(request, *args, **kwargs)
