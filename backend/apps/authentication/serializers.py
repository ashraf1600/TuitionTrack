"""
Authentication Serializers
"""
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from django.contrib.auth import get_user_model

User = get_user_model()


def validate_new_username(value):
    """Usernames are unique whatever the capitalisation, because sign-in ignores case."""
    if User.objects.filter(username__iexact=value).exists():
        raise serializers.ValidationError('A user with this username already exists.')
    return value


def validate_unique_email(value, exclude_user=None):
    """An email address identifies one account (it is how a password reset finds it). Blank is allowed."""
    value = (value or '').strip()
    if not value:
        return ''
    taken = User.objects.filter(email__iexact=value)
    if exclude_user is not None:
        taken = taken.exclude(pk=exclude_user.pk)
    if taken.exists():
        raise serializers.ValidationError('An account with this email address already exists.')
    return value


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
        from .sessions import resolve_login_name
        # Accept the username in any capitalisation, or the account's email address.
        attrs[self.username_field] = resolve_login_name(attrs.get(self.username_field))
        data = super().validate(attrs)
        request = self.context.get('request')
        pic_url = None
        if self.user.profile_picture:
            pic_url = (
                request.build_absolute_uri(self.user.profile_picture.url)
                if request else self.user.profile_picture.url
            )
        # Append extra user data to the response body as well
        data['user'] = {
            'id': str(self.user.id),
            'username': self.user.username,
            'name': self.user.get_full_name() or self.user.username,
            'email': self.user.email,
            'role': self.user.role,
            'tutor_id': str(self.user.tutor_id) if self.user.tutor_id else None,
            'must_change_password': self.user.must_change_password,
            'tutor_code': self.user.tutor_code,
            'profile_picture_url': pic_url,
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

    def validate_username(self, value):
        return validate_new_username(value)

    def validate_email(self, value):
        return validate_unique_email(value)

    def validate(self, attrs):
        if attrs['password'] != attrs.pop('password_confirm'):
            raise serializers.ValidationError({'password_confirm': 'Passwords do not match.'})
        candidate = User(**{k: v for k, v in attrs.items() if k != 'password'})
        try:
            _validated_new_password(attrs['password'], candidate)
        except serializers.ValidationError as exc:
            raise serializers.ValidationError({'password': exc.detail})
        return attrs

    def create(self, validated_data):
        password = validated_data.pop('password')
        user = User(**validated_data, role=User.Role.TUTOR)
        user.set_password(password)
        user.save()
        return user


class TutorDirectorySerializer(serializers.ModelSerializer):
    """
    Public directory of verified tutors for prospective students during registration.
    Privacy invariant: Never exposes personal contact details (email, phone) or tuition fees.
    """
    name = serializers.SerializerMethodField()
    subjects = serializers.SerializerMethodField()
    tuitions = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ['id', 'username', 'name', 'subjects', 'tuitions']

    def get_name(self, obj):
        return obj.get_full_name() or obj.username

    def get_subjects(self, obj):
        if hasattr(obj, 'tuitions'):
            subjects = [t.subject for t in obj.tuitions.all() if t.subject]
            return list(dict.fromkeys(subjects))
        return []

    def get_tuitions(self, obj):
        if hasattr(obj, 'tuitions'):
            return [
                {
                    'id': str(t.id),
                    'title': t.title,
                    'subject': t.subject,
                    'cycle_length': t.cycle_length,
                }
                for t in obj.tuitions.all()
            ]
        return []



class StudentSelfRegistrationSerializer(serializers.Serializer):
    """
    Student self-registration. Picking a tutor here is optional (it can be done
    later from the student portal); when one is picked it only creates a
    PENDING ConnectionRequest — the tutor decides whether to accept.
    """
    username = serializers.CharField(max_length=150)
    password = serializers.CharField(write_only=True, min_length=8)
    password_confirm = serializers.CharField(write_only=True)
    first_name = serializers.CharField(max_length=150)
    last_name = serializers.CharField(max_length=150, required=False, default='')
    email = serializers.EmailField(required=False, allow_blank=True, default='')
    phone = serializers.CharField(max_length=20, required=False, allow_blank=True, default='')

    grade_level = serializers.CharField(max_length=50, required=False, allow_blank=True, default='')
    institution = serializers.CharField(max_length=150, required=False, allow_blank=True, default='')
    parent_name = serializers.CharField(max_length=100, required=False, allow_blank=True, default='')
    parent_phone = serializers.CharField(max_length=20, required=False, allow_blank=True, default='')
    address = serializers.CharField(max_length=255, required=False, allow_blank=True, default='')
    message = serializers.CharField(max_length=500, required=False, allow_blank=True, default='')

    # Selected Tutor during registration (from public directory)
    selected_tutor_id = serializers.CharField(required=False, allow_blank=True, default='')
    selected_tutor_username = serializers.CharField(required=False, allow_blank=True, default='')
    tutor_username = serializers.CharField(required=False, allow_blank=True, default='')

    def validate_username(self, value):
        return validate_new_username(value)

    def validate_email(self, value):
        return validate_unique_email(value)

    def validate_selected_tutor_id(self, value):
        if not value or not str(value).strip():
            return ''
        import uuid
        try:
            uuid.UUID(str(value).strip())
        except (ValueError, AttributeError):
            raise serializers.ValidationError('Invalid tutor ID format.')
        return str(value).strip()

    def validate(self, attrs):
        if attrs['password'] != attrs.pop('password_confirm'):
            raise serializers.ValidationError({'password_confirm': 'Passwords do not match.'})
        candidate = User(username=attrs['username'], first_name=attrs['first_name'], email=attrs.get('email', ''))
        try:
            _validated_new_password(attrs['password'], candidate)
        except serializers.ValidationError as exc:
            raise serializers.ValidationError({'password': exc.detail})
        return attrs

    def create(self, validated_data):
        from django.db import transaction
        with transaction.atomic():
            return self._create(validated_data)

    def _create(self, validated_data):
        from apps.students.models import StudentProfile, ConnectionRequest

        tutor_id = validated_data.pop('selected_tutor_id', '').strip()
        tutor_user = validated_data.pop('selected_tutor_username', '').strip()
        fallback_user = validated_data.pop('tutor_username', '').strip()

        target_tutor = None
        if tutor_id:
            import uuid
            try:
                tutor_uuid = uuid.UUID(tutor_id)
                target_tutor = User.objects.filter(id=tutor_uuid, role=User.Role.TUTOR).first()
            except (ValueError, TypeError):
                target_tutor = None
        if not target_tutor and tutor_user:
            target_tutor = User.objects.filter(username=tutor_user, role=User.Role.TUTOR).first()
        if not target_tutor and fallback_user:
            target_tutor = User.objects.filter(username=fallback_user, role=User.Role.TUTOR).first()

        password = validated_data.pop('password')
        grade_level = validated_data.pop('grade_level', '')
        institution = validated_data.pop('institution', '')
        parent_name = validated_data.pop('parent_name', '')
        parent_phone = validated_data.pop('parent_phone', '')
        address = validated_data.pop('address', '')
        message = validated_data.pop('message', '')

        user = User.objects.create_user(
            username=validated_data['username'],
            password=password,
            first_name=validated_data['first_name'],
            last_name=validated_data.get('last_name', ''),
            email=validated_data.get('email', ''),
            phone=validated_data.get('phone', ''),
            role=User.Role.STUDENT,
            # `tutor` stays empty until a tutor accepts the request below.
            selected_tutor=target_tutor,
        )

        profile = StudentProfile.objects.create(
            user=user,
            grade_level=grade_level,
            institution=institution,
            parent_name=parent_name,
            parent_phone=parent_phone,
            address=address,
            tuition_fee=0.00,
            cycle_length=12,
        )

        if target_tutor:
            ConnectionRequest.objects.create(student=user, tutor=target_tutor, message=message)

        return user


class UserProfileSerializer(serializers.ModelSerializer):
    """Read-only profile serializer for /auth/me/"""
    # Same display name the login response returns, so it survives a page reload.
    name = serializers.SerializerMethodField()

    def get_name(self, obj):
        return obj.get_full_name() or obj.username

    tutor_code = serializers.SerializerMethodField()
    profile_picture_url = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'username', 'name', 'email', 'first_name', 'last_name',
            'role', 'phone', 'tutor_id', 'must_change_password',
            'tutor_code', 'profile_picture_url',
            'profile', 'created_at'
        ]
        read_only_fields = fields

    profile = serializers.SerializerMethodField()

    def get_tutor_code(self, obj):
        """Only reveal the tutor_code to the tutor themselves."""
        return obj.tutor_code if obj.role == User.Role.TUTOR else None

    def get_profile_picture_url(self, obj):
        request = self.context.get('request')
        if obj.profile_picture:
            url = obj.profile_picture.url
            return request.build_absolute_uri(url) if request else url
        return None

    def get_profile(self, obj):
        """A student's own academic details (never fee fields)."""
        profile = getattr(obj, 'student_profile', None) if obj.role == User.Role.STUDENT else None
        if not profile:
            return None
        return {
            'grade_level': profile.grade_level,
            'institution': profile.institution,
            'address': profile.address,
            'parent_name': profile.parent_name,
            'parent_phone': profile.parent_phone,
        }


