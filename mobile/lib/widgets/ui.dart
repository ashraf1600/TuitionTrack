import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/app_keys.dart';
import '../core/i18n.dart';
import '../core/repo.dart';
import 'theme.dart';
import 'tt_logo.dart';

/// A short message at the bottom. With [actionLabel] it offers one action
/// (usually "Undo") and stays a little longer.
void showToast(BuildContext context, String message, {bool error = false, String? actionLabel, VoidCallback? onAction}) {
  showToastOn(ScaffoldMessenger.maybeOf(context), message,
      error: error, actionLabel: actionLabel, onAction: onAction, tokens: context.tt);
}

/// [showToast] for code without a BuildContext (notification actions).
/// [tokens] are the caller's theme; the messenger itself sits above the app theme.
void showToastOn(ScaffoldMessengerState? messenger, String message,
    {bool error = false, String? actionLabel, VoidCallback? onAction, TtTokens? tokens}) {
  if (messenger == null) return;
  final hasAction = actionLabel != null && onAction != null;
  // Normal messages use the theme's high-contrast snack bar; errors are filled
  // with the danger colour (its ink is the background colour, 6:1 or better).
  final tt = tokens ?? rootNavigatorKey.currentContext?.tt ?? messenger.context.tt;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: tt.background, fontSize: 14)),
      backgroundColor: error ? tt.danger : tt.textPrimary,
      duration: Duration(seconds: error ? 5 : (hasAction ? 6 : 3)),
      // Without this a snack bar with an action stays until tapped; an Undo should simply time out.
      persist: false,
      action: hasAction ? SnackBarAction(label: actionLabel, textColor: error ? tt.background : (tt.isDark ? TtColors.lPrimary : TtColors.dPrimary), onPressed: onAction) : null,
    ));
}

/// Validates a form. When something is wrong the field shows why — and because that field
/// may be scrolled out of sight, a message says so too.
bool checkForm(BuildContext context, GlobalKey<FormState> form) {
  if (form.currentState?.validate() ?? false) return true;
  showToast(context, tr('Some details are missing or not right. Check the fields marked in red.'), error: true);
  return false;
}

/// Like [attempt] for changes that also work offline ([Repo] methods that may
/// answer `queued: true`): the toast says the change was kept on the phone
/// instead of claiming the server has it.
Future<bool> attemptSave(BuildContext context, Future<Map<String, dynamic>> Function() action, {required String success}) async {
  Map<String, dynamic>? result;
  final ok = await attempt(context, () async {
    result = await action();
  });
  if (ok && context.mounted) {
    final queued = result?['queued'] == true;
    showToast(context, queued ? tr('Saved on this phone. It will be sent when you are back online.') : success);
  }
  return ok;
}

/// Runs an action, reporting failure as a toast. Returns true when it succeeded.
Future<bool> attempt(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showToast(context, success);
    return true;
  } on ApiException catch (error) {
    if (context.mounted) showToast(context, error.message, error: true);
    return false;
  } catch (_) {
    if (context.mounted) showToast(context, tr('Something went wrong. Please try again.'), error: true);
    return false;
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool danger = false,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: context.tt.danger, foregroundColor: context.tt.background) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// Loads something from the server and shows a spinner, the error with a retry, or the content.
/// Pull down to refresh. Call `reload` (from the builder, or via a GlobalKey) after changing data.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder, this.scrollable = true});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  /// False when the builder returns its own scroll view.
  final bool scrollable;

  @override
  State<Loader<T>> createState() => LoaderState<T>();
}

class LoaderState<T> extends State<Loader<T>> {
  T? _data;
  bool _loaded = false;
  String? _error;
  bool _slow = false;
  Timer? _slowTimer;
  ValueNotifier<int>? _dataVersion;

  @override
  void initState() {
    super.initState();
    // Load again by itself when fresh data is available (back online, offline changes sent).
    try {
      _dataVersion = Provider.of<Repo>(context, listen: false).api.dataVersion..addListener(_onDataChanged);
    } on ProviderNotFoundException {
      _dataVersion = null;
    }
    reload();
  }

