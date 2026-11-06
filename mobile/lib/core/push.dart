import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_check.dart';
import 'json.dart';
import 'live.dart';
import 'reminders.dart';
import 'session.dart';

// The Firebase project the app belongs to, given at build time:
//   flutter build apk --dart-define=FIREBASE_API_KEY=… --dart-define=FIREBASE_APP_ID=…
//                     --dart-define=FIREBASE_SENDER_ID=… --dart-define=FIREBASE_PROJECT_ID=…
// (Firebase console → Project settings → Your apps → the Android app). A build
// without them simply has no push: everything else works, and news is still
// checked every 15 minutes in the background.
const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _appId = String.fromEnvironment('FIREBASE_APP_ID');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

/// Push notifications (Firebase Cloud Messaging), so news reaches the phone
/// even when the app is not running. See backend/apps/messaging/push.py:
/// - "message": a chat message, shown by Android itself;
/// - "sync": a silent nudge; the app checks for news and shows what is new.
class Push {
  Push._();

  static const _tokenKey = 'push_token';

  /// The pushed notification that opened the app, handled once someone is signed in.
  static RemoteMessage? launchMessage;

  static bool get configured =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      _senderId.isNotEmpty &&
      _projectId.isNotEmpty;

  static bool get ready => configured && Firebase.apps.isNotEmpty;

  static Future<bool> ensureFirebase() async {
    if (!configured) return false;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(apiKey: _apiKey, appId: _appId, messagingSenderId: _senderId, projectId: _projectId),
      );
    }
    return true;
  }

  /// At launch: listens for pushes. A phone without Google Play services still runs the app.
  static Future<void> init({required void Function(Json payload) onOpen}) async {
    try {
      if (!await ensureFirebase()) return;
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      await Reminders.instance.createMessagesChannel();
      // With the app open, the live connection usually has it already; this covers the rest.
      FirebaseMessaging.onMessage.listen((message) {
        final data = message.data;
        if (data['kind'] == 'message') {
          LiveConnection.instance.emit({'type': 'message', 'conversation_id': data['conversation_id'] ?? ''});
        } else {
          LiveConnection.instance.emit({'type': 'nudge'});
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) => onOpen(_payloadOf(message)));
      launchMessage = await FirebaseMessaging.instance.getInitialMessage();
    } catch (error) {
      debugPrint('Push unavailable: $error');
    }
  }

  static Json payloadOf(RemoteMessage message) => _payloadOf(message);

  static Json _payloadOf(RemoteMessage message) => {'type': 'server', 'link': message.data['link'] ?? ''};

  /// After signing in (and at launch when already signed in): this phone gets this account's pushes.
  static Future<void> register(Session session) async {
    if (!ready || !session.signedIn) return;
    try {
      await Reminders.instance.askPermissionOnce(session.settings);
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token != null) await _send(session, token);
      _refreshes ??= messaging.onTokenRefresh.listen((token) => _send(session, token));
    } catch (error) {
      debugPrint('Push not registered: $error');
    }
  }

  static StreamSubscription<String>? _refreshes;

  static Future<void> _send(Session session, String token) async {
    if (!session.signedIn) return;
    await session.api.post('/push/devices/', {'token': token, 'platform': 'android'});
    await session.settings.setString(_tokenKey, token);
  }

  /// Before signing out: this phone stops getting this account's pushes.
  static Future<void> unregister(Session session) async {
    final token = session.settings.getString(_tokenKey) ?? '';
    if (token.isEmpty) return;
    try {
      await session.api.send('DELETE', '/push/devices/', {'token': token});
    } catch (_) {
      // Offline: the server forgets the phone when the next push to it fails.
    }
    await session.settings.setString(_tokenKey, '');
  }
}

/// A push that arrived while the app was in the background or closed (its own isolate).
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Push.ensureFirebase();
    final data = message.data;
    if (data['kind'] == 'message') {
      // Android already showed it; the next check for news must not show it again.
      final prefs = await SharedPreferences.getInstance();
      await Reminders.markShown(PrefsSettings(prefs), 'msg-${data['message_id'] ?? ''}');
    } else if (data['kind'] == 'sync') {
      await checkForUpdatesInBackground();
    }
  } catch (error) {
    debugPrint('Background push not handled: $error');
  }
}
