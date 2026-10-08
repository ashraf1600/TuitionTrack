import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/cycle_progress.dart';
import 'exam_editor_screen.dart';
import 'exams_view.dart';
import 'group_form_screen.dart';

class _GroupData {
  _GroupData(this.tuition, this.cycles);
  final Json tuition;
  final List<Json> cycles;
}

/// One tuition group: its shared class tracker, its students, and its exams.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.tuitionId});
  final String tuitionId;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final _loader = GlobalKey<LoaderState<_GroupData>>();
  int _examsVersion = 0;

  Future<_GroupData> _load() async {
    final repo = context.read<Repo>();
    final results = await Future.wait<dynamic>([repo.tuition(widget.tuitionId), repo.cycles(widget.tuitionId)]);
    return _GroupData(results[0] as Json, results[1] as List<Json>);
  }

  Future<void> _edit(Json tuition) async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => GroupFormScreen(tuition: tuition)));
    if (changed == true) await _loader.currentState?.reload();
  }

  Future<void> _delete(Json tuition) async {
    final ok = await confirm(
      context,
      title: 'Delete "${tuition.str('title')}"?',
      message: 'The group, its student list and its exams (with all submissions and marks) will be deleted. '
          'What you already earned stays in your wallet history. This cannot be undone.',
      confirmLabel: 'Delete group',
      danger: true,
    );
    if (!ok || !mounted) return;
    final repo = context.read<Repo>();
    if (await attempt(context, () => repo.deleteTuition(widget.tuitionId), success: 'Group deleted.') && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Loader<_GroupData>(
        key: _loader,
        load: _load,
        scrollable: false,
        builder: (context, data, reload) {
          final tuition = data.tuition;
          return Scaffold(
            appBar: AppBar(
              title: Text(tuition.str('title'), overflow: TextOverflow.ellipsis),
              actions: [
                PopupMenuButton<String>(
                  tooltip: 'Group options',
                  onSelected: (value) => value == 'edit' ? _edit(tuition) : _delete(tuition),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit group'), contentPadding: EdgeInsets.zero)),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(leading: Icon(Icons.delete_outline, color: AppColors.danger), title: Text('Delete group'), contentPadding: EdgeInsets.zero),
                    ),
                  ],
                ),
              ],
              bottom: TabBar(tabs: [
                const Tab(text: 'Classes'),
                Tab(text: 'Students (${tuition.maps('enrollments').length})'),
                const Tab(text: 'Exams'),
              ]),
            ),
            body: TabBarView(
              children: [
                RefreshIndicator(onRefresh: reload, child: _ClassesTab(data: data, reload: reload)),
                RefreshIndicator(onRefresh: reload, child: _StudentsTab(tuition: tuition, reload: reload)),
                ExamsView(key: ValueKey('group-exams-$_examsVersion'), tuitionId: widget.tuitionId),
              ],
            ),
            floatingActionButton: Builder(builder: (context) {
              final controller = DefaultTabController.of(context);
              return AnimatedBuilder(
                animation: controller,
                builder: (context, _) => controller.index != 2
                    ? const SizedBox.shrink()
                    : FloatingActionButton.extended(
                        onPressed: () async {
                          final changed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(builder: (_) => ExamEditorScreen(initialTuitionId: widget.tuitionId)),
                          );
                          if (changed == true && mounted) setState(() => _examsVersion++);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('New exam'),
                      ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ── Classes: the shared cycle ────────────────────────────────────────────────

class _ClassesTab extends StatelessWidget {
  const _ClassesTab({required this.data, required this.reload});
  final _GroupData data;
  final Future<void> Function() reload;

  Future<void> _openClass(BuildContext context, Json entry) async {
    final tuition = data.tuition;
    final repo = context.read<Repo>();
    final classNo = classNoOf(entry);
    final wasDone = entry.flag('completed');
    final topic = TextEditingController(text: entry.str('topic'));
    var date = entry.date('date') ?? DateTime.now();

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Class $classNo', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(
                wasDone ? 'Recorded. You can correct the date or topic, or undo it.' : 'Marking it done counts it for every student in the group and adds it to your wallet.',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              gap16,
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text('Held on ${fmtDate(date)}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime.now().subtract(const Duration(days: 366)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setSheet(() => date = DateTime(picked.year, picked.month, picked.day, 12));
                },
              ),
              gap12,
              TextField(
                controller: topic,
                maxLength: 255,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Topic covered (optional)', hintText: 'e.g. Quadratic equations'),
              ),
              gap8,
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, 'done'),
                icon: const Icon(Icons.check),
                label: Text(wasDone ? 'Save changes' : 'Mark as done'),
              ),
              // Set homework for this class — applies to the whole tuition group.
              // The class itself stays independent: marking it done later does not
              // uncreate homework that was already sent to students.
              OutlinedButton.icon(
                icon: const Icon(Icons.assignment_outlined, size: 18),
                label: const Text('Set homework for this class'),
                onPressed: () => Navigator.pop(context, 'homework'),
              ),
              if (wasDone)
                TextButton(
                  onPressed: () => Navigator.pop(context, 'undo'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  child: const Text('Undo — this class was not held'),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'homework') {
      await _setHomeworkFromClass(context, tuition, classNo, topic.text.trim(), date);
      return;
    }
    final done = action == 'done';
    final ok = await attempt(
      context,
      () => repo.markClass(tuition.str('id'), classNo, done, date: done ? date : null, topic: done ? topic.text.trim() : ''),
      success: done ? 'Class $classNo recorded for the whole group.' : 'Class $classNo unmarked.',
    );
    if (ok) await reload();
  }

  /// Open a homework composer pre-filled with the class topic + date so the tutor
  /// can drop in the homework details and send it to the entire tuition group.
  Future<void> _setHomeworkFromClass(
    BuildContext context,
    Json tuition,
    int classNo,
    String topicText,
    DateTime heldOn,
  ) async {
    final repo = context.read<Repo>();
    final titleCtrl = TextEditingController(
      text: topicText.isNotEmpty ? 'Practice on $topicText' : 'Class $classNo follow-up',
    );
    final descriptionCtrl = TextEditingController();
    final initialDue = DateTime.now().add(const Duration(days: 3));
    var dueDate = DateTime(initialDue.year, initialDue.month, initialDue.day, 23, 59);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) {
          // Refresh the Send button whenever the title changes.
          void onTitleChanged() => setStateDialog(() {});
          return AlertDialog(
            title: Text('Homework — class $classNo'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (topicText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Topic: $topicText',
                        style: const TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ),
                  TextField(
                    controller: titleCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => onTitleChanged(),
                    decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Solve exercises 4.1–4.3'),
                  ),
                  gap12,
                  TextField(
                    controller: descriptionCtrl,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Details (optional)',
                      hintText: 'Pages, problems, instructions…',
                    ),
                  ),
                  gap12,
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text('Due ${fmtDate(dueDate)}'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: dueDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setStateDialog(() {
                          dueDate = DateTime(picked.year, picked.month, picked.day, 23, 59);
                        });
                      }
                    },
                  ),
                  gap8,
                  Text(
                    'Sent to every student in ${tuition.str('title')}.',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: titleCtrl.text.trim().isEmpty ? null : () => Navigator.pop(dialogContext, true),
                child: const Text('Send'),
              ),
            ],
          );
        },
      ),
    );
    if (saved != true || !context.mounted) return;
    await attempt(
      context,
      () => repo.createHomework(
        title: titleCtrl.text.trim(),
        description: descriptionCtrl.text.trim(),
        dueDate: dueDate,
        tuitionId: tuition.str('id'),
      ),
      success: 'Homework sent to ${tuition.str('title')}.',
    );
    // The class-attendance sheet is already closed; no reload needed here.
  }

  Future<void> _startNext(BuildContext context, Json cycle) async {
    final repo = context.read<Repo>();
    final ok = await confirm(
      context,
      title: 'Start cycle #${cycle.integer('cycle_number') + 1}?',
      message: 'Cycle #${cycle.integer('cycle_number')} is complete. It will be closed with its earnings of '
          '${taka(cycle.number('earned_revenue'))} kept in your history, and a fresh cycle starts for the group.',
      confirmLabel: 'Start next cycle',
    );
    if (!ok || !context.mounted) return;
    try {
      await repo.resetCycle(cycle.str('id'));
      if (context.mounted) showToast(context, 'New cycle started.');
      await reload();
    } on ApiException catch (error) {
      if (!context.mounted) return;
      // The most common failure mode is the backend refusing because the
      // current cycle still has un-recorded classes. Translate that into a
      // pointer for the tutor; otherwise fall back to the standard toast.
      final hint = (error.status == 400 || error.status == 403) &&
              (error.message.toLowerCase().contains('completion') ||
                  error.message.toLowerCase().contains('cycle'));
      showToast(
        context,
        hint ? 'Finish the classes of this cycle before starting the next one.' : error.message,
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tuition = data.tuition;
    final cycle = tuition.obj('active_cycle');
    final wallet = tuition.obj('wallet_summary') ?? {};
    final history = data.cycles.where((c) => c.str('status') == 'ARCHIVED').toList();

    return PageBody(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        AppCard(
          child: Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              Stat(label: 'Earned this cycle', value: taka(wallet.number('earned_revenue')), color: AppColors.success),
              Stat(label: 'Still to earn', value: taka(wallet.number('pending_balance')), color: AppColors.primarySoft),
              Stat(label: 'Per class', value: taka(wallet.number('per_class_rate'))),
              Stat(label: 'Past cycles', value: taka(wallet.number('archived_earnings'))),
            ],
          ),
        ),
        if (cycle == null)
          const Padding(padding: EdgeInsets.only(top: 16), child: Text('This group has no cycle yet.', style: TextStyle(color: AppColors.muted)))
        else ...[
          SectionTitle(
            'Cycle #${cycle.integer('cycle_number')}',
            subtitle: '${cycle.integer('completed_classes')} of ${cycle.integer('total_classes')} classes done. Tap a class to record it.',
          ),
          if (cycle.flag('is_complete')) ...[
            Banner2(
              'All classes of this cycle are done. Start the next cycle when you are ready.',
              color: AppColors.success,
              icon: Icons.celebration_outlined,
            ),
            gap8,
            BusyButton(onPressed: () => _startNext(context, cycle), label: 'Start next cycle', icon: Icons.restart_alt),
            gap12,
          ],
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final entry in orderedClasses(cycle)) ...[
                  if (classNoOf(entry) > 1) const Divider(),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: entry.flag('completed') ? AppColors.success.withValues(alpha: 0.2) : AppColors.card,
                      child: entry.flag('completed')
                          ? const Icon(Icons.check, color: AppColors.success)
                          : Text('${classNoOf(entry)}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
                    ),
                    title: Text('Class ${classNoOf(entry)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      entry.flag('completed')
                          ? [fmtDate(entry.date('date')), if (entry.str('topic').isNotEmpty) entry.str('topic')].join(' · ')
                          : 'Not done yet',
                      style: TextStyle(color: entry.flag('completed') ? AppColors.text : AppColors.faint),
                    ),
                    trailing: Icon(entry.flag('completed') ? Icons.edit_outlined : Icons.radio_button_unchecked, size: 20),
                    onTap: () => _openClass(context, entry),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (history.isNotEmpty) ...[
          const SectionTitle('Past cycles'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < history.length; i++) ...[
                  if (i > 0) const Divider(),
                  ExpansionTile(
                    shape: const Border(),
                    title: Text('Cycle #${history[i].integer('cycle_number')}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${history[i].integer('completed_classes')}/${history[i].integer('total_classes')} classes · earned ${taka(history[i].number('earned_revenue'))}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in orderedClasses(history[i]).where((c) => c.flag('completed')))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Class ${classNoOf(entry)} · ${fmtDate(entry.date('date'))}${entry.str('topic').isNotEmpty ? ' · ${entry.str('topic')}' : ''}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── Students of the group ────────────────────────────────────────────────────

class _StudentsTab extends StatelessWidget {
  const _StudentsTab({required this.tuition, required this.reload});
  final Json tuition;
  final Future<void> Function() reload;

  Future<void> _add(BuildContext context) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddStudentsSheet(tuition: tuition),
    );
    if (added == true) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    final students = tuition.maps('enrollments');
    return PageBody(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        FilledButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.person_add_alt_1), label: const Text('Add students to this group')),
        gap16,
        if (students.isEmpty)
          const EmptyState(
            icon: Icons.person_outline,
            title: 'No students in this group yet',
            message: 'Add students you created, or ones who asked to join you.',
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < students.length; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    leading: CircleAvatar(child: Text(students[i].str('student_name', '?').characters.first.toUpperCase())),
                    title: Text(students[i].str('student_name')),
                    subtitle: Text(
                      [
                        '@${students[i].str('username')}',
                        if (students[i].str('grade_level').isNotEmpty) students[i].str('grade_level'),
                        if (students[i].str('phone').isNotEmpty) students[i].str('phone'),
                      ].join(' · '),
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove ${students[i].str('student_name')} from the group',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () async {
                        final student = students[i];
                        final ok = await confirm(
                          context,
                          title: 'Remove ${student.str('student_name')}?',
                          message: 'They leave "${tuition.str('title')}" and stop seeing its classes and exams. '
                              'Their account stays, and the group\'s cycle and earnings are not changed.',
                          confirmLabel: 'Remove',
                          danger: true,
                        );
                        if (!ok || !context.mounted) return;
                        if (await attempt(context, () => repo.unenroll(tuition.str('id'), student.str('student_id')), success: 'Removed from the group.')) {
                          await reload();
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _AddStudentsSheet extends StatefulWidget {
  const _AddStudentsSheet({required this.tuition});
  final Json tuition;

  @override
  State<_AddStudentsSheet> createState() => _AddStudentsSheetState();
}

class _AddStudentsSheetState extends State<_AddStudentsSheet> {
  List<Json>? _candidates;
  final _picked = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<Repo>();
    final enrolled = widget.tuition.maps('enrollments').map((e) => e.str('student_id')).toSet();
    await attempt(context, () async {
      final all = await repo.students();
      if (mounted) setState(() => _candidates = all.where((s) => s.flag('is_active') && !enrolled.contains(s.str('id'))).toList());
    });
    if (mounted && _candidates == null) setState(() => _candidates = []);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add students to ${widget.tuition.str('title')}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            gap12,
            Expanded(
              child: _candidates == null
                  ? const Center(child: CircularProgressIndicator())
                  : _candidates!.isEmpty
                      ? const Center(
                          child: Text(
                            'All your active students are already in this group.\nCreate a student from the Students tab first.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.muted),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final s in _candidates!)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _picked.contains(s.str('id')),
                                onChanged: (value) => setState(() => value == true ? _picked.add(s.str('id')) : _picked.remove(s.str('id'))),
                                title: Text(s.str('full_name')),
                                subtitle: Text(
                                  ['@${s.str('username')}', if ((s.obj('profile') ?? {}).str('grade_level').isNotEmpty) (s.obj('profile') ?? {}).str('grade_level')].join(' · '),
                                ),
                              ),
                          ],
                        ),
            ),
            BusyButton(
              label: _picked.isEmpty ? 'Choose students' : 'Add ${_picked.length} student${_picked.length == 1 ? '' : 's'}',
              onPressed: _picked.isEmpty
                  ? null
                  : () async {
                      final ok = await attempt(context, () => repo.enroll(widget.tuition.str('id'), _picked.toList()), success: 'Added to the group.');
                      if (ok && context.mounted) Navigator.pop(context, true);
                    },
            ),
          ],
        ),
      ),
    );
  }
}
