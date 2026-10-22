import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/password_field.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

enum _Step { ask, code, password, done }

/// Forgot password: username or email → 6-digit code from the email → new password.
/// Pops with the account's username once the password has been changed.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialIdentifier = ''});

  final String initialIdentifier;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const _resendSeconds = 60;

  final _form = GlobalKey<FormState>();
  late final _identifier = TextEditingController(text: widget.initialIdentifier);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();

  _Step _step = _Step.ask;
  bool _busy = false;
  String? _error;
  String? _notice;
  bool _emailReady = true;
  Json? _reset; // {uid, token, username}
  int _wait = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkEmail();
  }

  Future<void> _checkEmail() async {
    try {
      final meta = await context.read<Repo>().meta();
      final auth = meta['auth'];
      if (mounted && auth is Map && auth['password_reset_email'] == false) setState(() => _emailReady = false);
    } catch (_) {
      // The server may be waking up; the form works anyway.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _wait = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _wait--);
      if (_wait <= 0) timer.cancel();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _run(() async {
        final repo = context.read<Repo>();
        final message = await repo.requestPasswordReset(_identifier.text.trim());
        if (!mounted) return;
        _code.clear();
        setState(() {
          _notice = message;
          _step = _Step.code;
        });
        _startCooldown();
      });

  Future<void> _verify() => _run(() async {
        final reset = await context.read<Repo>().verifyResetCode(_identifier.text.trim(), _code.text.trim());
        if (mounted) {
          setState(() {
            _reset = reset;
            _step = _Step.password;
          });
        }
      });

  Future<void> _save() => _run(() async {
        await context.read<Repo>().confirmPasswordReset(_reset!.str('uid'), _reset!.str('token'), _password.text);
        if (mounted) setState(() => _step = _Step.done);
      });

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    switch (_step) {
      case _Step.ask:
        await _sendCode();
      case _Step.code:
        await _verify();
      case _Step.password:
        await _save();
      case _Step.done:
        Navigator.pop(context, _reset?.str('username'));
    }
  }

  String get _title => switch (_step) {
        _Step.ask => tr('Forgot your password?'),
        _Step.code => tr('Enter the code'),
        _Step.password => tr('Choose a new password'),
        _Step.done => tr('Password changed'),
      };

  String get _subtitle => switch (_step) {
        _Step.ask => tr('Enter your username or email. We will email you a 6-digit code.'),
        _Step.code => tr('Type the 6-digit code from the email. Check the spam folder if it is not in your inbox.'),
        _Step.password => tr('For the account “{p0}”.', {'p0': Raw(_reset?.str('username') ?? '')}),
        _Step.done => tr('You are signed out on all devices. Sign in with your new password.'),
      };

  String get _button => switch (_step) {
        _Step.ask => tr('Email me a code'),
        _Step.code => tr('Continue'),
        _Step.password => tr('Save new password'),
        _Step.done => tr('Go to sign in'),
      };

  @override
  Widget build(BuildContext context) {
    final muted = context.tt.textSecondary;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Reset your password'))),
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
                      if (_step == _Step.done) ...[
                        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56),
                        gap16,
                      ],
                      Text(_title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(_subtitle, style: TextStyle(fontSize: 14, color: muted)),
                      gap24,
                      if (!_emailReady && _step == _Step.ask) ...[
                        Banner2(
                          tr('Email sending is not set up on this server yet, so the code may not arrive. Ask your tutor for a new temporary password.'),
                          color: AppColors.warning,
                        ),
                        gap12,
                      ],
                      if (_error != null) ...[Banner2(_error!, color: AppColors.danger, icon: Icons.error_outline), gap12],
                      if (_step == _Step.code && _notice != null && _notice!.isNotEmpty) ...[
                        Banner2(_notice!, color: AppColors.success, icon: Icons.mark_email_read_outlined),
                        gap12,
                      ],
                      ..._fields(),
                      gap24,
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: context.tt.onPrimary))
                            : Text(_button),
                      ),
                      if (_step == _Step.code) ...[
                        gap8,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: _busy ? null : () => setState(() {
                                _step = _Step.ask;
                                _error = null;
                              }),
                              child: Text(tr('Change username')),
                            ),
                            TextButton.icon(
                              onPressed: _busy || _wait > 0 ? null : _sendCode,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: Text(_wait > 0 ? tr('Send again in {n}s', {'n': _wait}) : tr('Send a new code')),
                            ),
                          ],
                        ),
                      ],
                      if (_step == _Step.ask) ...[
                        gap16,
                        Text(
                          tr('Student with no email on your account? Ask your tutor — they can give you a new temporary password.'),
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                      ],
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

  List<Widget> _fields() {
    switch (_step) {
      case _Step.ask:
        return [
          FieldLabel(tr('Username or email')),
          TextFormField(
            controller: _identifier,
            autofocus: _identifier.text.isEmpty,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded)),
            validator: (value) => (value == null || value.trim().isEmpty) ? tr('Required') : null,
          ),
        ];
      case _Step.code:
        return [
          FieldLabel(tr('6-digit code')),
          TextFormField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.w700),
            textInputAction: TextInputAction.done,
            onChanged: (value) {
              if (value.length == 6) _submit();
            },
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(hintText: '••••••', counterText: ''),
            validator: (value) => (value ?? '').length != 6 ? tr('Enter all 6 digits') : null,
          ),
        ];
      case _Step.password:
        return [
          PasswordField(
            controller: _password,
            label: tr('New password'),
            isNew: true,
            helper: tr('At least 8 characters. Avoid common words and your own name.'),
            validator: (v) => (v == null || v.length < 8) ? tr('Use at least 8 characters') : null,
          ),
          gap12,
          PasswordField(
            controller: _repeat,
            label: tr('Repeat the new password'),
            isNew: true,
            onSubmitted: (_) => _submit(),
            validator: (v) => v != _password.text ? tr('The two passwords are different') : null,
          ),
        ];
      case _Step.done:
        return const [];
    }
  }
}
