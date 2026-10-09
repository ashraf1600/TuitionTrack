import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/session.dart';
import 'theme.dart';
import 'ui.dart';
import '../screens/common/account_screen.dart';

/// Change this to the official Facebook page. Used by the drawer's follow link.
const facebookPageUrl = 'https://www.facebook.com/tuitiontrack';
const appVersion = '1.0.0';

/// Left-side menu: appearance (dark/light), account, server, about,
/// Facebook page, and sign out. Add as `drawer:` on home screens —
/// the hamburger button appears automatically.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  Future<void> _changeServer(BuildContext context) async {
    final session = context.read<Session>();
    final controller = TextEditingController(text: session.api.baseUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The address of your TuitionTrack server, for example https://tuitiontrack.example.com or '
              'http://192.168.0.10:8000 on your own network.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            gap12,
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Server address'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;
    await session.setServer(url);
    if (!context.mounted) return;
    await attempt(context, () => context.read<Session>().api.get('/meta/'), success: 'Connected to the server.');
  }

  Future<void> _openFacebook(BuildContext context) async {
    HapticFeedback.lightImpact();
    final uri = Uri.tryParse(facebookPageUrl);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) showToast(context, 'Could not open the Facebook page.', error: true);
    }
  }

  void _openAbout(BuildContext context) {
    HapticFeedback.lightImpact();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.school_rounded, color: AppColors.primarySoft),
            SizedBox(width: 10),
            Text('About TuitionTrack'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TuitionTrack helps private tutors run tuition groups, track classes and earnings, '
              'set exams and homework — and helps students follow their classes, submit work and see results.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            gap12,
            Text('Version $appVersion', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            const Text('Made for tutors, coaching centres and students.',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openFacebook(context);
            },
            child: const Text('Facebook page'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final u = Map<String, dynamic>.from(session.user ?? {});
    final rawName = (u['name'] as String? ?? '').trim();
    final rawUsername = (u['username'] as String? ?? '').trim();
    final name = rawName.isNotEmpty ? rawName : rawUsername;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.school_rounded, size: 40, color: AppColors.primarySoft),
                  gap8,
                  const Text('TuitionTrack', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(
                    '$name · ${session.isTutor ? 'Tutor' : 'Student'}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('APPEARANCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ),
            SegmentedButton<ThemeMode>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined, size: 16)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined, size: 16)),
              ],
              selected: {session.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (value) {
                HapticFeedback.lightImpact();
                session.setThemeMode(value.first);
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('My account'),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AccountScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Server address'),
              subtitle: Text(session.api.baseUrl, style: const TextStyle(fontSize: 12)),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                _changeServer(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About TuitionTrack'),
              onTap: () {
                Navigator.pop(context);
                _openAbout(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.thumb_up_outlined),
              title: const Text('Facebook page'),
              subtitle: const Text('Follow us for updates', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _openFacebook(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: const Text('Sign out', style: TextStyle(color: AppColors.danger)),
              onTap: () async {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                final ok = await confirm(
                  context,
                  title: 'Sign out?',
                  message: 'You will need your username and password to sign back in.',
                  confirmLabel: 'Sign out',
                );
                if (ok) await session.logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}
