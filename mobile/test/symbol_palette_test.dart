// The science toolbar's text edits: super/subscripts, chemistry formulas,
// formula templates and knowing when the cursor is inside a formula.
import 'package:flutter_test/flutter_test.dart';
import 'package:tuitiontrack/core/symbol_palette.dart';

void main() {
  group('insideMath', () {
    test(r'knows $ and \( formulas', () {
      expect(insideMath(r'Find $x', 7), isTrue);
      expect(insideMath(r'Find $x$ now', 12), isFalse);
      expect(insideMath(r'Find \(x', 8), isTrue);
      expect(insideMath(r'Find \(x\) now', 13), isFalse);
      expect(insideMath(r'$$a+b', 5), isTrue);
      expect(insideMath(r'$$a+b$$ c', 9), isFalse);
    });

    test('an escaped dollar is just a dollar', () {
      expect(insideMath(r'It costs \$5 and', 15), isFalse);
    });
  });

  group('insertText and insertTemplate', () {
    test('a symbol replaces the selection', () {
      expect(insertText('a b', 1, 2, 'α'), const TextEdit('aαb', 2, 2));
    });

    test('a structure outside a formula is wrapped in dollars', () {
      expect(insertTemplate('x ', 2, 2, r'\frac{§}{}'), const TextEdit(r'x $\frac{}{}$', 9, 9));
    });

    test('inside a formula it is not wrapped again', () {
      expect(insertTemplate(r'$a + ', 5, 5, r'\sqrt{§}'), const TextEdit(r'$a + \sqrt{}', 11, 11));
    });

    test('selected text goes where the cursor marker is', () {
      expect(insertTemplate('x+1', 0, 3, r'\sqrt{§}'), const TextEdit(r'$\sqrt{x+1}$', 10, 10));
    });
  });

  group('scriptEdit', () {
    test('raises and lowers a selection', () {
      expect(scriptEdit('x2', 1, 2, superscript: true), const TextEdit('x²', 1, 2));
      expect(scriptEdit('H2O', 1, 2, superscript: false), const TextEdit('H₂O', 1, 2));
    });

    test('with nothing selected it takes the number before the cursor', () {
      expect(scriptEdit('x2', 2, 2, superscript: true), const TextEdit('x²', 1, 2));
      expect(scriptEdit('H2', 2, 2, superscript: false), const TextEdit('H₂', 1, 2));
      expect(scriptEdit('10-3', 4, 4, superscript: true), const TextEdit('10⁻³', 2, 4));
      expect(scriptEdit('Fe3+', 4, 4, superscript: true), const TextEdit('Fe³⁺', 2, 4));
    });

    test('nothing to raise gives null', () {
      expect(scriptEdit('abc', 3, 3, superscript: true), isNull);
    });

    test('letters with no small form fall back to LaTeX', () {
      expect(scriptEdit('v th', 2, 4, superscript: true), const TextEdit(r'v ${}^{th}$', 2, 11));
    });
  });

  group('chemifyText', () {
    test('atom counts become subscripts', () {
      expect(chemifyText('H2SO4'), 'H₂SO₄');
      expect(chemifyText('Ca(OH)2'), 'Ca(OH)₂');
      expect(chemifyText('C6H12O6'), 'C₆H₁₂O₆');
      expect(chemifyText('(NH4)2SO4'), '(NH₄)₂SO₄');
    });

    test('charges become superscripts', () {
      expect(chemifyText('Fe3+'), 'Fe³⁺');
      expect(chemifyText('Cu2+'), 'Cu²⁺');
      expect(chemifyText('Na+'), 'Na⁺');
      expect(chemifyText('Cl-'), 'Cl⁻');
      expect(chemifyText('S2-'), 'S²⁻');
      expect(chemifyText('O2-'), 'O²⁻');
    });

    test('oxyanions keep their atom count', () {
      expect(chemifyText('NO3-'), 'NO₃⁻');
      expect(chemifyText('HCO3-'), 'HCO₃⁻');
      expect(chemifyText('NH4+'), 'NH₄⁺');
      expect(chemifyText('SO42-'), 'SO₄²⁻');
    });

    test('a caret charge is read as written', () {
      expect(chemifyText('Cu^2+'), 'Cu²⁺');
      expect(chemifyText('SO4^{2-}'), 'SO₄²⁻');
    });

    test('equations: coefficients stay, plus signs stay, arrows are drawn', () {
      expect(chemifyText('2H2 + O2 -> 2H2O'), '2H₂ + O₂ → 2H₂O');
      expect(chemifyText('2H2+O2->2H2O'), '2H₂+O₂→2H₂O');
      expect(chemifyText('N2 + 3H2 <=> 2NH3'), 'N₂ + 3H₂ ⇌ 2NH₃');
    });

    test('plain words and numbers are left alone', () {
      expect(chemifyText('about 2.5 g'), 'about 2.5 g');
      expect(chemifyText('well-known'), 'well-known');
    });
  });

  group('chemistryEdit and applyPaletteItem', () {
    test('tidies the word before the cursor', () {
      expect(chemistryEdit('Burn CH4', 8, 8), const TextEdit('Burn CH₄', 5, 8));
    });

    test('nothing to tidy gives null', () {
      expect(chemistryEdit('water', 5, 5), isNull);
    });

    test('\\ce wraps the selection', () {
      expect(ceEdit('H2O', 0, 3), const TextEdit(r'$\ce{H2O}$', 8, 8));
    });

    test('every tab has buttons and every template has its marker or is complete', () {
      for (final tab in paletteTabs) {
        expect(tab.items, isNotEmpty, reason: tab.id);
        for (final item in tab.items) {
          expect(item.label, isNotEmpty);
          if (item.action == PaletteAction.template) {
            final edit = applyPaletteItem(item, '', 0, 0)!;
            expect(edit.text, startsWith(r'$'), reason: item.label);
          }
        }
      }
    });
  });
}
