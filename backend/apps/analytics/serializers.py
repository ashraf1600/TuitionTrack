"""
Analytics App Serializers

Serializers for Tutor Wallet analytics and earnings breakdowns.
"""
from rest_framework import serializers


class ChartItemSerializer(serializers.Serializer):
    name = serializers.CharField()
    value = serializers.FloatField()
    color = serializers.CharField()


class StudentBreakdownSerializer(serializers.Serializer):
    student_id = serializers.UUIDField()
    student_name = serializers.CharField()
    cycle_id = serializers.UUIDField()
    cycle_number = serializers.IntegerField()
    completed_classes = serializers.IntegerField()
    total_classes = serializers.IntegerField()
    earned = serializers.FloatField()
    pending = serializers.FloatField()
    progress_percentage = serializers.FloatField()


class TuitionBreakdownSerializer(serializers.Serializer):
    tuition_id = serializers.UUIDField()
    tuition_title = serializers.CharField()
    student_count = serializers.IntegerField()
    cycle_id = serializers.UUIDField()
    cycle_number = serializers.IntegerField()
    completed_classes = serializers.IntegerField()
    total_classes = serializers.IntegerField()
    total_fee = serializers.FloatField()
    per_class_rate = serializers.FloatField()
    earned = serializers.FloatField()
    pending = serializers.FloatField()
    progress_percentage = serializers.FloatField()


class UnpaidCycleSerializer(serializers.Serializer):
    cycle_id = serializers.UUIDField()
    tuition_id = serializers.UUIDField(allow_null=True)
    tuition_title = serializers.CharField()
    cycle_number = serializers.IntegerField()
    completed_classes = serializers.IntegerField()
    total_classes = serializers.IntegerField()
    amount = serializers.FloatField()
    # When the cycle was closed (its last change), i.e. since when the money is due.
    finished_at = serializers.DateTimeField()


class PaidCycleSerializer(serializers.Serializer):
    cycle_id = serializers.UUIDField()
    tuition_id = serializers.UUIDField(allow_null=True)
    tuition_title = serializers.CharField()
    cycle_number = serializers.IntegerField()
    amount = serializers.FloatField()
    paid_at = serializers.DateTimeField()


class WalletAnalyticsSerializer(serializers.Serializer):
    total_students = serializers.IntegerField()
    total_tuitions = serializers.IntegerField()
    total_earned = serializers.FloatField()
    total_pending = serializers.FloatField()
    lifetime_archived_earnings = serializers.FloatField()
    # Finished cycles not marked paid yet, and what they come to.
    unpaid_cycles = serializers.IntegerField()
    unpaid_total = serializers.FloatField()
    unpaid_list = UnpaidCycleSerializer(many=True)
    # The last few cycles marked paid, newest first.
    recent_paid = PaidCycleSerializer(many=True)
    chart_data = ChartItemSerializer(many=True)
    tuition_breakdowns = TuitionBreakdownSerializer(many=True)
    # Legacy 1-on-1 cycles that predate tuition groups.
    student_breakdowns = StudentBreakdownSerializer(many=True)
