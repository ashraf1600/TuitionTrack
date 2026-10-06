from django.db import migrations, models


def keep_existing_behaviour(apps, schema_editor):
    """
    Until now `is_results_published` meant "students see results once the exam
    has closed" when on, and "not yet" when off. On maps to SCHEDULED with no
    time (the new default), so only the off rows need changing: they become
    MANUAL and stay hidden until the tutor publishes.
    """
    Exam = apps.get_model('exams', 'Exam')
    Exam.objects.filter(is_results_published=False).update(result_publish_mode='MANUAL')


def restore_flag(apps, schema_editor):
    Exam = apps.get_model('exams', 'Exam')
    # The old meaning of the flag was "visible after closing".
    Exam.objects.filter(result_publish_mode__in=['IMMEDIATE', 'SCHEDULED']).update(is_results_published=True)


class Migration(migrations.Migration):

    dependencies = [
        ('exams', '0008_account_and_marking_upgrades'),
    ]

    operations = [
        migrations.AddField(
            model_name='exam',
            name='result_publish_mode',
            field=models.CharField(
                choices=[
                    ('IMMEDIATE', 'Right after each student submits'),
                    ('MANUAL', 'When the tutor publishes them'),
                    ('SCHEDULED', 'At a set time (or when the exam closes)'),
                ],
                default='SCHEDULED',
                help_text=(
                    'IMMEDIATE: a student sees marks and answers as soon as they submit. '
                    'MANUAL: only while is_results_published is on. '
                    'SCHEDULED: from publish_time, or once the exam has closed if no time is set.'
                ),
                max_length=10,
                verbose_name='Result Publication Mode',
            ),
        ),
        migrations.AddField(
            model_name='exam',
            name='publish_time',
            field=models.DateTimeField(
                blank=True,
                help_text='Only for SCHEDULED mode. Empty means "as soon as nobody can submit any more".',
                null=True,
                verbose_name='Publish Results At (UTC)',
            ),
        ),
        migrations.RunPython(keep_existing_behaviour, restore_flag),
    ]
