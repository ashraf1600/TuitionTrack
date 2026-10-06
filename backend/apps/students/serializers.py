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

from .models import StudentProfile

User = get_user_model()


class StudentProfileSerializer(serializers.ModelSerializer):
    """Serializes the StudentProfile model fields."""

    class Meta:
        model = StudentProfile
        fields = [
            'id', 'grade_level', 'institution',
            'parent_name', 'parent_phone',
            'tuition_fee', 'cycle_length',
            'notes', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']


class StudentListSerializer(serializers.ModelSerializer):
    """
    Flat serializer for listing students with combined user + profile data.
    Used for GET /api/v1/students/ (list view).
    """
    student_id = serializers.UUIDField(source='id', read_only=True)
    full_name = serializers.SerializerMethodField()
    profile = StudentProfileSerializer(source='student_profile', read_only=True)

    class Meta:
        model = User
        fields = [
            'student_id', 'username', 'full_name',
            'email', 'phone', 'is_active',
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
    student_id = serializers.UUIDField(source='id', read_only=True)
    full_name = serializers.SerializerMethodField()
    profile = StudentProfileSerializer(source='student_profile')

    class Meta:
        model = User
        fields = [
            'student_id', 'username', 'first_name', 'last_name',
            'full_name', 'email', 'phone', 'is_active',
            'profile', 'created_at', 'updated_at',
        ]
        read_only_fields = ['student_id', 'username', 'full_name', 'created_at', 'updated_at']

    def get_full_name(self, obj):
        return obj.get_full_name() or obj.username

    def update(self, instance, validated_data):
        """Allow updating user fields and nested profile simultaneously."""
        profile_data = validated_data.pop('student_profile', {})

        # Update User fields
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()

        # Update StudentProfile fields
        if profile_data:
            profile = instance.student_profile
            for attr, value in profile_data.items():
                setattr(profile, attr, value)
            profile.save()

        return instance


class StudentCreateSerializer(serializers.Serializer):
    """
    Handles atomic creation of: User (STUDENT) + StudentProfile + Cycle #1.

    This is a flat serializer (not ModelSerializer) because it writes
    across two models (User + StudentProfile) in a single transaction.
    """
    # User fields
    username = serializers.CharField(max_length=150)
    password = serializers.CharField(write_only=True, min_length=6)
    first_name = serializers.CharField(max_length=150)
    last_name = serializers.CharField(max_length=150, required=False, default='')
    email = serializers.EmailField(required=False, allow_blank=True, default='')
    phone = serializers.CharField(max_length=20, required=False, allow_blank=True, default='')

    # StudentProfile fields
    grade_level = serializers.CharField(max_length=50, required=False, allow_blank=True, default='')
    institution = serializers.CharField(max_length=150, required=False, allow_blank=True, default='')
    parent_name = serializers.CharField(max_length=100, required=False, allow_blank=True, default='')
    parent_phone = serializers.CharField(max_length=20, required=False, allow_blank=True, default='')
    tuition_fee = serializers.DecimalField(max_digits=10, decimal_places=2, default=0.00)
    cycle_length = serializers.IntegerField(default=12, min_value=1)
    notes = serializers.CharField(required=False, allow_blank=True, default='')

    def validate_username(self, value):
        if User.objects.filter(username=value).exists():
            raise serializers.ValidationError('A user with this username already exists.')
        return value

    def validate_cycle_length(self, value):
        if value < 1:
            raise serializers.ValidationError('Cycle length must be at least 1 class.')
        return value

    @transaction.atomic
    def create(self, validated_data):
        """
        Atomically creates:
        1. User with role=STUDENT, tutor=request.user
        2. StudentProfile with financial/cycle config
        3. Cycle #1 with snapshotted fee and total_classes

        Uses select_for_update-style atomicity via @transaction.atomic.
        If any step fails, all are rolled back.
        """
        from apps.cycles.models import Cycle

        tutor = self.context['request'].user

        # ── Step 1: Create Student User ──────────────────────────────────────
        student_user = User.objects.create_user(
            username=validated_data['username'],
            password=validated_data['password'],
            first_name=validated_data['first_name'],
            last_name=validated_data.get('last_name', ''),
            email=validated_data.get('email', ''),
            phone=validated_data.get('phone', ''),
            role=User.Role.STUDENT,
            tutor=tutor,
        )

        # ── Step 2: Create StudentProfile ────────────────────────────────────
        profile = StudentProfile.objects.create(
            user=student_user,
            grade_level=validated_data.get('grade_level', ''),
            institution=validated_data.get('institution', ''),
            parent_name=validated_data.get('parent_name', ''),
            parent_phone=validated_data.get('parent_phone', ''),
            tuition_fee=validated_data.get('tuition_fee', 0),
            cycle_length=validated_data.get('cycle_length', 12),
            notes=validated_data.get('notes', ''),
        )

        # ── Step 3: Initialize Cycle #1 with snapshotted values ──────────────
        Cycle.objects.create(
            tutor=tutor,
            student=student_user,
            cycle_number=1,
            fee_snapshot=profile.tuition_fee,
            total_classes=profile.cycle_length,
            classes_data=Cycle.build_fresh_classes_data(profile.cycle_length),
            status=Cycle.Status.ACTIVE,
        )

        return student_user


class TuitionBatchStudentSerializer(serializers.ModelSerializer):
    student_id = serializers.UUIDField(source='id', read_only=True)
    full_name = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ['student_id', 'username', 'full_name', 'email', 'phone']

    def get_full_name(self, obj):
        return obj.get_full_name() or obj.username


class TuitionBatchSerializer(serializers.ModelSerializer):
    tutor_name = serializers.SerializerMethodField()
    students_detail = TuitionBatchStudentSerializer(source='students', many=True, read_only=True)
    student_count = serializers.SerializerMethodField()

    class Meta:
        from .models import TuitionBatch
        model = TuitionBatch
        fields = [
            'id', 'tutor', 'tutor_name', 'name', 'subject', 'description',
            'students', 'students_detail', 'student_count',
            'weekly_routine', 'monthly_fee', 'is_active', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'tutor', 'tutor_name', 'created_at', 'updated_at']

    def get_tutor_name(self, obj):
        return obj.tutor.get_full_name() or obj.tutor.username

    def get_student_count(self, obj):
        return obj.students.count()


class TuitionBatchCreateUpdateSerializer(serializers.ModelSerializer):
    student_ids = serializers.ListField(
        child=serializers.UUIDField(),
        required=False,
        default=list,
        write_only=True
    )

    class Meta:
        from .models import TuitionBatch
        model = TuitionBatch
        fields = [
            'id', 'name', 'subject', 'description', 'student_ids',
            'weekly_routine', 'monthly_fee', 'is_active'
        ]
        read_only_fields = ['id']

    def create(self, validated_data):
        from .models import TuitionBatch
        student_ids = validated_data.pop('student_ids', [])
        tutor = self.context['request'].user
        batch = TuitionBatch.objects.create(tutor=tutor, **validated_data)
        if student_ids:
            students = User.objects.filter(id__in=student_ids, role=User.Role.STUDENT)
            batch.students.set(students)
        return batch

    def update(self, instance, validated_data):
        student_ids = validated_data.pop('student_ids', None)
        for attr, val in validated_data.items():
            setattr(instance, attr, val)
        instance.save()
        if student_ids is not None:
            students = User.objects.filter(id__in=student_ids, role=User.Role.STUDENT)
            instance.students.set(students)
        return instance
