import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/charts.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/cycle_progress.dart';
import '../common/payments_screen.dart';
import 'exam_editor_screen.dart';
import 'exams_view.dart';
import 'tuition_form_screen.dart';

class _TuitionData {
  _TuitionData(this.tuition, this.cycles);
  final Json tuition;
  final List<Json> cycles;
}

/// One tuition: its shared class tracker, its students, and its exams.
class TuitionScreen extends StatefulWidget {
  const TuitionScreen({super.key, required this.tuitionId});
  final String tuitionId;

  @override
  State<TuitionScreen> createState() => _TuitionScreenState();
}

class _TuitionScreenState extends State<TuitionScreen> {
  final _loader = GlobalKey<LoaderState<_TuitionData>>();
  int _examsVersion = 0;

  Future<_TuitionData> _load() async {
    final repo = context.read<Repo>();
    final results = await Future.wait<dynamic>([repo.tuition(widget.tuitionId), repo.cycles(widget.tuitionId)]);
    return _TuitionData(results[0] as Json, results[1] as List<Json>);
  }

  Future<void> _edit(Json tuition) async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => TuitionFormScreen(tuition: tuition)));
    if (changed == true) await _loader.currentState?.reload();
  }

  Future<void> _delete(Json tuition) async {
    final ok = await confirm(
      context,
      title: 'Delete "${tuition.str('title')}"?',
      message: 'The tuition, its student list and its exams (with all submissions and marks) will be deleted. '
          'What you already earned stays in your wallet history. This cannot be undone.',
      confirmLabel: 'Delete tuition',
      danger: true,
    );
    if (!ok || !mounted) return;
    final repo = context.read<Repo>();
    if (await attempt(context, () => repo.deleteTuition(widget.tuitionId), success: 'Tuition deleted.') && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Loader<_TuitionData>(
        key: _loader,
        load: _load,
        scrollable: false,
        builder: (context, data, reload) {
          final tuition = data.tuition;
          return Scaffold(
            appBar: AppBar(
              title: Text(tuition.str('title'), overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  tooltip: 'Payments',
                  icon: Badge(
                    isLabelVisible: tuition.maps('pending_payments').isNotEmpty,
                    label: Text('${tuition.maps('pending_payments').length}'),
                    child: const Icon(Icons.receipt_long_outlined),
                  ),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => PaymentsScreen(tuitionId: widget.tuitionId)),
                    );
                    await reload();
                  },
                ),
                PopupMenuButton<String>(
                  tooltip: 'Tuition options',
                  onSelected: (value) => value == 'edit' ? _edit(tuition) : _delete(tuition),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit tuition'), contentPadding: EdgeInsets.zero)),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(leading: Icon(Icons.delete_outline, color: AppColors.danger), title: Text('Delete tuition'), contentPadding: EdgeInsets.zero),
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
                ExamsView(key: ValueKey('tuition-exams-$_examsVersion'), tuitionId: widget.tuitionId),
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
                        label: Text('New exam'),
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
  final _TuitionData data;
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
                wasDone ? 'Recorded. You can correct the date or topic, or undo it.' : 'Marking it done counts it for every student in the tuition and adds it to your wallet.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
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
              // Set homework for this class — applies to the whole tuition.
              // The class itself stays independent: marking it done later does not
              // uncreate homework that was already sent to students.
              OutlinedButton.icon(
                icon: Icon(Icons.assignment_outlined, size: 18),
                label: Text('Set homework for this class'),
                onPressed: () => Navigator.pop(context, 'homework'),
              ),
              if (wasDone)
                TextButton(
                  onPressed: () => Navigator.pop(context, 'undo'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  child: Text('Undo — this class was not held'),
                ),
            ],
          ),
        ),
      ),
    );
    final topicText = topic.text.trim();
    if (action == null || !context.mounted) return;
    if (action == 'homework') {
      await _setHomeworkFromClass(context, tuition, classNo, topicText, date);
      return;
    }
    final done = action == 'done';
    Json result = const {};
    final ok = await attempt(context, () async {
      result = await repo.markClass(tuition.str('id'), classNo, done,
          date: done ? date : null, topic: done ? topicText : '', tuitionTitle: tuition.str('title'));
    });
    if (!ok || !context.mounted) return;
    final finished = result['completed_cycle_number'];
    showToast(
      context,
      result['queued'] == true
          ? 'Saved on this phone. It will be sent when you are back online.'
          : finished is num
              ? 'Cycle #$finished is complete and cycle #${finished.toInt() + 1} has started. Mark #$finished paid when you receive the money.'
              : done
                  ? 'Class $classNo marked done for the whole tuition.'
                  : 'Class $classNo unmarked.',
    );
    await reload();
  }

  Future<void> _markPaid(BuildContext context, Json pending) async {
    final repo = context.read<Repo>();
    final n = pending.integer('cycle_number');
    final ok = await confirm(
      context,
      title: 'Mark cycle #$n as paid?',
      message: 'Record that ${pending.numberOrNull('amount') == null ? 'the fee' : taka(pending.number('amount'))} was received. '
          'Students stop seeing "payment pending" for this cycle.',
      confirmLabel: 'Mark paid',
    );
    if (!ok || !context.mounted) return;
    if (await attempt(context, () => repo.setCyclePayment(pending.str('cycle_id'), true), success: 'Cycle #$n marked as paid.')) {
      await reload();
    }
  }

  Future<void> _reopen(BuildContext context, Json previous) async {
    final repo = context.read<Repo>();
    final n = previous.integer('cycle_number');
    final ok = await confirm(
      context,
      title: 'Reopen cycle #$n?',
      message: 'Use this if the last class of cycle #$n was marked by mistake. The new, still empty cycle is removed '
          'and cycle #$n becomes current again, so you can unmark that class.',
      confirmLabel: 'Reopen',
    );
    if (!ok || !context.mounted) return;
    if (await attempt(context, () => repo.reopenCycle(previous.str('id')), success: 'Cycle #$n is open again.')) {
      await reload();
    }
  }

  /// Open a homework composer pre-filled with the class topic + date.
  /// "Each student" (default) creates one row per enrolled student so each
  /// submission is reviewed and marked done individually; "whole tuition"
  /// creates a single shared task.
  Future<void> _setHomeworkFromClass(
    BuildContext context,
    Json tuition,
    int classNo,
    String topicText,
    DateTime heldOn,
  ) async {
    final repo = context.read<Repo>();
    final roster = tuition
        .maps('enrollments')
        .where((e) => e['is_active'] != false)
        .map((e) => (id: e.str('student_id'), name: e.str('student_name')))
        .where((s) => s.id.isNotEmpty)
        .toList();
    final titleCtrl = TextEditingController(
      text: topicText.isNotEmpty ? 'Class $classNo — $topicText' : 'Class $classNo homework',
    );
    final descriptionCtrl = TextEditingController();
    final initialDue = DateTime.now().add(Duration(days: 1));
    var dueDate = DateTime(initialDue.year, initialDue.month, initialDue.day, 18, 0);
    var perStudent = roster.isNotEmpty;
    final sourceLabel =
        'Class $classNo · ${heldOn.day.toString().padLeft(2, '0')}/${heldOn.month.toString().padLeft(2, '0')}';

    var titleTick = 0;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) {
          // Refresh the Send button whenever the title changes.
          void onTitleChanged() => setStateDialog(() => titleTick++);
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
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
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
                      if (picked != null && dialogContext.mounted) {
                        final time = await showTimePicker(
                          context: dialogContext,
                          initialTime: TimeOfDay.fromDateTime(dueDate),
                        );
                        setStateDialog(() {
                          dueDate = DateTime(
                            picked.year,
                            picked.month,
                            picked.day,
                            time?.hour ?? 18,
                            time?.minute ?? 0,
                          );
                        });
                      }
                    },
                  ),
                  if (roster.isNotEmpty) ...[
                    gap8,
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('One copy per student (${roster.length})',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('Each submission is marked done individually. Off = one shared task.',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      value: perStudent,
                      onChanged: (v) => setStateDialog(() => perStudent = v),
                    ),
                  ],
                  gap8,
                  Text(
                    perStudent && roster.isNotEmpty
                        ? 'Sent to ${roster.length} students separately.'
                        : 'Sent to every student in ${tuition.str('title')}.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
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
    final title = titleCtrl.text.trim();
    final description = descriptionCtrl.text.trim();
    if (saved != true || !context.mounted) return;
    var queued = 0;
    void count(Json result) {
      if (result['queued'] == true) queued++;
    }

    final ok = await attempt(context, () async {
      if (perStudent && roster.isNotEmpty) {
        for (final s in roster) {
          count(await repo.createHomework(
            title: title,
            description: description,
            dueDate: dueDate,
            studentId: s.id,
            sourceLabel: sourceLabel,
            targetName: s.name,
          ));
        }
      } else {
        count(await repo.createHomework(
          title: title,
          description: description,
          dueDate: dueDate,
          tuitionId: tuition.str('id'),
          sourceLabel: sourceLabel,
          targetName: tuition.str('title'),
        ));
      }
    });
    if (!ok || !context.mounted) return;
    showToast(
      context,
      queued > 0
          ? 'Homework saved on this phone. It will be sent when you are back online.'
          : perStudent && roster.isNotEmpty
              ? 'Homework sent to ${roster.length} students (one copy each).'
              : 'Homework sent to ${tuition.str('title')}.',
    );
    await reload();
  }

  Future<void> _startNext(BuildContext context, Json cycle) async {
    final repo = context.read<Repo>();
    final ok = await confirm(
      context,
      title: 'Start cycle #${cycle.integer('cycle_number') + 1}?',
      message: 'Cycle #${cycle.integer('cycle_number')} is complete. It will be closed with its earnings of '
          '${taka(cycle.number('earned_revenue'))} kept in your history, and a fresh cycle starts for the tuition.',
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
    final scheme = Theme.of(context).colorScheme;
    final tuition = data.tuition;
    final cycle = tuition.obj('active_cycle');
    final wallet = tuition.obj('wallet_summary') ?? {};
    final history = data.cycles.where((c) => c.str('status') == 'ARCHIVED').toList();

    if (cycle == null) {
      return PageBody(children: [
        EmptyState(icon: Icons.event_busy_outlined, title: 'No cycle yet', message: 'This tuition has no class cycle yet.'),
      ]);
    }
    final classes = orderedClasses(cycle);
    final doneClasses = classes.where((c) => c.flag('completed')).toList()
      ..sort((a, b) {
        final byDate = (b.date('date') ?? DateTime(0)).compareTo(a.date('date') ?? DateTime(0));
        return byDate != 0 ? byDate : classNoOf(b).compareTo(classNoOf(a));
      });
    final next = classes.where((c) => !c.flag('completed')).firstOrNull;
    final done = cycle.integer('completed_classes');
    final total = cycle.integer('total_classes');

    final pendingPayments = tuition.maps('pending_payments');
    final previous = history.where((c) => c.integer('cycle_number') == cycle.integer('cycle_number') - 1).firstOrNull;
    return PageBody(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        // Unpaid finished cycles: a reminder with a one-tap fix. Nothing is blocked.
        for (final p in pendingPayments) ...[
          Banner2(
            'Payment pending for cycle #${p.integer('cycle_number')}'
            '${p.numberOrNull('amount') == null ? '' : ' · ${taka(p.number('amount'))}'}',
            color: AppColors.warning,
            icon: Icons.warning_amber_rounded,
            action: TextButton(onPressed: () => _markPaid(context, p), child: const Text('Mark paid')),
          ),
          gap8,
        ],
        // The headline: how far this cycle has got.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ProgressRing(done: done, total: total, size: 104, thickness: 10, caption: 'classes done'),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cycle #${cycle.integer('cycle_number')}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                        Text('$done/$total classes done', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                          total - done <= 0 ? 'All classes taught' : '${total - done} class${total - done == 1 ? '' : 'es'} left',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              gap16,
              Row(
                children: [
                  Expanded(child: Stat(label: 'Earned', value: taka(wallet.number('earned_revenue')), color: AppColors.success)),
                  Expanded(child: Stat(label: 'Still to earn', value: taka(wallet.number('pending_balance')), color: AppColors.primarySoft)),
                  Expanded(child: Stat(label: 'Per class', value: taka(wallet.number('per_class_rate')))),
                ],
              ),
              if (next != null) ...[
                gap16,
                FilledButton.icon(
                  onPressed: () => _openClass(context, next),
                  icon: const Icon(Icons.check),
                  label: Text('Mark class ${classNoOf(next)} done'),
                ),
              ],
              if (done == 0 && previous != null)
                TextButton.icon(
                  onPressed: () => _reopen(context, previous),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: Text('Last class of cycle #${previous.integer('cycle_number')} was a mistake? Reopen it'),
                ),
            ],
          ),
        ),
        if (cycle.flag('is_complete')) ...[
          gap12,
          const Banner2(
            'All classes of this cycle are done. Start the next cycle to keep tracking classes.',
            color: AppColors.success,
            icon: Icons.celebration_outlined,
          ),
          gap8,
          BusyButton(onPressed: () => _startNext(context, cycle), label: 'Start next cycle', icon: Icons.restart_alt),
        ],

        // Every class of the cycle as a tile: done, next, or still to come.
        const SectionTitle('Classes', subtitle: 'Tap a class to mark it, change its date or topic, or set homework.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in classes)
              _ClassTile(entry: entry, isNext: identical(entry, next), onTap: () => _openClass(context, entry)),
          ],
        ),

        // The log of what was taught, newest first.
        SectionTitle('Done classes ($done/$total)', icon: Icons.task_alt),
        if (doneClasses.isEmpty)
          Text('No class marked done yet in this cycle.', style: TextStyle(color: scheme.onSurfaceVariant))
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < doneClasses.length; i++) ...[
                  if (i > 0) const Divider(indent: 64),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.chartEarned.withValues(alpha: 0.15),
                      child: Text('${classNoOf(doneClasses[i])}',
                          style: TextStyle(fontWeight: FontWeight.w800, color: tone(context, AppColors.success))),
                    ),
                    title: Text(
                      doneClasses[i].str('topic').isNotEmpty ? doneClasses[i].str('topic') : 'Class ${classNoOf(doneClasses[i])}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      [
                        if (doneClasses[i].str('topic').isNotEmpty) 'Class ${classNoOf(doneClasses[i])}',
                        fmtDate(doneClasses[i].date('date')),
                      ].join(' · '),
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    ),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                    onTap: () => _openClass(context, doneClasses[i]),
                  ),
                ],
              ],
            ),
          ),

        if (history.isNotEmpty) ...[
          SectionTitle('Past cycles', subtitle: 'Earned in past cycles: ${taka(wallet.number('archived_earnings'))}'),
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
                      '${history[i].integer('completed_classes')}/${history[i].integer('total_classes')} classes done · earned ${taka(history[i].number('earned_revenue'))}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
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

/// One class of the cycle as a square: a tick when done, highlighted when it is next.
class _ClassTile extends StatelessWidget {
  const _ClassTile({required this.entry, required this.isNext, required this.onTap});
  final Json entry;
  final bool isNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = entry.flag('completed');
    final no = classNoOf(entry);
    final Color fill = done
        ? AppColors.chartEarned.withValues(alpha: 0.16)
        : isNext
            ? AppColors.chartPending.withValues(alpha: 0.14)
            : scheme.surfaceContainerHighest;
    final Color edge = done ? AppColors.chartEarned : (isNext ? AppColors.chartPending : scheme.outline);
    return Tooltip(
      message: done ? 'Class $no · ${fmtShortDate(entry.date('date'))}' : (isNext ? 'Class $no · next' : 'Class $no · not yet'),
      child: Semantics(
        button: true,
        label: done ? 'Class $no, done on ${fmtDate(entry.date('date'))}' : 'Class $no, ${isNext ? 'next' : 'not done yet'}',
        excludeSemantics: true,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: edge, width: isNext ? 2 : 1)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$no', style: TextStyle(fontWeight: FontWeight.w800, color: done || isNext ? scheme.onSurface : scheme.onSurfaceVariant)),
                  if (done)
                    Icon(Icons.check, size: 14, color: tone(context, AppColors.success))
                  else if (isNext)
                    Text('next', style: TextStyle(fontSize: 10, color: tone(context, AppColors.primarySoft))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Students of the tuition ───────────────────────────────────────────────────

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
        FilledButton.icon(onPressed: () => _add(context), icon: Icon(Icons.person_add_alt_1), label: Text('Add students to this tuition')),
        gap16,
        if (students.isEmpty)
          EmptyState(
            icon: Icons.person_outline,
            title: 'No students in this tuition yet',
            message: 'Add students you created, or ones who asked to join you.',
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < students.length; i++) ...[
                  if (i > 0) Divider(),
                  ListTile(
                    leading: CircleAvatar(child: Text(students[i].str('student_name', '?').characters.first.toUpperCase())),
                    title: Text(students[i].str('student_name')),
                    subtitle: Text(
                      [
                        '@${students[i].str('username')}',
                        if (students[i].str('grade_level').isNotEmpty) students[i].str('grade_level'),
                        if (students[i].str('phone').isNotEmpty) students[i].str('phone'),
                      ].join(' · '),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove ${students[i].str('student_name')} from the tuition',
                      icon: Icon(Icons.person_remove_outlined),
                      onPressed: () async {
                        final student = students[i];
                        final ok = await confirm(
                          context,
                          title: 'Remove ${student.str('student_name')}?',
                          message: 'They leave "${tuition.str('title')}" and stop seeing its classes and exams. '
                              'Their account stays, and the tuition\'s cycle and earnings are not changed.',
                          confirmLabel: 'Remove',
                          danger: true,
                        );
                        if (!ok || !context.mounted) return;
                        if (await attempt(context, () => repo.unenroll(tuition.str('id'), student.str('student_id')), success: 'Removed from the tuition.')) {
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
                      ? Center(
                          child: Text(
                            'All your active students are already in this tuition.\nCreate a student from the Students tab first.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                      final ok = await attempt(context, () => repo.enroll(widget.tuition.str('id'), _picked.toList()), success: 'Added to the tuition.');
                      if (ok && context.mounted) Navigator.pop(context, true);
                    },
            ),
          ],
        ),
      ),
    );
  }
}
