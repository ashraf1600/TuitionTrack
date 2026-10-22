import 'package:flutter/material.dart';

/// Colour tokens from the calm redesign handoff (`d` = dark theme, `l` = light).
/// Every text token clears WCAG AA (4.5:1) on the surface it sits on.
class TtColors {
  // Dark
  static const dBackground = Color(0xFF10151B);
  static const dSurface = Color(0xFF161C24);
  static const dCard = Color(0xFF1C242E);
  static const dCardRaised = Color(0xFF232C38);
  static const dBorder = Color(0xFF2C3542);
  static const dTextPrimary = Color(0xFFE7EBF0);
  static const dTextSecond = Color(0xFFA7B2BF);
  static const dTextTertiary = Color(0xFF8A94A1);
  static const dPrimary = Color(0xFF7FA9D8);
  static const dOnPrimary = Color(0xFF0E1319);
  static const dPrimaryCont = Color(0xFF22303F);
  static const dOnPrimaryCont = Color(0xFFA8C8E8);
  static const dSuccess = Color(0xFF74C79A);
  static const dSuccessCont = Color(0xFF1B2E25);
  static const dWarning = Color(0xFFE0B468);
  static const dWarningCont = Color(0xFF342B1B);
  static const dDanger = Color(0xFFE18C86);
  static const dDangerCont = Color(0xFF3A2422);
  static const dChartEarned = Color(0xFF5EB489);
  static const dChartTrack = Color(0xFF2A3442);
  // "This week" markers (handoff §4).
  static const dPastDayFill = Color(0xFF1E2630);
  static const dDotUpcoming = Color(0xFF4A5765);
  static const dDotPast = Color(0xFF333F4C);

  // Light
  static const lBackground = Color(0xFFF4F1EC);
  static const lSurface = Color(0xFFFBF9F6);
  static const lCard = Color(0xFFFFFCF8);
  static const lCardRaised = Color(0xFFEDF1F6);
  static const lBorder = Color(0xFFE6E1D8);
  static const lTextPrimary = Color(0xFF262B33);
  static const lTextSecond = Color(0xFF5A6472);
  static const lTextTertiary = Color(0xFF646D7B);
  static const lPrimary = Color(0xFF35648F);
  static const lOnPrimary = Color(0xFFFFFCF8);
  static const lPrimaryCont = Color(0xFFE4EBF2);
  static const lOnPrimaryCont = Color(0xFF27506F);
  static const lSuccess = Color(0xFF246B4D);
  static const lSuccessCont = Color(0xFFE0EDE5);
  static const lOnSuccessCont = Color(0xFF1F6248);
  static const lWarning = Color(0xFF8A6316);
  static const lWarningCont = Color(0xFFF7ECD8);
  static const lOnWarningCont = Color(0xFF7A5610);
  static const lDanger = Color(0xFFA8453E);
  // Not in the handoff table: the light counterpart of dDangerCont (lDanger on it is 5.0:1).
  static const lDangerCont = Color(0xFFF6E3E0);
  static const lChartEarned = Color(0xFF2E8A63);
  static const lChartTrack = Color(0xFFE7E2D9);
  // Light versions of the "This week" markers, picked to match the light mockup.
  static const lPastDayFill = Color(0xFFECE8E1);
  static const lDotUpcoming = Color(0xFF8C95A1);
  static const lDotPast = Color(0xFFC2C8D0);

  // Bronze for the leaderboard's third place (gold = warning, silver = text secondary).
  static const bronze = Color(0xFFB87A45);
}

/// The tokens for the current theme: `context.tt.cardRaised`, `context.tt.textTertiary`…
/// Use these instead of fixed colours so both themes stay right.
@immutable
class TtTokens extends ThemeExtension<TtTokens> {
  const TtTokens({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.card,
    required this.cardRaised,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.chartEarned,
    required this.chartTrack,
    required this.pastDayFill,
    required this.dotUpcoming,
    required this.dotPast,
  });

