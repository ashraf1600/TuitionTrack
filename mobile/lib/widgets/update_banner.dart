import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_info.dart';
import '../core/i18n.dart';
import '../core/json.dart';
import '../core/repo.dart';
import '../core/session.dart';
import 'theme.dart';
import 'ui.dart';

/// "Version 1.2.0 is available" under the app bar, when the server says a
/// newer APK exists. "Later" hides it until the next version.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  static const _dismissedKey = 'update_dismissed_version';
  // Asked once per app start, not on every screen.
  static Future<Json>? _meta;
  Json? _app;

  @override
  void initState() {
    super.initState();
    _meta ??= context.read<Repo>().meta();
    _meta!.then((meta) {
      if (mounted) setState(() => _app = meta.obj('app'));
    }).catchError((_) {
      _meta = null; // try again next time a home screen opens
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    if (app == null) return const SizedBox.shrink();
    final latest = app.str('latest_version');
    final url = app.str('download_url');
    final settings = context.read<Session>().settings;
    if (latest.isEmpty || url.isEmpty || compareVersions(appVersion, latest) >= 0) return const SizedBox.shrink();
    if (settings.getString(_dismissedKey) == latest) return const SizedBox.shrink();
    final ink = tone(context, AppColors.primarySoft);
    return Material(
      color: AppColors.primary.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(
          children: [
            Icon(Icons.system_update_rounded, size: 18, color: ink),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                app.str('release_notes').isEmpty
                    ? tr('Version {v} is available.', {'v': latest})
                    : tr('Version {v} is available: {notes}', {'v': latest, 'notes': app.str('release_notes')}),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () async {
                await settings.setString(_dismissedKey, latest);
                if (mounted) setState(() {});
              },
              child: Text(tr('Later')),
            ),
            FilledButton.tonal(
              onPressed: () async {
                final uri = Uri.tryParse(url);
                if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                  if (context.mounted) showToast(context, tr('Could not open the download link.'), error: true);
                }
              },
              child: Text(tr('Update')),
            ),
          ],
        ),
      ),
    );
  }
}
