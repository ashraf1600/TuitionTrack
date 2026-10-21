import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../theme/tt_theme.dart';

/// The TuitionTrack mark: a rounded blue tile with a progress ring (classes
/// completed so far) and a check mark inside it. The amber dot at the end of
/// the ring is the next class.
///
/// The same drawing is used for the launcher icon and the phone's
/// notification icon (see mobile/tool/make_icons.py), so the app looks the
/// same everywhere.
class TtMarkPainter extends CustomPainter {
  const TtMarkPainter({this.arc = 1, this.check = 1, this.spin, this.tile = true});

  /// How much of the ring is drawn, 0..1 (the finished ring covers 82%).
  final double arc;

  /// How much of the check mark is drawn, 0..1.
  final double check;

  /// When set (0..1), the ring is a short arc travelling around it: the loading look.
  final double? spin;
  final bool tile;

  static const _tileTop = Color(0xFF5C95CB);
  static const _tileBottom = Color(0xFF2B5680);
  static const _amber = Color(0xFFF2B84B);
  static const _center = Offset(0.5, 0.5);
  static const _radius = 0.27;
  static const _stroke = 0.075;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas
      ..save()
      ..translate((size.width - side) / 2, (size.height - side) / 2)
      ..scale(side); // from here on, everything is drawn in a 1 x 1 square

    if (tile) {
      final shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_tileTop, _tileBottom],
      ).createShader(const Rect.fromLTWH(0, 0, 1, 1));
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 1, 1), const Radius.circular(0.28)),
        Paint()..shader = shader,
      );
    }

    final ringRect = Rect.fromCircle(center: _center, radius: _radius);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(_center, _radius, line..color = Colors.white.withValues(alpha: 0.28));

    final double start;
    final double sweep;
    if (spin != null) {
      start = -math.pi / 2 + spin! * 2 * math.pi;
      sweep = 0.3 * 2 * math.pi;
    } else {
      start = -math.pi / 2;
      sweep = 0.82 * 2 * math.pi * arc;
    }
    if (sweep > 0.001) {
      canvas.drawArc(ringRect, start, sweep, false, line..color = Colors.white);
      if (spin != null || arc > 0.02) {
        final head = start + sweep;
        canvas.drawCircle(
          _center + Offset(math.cos(head), math.sin(head)) * _radius,
          0.045,
          Paint()..color = _amber,
        );
      }
    }

    if (check > 0) {
      final path = Path()
        ..moveTo(0.385, 0.51)
        ..lineTo(0.47, 0.595)
        ..lineTo(0.625, 0.415);
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * check),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.085
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TtMarkPainter old) => old.arc != arc || old.check != check || old.spin != spin || old.tile != tile;
}

/// The logo. With [animate] the ring and the check mark draw themselves once.
class TtLogo extends StatefulWidget {
  const TtLogo({super.key, this.size = 64, this.animate = false});
  final double size;
  final bool animate;

  @override
  State<TtLogo> createState() => _TtLogoState();
}

class _TtLogoState extends State<TtLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = !widget.animate || MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'TuitionTrack',
      image: true,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: still
            ? const CustomPaint(painter: TtMarkPainter())
            : AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value;
                  final pop = Curves.easeOutBack.transform(const Interval(0, 0.4).transform(t));
                  return Transform.scale(
                    scale: 0.82 + 0.18 * pop,
                    child: CustomPaint(
                      painter: TtMarkPainter(
                        arc: Curves.easeOutCubic.transform(const Interval(0.1, 0.75).transform(t)),
                        check: Curves.easeOut.transform(const Interval(0.5, 1).transform(t)),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// The loading animation: the logo breathes while the ring's arc travels around it
/// and the check mark draws in. Used while the app starts and while a sleeping
/// server wakes up.
class TtLoader extends StatefulWidget {
  const TtLoader({super.key, this.size = 72});
  final double size;

  @override
  State<TtLoader> createState() => _TtLoaderState();
}

class _TtLoaderState extends State<TtLoader> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void dispose() {
    _spin.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return Semantics(label: tr('Loading'), child: TtLogo(size: widget.size));
    return Semantics(
      label: tr('Loading'),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_spin, _intro]),
          builder: (context, _) {
            final intro = _intro.value;
            final pop = Curves.easeOutBack.transform(const Interval(0, 0.55).transform(intro));
            final breathe = 1 + 0.025 * math.sin(_spin.value * 2 * math.pi);
            return Opacity(
              opacity: const Interval(0, 0.35).transform(intro),
              child: Transform.scale(
                scale: (0.8 + 0.2 * pop) * breathe,
                child: CustomPaint(
                  painter: TtMarkPainter(
                    spin: _spin.value,
                    check: Curves.easeOut.transform(const Interval(0.35, 1).transform(intro)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// "TuitionTrack" in the brand's two weights.
class TtWordmark extends StatelessWidget {
  const TtWordmark({super.key, this.size = 28, this.center = true});
  final double size;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Tuition', style: TextStyle(fontWeight: FontWeight.w500, color: tt.textPrimary)),
          TextSpan(text: 'Track', style: TextStyle(fontWeight: FontWeight.w800, color: tt.primary)),
        ],
      ),
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontSize: size, height: 1.1, letterSpacing: -size * 0.02),
    );
  }
}

/// The whole-screen wait: the animated logo above the name.
class TtSplash extends StatelessWidget {
  const TtSplash({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TtLoader(size: 104),
            const SizedBox(height: 22),
            const TtWordmark(size: 32),
            if (message != null) ...[
              const SizedBox(height: 10),
              Text(message!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: tt.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}
