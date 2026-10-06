"""Authentication Admin Configuration"""
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from django.utils.translation import gettext_lazy as _
from .models import CustomUser


@admin.register(CustomUser)
class CustomUserAdmin(UserAdmin):
    list_display = [
        'username', 'get_full_name', 'email', 'role',
        'tutor', 'is_active', 'created_at'
    ]
    list_filter = ['role', 'is_active', 'is_staff', 'created_at']
    search_fields = ['username', 'first_name', 'last_name', 'email']
    ordering = ['-created_at']
    readonly_fields = ['id', 'created_at', 'updated_at']

    fieldsets = (
        (None, {'fields': ('id', 'username', 'password')}),
        (_('Personal Info'), {'fields': ('first_name', 'last_name', 'email', 'phone')}),
        (_('TuitionTrack Role'), {'fields': ('role', 'tutor')}),
        (_('Permissions'), {
            'fields': ('is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions'),
            'classes': ('collapse',),
        }),
        (_('Timestamps'), {'fields': ('created_at', 'updated_at', 'last_login', 'date_joined')}),
    )

    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': (
                'username', 'first_name', 'last_name', 'email',
                'phone', 'role', 'tutor', 'password1', 'password2'
            ),
        }),
    )
