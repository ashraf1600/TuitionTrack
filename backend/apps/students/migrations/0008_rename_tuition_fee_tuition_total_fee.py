from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('students', '0007_studentprofile_initial_password'),
    ]

    operations = [
        migrations.RenameField(
            model_name='tuition',
            old_name='tuition_fee',
            new_name='total_fee',
        ),
    ]
