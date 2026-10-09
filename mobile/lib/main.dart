import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api.dart';
import 'core/repo.dart';
import 'core/session.dart';
import 'screens/auth/force_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/student/student_home.dart';
import 'screens/tutor/tutor_home.dart';
import 'widgets/theme.dart';

/// The server the app talks to until the user sets another one on the sign-in screen.
/// 10.0.2.2 is how an Android emulator reaches the computer it runs on.
const defaultServer = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  final prefs = await SharedPreferences.getInstance();
  final session = Session(
    api: ApiClient(baseUrl: defaultServer, tokens: SecureTokenStore()),
    settings: PrefsSettings(prefs),
  );
  runApp(TuitionTrackApp(session: session));
  await session.restore();
}

class TuitionTrackApp extends StatefulWidget {
  const TuitionTrackApp({super.key, required this.session});
  final Session session;

  @override
  State<TuitionTrackApp> createState() => _TuitionTrackAppState();
}

class _TuitionTrackAppState extends State<TuitionTrackApp> {
  final _navigator = GlobalKey<NavigatorState>();
  String? _lastUser;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    // When the person changes (sign out, sign in as someone else) close whatever was open.
    final current = widget.session.user?['id']?.toString();
    if (current != _lastUser) {
      _lastUser = current;
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: widget.session),
        Provider<Repo>(create: (_) => Repo(widget.session.api)),
      ],
      child: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) => MaterialApp(
          title: 'TuitionTrack',
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          darkTheme: buildTheme(),
          themeMode: widget.session.themeMode,
          navigatorKey: _navigator,
          home: const _Root(),
        ),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (!session.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!session.signedIn) return const LoginScreen();
    if (session.mustChangePassword) return const ForcePasswordScreen();
    final key = ValueKey('${session.user?['id']}');
    return session.isTutor ? TutorHome(key: key) : StudentHome(key: key);
  }
}