  final bool isDark;
  final Color background, surface, card, cardRaised, border;
  final Color textPrimary, textSecondary, textTertiary;
  final Color primary, onPrimary, primaryContainer, onPrimaryContainer;
  final Color success, successContainer, onSuccessContainer;
  final Color warning, warningContainer, onWarningContainer;
  final Color danger, dangerContainer;
  final Color chartEarned, chartTrack;
  final Color pastDayFill, dotUpcoming, dotPast;

  /// Dark theme has no shadows (depth comes from tonal layers); light gets one soft shadow.
  List<BoxShadow> get cardShadow =>
      isDark ? const [] : const [BoxShadow(color: Color(0x0D262B33), blurRadius: 2, offset: Offset(0, 1))];

  static const dark = TtTokens(
    isDark: true,
    background: TtColors.dBackground,
    surface: TtColors.dSurface,
    card: TtColors.dCard,
    cardRaised: TtColors.dCardRaised,
    border: TtColors.dBorder,
    textPrimary: TtColors.dTextPrimary,
    textSecondary: TtColors.dTextSecond,
    textTertiary: TtColors.dTextTertiary,
    primary: TtColors.dPrimary,
    onPrimary: TtColors.dOnPrimary,
    primaryContainer: TtColors.dPrimaryCont,
    onPrimaryContainer: TtColors.dOnPrimaryCont,
    success: TtColors.dSuccess,
    successContainer: TtColors.dSuccessCont,
    onSuccessContainer: TtColors.dSuccess,
    warning: TtColors.dWarning,
    warningContainer: TtColors.dWarningCont,
    onWarningContainer: TtColors.dWarning,
    danger: TtColors.dDanger,
    dangerContainer: TtColors.dDangerCont,
    chartEarned: TtColors.dChartEarned,
    chartTrack: TtColors.dChartTrack,
    pastDayFill: TtColors.dPastDayFill,
    dotUpcoming: TtColors.dDotUpcoming,
    dotPast: TtColors.dDotPast,
  );

  static const light = TtTokens(
    isDark: false,
    background: TtColors.lBackground,
    surface: TtColors.lSurface,
    card: TtColors.lCard,
    cardRaised: TtColors.lCardRaised,
    border: TtColors.lBorder,
    textPrimary: TtColors.lTextPrimary,
    textSecondary: TtColors.lTextSecond,
    textTertiary: TtColors.lTextTertiary,
    primary: TtColors.lPrimary,
    onPrimary: TtColors.lOnPrimary,
    primaryContainer: TtColors.lPrimaryCont,
    onPrimaryContainer: TtColors.lOnPrimaryCont,
    success: TtColors.lSuccess,
    successContainer: TtColors.lSuccessCont,
    onSuccessContainer: TtColors.lOnSuccessCont,
    warning: TtColors.lWarning,
    warningContainer: TtColors.lWarningCont,
    onWarningContainer: TtColors.lOnWarningCont,
    danger: TtColors.lDanger,
    dangerContainer: TtColors.lDangerCont,
    chartEarned: TtColors.lChartEarned,
    chartTrack: TtColors.lChartTrack,
    pastDayFill: TtColors.lPastDayFill,
    dotUpcoming: TtColors.lDotUpcoming,
    dotPast: TtColors.lDotPast,
  );

  @override
  TtTokens copyWith() => this;

  // The two themes are swapped whole, never animated between token by token.
  @override
  TtTokens lerp(ThemeExtension<TtTokens>? other, double t) => t < 0.5 || other is! TtTokens ? this : other;
}

extension TtContext on BuildContext {
  /// The redesign tokens of the current theme.
  TtTokens get tt => Theme.of(this).extension<TtTokens>() ?? TtTokens.dark;
}

/// Text for buttons, tabs and chips. Material gives them no font of their own,
/// so without this they fall back to the phone's system font (and Bangla on
/// buttons would not match the rest of the app).
TextStyle uiText(double size, FontWeight weight) =>
    TextStyle(fontSize: size, fontWeight: weight, fontFamily: 'HankenGrotesk', fontFamilyFallback: const ['HindSiliguri']);

