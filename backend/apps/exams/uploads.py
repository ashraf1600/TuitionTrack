"""
One set of rules for every file a user can upload (exam media, answer sheets,
homework submissions): allowed type, size, and content that really is what its
name says. Keeping it in one place means a new upload path cannot forget a check.
"""
import os

from django.conf import settings

ALLOWED_EXTENSIONS = {'.png', '.jpg', '.jpeg', '.webp', '.pdf'}
ALLOWED_CONTENT_TYPES = {'image/png', 'image/jpeg', 'image/webp', 'application/pdf'}


class UploadRejected(ValueError):
    """The file must not be stored; the message is safe to show to the user."""


def _matches_extension(ext, header):
    if ext == '.png':
        return header.startswith(b'\x89PNG\r\n\x1a\n')
    if ext in ('.jpg', '.jpeg'):
        return header.startswith(b'\xff\xd8\xff')
    if ext == '.webp':
        return header.startswith(b'RIFF') and header[8:12] == b'WEBP'
    if ext == '.pdf':
        return header.startswith(b'%PDF')
    return False


def max_upload_bytes():
    return int(getattr(settings, 'MAX_UPLOAD_SIZE_MB', 10)) * 1024 * 1024


def validate_upload(uploaded_file):
    """
    Raise UploadRejected unless the file is a non-empty PNG/JPEG/WebP/PDF within
    the size limit whose first bytes match its extension (this blocks HTML or
    script files renamed to .png). Leaves the file positioned at the start.
    """
    if uploaded_file is None:
        raise UploadRejected('No file provided.')
    max_mb = int(getattr(settings, 'MAX_UPLOAD_SIZE_MB', 10))
    if not uploaded_file.size:
        raise UploadRejected('Empty file is not allowed.')
    if uploaded_file.size > max_upload_bytes():
        raise UploadRejected(f'File exceeds maximum size limit of {max_mb}MB ({uploaded_file.size} bytes).')

    _, ext = os.path.splitext(uploaded_file.name or '')
    ext = ext.lower()
    if ext not in ALLOWED_EXTENSIONS:
        allowed = ', '.join(sorted(ALLOWED_EXTENSIONS))
        raise UploadRejected(f'Invalid file format "{ext}". Allowed formats: {allowed}')

    content_type = (getattr(uploaded_file, 'content_type', '') or '').split(';')[0].strip().lower()
    # Some phones send a generic type; the content check below is what really counts.
    if content_type and content_type != 'application/octet-stream' and content_type not in ALLOWED_CONTENT_TYPES:
        raise UploadRejected(f'Invalid content type "{content_type}".')

    uploaded_file.seek(0)
    header = uploaded_file.read(16)
    uploaded_file.seek(0)
    if not _matches_extension(ext, header):
        raise UploadRejected('File content does not match its extension.')
    return uploaded_file
