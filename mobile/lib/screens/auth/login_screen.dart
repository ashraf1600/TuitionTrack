import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/password_field.dart';
import '../../widgets/theme.dart';
import '../../widgets/tt_logo.dart';
import '../../widgets/ui.dart';

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
    final repo = context.read<Repo>();
    final controller = TextEditingController(text: _v('username'));
    final identifier = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Reset your password')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Enter your username or email. If the account has an email address, a reset link is sent to it. Students without an email can ask their tutor for a new temporary password.'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            gap12,
            TextField(controller: controller, autofocus: true, decoration: InputDecoration(labelText: tr('Username or email'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(tr('Send link'))),
        ],
      ),
    );
    if (identifier == null || identifier.isEmpty || !mounted) return;
    await attempt(context, () async {
      final message = await repo.requestPasswordReset(identifier);
      if (mounted) showToast(context, message.isEmpty ? tr('If that account has an email, a reset link has been sent.') : message);
    });
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
