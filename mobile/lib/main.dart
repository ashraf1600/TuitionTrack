import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'core/api.dart';
import 'core/app_keys.dart';
import 'core/background_check.dart';
import 'core/json.dart';
import 'core/live.dart';
import 'core/offline.dart';
import 'core/push.dart';
import 'core/reminders.dart';
import 'core/repo.dart';
import 'core/session.dart';
import 'screens/auth/force_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/common/notification_actions.dart';
import 'screens/student/student_home.dart';
import 'screens/tutor/tutor_home.dart';
import 'widgets/theme.dart';
import 'widgets/tt_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  final prefs = await SharedPreferences.getInstance();
  final session = Session(
    api: ApiClient(
      baseUrl: defaultServer,
      tokens: SecureTokenStore(),
      // What the server last sent is kept on the phone, so screens open offline
      // and instantly while a sleeping server wakes up.
      cache: ResponseCache(storage: canPersistCache ? FileCacheStorage() : null),
    ),
    settings: PrefsSettings(prefs),
  );
  // Month and day names for both languages.
  await initializeDateFormatting();
  // Phone notifications; a phone that refuses them still runs the app.
  try {
    await Reminders.instance.init();
  } catch (error) {
    debugPrint('Notifications unavailable: $error');
  }
  Reminders.instance.onResponse = (response) => handleNotificationResponse(session, response);
  // Push notifications, when this build has a Firebase project (see core/push.dart).
  await Push.init(onOpen: (payload) => openNotificationTarget(session, payload));
  runApp(TuitionTrackApp(session: session));
  await session.restore();
  // The notification that opened the app (e.g. "Mark done"), once someone is signed in.
  final launch = Reminders.instance.launchResponse;
  if (launch != null && session.signedIn) {
    Reminders.instance.launchResponse = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => handleNotificationResponse(session, launch));
  }
  final pushed = Push.launchMessage;
  if (pushed != null && session.signedIn) {
    Push.launchMessage = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => openNotificationTarget(session, Push.payloadOf(pushed)));
  }
  await _startBackgroundCheck();
}

const _updatesTask = 'tuitiontrack-updates';

/// Every 15 minutes or so (the shortest Android allows; it decides exactly, and waits for a network),
/// asks the server for new notifications even when the app is closed, and
/// shows the new ones on the phone. Needs no Firebase account.
Future<void> _startBackgroundCheck() async {
  if (!Reminders.instance.available) return;
  try {
    await Workmanager().initialize(backgroundDispatcher);
    await Workmanager().registerPeriodicTask(_updatesTask, _updatesTask, frequency: const Duration(minutes: 15));
  } catch (error) {
    debugPrint('Background check unavailable: $error');
  }
}

/// Runs in the background (its own isolate): new notifications -> phone notifications.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    await checkForUpdatesInBackground();
    return true;
  });
}

class TuitionTrackApp extends StatefulWidget {
  const TuitionTrackApp({super.key, required this.session});
  final Session session;

  @override
  State<TuitionTrackApp> createState() => _TuitionTrackAppState();
}

class _TuitionTrackAppState extends State<TuitionTrackApp> with WidgetsBindingObserver {
  final _navigator = rootNavigatorKey;
  String? _lastUser;
  StreamSubscription<Json>? _live;
  Timer? _refreshSoon;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    WidgetsBinding.instance.addObserver(this);
    _onSessionChanged();
    // The other side saved something (a class marked, a payment, homework): open screens reload.
    _live = LiveConnection.instance.events.listen((event) {
      if (event.str('type') != 'nudge') return;
      _refreshSoon?.cancel();
      _refreshSoon = Timer(const Duration(seconds: 1), () => widget.session.api.dataVersion.value++);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = widget.session;
    // The live connection is open only while the app is on screen; pushes cover the rest.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      LiveConnection.instance.stop();
      return;
    }
    // Back in the app: see whether the server can be reached and send anything made offline.
    if (state != AppLifecycleState.resumed) return;
    if (!session.signedIn) return;
    LiveConnection.instance.start(session.api);
    if (session.api.offline.value) {
      session.api.checkConnection();
    } else {
      // Send anything made offline, then let open screens fetch what changed meanwhile
      // (a class the tutor marked, a payment they recorded).
      session.syncPending().then((sent) {
        if (sent == 0) session.api.dataVersion.value++;
      });
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_live?.cancel());
    _refreshSoon?.cancel();
    super.dispose();
  }

  void _onSessionChanged() {
    // When the person changes (sign out, sign in as someone else) close whatever was open.
    final session = widget.session;
    final current = session.user?['id']?.toString();
    if (current != _lastUser) {
      _lastUser = current;
      _navigator.currentState?.popUntil((route) => route.isFirst);
      if (current == null) {
        LiveConnection.instance.stop();
      } else {
        LiveConnection.instance.start(session.api);
        // Signed in on this phone: its pushes now belong to this account.
        unawaited(Push.register(session));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Session>.value(value: widget.session),
        Provider<Repo>(create: (_) => Repo(widget.session.api, outbox: widget.session.outbox)),
      ],
      child: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) => MaterialApp(
          title: 'TuitionTrack',
          debugShowCheckedModeBanner: false,
          theme: ttTheme(isDark: false, isBangla: widget.session.language == 'bn'),
          darkTheme: ttTheme(isDark: true, isBangla: widget.session.language == 'bn'),
          themeMode: widget.session.themeMode,
          navigatorKey: _navigator,
          scaffoldMessengerKey: rootMessengerKey,
          // English or Bangla, chosen in the menu; date pickers and system texts follow it.
          locale: Locale(widget.session.language),
          supportedLocales: const [Locale('en'), Locale('bn')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // A new language rebuilds every screen under it (keys force fresh state).
          home: _Root(key: ValueKey('language-${widget.session.language}')),
        ),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (!session.ready) {
      return const TtSplash();
    }
    if (!session.signedIn) return const LoginScreen();
    if (session.mustChangePassword) return const ForcePasswordScreen();
    final key = ValueKey('${session.user?['id']}');
    return session.isTutor ? TutorHome(key: key) : StudentHome(key: key);
  }
}
