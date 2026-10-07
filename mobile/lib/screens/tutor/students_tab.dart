import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import 'student_form_screen.dart';

class _StudentsData {
  _StudentsData(this.students, this.unassigned, this.tuitions);
  final List<Json> students;
  final List<Json> unassigned;
  final List<Json> tuitions;
}

/// Shows a username and a temporary password once, with copy buttons.
/// The password is never stored anywhere readable, so this is the only time it can be seen.
Future<void> showCredentials(BuildContext context, {required String name, required String username, required String password}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('Sign-in details for $name'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Give these to the student now. The password is shown only this once; they will be asked to choose their own when they first sign in.',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          gap12,
          for (final entry in {'Username': username, 'Temporary password': password}.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(entry.key, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              subtitle: SelectableText(entry.value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
              trailing: IconButton(
                tooltip: 'Copy ${entry.key.toLowerCase()}',
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: entry.value));
                  if (context.mounted) showToast(context, '${entry.key} copied.');
                },
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: 'TuitionTrack sign-in\nUsername: $username\nTemporary password: $password'));
            if (context.mounted) showToast(context, 'Both copied.');
          },
          child: const Text('Copy both'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    ),
  );
}

/// Every student connected to this tutor.
class StudentsTab extends StatefulWidget {
  const StudentsTab({super.key});

  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Loader<_StudentsData>(
      load: () async {
        final results = await Future.wait([repo.students(), repo.unassignedStudents(), repo.tuitions()]);
        return _StudentsData(results[0], results[1], results[2]);
      },
      builder: (context, data, reload) {
        // Students who only asked to join are not this tutor's to manage until accepted.
        final pendingIds = {
          for (final u in data.unassigned)
            if (u.str('request_status') == 'PENDING') u.str('id'),
        };
        final unassignedIds = {for (final u in data.unassigned) u.str('id')};
        final groupsOf = <String, List<String>>{};
        for (final tuition in data.tuitions) {
          for (final enrollment in tuition.maps('enrollments')) {
            groupsOf.putIfAbsent(enrollment.str('student_id'), () => []).add(tuition.str('title'));
          }
        }
        final query = _search.toLowerCase();
        final students = data.students.where((s) {
          if (query.isEmpty) return true;
          return s.str('full_name').toLowerCase().contains(query) ||
              s.str('username').toLowerCase().contains(query) ||
              s.str('phone').contains(query);
        }).toList();

        return PageBody(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (data.students.length > 5) ...[
              TextField(
                decoration: const InputDecoration(labelText: 'Search students', prefixIcon: Icon(Icons.search)),
                onChanged: (value) => setState(() => _search = value.trim()),
              ),
              gap12,
            ],
            if (data.students.isEmpty)
              const EmptyState(
                icon: Icons.person_outline,
                title: 'No students yet',
                message: 'Tap “Add student” to create an account for a student, or wait for students to send you a request.',
              )
            else if (students.isEmpty)
              const Text('No students match that search.', style: TextStyle(color: AppColors.muted))
            else
              for (final student in students) ...[
                _StudentCard(
                  student: student,
                  groups: groupsOf[student.str('id')] ?? const [],
                  pendingRequest: pendingIds.contains(student.str('id')),
                  unassigned: unassignedIds.contains(student.str('id')),
                  tuitions: data.tuitions,
                  reload: reload,
                ),
                gap8,
              ],
          ],
        );
      },
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.student,
    required this.groups,
    required this.pendingRequest,
    required this.unassigned,
    required this.tuitions,
    required this.reload,
  });
  final Json student;
  final List<String> groups;
  final bool pendingRequest;
  final bool unassigned;
  final List<Json> tuitions;
  final Future<void> Function() reload;

  Future<void> _action(BuildContext context, String action) async {
    final repo = context.read<Repo>();
    final id = student.str('id');
    final name = student.str('full_name');
    switch (action) {
      case 'edit':
        final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => StudentFormScreen(student: student)));
        if (changed == true) await reload();
      case 'group':
        final tuitionId = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(title: Text('Add $name to which group?', style: const TextStyle(fontWeight: FontWeight.w700))),
                if (tuitions.isEmpty) const ListTile(title: Text('Create a tuition group first.', style: TextStyle(color: AppColors.muted))),
                for (final t in tuitions)
                  ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: Text(t.str('title')),
                    enabled: !groups.contains(t.str('title')),
                    subtitle: groups.contains(t.str('title')) ? const Text('Already in this group') : null,
                    onTap: () => Navigator.pop(context, t.str('id')),
                  ),
              ],
            ),
          ),
        );
        if (tuitionId == null || !context.mounted) return;
        if (await attempt(context, () => repo.enroll(tuitionId, [id]), success: '$name added to the group.')) await reload();
      case 'reset':
        final ok = await confirm(
          context,
          title: 'Reset $name\'s password?',
          message: 'A new temporary password is created and shown to you once. The current password stops working and $name is signed out everywhere.',
          confirmLabel: 'Reset password',
        );
        if (!ok || !context.mounted) return;
        Json? result;
        await attempt(context, () async => result = await repo.resetStudentPassword(id));
        if (result != null && context.mounted) {
          await showCredentials(context, name: name, username: result!.str('username'), password: result!.str('temporary_password'));
          await reload();
        }
      case 'toggle':
        final active = student.flag('is_active');
        final ok = await confirm(
          context,
          title: active ? 'Deactivate $name?' : 'Reactivate $name?',
          message: active
              ? '$name will not be able to sign in and is taken off your active lists. Their history is kept and you can reactivate them at any time.'
              : '$name will be able to sign in again.',
          confirmLabel: active ? 'Deactivate' : 'Reactivate',
          danger: active,
        );
        if (!ok || !context.mounted) return;
        if (await attempt(context, () => repo.toggleStudentActive(id), success: active ? '$name deactivated.' : '$name reactivated.')) await reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = student.obj('profile') ?? {};
    final active = student.flag('is_active');
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: CircleAvatar(child: Text(student.str('full_name', '?').characters.first.toUpperCase())),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.str('full_name'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: active ? AppColors.text : AppColors.faint)),
                Text(
                  [
                    '@${student.str('username')}',
                    if (profile.str('grade_level').isNotEmpty) profile.str('grade_level'),
                    if (student.str('phone').isNotEmpty) student.str('phone'),
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final group in groups) Pill(group, color: AppColors.primarySoft, icon: Icons.groups),
                    if (pendingRequest)
                      const Pill('Asked to join — answer on Overview', color: AppColors.warning)
                    else if (groups.isEmpty && unassigned && active)
                      const Pill('Not in a group', color: AppColors.warning),
                    if (student.flag('must_change_password')) const Pill('Temporary password', color: AppColors.warning, icon: Icons.key),
                    if (!active) const Pill('Deactivated', color: AppColors.danger),
                  ],
                ),
              ],
            ),
          ),
          if (!pendingRequest)
            PopupMenuButton<String>(
              tooltip: 'Options for ${student.str('full_name')}',
              onSelected: (value) => _action(context, value),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit details')),
                if (active) const PopupMenuItem(value: 'group', child: Text('Add to a group')),
                const PopupMenuItem(value: 'reset', child: Text('Reset password')),
                PopupMenuItem(value: 'toggle', child: Text(active ? 'Deactivate' : 'Reactivate')),
              ],
            ),
        ],
      ),
    );
  }
}
