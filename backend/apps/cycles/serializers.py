"""
Cycles App Serializers

Serializers for:
  - Cycle detail & list with dynamic financial / attendance metrics
  - Toggle class request payload validation
  - Reset cycle response
"""
from rest_framework import serializers
from .models import Cycle


class CycleSerializer(serializers.ModelSerializer):
    """
    Complete representation of a billing cycle, including computed
    attendance counts, earned/pending revenue, and percentage.
    """
    student_id = serializers.UUIDField(source='student.id', read_only=True)
    student_name = serializers.SerializerMethodField()
    completed_classes = serializers.ReadOnlyField()
    earned_amount = serializers.ReadOnlyField()
    pending_amount = serializers.ReadOnlyField()
    is_complete = serializers.ReadOnlyField()
    progress_percentage = serializers.SerializerMethodField()

    class Meta:
        model = Cycle
        fields = [
            'id',
            'student_id',
            'student_name',
            'cycle_number',
            'fee_snapshot',
            'total_classes',
            'completed_classes',
            'earned_amount',
            'pending_amount',
            'progress_percentage',
            'is_complete',
            'status',
            'classes_data',
            'notes',
            'created_at',
            'updated_at',
        ]
        read_only_fields = [
            'id',
            'student_id',
            'student_name',
            'cycle_number',
            'fee_snapshot',
            'total_classes',
            'completed_classes',
            'earned_amount',
            'pending_amount',
            'progress_percentage',
            'is_complete',
            'status',
            'created_at',
            'updated_at',
        ]

    def get_student_name(self, obj):
        return obj.student.get_full_name() or obj.student.username

    def get_progress_percentage(self, obj):
        if not obj.total_classes:
            return 0.0
        return round((obj.completed_classes / obj.total_classes) * 100, 1)

    def to_representation(self, instance):
        """Strip fee and billing figures when viewed by a student."""
        data = super().to_representation(instance)
        request = self.context.get('request')
        if request and getattr(request.user, 'role', None) == 'STUDENT':
            data.pop('fee_snapshot', None)
            data.pop('earned_amount', None)
            data.pop('pending_amount', None)
        return data


class ToggleClassSerializer(serializers.Serializer):
    """
    Validates input for PATCH /api/v1/cycles/<id>/toggle_class/
    Supports both class_no and classNo, along with optional date and topic.
    """
    class_no = serializers.IntegerField(required=False, min_value=1)
    classNo = serializers.IntegerField(required=False, min_value=1)
    completed = serializers.BooleanField(required=True)
    date = serializers.DateTimeField(required=False, allow_null=True)
    topic = serializers.CharField(required=False, allow_blank=True, max_length=255)

    def validate(self, attrs):
        class_num = attrs.get('class_no') or attrs.get('classNo')
        if class_num is None:
            raise serializers.ValidationError('Either "class_no" or "classNo" must be provided.')
        attrs['resolved_class_no'] = class_num
        return attrs

