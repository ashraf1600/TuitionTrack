"""Students Admin Configuration"""
from django.contrib import admin
from .models import StudentProfile, Tuition, TuitionEnrollment, ConnectionRequest


@admin.register(StudentProfile)
class StudentProfileAdmin(admin.ModelAdmin):
    list_display = [
        'get_student_name', 'get_tutor_name', 'grade_level',
        'institution', 'tuition_fee', 'cycle_length', 'created_at'
    ]
    list_filter = ['grade_level', 'created_at']
    search_fields = [
        'user__username', 'user__first_name', 'user__last_name',
        'user__tutor__username', 'institution'
    ]
    readonly_fields = ['id', 'created_at', 'updated_at']
    ordering = ['user__first_name']

    fieldsets = (
        ('Student Identity', {'fields': ('id', 'user')}),
        ('Academic Info', {'fields': ('grade_level', 'institution')}),
        ('Parent / Guardian', {'fields': ('parent_name', 'parent_phone', 'address')}),
        ('Financial & Cycle Config', {
            'fields': ('tuition_fee', 'cycle_length'),
            'description': 'Changes here only affect NEW cycles. Active cycles use their own snapshots.'
        }),
        ('Notes', {'fields': ('notes',)}),
        ('Timestamps', {'fields': ('created_at', 'updated_at'), 'classes': ('collapse',)}),
    )

    def get_student_name(self, obj):
        return obj.user.get_full_name() or obj.user.username
    get_student_name.short_description = 'Student Name'

    def get_tutor_name(self, obj):
        tutor = obj.user.tutor
        return tutor.get_full_name() or tutor.username if tutor else '—'
    get_tutor_name.short_description = 'Tutor'


class TuitionEnrollmentInline(admin.TabularInline):
    model = TuitionEnrollment
    extra = 0
    raw_id_fields = ['student']


@admin.register(Tuition)
class TuitionAdmin(admin.ModelAdmin):
    list_display = ['title', 'tutor', 'subject', 'cycle_length', 'total_fee', 'enrolled_students_count', 'created_at']
    search_fields = ['title', 'subject', 'tutor__username']
    raw_id_fields = ['tutor']
    inlines = [TuitionEnrollmentInline]


@admin.register(ConnectionRequest)
class ConnectionRequestAdmin(admin.ModelAdmin):
    list_display = ['student', 'tutor', 'status', 'created_at', 'responded_at']
    list_filter = ['status']
    search_fields = ['student__username', 'tutor__username']
    raw_id_fields = ['student', 'tutor']
