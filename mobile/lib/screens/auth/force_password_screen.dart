import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../widgets/password_field.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

/// Shown instead of the app while the account still has a temporary password
/// (one a tutor chose or reset). Nothing else is reachable until it is changed.
class ForcePasswordScreen extends StatefulWidget {
  const ForcePasswordScreen({super.key});

  @override
  State<ForcePasswordScreen> createState() => _ForcePasswordScreenState();
}

class _ForcePasswordScreenState extends State<ForcePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!checkForm(context, _form)) return;
    setState(() => _error = null);
    try {
      await context.read<Session>().changePassword(_current.text, _next.text);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Choose your password')),
        actions: [TextButton(onPressed: session.logout, child: Text(tr('Sign out')))],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 460),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.key_rounded, size: 44, color: AppColors.warning),
                    gap12,
                    Text(
                      tr('Hello {p0}. Your account has a temporary password. Choose your own before you continue — only you will know it.', {'p0': session.displayName}),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    gap24,
                    if (_error != null) ...[Banner2(_error!, color: AppColors.danger, icon: Icons.error_outline), gap12],
                    PasswordField(
                      controller: _current,
                      label: tr('Temporary password'),
                      validator: (value) => (value == null || value.isEmpty) ? tr('Required') : null,
                    ),
                    gap12,
                    PasswordField(
                      controller: _next,
                      label: tr('New password'),
                      isNew: true,
                      helper: tr('At least 8 characters. Avoid common words and your own name.'),
                      validator: (value) => (value == null || value.length < 8) ? tr('Use at least 8 characters') : null,
                    ),
                    gap12,
                    PasswordField(
                      controller: _repeat,
                      label: tr('Repeat the new password'),
                      isNew: true,
                      validator: (value) => value != _next.text ? tr('The two passwords are different') : null,
                    ),
                    gap16,
                    BusyButton(onPressed: _save, label: tr('Save and continue'), icon: Icons.check),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
