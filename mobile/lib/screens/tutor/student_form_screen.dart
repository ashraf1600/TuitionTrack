import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import 'students_tab.dart' show showCredentials;

/// Create a student account, or edit a student's details. Pops with `true` when saved.
class StudentFormScreen extends StatefulWidget {
  const StudentFormScreen({super.key, this.student});
  final Json? student;

  @override
  State<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends State<StudentFormScreen> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{};
  List<Json> _tuitions = const [];
  String? _tuitionId;
  String? _error;

  bool get _editing => widget.student != null;

  static String _temporaryPassword() {
    // No look-alike characters (0/O, 1/l), so it can be read out or copied by hand.
    const alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(10, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    final s = widget.student ?? {};
    final profile = s.obj('profile') ?? {};
    String name(String key) {
      if (s.str(key).isNotEmpty) return s.str(key);
      // The list only carries full_name; split it for the two name boxes.
      final parts = s.str('full_name').split(' ');
      if (key == 'first_name') return parts.first;
      return parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }

    _c['first_name'] = TextEditingController(text: _editing ? name('first_name') : '');
    _c['last_name'] = TextEditingController(text: _editing ? name('last_name') : '');
    _c['username'] = TextEditingController(text: s.str('username'));
    _c['password'] = TextEditingController(text: _editing ? '' : _temporaryPassword());
    _c['email'] = TextEditingController(text: s.str('email'));
    _c['phone'] = TextEditingController(text: s.str('phone'));
    for (final field in ['grade_level', 'institution', 'address', 'parent_name', 'parent_phone', 'notes']) {
      _c[field] = TextEditingController(text: profile.str(field));
    }
    if (!_editing) _loadTuitions();
  }

  Future<void> _loadTuitions() async {
    try {
      final tuitions = await context.read<Repo>().tuitions();
      if (mounted) setState(() => _tuitions = tuitions);
    } on ApiException {
      // The group choice is optional; the form works without it.
    }
  }

  @override
  void dispose() {
    for (final controller in _c.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _v(String name) => _c[name]!.text.trim();

  Future<void> _save() async {
    if (!checkForm(context, _form)) return;
    final repo = context.read<Repo>();
    setState(() => _error = null);
    try {
      if (_editing) {
        await repo.updateStudent(widget.student!.str('id'), {
          'first_name': _v('first_name'),
          'last_name': _v('last_name'),
          'email': _v('email'),
          'phone': _v('phone'),
          'profile': {for (final f in ['grade_level', 'institution', 'address', 'parent_name', 'parent_phone', 'notes']) f: _v(f)},
        });
        if (!mounted) return;
        showToast(context, 'Student updated.');
        Navigator.pop(context, true);
      } else {
        final password = _c['password']!.text;
        await repo.createStudent({
          'username': _v('username'),
          'password': password,
          'first_name': _v('first_name'),
          'last_name': _v('last_name'),
          'email': _v('email'),
          'phone': _v('phone'),
          for (final f in ['grade_level', 'institution', 'address', 'parent_name', 'parent_phone', 'notes']) f: _v(f),
          'tuition_id': ?_tuitionId,
        });
        if (!mounted) return;
        await showCredentials(context, name: _v('first_name'), username: _v('username'), password: password);
        if (mounted) Navigator.pop(context, true);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Widget _field(String name, String label, {TextInputType? type, String? Function(String?)? validator, String? helper, int maxLines = 1, bool words = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _c[name],
        keyboardType: type,
        maxLines: maxLines,
        autocorrect: words,
        textCapitalization: words && type == null ? TextCapitalization.words : TextCapitalization.none,
        decoration: InputDecoration(labelText: label, helperText: helper),
        validator: validator,
      ),
    );
  }

  String? _required(String? value) => (value == null || value.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit student' : 'Add a student')),
      body: Form(
        key: _form,
        child: PageBody(
          children: [
            if (_error != null) ...[Banner2(_error!, color: AppColors.danger, icon: Icons.error_outline), gap12],
            _field('first_name', 'First name', validator: _required),
            _field('last_name', 'Last name'),
            if (!_editing) ...[
              _field(
                'username',
                'Username',
                words: false,
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Required';
                  return RegExp(r'^[\w.@+-]+$').hasMatch(value) ? null : 'Use letters, numbers and . _ - only (no spaces)';
                },
                helper: 'The student signs in with this.',
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: _c['password'],
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Temporary password',
                    helperText: 'The student must choose their own password at first sign-in.',
                    suffixIcon: IconButton(
                      tooltip: 'Make another password',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => setState(() => _c['password']!.text = _temporaryPassword()),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters' : null,
                ),
              ),
            ],
            _field('email', 'Email (optional)', type: TextInputType.emailAddress, words: false, validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return null;
              return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text) ? null : 'Enter a valid email address';
            }),
            _field('phone', 'Phone (optional)', type: TextInputType.phone),
            _field('grade_level', 'Class / grade'),
            _field('institution', 'School / college'),
            _field('address', 'Address'),
            _field('parent_name', 'Guardian name'),
            _field('parent_phone', 'Guardian phone', type: TextInputType.phone),
            _field('notes', 'Private notes (only you see these)', maxLines: 2, words: false),
            if (!_editing && _tuitions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String?>(
                  initialValue: _tuitionId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Add to a group now (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Not yet')),
                    for (final t in _tuitions) DropdownMenuItem<String?>(value: t.str('id'), child: Text(t.str('title'), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (value) => setState(() => _tuitionId = value),
                ),
              ),
            gap12,
            BusyButton(onPressed: _save, label: _editing ? 'Save changes' : 'Create student', icon: Icons.check),
          ],
        ),
      ),
    );
  }
}
