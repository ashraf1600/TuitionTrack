"""Backfill tutor_code for tutors created before auto-generation existed."""
import secrets
import string

from django.db import migrations, models


def _generate():
    alphabet = string.ascii_uppercase + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(6))


def backfill_tutor_codes(apps, schema_editor):
    CustomUser = apps.get_model('authentication', 'CustomUser')
    used = set(
        CustomUser.objects.exclude(tutor_code__isnull=True)
        .exclude(tutor_code='')
        .values_list('tutor_code', flat=True)
    )
    missing = CustomUser.objects.filter(role='TUTOR').filter(
        models.Q(tutor_code__isnull=True) | models.Q(tutor_code='')
    )
    for tutor in missing.iterator():
        for _ in range(50):
            candidate = _generate()
            if candidate not in used:
                used.add(candidate)
                tutor.tutor_code = candidate
                tutor.save(update_fields=['tutor_code'])
                break


class Migration(migrations.Migration):

    dependencies = [
        ('authentication', '0004_tutor_code_profile_pic_homework'),
    ]

    operations = [
        migrations.RunPython(backfill_tutor_codes, migrations.RunPython.noop),
    ]
