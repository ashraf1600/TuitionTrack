import 'package:flutter/material.dart';

/// The same dark slate and indigo palette as the website.
/// Surface/body tokens below are theme-aware — use Theme.of(context).colorScheme
/// (onSurface, onSurfaceVariant, surface, outline…) instead of these in screens.
/// Accent tokens (primary, success, warning, danger) work on both themes as
/// fills and borders; for text/icons on light backgrounds use [tone].
class AppColors {
  static const background = Color(0xFF020617); // slate-950
  static const surface = Color(0xFF0F172A); // slate-900
  static const card = Color(0xFF1E293B); // slate-800
  static const border = Color(0xFF334155); // slate-700
  static const muted = Color(0xFF94A3B8); // slate-400
  static const faint = Color(0xFF64748B); // slate-500
  static const text = Color(0xFFF1F5F9); // slate-100
  static const primary = Color(0xFF6366F1); // indigo-500
  static const primarySoft = Color(0xFFA5B4FC); // indigo-300
  static const success = Color(0xFF34D399); // emerald-400
  static const successDeep = Color(0xFF059669); // emerald-600: filled buttons with white text
  static const warning = Color(0xFFFBBF24); // amber-400
  static const warningDeep = Color(0xFFB45309); // amber-700: filled buttons with white text
  static const danger = Color(0xFFFB7185); // rose-400
  static const purple = Color(0xFFC084FC);
}

/// Accent color readable as text/icon on the current background.
/// Dark theme returns the accent unchanged; light theme returns a deeper
/// shade with proper contrast on white.
Color tone(BuildContext context, Color accent) {
  if (Theme.of(context).brightness == Brightness.dark) return accent;
  if (accent == AppColors.primarySoft) return const Color(0xFF4338CA); // indigo-700
  if (accent == AppColors.primary) return const Color(0xFF4F46E5); // indigo-600
  if (accent == AppColors.success) return const Color(0xFF047857); // emerald-700
  if (accent == AppColors.warning) return const Color(0xFFB45309); // amber-700
  if (accent == AppColors.danger) return const Color(0xFFBE123C); // rose-700
  if (accent == AppColors.muted) return const Color(0xFF64748B); // slate-500
  if (accent == AppColors.faint) return const Color(0xFF64748B); // slate-500
  return accent;
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.success,
    onSecondary: Colors.black,
    // Selected segments and tonal buttons: indigo, like the website's active tabs.
    secondaryContainer: Color(0xFF3730A3),
    onSecondaryContainer: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.muted,
    surfaceContainerHighest: AppColors.card,
    outline: AppColors.border,
    outlineVariant: AppColors.faint,
    error: AppColors.danger,
    onError: Colors.black,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.border),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.card),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.card, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: border.copyWith(borderSide: const BorderSide(color: AppColors.danger)),
      focusedErrorBorder: border.copyWith(borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
      labelStyle: const TextStyle(color: AppColors.muted),
      hintStyle: const TextStyle(color: AppColors.faint),
      helperStyle: const TextStyle(color: AppColors.muted),
      helperMaxLines: 3,
      errorMaxLines: 3,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.primarySoft)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primary.withValues(alpha: 0.25),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.surface, showDragHandle: true),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.card,
      side: const BorderSide(color: AppColors.border),
      labelStyle: const TextStyle(color: AppColors.text, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.muted),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary, linearTrackColor: AppColors.card),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.text,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.primary,
      dividerColor: AppColors.card,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.card),
    ),
  );
}

/// Light theme: same layout and accents, slate-50 pages with white surfaces.
/// Dark-hardcoded screens keep working because shared widgets and body text
/// below read from the color scheme instead of fixed constants.
ThemeData buildLightTheme() {
  const scheme = ColorScheme.light(
    primary: Color(0xFF4F46E5), // indigo-600: readable on white
    onPrimary: Colors.white,
    secondary: Color(0xFF047857), // emerald-700
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE0E7FF), // indigo-100
    onSecondaryContainer: Color(0xFF312E81), // indigo-900
    surface: Colors.white,
    onSurface: Color(0xFF0F172A), // slate-900
    onSurfaceVariant: Color(0xFF64748B), // slate-500
    surfaceContainerHighest: Color(0xFFF1F5F9), // slate-100: nested fills
    outline: Color(0xFFE2E8F0), // slate-200: borders
    outlineVariant: Color(0xFF64748B), // slate-500: faint hints
    error: Color(0xFFBE123C), // rose-700
    onError: Colors.white,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF8FAFC), // slate-50
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF0F172A),
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFF1F5F9), thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5)),
      errorBorder: border.copyWith(borderSide: const BorderSide(color: Color(0xFFBE123C))),
      focusedErrorBorder: border.copyWith(borderSide: const BorderSide(color: Color(0xFFBE123C), width: 1.5)),
      labelStyle: const TextStyle(color: Color(0xFF64748B)),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
      helperStyle: const TextStyle(color: Color(0xFF64748B)),
      helperMaxLines: 3,
      errorMaxLines: 3,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: const Color(0xFF0F172A),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: const Color(0xFF4F46E5))),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFF4F46E5).withValues(alpha: 0.15),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white, showDragHandle: true),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFF1F5F9),
      side: const BorderSide(color: Color(0xFFE2E8F0)),
      labelStyle: const TextStyle(color: Color(0xFF0F172A), fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    listTileTheme: const ListTileThemeData(iconColor: Color(0xFF64748B)),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Color(0xFF4F46E5), linearTrackColor: Color(0xFFF1F5F9)),
    tabBarTheme: const TabBarThemeData(
      labelColor: Color(0xFF0F172A),
      unselectedLabelColor: Color(0xFF64748B),
      indicatorColor: Color(0xFF4F46E5),
      dividerColor: Color(0xFFF1F5F9),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : const Color(0xFF94A3B8)),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0)),
    ),
  );
}
