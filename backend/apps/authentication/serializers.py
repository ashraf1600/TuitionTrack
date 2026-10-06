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


class UserProfileSerializer(serializers.ModelSerializer):
    """Read-only profile serializer for /auth/me/"""
    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'first_name', 'last_name',
            'role', 'phone', 'tutor_id', 'created_at'
        ]
        read_only_fields = fields
