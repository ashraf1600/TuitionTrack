import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/connect.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/math_text.dart';
import '../../widgets/science_paste.dart';
import '../../widgets/science_toolbar.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../student/homework_card.dart';

class _HomeworkData {
  _HomeworkData(this.homework, this.tuitions, this.students);
  final List<HomeworkItem> homework;
  final List<Json> tuitions;
  final List<Json> students;
}

T? _firstOrNull<T>(Iterable<T> items, [bool Function(T)? test]) {
  for (final e in items) {
    if (test == null || test(e)) return e;
  }
  return null;
}

/// Tutor homework: create (whole tuition or one copy per student), review
/// submissions, mark each done, split shared rows per student.
/// Same logic as the web HomeworkManager.
class HomeworkTab extends StatefulWidget {
  const HomeworkTab({super.key});

  @override
  State<HomeworkTab> createState() => _HomeworkTabState();
}

class _HomeworkTabState extends State<HomeworkTab> {
  final _key = GlobalKey<LoaderState<_HomeworkData>>();
  String _filter = 'all'; // all | pending | evaluated
  static const _filterLabels = {'all': 'All', 'pending': 'Pending', 'evaluated': 'Evaluated'};

  Future<_HomeworkData> _load() async {
    final repo = context.read<Repo>();
    final results = await Future.wait([repo.homework(), repo.tuitions(), repo.students()]);
    final items = results[0].map(HomeworkItem.fromJson).toList();
    return _HomeworkData(items, results[1], results[2]);
  }

  Future<void> _create(_HomeworkData data) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => HomeworkFormScreen(tuitions: data.tuitions, students: data.students),
      ),
    );
    if (created == true) await _key.currentState?.reload();
  }

  Future<void> _delete(HomeworkItem hw) async {
    final ok = await confirm(
      context,
      title: tr('Delete homework?'),
      message: tr('"{p0}" will be removed for its students. This cannot be undone.', {'p0': hw.title}),
      confirmLabel: tr('Delete'),
      danger: true,
    );
    if (!ok || !mounted) return;
    if (await attempt(context, () => context.read<Repo>().deleteHomework(hw.id), success: tr('Homework deleted.'))) {
      await _key.currentState?.reload();
    }
  }

  /// Turn one shared tuition row into one row per enrolled student so each
  /// submission is reviewed and marked done individually. One server call:
  /// either every copy is made and the shared row goes, or nothing changes.
  Future<void> _split(HomeworkItem hw, List<Json> tuitions) async {
    final tuition = _firstOrNull(tuitions, (t) => t.str('id') == hw.tuitionId);
    final members = (tuition?.maps('enrollments') ?? const []).where((e) => e['is_active'] != false).length;
    if (members == 0) {
      showToast(context, tr('No enrolled students found in this tuition to split across.'), error: true);
      return;
    }
    final ok = await confirm(
      context,
      title: tr('Split into per-student copies?'),
      message: tr('"{p0}" becomes {p1} individual rows (one per student). Work already handed in is kept. The shared row is removed.', {'p0': hw.title, 'p1': members}),
      confirmLabel: tr('Split ({p0})', {'p0': members}),
    );
    if (!ok || !mounted) return;
    final repo = context.read<Repo>();
    var made = 0;
    final done = await attempt(context, () async {
      made = (await repo.splitHomework(hw.id)).length;
    });
    if (!done || !mounted) return;
    showToast(context, tr('Split into {p0} individual copies.', {'p0': made}));
    await _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Loader<_HomeworkData>(
      key: _key,
      load: _load,
      builder: (context, data, reload) {
        final counts = {
          'all': data.homework.length,
          'pending': data.homework.where((h) => !h.isEvaluated).length,
          'evaluated': data.homework.where((h) => h.isEvaluated).length,
        };
        final filtered = data.homework.where((h) {
          if (_filter == 'pending') return !h.isEvaluated;
          if (_filter == 'evaluated') return h.isEvaluated;
          return true;
        }).toList();
        return PageBody(
          children: [
            PillToggle<String>(
              options: [
                for (final f in const ['all', 'pending', 'evaluated'])
                  (f, '${tr(_filterLabels[f]!)} ${localDigits('${counts[f] ?? 0}')}', null),
              ],
              selected: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
            gap12,
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () {
                HapticFeedback.lightImpact();
                _create(data);
              },
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('Assign homework')),
            ),
            gap8,
            if (filtered.isEmpty)
              EmptyState(
                icon: Icons.assignment_outlined,
                title: tr('No homework found'),
                message: _filter == 'all'
                    ? tr('Assign homework to a tuition or a student to get started.')
                    : (_filter == 'pending' ? tr('No pending homework right now.') : tr('No evaluated homework right now.')),
              )
            else
              for (final (i, hw) in filtered.indexed) ...[
                _TutorHomeworkRow(
                  hw: hw,
                  // Work for the same student (or tuition) sits under one header.
                  showHeader: i == 0 || _targetOf(filtered[i - 1]) != _targetOf(hw),
                  onChanged: () async {
                    await _key.currentState?.reload();
                  },
                  onDelete: () => _delete(hw),
                  onSplit: hw.isSharedGroupTask ? () => _split(hw, data.tuitions) : null,
                ),
                gap12,
              ],
          ],
        );
      },
    );
  }
}

