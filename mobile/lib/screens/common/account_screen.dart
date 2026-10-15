import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/password_field.dart';
import '../../widgets/share.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

/// The signed-in person's own details on one screen: a header with photo, name
/// and invite code, a flat settings-style list of fields (saved from the app
/// bar), and the password and sign-out actions underneath.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{};
  final _initial = <String, String>{};
  static const _profileFields = ['grade_level', 'institution', 'address', 'parent_name', 'parent_phone'];
  bool _saving = false;
  bool _photoBusy = false;

  @override
  void initState() {
    super.initState();
    _fill(context.read<Session>().user ?? {});
    for (final controller in _c.values) {
      controller.addListener(_changed);
    }
  }

  void _fill(Json user) {
    final profile = user.obj('profile') ?? {};
    final values = <String, String>{
      'full_name': [user.str('first_name'), user.str('last_name')].where((p) => p.trim().isNotEmpty).join(' '),
      'email': user.str('email'),
      'phone': user.str('phone'),
      for (final field in _profileFields) field: profile.str(field),
    };
    values.forEach((field, value) {
      _initial[field] = value;
      final controller = _c[field];
      if (controller == null) {
        _c[field] = TextEditingController(text: value);
      } else if (controller.text != value) {
        controller.text = value;
      }
    });
  }

  void _changed() => setState(() {});

  bool get _dirty => _c.entries.any((e) => e.value.text.trim() != (_initial[e.key] ?? '').trim());

  @override
  void dispose() {
    for (final controller in _c.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!checkForm(context, _form)) return;
    FocusScope.of(context).unfocus();
    final session = context.read<Session>();
    final repo = context.read<Repo>();
    // "Full name" is stored as first name (the first word) and last name (the rest).
    final name = _c['full_name']!.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final space = name.indexOf(' ');
    final changes = <String, dynamic>{
      'first_name': space < 0 ? name : name.substring(0, space),
      'last_name': space < 0 ? '' : name.substring(space + 1),
      'email': _c['email']!.text.trim(),
      'phone': _c['phone']!.text.trim(),
    };
    if (session.isStudent) {
      for (final field in _profileFields) {
        changes[field] = _c[field]!.text.trim();
      }
    }
    setState(() => _saving = true);
    final ok = await attempt(context, () async {
      await repo.updateMe(changes);
      await session.refreshUser();
    }, success: tr('Saved.'));
    if (!mounted) return;
    if (ok) _fill(session.user ?? {});
    setState(() => _saving = false);
  }

  Future<void> _photo(bool hasPhoto) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(tr('Take a photo')), onTap: () => Navigator.pop(context, 'camera')),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(tr('Choose from gallery')), onTap: () => Navigator.pop(context, 'gallery')),
            if (hasPhoto)
              ListTile(
                leading: Icon(Icons.delete_outline, color: tone(context, AppColors.danger)),
                title: Text(tr('Remove photo'), style: TextStyle(color: tone(context, AppColors.danger))),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final session = context.read<Session>();
    final repo = context.read<Repo>();
    if (choice == 'remove') {
      setState(() => _photoBusy = true);
      await attempt(context, () async {
        await repo.removeProfilePhoto();
        await session.refreshUser();
      }, success: tr('Photo removed.'));
      if (mounted) setState(() => _photoBusy = false);
      return;
    }
    XFile? file;
    try {
      // A profile photo is shown small: 800 px is plenty and keeps the upload quick.
      file = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
    } catch (_) {
      if (mounted) showToast(context, tr('Could not open the camera or gallery. Check the app permissions.'), error: true);
      return;
    }
    final picked = file;
    if (picked == null || !mounted) return;
    setState(() => _photoBusy = true);
    await attempt(context, () async {
      final bytes = await picked.readAsBytes();
      var name = picked.name.toLowerCase();
      if (!RegExp(r'\.(png|jpe?g|webp)$').hasMatch(name)) name = '$name.jpg';
      await repo.setProfilePhoto(bytes, name);
      await session.refreshUser();
    }, success: tr('Photo updated. Your students see it next to your name.'));
    if (mounted) setState(() => _photoBusy = false);
  }

  Future<void> _changePassword() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ChangePasswordSheet(),
    );
    if (changed == true && mounted) showToast(context, tr('Password changed. Other devices have been signed out.'));
  }

  Future<void> _signOutEverywhere() async {
    final session = context.read<Session>();
    final ok = await confirm(
      context,
      title: tr('Sign out on all devices?'),
      message: tr('Every phone and browser signed in to this account, including this one, will be signed out.'),
      confirmLabel: tr('Sign out everywhere'),
      danger: true,
    );
    if (!ok || !mounted) return;
    await attempt(context, () async {
      await session.api.post('/auth/logout-all/');
      await session.logout();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user ?? {};
    final scheme = Theme.of(context).colorScheme;
    final dirty = _dirty;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('My account')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _saving
                ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton(onPressed: dirty ? _save : null, child: Text(tr('Save'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: PageBody(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _Header(
              user: user,
              name: session.displayName,
              isTutor: session.isTutor,
              photoBusy: _photoBusy,
              onPhoto: session.isTutor ? () => _photo(user.str('profile_picture_url').isNotEmpty) : null,
            ),
            gap16,
            FlatGroup(children: [
              _FieldRow(
                label: tr('Full name'),
                controller: _c['full_name']!,
                capitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty) ? tr('Required') : null,
              ),
              _FieldRow(
                label: tr('Email'),
                controller: _c['email']!,
                type: TextInputType.emailAddress,
                hint: tr('Optional'),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return null;
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text) ? null : tr('Enter a valid email address');
                },
              ),
              _FieldRow(label: tr('Phone'), controller: _c['phone']!, type: TextInputType.phone, hint: tr('Optional')),
              if (session.isStudent) ...[
                _FieldRow(label: tr('Class'), controller: _c['grade_level']!, hint: tr('e.g. Class 10')),
                _FieldRow(label: tr('School'), controller: _c['institution']!, capitalization: TextCapitalization.words),
                _FieldRow(label: tr('Address'), controller: _c['address']!, capitalization: TextCapitalization.words),
                _FieldRow(label: tr('Guardian'), controller: _c['parent_name']!, capitalization: TextCapitalization.words),
                _FieldRow(label: tr('Guardian phone'), controller: _c['parent_phone']!, type: TextInputType.phone),
              ],
            ]),
            gap16,
            FlatGroup(children: [
              _ActionRow(icon: Icons.lock_outline, label: tr('Change password'), onTap: _changePassword),
              _ActionRow(icon: Icons.devices_other_outlined, label: tr('Sign out on all devices'), onTap: _signOutEverywhere),
              _ActionRow(icon: Icons.logout, label: tr('Sign out'), danger: true, onTap: () => session.logout()),
            ]),
            if (dirty) ...[
              gap12,
              Text(tr('You have unsaved changes. Tap Save at the top.'),
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Photo, name, role and (for tutors) the invite code with a copy button.
class _Header extends StatelessWidget {
  const _Header({required this.user, required this.name, required this.isTutor, required this.photoBusy, this.onPhoto});
  final Json user;
  final String name;
  final bool isTutor;
  final bool photoBusy;
  final VoidCallback? onPhoto;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photo = context.read<Session>().api.mediaUrl(user.str('profile_picture_url'));
    final initial = Text(
      name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: tone(context, AppColors.primarySoft)),
    );
    final code = user.str('tutor_code');
    return Row(
      children: [
        Semantics(
          button: onPhoto != null,
          label: onPhoto == null ? tr('Profile picture') : tr('Change profile photo'),
          child: GestureDetector(
            onTap: photoBusy ? null : onPhoto,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.22),
                  child: ClipOval(
                    child: SizedBox.square(
                      dimension: 68,
                      child: photoBusy
                          ? const Padding(padding: EdgeInsets.all(22), child: CircularProgressIndicator(strokeWidth: 2))
                          : photo.isEmpty
                              ? Center(child: initial)
                              : Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, _, _) => Center(child: initial)),
                    ),
                  ),
                ),
                if (onPhoto != null)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                      ),
                      child: const Icon(Icons.photo_camera, size: 13, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              Text('@${user.str('username')} · ${isTutor ? tr('Tutor') : tr('Student')}', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              if (isTutor && code.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) showToast(context, tr('Invite code copied. Students enter it to connect with you.'));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tr('Invite code '), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                          Text(code,
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 2, color: tone(context, AppColors.primarySoft))),
                          const SizedBox(width: 6),
                          Icon(Icons.copy_rounded, size: 15, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: tr('Share invite code'),
                            visualDensity: VisualDensity.compact,
                            iconSize: 18,
                            icon: Icon(Icons.share_rounded, color: tone(context, AppColors.primarySoft)),
                            onPressed: () => shareInviteCode(context, code),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.controller,
    this.type,
    this.hint,
    this.validator,
    this.capitalization = TextCapitalization.none,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? type;
  final String? hint;
  final String? Function(String?)? validator;
  final TextCapitalization capitalization;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const none = InputBorder.none;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 12, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 104, child: Text(label, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant))),
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: type,
              textCapitalization: capitalization,
              validator: validator,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: hint,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: none,
                enabledBorder: none,
                focusedBorder: none,
                errorBorder: none,
                focusedErrorBorder: none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? tone(context, AppColors.danger) : scheme.onSurface;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, size: 20, color: danger ? color : scheme.onSurfaceVariant),
      title: Text(label, style: TextStyle(fontSize: 15, color: color)),
      trailing: danger ? null : Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
      onTap: onTap,
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
              Text(tr('Change password'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              gap12,
              if (_error != null) ...[Banner2(_error!, color: AppColors.danger, icon: Icons.error_outline), gap12],
              PasswordField(controller: _current, label: tr('Current password'), validator: (v) => (v == null || v.isEmpty) ? tr('Required') : null),
              gap12,
              PasswordField(
                controller: _next,
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
                validator: (v) => v != _next.text ? tr('The two passwords are different') : null,
              ),
              gap16,
              BusyButton(onPressed: _save, label: tr('Change password')),
            ],
          ),
        ),
      ),
    );
  }
}
