import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/ui.dart';
import 'homework_card.dart';

class _Detail {
  _Detail(this.tutor, this.routines, this.classes, this.homework);
  final Json tutor;
  final List<RoutineSlot> routines;
  final List<ScheduledClass> classes;
  final List<HomeworkItem> homework;
}

/// Phase 3+4: DefaultTabController (Routine / Classes / Homework).
class TutorDetailScreen extends StatefulWidget {
  const TutorDetailScreen({super.key, required this.tutorId, required this.title});
  final String tutorId;
  final String title;

  @override
  State<TutorDetailScreen> createState() => _TutorDetailScreenState();
}

class _TutorDetailScreenState extends State<TutorDetailScreen> {
  final _key = GlobalKey<LoaderState<_Detail>>();

  Future<_Detail> _load() async {
    final repo = context.read<Repo>();
    final d = await repo.tutorDetail(widget.tutorId);
    final routines = ((d['weekly_routine'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => RoutineSlot.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final classes = ((d['upcoming_classes'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ScheduledClass.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final homework = ((d['homework'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => HomeworkItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return _Detail(Map<String, dynamic>.from(d['tutor'] ?? {}), routines, classes, homework);
  }

  @override
  Widget build(BuildContext context) {
    final isTutor = context.watch<Session>().isTutor;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          bottom: const TabBar(tabs: [Tab(text: 'Routine'), Tab(text: 'Classes'), Tab(text: 'Homework')]),
        ),
        body: Loader<_Detail>(
          key: _key,
          load: _load,
          scrollable: false,
          builder: (context, d, reload) => TabBarView(
            children: [
              // Routine tab
              d.routines.isEmpty
                  ? const Center(child: Text('No routine set yet.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: d.routines.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final r = d.routines[i];
                        return AppCard(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                    color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12)),
                                child: Text(r.day.length > 3 ? r.day.substring(0, 3).toUpperCase() : r.day.toUpperCase(),
                                    style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.indigo)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(r.subject.isEmpty ? 'Class' : r.subject,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text('${r.start} – ${r.end}', style: const TextStyle(color: Colors.grey)),
                                ]),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
              // Classes tab
              d.classes.isEmpty
                  ? const Center(child: Text('No upcoming classes.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: d.classes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final c = d.classes[i];
                        return AppCard(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.event_rounded, color: Colors.indigo),
                            title: Text(c.topic.isEmpty ? 'Class' : c.topic,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${c.at.toLocal()}'.substring(0, 16)),
                          ),
                        );
                      },
                    ),
              // Homework tab
              d.homework.isEmpty
                  ? const Center(child: Text('No homework assigned.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: d.homework.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => HomeworkCard(
                        hw: d.homework[i],
                        isTutor: isTutor,
                        onChanged: () => _key.currentState?.reload(),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