String _targetOf(HomeworkItem hw) => hw.studentName.isNotEmpty ? hw.studentName : hw.tuitionTitle;

class _TutorHomeworkRow extends StatelessWidget {
  const _TutorHomeworkRow({required this.hw, required this.onChanged, required this.onDelete, this.onSplit, this.showHeader = true});
  final HomeworkItem hw;
  final Future<void> Function() onChanged;
  final VoidCallback onDelete;
  final VoidCallback? onSplit;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final target = _targetOf(hw);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (target.isNotEmpty && showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: tt.primaryContainer,
                  child: hw.studentName.isNotEmpty
                      ? Text(target.characters.first.toUpperCase(),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tt.onPrimaryContainer))
                      : Icon(Icons.groups_outlined, size: 14, color: tt.onPrimaryContainer),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(target,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: tt.textSecondary), overflow: TextOverflow.ellipsis),
                ),
                if (hw.isSharedGroupTask)
                  Text(tr('shared'), style: TextStyle(fontSize: 12, color: tt.textTertiary)),
              ],
            ),
          ),
        HomeworkCard(
          hw: hw,
          isTutor: true,
          onChanged: onChanged,
          trailing: hw.isPending
              ? null
              : IconButton(
                  tooltip: tr('Delete homework'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: tt.textTertiary),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onDelete();
                  },
                ),
        ),
        if (!hw.isPending && onSplit != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                onSplit!();
              },
              icon: const Icon(Icons.call_split_outlined, size: 16),
              label: Text(tr('Split per student')),
            ),
          ),
      ],
    );
  }
}

/// Standalone route for the + button: loads tuitions + students, then the form.
class HomeworkCreateScreen extends StatelessWidget {
  const HomeworkCreateScreen({super.key, this.initialTuitionId});

  /// Opens the form with this tuition already chosen.
  final String? initialTuitionId;

  @override
  Widget build(BuildContext context) {
    return Loader<_HomeworkData>(
      load: () async {
        final repo = context.read<Repo>();
        final results = await Future.wait([repo.tuitions(), repo.students()]);
        return _HomeworkData(const [], results[0], results[1]);
      },
      builder: (context, data, reload) =>
          HomeworkFormScreen(tuitions: data.tuitions, students: data.students, initialTuitionId: initialTuitionId),
    );
  }
}
/// Create sheet: title + deadline required, tuition or student target,
/// optional fan-out into one copy per student.
class HomeworkFormScreen extends StatefulWidget {
  const HomeworkFormScreen({super.key, required this.tuitions, required this.students, this.initialTuitionId});
  final List<Json> tuitions;
  final List<Json> students;
  final String? initialTuitionId;

  @override
  State<HomeworkFormScreen> createState() => _HomeworkFormScreenState();
}

