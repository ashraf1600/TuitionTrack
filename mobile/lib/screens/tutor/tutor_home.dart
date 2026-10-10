import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../common/notifications.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/offline_banner.dart';
import 'exam_editor_screen.dart';
import 'exams_view.dart';
import 'home_tab.dart';
import 'homework_tab.dart';
import 'student_form_screen.dart';
import 'students_tab.dart';
import 'tuition_form_screen.dart';

/// The tutor's app in four tabs. Tuitions live on the Overview, as cards.
class TutorHome extends StatefulWidget {
  const TutorHome({super.key});

  @override
  State<TutorHome> createState() => _TutorHomeState();
}

class _TutorHomeState extends State<TutorHome> {
  int _tab = 0;
  // Bumped after something is created from the + button, so the visible tab reloads.
  int _version = 0;

  static const _titles = ['Overview', 'Students', 'Homework', 'Exams'];

  Future<void> _create() async {
    final Widget screen = switch (_tab) {
      1 => const StudentFormScreen(),
      2 => const HomeworkCreateScreen(),
      3 => const ExamEditorScreen(),
      _ => const TuitionFormScreen(),
    };
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => screen));
    if (changed == true && mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final body = switch (_tab) {
      0 => HomeTab(key: ValueKey('home$_version'), onCreateTuition: _create),
      1 => StudentsTab(key: ValueKey('students$_version')),
      2 => HomeworkTab(key: ValueKey('homework$_version')),
      _ => ExamsView(key: ValueKey('exams$_version')),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Hello, ${session.displayName}' : _titles[_tab]),
        actions: homeActions(context),
      ),
      drawer: const AppDrawer(),
      body: Column(children: [const OfflineBanner(), Expanded(child: body)]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(switch (_tab) { 1 => 'Student', 2 => 'Homework', 3 => 'Exam', _ => 'Tuition' }),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Students'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Homework'),
          NavigationDestination(icon: Icon(Icons.quiz_outlined), selectedIcon: Icon(Icons.quiz), label: 'Exams'),
        ],
      ),
    );
  }
}
