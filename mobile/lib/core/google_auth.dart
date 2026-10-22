import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'i18n.dart';

/// Sign in with Google on Android (and iOS), via the google_sign_in plugin.
///
/// The server's `/meta/` answer carries `auth.google_client_id`: the OAuth
/// client of type "Web application". It is passed here as `serverClientId`, so
/// the ID token Google hands back is addressed to that client and the server
/// can check it. Android also needs an OAuth client of type "Android" in the
/// same Google Cloud project, registered with this app's package name
/// (app.tuitiontrack.tuitiontrack) and the SHA-1 of the key that signs the APK
/// — see RENDER_DEPLOYMENT_GUIDE.md → "Sign in with Google".
class GoogleAuth {
  GoogleAuth._();

  static String? _initializedFor;
  static Future<void>? _initializing;

  /// Whether this platform can show the Google button at all.
  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> _init(String serverClientId) async {
    if (_initializedFor == serverClientId) return;
    if (_initializedFor != null) {
      // The plugin can be set up only once per app run.
      throw GoogleAuthException(tr('The server changed its Google settings. Close and reopen the app, then try again.'));
    }
    _initializing ??= GoogleSignIn.instance.initialize(serverClientId: serverClientId);
    try {
      await _initializing;
      _initializedFor = serverClientId;
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  /// Shows Google's account picker and returns an ID token for the server,
  /// or null when the person closed the picker.
  static Future<String?> signIn(String serverClientId) async {
    if (!supported) throw GoogleAuthException(tr('Google sign-in is not available on this device.'));
    try {
      await _init(serverClientId);
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw GoogleAuthException(tr('Google sign-in is not available on this device.'));
      }
      final account = await GoogleSignIn.instance.authenticate(scopeHint: const ['email']);
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw GoogleAuthException(tr('Google did not return a sign-in token. Please try again.'));
      }
      return token;
    } on GoogleSignInException catch (error) {
      final code = error.code;
      if (code == GoogleSignInExceptionCode.canceled || code == GoogleSignInExceptionCode.interrupted) {
        // Usually the person closed the picker. Right after picking an account it
        // means this APK's signing key is not registered with Google (see the guide).
        return null;
      }
      if (code == GoogleSignInExceptionCode.clientConfigurationError ||
          code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw GoogleAuthException(
          tr('Google sign-in is not set up correctly for this app version. Sign in with your username and password.'),
        );
      }
      if (code == GoogleSignInExceptionCode.uiUnavailable) {
        throw GoogleAuthException(tr('Google sign-in could not open. Please try again.'));
      }
      debugPrint('Google sign-in failed: $code ${error.description}');
      throw GoogleAuthException(tr('Google sign-in failed. Please try again.'));
    }
  }

  /// Forgets the Google account chosen on this phone, so the picker shows next time.
  static Future<void> signOut() async {
    if (_initializedFor == null) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Not signed in with Google, or the plugin is unavailable: nothing to forget.
    }
  }
}

class GoogleAuthException implements Exception {
  GoogleAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
