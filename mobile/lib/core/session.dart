import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'google_auth.dart';
import 'i18n.dart';
import 'json.dart';
import 'offline.dart';

/// Keeps tokens in the platform keystore; falls back to app preferences where that is unavailable.
class SecureTokenStore implements TokenStore {
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  @override
  Future<Map<String, String?>> read() async {
    try {
      return {'access': await _storage.read(key: _accessKey), 'refresh': await _storage.read(key: _refreshKey)};
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return {'access': prefs.getString(_accessKey), 'refresh': prefs.getString(_refreshKey)};
    }
  }

  @override
  Future<void> write({required String? access, required String? refresh}) async {
    try {
      await _put(_accessKey, access);
      await _put(_refreshKey, refresh);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      access == null ? await prefs.remove(_accessKey) : await prefs.setString(_accessKey, access);
      refresh == null ? await prefs.remove(_refreshKey) : await prefs.setString(_refreshKey, refresh);
    }
  }

  Future<void> _put(String key, String? value) =>
      value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value);
}

/// Small key-value settings (server address, what the user has already seen).
abstract class Settings {
  String? getString(String key);
  Future<void> setString(String key, String value);
  List<String> getList(String key);
  Future<void> setList(String key, List<String> value);

  /// Re-reads values another part of the app may have written meanwhile
  /// (the background check for notifications runs in its own isolate).
  Future<void> refresh();
}

class PrefsSettings implements Settings {
  PrefsSettings(this._prefs);
  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);
  @override
  Future<void> setString(String key, String value) => _prefs.setString(key, value);
  @override
  List<String> getList(String key) => _prefs.getStringList(key) ?? const [];
  @override
  Future<void> setList(String key, List<String> value) => _prefs.setStringList(key, value);
  @override
  Future<void> refresh() => _prefs.reload();
}

class MemorySettings implements Settings {
  final Map<String, Object> _data = {};
  @override
  String? getString(String key) => _data[key] as String?;
  @override
  Future<void> setString(String key, String value) async => _data[key] = value;
  @override
  List<String> getList(String key) => (_data[key] as List<String>?) ?? const [];
  @override
  Future<void> setList(String key, List<String> value) async => _data[key] = value;
  @override
  Future<void> refresh() async {}
}

/// Who is signed in, and the API client everything else uses.
class Session extends ChangeNotifier {
  Session({required this.api, required this.settings})
      : outbox = Outbox(readString: settings.getString, writeString: settings.setString) {
    api.onSessionExpired = _expired;
    api.overlay = outbox.applyTo;
    api.onBackOnline = _backOnline;
    // Before the first frame, so the app never flashes in the other language.
    setAppLanguage(settings.getString(_languageKey) ?? 'en');
  }

  static const _languageKey = 'language'; // 'en' | 'bn'

  /// The app language, 'en' or 'bn'.
  String get language => appLanguage;

  Future<void> setLanguage(String code) async {
    setAppLanguage(code);
    await settings.setString(_languageKey, appLanguage);
    notifyListeners();
  }

  /// Changes made while offline, waiting to be sent.
  final Outbox outbox;
  bool _syncing = false;

  static const serverKey = 'server_url';
  static const _themeKey = 'theme_mode'; // 'dark' | 'light'

  final ApiClient api;
  final Settings settings;

  Json? user;
  bool ready = false;
  ThemeMode themeMode = ThemeMode.dark;
  bool get isLight => themeMode == ThemeMode.light;

  /// Shown once on the sign-in screen after the session ended by itself.
  String? notice;

  bool get signedIn => user != null;
  bool get isTutor => user?['role'] == 'TUTOR';
  bool get isStudent => user?['role'] == 'STUDENT';
  bool get mustChangePassword => user?.flag('must_change_password') ?? false;
  String get displayName => user?.str('name').isNotEmpty == true ? user!.str('name') : (user?.str('username') ?? '');

  /// Loads the saved session when the app starts.
  Future<void> restore() async {
    final saved = settings.getString(serverKey);
    if (saved != null && saved.isNotEmpty) api.baseUrl = saved;
    if (settings.getString(_themeKey) == 'light') themeMode = ThemeMode.light;
    await api.cache?.load();
    await api.loadTokens();
    if (api.hasSession) {
      // Whose waiting changes to show, even before the server answers.
      outbox.useOwner(settings.getString('last_user_id') ?? '');
      try {
        user = Map<String, dynamic>.from(await api.get('/auth/me/') as Map);
        outbox.useOwner(user!.str('id'));
      } on ApiException catch (error) {
        // Offline at launch: stay signed in as whoever was last here, and let each
        // screen report the connection problem. Any other failure means the session is gone.
        final role = settings.getString('last_role') ?? '';
        user = (error.isOffline && role.isNotEmpty)
            ? {'role': role, 'username': settings.getString('last_username') ?? '', 'name': settings.getString('last_name') ?? ''}
            : null;
      }
    }
    ready = true;
    notifyListeners();
    if (user != null) unawaited(syncPending());
  }

