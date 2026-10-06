"""
Exams App Serializers

Handles serialization for:
  - Exam list, create, update, detail with dynamic status
  - Student exam submission payload & validation
  - Tutor grading payload & validation
  - Media upload response
"""
from rest_framework import serializers
from django.utils import timezone
from django.contrib.auth import get_user_model

from .models import Exam, ExamSubmission
from .sanitizer import sanitize_exam_html

User = get_user_model()


class ExamSubmissionSerializer(serializers.ModelSerializer):
    """Serializes student submission details."""
    student_name = serializers.SerializerMethodField()

    class Meta:
        model = ExamSubmission
        fields = [
            'id',
            'exam',
            'student',
            'student_name',
            'submitted_at',
            'answers_data',
            'image_urls',
            'status',
            'obtained_marks',
            'tutor_feedback',
            'is_graded',
            'graded_at',
            'created_at',
            'updated_at',
        ]
        read_only_fields = [
            'id',
            'student',
            'student_name',
            'submitted_at',
            'status',
            'obtained_marks',
            'tutor_feedback',
            'is_graded',
            'graded_at',
            'created_at',
            'updated_at',
        ]

    def get_student_name(self, obj):
        return obj.student.get_full_name() or obj.student.username


class ExamListSerializer(serializers.ModelSerializer):
    """Serializer for GET /api/v1/exams/ (list view)."""
    tutor_name = serializers.SerializerMethodField()
    student_name = serializers.SerializerMethodField()
    dynamic_status = serializers.SerializerMethodField()
    has_submission = serializers.SerializerMethodField()
    submission_id = serializers.SerializerMethodField()

    class Meta:
        model = Exam
        fields = [
            'id',
            'title',
            'tutor',
            'tutor_name',
            'student',
            'student_name',
            'total_marks',
            'start_time',
            'end_time',
            'duration_minutes',
            'grace_period_minutes',
            'is_published',
            'dynamic_status',
            'has_submission',
            'submission_id',
            'created_at',
        ]
        read_only_fields = fields

    def get_tutor_name(self, obj):
        return obj.tutor.get_full_name() or obj.tutor.username

    def get_student_name(self, obj):
        return obj.student.get_full_name() or obj.student.username

    def _get_submission(self, obj):
        # Cache submission on obj to avoid duplicate queries
        if not hasattr(obj, '_cached_submission'):
            request = self.context.get('request')
            if request and request.user.role == 'STUDENT':
                obj._cached_submission = obj.submissions.filter(student=request.user).first()
            elif request and request.user.role == 'TUTOR':
                obj._cached_submission = obj.submissions.filter(student=obj.student).first()
            else:
                obj._cached_submission = obj.submissions.first()
        return obj._cached_submission

    def get_dynamic_status(self, obj):
        sub = self._get_submission(obj)
        return obj.get_dynamic_status(sub)

    def get_has_submission(self, obj):
        return self._get_submission(obj) is not None

    def get_submission_id(self, obj):
        sub = self._get_submission(obj)
        return str(sub.id) if sub else None


class ExamDetailSerializer(serializers.ModelSerializer):
    """Serializer for GET /api/v1/exams/<id>/ (detail view)."""
    tutor_name = serializers.SerializerMethodField()
    student_name = serializers.SerializerMethodField()
    dynamic_status = serializers.SerializerMethodField()
    submission = serializers.SerializerMethodField()
    can_submit = serializers.SerializerMethodField()

    class Meta:
        model = Exam
        fields = [
            'id',
            'title',
            'content_html',
            'tutor',
            'tutor_name',
            'student',
            'student_name',
            'total_marks',
            'start_time',
            'end_time',
            'duration_minutes',
            'grace_period_minutes',
            'is_published',
            'dynamic_status',
            'can_submit',
            'submission',
            'created_at',
            'updated_at',
        ]
        read_only_fields = [
            'id',
            'tutor',
            'tutor_name',
            'student_name',
            'dynamic_status',
            'can_submit',
            'submission',
            'created_at',
            'updated_at',
        ]

    def get_tutor_name(self, obj):
        return obj.tutor.get_full_name() or obj.tutor.username

    def get_student_name(self, obj):
        return obj.student.get_full_name() or obj.student.username

    def _get_submission(self, obj):
        if not hasattr(obj, '_cached_submission'):
            request = self.context.get('request')
            if request and request.user.role == 'STUDENT':
                obj._cached_submission = obj.submissions.filter(student=request.user).first()
            else:
                obj._cached_submission = obj.submissions.first()
        return obj._cached_submission

    def get_dynamic_status(self, obj):
        sub = self._get_submission(obj)
        return obj.get_dynamic_status(sub)

    def get_submission(self, obj):
        sub = self._get_submission(obj)
        if sub:
            return ExamSubmissionSerializer(sub).data
        return None

    def get_can_submit(self, obj):
        request = self.context.get('request')
        if not request or request.user.role != 'STUDENT':
            return False
        sub = self._get_submission(obj)
        if sub:
            return False
        return obj.can_submit()


class ExamCreateUpdateSerializer(serializers.ModelSerializer):
    """
    Serializer for creating and editing exams by tutors.
    Automatically applies nh3 sanitization to content_html.
    """
    student_id = serializers.UUIDField(write_only=True)

    class Meta:
        model = Exam
        fields = [
            'id',
            'title',
            'student_id',
            'content_html',
            'total_marks',
            'start_time',
            'end_time',
            'duration_minutes',
            'grace_period_minutes',
            'is_published',
        ]
        read_only_fields = ['id']

    def validate_content_html(self, value):
        """Sanitize rich-text content to eliminate any stored XSS."""
        if not value:
            return ''
        return sanitize_exam_html(value)

    def validate(self, attrs):
        start = attrs.get('start_time') or (self.instance.start_time if self.instance else None)
        end = attrs.get('end_time') or (self.instance.end_time if self.instance else None)

        if start and end and end <= start:
            raise serializers.ValidationError({'end_time': 'End time must be strictly after start time.'})

        # Validate student belongs to the tutor
        request = self.context.get('request')
        if request and 'student_id' in attrs:
            student_id = attrs['student_id']
            try:
                student = User.objects.get(id=student_id, role='STUDENT', tutor=request.user)
                attrs['student'] = student
            except User.DoesNotExist:
                raise serializers.ValidationError({'student_id': 'Student not found or does not belong to you.'})

        return attrs


class SubmitExamSerializer(serializers.Serializer):
    """Validates payload for student exam submission."""
    answers_data = serializers.DictField(required=False, default=dict)
    image_urls = serializers.ListField(
        child=serializers.CharField(),
        required=False,
        default=list
    )


class GradeSubmissionSerializer(serializers.Serializer):
    """Validates payload for tutor grading."""
    obtained_marks = serializers.DecimalField(max_digits=6, decimal_places=2, min_value=0)
    tutor_feedback = serializers.CharField(required=False, allow_blank=True, default='')

    def validate_obtained_marks(self, value):
        submission = self.context.get('submission')
        if submission and value > submission.exam.total_marks:
            raise serializers.ValidationError(
                f'Obtained marks ({value}) cannot exceed exam total marks ({submission.exam.total_marks}).'
            )
        return value
