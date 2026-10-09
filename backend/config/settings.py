"""
TuitionTrack Backend — Django Settings
"""
import os
import sys
from pathlib import Path
from datetime import timedelta
from dotenv import load_dotenv

# ─── Base Directory ───────────────────────────────────────────────────────────
BASE_DIR = Path(__file__).resolve().parent.parent

# ─── Load Environment Variables ───────────────────────────────────────────────
load_dotenv(BASE_DIR / '.env')

# ─── Security ─────────────────────────────────────────────────────────────────
# DEBUG = os.getenv('DEBUG', 'False').lower() in ('true', '1', 't')
# SECRET_KEY = os.getenv('SECRET_KEY')
# if not SECRET_KEY:
#     if DEBUG:
#         import secrets
#         SECRET_KEY = os.getenv('SECRET_KEY', 'dev-secret-key-' + secrets.token_hex(16))
#     else:
#         from django.core.exceptions import ImproperlyConfigured
#         raise ImproperlyConfigured("The SECRET_KEY environment variable must be set in production.")
# ALLOWED_HOSTS = [h.strip() for h in os.getenv('ALLOWED_HOSTS', 'localhost,127.0.0.1,testserver').split(',') if h.strip()]
# # Render tells the service its own public hostname.
# if os.getenv('RENDER_EXTERNAL_HOSTNAME'):
#     ALLOWED_HOSTS.append(os.environ['RENDER_EXTERNAL_HOSTNAME'])
# if DEBUG and not os.getenv('ALLOWED_HOSTS'):
#     # Development only: lets a phone or emulator on the same network reach this computer
#     # (http://<this-PC's-IP>:8000, or http://10.0.2.2:8000 from an Android emulator).
#     ALLOWED_HOSTS = ['*']

# ─── Security ─────────────────────────────────────────────────────────────────

DEBUG = os.getenv('DEBUG', 'False').lower() in ('true', '1', 't')

SECRET_KEY = os.getenv('SECRET_KEY')

if not SECRET_KEY:
    if DEBUG:
        import secrets
        SECRET_KEY = 'dev-secret-key-' + secrets.token_hex(16)
    else:
        from django.core.exceptions import ImproperlyConfigured
        raise ImproperlyConfigured(
            "The SECRET_KEY environment variable must be set in production."
        )


# ─── Allowed Hosts ─────────────────────────────────────────────────────────────
#
# Production:
#   Set ALLOWED_HOSTS in environment variables.
#
# Example:
#   ALLOWED_HOSTS=your-domain.com,www.your-domain.com
#
# Development:
#   The local network IP is allowed so that a phone/emulator can connect.
#

allowed_hosts_env = os.getenv('ALLOWED_HOSTS', '').strip()

if allowed_hosts_env:
    ALLOWED_HOSTS = [
        host.strip()
        for host in allowed_hosts_env.split(',')
        if host.strip()
    ]
else:
    ALLOWED_HOSTS = [
        'localhost',
        '127.0.0.1',
        'testserver',
    ]

    # Development only:
    # Allows a phone on the same Wi-Fi network to access Django.
    # Uses this machine's actual LAN address (not a stale hardcoded one).
    if DEBUG:
        try:
            import socket
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.connect(('8.8.8.8', 80))
                _lan_ip = s.getsockname()[0]
            if _lan_ip and _lan_ip not in ALLOWED_HOSTS:
                ALLOWED_HOSTS.append(_lan_ip)
        except OSError:
            pass


# Render provides its own public hostname.
if os.getenv('RENDER_EXTERNAL_HOSTNAME'):
    ALLOWED_HOSTS.append(os.environ['RENDER_EXTERNAL_HOSTNAME'])
if os.getenv('RENDER') or os.getenv('RENDER_EXTERNAL_HOSTNAME'):
    if '.onrender.com' not in ALLOWED_HOSTS:
        ALLOWED_HOSTS.append('.onrender.com')

# ─── Application Definition ───────────────────────────────────────────────────
DJANGO_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
]

THIRD_PARTY_APPS = [
    'rest_framework',
    'rest_framework_simplejwt',
    # Lets a refresh token be revoked: sign-out, password change, deactivation.
    'rest_framework_simplejwt.token_blacklist',
    'corsheaders',
]

LOCAL_APPS = [
    'apps.authentication',
    'apps.students',
    'apps.cycles',
    'apps.analytics',
    'apps.exams',
]

INSTALLED_APPS = DJANGO_APPS + THIRD_PARTY_APPS + LOCAL_APPS

# ─── Middleware ───────────────────────────────────────────────────────────────
MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    # Serves the admin's CSS/JS in production without a separate web server.
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'

