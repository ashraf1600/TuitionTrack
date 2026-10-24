import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../core/reminders.dart';
import '../../core/repo.dart';
import '../../core/session.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import 'account_screen.dart';

const _seenKey = 'seen_notifications';

/// The bell in the app bar, with a count of notifications not yet opened.
/// Notifications are worked out by the server from the current state of things;
/// this device only remembers which ones the user has already seen.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> with WidgetsBindingObserver {
  List<Json> _items = const [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final settings = context.read<Session>().settings;
    try {
      final items = await context.read<Repo>().notifications();
      if (mounted) setState(() => _items = items);
      // New ones also go to the phone's notification shade.
      await Reminders.instance.announce(settings, items);
    } on ApiException {
      // The bell is not worth an error message; it refreshes again shortly.
    }
  }

  @override
  Widget build(BuildContext context) {
    final seen = context.watch<Session>().settings.getList(_seenKey).toSet();
    final unseen = _items.where((n) => !seen.contains(n.str('id'))).length;
    return IconButton(
      tooltip: unseen == 0 ? tr('Notifications') : tr('{p0} new notifications', {'p0': unseen}),
      icon: Badge(
        isLabelVisible: unseen > 0,
        backgroundColor: context.tt.warning,
        textColor: context.tt.background,
        label: Text(localDigits('$unseen')),
        child: Icon(Icons.notifications_outlined, color: context.tt.textSecondary),
      ),
      onPressed: () async {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => NotificationsScreen(items: _items)));
        if (mounted) {
          setState(() {});
          _load();
        }
      },
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.items});
  final List<Json> items;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final Set<String> _wasSeen;

  @override
  void initState() {
    super.initState();
    final settings = context.read<Session>().settings;
    _wasSeen = settings.getList(_seenKey).toSet();
    // Opening the list is what marks everything in it as seen. Keep only ids that still exist.
    settings.setList(_seenKey, widget.items.map((n) => n.str('id')).toList());
  }

  static (IconData, Color) _look(String kind) => switch (kind) {
        'request' => (Icons.person_add_alt_1_outlined, AppColors.primarySoft),
        'grade' => (Icons.rate_review_outlined, AppColors.warning),
        'class' => (Icons.task_alt_outlined, AppColors.success),
        'cycle' => (Icons.event_available_outlined, AppColors.success),
        'open' => (Icons.play_circle_outline, AppColors.success),
        'late' => (Icons.warning_amber_outlined, AppColors.warning),
        'soon' => (Icons.schedule_outlined, AppColors.primarySoft),
        'result' => (Icons.emoji_events_outlined, AppColors.warning),
        'connection' => (Icons.handshake_outlined, AppColors.primarySoft),
        'payment' => (Icons.payments_outlined, AppColors.warning),
        'homework' => (Icons.menu_book_outlined, AppColors.primarySoft),
        _ => (Icons.notifications_outlined, AppColors.faint),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Notifications'))),
      body: widget.items.isEmpty
          ? Padding(
              padding: EdgeInsets.all(16),
              child: EmptyState(icon: Icons.notifications_none, title: tr('Nothing new'), message: tr('You are all caught up.')),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: widget.items.length,
              separatorBuilder: (_, _) => Divider(indent: 68),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final (icon, color) = _look(item.str('kind'));
                final when = item.date('when');
                final body = item.str('body');
                // "closes" / "opens" style bodies describe the time shown after them.
                final timeWords = ['closes', 'opens', 'late work accepted until'].contains(body);
                final detail = [
                  if (body.isNotEmpty && !timeWords) body,
                  if (when != null) timeWords ? '$body ${fmtDateTime(when)}' : timeAgo(when),
                ].join(' · ');
                final isNew = !_wasSeen.contains(item.str('id'));
                return ListTile(
                  leading: CircleAvatar(backgroundColor: tonalContainer(context, color), child: Icon(icon, color: tone(context, color))),
                  title: Text(item.str('title'), style: TextStyle(fontWeight: isNew ? FontWeight.w700 : FontWeight.w500)),
                  subtitle: detail.isEmpty ? null : Text(detail, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  trailing: isNew ? const Icon(Icons.circle, size: 10, color: AppColors.primary) : null,
                );
              },
            ),
    );
  }
}

/// Bell + account button, shared by the tutor and student home screens.
List<Widget> homeActions(BuildContext context) {
  return [
    const NotificationBell(),
    IconButton(
      tooltip: tr('My account'),
      // Watches the session so a new or removed photo shows up straight away.
      icon: Consumer<Session>(
        builder: (context, s, _) => PersonAvatar(name: s.displayName, photo: s.user?.str('profile_picture_url'), radius: 16),
      ),
      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
    ),
    const SizedBox(width: 4),
  ];
}
