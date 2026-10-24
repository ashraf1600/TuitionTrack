"""
One-to-one chat between a tutor and one of their students.

A conversation is unique per (tutor, student). Messages have increasing
integer ids, so a phone that has message 120 asks for "after=120" to get only
what is new. Each side's "read up to" time gives unread counts and the
"Seen" mark on the sender's side.
"""
import uuid

from django.conf import settings
from django.db import models
from django.db.models import Q


class Conversation(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    tutor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='tutor_conversations',
        limit_choices_to={'role': 'TUTOR'},
    )
    student = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='student_conversations',
        limit_choices_to={'role': 'STUDENT'},
    )
    created_at = models.DateTimeField(auto_now_add=True)
    last_message_at = models.DateTimeField(null=True, blank=True, db_index=True)
    # Everything from the other side up to this moment has been seen.
    tutor_read_at = models.DateTimeField(null=True, blank=True)
    student_read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-last_message_at', '-created_at']
        constraints = [models.UniqueConstraint(fields=['tutor', 'student'], name='one_conversation_per_pair')]

    def __str__(self):
        return f'{self.tutor} ↔ {self.student}'

    def has_member(self, user):
        return user.id in (self.tutor_id, self.student_id)

    def other(self, user):
        return self.student if user.id == self.tutor_id else self.tutor

    @staticmethod
    def read_field(user):
        return 'tutor_read_at' if user.role == 'TUTOR' else 'student_read_at'

    def read_at_of(self, user):
        return getattr(self, self.read_field(user))

    def other_read_at(self, user):
        return self.student_read_at if user.id == self.tutor_id else self.tutor_read_at


class Message(models.Model):
    MAX_LENGTH = 4000

    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name='messages')
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='chat_messages')
    body = models.TextField(blank=True, default='')
    image = models.ImageField(upload_to='messages/', null=True, blank=True)
    # Set by the phone so a message sent twice on a bad connection is kept once.
    client_ref = models.CharField(max_length=64, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ['id']
        indexes = [models.Index(fields=['conversation', 'id'])]
        constraints = [
            models.UniqueConstraint(
                fields=['sender', 'client_ref'], condition=~Q(client_ref=''), name='one_message_per_client_ref',
            ),
        ]

    def __str__(self):
        return (self.body or '[photo]')[:40]
