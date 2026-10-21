import 'package:flutter/material.dart';

import '../theme/tt_theme.dart';

export '../theme/tt_theme.dart';

/// Accent names the screens use, now pointing at the calm redesign tokens
/// (lib/theme/tt_theme.dart). The values are the DARK theme tokens; [tone]
/// gives the light-theme counterpart for text and icons. New code should
/// prefer `context.tt` (theme-aware) over these.
class AppColors {
  static const background = TtColors.dBackground;
  static const surface = TtColors.dSurface;
  static const card = TtColors.dCard;
  static const border = TtColors.dBorder;
  static const muted = TtColors.dTextSecond;
  static const faint = TtColors.dTextTertiary;
  static const text = TtColors.dTextPrimary;
  static const primary = TtColors.dPrimary;
  static const primarySoft = TtColors.dOnPrimaryCont;
  static const success = TtColors.dSuccess;
  static const successDeep = TtColors.lSuccess; // filled buttons with light text
  static const warning = TtColors.dWarning;
  static const warningDeep = TtColors.lWarning; // filled buttons with light text
  static const danger = TtColors.dDanger;
  // No extra hue in the calm palette: "Assignment" is told apart by its label.
  static const purple = TtColors.dTextSecond;

  // Charts: earned / done on a neutral track; the next class uses the primary blue.
  static const chartEarned = TtColors.dChartEarned;
  static const chartPending = TtColors.dPrimary;
}

/// Accent colour readable as text/icon on the current background: the dark
/// token as is in the dark theme, its light-theme counterpart otherwise.
Color tone(BuildContext context, Color accent) {
  if (Theme.of(context).brightness == Brightness.dark) return accent;
  if (accent == AppColors.primarySoft) return TtColors.lOnPrimaryCont;
  if (accent == AppColors.primary) return TtColors.lPrimary;
  if (accent == AppColors.success) return TtColors.lSuccess;
  if (accent == AppColors.warning) return TtColors.lWarning;
  if (accent == AppColors.danger) return TtColors.lDanger;
  if (accent == AppColors.muted) return TtColors.lTextSecond;
  if (accent == AppColors.faint) return TtColors.lTextTertiary;
  if (accent == AppColors.text) return TtColors.lTextPrimary;
  if (accent == AppColors.chartEarned) return TtColors.lChartEarned;
  if (accent == AppColors.border) return TtColors.lBorder;
  if (accent == AppColors.card) return TtColors.lCard;
  if (accent == AppColors.surface) return TtColors.lSurface;
  if (accent == AppColors.background) return TtColors.lBackground;
  return accent;
}
