import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/charts.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../common/cycle_progress.dart';
import '../common/notification_actions.dart';
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
      title: tr('Delete "{p0}"?', {'p0': tuition.str('title')}),
      message: tr('The tuition, its student list and its exams (with all submissions and marks) will be deleted. What you already earned stays in your wallet history. This cannot be undone.'),
      confirmLabel: tr('Delete tuition'),
      danger: true,
    );
    if (!ok || !mounted) return;
    final repo = context.read<Repo>();
    if (await attempt(context, () => repo.deleteTuition(widget.tuitionId), success: tr('Tuition deleted.')) && mounted) {
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
                  tooltip: tr('Payments'),
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
                  tooltip: tr('Tuition options'),
                  onSelected: (value) => value == 'edit' ? _edit(tuition) : _delete(tuition),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text(tr('Edit tuition')), contentPadding: EdgeInsets.zero)),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(leading: Icon(Icons.delete_outline, color: AppColors.danger), title: Text(tr('Delete tuition')), contentPadding: EdgeInsets.zero),
                    ),
                  ],
                ),
              ],
              bottom: TabBar(tabs: [
                Tab(text: tr('Classes')),
                Tab(text: tr('Students ({p0})', {'p0': tuition.maps('enrollments').length})),
                Tab(text: tr('Exams')),
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
                        label: Text(tr('New exam')),
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
              Text(tr('Class {p0}', {'p0': classNo}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(
                wasDone ? tr('Recorded. You can correct the date or topic, or undo it.') : tr('Marking it done counts it for every student in the tuition and adds it to your wallet.'),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              gap16,
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(tr('Held on {p0}', {'p0': fmtDate(date)})),
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
                decoration: InputDecoration(labelText: tr('Topic covered (optional)'), hintText: tr('e.g. Quadratic equations')),
              ),
              gap8,
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, 'done'),
                icon: const Icon(Icons.check),
                label: Text(wasDone ? tr('Save changes') : tr('Mark as done')),
              ),
              // Set homework for this class — applies to the whole tuition.
              // The class itself stays independent: marking it done later does not
              // uncreate homework that was already sent to students.
              OutlinedButton.icon(
                icon: Icon(Icons.assignment_outlined, size: 18),
                label: Text(tr('Set homework for this class')),
                onPressed: () => Navigator.pop(context, 'homework'),
              ),
              if (wasDone)
                TextButton(
                  onPressed: () => Navigator.pop(context, 'undo'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  child: Text(tr('Undo — this class was not held')),
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
    final messenger = ScaffoldMessenger.maybeOf(context);
    final oldDate = entry.date('date');
    final oldTopic = entry.str('topic');
    showToast(
      context,
      !done
          ? tr('Class {n} unmarked.', {'n': classNo})
          : wasDone
              ? tr('Class {n} updated.', {'n': classNo})
              : classMarkedMessage(result, classNo, tuition.str('title')),
      actionLabel: tr('Undo'),
      onAction: () async {
        try {
          if (done && !wasDone) {
            // Newly marked: unmark it (reopening the cycle if it had just rolled over).
            await repo.undoMarkClass(tuition.str('id'), classNo, true, result);
          } else {
            // Unmarked or edited: put back the date and topic it had.
            await repo.markClass(tuition.str('id'), classNo, true, date: oldDate, topic: oldTopic);
          }
          showToastOn(messenger, tr('Undone.'));
        } on ApiException catch (error) {
          showToastOn(messenger, error.message, error: true);
        }
        await reload();
      },
    );
    await reload();
  }

  /// Records the payment at once, with Undo (no "are you sure" step).
  /// One tap: marks the next class done today, with Undo (the tile opens the full editor).
  Future<void> _quickMark(BuildContext context, Json entry) async {
    final tuition = data.tuition;
    final repo = context.read<Repo>();
    final classNo = classNoOf(entry);
    Json result = const {};
    final ok = await attempt(context, () async {
      result = await repo.markClass(tuition.str('id'), classNo, true, tuitionTitle: tuition.str('title'));
    });
    if (!ok || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    showToast(
      context,
      classMarkedMessage(result, classNo, tuition.str('title')),
      actionLabel: tr('Undo'),
      onAction: () async {
        try {
          await repo.undoMarkClass(tuition.str('id'), classNo, true, result);
          showToastOn(messenger, tr('Class {n} unmarked.', {'n': classNo}));
        } on ApiException catch (error) {
          showToastOn(messenger, error.message, error: true);
        }
        await reload();
      },
    );
    await reload();
  }

  Future<void> _markPaid(BuildContext context, Json pending) async {
    final repo = context.read<Repo>();
    final n = pending.integer('cycle_number');
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await attempt(context, () => repo.setCyclePayment(pending.str('cycle_id'), true));
    if (!ok || !context.mounted) return;
    showToast(
      context,
      tr('Cycle #{n} marked as paid.', {'n': n}),
      actionLabel: tr('Undo'),
      onAction: () async {
        try {
          await repo.setCyclePayment(pending.str('cycle_id'), false);
        } on ApiException catch (error) {
          showToastOn(messenger, error.message, error: true);
        }
        await reload();
      },
    );
    await reload();
  }

  Future<void> _reopen(BuildContext context, Json previous) async {
    final repo = context.read<Repo>();
    final n = previous.integer('cycle_number');
    final ok = await confirm(
      context,
      title: tr('Reopen cycle #{p0}?', {'p0': n}),
      message: tr('Use this if the last class of cycle #{p0} was marked by mistake. The new, still empty cycle is removed and cycle #{p1} becomes current again, so you can unmark that class.', {'p0': n, 'p1': n}),
      confirmLabel: tr('Reopen'),
    );
    if (!ok || !context.mounted) return;
    if (await attempt(context, () => repo.reopenCycle(previous.str('id')), success: tr('Cycle #{p0} is open again.', {'p0': n}))) {
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
      text: topicText.isNotEmpty ? tr('Class {p0} — {p1}', {'p0': classNo, 'p1': topicText}) : tr('Class {p0} homework', {'p0': classNo}),
    );
    final descriptionCtrl = TextEditingController();
    final initialDue = DateTime.now().add(Duration(days: 1));
    var dueDate = DateTime(initialDue.year, initialDue.month, initialDue.day, 18, 0);
    var perStudent = roster.isNotEmpty;
    final sourceLabel =
        tr('Class {p0} · {p1}/{p2}', {'p0': classNo, 'p1': heldOn.day.toString().padLeft(2, '0'), 'p2': heldOn.month.toString().padLeft(2, '0')});

    var titleTick = 0;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) {
          // Refresh the Send button whenever the title changes.
          void onTitleChanged() => setStateDialog(() => titleTick++);
          return AlertDialog(
            title: Text(tr('Homework — class {p0}', {'p0': classNo})),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (topicText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        tr('Topic: {p0}', {'p0': topicText}),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                  TextField(
                    controller: titleCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => onTitleChanged(),
                    decoration: InputDecoration(labelText: tr('Title'), hintText: tr('e.g. Solve exercises 4.1–4.3')),
                  ),
                  gap12,
                  TextField(
                    controller: descriptionCtrl,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: tr('Details (optional)'),
                      hintText: tr('Pages, problems, instructions…'),
                    ),
                  ),
                  gap12,
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(tr('Due {p0}', {'p0': fmtDate(dueDate)})),
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
                      title: Text(tr('One copy per student ({p0})', {'p0': roster.length}),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(tr('Each submission is marked done individually. Off = one shared task.'),
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      value: perStudent,
                      onChanged: (v) => setStateDialog(() => perStudent = v),
                    ),
                  ],
                  gap8,
                  Text(
                    perStudent && roster.isNotEmpty
                        ? tr('Sent to {p0} students separately.', {'p0': roster.length})
                        : tr('Sent to every student in {p0}.', {'p0': tuition.str('title')}),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('Cancel'))),
              FilledButton(
                onPressed: titleCtrl.text.trim().isEmpty ? null : () => Navigator.pop(dialogContext, true),
                child: Text(tr('Send')),
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
          ? tr('Homework saved on this phone. It will be sent when you are back online.')
          : perStudent && roster.isNotEmpty
              ? tr('Homework sent to {p0} students (one copy each).', {'p0': roster.length})
              : tr('Homework sent to {p0}.', {'p0': tuition.str('title')}),
    );
    await reload();
  }

  Future<void> _startNext(BuildContext context, Json cycle) async {
    final repo = context.read<Repo>();
    final ok = await confirm(
      context,
      title: tr('Start cycle #{p0}?', {'p0': cycle.integer('cycle_number') + 1}),
      message: tr('Cycle #{p0} is complete. It will be closed with its earnings of {p1} kept in your history, and a fresh cycle starts for the tuition.', {'p0': cycle.integer('cycle_number'), 'p1': taka(cycle.number('earned_revenue'))}),
      confirmLabel: tr('Start next cycle'),
    );
    if (!ok || !context.mounted) return;
    try {
      await repo.resetCycle(cycle.str('id'));
      if (context.mounted) showToast(context, tr('New cycle started.'));
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
        hint ? tr('Finish the classes of this cycle before starting the next one.') : error.message,
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
        EmptyState(icon: Icons.event_busy_outlined, title: tr('No cycle yet'), message: tr('This tuition has no class cycle yet.')),
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
            tr('Payment pending for cycle #{p0}{p1}', {'p0': p.integer('cycle_number'), 'p1': p.numberOrNull('amount') == null ? '' : ' · ${taka(p.number('amount'))}'}),
            color: AppColors.warning,
            icon: Icons.warning_amber_rounded,
            action: TextButton(onPressed: () => _markPaid(context, p), child: Text(tr('Mark paid'))),
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
                  ProgressRing(done: done, total: total, size: 104, thickness: 10, caption: tr('classes done')),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Cycle #{p0}', {'p0': cycle.integer('cycle_number')}), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                        Text(tr('{p0}/{p1} classes done', {'p0': done, 'p1': total}), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                          total - done <= 0 ? tr('All classes taught') : tr('{p0} class{p1} left', {'p0': total - done, 'p1': total - done == 1 ? '' : 'es'}),
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
                  Expanded(child: Stat(label: tr('Earned'), value: taka(wallet.number('earned_revenue')), color: AppColors.success)),
                  Expanded(child: Stat(label: tr('Still to earn'), value: taka(wallet.number('pending_balance')), color: AppColors.primarySoft)),
                  Expanded(child: Stat(label: tr('Per class'), value: taka(wallet.number('per_class_rate')))),
                ],
              ),
              if (next != null) ...[
                gap16,
                FilledButton.icon(
                  onPressed: () => _quickMark(context, next),
                  icon: const Icon(Icons.check),
                  label: Text(tr('Mark class {p0} done', {'p0': classNoOf(next)})),
                ),
              ],
              if (done == 0 && previous != null)
                TextButton.icon(
                  onPressed: () => _reopen(context, previous),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: Text(tr('Last class of cycle #{p0} was a mistake? Reopen it', {'p0': previous.integer('cycle_number')})),
                ),
            ],
          ),
        ),
        if (cycle.flag('is_complete')) ...[
          gap12,
          Banner2(
            tr('All classes of this cycle are done. Start the next cycle to keep tracking classes.'),
            color: AppColors.success,
            icon: Icons.celebration_outlined,
          ),
          gap8,
          BusyButton(onPressed: () => _startNext(context, cycle), label: tr('Start next cycle'), icon: Icons.restart_alt),
        ],

        // Every class of the cycle as a tile: done, next, or still to come.
        SectionTitle(tr('Classes'), subtitle: tr('Tap a class to mark it, change its date or topic, or set homework.')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in classes)
              _ClassTile(entry: entry, isNext: identical(entry, next), onTap: () => _openClass(context, entry)),
          ],
        ),

        // The log of what was taught, newest first.
        SectionTitle(tr('Done classes ({p0}/{p1})', {'p0': done, 'p1': total}), icon: Icons.task_alt),
        if (doneClasses.isEmpty)
          Text(tr('No class marked done yet in this cycle.'), style: TextStyle(color: scheme.onSurfaceVariant))
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
                      doneClasses[i].str('topic').isNotEmpty ? doneClasses[i].str('topic') : tr('Class {p0}', {'p0': classNoOf(doneClasses[i])}),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      [
                        if (doneClasses[i].str('topic').isNotEmpty) tr('Class {p0}', {'p0': classNoOf(doneClasses[i])}),
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
          SectionTitle(tr('Past cycles'), subtitle: tr('Earned in past cycles: {p0}', {'p0': taka(wallet.number('archived_earnings'))})),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < history.length; i++) ...[
                  if (i > 0) const Divider(),
                  ExpansionTile(
                    shape: const Border(),
                    title: Text(tr('Cycle #{p0}', {'p0': history[i].integer('cycle_number')}), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      tr('{p0}/{p1} classes done · earned {p2}', {'p0': history[i].integer('completed_classes'), 'p1': history[i].integer('total_classes'), 'p2': taka(history[i].number('earned_revenue'))}),
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in orderedClasses(history[i]).where((c) => c.flag('completed')))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            tr('Class {p0} · {p1}{p2}', {'p0': classNoOf(entry), 'p1': fmtDate(entry.date('date')), 'p2': entry.str('topic').isNotEmpty ? ' · ${entry.str('topic')}' : ''}),
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
      message: done ? tr('Class {p0} · {p1}', {'p0': no, 'p1': fmtShortDate(entry.date('date'))}) : (isNext ? tr('Class {p0} · next', {'p0': no}) : tr('Class {p0} · not yet', {'p0': no})),
      child: Semantics(
        button: true,
        label: done ? tr('Class {p0}, done on {p1}', {'p0': no, 'p1': fmtDate(entry.date('date'))}) : tr('Class {p0}, {p1}', {'p0': no, 'p1': isNext ? tr('next') : tr('not done yet')}),
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
                    Text(tr('next'), style: TextStyle(fontSize: 10, color: tone(context, AppColors.primarySoft))),
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
        FilledButton.icon(onPressed: () => _add(context), icon: Icon(Icons.person_add_alt_1), label: Text(tr('Add students to this tuition'))),
        gap16,
        if (students.isEmpty)
          EmptyState(
            icon: Icons.person_outline,
            title: tr('No students in this tuition yet'),
            message: tr('Add students you created, or ones who asked to join you.'),
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
                      tooltip: tr('Remove {p0} from the tuition', {'p0': students[i].str('student_name')}),
                      icon: Icon(Icons.person_remove_outlined),
                      onPressed: () async {
                        final student = students[i];
                        final ok = await confirm(
                          context,
                          title: tr('Remove {p0}?', {'p0': student.str('student_name')}),
                          message: tr('They leave "{p0}" and stop seeing its classes and exams. Their account stays, and the tuition\'s cycle and earnings are not changed.', {'p0': tuition.str('title')}),
                          confirmLabel: tr('Remove'),
                          danger: true,
                        );
                        if (!ok || !context.mounted) return;
                        if (await attempt(context, () => repo.unenroll(tuition.str('id'), student.str('student_id')), success: tr('Removed from the tuition.'))) {
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
            Text(tr('Add students to {p0}', {'p0': widget.tuition.str('title')}), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            gap12,
            Expanded(
              child: _candidates == null
                  ? const Center(child: CircularProgressIndicator())
                  : _candidates!.isEmpty
                      ? Center(
                          child: Text(
                            tr('All your active students are already in this tuition.\nCreate a student from the Students tab first.'),
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
              label: _picked.isEmpty ? tr('Choose students') : tr('Add {p0} student{p1}', {'p0': _picked.length, 'p1': _picked.length == 1 ? '' : 's'}),
              onPressed: _picked.isEmpty
                  ? null
                  : () async {
                      final ok = await attempt(context, () => repo.enroll(widget.tuition.str('id'), _picked.toList()), success: tr('Added to the tuition.'));
                      if (ok && context.mounted) Navigator.pop(context, true);
                    },
            ),
          ],
        ),
      ),
    );
  }
}
