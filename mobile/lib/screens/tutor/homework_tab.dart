import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/connect.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
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
      title: 'Delete homework?',
      message: '"${hw.title}" will be removed for its students. This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    if (await attempt(context, () => context.read<Repo>().deleteHomework(hw.id), success: 'Homework deleted.')) {
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
      showToast(context, 'No enrolled students found in this tuition to split across.', error: true);
      return;
    }
    final ok = await confirm(
      context,
      title: 'Split into per-student copies?',
      message: '"${hw.title}" becomes $members individual rows (one per student). '
          'Work already handed in is kept. The shared row is removed.',
      confirmLabel: 'Split ($members)',
    );
    if (!ok || !mounted) return;
    final repo = context.read<Repo>();
    var made = 0;
    final done = await attempt(context, () async {
      made = (await repo.splitHomework(hw.id)).length;
    });
    if (!done || !mounted) return;
    showToast(context, 'Split into $made individual copies.');
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
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: [
                      for (final f in const ['all', 'pending', 'evaluated'])
                        ButtonSegment(
                          value: f,
                          label: Text('${f[0].toUpperCase()}${f.substring(1)} (${counts[f] ?? 0})'),
                        ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (s) => setState(() => _filter = s.first),
                  ),
                ),
              ],
            ),
            gap12,
            FilledButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                _create(data);
              },
              icon: const Icon(Icons.add),
              label: const Text('Assign homework'),
            ),
            gap12,
            if (filtered.isEmpty)
              EmptyState(
                icon: Icons.assignment_outlined,
                title: 'No homework found',
                message: _filter == 'all'
                    ? 'Assign homework to a tuition or a student to get started.'
                    : 'No $_filter homework right now.',
              )
            else
              for (final hw in filtered) ...[
                _TutorHomeworkRow(
                  hw: hw,
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

class _TutorHomeworkRow extends StatelessWidget {
  const _TutorHomeworkRow({required this.hw, required this.onChanged, required this.onDelete, this.onSplit});
  final HomeworkItem hw;
  final Future<void> Function() onChanged;
  final VoidCallback onDelete;
  final VoidCallback? onSplit;

  @override
  Widget build(BuildContext context) {
    final target = hw.studentName.isNotEmpty ? hw.studentName : hw.tuitionTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (target.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(
              children: [
                Icon(hw.studentName.isNotEmpty ? Icons.person_outline : Icons.class_outlined,
                    size: 14, color: tone(context, AppColors.primarySoft)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(target,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tone(context, AppColors.primarySoft)),
                      overflow: TextOverflow.ellipsis),
                ),
                if (hw.isSharedGroupTask)
                  Text('shared', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        HomeworkCard(hw: hw, isTutor: true, onChanged: onChanged),
        if (!hw.isPending)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onSplit != null)
                TextButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onSplit!();
                  },
                  icon: const Icon(Icons.call_split_outlined, size: 16),
                  label: const Text('Split per student'),
                ),
              IconButton(
                tooltip: 'Delete homework',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onDelete();
                },
              ),
            ],
          ),
      ],
    );
  }
}