  @override
  void dispose() {
    _dataVersion?.removeListener(_onDataChanged);
    _slowTimer?.cancel();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) reload(quiet: true);
  }

  /// Loads again. [quiet] (background refreshes) keeps failures off screen:
  /// what was shown stays, and the next refresh tries again.
  Future<void> reload({bool quiet = false}) async {
    // A first load that takes long is usually the free server waking up: say so.
    if (!_loaded) {
      _slowTimer?.cancel();
      _slowTimer = Timer(const Duration(seconds: 6), () {
        if (mounted && !_loaded) setState(() => _slow = true);
      });
    }
    try {
      final data = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loaded = true;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      // Keep showing what we already have; a failed refresh should not blank the screen.
      if (_loaded) {
        if (!quiet) showToast(context, error.message, error: true);
      } else {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (!mounted) return;
      if (_loaded) {
        if (!quiet) showToast(context, tr('Could not refresh. Please try again.'), error: true);
      } else {
        setState(() => _error = tr('Something went wrong while loading. Please try again.'));
      }
    } finally {
      _slowTimer?.cancel();
      if (mounted && _slow) setState(() => _slow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      if (_error != null) {
        return ErrorView(message: _error!, onRetry: () {
          setState(() => _error = null);
          reload();
        });
      }
      // Grey shapes where the content will appear: the wait feels shorter than a spinner.
      return Align(
        alignment: Alignment.topCenter,
        child: ClipRect(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_slow) ...[
                    const Center(child: TtLoader(size: 64)),
                    const SizedBox(height: 10),
                    Text(
                      tr('Connecting to the server…\nIt can take up to a minute to wake up.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SkeletonBox(height: 84),
                  const SizedBox(height: 12),
                  const SkeletonBox(height: 140),
                  const SizedBox(height: 12),
                  const SkeletonBox(height: 120),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final child = widget.builder(context, _data as T, reload);
    if (!widget.scrollable) return child;
    return RefreshIndicator(onRefresh: reload, child: child);
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 44, color: scheme.outlineVariant),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurface)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(tr('Try again'))),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      child: Column(
        children: [
          // The icon on a soft tinted disc, like the logo's tile: calmer than a bare grey icon.
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: tt.primaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: tt.onPrimaryContainer),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: tt.textSecondary, fontSize: 14, height: 1.5)),
          ],
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing, this.icon});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: tone(context, AppColors.primarySoft)), const SizedBox(width: 8)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (subtitle != null) Text(subtitle!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The tonal container behind an accent: the token container for success,
/// warning, danger and primary, a light tint of anything else.
Color tonalContainer(BuildContext context, Color accent) {
  final tt = context.tt;
  if (accent == AppColors.success || accent == AppColors.chartEarned) return tt.successContainer;
  if (accent == AppColors.warning) return tt.warningContainer;
  if (accent == AppColors.danger) return tt.dangerContainer;
  if (accent == AppColors.primary || accent == AppColors.primarySoft) return tt.primaryContainer;
  if (accent == AppColors.muted || accent == AppColors.faint) return tt.cardRaised;
  return accent.withValues(alpha: 0.14);
}

/// A small rounded label: status, counts, categories.
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color = AppColors.muted, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink = tone(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tonalContainer(context, color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: ink), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// A tinted message box: information, warnings, errors.
class Banner2 extends StatelessWidget {
  const Banner2(this.message, {super.key, this.color = AppColors.primarySoft, this.icon = Icons.info_outline, this.action});
  final String message;
  final Color color;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ink = tone(context, color);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tonalContainer(context, color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: ink),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: ink, fontSize: 14, height: 1.45))),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.onLongPress, this.borderColor, this.accent});
  final Widget child;

  /// A thin coloured band along the top, e.g. a tuition's own colour.
  final Color? accent;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  /// Quick actions, e.g. a menu of shortcuts for this card.
  final VoidCallback? onLongPress;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    // No outlines: cards stand on their fill (and one soft shadow in the light
    // theme). A [borderColor] is only for cards that must call attention.
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: borderColor == null ? BorderSide.none : BorderSide(color: borderColor!),
    );
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: tt.cardShadow),
      child: Material(
        color: tt.card,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: accent == null
              ? Padding(padding: padding, child: child)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [Container(height: 4, color: accent), Padding(padding: padding, child: child)],
                ),
        ),
      ),
    );
  }
}

