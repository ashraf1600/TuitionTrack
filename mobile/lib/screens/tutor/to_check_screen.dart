import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import 'exams_view.dart';
import 'homework_tab.dart';

/// Everything waiting to be checked across all tuitions: exam answers to
/// grade, and homework handed in.
class ToCheckScreen extends StatelessWidget {
  const ToCheckScreen({super.key, this.initialTab = 0});

  /// 0 = exams to grade, 1 = homework handed in.
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('To check')),
          bottom: TabBar(tabs: [Tab(text: tr('Exams to grade')), Tab(text: tr('Homework'))]),
        ),
        body: const TabBarView(
          children: [
            ExamsView(toGradeOnly: true),
            HomeworkTab(initialFilter: 'handed'),
          ],
        ),
      ),
    );
  }
}
