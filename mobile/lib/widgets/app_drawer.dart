import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n.dart';
import '../core/reminders.dart';
import '../core/session.dart';
import '../screens/common/account_screen.dart';
import '../screens/common/payments_screen.dart';
import '../screens/student/connect_screen.dart';
import 'theme.dart';
import 'ui.dart';

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
        title: Text(tr('Server address')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('The address of your TuitionTrack server, for example https://tuitiontrack.example.com or http://192.168.0.10:8000 on your own network.'),
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            gap12,
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(labelText: tr('Server address')),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(tr('Save'))),
        ],
      ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;
    await session.setServer(url);
    if (!context.mounted) return;
    await attempt(context, () => context.read<Session>().api.get('/meta/'), success: tr('Connected to the server.'));
  }

  Future<void> _openFacebook(BuildContext context) async {
    HapticFeedback.lightImpact();
    final uri = Uri.tryParse(facebookPageUrl);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) showToast(context, tr('Could not open the Facebook page.'), error: true);
    }
  }

  void _openAbout(BuildContext context) {
    HapticFeedback.lightImpact();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.school_rounded, color: AppColors.primarySoft),
            SizedBox(width: 10),
            Text(tr('About TuitionTrack')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('TuitionTrack helps private tutors run tuitions, track classes and earnings, set exams and homework — and helps students follow their classes, submit work and see results.'),
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            gap12,
            Text(tr('Version {p0}', {'p0': appVersion}), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            Text(tr('Made for tutors, coaching centres and students.'),
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openFacebook(context);
            },
            child: Text(tr('Facebook page')),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
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
                  Text(tr('TuitionTrack'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(
                    '$name · ${session.isTutor ? tr('Tutor') : tr('Student')}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(tr('APPEARANCE'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ),
            SegmentedButton<ThemeMode>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(value: ThemeMode.dark, label: Text(tr('Dark')), icon: Icon(Icons.dark_mode_outlined, size: 16)),
                ButtonSegment(value: ThemeMode.light, label: Text(tr('Light')), icon: Icon(Icons.light_mode_outlined, size: 16)),
              ],
              selected: {session.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (value) {
                HapticFeedback.lightImpact();
                session.setThemeMode(value.first);
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(tr('LANGUAGE'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ),
            SegmentedButton<String>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(value: 'en', label: Text(tr('English'))),
                ButtonSegment(value: 'bn', label: Text('বাংলা')),
              ],
              selected: {session.language},
              showSelectedIcon: false,
              onSelectionChanged: (value) {
                HapticFeedback.lightImpact();
                session.setLanguage(value.first);
              },
            ),
            if (Reminders.instance.available)
              StatefulBuilder(
                builder: (context, setLocal) => SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: Text(tr('Reminders')),
                  subtitle: Text(
                    session.isTutor ? tr('Before and after your classes') : tr('Before classes and homework deadlines'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: Reminders.enabledIn(session.settings),
                  onChanged: (on) async {
                    HapticFeedback.lightImpact();
                    await Reminders.instance.setEnabled(session.settings, on);
                    // Screens set the reminders again when they next load.
                    session.api.dataVersion.value++;
                    setLocal(() {});
                  },
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: Text(tr('My account')),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AccountScreen()));
              },
            ),
            if (session.isStudent)
              ListTile(
                leading: const Icon(Icons.key_rounded),
                title: Text(tr('Connect to a tutor')),
                subtitle: Text(tr('Invite code, requests, find a tutor'), style: TextStyle(fontSize: 12)),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ConnectScreen()));
                },
              ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(session.isTutor ? tr('Payments') : tr('Payment history')),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const PaymentsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(tr('Server address')),
              subtitle: Text(session.api.baseUrl, style: const TextStyle(fontSize: 12)),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                _changeServer(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(tr('About TuitionTrack')),
              onTap: () {
                Navigator.pop(context);
                _openAbout(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.thumb_up_outlined),
              title: Text(tr('Facebook page')),
              subtitle: Text(tr('Follow us for updates'), style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _openFacebook(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: Text(tr('Sign out'), style: TextStyle(color: AppColors.danger)),
              onTap: () async {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                final ok = await confirm(
                  context,
                  title: tr('Sign out?'),
                  message: session.outbox.isEmpty
                      ? tr('You will need your username and password to sign back in.')
                      : tr('{p0} change{p1} not been sent yet. Signing out deletes {p2} from this phone.', {'p0': session.outbox.length, 'p1': session.outbox.length == 1 ? tr(' made offline has') : tr('s made offline have'), 'p2': session.outbox.length == 1 ? tr('it') : tr('them')}),
                  confirmLabel: tr('Sign out'),
                  danger: session.outbox.isNotEmpty,
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