/// A button that shows a spinner and ignores taps while its action runs.
class BusyButton extends StatefulWidget {
  const BusyButton({super.key, required this.onPressed, required this.label, this.icon, this.outlined = false, this.color});
  final Future<void> Function()? onPressed;
  final String label;
  final IconData? icon;
  final bool outlined;
  final Color? color;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: widget.outlined ? context.tt.primary : context.tt.onPrimary),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[Icon(widget.icon, size: 18), const SizedBox(width: 8)],
              Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
            ],
          );
    final enabled = widget.onPressed != null && !_busy;
    if (widget.outlined) {
      return OutlinedButton(onPressed: enabled ? _run : null, child: child);
    }
    return FilledButton(
      style: widget.color == null ? null : FilledButton.styleFrom(backgroundColor: widget.color),
      onPressed: enabled ? _run : null,
      child: child,
    );
  }
}

/// A labelled figure for dashboards.
class Stat extends StatelessWidget {
  const Stat({super.key, required this.label, required this.value, this.color});
  final String label;
  final String value;
  /// Accent for the figure; the theme's text colour when left out.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: accent == null || accent == AppColors.text ? scheme.onSurface : tone(context, accent),
                fontSize: 18,
                fontWeight: FontWeight.w800)),
      ],
    );
  }
}

/// Standard page padding with a comfortable maximum width on tablets.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 32)});
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}

const gap8 = SizedBox(height: 8);
const gap12 = SizedBox(height: 12);
const gap16 = SizedBox(height: 16);
const gap24 = SizedBox(height: 24);

/// A rounded block of rows with hairline dividers, like a phone's Settings app.
/// Use it instead of separate bordered cards for forms and lists of actions.
class FlatGroup extends StatelessWidget {
  const FlatGroup({super.key, required this.children, this.title});
  final List<Widget> children;

  /// A small caps label above the block.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final block = Material(
      color: context.tt.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 16, color: scheme.outline),
            children[i],
          ],
        ],
      ),
    );
    if (title == null) return block;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text(title!.toUpperCase(),
              style: TextStyle(fontSize: 12, letterSpacing: 0.72, fontWeight: FontWeight.w700, color: context.tt.textTertiary)),
        ),
        block,
      ],
    );
  }
}

/// A borderless text field for use inside a [FlatGroup].
class FlatField extends StatelessWidget {
  const FlatField({
    super.key,
    required this.controller,
    this.hint,
    this.minLines = 1,
    this.maxLines = 1,
    this.autofocus = false,
    this.style,
    this.onChanged,
    this.capitalization = TextCapitalization.sentences,
    this.contextMenuBuilder,
  });
  final TextEditingController controller;

  /// The long-press menu, e.g. `sciencePasteMenu` for maths and science text.
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final String? hint;
  final int minLines;
  final int maxLines;
  final bool autofocus;
  final TextStyle? style;
  final ValueChanged<String>? onChanged;
  final TextCapitalization capitalization;

  @override
  Widget build(BuildContext context) {
    const none = InputBorder.none;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        autofocus: autofocus,
        onChanged: onChanged,
        textCapitalization: capitalization,
        contextMenuBuilder: contextMenuBuilder ?? _defaultContextMenu,
        style: style ?? const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: none,
          enabledBorder: none,
          focusedBorder: none,
        ),
      ),
    );
  }
}

/// One tappable row inside a [FlatGroup]: icon or avatar, label, current value, chevron.
class PickerRow extends StatelessWidget {
  const PickerRow({super.key, required this.label, required this.value, required this.onTap, this.leading, this.trailing});
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Text(label, style: TextStyle(fontSize: 15, color: tt.textSecondary)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(value,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: tabular, color: tt.textPrimary)),
              ),
              const SizedBox(width: 4),
              trailing ?? Icon(Icons.chevron_right_rounded, size: 20, color: tt.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small (i) that explains a choice on tap, instead of a paragraph on screen.
class InfoTip extends StatelessWidget {
  const InfoTip(this.message, {super.key, this.title});
  final String message;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tr('More about this'),
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      icon: Icon(Icons.info_outline_rounded, color: context.tt.textTertiary),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[Text(title!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), gap8],
                Text(message, style: const TextStyle(fontSize: 14, height: 1.4)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A round placeholder with the first letter of a name (or an icon).
class InitialAvatar extends StatelessWidget {
  const InitialAvatar(this.name, {super.key, this.radius = 14, this.icon});
  final String name;
  final double radius;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ink = tone(context, AppColors.primarySoft);
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.18),
      child: icon != null
          ? Icon(icon, size: radius * 1.1, color: ink)
          : Text(name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase(),
              style: TextStyle(fontSize: radius * 0.9, fontWeight: FontWeight.w800, color: ink)),
    );
  }
}

