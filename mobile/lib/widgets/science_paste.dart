import 'package:flutter/material.dart';

import '../core/rich_clipboard.dart';

/// The text field's long-press menu, with Paste that keeps science text:
/// typeset maths comes in as LaTeX and H₂O / x² keep their small numbers
/// (Flutter's own Paste only sees the plain text of a copied page).
///
/// Use as `contextMenuBuilder: sciencePasteMenu` on question and paper fields.
Widget sciencePasteMenu(BuildContext context, EditableTextState state) {
  final items = [
    for (final item in state.contextMenuButtonItems)
      if (item.type != ContextMenuButtonType.paste)
        item
      else
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () async {
            final text = await readClipboardForQuestions();
            if (text == null || text.isEmpty) {
              item.onPressed?.call();
              return;
            }
            final value = state.textEditingValue;
            final selection = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
            final updated = value.text.replaceRange(selection.start, selection.end, text);
            state.userUpdateTextEditingValue(
              TextEditingValue(text: updated, selection: TextSelection.collapsed(offset: selection.start + text.length)),
              SelectionChangedCause.toolbar,
            );
            state.hideToolbar();
          },
        ),
  ];
  return AdaptiveTextSelectionToolbar.buttonItems(anchors: state.contextMenuAnchors, buttonItems: items);
}
