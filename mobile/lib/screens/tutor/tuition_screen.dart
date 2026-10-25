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
import 'homework_tab.dart';
import 'tuition_form_screen.dart';

class _TuitionData {
  _TuitionData(this.tuition, this.cycles, this.homework);
  final Json tuition;
  final List<Json> cycles;

  /// This tuition's homework (shared tasks and its students' copies), to show
  /// under the class done on the day it was given.
  final List<Json> homework;
}

/// One tuition: classes (pies, mark the next class, what was taught and the
/// homework given each day), its students, its homework and its exams.
class TuitionScreen extends StatefulWidget {
  const TuitionScreen({super.key, required this.tuitionId});
  final String tuitionId;

  @override
  State<TuitionScreen> createState() => _TuitionScreenState();
}

class _TuitionScreenState extends State<TuitionScreen> {
  final _loader = GlobalKey<LoaderState<_TuitionData>>();
  int _examsVersion = 0;
  int _homeworkVersion = 0;

  Future<void> _newExam() async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ExamEditorScreen(initialTuitionId: widget.tuitionId)));
    if (changed == true && mounted) setState(() => _examsVersion++);
  }

  Future<void> _newHomework() async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => HomeworkCreateScreen(initialTuitionId: widget.tuitionId)));
    if (changed == true && mounted) {
      setState(() => _homeworkVersion++);
      await _loader.currentState?.reload(quiet: true);
    }
  }

  Future<_TuitionData> _load() async {
    final repo = context.read<Repo>();
    final results = await Future.wait<dynamic>([
      repo.tuition(widget.tuitionId),
      repo.cycles(widget.tuitionId),
      repo.homework().catchError((_) => <Json>[]),
    ]);
    final tuition = results[0] as Json;
    final members = {for (final e in tuition.maps('enrollments')) e.str('student_id')};
    final homework = (results[2] as List<Json>)
        .where((h) => h.str('tuition_id') == widget.tuitionId || (h.str('tuition_id').isEmpty && members.contains(h.str('student_id'))))
        .toList();
    return _TuitionData(tuition, results[1] as List<Json>, homework);
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
      length: 4,
      child: Loader<_TuitionData>(
        key: _loader,
        load: _load,
        scrollable: false,
        builder: (context, data, reload) {
          final tuition = data.tuition;
          final students = tuition.maps('enrollments').length;
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: tuitionColorOf(widget.tuitionId), shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tuition.str('title'), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          [
                            if (tuition.str('subject').isNotEmpty) tuition.str('subject'),
                            tr('{p0} student{p1}', {'p0': students, 'p1': students == 1 ? '' : 's'}),
                            if (tuition.obj('active_cycle') != null) tr('Cycle {n}', {'n': tuition.obj('active_cycle')!.integer('cycle_number', 1)}),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: context.tt.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: tr('Classes')),
                  Tab(text: tr('Students ({p0})', {'p0': students})),
                  Tab(text: tr('Homework')),
                  Tab(text: tr('Exams')),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                RefreshIndicator(
                  onRefresh: reload,
                  child: _ClassesTab(data: data, reload: reload, onNewHomework: _newHomework, onNewExam: _newExam),
                ),
                RefreshIndicator(onRefresh: reload, child: _StudentsTab(tuition: tuition, reload: reload)),
                HomeworkTab(key: ValueKey('tuition-homework-$_homeworkVersion'), tuitionId: widget.tuitionId),
                ExamsView(key: ValueKey('tuition-exams-$_examsVersion'), tuitionId: widget.tuitionId),
              ],
            ),
            floatingActionButton: Builder(builder: (context) {
              final controller = DefaultTabController.of(context);
              return AnimatedBuilder(
                animation: controller,
                builder: (context, _) => controller.index != 3
                    ? const SizedBox.shrink()
                    : FloatingActionButton.extended(
                        onPressed: _newExam,
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
  const _ClassesTab({required this.data, required this.reload, required this.onNewHomework, required this.onNewExam});
  final _TuitionData data;
  final Future<void> Function() reload;
  final Future<void> Function() onNewHomework;
  final Future<void> Function() onNewExam;

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

  static const _week = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

  static List<Json> _sortedSlots(List<Json> slots) => [...slots]
    ..sort((a, b) {
      final byDay = _week.indexOf(normalizeDay(a.str('day'))).compareTo(_week.indexOf(normalizeDay(b.str('day'))));
      return byDay != 0 ? byDay : minutesOf(slotStart(a)).compareTo(minutesOf(slotStart(b)));
    });

  /// Titles of the homework given on [day] (one per task, not one per student copy).
  List<String> _homeworkOn(DateTime? day) {
    if (day == null) return const [];
    final titles = <String>{};
    for (final h in data.homework) {
      final at = h.date('created_at')?.toLocal();
      if (at != null && at.year == day.year && at.month == day.month && at.day == day.day) titles.add(h.str('title'));
    }
    return titles.toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tuition = data.tuition;
    final cycle = tuition.obj('active_cycle');
    final wallet = tuition.obj('wallet_summary') ?? {};
    final earned = wallet.number('earned_revenue');
    final feeTotal = earned + wallet.number('pending_balance');
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
        // The headline: classes done and taka earned this cycle, then what to do next.
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        ProgressRing(done: done, total: total, size: 108, thickness: 12, caption: tr('classes')),
                        const SizedBox(height: 8),
                        Text(
                          total - done <= 0 ? tr('All classes taught') : tr('Classes done · {n} left', {'n': total - done}),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        RingChart(
                          value: feeTotal <= 0 ? 0 : earned / feeTotal,
                          color: tuitionColorOf(tuition.str('id')),
                          size: 108,
                          thickness: 12,
                          label: tr('Taka earned: {a} of {b}', {'a': Raw(taka(earned)), 'b': Raw(taka(feeTotal))}),
                          center: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(taka(earned), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.tt.success)),
                              Text(tr('of {p0}', {'p0': taka(feeTotal)}), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(tr('{p0} per class', {'p0': taka(wallet.number('per_class_rate'))}),
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              if (next != null) ...[
                gap16,
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: () => _quickMark(context, next),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(tr('Mark class {p0} done', {'p0': classNoOf(next)})),
                ),
              ],
              gap12,
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                      onPressed: onNewHomework,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(tr('Homework')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                      onPressed: onNewExam,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(tr('Exam')),
                    ),
                  ),
                ],
              ),
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

        // The usual class days, as chips (today's highlighted).
        if (tuition.maps('routine').isNotEmpty) ...[
          SectionTitle(tr('Class days')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slot in _sortedSlots(tuition.maps('routine')))
                _DayChip(slot: slot, today: normalizeDay(slot.str('day')) == weekdayName(DateTime.now())),
            ],
          ),
        ],

        // What was taught, newest first, with the homework given that day. Tap to correct or undo.
        SectionTitle(tr('Classes done ({p0}/{p1})', {'p0': done, 'p1': total}), icon: Icons.task_alt),
        if (doneClasses.isEmpty)
          Text(tr('No class marked done yet in this cycle.'), style: TextStyle(color: scheme.onSurfaceVariant))
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < doneClasses.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 58, color: context.tt.border),
                  _DoneClassRow(
                    entry: doneClasses[i],
                    homework: _homeworkOn(doneClasses[i].date('date')),
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

/// "Sun · 5:00–6:30 PM", highlighted on today.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.slot, required this.today});
  final Json slot;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final day = normalizeDay(slot.str('day'));
    final end = slot.str('end_time');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: today ? tt.primaryContainer : tt.card, borderRadius: BorderRadius.circular(12)),
      child: Text(
        '${day.isEmpty ? slot.str('day') : dayLabel(day)} · ${to12h(slotStart(slot))}${end.isEmpty ? '' : '–${to12h(end)}'}${today ? ' · ${tr('today')}' : ''}',
        style: TextStyle(fontSize: 13, fontWeight: today ? FontWeight.w700 : FontWeight.w600, color: today ? tt.onPrimaryContainer : tt.textPrimary),
      ),
    );
  }
}

/// "✓ Thu, 22 Oct · Energy · Homework: Exercise 3.2 — Class 7 ✎"
class _DoneClassRow extends StatelessWidget {
  const _DoneClassRow({required this.entry, required this.homework, required this.onTap});
  final Json entry;
  final List<String> homework;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final date = entry.date('date');
    final topic = entry.str('topic');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: tt.successContainer, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, size: 16, color: tt.onSuccessContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    date == null ? tr('Class {p0}', {'p0': classNoOf(entry)}) : '${dayLabel(weekdayName(date))}, ${fmtShortDate(date)}',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tt.textPrimary),
                  ),
                  if (topic.isNotEmpty) Text(topic, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: tt.textSecondary)),
                  for (final title in homework)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        tr('Homework: {title}', {'title': Raw(title)}),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: tone(context, AppColors.warning)),
                      ),
                    ),
                ],
              ),
            ),
            Text(tr('Class {p0}', {'p0': classNoOf(entry)}), style: TextStyle(fontSize: 12, color: tt.textTertiary)),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(Icons.edit_outlined, size: 18, color: tt.textTertiary),
            ),
          ],
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
