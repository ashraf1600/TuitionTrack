import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/i18n.dart';
import '../core/rich_clipboard.dart';
import '../core/symbol_palette.dart';
import 'ui.dart';

/// A strip of science symbols above the keyboard for whichever text field is
/// being typed in: super/subscripts (x², H₂O), Greek letters, maths structures
/// (fractions, roots, integrals, vectors, matrices), physics units and
/// chemistry arrows, charges and formulas. It also holds a Paste button that
/// keeps formulas copied from ChatGPT, web pages and documents.
///
/// Put it at the bottom of a screen's body, below the scrolling form:
/// `Column(children: [Expanded(form), const ScienceToolbar()])`. It stays
/// hidden until a text field that takes words (not numbers or passwords) has
/// the cursor, so nothing else on the screen needs to know about it.
class ScienceToolbar extends StatefulWidget {
  const ScienceToolbar({super.key});

  @override
  State<ScienceToolbar> createState() => _ScienceToolbarState();
}

class _ScienceToolbarState extends State<ScienceToolbar> {
  EditableTextState? _field;
  int _tab = 0;

  static final _textKinds = {TextInputType.text.index, TextInputType.multiline.index};

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
    _field = _currentField();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  EditableTextState? _currentField() {
    try {
      final state = FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>();
      if (state == null || !state.mounted) return null;
      final editable = state.widget;
      if (editable.readOnly || editable.obscureText || !_textKinds.contains(editable.keyboardType.index)) return null;
      return state;
    } catch (_) {
      // A field that is being removed right now: no field has the cursor.
      return null;
    }
  }

  void _onFocusChanged() {
    final next = _currentField();
    if (identical(next, _field) || !mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      setState(() => _field = next);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _field = _currentField());
      });
    }
  }

  void _write(EditableTextState state, TextEdit edit) {
    state.userUpdateTextEditingValue(
      TextEditingValue(text: edit.text, selection: TextSelection(baseOffset: edit.start, extentOffset: edit.end)),
      SelectionChangedCause.toolbar,
    );
  }

  void _apply(PaletteItem item) {
    final state = _field;
    if (state == null) return;
    final value = state.textEditingValue;
    final selection = value.selection;
    final edit = applyPaletteItem(item, value.text, selection.isValid ? selection.start : -1, selection.isValid ? selection.end : -1);
    if (edit == null) {
      showToast(
        context,
        item.action == PaletteAction.chemistry
            ? tr('Type or select a formula first, like H2SO4.')
            : tr('Select the text first, or type the number before the cursor.'),
      );
      return;
    }
    _write(state, edit);
  }

  Future<void> _paste() async {
    final state = _field;
    if (state == null) return;
    final text = await readClipboardForQuestions();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      showToast(context, tr('The clipboard is empty.'));
      return;
    }
    final value = state.textEditingValue;
    final selection = value.selection;
    _write(state, insertText(value.text, selection.isValid ? selection.start : -1, selection.isValid ? selection.end : -1, text));
  }

  @override
  Widget build(BuildContext context) {
    if (_field == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final tab = paletteTabs[_tab];
    // Buttons here must never take the cursor away from the text field.
    return ExcludeFocus(
      child: Material(
        color: scheme.surfaceContainerHigh,
        elevation: 4,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 42,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: tr('Paste with formulas'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.content_paste, size: 20),
                      onPressed: _paste,
                    ),
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < paletteTabs.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                              child: ChoiceChip(
                                label: Text(tr(paletteTabs[i].title)),
                                selected: i == _tab,
                                visualDensity: VisualDensity.compact,
                                labelStyle: const TextStyle(fontSize: 13),
                                onSelected: (_) => setState(() => _tab = i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView.builder(
                  key: ValueKey(tab.id),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  itemCount: tab.items.length,
                  itemBuilder: (context, index) => _Key(item: tab.items[index], onTap: _apply),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.item, required this.onTap});
  final PaletteItem item;
  final void Function(PaletteItem item) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tool = item.isTool;
    Widget key = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: tool ? scheme.primaryContainer : scheme.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTap(item),
          child: Container(
            constraints: const BoxConstraints(minWidth: 40),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: Text(
              item.label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: tool ? FontWeight.w700 : FontWeight.w500,
                color: tool ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
    if (item.tip != null) key = Tooltip(message: tr(item.tip!), child: key);
    return key;
  }
}
