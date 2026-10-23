/// The symbols, formula templates and text edits behind the science toolbar
/// that sits above the keyboard when a question is typed in the app.
///
/// Everything here is plain Dart on strings (no widgets), so it is covered by
/// `test/symbol_palette_test.dart`. How the text is stored does not change:
/// symbols go in as Unicode (α, ×, →, H₂O, x²) and structures as LaTeX inside
/// `$…$` — exactly what pasted ChatGPT text looks like, so both render the same
/// way (see `science_text.dart` and `widgets/math_text.dart`).
library;

import 'dart:math' as math;

import 'science_text.dart';

/// What a toolbar button does to the text.
enum PaletteAction {
  /// Insert [PaletteItem.value] as it is (a symbol or unit).
  text,

  /// Insert a LaTeX structure; `§` marks where the cursor goes (or the selected text).
  /// Outside a formula it is wrapped in `$…$`.
  template,

  /// Raise the selected text, or the number/sign just before the cursor (x2 -> x²).
  superscript,

  /// Lower the same (H2 -> H₂).
  subscript,

  /// Turn a typed formula into a tidy one (H2SO4 -> H₂SO₄, Fe3+ -> Fe³⁺, -> into →).
  chemistry,

  /// Wrap in `\ce{…}` (mhchem) for reactions.
  ce,
}

class PaletteItem {
  const PaletteItem(this.label, this.value, {this.action = PaletteAction.text, this.tip});

  /// What the button shows.
  final String label;

  /// What is inserted (for [PaletteAction.template], the LaTeX with `§`).
  final String value;
  final PaletteAction action;

  /// A short hint, shown on long press (English key for `tr`).
  final String? tip;

  bool get isTool => action != PaletteAction.text;
}

class PaletteTab {
  const PaletteTab(this.id, this.title, this.items);
  final String id;

  /// English key for `tr`.
  final String title;
  final List<PaletteItem> items;
}

/// The result of an edit: the new text and where the selection is afterwards.
class TextEdit {
  const TextEdit(this.text, this.start, this.end);
  final String text;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) => other is TextEdit && other.text == text && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(text, start, end);

  @override
  String toString() => 'TextEdit("$text", $start, $end)';
}

// ── Where is the cursor? ─────────────────────────────────────────────────────

