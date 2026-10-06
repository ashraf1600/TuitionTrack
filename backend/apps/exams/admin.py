"""Exams Admin Configuration"""
from django.contrib import admin
from django.utils.html import format_html
from .models import Exam, ExamSubmission


class ExamSubmissionInline(admin.TabularInline):
    model = ExamSubmission
    extra = 0
    readonly_fields = [
        'id', 'student', 'submitted_at', 'status',
        'obtained_marks', 'is_graded', 'graded_at'
    ]
    fields = [
        'student', 'submitted_at', 'status',
        'obtained_marks', 'is_graded', 'tutor_feedback'
    ]


@admin.register(Exam)
class ExamAdmin(admin.ModelAdmin):
    list_display = [
        'title', 'get_student_name', 'get_tutor_name',
        'total_marks', 'start_time', 'end_time',
        'grace_period_minutes', 'is_published', 'created_at'
    ]
    list_filter = ['is_published', 'start_time', 'created_at']
    search_fields = ['title', 'student__first_name', 'student__last_name', 'tutor__username']
    readonly_fields = ['id', 'created_at', 'updated_at']
    ordering = ['-start_time']
    inlines = [ExamSubmissionInline]

    fieldsets = (
        ('Exam Identity', {'fields': ('id', 'tutor', 'student', 'title', 'is_published')}),
        ('Schedule (UTC)', {
            'fields': ('start_time', 'end_time', 'duration_minutes', 'grace_period_minutes'),
            'description': '⚠️ All times are in UTC. Ensure students know their local time.'
        }),
        ('Content', {
            'fields': ('content_html', 'total_marks'),
            'description': 'HTML is auto-sanitized via nh3 on save.'
        }),
        ('Timestamps', {'fields': ('created_at', 'updated_at'), 'classes': ('collapse',)}),
    )

    def get_student_name(self, obj):
        if obj.student:
            return obj.student.get_full_name() or obj.student.username
        if getattr(obj, 'tuition', None):
            return f'Tuition: {obj.tuition.title}'
        if getattr(obj, 'batch', None):
            return f'Batch: {obj.batch.name}'
        return 'All Enrolled Students'
    get_student_name.short_description = 'Student / Target'

    def get_tutor_name(self, obj):
        return obj.tutor.get_full_name() or obj.tutor.username
    get_tutor_name.short_description = 'Tutor'



@admin.register(ExamSubmission)
class ExamSubmissionAdmin(admin.ModelAdmin):
    list_display = [
        'get_exam_title', 'get_student_name', 'submitted_at',
        'status', 'obtained_marks', 'is_graded', 'graded_at'
    ]
    list_filter = ['status', 'is_graded', 'submitted_at']
    search_fields = [
        'exam__title', 'student__first_name', 'student__last_name',
        'student__username'
    ]
    readonly_fields = ['id', 'created_at', 'updated_at', 'submitted_at']
    ordering = ['-submitted_at']

    fieldsets = (
        ('Submission Identity', {'fields': ('id', 'exam', 'student', 'submitted_at', 'status')}),
        ('Answers', {'fields': ('answers_data', 'image_urls')}),
        ('Grading', {'fields': ('obtained_marks', 'tutor_feedback', 'is_graded', 'graded_at')}),
        ('Timestamps', {'fields': ('created_at', 'updated_at'), 'classes': ('collapse',)}),
    )

    def get_exam_title(self, obj):
        return obj.exam.title
    get_exam_title.short_description = 'Exam'

    def get_student_name(self, obj):
        return obj.student.get_full_name() or obj.student.username
    get_student_name.short_description = 'Student'
