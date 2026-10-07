#!/usr/bin/env bash
# Build step on the hosting platform: install packages, gather the admin's static
# files, and bring the online database up to date.
set -o errexit

pip install -r requirements.txt
python manage.py collectstatic --no-input
python manage.py migrate --no-input
