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

    def to_representation(self, instance):
        data = super().to_representation(instance)
        request = self.context.get('request')
        is_student = request and getattr(request.user, 'role', None) == 'STUDENT'
        from datetime import timedelta
        now = timezone.now()
        exam = instance.exam
        grace_limit = exam.end_time + timedelta(minutes=exam.grace_period_minutes)
        window_active = (now <= grace_limit)

        if is_student and (not exam.is_results_published or window_active):
            data['mcq_score'] = None
            data['cq_score'] = None
            data['obtained_marks'] = None
            data['tutor_feedback'] = ''
            data['is_graded'] = False
        return data



class ExamListSerializer(serializers.ModelSerializer):
    """Serializer for GET /api/v1/exams/ (list view)."""
    tutor_name = serializers.SerializerMethodField()
    tuition_id = serializers.UUIDField(source='tuition.id', read_only=True, allow_null=True)
    tuition_title = serializers.CharField(source='tuition.title', read_only=True, allow_null=True)
    student_name = serializers.SerializerMethodField()
    batch_name = serializers.SerializerMethodField()
    dynamic_status = serializers.SerializerMethodField()
    has_submission = serializers.SerializerMethodField()
    submission_id = serializers.SerializerMethodField()
    submissions_count = serializers.SerializerMethodField()
    mcq_count = serializers.SerializerMethodField()

    class Meta:
        model = Exam
        fields = [
            'id',
            'title',
            'category',
            'exam_type',
            'tutor',
            'tutor_name',
            'tuition_id',
            'tuition_title',
            'student',
            'student_name',
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
            'submissions_count',
            'created_at',
        ]
        read_only_fields = fields

    def get_tutor_name(self, obj):
        return obj.tutor.get_full_name() or obj.tutor.username

    def get_student_name(self, obj):
        if obj.student:
            return obj.student.get_full_name() or obj.student.username
        if obj.tuition:
            return f'Tuition: {obj.tuition.title}'
        return 'Unassigned'

    def get_batch_name(self, obj):
        return obj.tuition.title if obj.tuition else None

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
        request = self.context.get('request')
        if request and request.user.role == 'TUTOR':
            if obj.student:
                return self._get_submission(obj) is not None
            return obj.submissions.exists()
        return self._get_submission(obj) is not None

    def get_submission_id(self, obj):
        sub = self._get_submission(obj)
        return str(sub.id) if sub else None

    def get_submissions_count(self, obj):
        return obj.submissions.count()


class ExamDetailSerializer(serializers.ModelSerializer):
    """Serializer for GET /api/v1/exams/<id>/ (detail view)."""
    tutor_name = serializers.SerializerMethodField()
    tuition_id = serializers.UUIDField(source='tuition.id', read_only=True, allow_null=True)
    tuition_title = serializers.CharField(source='tuition.title', read_only=True, allow_null=True)
    student_name = serializers.SerializerMethodField()
    batch_name = serializers.SerializerMethodField()
    dynamic_status = serializers.SerializerMethodField()
    submission = serializers.SerializerMethodField()
    submissions = serializers.SerializerMethodField()
    can_submit = serializers.SerializerMethodField()
    mcq_data = serializers.SerializerMethodField()
    solution_html = serializers.SerializerMethodField()
    solution_media_url = serializers.SerializerMethodField()

    class Meta:
        model = Exam
        fields = [
            'id',
            'title',
            'category',
            'exam_type',
            'content_html',
            'mcq_data',
            'solution_html',
            'solution_media_url',
            'tutor',
            'tutor_name',
            'tuition_id',
            'tuition_title',
            'student',
            'student_name',
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
            'submissions',
            'created_at',
            'updated_at',
        ]
        read_only_fields = fields

    def to_representation(self, instance):
        data = super().to_representation(instance)
        request = self.context.get('request')
        now = timezone.now()
        is_student = request and getattr(request.user, 'role', None) == 'STUDENT'

        # Strict Time-Locked Anti-Cheat Security Invariant:
        # Before the scheduled start_time, students must NEVER receive content_html, mcq_data, or solutions.
        if is_student and now < instance.start_time:
            data['content_html'] = ''
            data['mcq_data'] = []
            data['solution_html'] = ''
            data['solution_media_url'] = ''
        elif is_student:
            sub = self._get_submission(instance)
            from datetime import timedelta
            grace_limit = instance.end_time + timedelta(minutes=instance.grace_period_minutes)
            window_active = (now <= grace_limit)
            if not (sub and instance.is_results_published and not window_active):
                data['solution_media_url'] = ''
                data['solution_html'] = ''
                stripped = []
                for q in (data.get('mcq_data') or []):
                    q_copy = dict(q)
                    q_copy.pop('correct_answer', None)
                    q_copy.pop('explanation', None)
                    stripped.append(q_copy)
                data['mcq_data'] = stripped


        return data

    def get_tutor_name(self, obj):
        return obj.tutor.get_full_name() or obj.tutor.username

    def get_student_name(self, obj):
        if obj.student:
            return obj.student.get_full_name() or obj.student.username
        if obj.tuition:
            return f'Tuition: {obj.tuition.title}'
        return 'All Enrolled Students'

    def get_batch_name(self, obj):
        return obj.tuition.title if obj.tuition else None

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

    def get_submission(self, obj):
        sub = self._get_submission(obj)
        if sub:
            return ExamSubmissionSerializer(sub, context=self.context).data
        return None

    def get_submissions(self, obj):
        request = self.context.get('request')
        if not request or request.user.role != 'TUTOR':
            return []
        return ExamSubmissionSerializer(obj.submissions.all().order_by('-submitted_at'), many=True, context=self.context).data

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

        if request.user.role == 'STUDENT':
            sub = self._get_submission(obj)
            if not sub or not obj.is_results_published:
                sanitized_q = []
                for q in questions:
                    q_copy = dict(q)
                    q_copy.pop('correct_answer', None)
                    q_copy.pop('explanation', None)
                    sanitized_q.append(q_copy)
                return sanitized_q

        return questions

    def get_solution_html(self, obj):
        """Show solutions only after submission AND published, or to tutors."""
        request = self.context.get('request')
        if not request or request.user.role == 'TUTOR':
            return obj.solution_html
        sub = self._get_submission(obj)
        if sub and obj.is_results_published:
            return obj.solution_html
        return ''

    def get_solution_media_url(self, obj):
        """Show solution media only after submission AND published, or to tutors."""
        request = self.context.get('request')
        if not request or request.user.role == 'TUTOR':
            return obj.solution_media_url
        sub = self._get_submission(obj)
        if sub and obj.is_results_published:
            return obj.solution_media_url
        return ''


