import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
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
      title: Text(tr('Sign-in details for {p0}', {'p0': name})),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Give these to the student now. The password is shown only this once; they will be asked to choose their own when they first sign in.'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          gap12,
          for (final entry in {tr('Username'): username, tr('Temporary password'): password}.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(entry.key, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
              subtitle: SelectableText(entry.value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
              trailing: IconButton(
                tooltip: tr('Copy {p0}', {'p0': entry.key.toLowerCase()}),
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: entry.value));
                  if (context.mounted) showToast(context, tr('{p0} copied.', {'p0': entry.key}));
                },
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: tr('TuitionTrack sign-in\nUsername: {p0}\nTemporary password: {p1}', {'p0': Raw(username), 'p1': Raw(password)})));
            if (context.mounted) showToast(context, tr('Both copied.'));
          },
          child: Text(tr('Copy both')),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done'))),
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
              _SearchField(hint: tr('Search students'), onChanged: (value) => setState(() => _search = value.trim())),
              gap16,
            ],
            if (data.students.isEmpty)
              EmptyState(
                icon: Icons.person_outline,
                title: tr('No students yet'),
                message: tr('Tap “Add student” to create an account for a student, or wait for students to send you a request.'),
              )
            else if (students.isEmpty)
              Text(tr('No students match that search.'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
            else
              // One card, students separated by hairlines.
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: context.tt.card, borderRadius: BorderRadius.circular(16), boxShadow: context.tt.cardShadow),
                child: Column(
                  children: [
                    for (final (i, student) in students.indexed) ...[
                      if (i > 0) Divider(height: 1, indent: 16, endIndent: 16, color: context.tt.border),
                      _StudentCard(
                        student: student,
                        groups: groupsOf[student.str('id')] ?? const [],
                        pendingRequest: pendingIds.contains(student.str('id')),
                        unassigned: unassignedIds.contains(student.str('id')),
                        tuitions: data.tuitions,
                        reload: reload,
                      ),
                    ],
                  ],
                ),
              ),
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
                ListTile(title: Text(tr('Add {p0} to which tuition?', {'p0': name}), style: const TextStyle(fontWeight: FontWeight.w700))),
                if (tuitions.isEmpty) ListTile(title: Text(tr('Create a tuition first.'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                for (final t in tuitions)
                  ListTile(
                    leading: Icon(Icons.groups_outlined),
                    title: Text(t.str('title')),
                    enabled: !groups.contains(t.str('title')),
                    subtitle: groups.contains(t.str('title')) ? Text(tr('Already in this tuition')) : null,
                    onTap: () => Navigator.pop(context, t.str('id')),
                  ),
              ],
            ),
          ),
        );
        if (tuitionId == null || !context.mounted) return;
        if (await attempt(context, () => repo.enroll(tuitionId, [id]), success: tr('{name} added to the tuition.', {'name': name}))) await reload();
      case 'reset':
        final ok = await confirm(
          context,
          title: tr('Reset the password of {name}?', {'name': name}),
          message: tr('A new temporary password is created and shown to you once. The current password stops working and {name} is signed out everywhere.', {'name': name}),
          confirmLabel: tr('Reset password'),
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
          title: active ? tr('Deactivate {name}?', {'name': name}) : tr('Reactivate {name}?', {'name': name}),
          message: active
              ? tr('{name} will not be able to sign in and is taken off your active lists. Their history is kept and you can reactivate them at any time.', {'name': name})
              : tr('{name} will be able to sign in again.', {'name': name}),
          confirmLabel: active ? tr('Deactivate') : tr('Reactivate'),
          danger: active,
        );
        if (!ok || !context.mounted) return;
        if (await attempt(context, () => repo.toggleStudentActive(id), success: active ? tr('{name} deactivated.', {'name': name}) : tr('{name} reactivated.', {'name': name}))) await reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final profile = student.obj('profile') ?? {};
    final active = student.flag('is_active');
    final name = student.str('full_name', '?');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 76),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: tt.primaryContainer,
              child: Text(name.characters.first.toUpperCase(),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: tt.onPrimaryContainer)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: active ? tt.textPrimary : tt.textTertiary)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      '@${student.str('username')}',
                      if (profile.str('grade_level').isNotEmpty) profile.str('grade_level'),
                      if (student.str('phone').isNotEmpty) student.str('phone'),
                    ].join(' · '),
                    style: TextStyle(color: tt.textSecondary, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final group in groups) Pill(group, color: AppColors.primarySoft),
                      if (pendingRequest)
                        Pill(tr('Asked to join — answer on Overview'), color: AppColors.warning, icon: Icons.person_add_alt_1_outlined)
                      else if (groups.isEmpty && unassigned && active)
                        Pill(tr('Not in a tuition'), color: AppColors.warning, icon: Icons.error_outline_rounded),
                      if (student.flag('must_change_password')) Pill(tr('Temporary password'), color: AppColors.warning, icon: Icons.key),
                      if (!active) Pill(tr('Deactivated'), color: AppColors.danger, icon: Icons.block_rounded),
                    ],
                  ),
                ],
              ),
            ),
            if (!pendingRequest)
              PopupMenuButton<String>(
                tooltip: tr('Options for {p0}', {'p0': name}),
                icon: Icon(Icons.more_vert_rounded, color: tt.textTertiary),
                style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                onSelected: (value) => _action(context, value),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(tr('Edit details'))),
                  if (active) PopupMenuItem(value: 'group', child: Text(tr('Add to a tuition'))),
                  PopupMenuItem(value: 'reset', child: Text(tr('Reset password'))),
                  PopupMenuItem(value: 'toggle', child: Text(active ? tr('Deactivate') : tr('Reactivate'))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A 48 dp search box on the card colour.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none);
    return SizedBox(
      height: 48,
      child: TextField(
        onChanged: onChanged,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(Icons.search_rounded, color: tt.textTertiary),
          filled: true,
          fillColor: tt.card,
          contentPadding: EdgeInsets.zero,
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: tt.primary, width: 1.5)),
        ),
      ),
    );
  }
}
