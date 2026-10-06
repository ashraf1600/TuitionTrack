"""Cycles Admin Configuration"""
from django.contrib import admin
from .models import Cycle


@admin.register(Cycle)
class CycleAdmin(admin.ModelAdmin):
    list_display = [
        'get_student_name', 'get_tutor_name', 'cycle_number', 'status',
        'fee_snapshot', 'total_classes', 'get_completed', 'get_earned',
        'created_at'
    ]
    list_filter = ['status', 'created_at']
    search_fields = [
        'student__username', 'student__first_name', 'student__last_name',
        'tutor__username'
    ]
    readonly_fields = [
        'id', 'created_at', 'updated_at',
        'get_completed', 'get_earned', 'get_pending'
    ]
    ordering = ['-created_at']

    fieldsets = (
        ('Participants', {'fields': ('id', 'tutor', 'student', 'cycle_number')}),
        ('Financial Snapshots', {
            'fields': ('fee_snapshot', 'total_classes'),
            'description': '⚠️ These are immutable snapshots from StudentProfile at creation time.'
        }),
        ('Attendance', {'fields': ('classes_data',)}),
        ('Status', {'fields': ('status', 'notes')}),
        ('Computed Analytics (Read-Only)', {
            'fields': ('get_completed', 'get_earned', 'get_pending'),
            'classes': ('collapse',),
        }),
        ('Timestamps', {'fields': ('created_at', 'updated_at'), 'classes': ('collapse',)}),
    )

    def get_student_name(self, obj):
        return obj.student.get_full_name() or obj.student.username
    get_student_name.short_description = 'Student'

    def get_tutor_name(self, obj):
        return obj.tutor.get_full_name() or obj.tutor.username
    get_tutor_name.short_description = 'Tutor'

    def get_completed(self, obj):
        return f'{obj.completed_classes} / {obj.total_classes}'
    get_completed.short_description = 'Completed Classes'

    def get_earned(self, obj):
        return f'{obj.earned_amount}'
    get_earned.short_description = 'Earned (BDT)'

    def get_pending(self, obj):
        return f'{obj.pending_amount}'
    get_pending.short_description = 'Pending (BDT)'
