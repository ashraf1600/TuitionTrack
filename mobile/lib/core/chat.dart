import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'i18n.dart';
import 'json.dart';

/// The other person in a chat: a tutor ("Ashraf Sir" to students) or a student.
class ChatPerson {
  const ChatPerson({required this.id, required this.name, required this.role, this.photo, this.lastSeen, this.phone});
  final String id;
  final String name;
  final String role;
  final String? photo;

  /// When they last had the app open (for "Active 5 min ago").
  final DateTime? lastSeen;

  /// A student's (or guardian's) number, given to their tutor only.
  final String? phone;

  bool get isTutor => role == 'TUTOR';

  factory ChatPerson.fromJson(Json j) => ChatPerson(
        id: j.str('id'),
        name: j.str('name').isNotEmpty ? j.str('name') : j.str('username'),
        role: j.str('role'),
        photo: j.str('photo').isEmpty ? null : j.str('photo'),
        lastSeen: j.date('last_seen')?.toLocal(),
        phone: j.str('phone').isEmpty ? null : j.str('phone'),
      );
}

/// The message a reply answers, shown as a small quote above it.
class ChatQuote {
  const ChatQuote({required this.id, required this.body, required this.hasImage, required this.mine});
  final int id;
  final String body;
  final bool hasImage;
  final bool mine;

  factory ChatQuote.fromJson(Json j) => ChatQuote(id: j.integer('id'), body: j.str('body'), hasImage: j.flag('has_image'), mine: j.flag('mine'));
}

enum SendState { sent, sending, failed }

/// One message. Messages written on this phone and not on the server yet have
/// id 0, a [clientRef], and [state] sending or failed.
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.body,
    required this.mine,
    required this.createdAt,
    this.image,
    this.clientRef = '',
    this.state = SendState.sent,
    this.localImage,
    this.replyTo,
  });

  final int id;
  final String body;
  final bool mine;
  final DateTime createdAt;
  final String? image;
  final String clientRef;
  SendState state;

  /// A photo picked on this phone, shown while it uploads.
  final Uint8List? localImage;

  /// The message this one answers.
  final ChatQuote? replyTo;

  bool get hasImage => (image != null && image!.isNotEmpty) || localImage != null;

  factory ChatMessage.fromJson(Json j) => ChatMessage(
        id: j.integer('id'),
        body: j.str('body'),
        mine: j.flag('mine'),
        createdAt: (j.date('created_at') ?? DateTime.now()).toLocal(),
        image: j.str('image').isEmpty ? null : j.str('image'),
        clientRef: j.str('client_ref'),
        replyTo: j.obj('reply_to') == null ? null : ChatQuote.fromJson(j.obj('reply_to')!),
      );
}

/// A row in the chat list.
class ChatSummary {
  ChatSummary({
    required this.id,
    required this.other,
    required this.unread,
    required this.canSend,
    this.last,
    this.lastAt,
    this.otherReadAt,
  });

  final String id;
  final ChatPerson other;
  final ChatMessage? last;
  final DateTime? lastAt;
  final int unread;
  final bool canSend;

  /// Up to when the other person has read this chat (for ✓✓ on my last message).
  final DateTime? otherReadAt;

  bool get lastSeenByOther => last != null && last!.mine && otherReadAt != null && !last!.createdAt.isAfter(otherReadAt!);

  factory ChatSummary.fromJson(Json j) => ChatSummary(
        id: j.str('id'),
        other: ChatPerson.fromJson(j.obj('other') ?? const {}),
        last: j.obj('last_message') == null ? null : ChatMessage.fromJson(j.obj('last_message')!),
        lastAt: j.date('last_message_at')?.toLocal(),
        unread: j.integer('unread'),
        canSend: j['can_send'] != false,
        otherReadAt: j.date('other_read_at')?.toLocal(),
      );
}

/// A page of messages.
class ChatPage {
  ChatPage({required this.messages, required this.hasMore, required this.canSend, this.otherReadAt});
  final List<ChatMessage> messages;
  final bool hasMore;
  final bool canSend;
  final DateTime? otherReadAt;
}

/// Someone this user may message, with their chat if one exists.
class ChatContact {
  ChatContact({required this.person, this.conversationId});
  final ChatPerson person;
  final String? conversationId;
}

