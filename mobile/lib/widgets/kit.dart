import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/i18n.dart';
import 'theme.dart';
import 'ui.dart';

/// The design kit of the redesigned screens: one hero card for the most
/// important thing, stat tiles, section headers with "See all", a week strip,
/// segmented filters and list rows. Built on the theme tokens (context.tt),
/// so both themes and both languages stay right.

/// Staggered entrance for the blocks of a page: each block fades and rises a
/// little after the one before. Skipped when the phone asks for less motion.
Widget entrance(BuildContext context, Widget child, int index) {
  if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
  return child
      .animate(delay: Duration(milliseconds: 40 * index.clamp(0, 8)))
      .fadeIn(duration: 280.ms, curve: Curves.easeOut)
      .moveY(begin: 10, end: 0, duration: 320.ms, curve: Curves.easeOutCubic);
}

/// Wraps each of [children] in [entrance], in order.
List<Widget> staggered(BuildContext context, List<Widget> children) =>
    [for (final (i, child) in children.indexed) entrance(context, child, i)];

// ── Page header ──────────────────────────────────────────────────────────────

/// "FRIDAY, 23 OCTOBER" over "Good evening, Rafi": the top of a home tab.
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({super.key, required this.name, required this.now, this.subtitle});
  final String name;
  final DateTime now;
  final String? subtitle;

  static String greeting(DateTime now) {
    final h = now.hour;
    if (h < 5) return tr('Good night');
    if (h < 12) return tr('Good morning');
    if (h < 17) return tr('Good afternoon');
    if (h < 21) return tr('Good evening');
    return tr('Good night');
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final first = name.trim().split(RegExp(r'\s+')).first;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            longDate(now).toUpperCase(),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: tt.textTertiary),
          ),
          const SizedBox(height: 4),
          Text(
            first.isEmpty ? greeting(now) : tr('{greeting}, {name}', {'greeting': greeting(now), 'name': Raw(first)}),
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.5, color: tt.textPrimary),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(fontSize: 14, color: tt.textSecondary)),
          ],
        ],
      ),
    );
  }
}

const _monthsEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _monthsBn = ['জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'];
const _weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _weekdaysBn = ['সোমবার', 'মঙ্গলবার', 'বুধবার', 'বৃহস্পতিবার', 'শুক্রবার', 'শনিবার', 'রবিবার'];
const _shortEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _shortBn = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহঃ', 'শুক্র', 'শনি', 'রবি'];

/// "Friday, 23 October" (in the app language).
String longDate(DateTime d) => isBangla
    ? '${_weekdaysBn[d.weekday - 1]}, ${localDigits('${d.day}')} ${_monthsBn[d.month - 1]}'
    : '${_weekdaysEn[d.weekday - 1]}, ${d.day} ${_monthsEn[d.month - 1]}';

/// "Mon" (in the app language).
String shortWeekday(DateTime d) => (isBangla ? _shortBn : _shortEn)[d.weekday - 1];

// ── Hero ─────────────────────────────────────────────────────────────────────

/// The one thing that matters most right now, on a tinted card with a clear action.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.icon = Icons.bolt_rounded,
    this.accent = AppColors.primary,
    this.action,
    this.meta = const [],
    this.live = false,
    this.onTap,
  });

  /// Small caps line above the title: "LIVE NOW", "NEXT CLASS".
  final String eyebrow;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final Widget? action;

  /// Small facts under the title (pills).
  final List<Widget> meta;

  /// Pulses the eyebrow dot (an exam open right now).
  final bool live;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final ink = tone(context, accent);
    final dark = tt.isDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: dark ? const [] : [BoxShadow(color: ink.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Material(
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        color: tt.card,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [ink.withValues(alpha: dark ? 0.26 : 0.16), ink.withValues(alpha: dark ? 0.06 : 0.03)],
              ),
              border: Border.all(color: ink.withValues(alpha: dark ? 0.28 : 0.20)),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Stack(
              children: [
                // The card's icon in a tinted badge, top right.
                Positioned(
                  right: 16,
                  top: 16,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: ink.withValues(alpha: dark ? 0.16 : 0.12), borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, size: 22, color: ink),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _Dot(color: ink, pulse: live),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              eyebrow.toUpperCase(),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: ink),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(right: 48),
                        child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.3, color: tt.textPrimary),
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!, style: TextStyle(fontSize: 14, color: tt.textSecondary)),
                      ],
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(spacing: 6, runSpacing: 6, children: meta),
                      ],
                      if (action != null) ...[const SizedBox(height: 16), SizedBox(width: double.infinity, child: action!)],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.pulse});
  final Color color;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final dot = Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
    if (!pulse || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) return dot;
    return SizedBox.square(
      dimension: 8,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color.withValues(alpha: 0.5), shape: BoxShape.circle))
              .animate(onPlay: (c) => c.repeat())
              .scaleXY(begin: 1, end: 2.6, duration: 1400.ms, curve: Curves.easeOut)
              .fadeOut(duration: 1400.ms),
          dot,
        ],
      ),
    );
  }
}

