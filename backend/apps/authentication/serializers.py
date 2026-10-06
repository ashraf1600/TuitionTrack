"""
Authentication Serializers
"""
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from django.contrib.auth import get_user_model

User = get_user_model()


class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    """
    Extends the default JWT token payload with role, user ID, name, and
    tutor_id (for student tokens — so the frontend knows the tenant).
    """

    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        # Add custom claims
        token['role'] = user.role
        token['name'] = user.get_full_name() or user.username
        token['tutor_id'] = str(user.tutor_id) if user.tutor_id else None
        return token

    def validate(self, attrs):
        data = super().validate(attrs)
        # Append extra user data to the response body as well
        data['user'] = {
            'id': str(self.user.id),
            'username': self.user.username,
            'name': self.user.get_full_name() or self.user.username,
            'email': self.user.email,
            'role': self.user.role,
            'tutor_id': str(self.user.tutor_id) if self.user.tutor_id else None,
        }
        return data


class TutorRegistrationSerializer(serializers.ModelSerializer):
    """Handles new tutor self-registration."""
    password = serializers.CharField(write_only=True, min_length=8)
    password_confirm = serializers.CharField(write_only=True)

    class Meta:
        model = User
        fields = [
            'username', 'email', 'first_name', 'last_name',
            'phone', 'password', 'password_confirm'
        ]

    def validate(self, attrs):
        if attrs['password'] != attrs.pop('password_confirm'):
            raise serializers.ValidationError({'password_confirm': 'Passwords do not match.'})
        return attrs

    def create(self, validated_data):
        password = validated_data.pop('password')
        user = User(**validated_data, role=User.Role.TUTOR)
        user.set_password(password)
        user.save()
        return user


class StudentSelfRegistrationSerializer(serializers.Serializer):
    """Handles student self-registration with profile info and optional tutor linking."""
    username = serializers.CharField(max_length=150)
    password = serializers.CharField(write_only=True, min_length=6)
    password_confirm = serializers.CharField(write_only=True)
    first_name = serializers.CharField(max_length=150)
    last_name = serializers.CharField(max_length=150, required=False, default='')
    email = serializers.EmailField(required=False, allow_blank=True, default='')
    phone = serializers.CharField(max_length=20, required=False, allow_blank=True, default='')

    grade_level = serializers.CharField(max_length=50, required=False, allow_blank=True, default='')
    institution = serializers.CharField(max_length=150, required=False, allow_blank=True, default='')
    parent_name = serializers.CharField(max_length=100, required=False, allow_blank=True, default='')
    parent_phone = serializers.CharField(max_length=20, required=False, allow_blank=True, default='')
    tutor_username = serializers.CharField(required=False, allow_blank=True, default='')

    def validate_username(self, value):
        if User.objects.filter(username=value).exists():
            raise serializers.ValidationError('A user with this username already exists.')
        return value

    def validate(self, attrs):
        if attrs['password'] != attrs.pop('password_confirm'):
            raise serializers.ValidationError({'password_confirm': 'Passwords do not match.'})
        return attrs

    def create(self, validated_data):
        from apps.students.models import StudentProfile
        from apps.cycles.models import Cycle

        tutor_username = validated_data.pop('tutor_username', '').strip()
        tutor = None
        if tutor_username:
            tutor = User.objects.filter(username=tutor_username, role=User.Role.TUTOR).first()

        password = validated_data.pop('password')
        grade_level = validated_data.pop('grade_level', '')
        institution = validated_data.pop('institution', '')
        parent_name = validated_data.pop('parent_name', '')
        parent_phone = validated_data.pop('parent_phone', '')

        user = User.objects.create_user(
            username=validated_data['username'],
            password=password,
            first_name=validated_data['first_name'],
            last_name=validated_data.get('last_name', ''),
            email=validated_data.get('email', ''),
            phone=validated_data.get('phone', ''),
            role=User.Role.STUDENT,
            tutor=tutor,
        )

        profile = StudentProfile.objects.create(
            user=user,
            grade_level=grade_level,
            institution=institution,
            parent_name=parent_name,
            parent_phone=parent_phone,
            tuition_fee=0.00,
            cycle_length=12,
        )

        if tutor:
            Cycle.objects.create(
                tutor=tutor,
                student=user,
                cycle_number=1,
                fee_snapshot=profile.tuition_fee,
                total_classes=profile.cycle_length,
                classes_data=Cycle.build_fresh_classes_data(profile.cycle_length),
                status=Cycle.Status.ACTIVE,
            )

        return user


class UserProfileSerializer(serializers.ModelSerializer):
    """Read-only profile serializer for /auth/me/"""
    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'first_name', 'last_name',
            'role', 'phone', 'tutor_id', 'created_at'
        ]
        read_only_fields = fields
