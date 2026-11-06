import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'json.dart';

/// The live connection to the server (/ws/, see backend/apps/messaging/consumers.py).
///
/// Open while the app is on screen and someone is signed in. It brings chat
/// messages, "seen" and "typing" the moment they happen, and a "nudge" when the
/// tutor or student saved something (so the bell refreshes). When the app is in
/// the background it is closed: push notifications take over (push.dart).
///
/// Events on [events]:
///   {"type": "message", "conversation_id", "message"}  a new chat message (also one this account sent from another phone)
///   {"type": "read", "conversation_id", "read_at"}     the other person opened the chat
///   {"type": "typing", "conversation_id"}              the other person is typing
///   {"type": "nudge"}                                   something changed: look for news
///   {"type": "connected"}                               (re)connected: catch up on anything missed
///
/// Screens keep a slow check of their own, so nothing is lost if the
/// connection cannot be made (a network that blocks WebSockets, a sleeping server).
class LiveConnection {
  LiveConnection._();
  static final instance = LiveConnection._();

  final _events = StreamController<Json>.broadcast();
  Stream<Json> get events => _events.stream;

  /// True while signed in on the live connection.
  final connected = ValueNotifier<bool>(false);

  ApiClient? _api;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _ping;
  Timer? _retry;
  int _attempt = 0;
  bool _wanted = false;
  bool _connecting = false;
  bool _forceRenew = false;
  final _typingSent = <String, DateTime>{};

  /// False in widget tests, which have no server to talk to.
  bool enabled = true;

  /// Opens the connection (and keeps it open) for [api]'s signed-in account.
  void start(ApiClient api) {
    if (!enabled) return;
    if (_api != api) _close();
    _api = api;
    _wanted = true;
    _attempt = 0;
    unawaited(_connect());
  }

  /// Closes it (app in the background, signed out).
  void stop() {
    _wanted = false;
    _retry?.cancel();
    _close();
  }

  /// Lets other sources (a push that arrived while the app is open) reach the same listeners.
  void emit(Json event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// Tells the other person in [conversationId] that this one is typing (at most every 3 seconds).
  void typing(String conversationId) {
    final last = _typingSent[conversationId];
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(seconds: 3)) return;
    _typingSent[conversationId] = now;
    _send({'type': 'typing', 'conversation_id': conversationId});
  }

  static Uri socketUri(String baseUrl) {
    final base = Uri.parse(baseUrl);
    return base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/ws/', query: null);
  }

  Future<void> _connect() async {
    final api = _api;
    if (!_wanted || _connecting || _channel != null || api == null || !api.hasSession) return;
    _connecting = true;
    try {
      final token = await api.freshAccessToken(force: _forceRenew);
      _forceRenew = false;
      if (token == null || !_wanted) {
        _scheduleRetry();
        return;
      }
      final channel = WebSocketChannel.connect(socketUri(api.baseUrl));
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 20));
      _sub = channel.stream.listen(_onData, onDone: _onClosed, onError: (_) => _onClosed(), cancelOnError: true);
      channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
    } catch (error) {
      debugPrint('Live connection failed: $error');
      _onClosed();
    } finally {
      _connecting = false;
    }
  }

  void _onData(dynamic raw) {
    Json? data;
    try {
      final decoded = jsonDecode(raw is String ? raw : utf8.decode(raw as List<int>));
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    if (data == null) return;
    switch (data.str('type')) {
      case 'ready':
        _attempt = 0;
        connected.value = true;
        _ping?.cancel();
        // Keeps phone networks and proxies from dropping a quiet connection.
        _ping = Timer.periodic(const Duration(seconds: 25), (_) => _send({'type': 'ping'}));
        emit({'type': 'connected'});
      case 'auth_failed':
        // The access token was refused (expired, signed out elsewhere): renew it next time.
        _forceRenew = true;
      case 'pong':
        break;
      default:
        emit(data);
    }
  }

  void _send(Json message) {
    if (!connected.value) return;
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (_) {
      // A broken connection is noticed by the stream and reopened.
    }
  }

  void _onClosed() {
    _close();
    if (_wanted) _scheduleRetry();
  }

  void _close() {
    _ping?.cancel();
    _ping = null;
    unawaited(_sub?.cancel());
    _sub = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(channel.sink.close().catchError((_) {}));
    connected.value = false;
  }

  void _scheduleRetry() {
    _retry?.cancel();
    // 1, 2, 4, 8, 16, then every 30 seconds, plus a little jitter so many phones don't knock together.
    final seconds = min(30, 1 << min(_attempt, 5));
    _attempt++;
    _retry = Timer(Duration(milliseconds: seconds * 1000 + _jitter.nextInt(800)), () => unawaited(_connect()));
  }

  static final _jitter = Random();
}