// ── Stats ────────────────────────────────────────────────────────────────────

/// A small tappable figure: icon, number, label. Three of these sit in a row.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.value, required this.label, this.accent = AppColors.primarySoft, this.onTap});
  final IconData icon;
  final String value;
  final String label;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: tonalContainer(context, accent), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: tone(context, accent)),
          ),
          const SizedBox(height: 12),
          Text(value,
              maxLines: 1,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.1, color: tt.textPrimary, fontFeatures: tabular)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: tt.textSecondary)),
        ],
      ),
    );
  }
}

/// Equal-width tiles in one row with even gaps.
class TileRow extends StatelessWidget {
  const TileRow({super.key, required this.children, this.gap = 10});
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(child: child),
          ],
        ],
      ),
    );
  }
}

// ── Sections ─────────────────────────────────────────────────────────────────

/// A section heading with an optional "See all" link on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction, this.count});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Shown in a small bubble after the title.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Row(
        children: [
          Flexible(
            child: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: tt.textPrimary)),
          ),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(color: tt.cardRaised, borderRadius: BorderRadius.circular(10)),
              child: Text(localDigits('$count'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tt.textSecondary)),
            ),
          ],
          const Spacer(),
          if (onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(minimumSize: const Size(40, 36), padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel ?? tr('See all')),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A row inside a card: tinted icon tile, title and subtitle, something on the right.
class KitRow extends StatelessWidget {
  const KitRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.accent = AppColors.primarySoft,
    this.onTap,
    this.dense = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color accent;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final size = dense ? 36.0 : 42.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 12),
        child: Row(
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: tonalContainer(context, accent), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: dense ? 18 : 20, color: tone(context, accent)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tt.textPrimary)),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: tt.textSecondary)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Several [KitRow]s on one card with hairlines between them.
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) Divider(height: 1, indent: 66, endIndent: 12, color: tt.border.withValues(alpha: 0.7)),
            child,
          ],
        ],
      ),
    );
  }
}

// ── Filters ──────────────────────────────────────────────────────────────────

/// Pill tabs with counts: "To do 3 · Upcoming 1 · Results 4".
class SegmentTabs<T> extends StatelessWidget {
  const SegmentTabs({super.key, required this.options, required this.selected, required this.onChanged});

  /// (value, label, count)
  final List<(T, String, int?)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: tt.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: tt.border)),
      child: Row(
        children: [
          for (final (value, label, count) in options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (value == selected) return;
                  HapticFeedback.selectionClick();
                  onChanged(value);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  height: 40,
                  decoration: BoxDecoration(
                    color: value == selected ? tt.primaryContainer : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: value == selected ? FontWeight.w700 : FontWeight.w500,
                            color: value == selected ? tt.onPrimaryContainer : tt.textSecondary,
                          ),
                        ),
                      ),
                      if (count != null && count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: value == selected ? tt.primary : tt.cardRaised,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            localDigits('$count'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: value == selected ? tt.onPrimary : tt.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Progress ─────────────────────────────────────────────────────────────────

/// A rounded bar that grows into place.
class GrowBar extends StatelessWidget {
  const GrowBar({super.key, required this.value, this.color, this.height = 8});
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: tt.chartTrack),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: v),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, x, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: x,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: color ?? tt.chartEarned, borderRadius: BorderRadius.circular(height)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A coloured initial in a rounded square: a subject's badge.
class InitialTile extends StatelessWidget {
  const InitialTile(this.text, {super.key, this.size = 42, this.seed});
  final String text;
  final double size;

  /// Picks the colour; the same seed always gets the same colour.
  final String? seed;

  static const _hues = [210.0, 150.0, 32.0, 280.0, 350.0, 185.0];

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final key = seed ?? text;
    final hue = _hues[key.codeUnits.fold<int>(0, (a, b) => a + b) % _hues.length];
    final bg = HSLColor.fromAHSL(1, hue, tt.isDark ? 0.30 : 0.45, tt.isDark ? 0.22 : 0.90).toColor();
    final fg = HSLColor.fromAHSL(1, hue, tt.isDark ? 0.55 : 0.50, tt.isDark ? 0.78 : 0.32).toColor();
    final letter = text.trim().isEmpty ? '?' : text.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(letter, style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