  Future<void> setServer(String url) async {
    api.baseUrl = url;
    await settings.setString(serverKey, api.baseUrl);
    // Saved answers belong to the old server.
    await api.cache?.clear();
    notifyListeners();
  }

  /// Sends the changes made offline, oldest first. Stops at the first one the
  /// server cannot take right now (still offline, server error) and keeps it;
  /// one the server refuses for good is dropped and reported in [Outbox.failures].
  /// Returns how many were sent.
  Future<int> syncPending() async {
    if (_syncing || outbox.isEmpty || !api.hasSession) return 0;
    _syncing = true;
    var sent = 0;
    try {
      for (final change in outbox.items) {
        try {
          await api.send(change.method, change.path, change.body);
          await outbox.remove(change.id);
          sent++;
        } on ApiException catch (error) {
          if (error.isUnreachable || error.status == 401 || error.status == 429 || error.status >= 500) break;
          await outbox.remove(change.id, failure: tr('{change} could not be saved: {reason}', {'change': Raw(change.label), 'reason': Raw(error.message)}));
        }
      }
    } finally {
      _syncing = false;
    }
    if (sent > 0) api.dataVersion.value++;
    return sent;
  }

  Future<void> _backOnline() async {
    final sent = await syncPending();
    // Screens showed saved data while offline; let them load fresh data now.
    if (sent == 0) api.dataVersion.value++;
  }

  /// Switches the whole app between dark and light. Remembered on this device.
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await settings.setString(_themeKey, mode == ThemeMode.light ? 'light' : 'dark');
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final data = Map<String, dynamic>.from(
      await api.post('/auth/token/', {'username': username.trim(), 'password': password}) as Map,
    );
    await _startSession(data);
  }

  /// Signs in with a Google ID token. With no account for that Google email the
  /// server answers 404 `google_account_not_found` (an [ApiException] whose
  /// [ApiException.data] has the email); calling again with [role] ('TUTOR' or
  /// 'STUDENT') then creates the account. Returns true when an account was created.
  Future<bool> loginWithGoogle(String idToken, {String? role}) async {
    final data = Map<String, dynamic>.from(
      await api.post('/auth/google/', {'id_token': idToken, if (role != null) 'role': role}) as Map,
    );
    await _startSession(data);
    return data.flag('created');
  }

  Future<void> _startSession(Json data) async {
    // Whatever was saved on this phone belongs to whoever used it before.
    await api.cache?.clear();
    await api.setTokens(data.str('access'), data.str('refresh'));
    user = data.obj('user');
    await refreshUser();
    unawaited(syncPending());
  }

  Future<void> registerTutor(Json form) async {
    await api.post('/auth/register/', form);
    await login(form.str('username'), form.str('password'));
  }

  Future<void> registerStudent(Json form) async {
    await api.post('/auth/register/student/', form);
    await login(form.str('username'), form.str('password'));
  }

  /// Re-reads the profile (after editing it, or changing the password).
  Future<void> refreshUser() async {
    user = Map<String, dynamic>.from(await api.get('/auth/me/') as Map);
    outbox.useOwner(user!.str('id'));
    await settings.setString('last_user_id', user!.str('id'));
    await settings.setString('last_role', user!.str('role'));
    await settings.setString('last_username', user!.str('username'));
    await settings.setString('last_name', user!.str('name'));
    notice = null;
    notifyListeners();
  }

  /// False for an account made with Google that has not set a password yet.
  bool get hasPassword => user?['has_password'] != false;

  Future<void> changePassword(String current, String next) async {
    final data = Map<String, dynamic>.from(
      await api.post('/auth/change-password/', {'current_password': current, 'new_password': next}) as Map,
    );
    // Every other device is signed out; this one carries on with the session it is handed back.
    if (data.str('access').isNotEmpty) await api.setTokens(data.str('access'), data.str('refresh'));
    await refreshUser();
  }

  Future<void> logout() async {
    final refresh = (await api.tokens.read())['refresh'];
    if (refresh != null && refresh.isNotEmpty && !api.offline.value) {
      try {
        await api.post('/auth/logout/', {'refresh': refresh});
      } catch (_) {
        // offline: the token simply expires on its own
      }
    }
    await api.setTokens(null, null);
    // The next "Continue with Google" shows the account picker again.
    unawaited(GoogleAuth.signOut());
    // Signing out leaves nothing of this account on the phone.
    await outbox.clear();
    outbox.useOwner('');
    await api.cache?.clear();
    await settings.setString('last_user_id', '');
    user = null;
    notifyListeners();
  }

  void _expired() {
    if (user == null) return;
    user = null;
    notice = tr('You have been signed out. Please sign in again.');
    notifyListeners();
  }
}