/// A round profile picture: the person's photo when they have one, otherwise
/// the first letter of their name. [photo] may be a full or server-relative URL.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.photo, this.radius = 16});
  final String name;
  final String? photo;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = (photo == null || photo!.isEmpty) ? '' : context.read<Repo>().api.mediaUrl(photo);
    final letter = Center(
      child: Text(
        name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase(),
        style: TextStyle(fontSize: radius * 0.85, fontWeight: FontWeight.w600, color: context.tt.onPrimaryContainer),
      ),
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: context.tt.primaryContainer,
      child: url.isEmpty
          ? letter
          : ClipOval(
              child: SizedBox.square(
                dimension: radius * 2,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  loadingBuilder: (_, child, progress) => progress == null ? child : letter,
                  errorBuilder: (_, _, _) => letter,
                ),
              ),
            ),
    );
  }
}

/// Shows [options] in a bottom sheet with an optional search box; returns the chosen value.
Future<String?> pickFromSheet(
  BuildContext context, {
  required String title,
  required List<({String value, String label, String? subtitle})> options,
  String? selected,
  IconData? icon,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _PickSheet(title: title, options: options, selected: selected, icon: icon),
  );
}

class _PickSheet extends StatefulWidget {
  const _PickSheet({required this.title, required this.options, this.selected, this.icon});
  final String title;
  final List<({String value, String label, String? subtitle})> options;
  final String? selected;
  final IconData? icon;

  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.options
        : widget.options.where((o) => o.label.toLowerCase().contains(q) || (o.subtitle ?? '').toLowerCase().contains(q)).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              if (widget.options.length > 7)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    autofocus: false,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(hintText: tr('Search'), prefixIcon: Icon(Icons.search), isDense: true),
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in shown)
                      ListTile(
                        leading: InitialAvatar(o.label, radius: 16, icon: widget.icon),
                        title: Text(o.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: o.subtitle == null || o.subtitle!.isEmpty
                            ? null
                            : Text(o.subtitle!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        trailing: o.value == widget.selected ? Icon(Icons.check, color: tone(context, AppColors.primarySoft)) : null,
                        onTap: () => Navigator.pop(context, o.value),
                      ),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(tr('Nothing matches.'), textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// A softly pulsing grey block standing in for content that is still loading.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, required this.height, this.radius = 16});
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Semantics(
      label: tr('Loading'),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(_pulse),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(widget.radius)),
        ),
      ),
    );
  }
}

/// A tonal segmented control: one 44 dp pill per option inside a soft track,
/// the selected one filled with the primary container.
class PillToggle<T> extends StatelessWidget {
  const PillToggle({super.key, required this.options, required this.selected, required this.onChanged});

  /// (value, label, optional icon)
  final List<(T, String, IconData?)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: tt.isDark ? tt.card : tt.background, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (final (value, label, icon) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: value == selected,
                child: Material(
                  color: value == selected ? tt.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: value == selected ? null : () => onChanged(value),
                    child: SizedBox(
                      height: 44,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 18, color: value == selected ? tt.onPrimaryContainer : tt.textSecondary),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: value == selected ? FontWeight.w600 : FontWeight.w500,
                                color: value == selected ? tt.onPrimaryContainer : tt.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small label above a form field (instead of relying on placeholder text).
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.tt.textSecondary)),
    );
  }
}

Widget _defaultContextMenu(BuildContext context, EditableTextState state) =>
    AdaptiveTextSelectionToolbar.editableText(editableTextState: state);
