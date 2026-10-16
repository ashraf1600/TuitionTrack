// Pasting science and maths from other places (same cases as the website's
// frontend/src/__tests__/scienceText.test.js).
import 'package:flutter_test/flutter_test.dart';
import 'package:tuitiontrack/core/science_text.dart';

void main() {
  group('super- and subscripts', () {
    test('maps what it can and refuses the rest', () {
      expect(toSuperscript('2'), '²');
      expect(toSuperscript('-19'), '⁻¹⁹');
      expect(toSubscript('2'), '₂');
      expect(toSuperscript('th'), isNull);
      expect(scriptText('2', superscript: false), '₂');
      expect(scriptText('th', superscript: true), r'\({}^{\text{th}}\)');
    });
  });

  group('unicodeToTex', () {
    test('turns Unicode maths into LaTeX commands', () {
      expect(unicodeToTex('x² − 4 ≤ 0'), r'x^{2} - 4 \le  0');
      expect(unicodeToTex('√(b²−4ac)'), r'\sqrt{b^{2}-4ac}');
      expect(unicodeToTex('√2'), r'\sqrt{2}');
      expect(unicodeToTex('θ = 30°'), r'\theta  = 30^\circ ');
      expect(unicodeToTex('H₂O'), 'H_{2}O');
    });

    test('leaves text groups alone', () {
      expect(unicodeToTex(r'\text{5 × 2} × 3'), r'\text{5 × 2} \times  3');
    });
  });

  group('chemistry', () {
    test(r'writes \ce formulas as plain LaTeX', () {
      expect(ceToTex('H2SO4'), r'\mathrm{H}_{2}\mathrm{S}\mathrm{O}_{4}');
      expect(ceToTex('2H2 + O2 -> 2H2O'), r'2\,\mathrm{H}_{2} + \mathrm{O}_{2} \rightarrow 2\,\mathrm{H}_{2}\mathrm{O}');
      expect(ceToTex('Cu2+'), r'\mathrm{Cu}^{2+}');
      expect(ceToTex('SO4^2-'), r'\mathrm{S}\mathrm{O}_{4}^{2-}');
      expect(ceToTex('N2 + 3H2 <=> 2NH3'), contains(r'\rightleftharpoons'));
      expect(ceToTex('NaCl(aq)'), r'\mathrm{Na}\mathrm{Cl}\,\mathrm{(aq)}');
    });

    test(r'prepareTex unwraps \ce, units and numbered environments', () {
      expect(prepareTex(r'\ce{H2O}'), r'\mathrm{H}_{2}\mathrm{O}');
      expect(prepareTex(r'\SI{9.8}{m/s^2}'), r'9.8\,\mathrm{m/s^2}');
      expect(prepareTex(r'\begin{align*} a &= b \label{x}\end{align*}'), r'\begin{aligned} a &= b \end{aligned}');
      expect(prepareTex(r'a \lt b'), 'a < b');
    });
  });

  group('texToPlain', () {
    test('reads like the formula when it cannot be typeset', () {
      expect(texToPlain(r'x^{2}+\frac{1}{2}'), 'x²+(1)/(2)');
      expect(texToPlain(r'\sqrt{2} \times \pi'), '√(2) × π');
      expect(texToPlain(r'v_{0} = 5\,\text{m/s}'), 'v₀ = 5m/s');
    });
  });

  group('wrapBareLatex', () {
    test('puts delimiters around LaTeX pasted without them', () {
      expect(wrapBareLatex('Find x if x^2 + 2x = 8.'), r'Find x if \(x^2 + 2x = 8\).');
      expect(wrapBareLatex(r'If \frac{1}{2} of a number is 5'), r'If \(\frac{1}{2}\) of a number is 5');
      expect(wrapBareLatex('The speed is 20 m/s^2 here'), r'The speed is \(20 m/s^2\) here');
      expect(wrapBareLatex('যদি x^2 = 4 হয়'), r'যদি \(x^2 = 4\) হয়');
    });

    test('leaves ordinary text and existing formulas alone', () {
      expect(wrapBareLatex('Save it as my_file.txt'), 'Save it as my_file.txt');
      expect(wrapBareLatex(r'Solve \(x^2 = 4\) now'), r'Solve \(x^2 = 4\) now');
      expect(wrapBareLatex(r'Prices: $5 and $10'), r'Prices: $5 and $10');
      expect(wrapBareLatex('No maths here.'), 'No maths here.');
    });
  });

  group('clipboard HTML', () {
    test('keeps superscripts and subscripts from Word, Google Docs and websites', () {
      expect(htmlToQuestionText('<p>H<sub>2</sub>SO<sub>4</sub> and x<sup>2</sup></p>'), 'H₂SO₄ and x²');
      expect(htmlToQuestionText('<p>10<span style="vertical-align:super">-19</span> C</p>'), '10⁻¹⁹ C');
      expect(htmlToQuestionText('<p>1<sup>st</sup> law</p>'), r'1\({}^{\text{st}}\) law');
    });

    test('turns typeset maths back into LaTeX', () {
      const katex = '<p>Solve <span class="katex"><span class="katex-mathml"><math><semantics><mrow><mi>x</mi></mrow>'
          '<annotation encoding="application/x-tex">x^2=4</annotation></semantics></math></span>'
          '<span class="katex-html">x2=4</span></span></p>';
      expect(htmlToQuestionText(katex), r'Solve \(x^2=4\)');
      expect(htmlToQuestionText('<p>Area <math><msup><mi>r</mi><mn>2</mn></msup></math></p>'), r'Area \({r}^{2}\)');
      expect(
        htmlToQuestionText('<math><mfrac><mn>1</mn><mn>2</mn></mfrac><mo>+</mo><msqrt><mi>y</mi></msqrt></math>'),
        r'\(\frac{1}{2}+\sqrt{y}\)',
      );
    });

    test('keeps question numbers and options from lists', () {
      const html = '<ol><li>What is H<sub>2</sub>O?<ol><li>Water</li><li>Salt</li></ol></li></ol>';
      expect(htmlToQuestionText(html), '1. What is H₂O?\nA) Water\nB) Salt');
      expect(hasRichScience(html), isTrue);
      expect(hasRichScience('<p>plain</p>'), isFalse);
    });

    test('tidies plain text from Word', () {
      expect(tidyPastedText('a\r\nb c​'), 'a\nb c');
      expect(tidyPastedText('5  3'), '5 × 3');
    });
  });
}
