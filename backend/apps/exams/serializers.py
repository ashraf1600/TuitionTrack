"""
Exams App Serializers

Handles serialization for:
  - Exam list, create, update, detail with dynamic status, batch assignment, and MCQs
  - Student exam submission payload & validation
  - Auto-grading & tutor grading payload & validation
  - Leaderboard generation for tuition batch / student rankings
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
            'mcq_score',
            'cq_score',
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
            'mcq_score',
            'cq_score',
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
    batch_name = serializers.SerializerMethodField()
    dynamic_status = serializers.SerializerMethodField()
    has_submission = serializers.SerializerMethodField()
    submission_id = serializers.SerializerMethodField()
    mcq_count = serializers.SerializerMethodField()

    class Meta:
        model = Exam
        fields = [
            'id',
            'title',
            'exam_type',
            'tutor',
            'tutor_name',
            'student',
            'student_name',
            'batch',
            'batch_name',
            'total_marks',
            'start_time',
            'end_time',
            'duration_minutes',
            'grace_period_minutes',
            'is_published',
            'is_results_published',
            'mcq_count',
            'dynamic_status',
            'has_submission',
            'submission_id',
            'created_at',
        ]
        read_only_fields = fields

    def get_tutor_name(self, obj):
        return obj.tutor.get_full_name() or obj.tutor.username

    def get_student_name(self, obj):
        if obj.student:
            return obj.student.get_full_name() or obj.student.username
        if obj.batch:
            return f'Batch: {obj.batch.name}'
        return 'Unassigned'

    def get_batch_name(self, obj):
        return obj.batch.name if obj.batch else None

    def get_mcq_count(self, obj):
        return len(obj.mcq_data) if isinstance(obj.mcq_data, list) else 0

    def _get_submission(self, obj):
        if not hasattr(obj, '_cached_submission'):
            request = self.context.get('request')
            if request and request.user.role == 'STUDENT':
                obj._cached_submission = obj.submissions.filter(student=request.user).first()
            elif request and request.user.role == 'TUTOR' and obj.student:
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
    batch_name = serializers.SerializerMethodField()
    dynamic_status = serializers.SerializerMethodField()
    submission = serializers.SerializerMethodField()
    can_submit = serializers.SerializerMethodField()
    mcq_data = serializers.SerializerMethodField()
    solution_html = serializers.SerializerMethodField()

    class Meta:
        model = Exam
        fields = [
            'id',
            'title',
            'exam_type',
            'content_html',
            'mcq_data',
            'solution_html',
            'solution_media_url',
            'tutor',
            'tutor_name',
            'student',
            'student_name',
            'batch',
            'batch_name',
            'total_marks',
            'start_time',
            'end_time',
            'duration_minutes',
            'grace_period_minutes',
            'is_published',
            'is_results_published',
            'dynamic_status',
            'can_submit',
            'submission',
            'created_at',
            'updated_at',
        ]
        read_only_fields = fields

    def get_tutor_name(self, obj):
        return obj.tutor.get_full_name() or obj.tutor.username

    def get_student_name(self, obj):
        if obj.student:
            return obj.student.get_full_name() or obj.student.username
        if obj.batch:
            return f'Batch: {obj.batch.name}'
        return 'Unassigned'

    def get_batch_name(self, obj):
        return obj.batch.name if obj.batch else None

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

    def get_mcq_data(self, obj):
        """
        Hide answers and explanations for students if they haven't submitted
        or if results are not yet published.
        """
        request = self.context.get('request')
        questions = obj.mcq_data or []
        if not request:
            return questions

        sub = self._get_submission(obj)
        # If student hasn't submitted yet, hide correct answer
        if request.user.role == 'STUDENT' and not sub:
            sanitized_q = []
            for q in questions:
                q_copy = dict(q)
                q_copy.pop('correct_answer', None)
                q_copy.pop('explanation', None)
                sanitized_q.append(q_copy)
            return sanitized_q

        return questions

    def get_solution_html(self, obj):
        """Show solutions only after submission or to tutors."""
        request = self.context.get('request')
        if not request or request.user.role == 'TUTOR':
            return obj.solution_html
        sub = self._get_submission(obj)
        if sub and obj.is_results_published:
            return obj.solution_html
        return ''


class ExamCreateUpdateSerializer(serializers.ModelSerializer):
    """
    Serializer for creating and editing exams by tutors.
    Supports either student_id (1-on-1) or batch_id (Tuition batch).
    """
    student_id = serializers.UUIDField(required=False, allow_null=True, write_only=True)
    batch_id = serializers.UUIDField(required=False, allow_null=True, write_only=True)

    class Meta:
        model = Exam
        fields = [
            'id',
            'title',
            'exam_type',
            'student_id',
            'batch_id',
            'content_html',
            'mcq_data',
            'solution_html',
            'solution_media_url',
            'total_marks',
            'start_time',
            'end_time',
            'duration_minutes',
            'grace_period_minutes',
            'is_published',
            'is_results_published',
        ]
        read_only_fields = ['id']

    def validate_content_html(self, value):
        if not value:
            return ''
        return sanitize_exam_html(value)

    def validate_solution_html(self, value):
        if not value:
            return ''
        return sanitize_exam_html(value)

    def validate(self, attrs):
        start = attrs.get('start_time') or (self.instance.start_time if self.instance else None)
        end = attrs.get('end_time') or (self.instance.end_time if self.instance else None)

        if start and end and end <= start:
            raise serializers.ValidationError({'end_time': 'End time must be strictly after start time.'})

        request = self.context.get('request')
        from apps.students.models import TuitionBatch

        student_id = attrs.pop('student_id', None)
        batch_id = attrs.pop('batch_id', None)

        if student_id:
            try:
                attrs['student'] = User.objects.get(id=student_id, role=User.Role.STUDENT)
            except User.DoesNotExist:
                raise serializers.ValidationError({'student_id': 'Selected student does not exist.'})
        elif batch_id:
            try:
                attrs['batch'] = TuitionBatch.objects.get(id=batch_id, tutor=request.user)
            except TuitionBatch.DoesNotExist:
                raise serializers.ValidationError({'batch_id': 'Selected tuition batch does not exist.'})
        elif not self.instance:
            raise serializers.ValidationError('You must assign the exam to either a Student or a Tuition Batch.')

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
    obtained_marks = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, min_value=0)
    cq_score = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, min_value=0)
    tutor_feedback = serializers.CharField(required=False, allow_blank=True, default='')

    def validate(self, attrs):
        submission = self.context.get('submission')
        marks = attrs.get('obtained_marks')
        if marks is not None and submission and marks > submission.exam.total_marks:
            raise serializers.ValidationError(
                f'Obtained marks ({marks}) cannot exceed exam total marks ({submission.exam.total_marks}).'
            )
        return attrs


class LeaderboardEntrySerializer(serializers.Serializer):
    rank = serializers.IntegerField()
    student_id = serializers.UUIDField()
    student_name = serializers.CharField()
    obtained_marks = serializers.FloatField()
    total_marks = serializers.FloatField()
    percentage = serializers.FloatField()
    mcq_score = serializers.FloatField()
    cq_score = serializers.FloatField(allow_null=True)
    status = serializers.CharField()
    submitted_at = serializers.DateTimeField()
    is_graded = serializers.BooleanField()
