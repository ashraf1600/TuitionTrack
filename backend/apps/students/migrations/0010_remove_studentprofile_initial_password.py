from django.db import migrations


def require_new_password(apps, schema_editor):
    """
    Passwords that were kept readable must be treated as known to others:
    their owners are asked to choose a new one at next sign-in.
    """
    StudentProfile = apps.get_model('students', 'StudentProfile')
    User = apps.get_model('authentication', 'CustomUser')
    user_ids = StudentProfile.objects.exclude(initial_password='').values_list('user_id', flat=True)
    User.objects.filter(id__in=list(user_ids)).update(must_change_password=True)


class Migration(migrations.Migration):

    dependencies = [
        ('students', '0009_group_tuition_and_connection_requests'),
        ('authentication', '0003_account_and_marking_upgrades'),
    ]

    operations = [
        migrations.RunPython(require_new_password, migrations.RunPython.noop),
        migrations.RemoveField(
            model_name='studentprofile',
            name='initial_password',
        ),
    ]
