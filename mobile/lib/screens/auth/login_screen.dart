import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/google_auth.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/password_field.dart';
import '../../widgets/theme.dart';
import '../../widgets/tt_logo.dart';
import '../../widgets/ui.dart';
import 'forgot_password_screen.dart';

enum _Mode { signIn, tutor, student }

/// Sign in, or create a tutor or student account.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{};
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  String? _error;
  Json? _tutor; // the tutor a new student asks to join (optional)
  String _googleClientId = ''; // from the server; empty hides the Google button
  bool _googleSignup = false;

  @override
  void initState() {
    super.initState();
    _loadGoogleSetup();
  }

  Future<void> _loadGoogleSetup() async {
    if (!GoogleAuth.supported) return;
    try {
      final meta = await context.read<Repo>().meta();
      final auth = meta['auth'];
      if (!mounted || auth is! Map) return;
      setState(() {
        _googleClientId = (auth['google_client_id'] as String?) ?? '';
        _googleSignup = auth['google_signup'] == true;
      });
    } catch (_) {
      // Server asleep or offline: the button appears on the next visit.
    }
  }

  Future<void> _google() async {
    final session = context.read<Session>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idToken = await GoogleAuth.signIn(_googleClientId);
      if (idToken == null || !mounted) return;
      final role = switch (_mode) {
        _Mode.tutor => 'TUTOR',
        _Mode.student => 'STUDENT',
        _Mode.signIn => null,
      };
      try {
        await session.loginWithGoogle(idToken, role: role);
      } on ApiException catch (error) {
        if (error.code != 'google_account_not_found' || !mounted) rethrow;
        if (error.data['signup_allowed'] != true || !_googleSignup) rethrow;
        final chosen = await _chooseRole(error.data.str('email'));
        if (chosen == null || !mounted) return;
        await session.loginWithGoogle(idToken, role: chosen);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on GoogleAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "No account uses this Google email yet — tutor or student?" Null when cancelled.
  Future<String?> _chooseRole(String email) => showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('Create your account with Google'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                gap8,
                Text(
                  tr('No TuitionTrack account uses {p0} yet. Which kind of account is it?', {'p0': Raw(email)}),
                  style: TextStyle(color: context.tt.textSecondary),
                ),
                gap16,
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, 'TUTOR'),
                  icon: const Icon(Icons.co_present_outlined),
                  label: Text(tr("I'm a tutor")),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
                gap12,
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.pop(context, 'STUDENT'),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text(tr("I'm a student")),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
                gap12,
                Text(
                  tr('Already have an account with another email? Cancel, sign in with your username, then add this email in your account.'),
                  style: TextStyle(fontSize: 12, color: context.tt.textTertiary),
                ),
              ],
            ),
          ),
        ),
      );

  TextEditingController _ctl(String name) => _c.putIfAbsent(name, TextEditingController.new);

  @override
  void dispose() {
    for (final controller in _c.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _v(String name) => _ctl(name).text.trim();

  Future<void> _submit() async {
    if (!checkForm(context, _form)) return;
    final session = context.read<Session>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (_mode) {
        case _Mode.signIn:
          await session.login(_v('username'), _ctl('password').text);
        case _Mode.tutor:
          await session.registerTutor({
            'username': _v('username'),
            'first_name': _v('first_name'),
            'last_name': _v('last_name'),
            'email': _v('email'),
            'phone': _v('phone'),
            'password': _ctl('password').text,
            'password_confirm': _ctl('password_confirm').text,
          });
        case _Mode.student:
          await session.registerStudent({
            'username': _v('username'),
            'first_name': _v('first_name'),
            'last_name': _v('last_name'),
            'email': _v('email'),
            'phone': _v('phone'),
            'grade_level': _v('grade_level'),
            'institution': _v('institution'),
            'address': _v('address'),
            'parent_name': _v('parent_name'),
            'parent_phone': _v('parent_phone'),
            'password': _ctl('password').text,
            'password_confirm': _ctl('password_confirm').text,
            if (_tutor != null) 'selected_tutor_id': _tutor!.str('id'),
            if (_tutor != null) 'message': _v('message'),
          });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final username = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialIdentifier: _v('username'))),
    );
    if (username != null && username.isNotEmpty && mounted) {
      _ctl('username').text = username;
      _ctl('password').clear();
      setState(() => _error = null);
      showToast(context, tr('Password changed. Sign in with your new password.'));
    }
  }

  Future<void> _changeServer() async {
    final session = context.read<Session>();
    final controller = TextEditingController(text: session.api.baseUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Server address')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('The address of your TuitionTrack server, for example https://tuitiontrack.example.com or http://192.168.0.10:8000 on your own network.'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            gap12,
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(labelText: tr('Server address')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(tr('Save'))),
        ],
      ),
    );
    if (url == null || url.isEmpty || !mounted) return;
    await session.setServer(url);
    if (!mounted) return;
    final repo = context.read<Repo>();
    await attempt(context, () async => repo.meta(), success: tr('Connected to the server.'));
  }

  Future<void> _pickTutor() async {
    final picked = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _TutorPicker(),
    );
    if (picked != null && mounted) setState(() => _tutor = picked);
  }

  String? _required(String? value) => (value == null || value.trim().isEmpty) ? tr('Required') : null;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final registering = _mode != _Mode.signIn;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: TtLogo(size: 76, animate: true)),
                      gap16,
                      const TtWordmark(size: 32),
                      const SizedBox(height: 4),
                      Text(
                        switch (_mode) {
                          _Mode.signIn => tr('Sign in to continue'),
                          _Mode.tutor => tr('Create your tutor account'),
                          _Mode.student => tr('Create your student account'),
                        },
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: context.tt.textSecondary),
                      ),
                      const SizedBox(height: 32),
                      PillToggle<_Mode>(
                        options: [
                          (_Mode.signIn, tr('Sign in'), null),
                          (_Mode.tutor, tr('New tutor'), null),
                          (_Mode.student, tr('New student'), null),
                        ],
                        selected: _mode,
                        onChanged: (mode) => setState(() {
                          _mode = mode;
                          _error = null;
                        }),
                      ),
                      gap24,
                      if (session.notice != null) ...[Banner2(session.notice!, color: AppColors.warning), gap12],
                      if (_error != null) ...[Banner2(_error!, color: AppColors.danger, icon: Icons.error_outline), gap12],
                      if (registering) ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _ctl('first_name'),
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(labelText: tr('First name')),
                                validator: _required,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _ctl('last_name'),
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(labelText: tr('Last name')),
                              ),
                            ),
                          ],
                        ),
                        gap12,
                      ],
                      FieldLabel(registering ? tr('Choose a username') : tr('Username or email')),
                      TextFormField(
                        controller: _ctl('username'),
                        autocorrect: false,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded)),
                        validator: _required,
                      ),
                      gap16,
                      PasswordField(
                        controller: _ctl('password'),
                        label: tr('Password'),
                        labelAbove: true,
                        isNew: registering,
                        helper: registering ? tr('At least 8 characters. Avoid common words and your own name.') : null,
                        onSubmitted: registering ? null : (_) => _submit(),
                        validator: (value) {
                          if (value == null || value.isEmpty) return tr('Required');
                          if (registering && value.length < 8) return tr('Use at least 8 characters');
                          return null;
                        },
                      ),
                      if (registering) ...[
                        gap12,
                        PasswordField(
                          controller: _ctl('password_confirm'),
                          label: tr('Repeat the password'),
                          isNew: true,
                          validator: (value) => value != _ctl('password').text ? tr('The two passwords are different') : null,
                        ),
                        gap12,
                        TextFormField(
                          controller: _ctl('email'),
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: _mode == _Mode.tutor ? tr('Email') : tr('Email (optional)'),
                            helperText: tr('Used to reset your password if you forget it.'),
                          ),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) return null;
                            return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text) ? null : tr('Enter a valid email address');
                          },
                        ),
                        gap12,
                        TextFormField(
                          controller: _ctl('phone'),
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(labelText: tr('Phone (optional)')),
                        ),
                      ],
                      if (_mode == _Mode.student) ...[
                        gap12,
                        Row(
                          children: [
                            Expanded(child: TextFormField(controller: _ctl('grade_level'), decoration: InputDecoration(labelText: tr('Class / grade')))),
                            const SizedBox(width: 12),
                            Expanded(child: TextFormField(controller: _ctl('institution'), decoration: InputDecoration(labelText: tr('School / college')))),
                          ],
                        ),
                        gap12,
                        TextFormField(controller: _ctl('address'), decoration: InputDecoration(labelText: tr('Address (optional)'))),
                        gap12,
                        Row(
                          children: [
                            Expanded(child: TextFormField(controller: _ctl('parent_name'), decoration: InputDecoration(labelText: tr('Guardian name')))),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _ctl('parent_phone'),
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(labelText: tr('Guardian phone')),
                              ),
                            ),
                          ],
                        ),
                        gap12,
                        AppCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('Your tutor (optional)'), style: TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                tr('Pick your tutor now to send them a request, or do it later from the app.'),
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                              ),
                              gap8,
                              if (_tutor == null)
                                OutlinedButton.icon(onPressed: _pickTutor, icon: const Icon(Icons.search), label: Text(tr('Find my tutor')))
                              else ...[
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const CircleAvatar(child: Icon(Icons.person)),
                                  title: Text(_tutor!.str('name')),
                                  subtitle: Text('@${_tutor!.str('username')}'),
                                  trailing: IconButton(
                                    tooltip: tr('Remove'),
                                    icon: const Icon(Icons.close),
                                    onPressed: () => setState(() => _tutor = null),
                                  ),
                                ),
                                TextFormField(
                                  controller: _ctl('message'),
                                  maxLength: 500,
                                  maxLines: 2,
                                  decoration: InputDecoration(labelText: tr('Message to the tutor (optional)')),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      gap24,
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: context.tt.onPrimary))
                            : Text(registering ? tr('Create account') : tr('Sign in')),
                      ),
                      if (!registering) ...[
                        gap8,
                        TextButton(onPressed: _forgotPassword, child: Text(tr('Forgot your password?'))),
                      ],
                      if (_googleClientId.isNotEmpty && (!registering || _googleSignup)) ...[
                        gap16,
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(tr('or'), style: TextStyle(color: context.tt.textTertiary)),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        gap16,
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          onPressed: _busy ? null : _google,
                          icon: const _GoogleMark(),
                          label: Text(registering ? tr('Sign up with Google') : tr('Continue with Google')),
                        ),
                      ],
                      const SizedBox(height: 32),
                      // The server, as a quiet footer (tap to change it).
                      TextButton.icon(
                        onPressed: _changeServer,
                        icon: const Icon(Icons.dns_outlined, size: 16),
                        label: Text(tr('Server: {p0}', {'p0': Raw(session.api.baseUrl.replaceFirst(RegExp(r'^https?://'), ''))}),
                            overflow: TextOverflow.ellipsis),
                        style: TextButton.styleFrom(
                          foregroundColor: context.tt.textTertiary,
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Search the public tutor directory.
class _TutorPicker extends StatefulWidget {
  const _TutorPicker();

  @override
  State<_TutorPicker> createState() => _TutorPickerState();
}

class _TutorPickerState extends State<_TutorPicker> {
  List<Json>? _tutors;
  String? _error;
  String _search = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final search = _search;
    try {
      final tutors = await context.read<Repo>().tutors(search);
      if (mounted && search == _search) setState(() => _tutors = tutors);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Find your tutor'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            gap12,
            TextField(
              autofocus: true,
              decoration: InputDecoration(labelText: tr('Search by name, username or subject'), prefixIcon: Icon(Icons.search)),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () {
                  if (!mounted) return;
                  _search = value.trim();
                  _load();
                });
              },
            ),
            gap12,
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
                  : _tutors == null
                      ? const Center(child: CircularProgressIndicator())
                      : _tutors!.isEmpty
                          ? Center(child: Text(tr('No tutors match that search.'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
                          : ListView.separated(
                              itemCount: _tutors!.length,
                              separatorBuilder: (_, _) => const Divider(),
                              itemBuilder: (context, index) {
                                final tutor = _tutors![index];
                                final subjects = tutor.strings('subjects');
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const CircleAvatar(child: Icon(Icons.person)),
                                  title: Text(tutor.str('name')),
                                  subtitle: Text(['@${tutor.str('username')}', if (subjects.isNotEmpty) subjects.join(', ')].join(' · ')),
                                  onTap: () => Navigator.pop(context, tutor),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Google's "G", drawn so no image asset is needed.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 20, height: 20, child: CustomPaint(painter: _GoogleMarkPainter()));
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    // Clockwise from 3 o'clock; the gap at the upper right makes the "G".
    const deg = 3.1415926535 / 180;
    canvas.drawArc(rect, 0, 45 * deg, false, arc(const Color(0xFF4285F4))); // blue
    canvas.drawArc(rect, 45 * deg, 90 * deg, false, arc(const Color(0xFF34A853))); // green
    canvas.drawArc(rect, 135 * deg, 90 * deg, false, arc(const Color(0xFFFBBC05))); // yellow
    canvas.drawArc(rect, 225 * deg, 90 * deg, false, arc(const Color(0xFFEA4335))); // red
    final mid = size.height / 2;
    canvas.drawLine(Offset(size.width / 2, mid), Offset(size.width - stroke / 2, mid), arc(const Color(0xFF4285F4)));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
