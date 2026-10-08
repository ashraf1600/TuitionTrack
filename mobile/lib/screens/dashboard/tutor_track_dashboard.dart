import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

// ============================================================================
// 1. THEME CONFIGURATION & THEME PROVIDER
// ============================================================================

class AppGradients {
  static const primary = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const emerald = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const amber = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const rose = LinearGradient(
    colors: [Color(0xFFF43F5E), Color(0xFFE11D48)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const darkSurface = LinearGradient(
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const lightSurface = LinearGradient(
    colors: [Colors.white, Color(0xFFF8FAFC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    HapticFeedback.mediumImpact();
    _themeMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC), // slate-50
      cardColor: Colors.white,
      dividerColor: const Color(0xFFE2E8F0), // slate-200
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF6366F1),
        secondary: Color(0xFF10B981),
        surface: Colors.white,
        onSurface: Color(0xFF0F172A), // slate-900
        outline: Color(0xFFE2E8F0),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF090D16), // deep slate/black
      cardColor: const Color(0xFF1E293B), // slate-900 elevated
      dividerColor: const Color(0xFF334155), // slate-800
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF818CF8),
        secondary: Color(0xFF34D399),
        surface: Color(0xFF1E293B),
        onSurface: Color(0xFFF8FAFC), // slate-50
        outline: Color(0xFF334155),
      ),
    );
  }
}

// ============================================================================
// 2. CUSTOM LEFT NAVIGATION DRAWER
// ============================================================================

