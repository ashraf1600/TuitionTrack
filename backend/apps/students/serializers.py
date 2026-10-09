"""
Students App Serializers

Handles serialization for:
  1. StudentProfile (profile data only)
  2. Student creation (User + StudentProfile + Cycle #1 — atomic operation)
  3. Student list/detail (combined User + Profile view)
"""
from rest_framework import serializers
from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Q

from .models import StudentProfile

User = get_user_model()


class StudentProfileSerializer(serializers.ModelSerializer):
    """Serializes the StudentProfile model fields."""

    class Meta:
        model = StudentProfile
        fields = [
            'id', 'grade_level', 'institution',
            'parent_name', 'parent_phone', 'address',
            'tuition_fee', 'cycle_length',
            'notes', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']


class StudentListSerializer(serializers.ModelSerializer):
    """
    Flat serializer for listing students with combined user + profile data.
    Used for GET /api/v1/students/ (list view).
    """
    id = serializers.UUIDField(read_only=True)
    student_id = serializers.UUIDField(source='id', read_only=True)
    full_name = serializers.SerializerMethodField()
    profile = StudentProfileSerializer(source='student_profile', read_only=True)

    class Meta:
        model = User
        fields = [
            'id', 'student_id', 'username', 'full_name',
            'email', 'phone', 'is_active', 'must_change_password',
            'profile', 'created_at',
        ]
        read_only_fields = fields

    def get_full_name(self, obj):
        return obj.get_full_name() or obj.username


class StudentDetailSerializer(serializers.ModelSerializer):
    """
    Detailed serializer for viewing/updating a single student.
    Used for GET/PATCH /api/v1/students/<id>/
    """
    id = serializers.UUIDField(read_only=True)
    student_id = serializers.UUIDField(source='id', read_only=True)
    full_name = serializers.SerializerMethodField()
    profile = StudentProfileSerializer(source='student_profile')

    class Meta:
        model = User
        fields = [
            'id', 'student_id', 'username', 'first_name', 'last_name',
            'full_name', 'email', 'phone', 'is_active', 'must_change_password',
            'profile', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'student_id', 'username', 'full_name', 'must_change_password', 'created_at', 'updated_at']

    def get_full_name(self, obj):
        return obj.get_full_name() or obj.username

    def update(self, instance, validated_data):
        """Allow updating user fields and nested profile simultaneously."""
        from django.db import transaction
        profile_data = validated_data.pop('student_profile', {})
        # is_active must only change via toggle_active/destroy endpoints (audit trail).
        validated_data.pop('is_active', None)

        with transaction.atomic():
            # Update User fields
            for attr, value in validated_data.items():
                setattr(instance, attr, value)
            instance.save()

            # Update StudentProfile fields (tolerate missing profile)
            if profile_data:
                from .models import StudentProfile
                profile, _ = StudentProfile.objects.get_or_create(user=instance)
                for attr, value in profile_data.items():
                    setattr(profile, attr, value)
                profile.full_clean(exclude=['user'])
                profile.save()
                # The response is built from the user's cached profile; point it at the saved one.
                instance.student_profile = profile

        return instance


class StudentCreateSerializer(serializers.Serializer):
    """
    Handles atomic creation of: User (STUDENT) + StudentProfile + Cycle #1.

    This is a flat serializer (not ModelSerializer) because it writes
    across two models (User + StudentProfile) in a single transaction.
    """
    # User fields
    username = serializers.CharField(max_length=150)
    password = serializers.CharField(write_only=True, min_length=8)
    first_name = serializers.CharField(max_length=150)
    last_name = serializers.CharField(max_length=150, required=False, default='')
    email = serializers.EmailField(required=False, allow_blank=True, default='')
    phone = serializers.CharField(max_length=20, required=False, allow_blank=True, default='')

    # StudentProfile fields
    grade_level = serializers.CharField(max_length=50, required=False, allow_blank=True, default='')
    institution = serializers.CharField(max_length=150, required=False, allow_blank=True, default='')
    parent_name = serializers.CharField(max_length=100, required=False, allow_blank=True, default='')
    parent_phone = serializers.CharField(max_length=20, required=False, allow_blank=True, default='')
    address = serializers.CharField(max_length=255, required=False, allow_blank=True, default='')
    tuition_fee = serializers.DecimalField(max_digits=10, decimal_places=2, default=0.00, min_value=0)
    cycle_length = serializers.IntegerField(default=12, min_value=1, max_value=500)
    notes = serializers.CharField(required=False, allow_blank=True, default='')
    tuition_id = serializers.UUIDField(required=False, allow_null=True, default=None)

    def validate_username(self, value):
        request = self.context.get('request')
        tutor = request.user if request else None
        existing = User.objects.filter(username=value).first()
        if not existing and User.objects.filter(username__iexact=value).exists():
            # Sign-in ignores capitalisation, so "Rafi" and "rafi" cannot be two accounts.
            raise serializers.ValidationError('A user with this username already exists.')
        if existing:
            from .services import can_manage
            # Re-using a username updates that account (and its password), so it is
            # only allowed for a student already connected to this tutor.
            if existing.role != User.Role.STUDENT or not tutor or not can_manage(tutor, existing):
                raise serializers.ValidationError('A user with this username already exists.')
        return value

    def validate_cycle_length(self, value):
        if value < 1:
            raise serializers.ValidationError('Cycle length must be at least 1 class.')
        return value

    def validate(self, attrs):
        from apps.authentication.serializers import validate_unique_email
        # The email may already belong to the very account being re-used, never to another one.
        same_account = User.objects.filter(username=attrs.get('username')).first()
        try:
            attrs['email'] = validate_unique_email(attrs.get('email', ''), exclude_user=same_account)
        except serializers.ValidationError as exc:
            raise serializers.ValidationError({'email': exc.detail})
        return attrs

    @transaction.atomic
    def create(self, validated_data):
        """
        Atomically creates or claims:
        1. User with role=STUDENT, tutor=request.user
        2. StudentProfile with financial/cycle config
        3. Optional TuitionEnrollment & AttendanceCycle if tuition_id is provided

        Uses select_for_update-style atomicity via @transaction.atomic.
        If any step fails, all are rolled back.
        """
        tutor = self.context['request'].user
        tuition_id = validated_data.pop('tuition_id', None)
        username = validated_data['username']

        existing_user = User.objects.filter(username=username).first()
        if existing_user and existing_user.role == User.Role.STUDENT:
            # ── Step 1: Claim & Update Existing Student User ─────────────────
            student_user = existing_user
            if student_user.tutor_id is None:
                student_user.tutor = tutor
            student_user.first_name = validated_data.get('first_name', student_user.first_name)
            if validated_data.get('last_name'):
                student_user.last_name = validated_data['last_name']
            if validated_data.get('email'):
                student_user.email = validated_data['email']
            if validated_data.get('phone'):
                student_user.phone = validated_data['phone']
            if validated_data.get('password'):
                student_user.set_password(validated_data['password'])
                student_user.must_change_password = True
            student_user.is_active = True
            student_user.save()

            # ── Step 2: Update or Create StudentProfile ──────────────────────
            profile, _ = StudentProfile.objects.get_or_create(user=student_user)
            if validated_data.get('grade_level'):
                profile.grade_level = validated_data['grade_level']
            if validated_data.get('institution'):
                profile.institution = validated_data['institution']
            if validated_data.get('parent_name'):
                profile.parent_name = validated_data['parent_name']
            if validated_data.get('parent_phone'):
                profile.parent_phone = validated_data['parent_phone']
            if validated_data.get('address'):
                profile.address = validated_data['address']
            if 'tuition_fee' in validated_data:
                profile.tuition_fee = validated_data['tuition_fee']
            if 'cycle_length' in validated_data:
                profile.cycle_length = validated_data['cycle_length']
            if validated_data.get('notes'):
                profile.notes = validated_data['notes']
            profile.save()
        else:
            # ── Step 1: Create Student User ──────────────────────────────────
            student_user = User.objects.create_user(
                username=validated_data['username'],
                password=validated_data['password'],
                first_name=validated_data['first_name'],
                last_name=validated_data.get('last_name', ''),
                email=validated_data.get('email', ''),
                phone=validated_data.get('phone', ''),
                role=User.Role.STUDENT,
                tutor=tutor,
                # The tutor picked this password, so the student sets their own at first sign-in.
                must_change_password=True,
            )

            # ── Step 2: Create StudentProfile ────────────────────────────────
            profile = StudentProfile.objects.create(
                user=student_user,
                grade_level=validated_data.get('grade_level', ''),
                institution=validated_data.get('institution', ''),
                parent_name=validated_data.get('parent_name', ''),
                parent_phone=validated_data.get('parent_phone', ''),
                address=validated_data.get('address', ''),
                tuition_fee=validated_data.get('tuition_fee', 0),
                cycle_length=validated_data.get('cycle_length', 12),
                notes=validated_data.get('notes', ''),
            )

        # ── Step 4: Optional Tuition Enrollment ──────────────────────────────
        if tuition_id:
            from apps.students.models import Tuition
            from .services import enroll_student
            from rest_framework.exceptions import ValidationError as DRFValidationError
            tuition = Tuition.objects.filter(id=tuition_id, tutor=tutor).first()
            if not tuition:
                raise DRFValidationError({'tuition_id': 'Selected tuition does not exist or belongs to another tutor.'})
            enroll_student(tuition, student_user)

        return student_user


# ── Tuition Group Serializers ────────────────────────────────────────────

def _active_enrollments(tuition):
    return tuition.enrollments.filter(is_active=True, student__is_active=True)


class StudentTuitionSerializer(serializers.ModelSerializer):
    """
    A tuition group as an enrolled student sees it: what it is, when it meets,
    and the shared class progress. Allow-list only — no fee, wallet or
    classmates' details can appear here.
    """
    name = serializers.CharField(source='title', read_only=True)
    weekly_routine = serializers.JSONField(source='routine', read_only=True)
    tutor_name = serializers.SerializerMethodField()
    enrolled_count = serializers.SerializerMethodField()
    active_cycle = serializers.SerializerMethodField()

    class Meta:
        from .models import Tuition
        model = Tuition
        fields = [
            'id', 'tutor_name', 'title', 'name', 'subject', 'description',
            'cycle_length', 'routine', 'weekly_routine',
            'enrolled_count', 'active_cycle', 'created_at',
        ]
        read_only_fields = fields

    def get_tutor_name(self, obj):
        return obj.tutor.get_full_name() or obj.tutor.username

    def get_enrolled_count(self, obj):
        return _active_enrollments(obj).count()

    def get_active_cycle(self, obj):
        from apps.cycles.serializers import StudentCycleSerializer
        cycle = obj.active_cycle
        return StudentCycleSerializer(cycle, context=self.context).data if cycle else None


class TuitionSerializer(StudentTuitionSerializer):
    """
    Tutor view of a tuition group: roster, the shared cycle with earnings, and
    the wallet summary. Views must never hand this to a student.
    """
    # Old names for total_fee, kept so existing clients keep working.
    tuition_fee = serializers.DecimalField(source='total_fee', max_digits=10, decimal_places=2, read_only=True)
    monthly_fee = serializers.DecimalField(source='total_fee', max_digits=10, decimal_places=2, read_only=True)
    enrollments = serializers.SerializerMethodField()
    students_detail = serializers.SerializerMethodField()
    wallet_summary = serializers.SerializerMethodField()

    class Meta(StudentTuitionSerializer.Meta):
        fields = StudentTuitionSerializer.Meta.fields + [
            'tutor', 'total_fee', 'tuition_fee', 'monthly_fee',
            'enrollments', 'students_detail', 'wallet_summary', 'updated_at',
        ]
        read_only_fields = fields

    def get_active_cycle(self, obj):
        from apps.cycles.serializers import AttendanceCycleSerializer
        cycle = obj.active_cycle
        return AttendanceCycleSerializer(cycle, context=self.context).data if cycle else None

    def get_students_detail(self, obj):
        return self.get_enrollments(obj)

    def get_enrollments(self, obj):
        res = []
        for enr in _active_enrollments(obj).select_related('student', 'student__student_profile'):
            student = enr.student
            profile = getattr(student, 'student_profile', None)
            res.append({
                'id': str(student.id),
                'student_id': str(student.id),
                'enrollment_id': str(enr.id),
                'student_name': student.get_full_name() or student.username,
                'username': student.username,
                'email': student.email,
                'phone': student.phone or getattr(profile, 'parent_phone', ''),
                'grade_level': getattr(profile, 'grade_level', ''),
                'institution': getattr(profile, 'institution', ''),
                'address': getattr(profile, 'address', ''),
                'joined_at': enr.joined_at,
            })
        return res

    def get_wallet_summary(self, obj):
        """
        Tuition Wallet: earned = (total_fee / cycle_length) * completed_classes
        for the current cycle, plus what earlier (archived) cycles earned.
        """
        from decimal import Decimal
        cycle = obj.active_cycle
        lifetime = sum(
            (c.earned_revenue for c in obj.cycles.filter(status='ARCHIVED')),
            Decimal('0.00'),
        )
        earned = cycle.earned_revenue if cycle else Decimal('0.00')
        return {
            'total_students': _active_enrollments(obj).count(),
            'total_fee': float(obj.total_fee),
            'per_class_rate': float(cycle.per_class_rate) if cycle else 0.0,
            'completed_classes': cycle.completed_classes if cycle else 0,
            'total_classes': cycle.total_classes if cycle else obj.cycle_length,
            'earned_revenue': float(earned),
            'pending_balance': float(cycle.pending_balance) if cycle else float(obj.total_fee),
            'archived_earnings': float(lifetime),
            'lifetime_earnings': float(lifetime + earned),
        }


class TuitionCreateUpdateSerializer(serializers.ModelSerializer):
    """
    Create / edit a tuition group. `student_ids`, when sent, is the full roster:
    students not listed are removed from the group, new ones are enrolled.
    """
    student_ids = serializers.ListField(
        child=serializers.UUIDField(),
        required=False,
        write_only=True
    )
    cycle_length = serializers.IntegerField(min_value=1, max_value=500, required=False)
    total_fee = serializers.DecimalField(max_digits=10, decimal_places=2, min_value=0, required=False)
    # Old name for total_fee, accepted so existing clients keep working.
    tuition_fee = serializers.DecimalField(max_digits=10, decimal_places=2, min_value=0, required=False, write_only=True)

    class Meta:
        from .models import Tuition
        model = Tuition
        fields = [
            'id', 'title', 'subject', 'description', 'cycle_length',
            'total_fee', 'tuition_fee', 'routine', 'student_ids',
        ]
        read_only_fields = ['id']

    def _tutor(self):
        return self.instance.tutor if self.instance else self.context['request'].user

    def validate_student_ids(self, value):
        from .services import manageable_students
        allowed = set(manageable_students(self._tutor()).filter(id__in=value).values_list('id', flat=True))
        for s_id in value:
            if s_id not in allowed:
                raise serializers.ValidationError(f'Cannot enroll student {s_id}: not one of your students.')
        return value

    def validate(self, attrs):
        legacy_fee = attrs.pop('tuition_fee', None)
        if legacy_fee is not None:
            attrs.setdefault('total_fee', legacy_fee)

        # Completed classes are never dropped by shrinking the cycle.
        new_length = attrs.get('cycle_length')
        if self.instance and new_length:
            cycle = self.instance.active_cycle
            if cycle and new_length < cycle.highest_completed_class_no:
                raise serializers.ValidationError({
                    'cycle_length': (
                        f'Class #{cycle.highest_completed_class_no} is already completed in the current cycle, '
                        f'so the cycle cannot be shorter than {cycle.highest_completed_class_no} classes.'
                    )
                })
        return attrs

    def _students(self, student_ids):
        return User.objects.filter(id__in=student_ids, role=User.Role.STUDENT)

    @transaction.atomic
    def create(self, validated_data):
        from .models import Tuition
        from .services import enroll_student
        from apps.cycles.models import AttendanceCycle
        student_ids = validated_data.pop('student_ids', [])
        tutor = validated_data.pop('tutor', None) or self.context['request'].user
        tuition = Tuition.objects.create(tutor=tutor, **validated_data)

        # The group gets its shared Cycle #1 straight away, students or not.
        AttendanceCycle.start_for(tuition, cycle_number=1)
        for student in self._students(student_ids):
            enroll_student(tuition, student)
        return tuition

    @transaction.atomic
    def update(self, instance, validated_data):
        from .services import enroll_student, unenroll_student
        from apps.cycles.models import AttendanceCycle
        student_ids = validated_data.pop('student_ids', None)
        for attr, val in validated_data.items():
            setattr(instance, attr, val)
        instance.save()

        # The current cycle follows fee / length edits; archived cycles stay frozen.
        AttendanceCycle.ensure_active(instance).sync_with_tuition()

        if student_ids is not None:
            target_ids = set(student_ids)
            for enr in instance.enrollments.filter(is_active=True).select_related('student'):
                if enr.student_id not in target_ids:
                    unenroll_student(instance, enr.student)
            for student in self._students(target_ids):
                enroll_student(instance, student)
        return instance


# ── Connection Requests ──────────────────────────────────────────────────

class ConnectionRequestSerializer(serializers.ModelSerializer):
    """A student's request to study with a tutor, as either side sees it."""
    student_id = serializers.UUIDField(read_only=True)
    tutor_id = serializers.UUIDField(read_only=True)
    student_name = serializers.SerializerMethodField()
    student_username = serializers.CharField(source='student.username', read_only=True)
    tutor_name = serializers.SerializerMethodField()
    tutor_display_name = serializers.SerializerMethodField()
    tutor_username = serializers.CharField(source='tutor.username', read_only=True)
    student = serializers.SerializerMethodField()

    class Meta:
        from .models import ConnectionRequest
        model = ConnectionRequest
        fields = [
            'id', 'status', 'message', 'created_at', 'responded_at',
            'student_id', 'student_name', 'student_username', 'student',
            'tutor_id', 'tutor_name', 'tutor_display_name', 'tutor_username',
        ]
        read_only_fields = fields

    def get_student_name(self, obj):
        return obj.student.get_full_name() or obj.student.username

    def get_tutor_name(self, obj):
        return obj.tutor.get_full_name() or obj.tutor.username

    def get_tutor_display_name(self, obj):
        first = obj.tutor.first_name or obj.tutor.username
        return f"{first} Sir"

    def get_student(self, obj):
        """Contact details so the tutor can decide — never shown to other students."""
        request = self.context.get('request')
        if not request or getattr(request.user, 'role', '') != 'TUTOR':
            return None
        profile = getattr(obj.student, 'student_profile', None)
        return {
            'email': obj.student.email,
            'phone': obj.student.phone,
            'grade_level': getattr(profile, 'grade_level', ''),
            'institution': getattr(profile, 'institution', ''),
            'address': getattr(profile, 'address', ''),
            'parent_name': getattr(profile, 'parent_name', ''),
            'parent_phone': getattr(profile, 'parent_phone', ''),
        }


class ConnectionRequestCreateSerializer(serializers.Serializer):
    """Student picks a tutor by id or username."""
    tutor_id = serializers.UUIDField(required=False, allow_null=True)
    tutor_username = serializers.CharField(required=False, allow_blank=True, max_length=150)
    message = serializers.CharField(required=False, allow_blank=True, max_length=500, default='')

    def validate(self, attrs):
        tutors = User.objects.filter(role=User.Role.TUTOR, is_active=True)
        tutor = None
        if attrs.get('tutor_id'):
            tutor = tutors.filter(id=attrs['tutor_id']).first()
        elif attrs.get('tutor_username', '').strip():
            tutor = tutors.filter(username__iexact=attrs['tutor_username'].strip()).first()
        if not tutor:
            raise serializers.ValidationError({'tutor_id': 'Tutor not found.'})
        attrs['tutor'] = tutor
        return attrs


# -- Tutor Code Connection ------------------------------------------------

class TutorCodeConnectionSerializer(serializers.Serializer):
    tutor_code = serializers.CharField(max_length=8, min_length=4)
    message = serializers.CharField(required=False, allow_blank=True, max_length=500, default='')

    def validate_tutor_code(self, value):
        value = value.strip().upper()
        if not User.objects.filter(tutor_code=value, role=User.Role.TUTOR, is_active=True).exists():
            raise serializers.ValidationError('No active tutor found with that code.')
        return value

    def validate(self, attrs):
        code = attrs['tutor_code']
        attrs['tutor'] = User.objects.filter(tutor_code=code, role=User.Role.TUTOR, is_active=True).first()
        return attrs


class ConnectedTutorSerializer(serializers.Serializer):
    """
    Tutor card on the student dashboard.
    display_name => 'Ashraf Sir' (first_name + ' Sir').
    """
    id = serializers.SerializerMethodField()
    display_name = serializers.SerializerMethodField()
    username = serializers.SerializerMethodField()
    profile_picture_url = serializers.SerializerMethodField()
    tuitions = serializers.SerializerMethodField()
    subjects = serializers.SerializerMethodField()

    def get_id(self, obj):
        return str(obj.id)

    def get_display_name(self, obj):
        first = obj.first_name or obj.username
        return f"{first} Sir"

    def get_username(self, obj):
        return obj.username

    def get_profile_picture_url(self, obj):
        request = self.context.get("request")
        if obj.profile_picture:
            url = obj.profile_picture.url
            if request:
                return request.build_absolute_uri(url)
            return url
        return None

    def get_tuitions(self, obj):
        return [
            {
                "id": str(t.id),
                "title": t.title,
                "subject": t.subject,
                "routine": t.routine,
                "cycle_length": t.cycle_length,
            }
            for t in obj.tuitions.all()
        ]

    def get_subjects(self, obj):
        subjects = [t.subject for t in obj.tuitions.all() if t.subject]
        return list(dict.fromkeys(subjects))


class HomeworkSerializer(serializers.ModelSerializer):
    """Read serializer for students and tutors (homework list/detail)."""
    due_date = serializers.DateTimeField(format="%Y-%m-%dT%H:%M:%SZ")
    tutor_name = serializers.SerializerMethodField()
    tutor_display_name = serializers.SerializerMethodField()
    tutor_profile_picture = serializers.SerializerMethodField()
    student_name = serializers.SerializerMethodField()
    tuition_title = serializers.SerializerMethodField()
    is_submitted = serializers.SerializerMethodField()

    class Meta:
        from .models import Homework
        model = Homework
        fields = [
            "id", "title", "description", "due_date", "source_label",
            "tutor_name", "tutor_display_name", "tutor_profile_picture",
            "student_id", "student_name", "tuition_id", "tuition_title",
            "submitted_online_url", "submitted_at", "is_submitted",
            "is_evaluated", "evaluated_at", "tutor_feedback",
            "created_at", "updated_at",
        ]
        read_only_fields = fields

    def get_tutor_name(self, obj):
        return obj.tutor.get_full_name() or obj.tutor.username

    def get_tutor_display_name(self, obj):
        first = obj.tutor.first_name or obj.tutor.username
        return f"{first} Sir"

    def get_tutor_profile_picture(self, obj):
        request = self.context.get("request")
        if obj.tutor.profile_picture:
            url = obj.tutor.profile_picture.url
            return request.build_absolute_uri(url) if request else url
        return None

    def get_student_name(self, obj):
        if obj.student:
            return obj.student.get_full_name() or obj.student.username
        return None

    def get_tuition_title(self, obj):
        return obj.tuition.title if obj.tuition else None

    def get_is_submitted(self, obj):
        return bool(obj.submitted_online_url or getattr(obj, "submission_file", None) or obj.submitted_at)


class HomeworkCreateUpdateSerializer(serializers.ModelSerializer):
    """Tutor creates/edits homework. is_evaluated is NOT writable here."""

    class Meta:
        from .models import Homework
        model = Homework
        fields = [
            "id", "title", "description", "due_date", "source_label",
            "student", "tuition", "tutor_feedback",
        ]
        read_only_fields = ["id"]

    def validate(self, attrs):
        if not attrs.get("student") and not attrs.get("tuition"):
            raise serializers.ValidationError(
                "Provide either a student or a tuition group for this homework."
            )
        if attrs.get("student") and attrs.get("tuition"):
            raise serializers.ValidationError(
                "Assign homework to either a student OR a tuition group, not both."
            )
        return attrs


class HomeworkMarkDoneSerializer(serializers.Serializer):
    """POST /api/v1/homework/<id>/mark_done/ — tutor only."""
    feedback = serializers.CharField(required=False, allow_blank=True, default="")


class StudentHomeworkSubmitSerializer(serializers.Serializer):
    """Student optionally submits an online link and/or file. No is_evaluated here."""
    submitted_online_url = serializers.URLField(required=False, allow_blank=True, default="")
    submission_file = serializers.FileField(required=False, allow_null=True)


class TutorHomeworkEvaluateSerializer(serializers.Serializer):
    """Tutor-only: the ONLY path that writes is_evaluated."""
    is_evaluated = serializers.BooleanField()
    tutor_feedback = serializers.CharField(required=False, allow_blank=True, default="")


class ConnectedTutorListSerializer(serializers.Serializer):
    """Student tutor list: display_name='Ashraf Sir' + profile_picture. No tuition titles."""
    id = serializers.UUIDField(read_only=True)
    display_name = serializers.SerializerMethodField()
    username = serializers.CharField(read_only=True)
    profile_picture = serializers.SerializerMethodField()

    def get_display_name(self, obj):
        first = (obj.first_name or "").strip() or obj.username
        return f"{first} Sir"

    def get_profile_picture(self, obj):
        if not obj.profile_picture:
            return None
        url = obj.profile_picture.url
        request = self.context.get("request")
        return request.build_absolute_uri(url) if request else url


class WeeklyRoutineSerializer(serializers.ModelSerializer):
    class Meta:
        from .models import WeeklyRoutine
        model = WeeklyRoutine
        fields = ["id", "day_of_week", "start_time", "end_time", "subject", "student", "tuition"]
        read_only_fields = ["id"]

    def validate(self, attrs):
        if not attrs.get("student") and not attrs.get("tuition"):
            raise serializers.ValidationError("Provide a student or a tuition group.")
        if attrs.get("student") and attrs.get("tuition"):
            raise serializers.ValidationError("Provide either student OR tuition, not both.")
        return attrs


class ClassScheduleSerializer(serializers.ModelSerializer):
    scheduled_at = serializers.DateTimeField(format="%Y-%m-%dT%H:%M:%SZ")

    class Meta:
        from .models import ClassSchedule
        model = ClassSchedule
        fields = ["id", "scheduled_at", "topic", "is_cancelled", "student", "tuition"]
        read_only_fields = ["id"]
