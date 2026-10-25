import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/tt_logo.dart';
import '../../widgets/update_banner.dart';
import '../common/notifications.dart';
import 'home_tab.dart';
import 'student_form_screen.dart';
import 'students_tab.dart';
import 'tuition_form_screen.dart';
import 'tuitions_tab.dart';
import 'wallet_tab.dart';

/// The tutor's app in four tabs: Overview (what to do now), Tuitions (cards;
/// homework and exams live inside each tuition), Wallet (money) and Students.
class TutorHome extends StatefulWidget {
  const TutorHome({super.key});

  @override
  State<TutorHome> createState() => _TutorHomeState();
}

class _TutorHomeState extends State<TutorHome> {
  int _tab = 0;
  // Bumped after something is created, so the visible tab reloads.
  int _version = 0;

  static const _titles = ['Overview', 'Tuitions', 'Wallet', 'Students'];

  Future<void> _create(Widget screen) async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => screen));
    if (changed == true && mounted) setState(() => _version++);
  }

  Future<void> _newTuition() => _create(const TuitionFormScreen());

  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      0 => HomeTab(key: ValueKey('home$_version'), onCreateTuition: _newTuition),
      1 => TuitionsTab(key: ValueKey('tuitions$_version'), onCreateTuition: _newTuition),
      2 => WalletTab(key: ValueKey('wallet$_version')),
      _ => StudentsTab(key: ValueKey('students$_version')),
    };
    return Scaffold(
      appBar: AppBar(
        title: _tab == 0 ? const TtWordmark(size: 20, center: false) : Text(tr(_titles[_tab])),
        centerTitle: false,
        actions: homeActions(context),
      ),
      drawer: const AppDrawer(),
      body: Column(children: [const OfflineBanner(), const UpdateBanner(), Expanded(child: body)]),
      floatingActionButton: switch (_tab) {
        1 => FloatingActionButton.extended(onPressed: _newTuition, icon: const Icon(Icons.add), label: Text(tr('Tuition'))),
        3 => FloatingActionButton.extended(
            onPressed: () => _create(const StudentFormScreen()),
            icon: const Icon(Icons.add),
            label: Text(tr('Student')),
          ),
        _ => null,
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.space_dashboard_outlined), selectedIcon: const Icon(Icons.space_dashboard), label: tr('Overview')),
          NavigationDestination(icon: const Icon(Icons.grid_view_outlined), selectedIcon: const Icon(Icons.grid_view_rounded), label: tr('Tuitions')),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: const Icon(Icons.account_balance_wallet),
            label: tr('Wallet'),
          ),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: tr('Students')),
        ],
      ),
    );
  }
}
