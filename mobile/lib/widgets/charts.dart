import 'package:flutter/material.dart';

import '../core/i18n.dart';
import 'theme.dart';

/// A circular "done of total" meter with the count in the middle (e.g. 10/12).
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.done,
    required this.total,
    this.size = 64,
    this.thickness = 7,
    this.color = AppColors.chartEarned,
    this.caption,
  });

  final int done;
  final int total;
  final double size;
  final double thickness;
  final Color color;

  /// A word under the count, e.g. "classes". Left out on small rings.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Semantics(
      label: tr('{p0} of {p1}{p2} done', {'p0': done, 'p1': total, 'p2': caption == null ? '' : ' $caption'}),
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: value,
              strokeWidth: thickness,
              strokeCap: StrokeCap.round,
              color: tone(context, color),
              backgroundColor: context.tt.chartTrack,
            ),
            Center(
              child: Padding(
                padding: EdgeInsets.all(thickness + 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: localDigits('$done'), style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
                          TextSpan(text: localDigits('/$total'), style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                        ]),
                        style: TextStyle(fontSize: size * 0.24),
                      ),
                      if (caption != null)
                        Text(caption!, style: TextStyle(fontSize: size * 0.11, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A thin rounded progress bar.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, this.color = AppColors.chartEarned, this.height = 6, this.label});
  final double value;
  final Color color;
  final double height;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.isNaN ? 0 : value.clamp(0.0, 1.0),
        minHeight: height,
        color: tone(context, color),
        backgroundColor: context.tt.chartTrack,
        semanticsLabel: label,
      ),
    );
  }
}

/// A stable colour per tuition, shared by its classes, its card and its wallet
/// slice. Never green, amber or red: those mean done/earned, due and late.
const tuitionPalette = [
  Color(0xFF5C95CB), // blue
  Color(0xFF8E7CC3), // violet
  Color(0xFF3FA3A8), // teal
  Color(0xFFC77DAA), // pink
  Color(0xFF6F86D6), // indigo
  Color(0xFFB39A7A), // sand
];

Color tuitionColorOf(String tuitionId) {
  var hash = 0;
  for (final unit in tuitionId.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return tuitionPalette[hash % tuitionPalette.length];
}

/// A pie ring (filled share of [value] out of 1) with anything in the middle.
class RingChart extends StatelessWidget {
  const RingChart({super.key, required this.value, required this.color, required this.center, this.size = 96, this.thickness = 12, this.label});
  final double value;
  final Color color;
  final Widget center;
  final double size;
  final double thickness;

  /// Read by screen readers, e.g. "Taka earned: 7,000 of 12,000".
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      excludeSemantics: label != null,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: value.isNaN ? 0 : value.clamp(0.0, 1.0),
              strokeWidth: thickness,
              color: color,
              backgroundColor: context.tt.chartTrack,
            ),
            Center(
              child: Padding(
                padding: EdgeInsets.all(thickness + 2),
                child: FittedBox(fit: BoxFit.scaleDown, child: center),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
