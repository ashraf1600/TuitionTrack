"""
Analytics App Views

Endpoints:
  GET /api/v1/analytics/wallet/ — Tutor-level live earnings and pending tuition breakdown
"""
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from apps.authentication.permissions import IsTutor
from apps.cycles.models import Cycle
from .serializers import WalletAnalyticsSerializer


class WalletAnalyticsView(APIView):
    """
    GET /api/v1/analytics/wallet/   (tutor only)

    The Tuition Wallet. Each tuition group has one shared cycle, and the tutor
    earns per completed class of the group:

        earned = (total_fee / cycle_length) * completed_classes

    Totals cover every active group cycle; archived cycles make up lifetime
    earnings. Legacy 1-on-1 cycles are still counted for students who are not
    in any tuition group.
    """
    permission_classes = [IsAuthenticated, IsTutor]

    def get(self, request):
        from decimal import Decimal
        from django.db.models import Q
        from apps.cycles.models import AttendanceCycle
        from apps.students.models import TuitionEnrollment

        tutor = request.user

        group_active = list(
            AttendanceCycle.objects.filter(
                tuition__tutor=tutor, status=AttendanceCycle.Status.ACTIVE
            ).select_related('tuition').order_by('tuition__title')
        )
        # `tutor=` also catches archived cycles whose tuition was deleted.
        group_archived = AttendanceCycle.objects.filter(
            Q(tuition__tutor=tutor) | Q(tutor=tutor),
            status=AttendanceCycle.Status.ARCHIVED,
        ).distinct()

        enrolled_student_ids = set(
            TuitionEnrollment.objects.filter(
                tuition__tutor=tutor, is_active=True, student__is_active=True
            ).values_list('student_id', flat=True)
        )

        # Legacy 1-on-1 cycles: only for active students not billed through a group.
        legacy_active = Cycle.objects.filter(
            tutor=tutor,
            status=Cycle.Status.ACTIVE,
            student__is_active=True,
        ).exclude(student_id__in=enrolled_student_ids).select_related('student')
        legacy_archived = Cycle.objects.filter(tutor=tutor, status=Cycle.Status.ARCHIVED)

        # Money is added up as Decimal and turned into a number only for the response.
        zero = Decimal('0.00')
        total_earned = float(
            sum((c.earned_revenue for c in group_active), zero) + sum((Decimal(c.earned_amount) for c in legacy_active), zero)
        )
        total_pending = float(
            sum((c.pending_balance for c in group_active), zero) + sum((Decimal(c.pending_amount) for c in legacy_active), zero)
        )
        lifetime_archived = float(
            sum((c.earned_revenue for c in group_archived), zero)
            + sum((Decimal(c.earned_amount) for c in legacy_archived), zero)
        )

        # Finished cycles the tutor has not marked paid yet (cash still to collect).
        group_archived = list(group_archived.select_related('tuition'))
        unpaid = sorted(
            (c for c in group_archived if c.payment_status == AttendanceCycle.Payment.PENDING),
            key=lambda c: c.updated_at,
        )
        unpaid_total = float(sum((c.earned_revenue for c in unpaid), zero))

        def title_of(cycle):
            return cycle.tuition.title if cycle.tuition_id else 'Deleted tuition'

        unpaid_list = [
            {
                'cycle_id': c.id,
                'tuition_id': c.tuition_id,
                'tuition_title': title_of(c),
                'cycle_number': c.cycle_number,
                'completed_classes': c.completed_classes,
                'total_classes': c.total_classes,
                'amount': float(c.earned_revenue),
                'finished_at': c.updated_at,
            }
            for c in unpaid
        ]
        paid = sorted(
            (c for c in group_archived if c.payment_status == AttendanceCycle.Payment.PAID and c.paid_at),
            key=lambda c: c.paid_at,
            reverse=True,
        )[:5]
        recent_paid = [
            {
                'cycle_id': c.id,
                'tuition_id': c.tuition_id,
                'tuition_title': title_of(c),
                'cycle_number': c.cycle_number,
                'amount': float(c.earned_revenue),
                'paid_at': c.paid_at,
            }
            for c in paid
        ]

        students_per_tuition = {}
        for tuition_id in TuitionEnrollment.objects.filter(
            tuition__tutor=tutor, is_active=True, student__is_active=True
        ).values_list('tuition_id', flat=True):
            students_per_tuition[tuition_id] = students_per_tuition.get(tuition_id, 0) + 1

        tuition_breakdowns = [
            {
                'tuition_id': c.tuition_id,
                'tuition_title': c.tuition.title,
                'student_count': students_per_tuition.get(c.tuition_id, 0),
                'cycle_id': c.id,
                'cycle_number': c.cycle_number,
                'completed_classes': c.completed_classes,
                'total_classes': c.total_classes,
                'total_fee': float(c.total_fee),
                'per_class_rate': float(c.per_class_rate),
                'earned': float(c.earned_revenue),
                'pending': float(c.pending_balance),
                'progress_percentage': c.progress_percent,
            }
            for c in group_active
        ]

        student_breakdowns = [
            {
                'student_id': c.student.id,
                'student_name': c.student.get_full_name() or c.student.username,
                'cycle_id': c.id,
                'cycle_number': c.cycle_number,
                'completed_classes': c.completed_classes,
                'total_classes': c.total_classes,
                'earned': float(c.earned_amount),
                'pending': float(c.pending_amount),
                'progress_percentage': round((c.completed_classes / c.total_classes) * 100, 1) if c.total_classes else 0.0,
            }
            for c in legacy_active
        ]

        payload = {
            'total_students': len(enrolled_student_ids | {c.student_id for c in legacy_active}),
            'total_tuitions': len(group_active),
            'total_earned': round(total_earned, 2),
            'total_pending': round(total_pending, 2),
            'lifetime_archived_earnings': round(lifetime_archived, 2),
            'unpaid_cycles': len(unpaid),
            'unpaid_total': round(unpaid_total, 2),
            'unpaid_list': unpaid_list,
            'recent_paid': recent_paid,
            'chart_data': [
                {'name': 'Earned', 'value': round(total_earned, 2), 'color': '#10B981'},
                {'name': 'Pending', 'value': round(total_pending, 2), 'color': '#6366F1'},
            ],
            'tuition_breakdowns': tuition_breakdowns,
            'student_breakdowns': student_breakdowns,
        }

        serializer = WalletAnalyticsSerializer(payload)
        return Response(serializer.data)


