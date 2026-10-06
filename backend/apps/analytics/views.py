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
    GET /api/v1/analytics/wallet/
    Computes real-time financial stats across all active cycles for the logged-in tutor,
    plus lifetime earnings from archived cycles.
    """
    permission_classes = [IsAuthenticated, IsTutor]

    def get(self, request):
        tutor = request.user

        # Fetch all active cycles for this tutor with students pre-joined
        active_cycles = Cycle.objects.filter(
            tutor=tutor,
            status=Cycle.Status.ACTIVE
        ).select_related('student', 'student__student_profile')

        # Fetch archived cycles for lifetime calculation
        archived_cycles = Cycle.objects.filter(
            tutor=tutor,
            status=Cycle.Status.ARCHIVED
        )

        total_earned = sum(float(c.earned_amount) for c in active_cycles)
        total_pending = sum(float(c.pending_amount) for c in active_cycles)
        lifetime_archived = sum(float(c.earned_amount) for c in archived_cycles)

        total_students = active_cycles.values('student').distinct().count()

        chart_data = [
            {'name': 'Earned', 'value': round(total_earned, 2), 'color': '#10B981'},
            {'name': 'Pending', 'value': round(total_pending, 2), 'color': '#6366F1'},
        ]

        student_breakdowns = []
        for c in active_cycles:
            completed = c.completed_classes
            total = c.total_classes
            pct = round((completed / total) * 100, 1) if total > 0 else 0.0

            student_breakdowns.append({
                'student_id': c.student.id,
                'student_name': c.student.get_full_name() or c.student.username,
                'cycle_id': c.id,
                'cycle_number': c.cycle_number,
                'completed_classes': completed,
                'total_classes': total,
                'earned': float(c.earned_amount),
                'pending': float(c.pending_amount),
                'progress_percentage': pct,
            })

        payload = {
            'total_students': total_students,
            'total_earned': round(total_earned, 2),
            'total_pending': round(total_pending, 2),
            'lifetime_archived_earnings': round(lifetime_archived, 2),
            'chart_data': chart_data,
            'student_breakdowns': student_breakdowns,
        }

        serializer = WalletAnalyticsSerializer(payload)
        return Response(serializer.data)