class _HomeworkFormScreenState extends State<HomeworkFormScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  bool _toGroup = true;
  String? _tuitionId;
  String? _studentId;
  bool _perStudent = true;
  bool _showInstructions = false;
  DateTime _due = _at(1, 18);

  @override
  void initState() {
    super.initState();
    _tuitionId = widget.initialTuitionId;
  }

  /// [days] from today at [hour]:00.
  static DateTime _at(int days, int hour) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + days, hour);
  }

  Json? get _tuition => _firstOrNull(widget.tuitions, (t) => t.str('id') == _tuitionId) ?? _firstOrNull(widget.tuitions);
  Json? get _student => _firstOrNull(widget.students, (s) => s.str('id') == _studentId) ?? _firstOrNull(widget.students);
  static String _studentName(Json s) => s.str('full_name').isNotEmpty ? s.str('full_name') : '@${s.str('username')}';

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  List<(String, String)> get _roster {
    final t = _tuition;
    if (t == null) return const [];
    return (t.maps('enrollments'))
        .where((e) => e['is_active'] != false && e.str('student_id').isNotEmpty)
        .map((e) => (e.str('student_id'), e.str('student_name')))
        .toList();
  }

  Future<void> _pickDue() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_due));
    if (!mounted) return;
    setState(() => _due = DateTime(date.year, date.month, date.day, time?.hour ?? 18, time?.minute ?? 0));
  }

  Future<void> _send() async {
    HapticFeedback.lightImpact();
    if (_title.text.trim().isEmpty) {
      showToast(context, tr('Title is required.'), error: true);
      return;
    }
    if (_due.isBefore(DateTime.now())) {
      showToast(context, tr('Deadline must be in the future.'), error: true);
      return;
    }
    final repo = context.read<Repo>();
    final title = _title.text.trim();
    final description = _desc.text.trim();
    var sent = 0;
    var queued = 0;
    void count(Json result) => result['queued'] == true ? queued++ : sent++;
    var success = tr('Homework assigned.');
    final ok = await attempt(context, () async {
      if (_toGroup) {
        final tuition = _firstOrNull(widget.tuitions, (t) => t.str('id') == _tuitionId) ?? _firstOrNull(widget.tuitions);
        if (tuition == null) throw ApiException(tr('Create a tuition first.'));
        final roster = _roster;
        if (_perStudent && roster.isNotEmpty) {
          for (final (sid, name) in roster) {
            count(await repo.createHomework(
              title: title,
              description: description,
              dueDate: _due,
              studentId: sid,
              targetName: name,
            ));
          }
          success = tr('Homework sent to {p0} students (one copy each).', {'p0': roster.length});
        } else {
          count(await repo.createHomework(
            title: title,
            description: description,
            dueDate: _due,
            tuitionId: tuition.str('id'),
            targetName: tuition.str('title'),
          ));
          success = tr('Homework sent to {p0}.', {'p0': tuition.str('title')});
        }
      } else {
        final student = _firstOrNull(widget.students, (s) => s.str('id') == _studentId) ?? _firstOrNull(widget.students);
        if (student == null) throw ApiException(tr('Choose a student.'));
        count(await repo.createHomework(
          title: title,
          description: description,
          dueDate: _due,
          studentId: student.str('id'),
          targetName: student.str('full_name'),
        ));
      }
    });
    if (ok && mounted) {
      showToast(
        context,
        queued == 0
            ? success
            : sent == 0
                ? tr('Saved on this phone. It will be sent when you are back online.')
                : tr('{p0} sent, {p1} saved on this phone to send when you are back online.', {'p0': sent, 'p1': queued}),
      );
    }
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _chooseTarget() async {
    final picked = _toGroup
        ? await pickFromSheet(
            context,
            title: tr('Choose a tuition'),
            icon: Icons.class_outlined,
            selected: _tuition?.str('id'),
            options: [
              for (final t in widget.tuitions)
                (
                  value: t.str('id'),
                  label: t.str('title'),
                  subtitle: '${t.integer('enrolled_count')} student${t.integer('enrolled_count') == 1 ? '' : 's'}',
                ),
            ],
          )
        : await pickFromSheet(
            context,
            title: tr('Choose a student'),
            selected: _student?.str('id'),
            options: [
              for (final s in widget.students) (value: s.str('id'), label: _studentName(s), subtitle: '@${s.str('username')}'),
            ],
          );
    if (picked == null || !mounted) return;
    setState(() {
      if (_toGroup) {
        _tuitionId = picked;
      } else {
        _studentId = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roster = _roster;
    final tuition = _tuition;
    final student = _student;
    final targetName = _toGroup ? (tuition?.str('title') ?? tr('No tuitions yet')) : (student == null ? tr('No students yet') : _studentName(student));
    final quick = <(String, DateTime)>[(tr('Tomorrow'), _at(1, 18)), (tr('In 3 days'), _at(3, 18)), (tr('Next week'), _at(7, 18))];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Assign homework'))),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                FlatGroup(children: [
                  FlatField(
                    controller: _title,
                    hint: tr('Title, e.g. Chapter 4 problems'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    contextMenuBuilder: sciencePasteMenu,
                    onChanged: (_) => setState(() {}),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    alignment: Alignment.topCenter,
                    child: _showInstructions || _desc.text.isNotEmpty
                        ? FlatField(
                            controller: _desc,
                            hint: tr('Instructions: pages, problems, how to hand in…'),
                            minLines: 3,
                            maxLines: 8,
                            autofocus: _desc.text.isEmpty,
                            contextMenuBuilder: sciencePasteMenu,
                            onChanged: (_) => setState(() {}),
                          )
                        : InkWell(
                            onTap: () => setState(() => _showInstructions = true),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                              child: Row(
                                children: [
                                  Icon(Icons.add, size: 18, color: scheme.onSurfaceVariant),
                                  const SizedBox(width: 8),
                                  Text(tr('Add instructions'), style: TextStyle(color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ),
                  ),
                ]),
                // Formulas typed with the science keys or pasted from ChatGPT, as students will see them.
                if (hasMath(_title.text) || hasMath(_desc.text)) ...[
                  gap8,
                  AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Students will see'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        if (_title.text.trim().isNotEmpty) MathText(_title.text.trim(), style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (_desc.text.trim().isNotEmpty) ...[const SizedBox(height: 4), MathText(_desc.text.trim())],
                      ],
                    ),
                  ),
                ],
                gap16,
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [
                      ButtonSegment(value: true, label: Text(tr('Tuition')), icon: Icon(Icons.class_outlined, size: 18)),
                      ButtonSegment(value: false, label: Text(tr('Student')), icon: Icon(Icons.person_outline, size: 18)),
                    ],
                    selected: {_toGroup},
                    onSelectionChanged: (s) => setState(() => _toGroup = s.first),
                  ),
                ),
                gap12,
                FlatGroup(children: [
                  PickerRow(
                    leading: InitialAvatar(targetName, radius: 14, icon: _toGroup ? Icons.class_outlined : null),
                    label: _toGroup ? tr('Tuition') : tr('Student'),
                    value: targetName,
                    onTap: (_toGroup ? widget.tuitions.isEmpty : widget.students.isEmpty) ? null : _chooseTarget,
                  ),
                  if (_toGroup && roster.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(tr('One copy per student ({p0})', {'p0': roster.length}), style: const TextStyle(fontSize: 14))),
                          InfoTip(
                            tr('On: every student gets their own copy, and you mark each one done separately.\n\nOff: one shared task for the whole tuition; marking it done counts for everyone.'),
                            title: tr('One copy per student'),
                          ),
                          Switch(value: _perStudent, onChanged: (v) => setState(() => _perStudent = v)),
                        ],
                      ),
                    ),
                  PickerRow(
                    leading: Icon(Icons.calendar_month_outlined, size: 22, color: tone(context, AppColors.primarySoft)),
                    label: tr('Due'),
                    value: '${fmtShortDate(_due)}, ${dayLabel(weekdayName(_due))} · ${fmtTime(_due)}',
                    onTap: _pickDue,
                  ),
                ]),
                gap8,
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (label, at) in quick)
                      ChoiceChip(
                        label: Text(label),
                        selected: _due == at,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _due = at),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: BusyButton(
                  label: _toGroup && _perStudent && roster.isNotEmpty ? tr('Assign to {p0} students', {'p0': roster.length}) : tr('Assign homework'),
                  icon: Icons.send,
                  onPressed: _title.text.trim().isEmpty ? null : _send,
                ),
              ),
            ),
          ),
          // x², H₂O, fractions, Greek letters and units — the same keys as in exams.
          const ScienceToolbar(),
        ],
      ),
    );
  }
}
