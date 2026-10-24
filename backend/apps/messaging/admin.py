from django.contrib import admin

from .models import Conversation, Message


@admin.register(Conversation)
class ConversationAdmin(admin.ModelAdmin):
    list_display = ('tutor', 'student', 'last_message_at')
    raw_id_fields = ('tutor', 'student')


@admin.register(Message)
class MessageAdmin(admin.ModelAdmin):
    list_display = ('conversation', 'sender', 'created_at')
    raw_id_fields = ('conversation', 'sender')
