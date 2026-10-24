import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/api.dart';
import '../../core/app_keys.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/reminder_plan.dart';
import '../../core/reminders.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/ui.dart';
import '../student/tutor_detail_screen.dart';
import '../tutor/tuition_screen.dart';
import 'chat_screen.dart';
import 'cycle_progress.dart';

/// What happens when a phone notification, or its "Mark done" button, is tapped.
Future<void> handleNotificationResponse(Session session, NotificationResponse response) async {
  if (!session.signedIn) return;
  Json payload;
  try {
    final decoded = jsonDecode(response.payload ?? '{}');
    payload = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  } catch (_) {
    payload = <String, dynamic>{};
  }
  final repo = Repo(session.api, outbox: session.outbox);
  final type = payload.str('type');

  if (response.actionId == Reminders.markActionId && session.isTutor) {
    await markNextClassFromReminder(repo, session, payload.str('tuition'));
    return;
  }

  // A plain tap opens the screen the notification is about.
  String tuitionId = (type == 'mark' || type == 'tuition') ? payload.str('tuition') : '';
  String tutorId = type == 'tutor' ? payload.str('tutor') : '';
  final link = payload.str('link');
  final tuitionLink = RegExp(r'^/tuitions/([0-9a-f-]{36})').firstMatch(link);
  final tutorLink = RegExp(r'tutor=([0-9a-f-]{36})').firstMatch(link);
  if (tuitionLink != null) tuitionId = tuitionLink[1]!;
  if (tutorLink != null) tutorId = tutorLink[1]!;

  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) return;
  final chatLink = RegExp(r'^/chats/([0-9a-f-]{36})').firstMatch(link);
  if (chatLink != null) {
    await navigator.push(MaterialPageRoute<void>(builder: (_) => ChatScreen(conversationId: chatLink[1]!)));
    return;
  }
  if (session.isTutor && tuitionId.isNotEmpty) {
    await navigator.push(MaterialPageRoute<void>(builder: (_) => TuitionScreen(tuitionId: tuitionId)));
  } else if (session.isStudent && tutorId.isNotEmpty) {
    await navigator.push(MaterialPageRoute<void>(builder: (_) => TutorDetailScreen(tutorId: tutorId, title: tr('Your tutor'))));
  }
}

/// Records the next class of a tuition from the "Mark done" button, unless a
/// class is already recorded for today, and offers Undo.
Future<void> markNextClassFromReminder(Repo repo, Session session, String tuitionId) async {
  final messenger = rootMessengerKey.currentState;
  if (tuitionId.isEmpty) return;
  try {
    final tuition = await repo.tuition(tuitionId);
    final title = tuition.str('title');
    if (classRecordedOn(tuition, DateTime.now())) {
      showToastOn(messenger, tr("{title}: today's class is already marked.", {'title': title}));
      return;
    }
    final cycle = tuition.obj('active_cycle');
    final next = cycle == null ? null : orderedClasses(cycle).where((c) => !c.flag('completed')).firstOrNull;
    if (next == null) {
      showToastOn(messenger, tr('{title}: no class left to mark in this cycle.', {'title': title}));
      return;
    }
    final classNo = classNoOf(next);
    final result = await repo.markClass(tuitionId, classNo, true, tuitionTitle: title);
    session.api.dataVersion.value++;
    showToastOn(
      messenger,
      classMarkedMessage(result, classNo, title),
      actionLabel: tr('Undo'),
      onAction: () async {
        try {
          await repo.undoMarkClass(tuitionId, classNo, true, result);
          session.api.dataVersion.value++;
          showToastOn(rootMessengerKey.currentState, tr('Class {n} unmarked.', {'n': classNo}));
        } on ApiException catch (error) {
          showToastOn(rootMessengerKey.currentState, error.message, error: true);
        }
      },
    );
  } on ApiException catch (error) {
    showToastOn(messenger, error.message, error: true);
  }
}

/// The message after a class is marked, saying when it started a new cycle or waits to be sent.
String classMarkedMessage(Json result, int classNo, String title) {
  final finished = result['completed_cycle_number'];
  if (result['queued'] == true) return tr('Saved on this phone. It will be sent when you are back online.');
  if (finished is num) {
    return tr('Class {n} marked. Cycle #{done} is complete and cycle #{next} has started.',
        {'n': classNo, 'done': finished.toInt(), 'next': finished.toInt() + 1});
  }
  return title.isEmpty ? tr('Class {n} marked done.', {'n': classNo}) : tr('Class {n} of {title} marked done.', {'n': classNo, 'title': title});
}
