import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/session.dart';
import 'theme.dart';

/// A thin strip under the app bar that says when the app is working from what
/// is saved on the phone, how many changes are waiting to be sent, and which
/// ones the server refused. Shows nothing when all is well.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    return ValueListenableBuilder<bool>(
      valueListenable: session.api.offline,
      builder: (context, offline, _) => ListenableBuilder(
        listenable: session.outbox,
        builder: (context, _) {
          final waiting = session.outbox.length;
          final failures = session.outbox.failures;
          final changes = waiting == 1 ? tr('1 change') : tr('{n} changes', {'n': waiting});
          return AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (failures.isNotEmpty)
                  _Strip(
                    color: AppColors.danger,
                    icon: Icons.error_outline,
                    message: failures.length == 1 ? failures.first : tr('{p0} changes could not be saved.', {'p0': failures.length}),
                    action: TextButton(
                      onPressed: () async {
                        if (failures.length > 1) {
                          await showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(tr('Not saved')),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [for (final f in failures) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(f))],
                              ),
                              actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('OK')))],
                            ),
                          );
                        }
                        session.outbox.clearFailures();
                      },
                      child: Text(failures.length > 1 ? tr('View') : tr('Dismiss')),
                    ),
                  ),
                if (offline)
                  _Strip(
                    color: AppColors.warning,
                    icon: Icons.cloud_off_outlined,
                    message: waiting == 0
                        ? tr('You\'re offline. Showing what\'s saved on this phone.')
                        : tr('You\'re offline. {p0} will be sent when you\'re back online.', {'p0': changes}),
                    action: TextButton(onPressed: session.api.checkConnection, child: Text(tr('Retry'))),
                  )
                else if (waiting > 0)
                  _Strip(
                    color: AppColors.primarySoft,
                    icon: Icons.cloud_upload_outlined,
                    message: tr('Sending {p0} made offline…', {'p0': changes}),
                    action: TextButton(onPressed: session.syncPending, child: Text(tr('Send now'))),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.color, required this.icon, required this.message, this.action});
  final Color color;
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ink = tone(context, color);
    return Material(
      color: color.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: ink),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600))),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}
