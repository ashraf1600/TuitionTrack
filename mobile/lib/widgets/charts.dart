import 'package:flutter/material.dart';

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
      label: '$done of $total${caption == null ? '' : ' $caption'} done',
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
              color: color,
              backgroundColor: scheme.surfaceContainerHighest,
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
                          TextSpan(text: '$done', style: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurface)),
                          TextSpan(text: '/$total', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
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
        color: color,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        semanticsLabel: label,
      ),
    );
  }
}
