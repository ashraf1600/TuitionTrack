import django.db.models.deletion
from django.db import migrations, models


def _completed(cycle):
    return sum(1 for c in (cycle.classes_data or []) if c.get('completed'))


def merge_cycles_per_tuition(apps, schema_editor):
    """
    Cycles used to belong to one enrollment (one student). They now belong to
    the tuition and are shared by the whole group, so the per-student rows of
    each tuition are folded into one row per cycle:

    - ARCHIVED rows with the same cycle number merge into one. The row with the
      most completed classes is kept and the fees are summed, because each old
      row carried one student's fee and the new row carries the group's.
    - ACTIVE rows collapse into the one with the most completed classes; it
      takes the tuition's current total_fee.
    - Rows whose enrollment was already gone keep `tuition` empty; their
      `tutor` link still counts them towards lifetime earnings.
    """
    AttendanceCycle = apps.get_model('cycles', 'AttendanceCycle')
    Tuition = apps.get_model('students', 'Tuition')

    for tuition in Tuition.objects.all():
        rows = list(
            AttendanceCycle.objects.filter(enrollment__tuition=tuition).select_related('enrollment')
        )
        archived = {}
        for row in rows:
            if row.status == 'ARCHIVED':
                archived.setdefault(row.cycle_number, []).append(row)

        last_number = 0
        for number in sorted(archived):
            group = archived[number]
            keeper = max(group, key=_completed)
            keeper.fee_snapshot = sum(r.fee_snapshot for r in group)
            keeper.tuition = tuition
            keeper.tutor_id = keeper.tutor_id or tuition.tutor_id
            keeper.total_classes = keeper.total_classes_snapshot or keeper.total_classes
            keeper.save()
            for r in group:
                if r.pk != keeper.pk:
                    r.delete()
            last_number = max(last_number, number)

        active = [r for r in rows if r.status == 'ACTIVE']
        # Prefer the progress of students who are still in the group.
        current = [r for r in active if r.enrollment and r.enrollment.is_active] or active
        if current:
            keeper = max(current, key=_completed)
            for r in active:
                if r.pk != keeper.pk:
                    r.delete()
            keeper.tuition = tuition
            keeper.tutor_id = keeper.tutor_id or tuition.tutor_id
            keeper.cycle_number = max(keeper.cycle_number, last_number + 1)
            keeper.fee_snapshot = tuition.total_fee
            keeper.total_classes = keeper.total_classes_snapshot or keeper.total_classes
            keeper.save()
        else:
            AttendanceCycle.objects.create(
                tuition=tuition,
                tutor_id=tuition.tutor_id,
                cycle_number=last_number + 1,
                fee_snapshot=tuition.total_fee,
                total_classes=tuition.cycle_length,
                total_classes_snapshot=tuition.cycle_length,
                classes_data=[
                    {'class_no': i, 'completed': False, 'date': None, 'topic': ''}
                    for i in range(1, tuition.cycle_length + 1)
                ],
                status='ACTIVE',
            )

    # An orphaned ACTIVE row (enrollment deleted) can no longer be worked on.
    AttendanceCycle.objects.filter(tuition__isnull=True, status='ACTIVE').update(status='ARCHIVED')


class Migration(migrations.Migration):

    dependencies = [
        ('cycles', '0004_attendancecycle_total_classes_snapshot'),
        ('students', '0009_group_tuition_and_connection_requests'),
    ]

    operations = [
        migrations.AddField(
            model_name='attendancecycle',
            name='tuition',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='cycles', to='students.tuition', verbose_name='Tuition'),
        ),
        migrations.RemoveConstraint(
            model_name='attendancecycle',
            name='unique_active_attendance_cycle_per_enrollment',
        ),
        migrations.RunPython(merge_cycles_per_tuition, migrations.RunPython.noop),
    ]
