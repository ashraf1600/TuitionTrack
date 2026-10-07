import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/cycle_progress.dart';
import '../common/leaderboard_screen.dart';
import '../common/notifications.dart';
import 'exam_result_screen.dart';
import 'exam_take_screen.dart';

class _StudentData {
  _StudentData(this.tuitions, this.connections, this.exams);
  final List<Json> tuitions;
  final List<Json> connections;
  final List<Json> exams;
}

/// The student's app: their groups and class progress, their tutors, and their exams.
class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  final _loader = GlobalKey<LoaderState<_StudentData>>();
  int _tab = 0;

  Future<_StudentData> _load() async {
    final repo = context.read<Repo>();
    final results = await Future.wait([repo.tuitions(), repo.connections(), repo.exams()]);
    return _StudentData(results[0], results[1], results[2]);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(title: Text(_tab == 0 ? 'Hello, ${session.displayName}' : 'Exams & assignments'), actions: homeActions(context)),
      body: Loader<_StudentData>(
        key: _loader,
        load: _load,
        builder: (context, data, reload) => _tab == 0
            ? _GroupsTab(data: data, reload: reload)
            : _ExamsTab(exams: data.exams, reload: reload),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          setState(() => _tab = index);
          _loader.currentState?.reload();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'My classes'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Exams'),
        ],
      ),
    );
  }
}

// ── My classes ───────────────────────────────────────────────────────────────

class _GroupsTab extends StatelessWidget {
  const _GroupsTab({required this.data, required this.reload});
  final _StudentData data;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final pending = data.connections.where((c) => c.str('status') == 'PENDING').toList();
    return PageBody(
      children: [
        const SectionTitle('My tuition groups', icon: Icons.groups_outlined, subtitle: 'Class progress is shared by everyone in the group.'),
        if (data.tuitions.isEmpty)
          EmptyState(
            icon: Icons.groups_outlined,
            title: 'You are not in a tuition group yet',
            message: pending.isEmpty
                ? 'Send a request to your tutor below. Once they accept and add you to a group, it appears here.'
                : 'Your request is with your tutor. Once they add you to a group, it appears here.',
          )
        else
          for (final tuition in data.tuitions) ...[_GroupCard(tuition: tuition), gap12],
        gap8,
        _TutorConnect(connections: data.connections, tuitions: data.tuitions, reload: reload),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.tuition});
  final Json tuition;

  @override
  Widget build(BuildContext context) {
    final cycle = tuition.obj('active_cycle');
    final routine = tuition.maps('routine');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tuition.str('title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text(
            [
              if (tuition.str('subject').isNotEmpty) tuition.str('subject'),
              'Tutor: ${tuition.str('tutor_name')}',
              '${tuition.integer('enrolled_count')} student${tuition.integer('enrolled_count') == 1 ? '' : 's'}',
            ].join(' · '),
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          if (tuition.str('description').isNotEmpty) ...[
            gap8,
            Text(tuition.str('description'), style: const TextStyle(fontSize: 13)),
          ],
          if (routine.isNotEmpty) ...[
            gap12,
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final slot in routine)
                  Pill(
                    '${slot.str('day').length > 3 ? slot.str('day').substring(0, 3) : slot.str('day')} ${to12h(slot.str('start_time', slot.str('time')))}',
                    icon: Icons.schedule,
                    color: AppColors.primarySoft,
                  ),
              ],
            ),
          ],
          gap12,
          if (cycle == null)
            const Text('No classes recorded yet.', style: TextStyle(color: AppColors.muted))
          else
            CycleProgress(cycle: cycle),
        ],
      ),
    );
  }
}

class _TutorConnect extends StatelessWidget {
  const _TutorConnect({required this.connections, required this.tuitions, required this.reload});
  final List<Json> connections;
  final List<Json> tuitions;
  final Future<void> Function() reload;

