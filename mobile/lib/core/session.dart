import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'json.dart';

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
}

/// Who is signed in, and the API client everything else uses.
class Session extends ChangeNotifier {
  Session({required this.api, required this.settings}) {
    api.onSessionExpired = _expired;
  }

  static const serverKey = 'server_url';

  final ApiClient api;
  final Settings settings;

  Json? user;
  bool ready = false;

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
    await api.loadTokens();
    if (api.hasSession) {
      try {
        user = Map<String, dynamic>.from(await api.get('/auth/me/') as Map);
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
  }

  Future<void> setServer(String url) async {
    api.baseUrl = url;
    await settings.setString(serverKey, api.baseUrl);
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final data = Map<String, dynamic>.from(
      await api.post('/auth/token/', {'username': username.trim(), 'password': password}) as Map,
    );
    await api.setTokens(data.str('access'), data.str('refresh'));
    user = data.obj('user');
    await refreshUser();
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
    await settings.setString('last_role', user!.str('role'));
    await settings.setString('last_username', user!.str('username'));
    await settings.setString('last_name', user!.str('name'));
    notice = null;
    notifyListeners();
  }

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
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await api.post('/auth/logout/', {'refresh': refresh});
      } catch (_) {
        // offline: the token simply expires on its own
      }
    }
    await api.setTokens(null, null);
    user = null;
    notifyListeners();
  }

  void _expired() {
    if (user == null) return;
    user = null;
    notice = 'You have been signed out. Please sign in again.';
    notifyListeners();
  }
}
