import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../theme/tt_theme.dart';

/// What the tutor adds while marking a class done: both parts are optional.
class ClassDoneDetails {
  const ClassDoneDetails({this.topic = '', this.homework = '', required this.due});
  final String topic;
  final String homework;
  final DateTime due;
}

/// The sheet behind "Mark class done": one place to say what was covered and to
/// give homework, then one button. Leaving both empty just marks the class.
/// Returns null when the sheet is dismissed (nothing is marked).
Future<ClassDoneDetails?> askClassDone(BuildContext context, {required String tuitionTitle, required int classNo}) {
  return showModalBottomSheet<ClassDoneDetails>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ClassDoneSheet(tuitionTitle: tuitionTitle, classNo: classNo),
  );
}

/// Sends [title] as homework for the class: one copy per enrolled student (each is
/// checked on its own), or one for the tuition when nobody is enrolled yet.
/// Returns true when it was kept on the phone to send later.
Future<bool> sendClassHomework(Repo repo, Json tuition, int classNo, String title, DateTime due) async {
  final now = DateTime.now();
  final source = tr('Class {p0} · {p1}/{p2}',
      {'p0': classNo, 'p1': now.day.toString().padLeft(2, '0'), 'p2': now.month.toString().padLeft(2, '0')});
  final roster = tuition
      .maps('enrollments')
      .where((e) => e['is_active'] != false && e.str('student_id').isNotEmpty)
      .toList();
  var queued = false;
  if (roster.isEmpty) {
    final result = await repo.createHomework(
        title: title, dueDate: due, tuitionId: tuition.str('id'), sourceLabel: source, targetName: tuition.str('title'));
    return result['queued'] == true;
  }
  for (final s in roster) {
    final result = await repo.createHomework(
        title: title, dueDate: due, studentId: s.str('student_id'), sourceLabel: source, targetName: s.str('student_name'));
    if (result['queued'] == true) queued = true;
  }
  return queued;
}

class _ClassDoneSheet extends StatefulWidget {
  const _ClassDoneSheet({required this.tuitionTitle, required this.classNo});
  final String tuitionTitle;
  final int classNo;

  @override
  State<_ClassDoneSheet> createState() => _ClassDoneSheetState();
}

class _ClassDoneSheetState extends State<_ClassDoneSheet> {
  final _topic = TextEditingController();
  final _homework = TextEditingController();
  // Days until the homework is due (6 PM that day).
  int _dueIn = 1;

  @override
  void initState() {
    super.initState();
    _homework.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _topic.dispose();
    _homework.dispose();
    super.dispose();
  }

  void _done() {
    final day = DateTime.now().add(Duration(days: _dueIn));
    Navigator.pop(
      context,
      ClassDoneDetails(
        topic: _topic.text.trim(),
        homework: _homework.text.trim(),
        due: DateTime(day.year, day.month, day.day, 18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final hasHomework = _homework.text.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Class {n} done', {'n': widget.classNo}),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: tt.textPrimary)),
              if (widget.tuitionTitle.isNotEmpty)
                Text(widget.tuitionTitle, style: TextStyle(fontSize: 13, color: tt.textSecondary)),
              const SizedBox(height: 16),
              TextField(
                controller: _topic,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: tr('Topic covered (optional)'),
                  prefixIcon: const Icon(Icons.menu_book_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _homework,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: tr('Homework (optional)'),
                  hintText: tr('e.g. Solve exercises 4.1–4.3'),
                  prefixIcon: const Icon(Icons.assignment_outlined),
                ),
              ),
              if (hasHomework) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(tr('Due'), style: TextStyle(fontSize: 13, color: tt.textSecondary)),
                    for (final (days, label) in [(1, tr('Tomorrow')), (3, tr('In 3 days')), (7, tr('Next week'))])
                      ChoiceChip(
                        label: Text(label),
                        selected: _dueIn == days,
                        onSelected: (_) => setState(() => _dueIn = days),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _done,
                icon: const Icon(Icons.check_rounded),
                label: Text(hasHomework ? tr('Mark done and send homework') : tr('Mark class done')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
