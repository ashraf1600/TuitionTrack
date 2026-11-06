import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'i18n.dart';
import 'reminders.dart';
import 'repo.dart';
import 'session.dart';

/// The server the app talks to until the user sets another one on the sign-in screen.
/// Override at build time with --dart-define=API_BASE_URL=https://… . Release builds
/// default to the hosted API (https); development builds to the computer they run on
/// (10.0.2.2 is how an Android emulator reaches it).
const defaultServer = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: kReleaseMode ? 'https://tuitiontrack-api.onrender.com' : 'http://10.0.2.2:8000',
);

/// With the app closed (its own isolate): asks the server for notifications
/// and shows the new ones on the phone. Run every 15 minutes or so by
/// Workmanager, and at once when a "sync" push arrives (push.dart).
Future<void> checkForUpdatesInBackground() async {
  try {
    DartPluginRegistrant.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final settings = PrefsSettings(prefs);
    if (!Reminders.enabledIn(settings)) return;
    final saved = settings.getString(Session.serverKey);
    final api = ApiClient(baseUrl: saved == null || saved.isEmpty ? defaultServer : saved, tokens: SecureTokenStore());
    await api.loadTokens();
    if (!api.hasSession) return;
    setAppLanguage(settings.getString('language') ?? 'en');
    final items = await Repo(api).notifications();
    await Reminders.instance.init();
    await Reminders.instance.announce(settings, items);
  } catch (error) {
    // Offline, signed out, or the server is asleep: try again next time.
    debugPrint('Background check skipped: $error');
  }
}
