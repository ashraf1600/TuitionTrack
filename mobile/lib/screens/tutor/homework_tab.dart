import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/connect.dart';
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

/// Tutor homework: create (whole group or one copy per student), review
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

  /// Turn one shared group row into one row per enrolled student so each
  /// submission is reviewed and marked done individually.
  Future<void> _split(HomeworkItem hw, List<Json> tuitions) async {
    final tuition = _firstOrNull(tuitions, (t) => t.str('id') == hw.tuitionId);
    final roster = (tuition?.maps('enrollments') ?? const [])
        .where((e) => e['is_active'] != false)
        .map((e) => (id: e.str('student_id'), name: e.str('student_name')))
        .where((s) => s.id.isNotEmpty)
        .toList();
    if (roster.isEmpty) {
      showToast(context, 'No enrolled students found in this group to split across.', error: true);
      return;
    }
    final ok = await confirm(
      context,
      title: 'Split into per-student copies?',
      message:
          '"${hw.title}" becomes ${roster.length} individual rows (one per student). The shared row is removed.',
      confirmLabel: 'Split (${roster.length})',
    );
    if (!ok || !mounted) return;
    final repo = context.read<Repo>();
    var done = 0;
    final ok2 = await attempt(context, () async {
      for (final s in roster) {
        await repo.createHomework(
          title: hw.title,
          description: hw.description,
          dueDate: hw.dueDate,
          studentId: s.id,
          sourceLabel: hw.sourceLabel,
        );
        done++;
      }
      await repo.deleteHomework(hw.id);
    }, success: done == roster.length ? 'Split into $done individual copies.' : null);
    if (ok2) await _key.currentState?.reload();
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
                    ? 'Assign homework to a group or a student to get started.'
                    : 'No ${_filter} homework right now.',
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
                Icon(hw.studentName.isNotEmpty ? Icons.person_outline : Icons.groups_outlined,
                    size: 14, color: AppColors.primarySoft),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(target,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primarySoft),
                      overflow: TextOverflow.ellipsis),
                ),
                if (hw.isSharedGroupTask)
                  Text('shared', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        HomeworkCard(hw: hw, isTutor: true, onChanged: onChanged),
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

/// Standalone route for the + button: loads groups + students, then the form.
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
/// Create sheet: title + deadline required, group or student target,
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
  DateTime _due = DateTime.now().add(const Duration(days: 1));

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  List<(String, String)> get _roster {
    final t = _firstOrNull(widget.tuitions, (t) => t.str('id') == _tuitionId);
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
    final ok = await attempt(context, () async {
      if (_toGroup) {
        final id = _tuitionId ?? _firstOrNull(widget.tuitions)?.str('id') ?? '';
        if (id.isEmpty) throw ApiException('Create a tuition group first.');
        final roster = _roster;
        if (_perStudent && roster.isNotEmpty) {
          var done = 0;
          for (final (sid, _) in roster) {
            await repo.createHomework(
              title: _title.text.trim(),
              description: _desc.text.trim(),
              dueDate: _due,
              studentId: sid,
            );
            done++;
          }
          if (done < roster.length) throw ApiException('Only $done of ${roster.length} copies were sent.');
        } else {
          await repo.createHomework(
            title: _title.text.trim(),
            description: _desc.text.trim(),
            dueDate: _due,
            tuitionId: id,
          );
        }
      } else {
        final sid = _studentId ?? _firstOrNull(widget.students)?.str('id') ?? '';
        if (sid.isEmpty) throw ApiException('Choose a student.');
        await repo.createHomework(
          title: _title.text.trim(),
          description: _desc.text.trim(),
          dueDate: _due,
          studentId: sid,
        );
      }
    }, success: 'Homework assigned.');
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final roster = _roster;
    return Scaffold(
      appBar: AppBar(title: const Text('Assign homework')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title *', hintText: 'e.g. Chapter 4 problems'),
          ),
          gap12,
          TextField(
            controller: _desc,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Instructions (optional)'),
          ),
          gap12,
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Tuition group'), icon: Icon(Icons.groups_outlined)),
              ButtonSegment(value: false, label: Text('Student'), icon: Icon(Icons.person_outline)),
            ],
            selected: {_toGroup},
            onSelectionChanged: (s) => setState(() => _toGroup = s.first),
          ),
          gap12,
          if (_toGroup)
            DropdownButtonFormField<String>(
              initialValue: _tuitionId ?? _firstOrNull(widget.tuitions)?.str('id'),
              decoration: const InputDecoration(labelText: 'Group'),
              items: [
                for (final t in widget.tuitions)
                  DropdownMenuItem(value: t.str('id'), child: Text(t.str('title'), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _tuitionId = v),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _studentId ?? _firstOrNull(widget.students)?.str('id'),
              decoration: const InputDecoration(labelText: 'Student'),
              items: [
                for (final s in widget.students)
                  DropdownMenuItem(
                      value: s.str('id'),
                      child: Text(s.str('full_name').isNotEmpty ? s.str('full_name') : '@${s.str('username')}',
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _studentId = v),
            ),
          if (_toGroup && roster.isNotEmpty) ...[
            gap8,
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Separate copy per student (${roster.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('Each submission is marked done individually. Off = one shared task.',
                  style: TextStyle(fontSize: 12)),
              value: _perStudent,
              onChanged: (v) => setState(() => _perStudent = v ?? true),
            ),
          ],
          gap12,
          OutlinedButton.icon(
            onPressed: _pickDue,
            icon: const Icon(Icons.event_outlined),
            label: Text('Deadline: ${_due.day}/${_due.month} ${_due.hour.toString().padLeft(2, '0')}:${_due.minute.toString().padLeft(2, '0')}'),
          ),
          gap16,
          BusyButton(label: 'Assign homework', icon: Icons.send, onPressed: _send),
        ],
      ),
    );
  }
}
