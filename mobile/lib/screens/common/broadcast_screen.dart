import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/chat.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/charts.dart';
import '../../widgets/science_paste.dart';
import '../../widgets/science_toolbar.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

/// A tutor writes once to every student of a tuition: "No class today",
/// "Exam on Friday", a fee reminder. Each student gets it in their own chat,
/// so their replies come back privately.
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key, this.initialTuitionId, this.initialText = ''});
  final String? initialTuitionId;
  final String initialText;

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  late final _text = TextEditingController(text: widget.initialText);
  late String? _tuitionId = widget.initialTuitionId;
  final _ref = newClientRef();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(Json tuition) async {
    HapticFeedback.lightImpact();
    final api = ChatApi(context.read<Session>().api);
    var students = 0;
    final ok = await attempt(context, () async {
      students = await api.broadcast(tuition.str('id'), _text.text.trim(), clientRef: _ref);
    });
    if (!ok || !mounted) return;
    showToast(context, students == 1 ? tr('Sent to 1 student.') : tr('Sent to {n} students.', {'n': students}));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Message a whole tuition'))),
      body: Loader<List<Json>>(
        load: context.read<Repo>().tuitions,
        scrollable: false,
        builder: (context, tuitions, reload) {
          final tt = context.tt;
          if (tuitions.isEmpty) {
            return PageBody(children: [
              EmptyState(icon: Icons.class_outlined, title: tr('No tuitions yet'), message: tr('Create a tuition and add students first.')),
            ]);
          }
          final tuition = tuitions.firstWhere((t) => t.str('id') == _tuitionId, orElse: () => tuitions.first);
          final students = tuition.maps('enrollments').where((e) => e['is_active'] != false).length;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    FlatGroup(children: [
                      PickerRow(
                        leading: Container(width: 14, height: 14, decoration: BoxDecoration(color: tuitionColorOf(tuition.str('id')), shape: BoxShape.circle)),
                        label: tr('Tuition'),
                        value: tuition.str('title'),
                        onTap: tuitions.length < 2
                            ? null
                            : () async {
                                final picked = await pickFromSheet(
                                  context,
                                  title: tr('Choose a tuition'),
                                  icon: Icons.class_outlined,
                                  selected: tuition.str('id'),
                                  options: [
                                    for (final t in tuitions)
                                      (value: t.str('id'), label: t.str('title'), subtitle: tr('{p0} student{p1}', {'p0': t.integer('enrolled_count'), 'p1': t.integer('enrolled_count') == 1 ? '' : 's'})),
                                  ],
                                );
                                if (picked != null) setState(() => _tuitionId = picked);
                              },
                      ),
                    ]),
                    gap12,
                    FlatGroup(children: [
                      FlatField(
                        controller: _text,
                        hint: tr('e.g. No class today. We will meet on Thursday at 5 PM.'),
                        minLines: 5,
                        maxLines: 10,
                        contextMenuBuilder: sciencePasteMenu,
                        onChanged: (_) => setState(() {}),
                      ),
                    ]),
                    gap12,
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 16, color: tt.textTertiary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr('Goes to {n} students, each in their own chat. Replies come back to you privately. Students do not see the tuition\'s name.', {'n': students}),
                            style: TextStyle(fontSize: 13, height: 1.45, color: tt.textSecondary),
                          ),
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
                      label: students == 1 ? tr('Send to 1 student') : tr('Send to {n} students', {'n': students}),
                      icon: Icons.send_rounded,
                      onPressed: _text.text.trim().isEmpty || students == 0 ? null : () => _send(tuition),
                    ),
                  ),
                ),
              ),
              const ScienceToolbar(),
            ],
          );
        },
      ),
    );
  }
}
