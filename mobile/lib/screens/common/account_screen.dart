import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/password_field.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

/// The signed-in person's own details, password and sign-out.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{};
  static const _userFields = ['first_name', 'last_name', 'email', 'phone'];
  static const _profileFields = ['grade_level', 'institution', 'address', 'parent_name', 'parent_phone'];

  @override
  void initState() {
    super.initState();
    final user = context.read<Session>().user ?? {};
    final profile = user.obj('profile') ?? {};
    for (final field in _userFields) {
      _c[field] = TextEditingController(text: user.str(field));
    }
    for (final field in _profileFields) {
      _c[field] = TextEditingController(text: profile.str(field));
    }
  }

  @override
  void dispose() {
    for (final controller in _c.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!checkForm(context, _form)) return;
    final session = context.read<Session>();
    final repo = context.read<Repo>();
    final changes = <String, dynamic>{for (final field in _userFields) field: _c[field]!.text.trim()};
    if (session.isStudent) {
      for (final field in _profileFields) {
        changes[field] = _c[field]!.text.trim();
      }
    }
    await attempt(context, () async {
      await repo.updateMe(changes);
      await session.refreshUser();
    }, success: 'Your details have been saved.');
  }

  Future<void> _changePassword() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ChangePasswordSheet(),
    );
    if (changed == true && mounted) showToast(context, 'Password changed. Other devices have been signed out.');
  }

  Future<void> _signOutEverywhere() async {
    final session = context.read<Session>();
    final ok = await confirm(
      context,
      title: 'Sign out on all devices?',
      message: 'Every phone and browser signed in to this account, including this one, will be signed out.',
      confirmLabel: 'Sign out everywhere',
      danger: true,
    );
    if (!ok || !mounted) return;
    await attempt(context, () async {
      await session.api.post('/auth/logout-all/');
      await session.logout();
    });
  }

  Widget _field(String name, String label, {TextInputType? type, String? Function(String?)? validator, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _c[name],
        keyboardType: type,
        maxLines: maxLines,
        textCapitalization: type == null ? TextCapitalization.words : TextCapitalization.none,
        decoration: InputDecoration(labelText: label),
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user ?? {};
    return Scaffold(
      appBar: AppBar(title: Text('My account')),
      body: Form(
        key: _form,
        child: PageBody(
          children: [
            AppCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.25),
                    child: Text(
                      session.displayName.isEmpty ? '?' : session.displayName[0].toUpperCase(),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primarySoft),
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(session.displayName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        Text('@${user.str('username')} · ${session.isTutor ? 'Tutor' : 'Student'}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SectionTitle('My details'),
            if (session.isTutor && (user.str('tutor_code').isNotEmpty)) ...[
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('MY STUDENT INVITE CODE',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primarySoft)),
                          const SizedBox(height: 4),
                          Text(user.str('tutor_code'),
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3, color: AppColors.primarySoft)),
                          const Text('Students enter this code to request connection with you.',
                              style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy invite code',
                      icon: const Icon(Icons.copy, color: AppColors.primarySoft),
                      onPressed: () async {
                        HapticFeedback.lightImpact();
                        await Clipboard.setData(ClipboardData(text: user.str('tutor_code')));
                        if (context.mounted) showToast(context, 'Invite code copied.');
                      },
                    ),
                  ],
                ),
              ),
              gap12,
            ],
            _field('first_name', 'First name', validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            _field('last_name', 'Last name'),
            _field('email', 'Email', type: TextInputType.emailAddress, validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return null;
              return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text) ? null : 'Enter a valid email address';
            }),
            _field('phone', 'Phone', type: TextInputType.phone),
            if (session.isStudent) ...[
              _field('grade_level', 'Class / grade'),
              _field('institution', 'School / college'),
              _field('address', 'Address'),
              _field('parent_name', 'Guardian name'),
              _field('parent_phone', 'Guardian phone', type: TextInputType.phone),
            ],
            BusyButton(onPressed: _save, label: 'Save details', icon: Icons.check),
            SectionTitle('Security'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Change password'),
                    subtitle: const Text('Signs your other devices out'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _changePassword,
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.devices_other_outlined),
                    title: const Text('Sign out on all devices'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _signOutEverywhere,
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: AppColors.danger),
                    title: Text('Sign out', style: TextStyle(color: AppColors.danger)),
                    onTap: () => session.logout(),
                  ),
                ],
              ),
            ),
            gap16,
            Text('Server: ${session.api.baseUrl}', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.outlineVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
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
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Change password', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              gap12,
              if (_error != null) ...[Banner2(_error!, color: AppColors.danger, icon: Icons.error_outline), gap12],
              PasswordField(controller: _current, label: 'Current password', validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
              gap12,
              PasswordField(
                controller: _next,
                label: 'New password',
                isNew: true,
                helper: 'At least 8 characters. Avoid common words and your own name.',
                validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
              ),
              gap12,
              PasswordField(
                controller: _repeat,
                label: 'Repeat the new password',
                isNew: true,
                validator: (v) => v != _next.text ? 'The two passwords are different' : null,
              ),
              gap16,
              BusyButton(onPressed: _save, label: 'Change password'),
            ],
          ),
        ),
      ),
    );
  }
}
