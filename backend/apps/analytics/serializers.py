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


class WalletAnalyticsSerializer(serializers.Serializer):
    total_students = serializers.IntegerField()
    total_earned = serializers.FloatField()
    total_pending = serializers.FloatField()
    lifetime_archived_earnings = serializers.FloatField()
    chart_data = ChartItemSerializer(many=True)
    student_breakdowns = StudentBreakdownSerializer(many=True)