class ProfileUpdateSerializer(serializers.Serializer):
    """What a user may change about themselves. Username and role are fixed."""
    first_name = serializers.CharField(max_length=150, required=False)
    last_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    email = serializers.EmailField(required=False, allow_blank=True)
    phone = serializers.CharField(max_length=20, required=False, allow_blank=True)
    # Students only
    grade_level = serializers.CharField(max_length=50, required=False, allow_blank=True)
    institution = serializers.CharField(max_length=150, required=False, allow_blank=True)
    address = serializers.CharField(max_length=255, required=False, allow_blank=True)
    parent_name = serializers.CharField(max_length=100, required=False, allow_blank=True)
    parent_phone = serializers.CharField(max_length=20, required=False, allow_blank=True)

    USER_FIELDS = ('first_name', 'last_name', 'email', 'phone')
    PROFILE_FIELDS = ('grade_level', 'institution', 'address', 'parent_name', 'parent_phone')

    def validate_email(self, value):
        return validate_unique_email(value, exclude_user=self.instance)

    def update(self, instance, validated_data):
        from apps.students.models import StudentProfile
        changed = [f for f in self.USER_FIELDS if f in validated_data]
        for field in changed:
            setattr(instance, field, validated_data[field])
        if changed:
            instance.save(update_fields=changed + ['updated_at'])

        profile_changes = {f: validated_data[f] for f in self.PROFILE_FIELDS if f in validated_data}
        if profile_changes and instance.role == User.Role.STUDENT:
            # Edit the instance already attached to the user, so the response shows the new values.
            profile = getattr(instance, 'student_profile', None) or StudentProfile.objects.create(user=instance)
            for field, value in profile_changes.items():
                setattr(profile, field, value)
            profile.save(update_fields=list(profile_changes) + ['updated_at'])
        return instance