  Future<void> _find(BuildContext context) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FindTutorSheet(existing: connections),
    );
    if (sent == true) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'My tutors',
          icon: Icons.handshake_outlined,
          trailing: TextButton.icon(onPressed: () => _find(context), icon: const Icon(Icons.search, size: 18), label: const Text('Find a tutor')),
        ),
        // A tutor who added this student straight into a group never received a request from them.
        for (final name in {
          for (final t in tuitions)
            if (!connections.any((c) => c.str('tutor_name') == t.str('tutor_name'))) t.str('tutor_name'),
        }) ...[
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(name),
              subtitle: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Align(alignment: Alignment.centerLeft, child: Pill('Your tutor', color: AppColors.success)),
              ),
            ),
          ),
          gap8,
        ],
        if (connections.isEmpty && tuitions.isEmpty)
          const EmptyState(
            icon: Icons.person_search_outlined,
            title: 'No tutor yet',
            message: 'Find your tutor and send a request. They decide whether to accept.',
          )
        else if (connections.isNotEmpty)
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < connections.length; i++) ...[
                  if (i > 0) const Divider(),
                  Builder(builder: (context) {
                    final c = connections[i];
                    final status = c.str('status');
                    final (label, color) = switch (status) {
                      'ACCEPTED' => ('Connected', AppColors.success),
                      'REJECTED' => ('Declined', AppColors.danger),
                      _ => ('Waiting for the tutor', AppColors.warning),
                    };
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(c.str('tutor_name')),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Align(alignment: Alignment.centerLeft, child: Pill(label, color: color)),
                      ),
                      trailing: status == 'PENDING'
                          ? TextButton(
                              onPressed: () async {
                                final ok = await confirm(
                                  context,
                                  title: 'Withdraw this request?',
                                  message: 'Your request to ${c.str('tutor_name')} will be removed.',
                                  confirmLabel: 'Withdraw',
                                  danger: true,
                                );
                                if (!ok || !context.mounted) return;
                                if (await attempt(context, () => repo.withdrawConnection(c.str('id')), success: 'Request withdrawn.')) {
                                  await reload();
                                }
                              },
                              child: const Text('Withdraw'),
                            )
                          : status == 'REJECTED'
                              ? TextButton(
                                  onPressed: () async {
                                    if (await attempt(context, () => repo.sendConnection(c.str('tutor_id'), ''), success: 'Request sent again.')) {
                                      await reload();
                                    }
                                  },
                                  child: const Text('Ask again'),
                                )
                              : null,
                    );
                  }),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _FindTutorSheet extends StatefulWidget {
  const _FindTutorSheet({required this.existing});
  final List<Json> existing;

  @override
  State<_FindTutorSheet> createState() => _FindTutorSheetState();
}