/// Standalone route for the + button: loads tuitions + students, then the form.
class HomeworkCreateScreen extends StatelessWidget {
  const HomeworkCreateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Loader<_HomeworkData>(
      load: () async {
        final repo = context.read<Repo>();
        final results = await Future.wait([repo.homework(), repo.tuitions(), repo.students()]);
        return _HomeworkData(const [], results[1], results[2]);
      },
      builder: (context, data, reload) => HomeworkFormScreen(tuitions: data.tuitions, students: data.students),
    );
  }
}
/// Create sheet: title + deadline required, tuition or student target,
/// optional fan-out into one copy per student.
class HomeworkFormScreen extends StatefulWidget {
  const HomeworkFormScreen({super.key, required this.tuitions, required this.students});
  final List<Json> tuitions;
  final List<Json> students;

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
      showToast(context, 'Title is required.', error: true);
      return;
    }
    if (_due.isBefore(DateTime.now())) {
      showToast(context, 'Deadline must be in the future.', error: true);
      return;
    }
    final repo = context.read<Repo>();
    final title = _title.text.trim();
    final description = _desc.text.trim();
    var sent = 0;
    var queued = 0;
    void count(Json result) => result['queued'] == true ? queued++ : sent++;
    var success = 'Homework assigned.';
    final ok = await attempt(context, () async {
      if (_toGroup) {
        final tuition = _firstOrNull(widget.tuitions, (t) => t.str('id') == _tuitionId) ?? _firstOrNull(widget.tuitions);
        if (tuition == null) throw ApiException('Create a tuition first.');
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
          success = 'Homework sent to ${roster.length} students (one copy each).';
        } else {
          count(await repo.createHomework(
            title: title,
            description: description,
            dueDate: _due,
            tuitionId: tuition.str('id'),
            targetName: tuition.str('title'),
          ));
          success = 'Homework sent to ${tuition.str('title')}.';
        }
      } else {
        final student = _firstOrNull(widget.students, (s) => s.str('id') == _studentId) ?? _firstOrNull(widget.students);
        if (student == null) throw ApiException('Choose a student.');
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
                ? 'Saved on this phone. It will be sent when you are back online.'
                : '$sent sent, $queued saved on this phone to send when you are back online.',
      );
    }
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _chooseTarget() async {
    final picked = _toGroup
        ? await pickFromSheet(
            context,
            title: 'Choose a tuition',
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
            title: 'Choose a student',
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
    final targetName = _toGroup ? (tuition?.str('title') ?? 'No tuitions yet') : (student == null ? 'No students yet' : _studentName(student));
    final quick = <(String, DateTime)>[('Tomorrow', _at(1, 18)), ('In 3 days', _at(3, 18)), ('Next week', _at(7, 18))];
    return Scaffold(
      appBar: AppBar(title: const Text('Assign homework')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                FlatGroup(children: [
                  FlatField(
                    controller: _title,
                    hint: 'Title, e.g. Chapter 4 problems',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    onChanged: (_) => setState(() {}),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    alignment: Alignment.topCenter,
                    child: _showInstructions || _desc.text.isNotEmpty
                        ? FlatField(controller: _desc, hint: 'Instructions: pages, problems, how to hand in…', minLines: 3, maxLines: 8, autofocus: _desc.text.isEmpty)
                        : InkWell(
                            onTap: () => setState(() => _showInstructions = true),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                              child: Row(
                                children: [
                                  Icon(Icons.add, size: 18, color: scheme.onSurfaceVariant),
                                  const SizedBox(width: 8),
                                  Text('Add instructions', style: TextStyle(color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ),
                  ),
                ]),
                gap16,
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: true, label: Text('Tuition'), icon: Icon(Icons.class_outlined, size: 18)),
                      ButtonSegment(value: false, label: Text('Student'), icon: Icon(Icons.person_outline, size: 18)),
                    ],
                    selected: {_toGroup},
                    onSelectionChanged: (s) => setState(() => _toGroup = s.first),
                  ),
                ),
                gap12,
                FlatGroup(children: [
                  PickerRow(
                    leading: InitialAvatar(targetName, radius: 14, icon: _toGroup ? Icons.class_outlined : null),
                    label: _toGroup ? 'Tuition' : 'Student',
                    value: targetName,
                    onTap: (_toGroup ? widget.tuitions.isEmpty : widget.students.isEmpty) ? null : _chooseTarget,
                  ),
                  if (_toGroup && roster.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text('One copy per student (${roster.length})', style: const TextStyle(fontSize: 14))),
                          const InfoTip(
                            'On: every student gets their own copy, and you mark each one done separately.\n\n'
                            'Off: one shared task for the whole tuition; marking it done counts for everyone.',
                            title: 'One copy per student',
                          ),
                          Switch(value: _perStudent, onChanged: (v) => setState(() => _perStudent = v)),
                        ],
                      ),
                    ),
                  PickerRow(
                    leading: Icon(Icons.calendar_month_outlined, size: 22, color: tone(context, AppColors.primarySoft)),
                    label: 'Due',
                    value: '${fmtShortDate(_due)}, ${weekdayName(_due).substring(0, 3)} · ${fmtTime(_due)}',
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
                  label: _toGroup && _perStudent && roster.isNotEmpty ? 'Assign to ${roster.length} students' : 'Assign homework',
                  icon: Icons.send,
                  onPressed: _title.text.trim().isEmpty ? null : _send,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
