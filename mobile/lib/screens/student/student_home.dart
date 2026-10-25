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
import '../../widgets/offline_banner.dart';
import '../../widgets/tt_logo.dart';
import '../../widgets/ui.dart';
import '../../widgets/update_banner.dart';
import '../common/notifications.dart';
import 'connect_screen.dart';
import 'student_lists.dart';
import 'student_today.dart';
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

/// The student's app: Home (what's on now, each tutor as a card — tap one for
/// their subjects, routine and classes done), then every test and every piece
/// of homework across tutors on the other two tabs.
class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  final _loader = GlobalKey<LoaderState<_StudentData>>();
  StudentTab _tab = StudentTab.home;
  bool _showResults = false;
  int _examCount = 0;
  int _homeworkCount = 0;

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
    // Homework reminders for the coming week (they work offline). No class reminders for students.
    unawaited(Reminders.instance.schedule(settings, studentReminders(results[4], DateTime.now())));
    if (mounted) {
      final now = context.read<Session>().api.serverNow;
      setState(() {
        _examCount = pendingExamCount(results[3], now);
        _homeworkCount = pendingHomeworkCount(homework);
      });
    }
    return _StudentData(results[0], results[1], results[2], results[3], homework, results[4]);
  }

  void _open(StudentTab tab, {bool results = false}) {
    setState(() {
      _tab = tab;
      _showResults = results;
    });
    _loader.currentState?.reload(quiet: true);
  }

  Future<void> _openTutor(String tutorId, String name) async {
    if (tutorId.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => TutorDetailScreen(tutorId: tutorId, title: name.isEmpty ? tr('Tutor') : name)),
    );
    await _loader.currentState?.reload(quiet: true);
  }

  Future<void> _openConnect() async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ConnectScreen()));
    await _loader.currentState?.reload(quiet: true);
  }

  Widget? _title() => switch (_tab) {
        StudentTab.home => const TtWordmark(size: 20, center: false),
        StudentTab.tests => Text(tr('Tests & results')),
        StudentTab.homework => Text(tr('Homework')),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: _title(), centerTitle: false, actions: homeActions(context)),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          const OfflineBanner(),
          const UpdateBanner(),
          Expanded(
            child: Loader<_StudentData>(
              key: _loader,
              load: _load,
              builder: (context, data, reload) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                child: KeyedSubtree(
                  key: ValueKey(_tab),
                  child: switch (_tab) {
                    StudentTab.home => StudentTodayView(
                        tutors: data.tutors,
                        tuitions: data.tuitions,
                        connections: data.connections,
                        exams: data.exams,
                        homework: data.homework,
                        reload: reload,
                        onOpenTab: _open,
                        onOpenTutor: _openTutor,
                        onConnect: _openConnect,
                      ),
                    StudentTab.tests => StudentExamsList(
                        key: ValueKey('tests-$_showResults'),
                        exams: data.exams,
                        reload: reload,
                        initialView: _showResults ? ExamsView.results : null,
                      ),
                    StudentTab.homework => StudentHomeworkList(items: data.homework, reload: reload),
                  },
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (index) => _open(StudentTab.values[index]),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: tr('Home')),
          // Red counts: tests and homework still waiting, so a tap shows what is due.
          NavigationDestination(
            icon: countBadge(const Icon(Icons.quiz_outlined), _examCount),
            selectedIcon: countBadge(const Icon(Icons.quiz_rounded), _examCount),
            label: tr('Tests'),
          ),
          NavigationDestination(
            icon: countBadge(const Icon(Icons.menu_book_outlined), _homeworkCount),
            selectedIcon: countBadge(const Icon(Icons.menu_book_rounded), _homeworkCount),
            label: tr('Homework'),
          ),
        ],
      ),
    );
  }
}