class TutorTrackDrawer extends StatelessWidget {
  const TutorTrackDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;
    final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Drawer(
      backgroundColor: bg,
      child: SafeArea(
        child: Column(
          children: [
            // User Profile Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor, width: 1)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2.5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppGradients.primary,
                    ),
                    child: const CircleAvatar(
                      radius: 26,
                      backgroundColor: Color(0xFF1E293B),
                      child: Text(
                        'AK',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ashraf Karim',
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: AppGradients.emerald,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Tutor Pro',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'ashraf@tuitiontrack.app',
                          style: TextStyle(color: textMuted, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Navigation Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                children: [
                  _DrawerTile(
                    icon: Icons.dashboard_rounded,
                    title: 'Dashboard',
                    isSelected: true,
                    isDark: isDark,
                    onTap: () => Navigator.pop(context),
                  ),
                  _DrawerTile(
                    icon: Icons.groups_rounded,
                    title: 'Tuition Batches',
                    isDark: isDark,
                    onTap: () => Navigator.pop(context),
                  ),
                  _DrawerTile(
                    icon: Icons.assignment_rounded,
                    title: 'Exams & Tasks',
                    isDark: isDark,
                    onTap: () => Navigator.pop(context),
                  ),
                  _DrawerTile(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'Wallet Analytics',
                    isDark: isDark,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1),
                  ),
                  _DrawerTile(
                    icon: Icons.settings_rounded,
                    title: 'Settings',
                    isDark: isDark,
                    onTap: () => Navigator.pop(context),
                  ),
                  _DrawerTile(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & Support',
                    isDark: isDark,
                    onTap: () => Navigator.pop(context),
                  ),
                  _DrawerTile(
                    icon: Icons.info_outline_rounded,
                    title: 'About TutorTrack',
                    isDark: isDark,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Theme Toggle & Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderColor, width: 1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                        color: isDark ? const Color(0xFFF59E0B) : const Color(0xFF6366F1),
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isDark ? 'Dark Mode' : 'Light Mode',
                        style: TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Switch.adaptive(
                    value: isDark,
                    activeColor: const Color(0xFF6366F1),
                    onChanged: (_) => themeProvider.toggleTheme(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.title,
    required this.isDark,
    required this.onTap,
    this.isSelected = false,
  });

  final IconData icon;
  final String title;
  final bool isDark;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final activeBg = isDark
        ? const Color(0xFF6366F1).withOpacity(0.18)
        : const Color(0xFF6366F1).withOpacity(0.12);
    final activeText = isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5);
    final idleText = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: isSelected ? activeText : idleText),
              const SizedBox(width: 14),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? activeText : idleText,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 3. MAIN DASHBOARD SCREEN (HERO DONUT CHART, TABS, & COUNTDOWN)
// ============================================================================

class TutorTrackDashboardScreen extends StatefulWidget {
  const TutorTrackDashboardScreen({super.key});

  @override
  State<TutorTrackDashboardScreen> createState() => _TutorTrackDashboardScreenState();
}

class _TutorTrackDashboardScreenState extends State<TutorTrackDashboardScreen> {
  // Gamified Cycle & Financial State
  final int totalClasses = 12;
  int completedClasses = 8;
  final double tuitionFee = 6000.0;

  double get perClassRate => tuitionFee / totalClasses;
  double get earnedRevenue => perClassRate * completedClasses;
  double get pendingRevenue => tuitionFee - earnedRevenue;

  void _toggleClass(int classNumber) {
    HapticFeedback.mediumImpact();
    setState(() {
      if (completedClasses >= classNumber) {
        completedClasses = classNumber - 1;
      } else {
        completedClasses = classNumber;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: scaffoldBg,
      drawer: const TutorTrackDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Icon(Icons.menu_rounded, color: textPrimary, size: 20),
            ),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TutorTrack',
              style: TextStyle(
                color: textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'HSC Higher Math • Batch 2026',
              style: TextStyle(color: textMuted, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: const Icon(Icons.notifications_none_rounded, size: 20),
            ),
            onPressed: () {},
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: DefaultTabController(
        length: 3,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                  child: Column(
                    children: [
                      // 1. HERO GAMIFIED WALLET CARD
                      _GamifiedWalletCard(
                        totalClasses: totalClasses,
                        completedClasses: completedClasses,
                        earnedRevenue: earnedRevenue,
                        pendingRevenue: pendingRevenue,
                        isDark: isDark,
                      ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1, end: 0),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverTabBarDelegate(
                  TabBar(
                    labelColor: isDark ? Colors.white : const Color(0xFF0F172A),
                    unselectedLabelColor: textMuted,
                    indicatorColor: const Color(0xFF6366F1),
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    tabs: const [
                      Tab(text: 'Classes Grid'),
                      Tab(text: 'Routine'),
                      Tab(text: 'Homework'),
                    ],
                  ),
                  isDark: isDark,
                ),
              ),
            ];
          },
          body: TabBarView(
            children: [
              // Tab 1: Interactive Class Grid
              _ClassesGridTab(
                totalClasses: totalClasses,
                completedClasses: completedClasses,
                isDark: isDark,
                onToggle: _toggleClass,
              ),

              // Tab 2: Weekly Schedule Routine
              _RoutineTab(isDark: isDark),

              // Tab 3: Ultra-Attractive Homework Cards
              _HomeworkTab(isDark: isDark),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 4. HERO GAMIFIED WALLET CARD WITH FL_CHART DONUT
// ============================================================================

class _GamifiedWalletCard extends StatelessWidget {
  const _GamifiedWalletCard({
    required this.totalClasses,
    required this.completedClasses,
    required this.earnedRevenue,
    required this.pendingRevenue,
    required this.isDark,
  });

  final int totalClasses;
  final int completedClasses;
  final double earnedRevenue;
  final double pendingRevenue;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final remainingClasses = totalClasses - completedClasses;
    final progressPercent = ((completedClasses / totalClasses) * 100).toInt();

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final shadowColor = isDark ? Colors.black.withOpacity(0.4) : Colors.grey.withOpacity(0.08);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.wallet_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Tuition Cycle Wallet',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Cycle #1',
                  style: TextStyle(
                    color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Donut Chart with Embedded Center Stats
          SizedBox(
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 65,
                    startDegreeOffset: -90,
                    sections: [
                      // Completed section
                      PieChartSectionData(
                        value: completedClasses.toDouble(),
                        color: const Color(0xFF10B981),
                        radius: 18,
                        showTitle: false,
                      ),
                      // Remaining section
                      PieChartSectionData(
                        value: (remainingClasses > 0 ? remainingClasses : 0.01).toDouble(),
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        radius: 14,
                        showTitle: false,
                      ),
                    ],
                  ),
                  swapAnimationDuration: const Duration(milliseconds: 600),
                  swapAnimationCurve: Curves.easeInOutCubic,
                ),
                // Center metrics
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '৳ ${earnedRevenue.toInt()}',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ).animate().scale(delay: 200.ms, duration: 400.ms),
                    const SizedBox(height: 2),
                    Text(
                      'Earned Revenue',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$completedClasses/$totalClasses Classes ($progressPercent%)',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Financial Breakdown Badges
          Row(
            children: [
              Expanded(
                child: _MetricBadge(
                  label: 'Pending Balance',
                  value: '৳ ${pendingRevenue.toInt()}',
                  indicatorColor: const Color(0xFF6366F1),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricBadge(
                  label: 'Rate / Class',
                  value: '৳ ${((pendingRevenue + earnedRevenue) / totalClasses).toInt()}',
                  indicatorColor: const Color(0xFFF59E0B),
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({
    required this.label,
    required this.value,
    required this.indicatorColor,
    required this.isDark,
  });

  final String label;
  final String value;
  final Color indicatorColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withOpacity(0.6) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 3.5, backgroundColor: indicatorColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 5. TAB 1: INTERACTIVE CLASS CHECKOFF GRID
// ============================================================================

class _ClassesGridTab extends StatelessWidget {
  const _ClassesGridTab({
    required this.totalClasses,
    required this.completedClasses,
    required this.isDark,
    required this.onToggle,
  });

  final int totalClasses;
  final int completedClasses;
  final bool isDark;
  final void Function(int classNumber) onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Dynamic Cycle Progress',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            Text(
              'Tap box to toggle class',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.1,
          ),
          itemCount: totalClasses,
          itemBuilder: (context, index) {
            final classNo = index + 1;
            final isCompleted = classNo <= completedClasses;

            return GestureDetector(
              onTap: () => onToggle(classNo),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  gradient: isCompleted ? AppGradients.emerald : null,
                  color: isCompleted
                      ? null
                      : (isDark ? const Color(0xFF1E293B) : Colors.white),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isCompleted
                        ? const Color(0xFF10B981)
                        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    width: 1.5,
                  ),
                  boxShadow: isCompleted
                      ? [
                          BoxShadow(
                            color: const Color(0xFF10B981).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      color: isCompleted
                          ? Colors.white
                          : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                      size: 20,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Class $classNo',
                      style: TextStyle(
                        color: isCompleted
                            ? Colors.white
                            : (isDark ? Colors.white : const Color(0xFF0F172A)),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ============================================================================
// 6. TAB 2: WEEKLY SCHEDULE ROUTINE
// ============================================================================

class _RoutineTab extends StatelessWidget {
  const _RoutineTab({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final routines = [
      {'day': 'Saturday', 'time': '06:00 PM - 07:30 PM', 'topic': 'Calculus: Integration & Areas'},
      {'day': 'Monday', 'time': '06:00 PM - 07:30 PM', 'topic': 'Conics: Parabola & Ellipse'},
      {'day': 'Wednesday', 'time': '07:30 PM - 09:00 PM', 'topic': 'Vector Analysis & Dot Products'},
    ];

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: routines.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final r = routines[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: AppGradients.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.calendar_today_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r['day']!,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      r['time']!,
                      style: const TextStyle(
                        color: Color(0xFF818CF8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      r['topic']!,
                      style: TextStyle(
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// 7. TAB 3: ULTRA-ATTRACTIVE HOMEWORK CARDS WITH LIVE COUNTDOWN
// ============================================================================

class _HomeworkTab extends StatelessWidget {
  const _HomeworkTab({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        // Urgent Homework (Less than 2 hours left)
        _HomeworkCard(
          title: 'Differentiation & Chain Rule Worksheet 04',
          subject: 'Higher Math',
          assignedDate: 'Assigned Yesterday',
          remainingDuration: const Duration(hours: 1, minutes: 45),
          isSubmitted: false,
          isDark: isDark,
        ),
        const SizedBox(height: 16),

        // Upcoming Homework (3 days left)
        _HomeworkCard(
          title: 'Conic Sections Derivations & MCQ Set',
          subject: 'Higher Math 2nd Paper',
          assignedDate: 'Assigned 2 Days Ago',
          remainingDuration: const Duration(days: 3, hours: 4),
          isSubmitted: false,
          isDark: isDark,
        ),
        const SizedBox(height: 16),

        // Already Evaluated Homework
        _HomeworkCard(
          title: 'Vector Products & Cross Multiplication',
          subject: 'Higher Math 1st Paper',
          assignedDate: 'Assigned Last Week',
          remainingDuration: Duration.zero,
          isSubmitted: true,
          isEvaluated: true,
          tutorFeedback: 'Excellent handwriting and clear derivations in Q3!',
          isDark: isDark,
        ),
      ],
    );
  }
}

class _HomeworkCard extends StatelessWidget {
  const _HomeworkCard({
    required this.title,
    required this.subject,
    required this.assignedDate,
    required this.remainingDuration,
    required this.isSubmitted,
    required this.isDark,
    this.isEvaluated = false,
    this.tutorFeedback,
  });

  final String title;
  final String subject;
  final String assignedDate;
  final Duration remainingDuration;
  final bool isSubmitted;
  final bool isDark;
  final bool isEvaluated;
  final String? tutorFeedback;

  @override
  Widget build(BuildContext context) {
    final isUrgent = remainingDuration.inHours < 2 && remainingDuration > Duration.zero;

    final cardBg = isDark
        ? const Color(0xFF1E293B).withOpacity(0.7)
        : Colors.white.withOpacity(0.9);
    final borderColor = isDark
        ? const Color(0xFF334155).withOpacity(0.7)
        : const Color(0xFFE2E8F0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withOpacity(0.3) : Colors.grey.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Subject Tag + Glowing Countdown Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      subject,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5),
                      ),
                    ),
                  ),

                  // Glowing Live Countdown Badge
                  if (!isSubmitted && remainingDuration > Duration.zero)
                    _GlowingCountdownBadge(
                      duration: remainingDuration,
                      isUrgent: isUrgent,
                    )
                  else if (isEvaluated)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Evaluated',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Title
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),

              Text(
                assignedDate,
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  fontSize: 12,
                ),
              ),

              // Optional Tutor Feedback
              if (tutorFeedback != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.comment_rounded, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tutorFeedback!,
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Action Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: isEvaluated
                        ? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
                        : const Color(0xFF6366F1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    isEvaluated ? 'View Submission' : 'Submit Solution (Link/File)',
                    style: TextStyle(
                      color: isEvaluated
                          ? (isDark ? Colors.white : const Color(0xFF0F172A))
                          : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowingCountdownBadge extends StatelessWidget {
  const _GlowingCountdownBadge({
    required this.duration,
    required this.isUrgent,
  });

  final Duration duration;
  final bool isUrgent;

  @override
  Widget build(BuildContext context) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final text = hours > 0
        ? '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m left'
        : '${minutes}m left';

    final glowColor = isUrgent ? const Color(0xFFF43F5E) : const Color(0xFF10B981);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: glowColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: glowColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(isUrgent ? 0.45 : 0.25),
            blurRadius: isUrgent ? 10 : 6,
            spreadRadius: isUrgent ? 1 : 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, color: glowColor, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: glowColor,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 8. PERSISTENT SLIVER TAB BAR DELEGATE
// ============================================================================

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate(this._tabBar, {required this.isDark});

  final TabBar _tabBar;
  final bool isDark;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final bg = isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC);
    return Container(
      color: bg,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}
