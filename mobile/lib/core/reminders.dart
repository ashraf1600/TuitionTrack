import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'i18n.dart';
import 'json.dart';
import 'reminder_plan.dart';
import 'session.dart';

/// Phone notifications: class and homework reminders set for later (they
/// work without internet), and the server's notifications shown as they
/// arrive while the app is in use.
class Reminders {
  Reminders._();
  static final instance = Reminders._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Called when a notification (or its "Mark done" button) is tapped while the app runs.
  void Function(NotificationResponse response)? onResponse;

  /// The tap that opened the app, handled once the session is ready.
  NotificationResponse? launchResponse;

  static const markActionId = 'mark_done';
  static const _remindersKey = 'reminders'; // 'on' | 'off'
  static const _askedKey = 'notification_permission_asked';
  static const _notifiedKey = 'notified_ids';
  static const _seededKey = 'notified_seeded';

  bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (_ready || !available) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_stat_tt')),
      onDidReceiveNotificationResponse: (response) => onResponse?.call(response),
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) launchResponse = launch?.notificationResponse;
    _ready = true;
  }

  static bool enabledIn(Settings settings) => settings.getString(_remindersKey) != 'off';

  Future<void> setEnabled(Settings settings, bool on) async {
    await settings.setString(_remindersKey, on ? 'on' : 'off');
    if (!on) await _cancelScheduled();
  }

  /// Asks Android 13+ for permission once; afterwards the phone's settings decide.
  Future<void> _askOnce(Settings settings) async {
    if (settings.getString(_askedKey) == 'yes') return;
    await settings.setString(_askedKey, 'yes');
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  }

  /// Replaces the scheduled reminders with [plan].
  Future<void> schedule(Settings settings, List<PlannedReminder> plan) async {
    if (!_ready) return;
    try {
      if (!enabledIn(settings)) {
        await _cancelScheduled();
        return;
      }
      await _askOnce(settings);
      await _cancelScheduled();
      for (final item in plan) {
        await _plugin.zonedSchedule(
          id: reminderId(item.key),
          scheduledDate: tz.TZDateTime.from(item.at, tz.UTC),
          notificationDetails: _details(classes: true, markAction: item.markAction),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: item.title,
          body: item.body,
          payload: jsonEncode(item.payload),
        );
      }
    } catch (error) {
      // Reminders are a convenience: a phone that refuses them must not break the app.
      debugPrint('Reminders not set: $error');
    }
  }

  Future<void> _cancelScheduled() async {
    if (!_ready) return;
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (pending.id >= 100000 && pending.id < 190000) await _plugin.cancel(id: pending.id);
    }
  }

  /// Shows the server notifications this phone has not shown before. The first
  /// time, everything already there is only remembered, so nobody gets a flood.
  Future<void> announce(Settings settings, List<Json> items) async {
    if (!_ready || !enabledIn(settings)) return;
    try {
      await settings.refresh();
      final shown = settings.getList(_notifiedKey).toSet();
      final ids = [for (final n in items) n.str('id')];
      if (settings.getString(_seededKey) != 'yes') {
        await settings.setString(_seededKey, 'yes');
        await settings.setList(_notifiedKey, ids.take(300).toList());
        return;
      }
      final fresh = items.where((n) => !shown.contains(n.str('id'))).toList();
      if (fresh.isEmpty) return;
      await _askOnce(settings);
      if (fresh.length <= 3) {
        for (final n in fresh) {
          await _plugin.show(
            id: reminderId('server:${n.str('id')}', base: 200000),
            title: n.str('title'),
            body: _bodyOf(n),
            notificationDetails: _details(classes: false),
            payload: jsonEncode({'type': 'server', 'link': n.str('link')}),
          );
        }
      } else {
        await _plugin.show(
          id: reminderId('server:summary', base: 200000),
          title: tr('{n} new updates', {'n': fresh.length}),
          body: fresh.take(3).map((n) => n.str('title')).join(' · '),
          notificationDetails: _details(classes: false),
          payload: jsonEncode({'type': 'server'}),
        );
      }
      await settings.setList(_notifiedKey, [...ids, ...shown.where((id) => !ids.contains(id))].take(300).toList());
    } catch (error) {
      debugPrint('Notification not shown: $error');
    }
  }

  static String _bodyOf(Json n) {
    final body = n.str('body');
    // "opens" / "closes" / "due" describe the time that follows them on the bell screen.
    return const ['opens', 'closes', 'due', 'late work accepted until'].contains(body) ? '' : body;
  }

  NotificationDetails _details({required bool classes, bool markAction = false}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        classes ? 'reminders' : 'updates',
        classes ? tr('Class and homework reminders') : tr('Updates from TuitionTrack'),
        channelDescription: classes ? tr('Before and after your classes, and before homework is due.') : tr('New homework, payments, exams and requests.'),
        icon: '@drawable/ic_stat_tt',
        color: const Color(0xFF3F7CB5),
        importance: Importance.high,
        priority: Priority.high,
        category: classes ? AndroidNotificationCategory.reminder : AndroidNotificationCategory.event,
        actions: markAction ? [AndroidNotificationAction(markActionId, tr('Mark done'), showsUserInterface: true)] : null,
      ),
    );
  }
}
