import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart' show HomeworkItem;
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/reminder_plan.dart';
import '../../core/reminders.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/charts.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import '../../widgets/update_banner.dart';
import '../common/notifications.dart';
import 'connect_screen.dart';
import 'student_lists.dart';
import 'tutor_detail_screen.dart';

class _StudentData {
  _StudentData(this.tutors, this.tuitions, this.connections, this.exams, this.homework, this.homeworkRaw);
  final List<Json> tutors;
  final List<Json> tuitions;
  final List<Json> connections;
  final List<Json> exams;
  final List<HomeworkItem> homework;
  final List<Json> homeworkRaw;
}

/// The student's app: one flashcard per tutor on the home tab (tap one for
/// that tutor's classes, exams and homework), plus every exam and every piece
/// of homework across tutors on the other two tabs.
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
    final settings = context.read<Session>().settings;
    final results = await Future.wait([
      repo.myTutors(),
      repo.tuitions(),
      repo.connections(),
      repo.exams(),
      repo.homework(),
    ]);
    final homework = results[4]
        .map(HomeworkItem.fromJson)
        .toList()
      // Pending first (nearest deadline on top), checked work below.
      ..sort((a, b) {
        if (a.isEvaluated != b.isEvaluated) return a.isEvaluated ? 1 : -1;
        return a.dueDate.compareTo(b.dueDate);
      });
    // Class and homework reminders for the coming week (they work offline).
    unawaited(Reminders.instance.schedule(settings, studentReminders(results[1], results[4], DateTime.now())));
    return _StudentData(results[0], results[1], results[2], results[3], homework, results[4]);
  }

  String _title() => switch (_tab) {
        1 => tr('Exams & assignments'),
        2 => tr('Homework'),
        _ => tr('Hello, {p0}', {'p0': context.read<Session>().displayName}),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title()), actions: homeActions(context)),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          const OfflineBanner(),
          const UpdateBanner(),
          Expanded(
            child: Loader<_StudentData>(
              key: _loader,
              load: _load,
              builder: (context, data, reload) => switch (_tab) {
                1 => StudentExamsList(exams: data.exams, reload: reload),
                2 => StudentHomeworkList(items: data.homework, reload: reload),
                _ => _TutorFlashcards(data: data, reload: reload),
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          setState(() => _tab = index);
          _loader.currentState?.reload(quiet: true);
        },
        destinations: [
          NavigationDestination(icon: Icon(Icons.style_outlined), selectedIcon: Icon(Icons.style), label: tr('Tutors')),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: tr('Exams')),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: tr('Homework')),
        ],
      ),
    );
  }
}

// ── Flashcards ───────────────────────────────────────────────────────────────

class _TutorFlashcards extends StatelessWidget {
  const _TutorFlashcards({required this.data, required this.reload});
  final _StudentData data;
  final Future<void> Function() reload;

  Future<void> _openConnect(BuildContext context) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ConnectScreen()));
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final pending = data.connections.where((c) => c.str('status') == 'PENDING').toList();
    final tutors = data.tutors;
    return PageBody(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (pending.isNotEmpty) ...[
          Banner2(
            pending.length == 1
                ? tr('Your request to {p0} is waiting for an answer.', {'p0': _name(pending.first)})
                : tr('{p0} requests are waiting for an answer.', {'p0': pending.length}),
            icon: Icons.hourglass_top_rounded,
            color: AppColors.warning,
            action: TextButton(onPressed: () => _openConnect(context), child: Text(tr('View'))),
          ),
          gap12,
        ],
        if (tutors.isEmpty)
          EmptyState(
            icon: Icons.style_outlined,
            title: tr('No tutor yet'),
            message: tr('Enter the invite code your tutor gave you. Their card appears here once they accept.'),
            action: FilledButton.icon(
              onPressed: () => _openConnect(context),
              icon: const Icon(Icons.key_rounded),
              label: Text(tr('Enter invite code')),
            ),
          )
        else
          for (final tutor in tutors) ...[
            _Flashcard(
              tutor: tutor,
              tuitions: data.tuitions.where((t) => t.str('tutor_id') == tutor.str('id')).toList(),
              openWork: _openWork(tutor.str('id')),
              onOpen: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => TutorDetailScreen(tutorId: tutor.str('id'), title: _tutorName(tutor)),
                  ),
                );
                await reload();
              },
            ),
            gap12,
          ],
      ],
    );
  }

  /// Homework still to hand in and exams open now, for one tutor.
  ({int homework, int exams}) _openWork(String tutorId) {
    final homework = data.homeworkRaw
        .where((h) => h.str('tutor_id') == tutorId && !h.flag('is_evaluated') && !h.flag('is_submitted'))
        .length;
    final exams = data.exams.where((e) => e.str('tutor') == tutorId && !e.flag('has_submission') && e.flag('can_submit')).length;
    return (homework: homework, exams: exams);
  }

  static String _name(Json connection) =>
      connection.str('tutor_display_name').isNotEmpty ? connection.str('tutor_display_name') : connection.str('tutor_name');
}