# ─── Database ─────────────────────────────────────────────────────────────────
# Online: PostgreSQL, from DATABASE_URL (e.g. the Supabase "Session pooler" connection string).
# On your own PC, with no DATABASE_URL: the SQLite file next to manage.py.
DATABASE_URL = os.getenv('DATABASE_URL', '').strip()
if DATABASE_URL:
    import dj_database_url
    DATABASES = {
        'default': dj_database_url.parse(
            DATABASE_URL,
            conn_max_age=int(os.getenv('DB_CONN_MAX_AGE', 60)),
            conn_health_checks=True,
            ssl_require=os.getenv('DB_SSL', 'True').lower() in ('true', '1', 't'),
        )
    }
    # Connection poolers (Supabase, PgBouncer) cannot keep server-side cursors between queries.
    DATABASES['default']['DISABLE_SERVER_SIDE_CURSORS'] = True
else:
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': BASE_DIR / 'db.sqlite3',
            'OPTIONS': {
                'timeout': 20,
            },
        }
    }

# ─── Custom User Model ────────────────────────────────────────────────────────
AUTH_USER_MODEL = 'authentication.CustomUser'

# ─── Password Validation ──────────────────────────────────────────────────────
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

# ─── Internationalisation ─────────────────────────────────────────────────────
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
# Zone used when a time is written out for people (emails). Storage stays UTC.
DISPLAY_TIME_ZONE = os.getenv('DISPLAY_TIME_ZONE', 'Asia/Dhaka')
# Where the React app is served; used to build links in emails (password reset).
FRONTEND_URL = os.getenv('FRONTEND_URL', 'http://localhost:5173')
USE_I18N = True
USE_TZ = True  # All datetimes stored as UTC — critical for exam time engine

# ─── Static & Media Files ─────────────────────────────────────────────────────
STATIC_URL = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

MEDIA_URL = os.getenv('MEDIA_URL', '/media/')
MEDIA_ROOT = BASE_DIR / 'media'
MAX_UPLOAD_SIZE_MB = int(os.getenv('MAX_UPLOAD_SIZE_MB', 10))

STORAGES = {
    # Uploaded question pictures and answer sheets. On your own PC: the media/ folder.
    'default': {'BACKEND': 'django.core.files.storage.FileSystemStorage'},
    'staticfiles': {
        'BACKEND': 'django.contrib.staticfiles.storage.StaticFilesStorage' if DEBUG
        else 'whitenoise.storage.CompressedStaticFilesStorage',
    },
}
# Online: an S3-compatible bucket (Supabase Storage, Cloudflare R2, AWS S3). A hosted server's
# own disk is wiped on every deploy, so uploads must live somewhere else.
if os.getenv('S3_BUCKET') and os.getenv('S3_ACCESS_KEY_ID') and os.getenv('S3_SECRET_ACCESS_KEY'):
    STORAGES['default'] = {
        'BACKEND': 'storages.backends.s3.S3Storage',
        'OPTIONS': {
            'bucket_name': os.environ['S3_BUCKET'],
            'endpoint_url': os.getenv('S3_ENDPOINT_URL') or None,
            'access_key': os.getenv('S3_ACCESS_KEY_ID'),
            'secret_key': os.getenv('S3_SECRET_ACCESS_KEY'),
            'region_name': os.getenv('S3_REGION') or None,
            'addressing_style': 'path',
            'signature_version': 's3v4',
            'default_acl': None,
            'file_overwrite': False,
            # Files are opened by their plain public address (the bucket must be public),
            # e.g. <project>.supabase.co/storage/v1/object/public/<bucket>
            'querystring_auth': False,
            'custom_domain': os.getenv('S3_PUBLIC_DOMAIN') or None,
        },
    }

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# ─── CORS ─────────────────────────────────────────────────────────────────────
CORS_ALLOWED_ORIGINS = [
    'http://localhost:5173',  # React Vite dev server
    'http://localhost:3000',
]
CORS_ALLOWED_ORIGINS += [o.strip() for o in os.getenv('CORS_ALLOWED_ORIGINS', '').split(',') if o.strip()]
CSRF_TRUSTED_ORIGINS = [o.strip() for o in os.getenv('CSRF_TRUSTED_ORIGINS', '').split(',') if o.strip()]

frontend_env = os.getenv('FRONTEND_URL', '').strip().rstrip('/')
if frontend_env:
    if frontend_env not in CORS_ALLOWED_ORIGINS:
        CORS_ALLOWED_ORIGINS.append(frontend_env)
    if frontend_env not in CSRF_TRUSTED_ORIGINS:
        CSRF_TRUSTED_ORIGINS.append(frontend_env)

if os.getenv('RENDER_EXTERNAL_HOSTNAME'):
    render_origin = f"https://{os.environ['RENDER_EXTERNAL_HOSTNAME']}"
    if render_origin not in CSRF_TRUSTED_ORIGINS:
        CSRF_TRUSTED_ORIGINS.append(render_origin)

if os.getenv('RENDER') or os.getenv('RENDER_EXTERNAL_HOSTNAME'):
    if 'https://*.onrender.com' not in CSRF_TRUSTED_ORIGINS:
        CSRF_TRUSTED_ORIGINS.append('https://*.onrender.com')

