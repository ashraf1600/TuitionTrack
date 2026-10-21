import 'package:flutter/material.dart';

import '../core/i18n.dart';
import 'ui.dart';

/// A password box with a show/hide button.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.validator,
    this.onSubmitted,
    this.isNew = false,
    this.labelAbove = false,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;

  /// True for a password being chosen (so password managers offer to save it).
  final bool isNew;

  /// Shows [label] as a small label above the box instead of inside it.
  final bool labelAbove;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [widget.isNew ? AutofillHints.newPassword : AutofillHints.password],
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.labelAbove ? null : widget.label,
        helperText: widget.helper,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _hidden ? tr('Show password') : tr('Hide password'),
          icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
    if (!widget.labelAbove) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [FieldLabel(widget.label), field],
    );
  }
}