String _tutorName(Json tutor) {
  final name = tutor.str('display_name');
  return name.isNotEmpty ? name : tutor.str('username');
}

/// One tutor at a glance: who, what, how far the current cycle has got, and
/// whether anything needs attention. Tap for everything else.
class _Flashcard extends StatelessWidget {
  const _Flashcard({required this.tutor, required this.tuitions, required this.openWork, required this.onOpen});
  final Json tutor;
  final List<Json> tuitions;
  final ({int homework, int exams}) openWork;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = _tutorName(tutor);
    final photo = context.read<Session>().api.mediaUrl(tutor.str('profile_picture_url', tutor.str('profile_picture')));
    final subjects = {
      for (final t in tuitions)
        if (t.str('subject').isNotEmpty) t.str('subject'),
    };
    final pendingCycles = [
      for (final t in tuitions)
        for (final p in t.maps('pending_payments')) p.integer('cycle_number'),
    ];
    final now = DateTime.now();
    final next = nextClass(tuitions, now);
    final main = tuitions.isEmpty ? null : tuitions.first;
    final cycle = main?.obj('active_cycle');
    final done = cycle?.integer('completed_classes') ?? 0;
    final total = cycle?.integer('total_classes') ?? main?.integer('cycle_length') ?? 0;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A thin accent along the top makes each card read as a card in a deck.
            Container(height: 4, color: pendingCycles.isEmpty ? context.tt.primary : context.tt.warning),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: context.tt.primaryContainer,
                        child: ClipOval(
                          child: SizedBox.square(
                            dimension: 44,
                            child: photo.isEmpty
                                ? Center(child: InitialAvatar(name, radius: 22))
                                : Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, _, _) => InitialAvatar(name, radius: 22)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                            Text(
                              [
                                if (subjects.isNotEmpty) subjects.join(', '),
                                if (tuitions.isNotEmpty) tuitions.map((t) => t.str('title')).join(' · ') else tr('Not in a tuition yet'),
                              ].join(' — '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                    ],
                  ),
                  if (main != null) ...[
                    gap16,
                    Row(
                      children: [
                        ProgressRing(done: done, total: total, size: 84, thickness: 9, caption: tr('classes')),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('{p0}/{p1} classes done', {'p0': done, 'p1': total}), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              Text(
                                tr('Cycle #{p0}{p1}', {'p0': cycle?.integer('cycle_number') ?? 1, 'p1': tuitions.length > 1 ? ' · ${main.str('title')}' : ''}),
                                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                              ),
                              if (next != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      Icon(Icons.schedule_rounded, size: 14, color: tone(context, AppColors.primarySoft)),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          tuitions.length > 1
                                              ? tr('Next: {when} · {title}', {'when': whenLabel(next.at, now), 'title': next.tuition.str('title')})
                                              : tr('Next: {when}', {'when': whenLabel(next.at, now)}),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tone(context, AppColors.primarySoft)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (openWork.exams > 0)
                                    Pill(tr('{p0} exam{p1} open', {'p0': openWork.exams, 'p1': openWork.exams == 1 ? '' : 's'}), color: AppColors.success, icon: Icons.quiz_outlined),
                                  if (openWork.homework > 0)
                                    Pill(tr('{p0} homework', {'p0': openWork.homework}), color: AppColors.primarySoft, icon: Icons.menu_book_outlined),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // A second or third tuition with the same tutor: one slim line each.
                    for (final other in tuitions.skip(1)) ...[
                      gap12,
                      _MiniProgress(tuition: other),
                    ],
                  ],
                  if (pendingCycles.isNotEmpty) ...[
                    gap12,
                    _PaymentPendingChip(cycles: pendingCycles),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniProgress extends StatelessWidget {
  const _MiniProgress({required this.tuition});
  final Json tuition;

  @override
  Widget build(BuildContext context) {
    final cycle = tuition.obj('active_cycle');
    final done = cycle?.integer('completed_classes') ?? 0;
    final total = cycle?.integer('total_classes') ?? tuition.integer('cycle_length');
    return Row(
      children: [
        Expanded(child: Text(tuition.str('title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        const SizedBox(width: 8),
        SizedBox(width: 80, child: ProgressLine(value: total == 0 ? 0.0 : done / total, height: 4)),
        const SizedBox(width: 8),
        Text('$done/$total', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// "Payment pending · Cycle #2" — a reminder only; nothing is ever blocked.
class _PaymentPendingChip extends StatelessWidget {
  const _PaymentPendingChip({required this.cycles});
  final List<int> cycles;

  @override
  Widget build(BuildContext context) {
    final ink = tone(context, AppColors.warning);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: context.tt.warningContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('Payment pending for cycle {p0}', {'p0': cycles.map((n) => '#$n').join(', ')}),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink),
            ),
          ),
        ],
      ),
    );
  }
}