def _validated_new_password(value, user):
    from django.contrib.auth.password_validation import validate_password
    from django.core.exceptions import ValidationError as DjangoValidationError
    try:
        validate_password(value, user=user)
    except DjangoValidationError as exc:
        raise serializers.ValidationError(list(exc.messages))
    return value


class ChangePasswordSerializer(serializers.Serializer):
    current_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True, min_length=8)

    def validate_current_password(self, value):
        if not self.context['request'].user.check_password(value):
            raise serializers.ValidationError('Your current password is not correct.')
        return value

    def validate_new_password(self, value):
        return _validated_new_password(value, self.context['request'].user)

    def validate(self, attrs):
        if attrs['current_password'] == attrs['new_password']:
            raise serializers.ValidationError({'new_password': 'Choose a password different from the current one.'})
        return attrs


class PasswordResetRequestSerializer(serializers.Serializer):
    identifier = serializers.CharField(max_length=254, help_text='Username or email address.')


class PasswordResetConfirmSerializer(serializers.Serializer):
    uid = serializers.CharField()
    token = serializers.CharField()
    new_password = serializers.CharField(write_only=True, min_length=8)

    def validate(self, attrs):
        from django.contrib.auth.tokens import default_token_generator
        from django.utils.encoding import force_str
        from django.utils.http import urlsafe_base64_decode
        invalid = serializers.ValidationError('This reset link is invalid or has expired. Please request a new one.')
        try:
            user = User.objects.get(pk=force_str(urlsafe_base64_decode(attrs['uid'])), is_active=True)
        except Exception:
            raise invalid
        if not default_token_generator.check_token(user, attrs['token']):
            raise invalid
        try:
            _validated_new_password(attrs['new_password'], user)
        except serializers.ValidationError as exc:
            raise serializers.ValidationError({'new_password': exc.detail})
        attrs['user'] = user
        return attrs
