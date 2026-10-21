// @vitest-environment jsdom
import { describe, expect, it } from 'vitest';
import {
  ceToTex,
  mathmlToTex,
  prepareTex,
  scriptText,
  texToPlain,
  toSubscript,
  toSuperscript,
  unicodeToTex,
  wrapBareLatex,
} from '../utils/scienceText';
import { htmlToPlainText, htmlWithLatex } from '../utils/clipboard';

describe('super- and subscripts', () => {
  it('maps what it can and refuses the rest', () => {
    expect(toSuperscript('2')).toBe('²');
    expect(toSuperscript('-19')).toBe('⁻¹⁹');
    expect(toSubscript('2')).toBe('₂');
    expect(toSuperscript('th')).toBeNull();
    expect(scriptText('2', 'sub')).toBe('₂');
    expect(scriptText('th', 'sup')).toBe('\\({}^{\\text{th}}\\)');
  });
});

describe('unicodeToTex', () => {
  it('turns Unicode maths into LaTeX commands', () => {
    expect(unicodeToTex('x² − 4 ≤ 0')).toBe('x^{2} - 4 \\le  0');
    expect(unicodeToTex('√(b²−4ac)')).toBe('\\sqrt{b^{2}-4ac}');
    expect(unicodeToTex('√2')).toBe('\\sqrt{2}');
    expect(unicodeToTex('θ = 30°')).toBe('\\theta  = 30^\\circ ');
    expect(unicodeToTex('H₂O')).toBe('H_{2}O');
  });

  it('leaves text groups alone', () => {
    expect(unicodeToTex('\\text{5 × 2} × 3')).toBe('\\text{5 × 2} \\times  3');
  });
});

describe('chemistry', () => {
  it('writes \\ce formulas as plain LaTeX', () => {
    expect(ceToTex('H2SO4')).toBe('\\mathrm{H}_{2}\\mathrm{S}\\mathrm{O}_{4}');
    expect(ceToTex('2H2 + O2 -> 2H2O')).toBe(
      '2\\,\\mathrm{H}_{2} + \\mathrm{O}_{2} \\rightarrow 2\\,\\mathrm{H}_{2}\\mathrm{O}'
    );
    expect(ceToTex('Cu2+')).toBe('\\mathrm{Cu}^{2+}');
    expect(ceToTex('SO4^2-')).toBe('\\mathrm{S}\\mathrm{O}_{4}^{2-}');
    expect(ceToTex('N2 + 3H2 <=> 2NH3')).toContain('\\rightleftharpoons');
    expect(ceToTex('NaCl(aq)')).toBe('\\mathrm{Na}\\mathrm{Cl}\\,\\mathrm{(aq)}');
  });

  it('prepareTex unwraps \\ce, units and numbered environments', () => {
    expect(prepareTex('\\ce{H2O}')).toBe('\\mathrm{H}_{2}\\mathrm{O}');
    expect(prepareTex('\\ce{H2O}', { keepCe: true })).toBe('\\ce{H2O}');
    expect(prepareTex('\\SI{9.8}{m/s^2}')).toBe('9.8\\,\\mathrm{m/s^2}');
    expect(prepareTex('\\begin{align*} a &= b \\label{x}\\end{align*}')).toBe('\\begin{aligned} a &= b \\end{aligned}');
    expect(prepareTex('a \\lt b')).toBe('a < b');
  });
});

describe('texToPlain', () => {
  it('reads like the formula when it cannot be typeset', () => {
    expect(texToPlain('x^{2}+\\frac{1}{2}')).toBe('x²+(1)/(2)');
    expect(texToPlain('\\sqrt{2} \\times \\pi')).toBe('√(2) × π');
    expect(texToPlain('v_{0} = 5\\,\\text{m/s}')).toBe('v₀ = 5m/s');
  });
});

describe('wrapBareLatex', () => {
  it('puts delimiters around LaTeX pasted without them', () => {
    expect(wrapBareLatex('Find x if x^2 + 2x = 8.')).toBe('Find x if \\(x^2 + 2x = 8\\).');
    expect(wrapBareLatex('If \\frac{1}{2} of a number is 5')).toBe('If \\(\\frac{1}{2}\\) of a number is 5');
    expect(wrapBareLatex('The speed is 20 m/s^2 here')).toBe('The speed is \\(20 m/s^2\\) here');
    expect(wrapBareLatex('যদি x^2 = 4 হয়')).toBe('যদি \\(x^2 = 4\\) হয়');
  });

  it('leaves ordinary text and existing formulas alone', () => {
    expect(wrapBareLatex('Save it as my_file.txt')).toBe('Save it as my_file.txt');
    expect(wrapBareLatex('Solve \\(x^2 = 4\\) now')).toBe('Solve \\(x^2 = 4\\) now');
    expect(wrapBareLatex('Prices: $5 and $10')).toBe('Prices: $5 and $10');
    expect(wrapBareLatex('No maths here.')).toBe('No maths here.');
  });
});

describe('MathML', () => {
  it('converts MathML without a LaTeX copy', () => {
    const doc = new DOMParser().parseFromString(
      '<math><mfrac><mn>1</mn><mn>2</mn></mfrac><mo>+</mo><msup><mi>x</mi><mn>2</mn></msup><mo>×</mo><msqrt><mi>y</mi></msqrt></math>',
      'text/html'
    );
    expect(mathmlToTex(doc.querySelector('math'))).toBe('\\frac{1}{2}+{x}^{2}\\times \\sqrt{y}');
  });
});

describe('clipboard HTML', () => {
  it('keeps superscripts and subscripts from Word, Google Docs and websites', () => {
    expect(htmlToPlainText('<p>H<sub>2</sub>SO<sub>4</sub> and x<sup>2</sup></p>')).toBe('H₂SO₄ and x²');
    expect(htmlToPlainText('<p>10<span style="vertical-align:super">-19</span> C</p>')).toBe('10⁻¹⁹ C');
    expect(htmlToPlainText('<p>1<sup>st</sup> law</p>')).toBe('1\\({}^{\\text{st}}\\) law');
  });

  it('turns typeset maths back into LaTeX', () => {
    const katex = '<p>Solve <span class="katex"><span class="katex-mathml"><math><semantics><mrow><mi>x</mi></mrow><annotation encoding="application/x-tex">x^2=4</annotation></semantics></math></span><span class="katex-html">x2=4</span></span></p>';
    expect(htmlToPlainText(katex)).toBe('Solve \\(x^2=4\\)');
    const mathml = '<p>Area <math><msup><mi>r</mi><mn>2</mn></msup></math></p>';
    expect(htmlToPlainText(mathml)).toBe('Area \\({r}^{2}\\)');
  });

  it('converts bare MathML and keeps list numbers and options', () => {
    expect(htmlToPlainText('<math><mfrac><mn>1</mn><mn>2</mn></mfrac><mo>+</mo><msqrt><mi>y</mi></msqrt></math>')).toBe(
      '\\(\\frac{1}{2}+\\sqrt{y}\\)'
    );
    expect(htmlToPlainText('<ol><li>What is H<sub>2</sub>O?<ol><li>Water</li><li>Salt</li></ol></li></ol>')).toBe(
      '1. What is H₂O?\nA) Water\nB) Salt'
    );
  });

  it('keeps sub/superscripts in the rich-text editor too', () => {
    expect(htmlWithLatex('<p>CO<sub>2</sub></p>')).toBe('<p>CO₂</p>');
  });
});
