import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// One slice of a [DonutChart].
class DonutSlice {
  const DonutSlice({required this.label, required this.value, required this.color, this.display});
  final String label;
  final double value;
  final Color color;

  /// The value as shown in the legend (e.g. "৳ 4,000"). Defaults to the number.
  final String? display;
}

/// A ring chart with its legend beside it (or below on narrow screens).
///
/// Slices are separated by a small gap so neighbouring colours never touch,
/// the legend names every slice so meaning never rests on colour alone, and
/// the centre carries the headline figure.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    this.centerValue,
    this.centerLabel,
    this.size = 148,
    this.thickness = 18,
    this.semanticsLabel,
  });

  final List<DonutSlice> slices;
  final String? centerValue;
  final String? centerLabel;
  final double size;
  final double thickness;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = slices.fold<double>(0, (sum, s) => sum + (s.value > 0 ? s.value : 0));
    final ring = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(
          slices: slices,
          total: total,
          thickness: thickness,
          track: scheme.surfaceContainerHighest,
          gapColor: scheme.surface,
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(thickness + 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (centerValue != null)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(centerValue!, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: scheme.onSurface)),
                  ),
                if (centerLabel != null)
                  Text(centerLabel!, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      Text(
                        s.display ?? s.value.toStringAsFixed(0),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: scheme.onSurface),
                      ),
                      if (total > 0)
                        Text('${(s.value / total * 100).round()}%', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    return Semantics(
      label: semanticsLabel ??
          slices.map((s) => '${s.label}: ${s.display ?? s.value.toStringAsFixed(0)}').join(', '),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < size + 130) {
            return Column(children: [ring, const SizedBox(height: 12), legend]);
          }
          return Row(children: [ring, const SizedBox(width: 20), Expanded(child: legend)]);
        },
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.total, required this.thickness, required this.track, required this.gapColor});
  final List<DonutSlice> slices;
  final double total;
  final double thickness;
  final Color track;
  final Color gapColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(thickness / 2, thickness / 2, size.width - thickness, size.height - thickness);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (total <= 0) return;
    final shown = slices.where((s) => s.value > 0).toList();
    // About 2 px of surface between slices, measured along the ring.
    final gap = shown.length > 1 ? 2.5 / (rect.width / 2) : 0.0;
    var start = -math.pi / 2;
    for (final s in shown) {
      final sweep = s.value / total * math.pi * 2;
      final drawn = sweep - gap;
      if (drawn > 0) canvas.drawArc(rect, start + gap / 2, drawn, false, paint..color = s.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.total != total || old.slices != slices || old.track != track || old.thickness != thickness || old.gapColor != gapColor;
}

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
