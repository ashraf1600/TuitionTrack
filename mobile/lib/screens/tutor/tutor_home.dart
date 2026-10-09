import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../common/notifications.dart';
import 'exam_editor_screen.dart';
import 'exams_view.dart';
import 'group_form_screen.dart';
import 'groups_tab.dart';
import 'home_tab.dart';
import 'homework_tab.dart';
import 'student_form_screen.dart';
import 'students_tab.dart';

/// The tutor's app: overview and wallet, tuition groups, students, homework, and exams.
class TutorHome extends StatefulWidget {
  const TutorHome({super.key});

  @override
  State<TutorHome> createState() => _TutorHomeState();
}

class _TutorHomeState extends State<TutorHome> {
  int _tab = 0;
  // Bumped after something is created from the + button, so the visible tab reloads.
  int _version = 0;

  static const _titles = ['Overview', 'Tuition groups', 'Students', 'Homework', 'Exams & assignments'];

  Future<void> _create() async {
    final Widget screen = switch (_tab) {
      2 => const StudentFormScreen(),
      3 => const HomeworkCreateScreen(),
      4 => const ExamEditorScreen(),
      _ => const GroupFormScreen(),
    };
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => screen));
    if (changed == true && mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final body = switch (_tab) {
      0 => HomeTab(key: ValueKey('home$_version'), onOpenTab: (index) => setState(() => _tab = index)),
      1 => GroupsTab(key: ValueKey('groups$_version')),
      2 => StudentsTab(key: ValueKey('students$_version')),
      3 => HomeworkTab(key: ValueKey('homework$_version')),
      _ => ExamsView(key: ValueKey('exams$_version')),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Hello, ${session.displayName}' : _titles[_tab]),
        actions: homeActions(context),
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(switch (_tab) { 2 => 'Add student', 3 => 'Assign homework', 4 => 'New exam', _ => 'New group' }),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Groups'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Students'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Homework'),
          NavigationDestination(icon: Icon(Icons.quiz_outlined), selectedIcon: Icon(Icons.quiz), label: 'Exams'),
        ],
      ),
    );
  }
}
