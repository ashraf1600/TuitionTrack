"""
Exams App Serializers

Handles serialization for:
  - Exam list, create, update, detail with dynamic status, batch assignment, and MCQs
  - Student exam submission payload & validation
  - Auto-grading & tutor grading payload & validation
  - Leaderboard generation for tuition batch / student rankings
"""
from rest_framework import serializers
from rest_framework.exceptions import PermissionDenied
from django.utils import timezone
from django.contrib.auth import get_user_model

from .models import Exam, ExamAttempt, ExamSubmission
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
            'text_answer',
            'image_urls',
            'started_at',
            'status',
            'mcq_score',
            'cq_score',
            'cq_breakdown',
            'obtained_marks',
            'tutor_feedback',
            'is_graded',
            'graded_at',
            'created_at',
            'updated_at',
        ]
        read_only_fields = [
            'cq_breakdown',
            'id',
            'student',
            'student_name',
            'submitted_at',
            'started_at',
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

        if is_student and not instance.exam.results_released(instance):
            data['mcq_score'] = None
            data['cq_score'] = None
            data['cq_breakdown'] = {}
            data['obtained_marks'] = None
            data['tutor_feedback'] = ''
            data['is_graded'] = False
        return data



def _real_submissions(exam):
    """Submissions a student actually made (auto-created MISSED placeholders excluded)."""
    return [sub for sub in exam.submissions.all() if sub.status != ExamSubmission.Status.MISSED]


def _own_submission(exam, request):
    """The submission the current viewer is concerned with, if any."""
    if not request:
        return None
    if request.user.role == 'STUDENT':
        student_id = request.user.id
    elif exam.student_id:
        student_id = exam.student_id
    else:
        return None
    return next((sub for sub in _real_submissions(exam) if sub.student_id == student_id), None)


# The only keys of a question a student may ever receive while results are not out.
# An allow-list, so a new answer-bearing key added later cannot leak by accident.
STUDENT_QUESTION_FIELDS = ('id', 'question', 'options', 'image_url')


def student_safe_questions(questions):
    """Questions with the answer key, explanations and anything unlisted removed."""
    safe = []
    for q in questions or []:
        if not isinstance(q, dict):
            continue
        item = {key: q[key] for key in STUDENT_QUESTION_FIELDS if key in q}
        item['points'] = q.get('points') if q.get('points') is not None else q.get('marks', 1)
        safe.append(item)
    return safe


def _result_status(exam, submission):
    """What a student may know about when results come out (never the results themselves)."""
    return {
        'released': exam.results_released(submission),
        'mode': exam.result_publish_mode,
        'publish_at': exam.results_release_time,
    }


def _assigned_student_count(exam):
    if exam.student_id:
        return 1
    if exam.tuition_id:
        return exam.tuition.enrollments.filter(is_active=True, student__is_active=True).count()
    return 0


def _status_for(exam, request, submission):
    """Dynamic status with tutor-friendly wording for drafts and finished group exams."""
    is_tutor = request and request.user.role == 'TUTOR'
    if is_tutor and not exam.is_published:
        return Exam.DynamicStatus.DRAFT
    status_text = exam.get_dynamic_status(submission)
    if is_tutor and not submission and status_text == Exam.DynamicStatus.MISSED:
        return Exam.DynamicStatus.CLOSED
    return status_text


class ExamListSerializer(serializers.ModelSerializer):
    """Serializer for GET /api/v1/exams/ (list view)."""
    can_submit = serializers.SerializerMethodField()
    graded_count = serializers.SerializerMethodField()
    assigned_count = serializers.SerializerMethodField()
    my_result = serializers.SerializerMethodField()
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
    results_released = serializers.SerializerMethodField()
    results_release_time = serializers.ReadOnlyField()

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
            'late_submission_until',
            'shuffle_questions',
            'negative_marks_per_wrong',
            'is_published',
            'is_results_published',
            'result_publish_mode',
            'publish_time',
            'results_released',
            'results_release_time',
            'mcq_count',
            'dynamic_status',
            'can_submit',
            'has_submission',
            'submission_id',
            'submissions_count',
            'graded_count',
            'assigned_count',
            'my_result',
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
            obj._cached_submission = _own_submission(obj, self.context.get('request'))
        return obj._cached_submission

    def get_dynamic_status(self, obj):
        return _status_for(obj, self.context.get('request'), self._get_submission(obj))

    def get_can_submit(self, obj):
        request = self.context.get('request')
        if not request or request.user.role != 'STUDENT':
            return False
        return self._get_submission(obj) is None and obj.can_submit()

    def get_has_submission(self, obj):
        request = self.context.get('request')
        if request and request.user.role == 'TUTOR' and not obj.student_id:
            return bool(_real_submissions(obj))
        return self._get_submission(obj) is not None

    def get_submission_id(self, obj):
        sub = self._get_submission(obj)
        return str(sub.id) if sub else None

    def get_submissions_count(self, obj):
        return len(_real_submissions(obj))

    def get_graded_count(self, obj):
        return sum(1 for sub in _real_submissions(obj) if sub.is_graded)

    def get_assigned_count(self, obj):
        request = self.context.get('request')
        if not request or request.user.role != 'TUTOR':
            return None
        return _assigned_student_count(obj)

    def get_results_released(self, obj):
        """Student: may I see my result now? Tutor: are results out for the group?"""
        request = self.context.get('request')
        if request and request.user.role == 'STUDENT':
            return obj.results_released(self._get_submission(obj))
        return obj.results_public()

    def get_my_result(self, obj):
        """A student's own marks, once results are released to them."""
        request = self.context.get('request')
        if not request or request.user.role != 'STUDENT':
            return None
        sub = self._get_submission(obj)
        if not sub:
            return None
        data = ExamSubmissionSerializer(sub, context=self.context).data
        return {
            'is_graded': data['is_graded'],
            'obtained_marks': data['obtained_marks'],
            'status': data['status'],
        }


class ExamDetailSerializer(serializers.ModelSerializer):
    """
    Full exam detail for the tutor who owns it, answer key included.
    Students are served by StudentExamSerializer; as a second line of defence this
    class also withholds every answer-bearing field from anyone who is not a tutor.
    """
    results_released = serializers.SerializerMethodField()
    results_release_time = serializers.ReadOnlyField()
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
    is_timed = serializers.ReadOnlyField()
    attempt_started_at = serializers.SerializerMethodField()
    attempt_deadline = serializers.SerializerMethodField()
    requires_start = serializers.SerializerMethodField()

    class Meta:
        model = Exam
        fields = [
            'id',
            'title',
            'category',
            'exam_type',
            'content_html',
            'mcq_data',
            'written_scheme',
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
            'late_submission_until',
            'shuffle_questions',
            'negative_marks_per_wrong',
            'is_timed',
            'attempt_started_at',
            'attempt_deadline',
            'requires_start',
            'is_published',
            'is_results_published',
            'result_publish_mode',
            'publish_time',
            'results_released',
            'results_release_time',
            'dynamic_status',
            'can_submit',
            'submission',
            'submissions',
            'created_at',
            'updated_at',
        ]
        read_only_fields = fields

    def _is_tutor(self):
        request = self.context.get('request')
        return bool(request and getattr(request.user, 'role', None) == 'TUTOR')

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if self._is_tutor():
            return data

        request = self.context.get('request')
        now = timezone.now()
        # Strict Time-Locked Anti-Cheat Security Invariant:
        # Before the scheduled start_time, students must NEVER receive content_html or mcq_data.
        if now < instance.start_time or data.get('requires_start'):
            # Not started yet (by the clock, or — for a timed exam — by this student).
            data['content_html'] = ''
            data['mcq_data'] = []
        elif instance.shuffle_questions and request and not self._get_submission(instance):
            # A different but stable order per student; answers are keyed by question id.
            import random
            random.Random(f'{instance.id}:{request.user.id}').shuffle(data['mcq_data'])
        return data

    def get_results_released(self, obj):
        if self._is_tutor():
            return obj.results_public()
        return obj.results_released(self._get_submission(obj))

    def _get_attempt(self, obj):
        if not hasattr(obj, '_cached_attempt'):
            request = self.context.get('request')
            obj._cached_attempt = (
                ExamAttempt.objects.filter(exam=obj, student=request.user).first()
                if request and request.user.role == 'STUDENT' else None
            )
        return obj._cached_attempt

    def get_attempt_started_at(self, obj):
        attempt = self._get_attempt(obj)
        return attempt.started_at if attempt else None

    def get_attempt_deadline(self, obj):
        """When this student's own on-time window ends (their timer, capped at end_time)."""
        attempt = self._get_attempt(obj)
        return obj.personal_deadline(attempt.started_at if attempt else None)

    def get_requires_start(self, obj):
        """Timed exam the student has not opened yet: questions stay hidden until they start."""
        request = self.context.get('request')
        if not request or request.user.role != 'STUDENT' or not obj.is_timed:
            return False
        return self._get_attempt(obj) is None and self._get_submission(obj) is None

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
            obj._cached_submission = _own_submission(obj, self.context.get('request'))
        return obj._cached_submission

    def get_dynamic_status(self, obj):
        return _status_for(obj, self.context.get('request'), self._get_submission(obj))

    def get_submission(self, obj):
        sub = self._get_submission(obj)
        if sub:
            return ExamSubmissionSerializer(sub, context=self.context).data
        return None

    def get_submissions(self, obj):
        request = self.context.get('request')
        if not request or request.user.role != 'TUTOR':
            return []
        subs = sorted(_real_submissions(obj), key=lambda sub: sub.submitted_at or timezone.now(), reverse=True)
        return ExamSubmissionSerializer(subs, many=True, context=self.context).data

    def get_can_submit(self, obj):
        request = self.context.get('request')
        if not request or request.user.role != 'STUDENT':
            return False
        sub = self._get_submission(obj)
        if sub:
            return False
        return obj.can_submit()

    def get_mcq_data(self, obj):
        """The answer key goes to tutors only. Students get it from the result endpoint, once released."""
        questions = obj.mcq_data or []
        return questions if self._is_tutor() else student_safe_questions(questions)

    def get_solution_html(self, obj):
        return obj.solution_html if self._is_tutor() else ''

    def get_solution_media_url(self, obj):
        return obj.solution_media_url if self._is_tutor() else ''


class StudentExamSerializer(ExamDetailSerializer):
    """
    What a student receives to sit an exam: GET /api/v1/exams/<id>/ and /start/.

    It has no answer-bearing field at all — no correct_answer, no explanation, no
    model solution — whatever the publication state. Marks and answers travel only
    through ExamResultSerializer, which refuses to run before results are released.
    """
    mcq_data = serializers.SerializerMethodField()
    result_status = serializers.SerializerMethodField()

    class Meta(ExamDetailSerializer.Meta):
        fields = [
            field for field in ExamDetailSerializer.Meta.fields
            if field not in ('solution_html', 'solution_media_url', 'submissions', 'is_results_published', 'publish_time')
        ] + ['result_status']
        read_only_fields = fields

    def _is_tutor(self):
        return False

    def get_mcq_data(self, obj):
        return student_safe_questions(obj.mcq_data)

    def get_result_status(self, obj):
        return _result_status(obj, self._get_submission(obj))


class ExamResultSerializer(serializers.Serializer):
    """
    A student's evaluated paper: every question with their answer, the correct
    answer and the marks it earned, plus written marks, feedback and solutions.

    Serialises an ExamSubmission. This is the only place the answer key is sent
    to a student, and it raises instead of serialising when results are not
    released for that submission.
    """

    def to_representation(self, submission):
        exam = submission.exam
        request = self.context.get('request')
        is_tutor = bool(request and getattr(request.user, 'role', None) == 'TUTOR')
        if not is_tutor and not exam.results_released(submission):
            raise PermissionDenied('Results are not published yet.')

        review = {row['id']: row for row in submission.mcq_review()}
        questions = []
        for idx, q in enumerate(exam.mcq_data or []):
            row = review.get(str(q.get('id', f'mcq-{idx}')), {})
            questions.append({
                'id': str(q.get('id', f'mcq-{idx}')),
                'question': q.get('question', ''),
                'image_url': q.get('image_url', ''),
                'options': q.get('options', []),
                'points': row.get('points', 1),
                'correct_answer': row.get('correct_answer'),
                'selected': row.get('selected'),
                'outcome': row.get('outcome', 'skipped'),
                'awarded': row.get('awarded', 0),
                'explanation': q.get('explanation', ''),
            })

        outcomes = [q['outcome'] for q in questions]
        breakdown = submission.cq_breakdown or {}
        total = float(exam.total_marks)
        obtained = float(submission.obtained_marks) if submission.obtained_marks is not None else None
        has_written = exam.exam_type != Exam.ExamType.MCQ
        return {
            'exam': {
                'id': str(exam.id),
                'title': exam.title,
                'category': exam.category,
                'exam_type': exam.exam_type,
                'total_marks': total,
                'negative_marks_per_wrong': float(exam.negative_marks_per_wrong or 0),
            },
            'status': submission.status,
            'submitted_at': submission.submitted_at,
            'is_graded': submission.is_graded,
            'obtained_marks': obtained,
            'percentage': round(obtained / total * 100, 1) if obtained is not None and total > 0 else None,
            'mcq_score': float(submission.mcq_score or 0),
            'mcq_total': round(sum(q['points'] for q in questions), 2),
            'cq_score': float(submission.cq_score) if submission.cq_score is not None else None,
            'summary': {
                'correct': outcomes.count('correct'),
                'wrong': outcomes.count('wrong'),
                'skipped': outcomes.count('skipped'),
            },
            'questions': questions,
            'written': {
                'content_html': exam.content_html,
                'scheme': [
                    {**item, 'awarded': breakdown.get(item['id'])} for item in (exam.written_scheme or [])
                ],
                'text_answer': submission.text_answer,
                'image_urls': submission.uploaded_images or submission.image_urls or [],
                # A written part that has not been marked yet is "awaiting marking", not zero.
                'awaiting_marking': has_written and not submission.is_graded,
            } if has_written else None,
            'tutor_feedback': submission.tutor_feedback,
            'solution_html': exam.solution_html,
            'solution_media_url': exam.solution_media_url,
        }


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
            'written_scheme',
            'solution_html',
            'solution_media_url',
            'total_marks',
            'start_time',
            'end_time',
            'duration_minutes',
            'grace_period_minutes',
            'late_submission_until',
            'shuffle_questions',
            'negative_marks_per_wrong',
            'is_published',
            'is_results_published',
            'result_publish_mode',
            'publish_time',
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

    def validate_written_scheme(self, value):
        """Normalise to [{id, label, marks}] with server-made ids and positive marks."""
        import uuid
        if value in (None, ''):
            return []
        if not isinstance(value, list):
            raise serializers.ValidationError('The marking scheme must be a list.')
        if len(value) > 50:
            raise serializers.ValidationError('A marking scheme can have at most 50 questions.')
        scheme = []
        for idx, item in enumerate(value):
            if not isinstance(item, dict):
                raise serializers.ValidationError(f'Written question #{idx + 1} must be an object.')
            label = str(item.get('label', '')).strip()[:120] or f'Q{idx + 1}'
            try:
                marks = round(float(item.get('marks')), 2)
            except (TypeError, ValueError):
                raise serializers.ValidationError(f'"{label}" needs a number of marks.')
            if marks <= 0:
                raise serializers.ValidationError(f'"{label}" must be worth more than 0 marks.')
            item_id = str(item.get('id') or '')
            try:
                uuid.UUID(item_id)
            except (ValueError, AttributeError):
                item_id = str(uuid.uuid4())
            scheme.append({'id': item_id, 'label': label, 'marks': marks})
        return scheme

    def validate(self, attrs):
        start = attrs.get('start_time') or (self.instance.start_time if self.instance else None)
        end = attrs.get('end_time') or (self.instance.end_time if self.instance else None)

        if start and end and end <= start:
            raise serializers.ValidationError({'end_time': 'End time must be strictly after start time.'})

        if not self.instance:
            if end and end <= timezone.now():
                raise serializers.ValidationError({'end_time': 'Exam end time cannot be in the past.'})

        late_until = attrs.get('late_submission_until') if 'late_submission_until' in attrs else (
            self.instance.late_submission_until if self.instance else None
        )
        if late_until and end and late_until <= end:
            raise serializers.ValidationError({'late_submission_until': 'Late work must be accepted until some time after the deadline.'})

        category = attrs.get('category') or (self.instance.category if self.instance else Exam.AssessmentCategory.EXAM)
        if category == Exam.AssessmentCategory.ASSIGNMENT:
            # Assignments have a deadline, not a stopwatch.
            attrs['duration_minutes'] = None

        total_marks = attrs.get('total_marks') or (self.instance.total_marks if self.instance else None)
        mcq_data = attrs.get('mcq_data') if 'mcq_data' in attrs else (self.instance.mcq_data if self.instance else None)

        if 'mcq_data' in attrs and attrs['mcq_data'] is not None:
            raw_mcq = attrs['mcq_data']
            if not isinstance(raw_mcq, list):
                raise serializers.ValidationError({'mcq_data': 'mcq_data must be a list of questions.'})

            # Left out on create, the model default applies — and that is "published".
            is_published = attrs.get('is_published') if 'is_published' in attrs else (self.instance.is_published if self.instance else True)
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
                if len(options) > 5:
                    raise serializers.ValidationError({'mcq_data': f'Question #{idx+1} can have at most 5 options.'})

                # A question may be a picture (a photographed problem) instead of, or as well as, text.
                image_url = str(q.get('image_url') or '').strip()
                if image_url and (
                    len(image_url) > 500
                    or not (image_url.startswith('/media/') or image_url.lower().startswith(('http://', 'https://')))
                ):
                    raise serializers.ValidationError({'mcq_data': f'Question #{idx+1} has a picture address that is not allowed.'})

                if is_published:
                    if not question_text and not image_url:
                        raise serializers.ValidationError({'mcq_data': f'Question #{idx+1} needs some text or a picture.'})
                    if any(not str(opt).strip() for opt in options):
                        raise serializers.ValidationError({
                            'mcq_data': f'Question #{idx+1} has an empty option. Fill it in or remove it before publishing.'
                        })

                raw_points = q.get('points') if q.get('points') not in (None, '') else q.get('marks', 1)
                try:
                    points = round(float(raw_points), 2)
                except (TypeError, ValueError):
                    raise serializers.ValidationError({'mcq_data': f'Question #{idx+1} needs a number of marks.'})
                if points <= 0:
                    raise serializers.ValidationError({'mcq_data': f'Question #{idx+1} must be worth more than 0 marks.'})

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

                # Stored shape is fixed here; unknown keys from the client are dropped.
                normalized_q = {
                    'id': q_id,
                    'question': question_text,
                    'image_url': image_url,
                    'options': [str(o).strip() for o in options],
                    'points': points,
                    'marks': points,
                    'explanation': str(q.get('explanation') or '').strip()[:5000],
                }
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

        scheme = attrs.get('written_scheme') if 'written_scheme' in attrs else (
            self.instance.written_scheme if self.instance else []
        )
        if scheme and total_marks is not None:
            mcq_points = 0.0
            for q in (mcq_data or []):
                try:
                    mcq_points += float(q.get('points') if q.get('points') is not None else q.get('marks', 1))
                except (ValueError, TypeError):
                    pass
            written_points = sum(float(item['marks']) for item in scheme)
            if round(mcq_points + written_points, 2) > float(total_marks):
                raise serializers.ValidationError({
                    'written_scheme': (
                        f'MCQ points ({mcq_points:g}) plus written marks ({written_points:g}) '
                        f'come to more than the total marks ({total_marks}).'
                    )
                })

        # ── When students get to see marks and answers ──
        Mode = Exam.ResultPublishMode
        if 'result_publish_mode' not in attrs and 'is_results_published' in attrs:
            # Older clients only send the switch: on meant "once the exam has closed", off meant "not yet".
            attrs['result_publish_mode'] = Mode.SCHEDULED if attrs['is_results_published'] else Mode.MANUAL
            attrs['publish_time'] = None
        elif attrs.get('result_publish_mode') == Mode.MANUAL and 'is_results_published' not in attrs:
            if not self.instance or self.instance.result_publish_mode != Mode.MANUAL:
                attrs['is_results_published'] = False

        mode = attrs.get('result_publish_mode') or (self.instance.result_publish_mode if self.instance else Mode.SCHEDULED)
        if mode != Mode.SCHEDULED:
            attrs['publish_time'] = None
        else:
            publish_time = attrs.get('publish_time') if 'publish_time' in attrs else (
                self.instance.publish_time if self.instance else None
            )
            if publish_time and start and publish_time <= start:
                raise serializers.ValidationError({'publish_time': 'Results cannot be published before the exam starts.'})

        request = self.context.get('request')
        from apps.students.models import Tuition

        # Pop both names unconditionally: `a or b` would leave batch_id behind when
        # tuition_id is set, and it is not a model field.
        tuition_id = attrs.pop('tuition_id', None)
        batch_id = attrs.pop('batch_id', None)
        tuition_id = tuition_id or batch_id
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
                from apps.students.services import manageable_students
                student = manageable_students(request.user).get(id=student_id)
            except User.DoesNotExist:
                raise serializers.ValidationError({'student_id': 'Selected student does not exist or belongs to another tutor.'})
            attrs['student'] = student
            attrs['tuition'] = None

        return attrs

    def update(self, instance, validated_data):
        """Save the edit, then re-mark MCQs so existing submissions match the new answer key."""
        regrade = any(key in validated_data for key in ('mcq_data', 'negative_marks_per_wrong', 'total_marks', 'exam_type'))
        exam = super().update(instance, validated_data)
        if regrade:
            for submission in exam.submissions.exclude(status=ExamSubmission.Status.MISSED):
                submission.exam = exam
                submission.calculate_mcq_score()
                submission.save(update_fields=['mcq_score', 'obtained_marks', 'is_graded', 'graded_at', 'updated_at'])
        return exam


class SubmitExamSerializer(serializers.Serializer):
    """Validates payload for student exam submission."""
    answers_data = serializers.DictField(required=False, default=dict, child=serializers.CharField(max_length=5000))
    text_answer = serializers.CharField(required=False, allow_blank=True, default='', max_length=20000)
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
    cq_breakdown = serializers.DictField(
        child=serializers.FloatField(min_value=0), required=False,
        help_text='Marks per written question id. When sent, cq_score becomes their sum.',
    )
    tutor_feedback = serializers.CharField(required=False, allow_blank=True, default='')

    def validate(self, attrs):
        submission = self.context.get('submission')
        total = submission.exam.total_marks if submission else None

        breakdown = attrs.get('cq_breakdown')
        if breakdown is not None and submission:
            scheme = {item['id']: item for item in (submission.exam.written_scheme or [])}
            if not scheme:
                raise serializers.ValidationError({'cq_breakdown': 'This exam has no written marking scheme.'})
            cleaned = {}
            for item_id, marks in breakdown.items():
                item = scheme.get(str(item_id))
                if not item:
                    raise serializers.ValidationError({'cq_breakdown': 'Unknown written question.'})
                if marks > float(item['marks']):
                    raise serializers.ValidationError({
                        'cq_breakdown': f'"{item["label"]}" is out of {item["marks"]:g}; {marks:g} is too many.'
                    })
                cleaned[str(item_id)] = round(marks, 2)
            attrs['cq_breakdown'] = cleaned
            attrs['cq_score'] = round(sum(cleaned.values()), 2)
            attrs.pop('obtained_marks', None)

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
