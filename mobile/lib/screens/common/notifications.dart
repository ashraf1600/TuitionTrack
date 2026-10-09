import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/json.dart';
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
    try {
      final items = await context.read<Repo>().notifications();
      if (mounted) setState(() => _items = items);
    } on ApiException {
      // The bell is not worth an error message; it refreshes again shortly.
    }
  }

  @override
  Widget build(BuildContext context) {
    final seen = context.watch<Session>().settings.getList(_seenKey).toSet();
    final unseen = _items.where((n) => !seen.contains(n.str('id'))).length;
    return IconButton(
      tooltip: unseen == 0 ? 'Notifications' : '$unseen new notifications',
      icon: Badge(isLabelVisible: unseen > 0, label: Text('$unseen'), child: Icon(Icons.notifications_outlined)),
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
        'cycle' => (Icons.event_available_outlined, AppColors.success),
        'open' => (Icons.play_circle_outline, AppColors.success),
        'late' => (Icons.warning_amber_outlined, AppColors.warning),
        'soon' => (Icons.schedule_outlined, AppColors.primarySoft),
        'result' => (Icons.emoji_events_outlined, AppColors.warning),
        'connection' => (Icons.handshake_outlined, AppColors.primarySoft),
        _ => (Icons.notifications_outlined, AppColors.faint),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Notifications')),
      body: widget.items.isEmpty
          ? Padding(
              padding: EdgeInsets.all(16),
              child: EmptyState(icon: Icons.notifications_none, title: 'Nothing new', message: 'You are all caught up.'),
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
                  leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color)),
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
  final session = context.read<Session>();
  return [
    const NotificationBell(),
    IconButton(
      tooltip: 'My account',
      icon: CircleAvatar(
        radius: 15,
        backgroundColor: AppColors.primary.withValues(alpha: 0.3),
        child: Text(
          session.displayName.isEmpty ? '?' : session.displayName[0].toUpperCase(),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primarySoft),
        ),
      ),
      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
    ),
    const SizedBox(width: 4),
  ];
}