class ExamCreateUpdateSerializer(serializers.ModelSerializer):
    """
    Serializer for creating and editing exams by tutors.
    Supports tuition_id (Tuition-centric), batch_id, or student_id.
    """
    tuition_id = serializers.UUIDField(required=False, allow_null=True, write_only=True)
    batch_id = serializers.UUIDField(required=False, allow_null=True, write_only=True)
    student_id = serializers.UUIDField(required=False, allow_null=True, write_only=True)

    class Meta:
        model = Exam
        fields = [
            'id',
            'title',
            'category',
            'exam_type',
            'tuition_id',
            'batch_id',
            'student_id',

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

        if not self.instance:
            if end and end <= timezone.now():
                raise serializers.ValidationError({'end_time': 'Exam end time cannot be in the past.'})

        total_marks = attrs.get('total_marks') or (self.instance.total_marks if self.instance else None)
        mcq_data = attrs.get('mcq_data') if 'mcq_data' in attrs else (self.instance.mcq_data if self.instance else None)

        if 'mcq_data' in attrs and attrs['mcq_data'] is not None:
            raw_mcq = attrs['mcq_data']
            if not isinstance(raw_mcq, list):
                raise serializers.ValidationError({'mcq_data': 'mcq_data must be a list of questions.'})

            is_published = attrs.get('is_published') if 'is_published' in attrs else (self.instance.is_published if self.instance else False)
            normalized_mcq = []
            import uuid

            placeholder_choices = {'option 1', 'option 2', 'option 3', 'option 4', 'choice 1', 'choice 2', 'sample option'}

            for idx, q in enumerate(raw_mcq):
                if not isinstance(q, dict):
                    raise serializers.ValidationError({'mcq_data': f'Question item #{idx+1} must be an object.'})

                # Server-side UUID generation for question items
                q_id = str(q.get('id') or '')
                try:
                    uuid.UUID(q_id)
                except (ValueError, AttributeError):
                    q_id = str(uuid.uuid4())

                question_text = str(q.get('question', '')).strip()
                options = q.get('options', [])
                if not isinstance(options, list) or len(options) < 2:
                    raise serializers.ValidationError({'mcq_data': f'Question #{idx+1} must contain at least 2 options.'})

                # Reject default placeholder choices when published
                if is_published:
                    for opt in options:
                        if str(opt).strip().lower() in placeholder_choices:
                            raise serializers.ValidationError({
                                'mcq_data': f'Question #{idx+1} contains default placeholder choice "{opt}". Please provide real answer choices before publishing.'
                            })

                # Normalize question answer keys to 0-based numeric indices
                raw_ans = q.get('correct_answer')
                if raw_ans is None or raw_ans == '':
                    if is_published:
                        raise serializers.ValidationError({
                            'mcq_data': f'Question #{idx+1} is missing a correct answer key.'
                        })
                    correct_idx = None
                else:
                    try:
                        if isinstance(raw_ans, str) and raw_ans.strip().upper() in ('A', 'B', 'C', 'D', 'E'):
                            correct_idx = ord(raw_ans.strip().upper()) - ord('A')
                        else:
                            correct_idx = int(raw_ans)
                    except (ValueError, TypeError):
                        raise serializers.ValidationError({
                            'mcq_data': f'Question #{idx+1} has invalid correct_answer key: {raw_ans}'
                        })
                    if correct_idx < 0 or correct_idx >= len(options):
                        raise serializers.ValidationError({
                            'mcq_data': f'Question #{idx+1} correct_answer index ({correct_idx}) is out of bounds for {len(options)} options.'
                        })

                normalized_q = dict(q)
                normalized_q['id'] = q_id
                normalized_q['question'] = question_text
                normalized_q['options'] = [str(o).strip() for o in options]
                if correct_idx is not None:
                    normalized_q['correct_answer'] = correct_idx
                normalized_mcq.append(normalized_q)

            attrs['mcq_data'] = normalized_mcq
            mcq_data = normalized_mcq

        if mcq_data and isinstance(mcq_data, list) and total_marks is not None:
            sum_points = 0.0
            for q in mcq_data:
                p = q.get('points') if q.get('points') is not None else q.get('marks', 1)
                try:
                    sum_points += float(p)
                except (ValueError, TypeError):
                    pass
            if sum_points > float(total_marks):
                raise serializers.ValidationError({
                    'mcq_data': f'Sum of MCQ points ({sum_points}) cannot exceed total marks ({total_marks}).'
                })


        request = self.context.get('request')
        from apps.students.models import Tuition

        tuition_id = attrs.pop('tuition_id', None) or attrs.pop('batch_id', None)
        student_id = attrs.pop('student_id', None)

        provided = [bool(tuition_id), bool(student_id)]
        if sum(provided) > 1:
            raise serializers.ValidationError('Assign the exam to exactly one target: tuition or student.')
        # Partial update without target keys: keep existing targets.
        if not any(provided):
            if not self.instance:
                raise serializers.ValidationError('You must assign the exam to a Tuition or Student.')
            return attrs

        if tuition_id:
            try:
                tuition = Tuition.objects.get(id=tuition_id, tutor=request.user)
            except Tuition.DoesNotExist:
                raise serializers.ValidationError({'tuition_id': 'Selected tuition does not exist.'})
            attrs['tuition'] = tuition
            attrs['student'] = None
        elif student_id:
            try:
                from django.db.models import Q
                student = User.objects.get(
                    Q(id=student_id, role=User.Role.STUDENT) &
                    (Q(tutor=request.user) | Q(selected_tutor=request.user))
                )
            except User.DoesNotExist:
                raise serializers.ValidationError({'student_id': 'Selected student does not exist or belongs to another tutor.'})
            attrs['student'] = student
            attrs['tuition'] = None


        return attrs


class SubmitExamSerializer(serializers.Serializer):
    """Validates payload for student exam submission."""
    answers_data = serializers.DictField(required=False, default=dict, child=serializers.CharField(max_length=5000))
    uploaded_images = serializers.ListField(
        child=serializers.CharField(max_length=500),
        required=False,
        default=list,
        max_length=20,
    )
    image_urls = serializers.ListField(
        child=serializers.CharField(max_length=500),
        required=False,
        default=list,
        max_length=20,
    )

    def validate_answers_data(self, value):
        if len(value) > 200:
            raise serializers.ValidationError('Too many answers (max 200).')
        return value

    def validate(self, attrs):
        for key in ('uploaded_images', 'image_urls'):
            for url in attrs.get(key, []) or []:
                u = (url or '').strip()
                if not u:
                    raise serializers.ValidationError({key: 'Empty URL is not allowed.'})
                low = u.lower()
                if low.startswith(('javascript:', 'data:text/html', 'vbscript:')):
                    raise serializers.ValidationError({key: 'Unsafe URL scheme.'})
                if len(u) > 500:
                    raise serializers.ValidationError({key: 'URL too long.'})
        return attrs


class GradeSubmissionSerializer(serializers.Serializer):
    """Validates payload for tutor grading."""
    obtained_marks = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, min_value=0)
    cq_score = serializers.DecimalField(max_digits=6, decimal_places=2, required=False, min_value=0)
    tutor_feedback = serializers.CharField(required=False, allow_blank=True, default='')

    def validate(self, attrs):
        submission = self.context.get('submission')
        total = submission.exam.total_marks if submission else None
        cq_score = attrs.get('cq_score')
        obtained_marks = attrs.get('obtained_marks')

        if cq_score is not None and submission and total is not None:
            mcq = float(submission.mcq_score or 0)
            if (mcq + float(cq_score)) > float(total):
                raise serializers.ValidationError(
                    {'cq_score': f'Combined score ({mcq + float(cq_score)}) cannot exceed exam total marks ({total}).'}
                )
        if obtained_marks is not None and total is not None and float(obtained_marks) > float(total):
            raise serializers.ValidationError(
                {'obtained_marks': f'Obtained marks ({obtained_marks}) cannot exceed exam total marks ({total}).'}
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