/// The chat endpoints (see backend/apps/messaging/views.py).
class ChatApi {
  ChatApi(this.api);
  final ApiClient api;

  static Json _map(dynamic data) => data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  static List<Json> _rows(Json data) => ((data['results'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  Future<({List<ChatSummary> chats, int unread})> chats() async {
    final data = _map(await api.get('/chats/'));
    return (chats: _rows(data).map(ChatSummary.fromJson).toList(), unread: data.integer('unread_total'));
  }

  Future<int> unread() async => _map(await api.getFresh('/chats/unread/')).integer('unread');

  Future<List<ChatContact>> contacts() async {
    final data = _map(await api.get('/chats/contacts/'));
    return [
      for (final row in _rows(data))
        ChatContact(person: ChatPerson.fromJson(row), conversationId: row.str('conversation_id').isEmpty ? null : row.str('conversation_id')),
    ];
  }

  /// The chat with [userId], made on the server if it is new.
  Future<ChatSummary> start(String userId) async => ChatSummary.fromJson(_map(await api.post('/chats/start/', {'user_id': userId})));

  Future<ChatSummary> conversation(String id) async => ChatSummary.fromJson(_map(await api.get('/chats/$id/')));

  /// The newest messages, older ones ([before]) or only new ones ([after]).
  Future<ChatPage> messages(String id, {int? after, int? before, int limit = 40}) async {
    final query = <String, dynamic>{'limit': limit, if (after != null) 'after': after, if (before != null) 'before': before};
    // The newest page is kept for reading offline; polls and older pages are not.
    final raw = after == null && before == null
        ? await api.get('/chats/$id/messages/', query: query)
        : await api.getFresh('/chats/$id/messages/', query: query);
    final data = _map(raw);
    return ChatPage(
      messages: _rows(data).map(ChatMessage.fromJson).toList(),
      hasMore: data.flag('has_more'),
      canSend: data['can_send'] != false,
      otherReadAt: data.date('other_read_at')?.toLocal(),
    );
  }

  Future<ChatMessage> send(String id, {required String body, required String clientRef, int? replyTo}) async =>
      ChatMessage.fromJson(_map(await api.post('/chats/$id/messages/', {'body': body, 'client_ref': clientRef, if (replyTo != null) 'reply_to': replyTo})));

  Future<ChatMessage> sendPhoto(String id, {required Uint8List bytes, required String filename, String body = '', required String clientRef, int? replyTo}) async =>
      ChatMessage.fromJson(_map(await api.postWithFile(
        '/chats/$id/messages/',
        field: 'image',
        bytes: bytes,
        filename: filename,
        fields: {'body': body, 'client_ref': clientRef, if (replyTo != null) 'reply_to': '$replyTo'},
      )));

  Future<void> markRead(String id) async => api.post('/chats/$id/read/');

  /// One message to every student of a tuition (each gets it in their own chat).
  /// Answers how many students it was sent to.
  Future<int> broadcast(String tuitionId, String body, {required String clientRef}) async =>
      _map(await api.post('/chats/broadcast/', {'tuition_id': tuitionId, 'body': body, 'client_ref': clientRef})).integer('students');
}

/// How many messages wait unread, shared by the chat buttons. Checked every
/// half minute while the app is open, and right away after reading a chat.
class ChatUnread extends ValueNotifier<int> {
  ChatUnread._() : super(0);
  static final instance = ChatUnread._();

  Future<void> refresh(ApiClient api) async {
    try {
      value = await ChatApi(api).unread();
    } on ApiException {
      // The badge is not worth an error; it checks again shortly.
    }
  }
}

/// A short random id for a message written on this phone.
String newClientRef() => 'm${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 30)}';

final _random = Random();

/// "Active now", "Active 5 min ago", "Active 3 h ago", "Active yesterday" — or null when unknown.
String? activeLabel(DateTime? lastSeen) {
  if (lastSeen == null) return null;
  final gap = DateTime.now().difference(lastSeen);
  if (gap.inMinutes < 2) return tr('Active now');
  if (gap.inMinutes < 60) return tr('Active {n} min ago', {'n': gap.inMinutes});
  if (gap.inHours < 24) return tr('Active {n} h ago', {'n': gap.inHours});
  if (gap.inDays == 1) return tr('Active yesterday');
  return tr('Active {n} days ago', {'n': gap.inDays});
}