class NotificationsView(APIView):
    """
    GET /api/v1/notifications/
    The bell. Notifications are worked out from the current state of things —
    pending requests, work waiting to be graded, exams opening or open — so
    they can never go stale, and each has a stable id the app uses to remember
    what the user has already seen.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        from datetime import timedelta
        from django.utils import timezone
        from apps.cycles.models import AttendanceCycle
        from apps.exams.models import Exam, ExamSubmission
        from apps.students.models import ConnectionRequest

        user = request.user
        now = timezone.now()
        items = []

        def add(item_id, kind, title, body='', when=None, link=''):
            items.append({'id': item_id, 'kind': kind, 'title': title, 'body': body, 'when': when or now, 'link': link})

        if user.role == 'TUTOR':
            for req in ConnectionRequest.objects.filter(
                tutor=user, status=ConnectionRequest.Status.PENDING, student__is_active=True
            ).select_related('student')[:20]:
                name = req.student.get_full_name() or req.student.username
                add(f'request-{req.id}', 'request', f'{name} wants to join you', req.message, req.created_at, '/tutor')

            # Counted in the database: only exams with work waiting come back, never every exam ever set.
            from django.db.models import Count, Max, Q as DbQ
            ungraded = DbQ(submissions__is_graded=False) & ~DbQ(submissions__status=ExamSubmission.Status.MISSED)
            exams = (
                Exam.objects.filter(tutor=user, is_published=True)
                .annotate(waiting=Count('submissions', filter=ungraded), latest=Max('submissions__submitted_at', filter=ungraded))
                .filter(waiting__gt=0)
                .only('id', 'title', 'tuition_id')
            )
            for exam in exams:
                waiting = exam.waiting
                link = f'/tuitions/{exam.tuition_id}' if exam.tuition_id else '/tutor'
                add(
                    f'grade-{exam.id}-{waiting}', 'grade',
                    f'{waiting} submission{"" if waiting == 1 else "s"} to grade',
                    exam.title, exam.latest or now, link,
                )

            for cycle in AttendanceCycle.objects.filter(
                tuition__tutor=user, status=AttendanceCycle.Status.ACTIVE
            ).select_related('tuition'):
                if cycle.is_complete:
                    add(
                        f'cycle-{cycle.id}', 'cycle',
                        f'{cycle.tuition.title}: cycle #{cycle.cycle_number} is complete',
                        'Start the next cycle when you are ready.', cycle.updated_at, f'/tuitions/{cycle.tuition_id}',
                    )

            # Finished cycles not marked paid yet.
            for cycle in AttendanceCycle.objects.filter(
                tuition__tutor=user, status=AttendanceCycle.Status.ARCHIVED,
                payment_status=AttendanceCycle.Payment.PENDING,
            ).select_related('tuition').order_by('-updated_at')[:20]:
                add(
                    f'unpaid-{cycle.id}', 'payment',
                    f'{cycle.tuition.title}: payment pending for cycle #{cycle.cycle_number}',
                    'Mark it paid when you receive the money.', cycle.updated_at, f'/tuitions/{cycle.tuition_id}',
                )

            # Homework handed in and waiting to be checked.
            from apps.students.models import Homework
            for hw in Homework.objects.filter(
                tutor=user, is_evaluated=False, submitted_at__isnull=False, submitted_at__gte=now - timedelta(days=14),
            ).select_related('student').order_by('-submitted_at')[:20]:
                who = (hw.student.get_full_name() or hw.student.username) if hw.student_id else 'A student'
                add(
                    f'handed-in-{hw.id}-{int(hw.submitted_at.timestamp())}', 'homework',
                    f'{who} handed in homework', hw.title, hw.submitted_at, '/tutor',
                )

        elif user.role == 'STUDENT':
            # Students see their tutor as "Ashraf Sir"; the names tutors give their tuitions stay on the tutor's side.
            from apps.authentication.naming import sir_name
            from django.db.models import Q
            # Only exams that can still matter (open, coming up, or closed in the last 30 days),
            # and only this student's own submissions.
            from django.db.models import Prefetch
            exams = Exam.objects.filter(is_published=True).filter(
                Q(student=user) | Q(tuition__enrollments__student=user, tuition__enrollments__is_active=True)
            ).filter(
                Q(end_time__gte=now - timedelta(days=30)) | Q(late_submission_until__gte=now)
            ).distinct().prefetch_related(
                Prefetch('submissions', queryset=ExamSubmission.objects.filter(student=user))
            )
            for exam in exams:
                mine = next(
                    (s for s in exam.submissions.all()
                     if s.student_id == user.id and s.status != ExamSubmission.Status.MISSED),
                    None,
                )
                noun = 'Assignment' if exam.category == Exam.AssessmentCategory.ASSIGNMENT else 'Exam'
                if mine:
                    if exam.results_released(mine, now) and mine.is_graded:
                        add(f'result-{exam.id}', 'result', f'Results are out: {exam.title}', '', mine.graded_at or exam.end_time, '/student')
                    continue
                if exam.start_time <= now <= exam.end_time:
                    add(f'open-{exam.id}', 'open', f'{noun} open now: {exam.title}', 'closes', exam.end_time, '/student')
                elif exam.end_time < now <= exam.final_deadline:
                    add(f'late-{exam.id}', 'late', f'Deadline passed: {exam.title}', 'late work accepted until', exam.final_deadline, '/student')
                elif now < exam.start_time <= now + timedelta(hours=48):
                    add(f'soon-{exam.id}', 'soon', f'{noun} coming up: {exam.title}', 'opens', exam.start_time, '/student')

            recent = now - timedelta(days=14)
            for req in ConnectionRequest.objects.filter(
                student=user, responded_at__gte=recent
            ).exclude(status=ConnectionRequest.Status.PENDING).select_related('tutor'):
                tutor_name = req.tutor.get_full_name() or req.tutor.username
                accepted = req.status == ConnectionRequest.Status.ACCEPTED
                add(
                    f'connection-{req.id}-{req.status}', 'connection',
                    f'{tutor_name} {"accepted" if accepted else "declined"} your request',
                    '', req.responded_at, '/student',
                )

            # Finished cycles waiting for payment, and payments just recorded.
            # A reminder only: classes and everything else go on as usual.
            from apps.students.models import TuitionEnrollment
            tuition_ids = list(TuitionEnrollment.objects.filter(student=user, is_active=True).values_list('tuition_id', flat=True))
            for cycle in AttendanceCycle.objects.filter(
                tuition_id__in=tuition_ids, status=AttendanceCycle.Status.ARCHIVED,
            ).select_related('tuition', 'tuition__tutor'):
                tutor = cycle.tuition.tutor
                link = f'/student?tutor={tutor.id}'
                if cycle.payment_status == AttendanceCycle.Payment.PENDING:
                    # No amount: the cycle's fee is the whole group's total, not what one student owes.
                    add(
                        f'pay-{cycle.id}', 'payment',
                        f'{sir_name(tutor)}: payment pending for cycle #{cycle.cycle_number}',
                        'Classes go on as usual.', cycle.updated_at, link,
                    )
                elif cycle.paid_at and cycle.paid_at >= recent:
                    add(
                        f'paid-{cycle.id}', 'payment',
                        f'Payment received for cycle #{cycle.cycle_number}',
                        sir_name(tutor), cycle.paid_at, link,
                    )
            # Classes the tutor just marked done (last 3 days): the phone shows each one as a pop-up.
            # The id carries the class date, so undoing and marking again notifies again, while
            # everything else that touches the cycle (payment, reopen) does not repeat it.
            from datetime import timezone as dt_timezone
            from django.utils.dateparse import parse_datetime
            class_cutoff = now - timedelta(days=3)
            recent_cycles = AttendanceCycle.objects.filter(
                tuition_id__in=tuition_ids, updated_at__gte=class_cutoff,
            ).select_related('tuition', 'tuition__tutor').order_by('-updated_at')[:12]
            done_classes = []
            for cycle in recent_cycles:
                for entry in cycle.classes_data or []:
                    if not isinstance(entry, dict) or not entry.get('completed'):
                        continue
                    when = parse_datetime(str(entry.get('date') or ''))
                    if when is None:
                        continue
                    if timezone.is_naive(when):
                        when = timezone.make_aware(when, dt_timezone.utc)
                    if when < class_cutoff:
                        continue
                    done_classes.append((when, cycle, entry))
            done_classes.sort(key=lambda row: row[0], reverse=True)
            for when, cycle, entry in done_classes[:20]:
                number = AttendanceCycle._class_no(entry)
                tutor = cycle.tuition.tutor
                add(
                    f'class-{cycle.id}-{number}-{int(when.timestamp())}', 'class',
                    f'{sir_name(tutor)}: class {number} done',
                    str(entry.get('topic') or ''), when, f'/student?tutor={tutor.id}',
                )

            # Older cycles that completed before automatic roll-over and are still current.
            from apps.cycles.models import Cycle as LegacyCycle
            for cycle in AttendanceCycle.objects.filter(
                tuition_id__in=tuition_ids, status=AttendanceCycle.Status.ACTIVE,
            ).select_related('tuition', 'tuition__tutor'):
                if cycle.is_complete and cycle.payment_status == AttendanceCycle.Payment.PENDING:
                    add(
                        f'cycle-due-{cycle.id}', 'payment',
                        f'{sir_name(cycle.tuition.tutor)}: cycle #{cycle.cycle_number} complete — payment due',
                        'Classes go on as usual.', cycle.updated_at, f'/student?tutor={cycle.tuition.tutor_id}',
                    )

            # Homework: newly set, due within a day, and just checked.
            from apps.students.services import student_homework
            for hw in student_homework(user).filter(
                Q(created_at__gte=recent) | Q(evaluated_at__gte=recent) | Q(due_date__lte=now + timedelta(hours=24), due_date__gte=now)
            ).order_by('-created_at')[:40]:
                if hw.is_evaluated:
                    if hw.evaluated_at and hw.evaluated_at >= recent:
                        add(f'hw-checked-{hw.id}', 'homework', f'Homework checked: {hw.title}', hw.tutor_feedback[:120], hw.evaluated_at, '/student')
                    continue
                if hw.submitted_at:
                    continue
                if now <= hw.due_date <= now + timedelta(hours=24):
                    add(f'hw-due-{hw.id}', 'homework', f'Homework due soon: {hw.title}', 'due', hw.due_date, '/student')
                elif hw.created_at >= now - timedelta(days=7):
                    add(f'hw-new-{hw.id}', 'homework', f'New homework: {hw.title}', 'due', hw.due_date, '/student')

            # Legacy 1-on-1 billing (students with no tuition group).
            for cycle in LegacyCycle.objects.filter(
                student=user, status=LegacyCycle.Status.ACTIVE
            ).select_related('tutor'):
                if not cycle.is_complete:
                    continue
                tutor = cycle.tutor
                tutor_name = f'{(tutor.first_name or "").strip() or tutor.username} Sir'
                amount = f'৳{float(cycle.fee_snapshot):,.0f}'
                add(
                    f'cycle-due-{cycle.id}', 'cycle',
                    f'Cycle #{cycle.cycle_number} complete — payment due',
                    f'{tutor_name} · {amount}', cycle.updated_at, '/student',
                )

        # Unread chat messages, one item per conversation. The app keeps them out of
        # the bell (the chat button has its own badge) but shows them on the phone.
        from apps.messaging.views import unread_notifications
        items.extend(unread_notifications(user, request))

        return Response({'count': len(items), 'notifications': items})
