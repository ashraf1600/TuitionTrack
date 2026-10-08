#!/usr/bin/env bash
# Build step on the hosting platform: install packages, gather the admin's static
# files, and bring the online database up to date.
set -o errexit

pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py migrate --no-input

# Optional: Automatically create superuser if environment variables are provided
if [ -n "$DJANGO_SUPERUSER_USERNAME" ] && [ -n "$DJANGO_SUPERUSER_PASSWORD" ]; then
  echo "Creating superuser '$DJANGO_SUPERUSER_USERNAME'..."
  python manage.py createsuperuser --no-input || true
fi
