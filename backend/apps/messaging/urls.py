from django.urls import path

from .views import BroadcastView, ChatListView, ContactsView, ConversationView, MessagesView, ReadView, StartChatView, UnreadView

urlpatterns = [
    path('chats/', ChatListView.as_view(), name='chat-list'),
    path('chats/unread/', UnreadView.as_view(), name='chat-unread'),
    path('chats/contacts/', ContactsView.as_view(), name='chat-contacts'),
    path('chats/start/', StartChatView.as_view(), name='chat-start'),
    path('chats/broadcast/', BroadcastView.as_view(), name='chat-broadcast'),
    path('chats/<uuid:pk>/', ConversationView.as_view(), name='chat-detail'),
    path('chats/<uuid:pk>/messages/', MessagesView.as_view(), name='chat-messages'),
    path('chats/<uuid:pk>/read/', ReadView.as_view(), name='chat-read'),
]