/// True when [offset] is inside a formula: `$…$`, `$$…$$`, `\(…\)` or `\[…\]`.
bool insideMath(String text, int offset) {
  String? open; // r'$', r'$$', r'\(' or r'\['
  var i = 0;
  final stop = _bound(offset, text.length);
  while (i < stop) {
    if (text.startsWith(r'\(', i)) {
      open ??= r'\(';
      i += 2;
    } else if (text.startsWith(r'\[', i)) {
      open ??= r'\[';
      i += 2;
    } else if (text.startsWith(r'\)', i)) {
      if (open == r'\(') open = null;
      i += 2;
    } else if (text.startsWith(r'\]', i)) {
      if (open == r'\[') open = null;
      i += 2;
    } else if (text.startsWith(r'\', i)) {
      i += 2; // an escaped character such as \$ or \\
    } else if (text.startsWith(r'$$', i)) {
      open = open == r'$$' ? null : (open ?? r'$$');
      i += 2;
    } else if (text[i] == r'$') {
      open = open == r'$' ? null : (open ?? r'$');
      i++;
    } else {
      i++;
    }
  }
  return open != null;
}

// ── Edits ────────────────────────────────────────────────────────────────────

(int, int) _range(String text, int start, int end) {
  var a = start < 0 ? text.length : start;
  var b = end < 0 ? text.length : end;
  if (a > b) {
    final t = a;
    a = b;
    b = t;
  }
  return (_bound(a, text.length), _bound(b, text.length));
}

int _bound(int value, int length) => math.min(math.max(value, 0), length);

/// Replaces the selection with [insert]; the cursor lands after it.
TextEdit insertText(String text, int start, int end, String insert) {
  final (a, b) = _range(text, start, end);
  final updated = text.replaceRange(a, b, insert);
  final caret = a + insert.length;
  return TextEdit(updated, caret, caret);
}

/// `§` in [template] is where the cursor goes; a selected text replaces it.
/// Outside a formula the structure is wrapped in `$…$`.
TextEdit insertTemplate(String text, int start, int end, String template) {
  final (a, b) = _range(text, start, end);
  final selected = text.substring(a, b);
  final marker = template.indexOf('§');
  final before = marker < 0 ? template : template.substring(0, marker);
  final after = marker < 0 ? '' : template.substring(marker + 1);
  var piece = '$before$selected$after';
  var caret = before.length + selected.length;
  if (marker >= 0 && selected.isEmpty) caret = before.length;
  if (!insideMath(text, a)) {
    piece = '\$$piece\$';
    caret += 1;
  }
  return TextEdit(text.replaceRange(a, b, piece), a + caret, a + caret);
}

final _runBeforeCursor = RegExp(r'(\d+[+\-−]|[+\-−]\d+|\d+|[+\-−])$');

/// Raises ([superscript]) or lowers the selected text. With nothing selected it
/// takes the number or sign typed just before the cursor ("x2" -> "x²",
/// "H2" -> "H₂", "10-3" -> "10⁻³"). Returns null when there is nothing to change.
TextEdit? scriptEdit(String text, int start, int end, {required bool superscript}) {
  final (a, b) = _range(text, start, end);
  String convert(String s) => (superscript ? toSuperscript(s) : toSubscript(s)) ?? '';
  if (a != b) {
    final selected = text.substring(a, b);
    final unicode = convert(selected);
    if (unicode.isNotEmpty) {
      return TextEdit(text.replaceRange(a, b, unicode), a, a + unicode.length);
    }
    // Letters with no small form: let the formula renderer raise or lower them.
    final inner = '${superscript ? '^' : '_'}{$selected}';
    final latex = insideMath(text, a) ? inner : '\${}$inner\$';
    return TextEdit(text.replaceRange(a, b, latex), a, a + latex.length);
  }
  final match = _runBeforeCursor.firstMatch(text.substring(0, a));
  if (match == null) return null;
  final unicode = convert(match[0]!);
  if (unicode.isEmpty) return null;
  final from = a - match[0]!.length;
  return TextEdit(text.replaceRange(from, a, unicode), from, from + unicode.length);
}

bool _isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
bool _isSign(String ch) => ch == '+' || ch == '-' || ch == '−';
bool _isLetter(String ch) => RegExp(r'[A-Za-z]').hasMatch(ch);
bool _isFormulaBase(String ch) => _isLetter(ch) || ch == ')' || ch == ']';

/// A charge sign is only a charge when nothing that looks like a new part follows it.
bool _endsCharge(String token, int index) {
  if (index >= token.length) return true;
  return ')]},;.:→⇌↔←'.contains(token[index]);
}

String _chemToken(String input) {
  var token = input.replaceAll('<=>', '⇌').replaceAll('<->', '↔').replaceAll('->', '→').replaceAll('<-', '←');
  // Charges written with a caret: Cu^2+, SO4^{2-}
  token = token.replaceAllMapped(RegExp(r'\^\{?(\d*[+\-−]|\d+)\}?'), (m) => toSuperscript(m[1]!) ?? m[0]!);
  final out = StringBuffer();
  var i = 0;
  while (i < token.length) {
    final ch = token[i];
    if (_isDigit(ch)) {
      var j = i;
      while (j < token.length && _isDigit(token[j])) {
        j++;
      }
      final run = token.substring(i, j);
      final previous = i > 0 ? token[i - 1] : '';
      if (previous.isNotEmpty && _isFormulaBase(previous)) {
        final chargeFollows = j < token.length && _isSign(token[j]) && _endsCharge(token, j + 1);
        if (chargeFollows) {
          final sign = toSuperscript(token[j])!;
          if (run.length > 1) {
            // SO42- : the 4 is the atom count, "2-" the charge.
            out
              ..write(toSubscript(run.substring(0, run.length - 1)))
              ..write(toSuperscript(run.substring(run.length - 1)))
              ..write(sign);
          } else if ((previous == 'O' || previous == 'H') && token.substring(0, i - 1).contains(RegExp(r'[A-Za-z]'))) {
            // NO3-, HCO3-, NH4+ : an atom count, then the charge sign.
            out
              ..write(toSubscript(run))
              ..write(sign);
          } else {
            // Fe3+, Cu2+, O2-, S2- : the number is the charge.
            out
              ..write(toSuperscript(run))
              ..write(sign);
          }
          i = j + 1;
          continue;
        }
        out.write(toSubscript(run) ?? run);
        i = j;
        continue;
      }
      out.write(run);
      i = j;
      continue;
    }
    if (_isSign(ch) && i > 0 && _isFormulaBase(token[i - 1]) && _endsCharge(token, i + 1)) {
      out.write(toSuperscript(ch));
      i++;
      continue;
    }
    out.write(ch);
    i++;
  }
  return out.toString();
}

/// "H2SO4 + 2NaOH -> Na2SO4 + 2H2O" as "H₂SO₄ + 2NaOH → Na₂SO₄ + 2H₂O".
String chemifyText(String input) => input.replaceAllMapped(RegExp(r'\S+'), (m) => _chemToken(m[0]!));

/// Tidies the selected formula, or the word typed just before the cursor.
TextEdit? chemistryEdit(String text, int start, int end) {
  var (a, b) = _range(text, start, end);
  if (a == b) {
    final word = RegExp(r'\S+$').firstMatch(text.substring(0, a));
    if (word == null) return null;
    a -= word[0]!.length;
  }
  final original = text.substring(a, b);
  final tidy = chemifyText(original);
  if (tidy == original) return null;
  return TextEdit(text.replaceRange(a, b, tidy), a, a + tidy.length);
}

/// Wraps the selection in `\ce{…}`; with nothing selected, leaves the cursor inside the braces.
TextEdit ceEdit(String text, int start, int end) => insertTemplate(text, start, end, r'\ce{§}');

/// Applies one toolbar button. Null means there was nothing to change.
TextEdit? applyPaletteItem(PaletteItem item, String text, int start, int end) {
  switch (item.action) {
    case PaletteAction.text:
      return insertText(text, start, end, item.value);
    case PaletteAction.template:
      return insertTemplate(text, start, end, item.value);
    case PaletteAction.superscript:
      return scriptEdit(text, start, end, superscript: true);
    case PaletteAction.subscript:
      return scriptEdit(text, start, end, superscript: false);
    case PaletteAction.chemistry:
      return chemistryEdit(text, start, end);
    case PaletteAction.ce:
      return ceEdit(text, start, end);
  }
}

// ── The buttons ──────────────────────────────────────────────────────────────

List<PaletteItem> _chars(String chars) => [for (final ch in chars.split(' ')) if (ch.isNotEmpty) PaletteItem(ch, ch)];

const _scripts = PaletteTab('scripts', 'x² x₂', [
  PaletteItem('x²', '', action: PaletteAction.superscript, tip: 'Raise the selected text, or the number before the cursor'),
  PaletteItem('x₂', '', action: PaletteAction.subscript, tip: 'Lower the selected text, or the number before the cursor'),
  PaletteItem('H₂O', '', action: PaletteAction.chemistry, tip: 'Tidy a typed formula: H2SO4 becomes H₂SO₄'),
]);

final List<PaletteTab> paletteTabs = [
  PaletteTab('scripts', _scripts.title, [
    ..._scripts.items,
    ..._chars('⁰ ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹ ⁺ ⁻ ⁼ ⁽ ⁾ ⁿ ⁱ'),
    ..._chars('₀ ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉ ₊ ₋ ₌ ₍ ₎ ₙ ₓ ₐ ₑ ₒ ₕ ₖ ₗ ₘ ₚ ₛ ₜ'),
  ]),
  PaletteTab('math', 'Math', [
    const PaletteItem('a⁄b', r'\frac{§}{}', action: PaletteAction.template, tip: 'Fraction'),
    const PaletteItem('√', r'\sqrt{§}', action: PaletteAction.template, tip: 'Square root'),
    const PaletteItem('ⁿ√', r'\sqrt[n]{§}', action: PaletteAction.template, tip: 'Root'),
    const PaletteItem('Σ', r'\sum_{i=1}^{n} §', action: PaletteAction.template, tip: 'Sum'),
    const PaletteItem('∫', r'\int_{a}^{b} § \, dx', action: PaletteAction.template, tip: 'Integral'),
    const PaletteItem('lim', r'\lim_{x \to 0} §', action: PaletteAction.template, tip: 'Limit'),
    const PaletteItem('d/dx', r'\frac{d}{dx} §', action: PaletteAction.template, tip: 'Derivative'),
    const PaletteItem('∂/∂x', r'\frac{\partial §}{\partial x}', action: PaletteAction.template, tip: 'Partial derivative'),
    const PaletteItem('log', r'\log_{§}', action: PaletteAction.template, tip: 'Logarithm with a base'),
    const PaletteItem('sin', r'\sin §', action: PaletteAction.template),
    const PaletteItem('cos', r'\cos §', action: PaletteAction.template),
    const PaletteItem('tan', r'\tan §', action: PaletteAction.template),
    const PaletteItem('|x|', r'\left| § \right|', action: PaletteAction.template, tip: 'Absolute value'),
    const PaletteItem('(  )', r'\left( § \right)', action: PaletteAction.template, tip: 'Big brackets'),
    const PaletteItem('nCr', r'\binom{n}{r}', action: PaletteAction.template, tip: 'Combination'),
    const PaletteItem('v⃗', r'\vec{§}', action: PaletteAction.template, tip: 'Vector'),
    const PaletteItem('x̄', r'\overline{§}', action: PaletteAction.template, tip: 'Bar'),
    const PaletteItem('x̂', r'\hat{§}', action: PaletteAction.template, tip: 'Unit vector'),
    const PaletteItem('[ ]', '\\begin{bmatrix} § & \\\\  &  \\end{bmatrix}', action: PaletteAction.template, tip: 'Matrix'),
    ..._chars('± ∓ × ÷ · √ ∛ ∞ ≠ ≈ ≡ ≤ ≥ ≪ ≫ ∝ ° ′ ″ ‰ ∠ ⊥ ∥ △ ∴ ∵ ∈ ∉ ⊂ ⊆ ∪ ∩ ∅ ∀ ∃ ∑ ∏ ∫ ∮ ∂ ∇ → ← ↔ ⇒ ⇔ ℝ ℕ ℤ ℚ ℂ'),
  ]),
  PaletteTab('greek', 'Greek', [
    ..._chars('α β γ δ ε ζ η θ ι κ λ μ ν ξ ο π ρ σ τ υ φ χ ψ ω ϕ ϑ ς'),
    ..._chars('Γ Δ Θ Λ Ξ Π Σ Υ Φ Ψ Ω'),
  ]),
  PaletteTab('physics', 'Physics', [
    const PaletteItem('F⃗', r'\vec{F}', action: PaletteAction.template, tip: 'Vector F'),
    const PaletteItem('v⃗', r'\vec{v}', action: PaletteAction.template, tip: 'Vector v'),
    const PaletteItem('Δx', r'\Delta §', action: PaletteAction.template, tip: 'Change in'),
    const PaletteItem('dx/dt', r'\frac{d §}{dt}', action: PaletteAction.template, tip: 'Rate of change'),
    const PaletteItem('½mv²', r'\frac{1}{2}mv^{2}', action: PaletteAction.template, tip: 'Kinetic energy'),
    const PaletteItem('E=mc²', r'E = mc^{2}', action: PaletteAction.template),
    const PaletteItem('×10ⁿ', r'\times 10^{§}', action: PaletteAction.template, tip: 'Scientific notation'),
    const PaletteItem('unit', r'\mathrm{§}', action: PaletteAction.template, tip: 'Upright text for a unit'),
    ..._chars('Ω µ ħ ℏ Å ° ε₀ μ₀ λ ν ρ σ τ φ ω Δ ∇ ∝ ≈ ± × · → ← ↑ ↓ ⊗ ⊙ ∮ ∫ ∂'),
    ..._chars('m/s m·s⁻¹ m·s⁻² kg·m·s⁻¹ kg·m² N·m N/m² J/K J·mol⁻¹·K⁻¹ W Hz Pa °C K eV kWh N/C V/m T Wb F H S cd mol mol⁻¹ rad rad/s'),
  ]),
  PaletteTab('chem', 'Chem', [
    const PaletteItem('H₂O', '', action: PaletteAction.chemistry, tip: 'Tidy a typed formula: H2SO4 becomes H₂SO₄'),
    const PaletteItem('\\ce', '', action: PaletteAction.ce, tip: 'Reaction or formula in \\ce{…} form'),
    const PaletteItem('⟶ over', r'\xrightarrow{§}', action: PaletteAction.template, tip: 'Arrow with conditions on top'),
    ..._chars('→ ⇌ ⇄ ↑ ↓ ⟶ Δ · ° ⁺ ⁻ ²⁺ ³⁺ ²⁻ ³⁻ (s) (l) (g) (aq)'),
    ..._chars('H₂O CO₂ H₂SO₄ HCl HNO₃ NaOH NH₃ CH₄ C₂H₅OH C₆H₁₂O₆ CH₃COOH O₂ N₂ H₂ Cl₂ CaCO₃ NaCl KMnO₄ Fe₂O₃ Na₂CO₃ NaHCO₃'),
  ]),
];
