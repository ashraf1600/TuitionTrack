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

        total_earned = sum(float(c.earned_revenue) for c in group_active) + sum(float(c.earned_amount) for c in legacy_active)
        total_pending = sum(float(c.pending_balance) for c in group_active) + sum(float(c.pending_amount) for c in legacy_active)
        lifetime_archived = sum(float(c.earned_revenue) for c in group_archived) + sum(float(c.earned_amount) for c in legacy_archived)

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

            exams = Exam.objects.filter(tutor=user, is_published=True).select_related('tuition').prefetch_related('submissions')
            for exam in exams:
                waiting = [
                    s for s in exam.submissions.all()
                    if s.status != ExamSubmission.Status.MISSED and not s.is_graded
                ]
                if waiting:
                    latest = max(s.submitted_at or now for s in waiting)
                    link = f'/tuitions/{exam.tuition_id}' if exam.tuition_id else '/tutor'
                    add(
                        f'grade-{exam.id}-{len(waiting)}', 'grade',
                        f'{len(waiting)} submission{"" if len(waiting) == 1 else "s"} to grade',
                        exam.title, latest, link,
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

        elif user.role == 'STUDENT':
            from django.db.models import Q
            exams = Exam.objects.filter(is_published=True).filter(
                Q(student=user) | Q(tuition__enrollments__student=user, tuition__enrollments__is_active=True)
            ).distinct().prefetch_related('submissions')
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

            # Completed billing cycle → payment due. Derived from the ACTIVE
            # cycle, so it clears itself as soon as the tutor starts the next one.
            from apps.cycles.models import Cycle as LegacyCycle
            from apps.students.models import TuitionEnrollment
            seen_cycle_ids = set()
            for enr in TuitionEnrollment.objects.filter(
                student=user, is_active=True
            ).select_related('tuition', 'tuition__tutor'):
                tuition = enr.tuition
                cycle = tuition.cycles.filter(status=AttendanceCycle.Status.ACTIVE).first()
                if not cycle or not cycle.is_complete or cycle.id in seen_cycle_ids:
                    continue
                seen_cycle_ids.add(cycle.id)
                tutor = tuition.tutor
                tutor_name = f'{(tutor.first_name or "").strip() or tutor.username} Sir'
                amount = f'৳{float(cycle.total_fee):,.0f}'
                add(
                    f'cycle-due-{cycle.id}', 'cycle',
                    f'{tuition.title}: cycle #{cycle.cycle_number} complete — payment due',
                    f'{tutor_name} · {amount}', cycle.updated_at, f'/student?tutor={tutor.id}',
                )

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

        return Response({'count': len(items), 'notifications': items})
