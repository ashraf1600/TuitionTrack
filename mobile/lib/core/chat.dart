import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'json.dart';

/// The other person in a chat: a tutor ("Ashraf Sir" to students) or a student.
class ChatPerson {
  const ChatPerson({required this.id, required this.name, required this.role, this.photo});
  final String id;
  final String name;
  final String role;
  final String? photo;

  bool get isTutor => role == 'TUTOR';

  factory ChatPerson.fromJson(Json j) => ChatPerson(
        id: j.str('id'),
        name: j.str('name').isNotEmpty ? j.str('name') : j.str('username'),
        role: j.str('role'),
        photo: j.str('photo').isEmpty ? null : j.str('photo'),
      );
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

  bool get hasImage => (image != null && image!.isNotEmpty) || localImage != null;

  factory ChatMessage.fromJson(Json j) => ChatMessage(
        id: j.integer('id'),
        body: j.str('body'),
        mine: j.flag('mine'),
        createdAt: (j.date('created_at') ?? DateTime.now()).toLocal(),
        image: j.str('image').isEmpty ? null : j.str('image'),
        clientRef: j.str('client_ref'),
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
  });

  final String id;
  final ChatPerson other;
  final ChatMessage? last;
  final DateTime? lastAt;
  final int unread;
  final bool canSend;

  factory ChatSummary.fromJson(Json j) => ChatSummary(
        id: j.str('id'),
        other: ChatPerson.fromJson(j.obj('other') ?? const {}),
        last: j.obj('last_message') == null ? null : ChatMessage.fromJson(j.obj('last_message')!),
        lastAt: j.date('last_message_at')?.toLocal(),
        unread: j.integer('unread'),
        canSend: j['can_send'] != false,
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

  Future<ChatMessage> send(String id, {required String body, required String clientRef}) async =>
      ChatMessage.fromJson(_map(await api.post('/chats/$id/messages/', {'body': body, 'client_ref': clientRef})));

  Future<ChatMessage> sendPhoto(String id, {required Uint8List bytes, required String filename, String body = '', required String clientRef}) async =>
      ChatMessage.fromJson(_map(await api.postWithFile(
        '/chats/$id/messages/',
        field: 'image',
        bytes: bytes,
        filename: filename,
        fields: {'body': body, 'client_ref': clientRef},
      )));

  Future<void> markRead(String id) async => api.post('/chats/$id/read/');
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