# Allow *.onrender.com subdomains so Render static frontend and API connect seamlessly
CORS_ALLOWED_ORIGIN_REGEXES = [
    r'^https:\/\/.*\.onrender\.com$',
]
if DEBUG:
    # Development only: the mobile app run in a browser (`flutter run -d chrome`) uses a random local port.
    CORS_ALLOWED_ORIGIN_REGEXES.append(r'^http://(localhost|127\.0\.0\.1)(:\d+)?$')

CORS_ALLOW_CREDENTIALS = True

# ─── Django REST Framework ────────────────────────────────────────────────────
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',
    ),
    # One contract for every client (see config/api.py): JSON-object bodies in,
    # and every error out with `message` + `code`.
    'DEFAULT_RENDERER_CLASSES': (
        'config.api.ApiJSONRenderer',
    ),
    'DEFAULT_PARSER_CLASSES': (
        'config.api.ObjectJSONParser',
        'rest_framework.parsers.FormParser',
        'rest_framework.parsers.MultiPartParser',
    ),
    'EXCEPTION_HANDLER': 'config.api.api_exception_handler',
    'DEFAULT_PAGINATION_CLASS': 'apps.authentication.pagination.StandardPagination',
    'PAGE_SIZE': 20,
    # Datetimes are always ISO 8601 in UTC, e.g. 2026-10-06T19:14:07.399411Z (DRF's default),
    # the same form hand-built responses produce, so strict mobile parsers see one format.
    'DEFAULT_THROTTLE_CLASSES': (
        'rest_framework.throttling.AnonRateThrottle',
        'rest_framework.throttling.UserRateThrottle',
    ),
    'DEFAULT_THROTTLE_RATES': {
        'anon': '60/min',
        'user': '600/min',
        # Sign-in, sign-up and password reset: slow enough to blunt password guessing.
        'auth': os.getenv('AUTH_THROTTLE_RATE', '20/min'),
    },
}
if 'test' in sys.argv:
    # The test suite signs in far more often than a person can; throttling has its own test.
    REST_FRAMEWORK['DEFAULT_THROTTLE_RATES'] = {'anon': '100000/min', 'user': '100000/min', 'auth': '100000/min'}

# ─── Simple JWT ───────────────────────────────────────────────────────────────
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(
        minutes=int(os.getenv('ACCESS_TOKEN_LIFETIME_MINUTES', 60))
    ),
    'REFRESH_TOKEN_LIFETIME': timedelta(
        days=int(os.getenv('REFRESH_TOKEN_LIFETIME_DAYS', 7))
    ),
    # Rotation without blacklist keeps old refresh valid; either install
    # token_blacklist app or disable rotation. Disabled by default.
    'ROTATE_REFRESH_TOKENS': False,
    'BLACKLIST_AFTER_ROTATION': False,
    'AUTH_HEADER_TYPES': ('Bearer',),
    'USER_ID_FIELD': 'id',
    'USER_ID_CLAIM': 'user_id',
    'TOKEN_OBTAIN_SERIALIZER': 'apps.authentication.serializers.CustomTokenObtainPairSerializer',
}

# ─── Email ────────────────────────────────────────────────────────────────────
EMAIL_BACKEND = os.getenv(
    'EMAIL_BACKEND',
    'django.core.mail.backends.console.EmailBackend'
)
EMAIL_HOST = os.getenv('EMAIL_HOST', 'smtp.gmail.com')
EMAIL_PORT = int(os.getenv('EMAIL_PORT', 587))
EMAIL_USE_TLS = os.getenv('EMAIL_USE_TLS', 'True') == 'True'
EMAIL_HOST_USER = os.getenv('EMAIL_HOST_USER', '')
EMAIL_HOST_PASSWORD = os.getenv('EMAIL_HOST_PASSWORD', '')
DEFAULT_FROM_EMAIL = os.getenv('DEFAULT_FROM_EMAIL', 'TuitionTrack <noreply@tuitiontrack.app>')

# ─── Production (DEBUG off) ───────────────────────────────────────────────────
if not DEBUG:
    # The host terminates https and forwards plain http to the app, saying so in this header.
    SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
    SECURE_SSL_REDIRECT = os.getenv('SECURE_SSL_REDIRECT', 'True').lower() in ('true', '1', 't')
    # The host's health check calls this over plain http from inside its network.
    SECURE_REDIRECT_EXEMPT = [r'^api/v1/meta/$']
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SECURE_HSTS_SECONDS = int(os.getenv('SECURE_HSTS_SECONDS', 60 * 60 * 24 * 30))
    SECURE_CONTENT_TYPE_NOSNIFF = True

# Errors go to the console, which is what a hosting platform collects as its logs.
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {'console': {'class': 'logging.StreamHandler'}},
    'root': {'handlers': ['console'], 'level': 'WARNING'},
    'loggers': {
        'django.request': {'handlers': ['console'], 'level': 'ERROR', 'propagate': False},
    },
}