/// Tabular figures, so times and counts line up in columns.
const tabular = [FontFeature.tabularFigures()];

/// Type scale (handoff §2). Bangla gets a taller line box.
TextTheme ttTextTheme(Color primary, Color secondary, {bool isBangla = false}) {
  final b = isBangla ? 1.55 : 1.45; // body
  final t = isBangla ? 1.40 : 1.30; // titles
  return TextTheme(
    displaySmall: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.6, color: primary),
    titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: t, letterSpacing: -0.2, color: primary),
    titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: isBangla ? 1.45 : 1.35, color: primary),
    bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: b, color: primary),
    // The default style for any Text without its own: primary ink, so plain
    // text never turns grey. Help text sets textSecondary explicitly.
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: isBangla ? 1.55 : 1.50, color: primary),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.40, color: secondary),
    labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.40),
    labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.40, color: secondary),
    labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.40, color: secondary),
  );
}

/// The app theme for both modes. Notes on the colour scheme roles, chosen so
/// existing screens keep their meaning:
/// - `surface` is the card colour (screens paint cards and grouped lists with it);
///   bars and sheets get the `surface` token through their component themes.
/// - `surfaceContainerHighest` is cardRaised: fills nested inside a card.
/// - `outline` is the hairline border; `outlineVariant` is the tertiary ink
///   used for faint icons and hints.
ThemeData ttTheme({required bool isDark, bool isBangla = false}) {
  final tt = isDark ? TtTokens.dark : TtTokens.light;
  final scheme = ColorScheme(
    brightness: isDark ? Brightness.dark : Brightness.light,
    primary: tt.primary,
    onPrimary: tt.onPrimary,
    primaryContainer: tt.primaryContainer,
    onPrimaryContainer: tt.onPrimaryContainer,
    secondary: tt.success,
    onSecondary: tt.background,
    // Selected segments and tonal buttons.
    secondaryContainer: tt.primaryContainer,
    onSecondaryContainer: tt.onPrimaryContainer,
    tertiary: tt.warning,
    onTertiary: tt.background,
    tertiaryContainer: tt.warningContainer,
    onTertiaryContainer: tt.onWarningContainer,
    error: tt.danger,
    onError: tt.background,
    errorContainer: tt.dangerContainer,
    onErrorContainer: tt.danger,
    surface: tt.card,
    onSurface: tt.textPrimary,
    onSurfaceVariant: tt.textSecondary,
    surfaceDim: tt.background,
    surfaceBright: tt.cardRaised,
    surfaceContainerLowest: tt.background,
    surfaceContainerLow: tt.surface,
    surfaceContainer: tt.surface,
    surfaceContainerHigh: tt.card,
    surfaceContainerHighest: tt.cardRaised,
    surfaceTint: Colors.transparent,
    outline: tt.border,
    outlineVariant: tt.textTertiary,
    inverseSurface: tt.textPrimary,
    onInverseSurface: tt.background,
    inversePrimary: isDark ? TtColors.lPrimary : TtColors.dPrimary,
    shadow: isDark ? Colors.transparent : const Color(0x14262B33),
    scrim: Colors.black54,
  );
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: tt.border),
  );
  final textTheme = ttTextTheme(tt.textPrimary, tt.textSecondary, isBangla: isBangla);
  return ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
    extensions: [tt],
    scaffoldBackgroundColor: tt.background,
    // Screens slide and fade in (Android's own motion) instead of the older zoom.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
    canvasColor: tt.background,
    fontFamily: 'HankenGrotesk',
    fontFamilyFallback: const ['HindSiliguri'],
    textTheme: textTheme,
    iconTheme: IconThemeData(color: tt.textSecondary),
    appBarTheme: AppBarTheme(
      backgroundColor: tt.background,
      foregroundColor: tt.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      titleTextStyle: textTheme.titleLarge!.copyWith(fontFamily: 'HankenGrotesk', fontFamilyFallback: const ['HindSiliguri']),
      iconTheme: IconThemeData(color: tt.textPrimary),
      actionsIconTheme: IconThemeData(color: tt.textSecondary),
    ),
    cardTheme: CardThemeData(
      color: tt.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shadowColor: scheme.shadow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: tt.border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tt.cardRaised,
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(borderSide: BorderSide(color: tt.primary, width: 1.5)),
      errorBorder: fieldBorder.copyWith(borderSide: BorderSide(color: tt.danger)),
      focusedErrorBorder: fieldBorder.copyWith(borderSide: BorderSide(color: tt.danger, width: 1.5)),
      labelStyle: TextStyle(color: tt.textSecondary),
      floatingLabelStyle: TextStyle(color: tt.primary),
      hintStyle: TextStyle(color: tt.textTertiary),
      helperStyle: TextStyle(color: tt.textSecondary),
      errorStyle: TextStyle(color: tt.danger),
      prefixIconColor: tt.textTertiary,
      suffixIconColor: tt.textTertiary,
      helperMaxLines: 3,
      errorMaxLines: 3,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: uiText(14, FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: tt.textPrimary,
        side: BorderSide(color: tt.border),
        textStyle: uiText(14, FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    // Size(48, 48), not fromHeight: a full-width minimum would break text buttons inside rows.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: isDark ? tt.onPrimaryContainer : tt.primary,
        textStyle: uiText(14, FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(44, 44))),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        side: WidgetStatePropertyAll(BorderSide(color: tt.border)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? tt.primaryContainer : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? tt.onPrimaryContainer : tt.textSecondary),
        textStyle: WidgetStatePropertyAll(uiText(14, FontWeight.w600)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: tt.primary,
      foregroundColor: tt.onPrimary,
      elevation: isDark ? 0 : 2,
      focusElevation: isDark ? 0 : 2,
      hoverElevation: isDark ? 0 : 3,
      highlightElevation: isDark ? 0 : 3,
      extendedSizeConstraints: const BoxConstraints.tightFor(height: 52),
      extendedTextStyle: uiText(15, FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tt.surface,
      surfaceTintColor: Colors.transparent,
      height: 64,
      elevation: 0,
      indicatorColor: tt.primaryContainer,
      indicatorShape: const StadiumBorder(),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? tt.onPrimaryContainer : tt.textSecondary),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? tt.primary : tt.textSecondary,
        ),
      ),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: tt.surface, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: tt.textPrimary,
      contentTextStyle: uiText(14, FontWeight.w500).copyWith(color: tt.background),
      actionTextColor: scheme.inversePrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tt.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tt.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: tt.textTertiary,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tt.cardRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tt.primaryContainer,
      selectedColor: tt.primaryContainer,
      labelStyle: uiText(12, FontWeight.w600).copyWith(color: tt.onPrimaryContainer),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: tt.textTertiary,
      minVerticalPadding: 10,
      minTileHeight: 56,
      titleTextStyle: textTheme.bodyLarge,
      subtitleTextStyle: TextStyle(fontSize: 13, height: 1.4, color: tt.textSecondary),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tt.chartEarned,
      linearTrackColor: tt.chartTrack,
      circularTrackColor: tt.chartTrack,
      linearMinHeight: 8,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: tt.textPrimary,
      unselectedLabelColor: tt.textSecondary,
      indicatorColor: tt.primary,
      dividerColor: tt.border,
      labelStyle: uiText(14, FontWeight.w600),
      unselectedLabelStyle: uiText(14, FontWeight.w500),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? tt.onPrimary : tt.textTertiary),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? tt.primary : tt.cardRaised),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? tt.primary : tt.border),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? tt.primary : Colors.transparent),
      checkColor: WidgetStatePropertyAll(tt.onPrimary),
      side: BorderSide(color: tt.textTertiary, width: 1.5),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? tt.primary : tt.textTertiary),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: tt.primary, selectionHandleColor: tt.primary),
  );
}
