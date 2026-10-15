import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_info.dart';
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
              style: TextStyle(color: context.tt.textSecondary, fontSize: 14, height: 1.5),
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
            Icon(Icons.school_outlined, color: context.tt.primary),
            const SizedBox(width: 10),
            Flexible(child: Text(tr('About TuitionTrack'))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('TuitionTrack helps private tutors run tuitions, track classes and earnings, set exams and homework — and helps students follow their classes, submit work and see results.'),
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            gap12,
            Text(tr('Version {p0}', {'p0': appVersion}), style: TextStyle(color: context.tt.textTertiary, fontSize: 12)),
            Text(tr('Made for tutors, coaching centres and students.'),
                style: TextStyle(color: context.tt.textTertiary, fontSize: 12)),
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
    final tt = context.tt;
    final u = Map<String, dynamic>.from(session.user ?? {});
    final rawName = (u['name'] as String? ?? '').trim();
    final rawUsername = (u['username'] as String? ?? '').trim();
    final name = rawName.isNotEmpty ? rawName : rawUsername;
    void open(Widget screen) {
      HapticFeedback.lightImpact();
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
    }

    return Drawer(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(20))),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: tt.primaryContainer, borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.school_outlined, size: 24, color: tt.onPrimaryContainer),
                  ),
                  const SizedBox(height: 16),
                  Text(tr('TuitionTrack'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: tt.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    '$name · ${session.isTutor ? tr('Tutor') : tr('Student')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tt.textSecondary, fontSize: 14),
                  ),
                  _SectionLabel(tr('APPEARANCE')),
                  PillToggle<ThemeMode>(
                    options: [
                      (ThemeMode.dark, tr('Dark'), Icons.dark_mode_outlined),
                      (ThemeMode.light, tr('Light'), Icons.light_mode_outlined),
                    ],
                    selected: session.themeMode,
                    onChanged: (mode) {
                      HapticFeedback.lightImpact();
                      session.setThemeMode(mode);
                    },
                  ),
                  _SectionLabel(tr('LANGUAGE')),
                  PillToggle<String>(
                    options: [('en', tr('English'), null), ('bn', 'বাংলা', null)],
                    selected: session.language,
                    onChanged: (code) {
                      HapticFeedback.lightImpact();
                      session.setLanguage(code);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (Reminders.instance.available)
                    StatefulBuilder(
                      builder: (context, setLocal) => SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(Icons.notifications_none_rounded, size: 20, color: tt.textTertiary),
                        title: Text(tr('Reminders')),
                        subtitle: Text(
                          session.isTutor ? tr('Before and after your classes') : tr('Before classes and homework deadlines'),
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
                  Divider(height: 17, color: tt.border),
                  _DrawerItem(
                    icon: Icons.person_outline_rounded,
                    title: tr('My account'),
                    onTap: () => open(const AccountScreen()),
                  ),
                  if (session.isStudent)
                    _DrawerItem(
                      icon: Icons.key_rounded,
                      title: tr('Connect to a tutor'),
                      subtitle: tr('Invite code, requests, find a tutor'),
                      onTap: () => open(const ConnectScreen()),
                    ),
                  _DrawerItem(
                    icon: Icons.receipt_long_outlined,
                    title: session.isTutor ? tr('Payments') : tr('Payment history'),
                    onTap: () => open(const PaymentsScreen()),
                  ),
                  _DrawerItem(
                    icon: Icons.dns_outlined,
                    title: tr('Server address'),
                    subtitle: session.api.baseUrl.replaceFirst(RegExp(r'^https?://'), ''),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                      _changeServer(context);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.info_outline_rounded,
                    title: tr('About TuitionTrack'),
                    onTap: () {
                      Navigator.pop(context);
                      _openAbout(context);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.facebook,
                    title: tr('Facebook page'),
                    subtitle: tr('Follow us for updates'),
                    trailing: Icons.open_in_new_rounded,
                    onTap: () {
                      Navigator.pop(context);
                      _openFacebook(context);
                    },
                  ),
                ],
              ),
            ),
            // Sign out stays at the bottom, after a hairline.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1, color: tt.border),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: _DrawerItem(
                icon: Icons.logout_rounded,
                title: tr('Sign out'),
                color: tt.danger,
                chevron: false,
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
            ),
          ],
        ),
      ),
    );
  }
}

/// Small caps label above a group in the drawer.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.72, color: context.tt.textTertiary),
      ),
    );
  }
}

/// A 56 dp drawer row: tertiary icon, title (and a quiet subtitle), chevron.
class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.color,
    this.trailing = Icons.chevron_right_rounded,
    this.chevron = true,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;
  final IconData trailing;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color ?? tt.textTertiary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: color ?? tt.textPrimary)),
                    if (subtitle != null)
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, height: 1.4, color: tt.textSecondary)),
                  ],
                ),
              ),
              if (chevron) Icon(trailing, size: 20, color: tt.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