class _FindTutorSheetState extends State<_FindTutorSheet> {
  final _message = TextEditingController();
  List<Json>? _tutors;
  String _search = '';
  Json? _picked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final search = _search;
    try {
      final tutors = await context.read<Repo>().tutors(search);
      if (mounted && search == _search) setState(() => _tutors = tutors);
    } on ApiException catch (error) {
      if (mounted) showToast(context, error.message, error: true);
    }
  }

  String? _statusWith(String tutorId) {
    for (final c in widget.existing) {
      if (c.str('tutor_id') == tutorId) return c.str('status');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: _picked != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Send a request to ${_picked!.str('name')}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  gap12,
                  TextField(
                    controller: _message,
                    maxLength: 500,
                    maxLines: 3,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Message (optional)',
                      hintText: 'e.g. Class 10, I need help with algebra.',
                    ),
                  ),
                  gap12,
                  BusyButton(
                    label: 'Send request',
                    icon: Icons.send,
                    onPressed: () async {
                      final ok = await attempt(
                        context,
                        () => repo.sendConnection(_picked!.str('id'), _message.text.trim()),
                        success: 'Request sent. Your tutor will see it.',
                      );
                      if (ok && context.mounted) Navigator.pop(context, true);
                    },
                  ),
                  TextButton(onPressed: () => setState(() => _picked = null), child: const Text('Choose a different tutor')),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Find a tutor', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  gap12,
                  TextField(
                    decoration: const InputDecoration(labelText: 'Search by name, username or subject', prefixIcon: Icon(Icons.search)),
                    onChanged: (value) {
                      _search = value.trim();
                      _load();
                    },
                  ),
                  gap12,
                  Expanded(
                    child: _tutors == null
                        ? const Center(child: CircularProgressIndicator())
                        : _tutors!.isEmpty
                            ? const Center(child: Text('No tutors match that search.', style: TextStyle(color: AppColors.muted)))
                            : ListView.separated(
                                itemCount: _tutors!.length,
                                separatorBuilder: (_, _) => const Divider(),
                                itemBuilder: (context, index) {
                                  final tutor = _tutors![index];
                                  final status = _statusWith(tutor.str('id'));
                                  final blocked = status == 'PENDING' || status == 'ACCEPTED';
                                  final subjects = tutor.strings('subjects');
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    enabled: !blocked,
                                    leading: const CircleAvatar(child: Icon(Icons.person)),
                                    title: Text(tutor.str('name')),
                                    subtitle: Text([
                                      '@${tutor.str('username')}',
                                      if (subjects.isNotEmpty) subjects.join(', '),
                                      if (status == 'PENDING') 'request sent',
                                      if (status == 'ACCEPTED') 'already connected',
                                    ].join(' · ')),
                                    trailing: blocked ? null : const Icon(Icons.chevron_right),
                                    onTap: blocked ? null : () => setState(() => _picked = tutor),
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

// ── Exams ────────────────────────────────────────────────────────────────────

class _ExamsTab extends StatelessWidget {
  const _ExamsTab({required this.exams, required this.reload});
  final List<Json> exams;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final now = context.read<Session>().api.serverNow;
    // To do = can be turned in now; Upcoming = not open yet; Done = turned in or over.
    final todo = exams.where((e) => !e.flag('has_submission') && e.flag('can_submit')).toList()
      ..sort((a, b) => (a.date('end_time') ?? now).compareTo(b.date('end_time') ?? now));
    final upcoming = exams
        .where((e) => !e.flag('has_submission') && !e.flag('can_submit') && (e.date('start_time')?.isAfter(now) ?? false))
        .toList()
      ..sort((a, b) => (a.date('start_time') ?? now).compareTo(b.date('start_time') ?? now));
    final done = exams.where((e) => !todo.contains(e) && !upcoming.contains(e)).toList();

    if (exams.isEmpty) {
      return const PageBody(children: [
        EmptyState(
          icon: Icons.assignment_outlined,
          title: 'No exams or assignments yet',
          message: 'When your tutor sets one, it appears here.',
        ),
      ]);
    }
    Widget group(String title, String subtitle, IconData icon, List<Json> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle('$title (${items.length})', subtitle: subtitle, icon: icon),
            for (final exam in items) ...[_ExamCard(exam: exam, reload: reload), gap12],
          ],
        );
    return PageBody(
      children: [
        if (todo.isNotEmpty) group('To do', 'Open now', Icons.play_circle_outline, todo),
        if (upcoming.isNotEmpty) group('Upcoming', 'Not open yet', Icons.schedule, upcoming),
        if (done.isNotEmpty) group('Done', 'Turned in or finished', Icons.check_circle_outline, done),
      ],
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam, required this.reload});
  final Json exam;
  final Future<void> Function() reload;

  Future<void> _take(BuildContext context) async {
    final repo = context.read<Repo>();
    final isAssignment = exam.str('category') == 'ASSIGNMENT';
    final minutes = exam.integer('duration_minutes');
    if (minutes > 0 && !isAssignment) {
      final ok = await confirm(
        context,
        title: 'Start the timed exam?',
        message: 'You get $minutes minutes from the moment you start, and the clock keeps running if you leave the app.',
        confirmLabel: 'Start now',
      );
      if (!ok || !context.mounted) return;
    }
    Json? started;
    await attempt(context, () async => started = await repo.startExam(exam.str('id')));
    if (started == null || !context.mounted) return;
    final response = await Navigator.push<Json>(
      context,
      MaterialPageRoute(builder: (_) => ExamTakeScreen(exam: started!.obj('exam') ?? {})),
    );
    await reload();
    if (response == null || !context.mounted) return;
    final status = response.obj('result_status') ?? {};
    if (response.flag('results_released')) {
      showToast(context, 'Submitted. Here is your result.');
      _openResult(context);
    } else if (status.str('mode') == 'SCHEDULED' && status.date('publish_at') != null) {
      showToast(context, 'Submitted. Results will be published on ${fmtDateTime(status.date('publish_at'))}.');
    } else {
      showToast(context, 'Submitted. Your tutor will publish the results.');
    }
  }

  void _openResult(BuildContext context) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ExamResultScreen(examId: exam.str('id'), title: exam.str('title'))));
  }

  @override
  Widget build(BuildContext context) {
    final now = context.read<Session>().api.serverNow;
    final isAssignment = exam.str('category') == 'ASSIGNMENT';
    final start = exam.date('start_time') ?? now;
    final end = exam.date('end_time') ?? now;
    final lateEnd = exam.date('late_submission_until');
    final done = exam.flag('has_submission');
    final upcoming = !done && now.isBefore(start);
    final open = !done && !upcoming && exam.flag('can_submit');
    final isLate = open && now.isAfter(end);
    final missed = !done && !upcoming && !open;
    final result = exam.obj('my_result');
    final released = exam.flag('results_released');
    final minutes = exam.integer('duration_minutes');
    final negative = exam.number('negative_marks_per_wrong');

    return AppCard(
      borderColor: open ? (isLate ? AppColors.warning : AppColors.success).withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill(isAssignment ? 'Assignment' : 'Exam', color: isAssignment ? AppColors.purple : AppColors.primarySoft),
              if (minutes > 0 && !isAssignment) ...[const SizedBox(width: 6), Pill('$minutes min', icon: Icons.timer_outlined)],
              const Spacer(),
              Text('${trimNumber(exam.number('total_marks'))} marks', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success)),
            ],
          ),
          gap8,
          Text(exam.str('title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (exam.str('batch_name').isNotEmpty) Text(exam.str('batch_name'), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          gap8,
          if (upcoming)
            Text('Opens ${relativeFromNow(start.difference(now))} · ${fmtDateTime(start)}', style: const TextStyle(color: AppColors.primarySoft))
          else
            Text('${isAssignment ? 'Due' : 'Ends'} ${fmtDateTime(end)}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          if (open && !isLate) Text('Closes ${relativeFromNow(end.difference(now))}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
          if (isLate)
            Text(
              lateEnd != null && lateEnd.isAfter(now)
                  ? 'Deadline passed — late work accepted ${relativeFromNow(lateEnd.difference(now)).replaceFirst('in ', 'for ')}'
                  : 'Deadline passed — hand in now',
              style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600),
            ),
          if (!isAssignment && upcoming && negative > 0)
            Text('Wrong MCQ answers lose ${trimNumber(negative)} mark(s).', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const Divider(height: 24),
          if (done) ...[
            Row(
              children: [
                const Icon(Icons.check_circle, size: 18, color: AppColors.success),
                const SizedBox(width: 6),
                Text('Turned in${result?.str('status') == 'DELAYED' ? ' (late)' : ''}'),
                const Spacer(),
                if (released && result?.numberOrNull('obtained_marks') != null)
                  Text(
                    '${trimNumber(result!.number('obtained_marks'))} / ${trimNumber(exam.number('total_marks'))}${result.flag('is_graded') ? '' : ' so far'}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.success),
                  )
                else
                  const Pill('Results pending', icon: Icons.hourglass_empty, color: AppColors.muted),
              ],
            ),
            if (!released && exam.str('result_publish_mode') == 'SCHEDULED' && exam.date('results_release_time') != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Results on ${fmtDateTime(exam.date('results_release_time'))}', style: const TextStyle(color: AppColors.faint, fontSize: 12)),
              ),
            gap12,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => _openResult(context), child: Text(released ? 'View my result' : 'View my submission')),
                ),
                if (released) ...[
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Leaderboard',
                    icon: const Icon(Icons.emoji_events_outlined, color: AppColors.warning),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => LeaderboardScreen(examId: exam.str('id'), title: exam.str('title'))),
                    ),
                  ),
                ],
              ],
            ),
          ] else if (open)
            SizedBox(
              width: double.infinity,
              child: BusyButton(
                onPressed: () => _take(context),
                color: isLate ? const Color(0xFFB45309) : const Color(0xFF059669),
                icon: Icons.arrow_forward,
                label: isLate
                    ? 'Hand in late'
                    : isAssignment
                        ? 'Open assignment'
                        : minutes > 0
                            ? 'Start exam ($minutes min)'
                            : 'Start exam',
              ),
            )
          else if (upcoming)
            Text('Questions unlock when the ${isAssignment ? 'assignment' : 'exam'} opens.', style: const TextStyle(color: AppColors.muted, fontSize: 13))
          else if (missed)
            Text(
              '${isAssignment ? 'The deadline has passed.' : 'This exam has ended.'} You did not turn it in.',
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
        ],
      ),
    );
  }
}
