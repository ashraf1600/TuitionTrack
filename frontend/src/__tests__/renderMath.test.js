// @vitest-environment jsdom
import { describe, expect, it } from 'vitest';
import { renderMathToHtml } from '../utils/renderMath';
import { parseQuestions, parseWrittenQuestions } from '../utils/mcqParser';

const formulas = (html) => (html.match(/class="katex"/g) || []).length;
const fallbacks = (html) => (html.match(/math-fallback/g) || []).length;
const text = (html) => {
  const div = document.createElement('div');
  div.innerHTML = html;
  div.querySelectorAll('.katex').forEach((k) => k.remove());
  return div.textContent;
};

// The CQ from the request, as ChatGPT gives it.
const CQ = String.raw`**প্রশ্ন ১। সূচক ও লগারিদম**
**উদ্দীপক:**
$$a=2^3\times 2^{-2},\qquad b=\log_2 8$$

ক. সূচক কাকে বলে? (১)
খ. $a^m\times a^n=a^{m+n}$ ব্যাখ্যা করো। (২)
গ. $a$-এর মান নির্ণয় করো। (৩)
ঘ. $a^b+b^a$-এর মান নির্ণয় করো। (৪)`;

describe('formulas pasted without delimiters (question and option text)', () => {
  const cases = [
    'x^2+2x+1',
    '\\frac{1}{x}',
    '3.0 \\times 10^{8}',
    '9.11 \\times 10^{-31}',
    '6.02 \\times 10^{23}',
    '\\log_2 8',
    '\\sqrt{x^2+y^2}',
    '\\begin{bmatrix}1&2\\\\3&4\\end{bmatrix}',
    'a=2^3\\times 2^{-2},\\qquad b=\\log_2 8',
    '\\alpha + \\beta \\leq \\Delta \\pm \\sum_{i=1}^{n} i \\cdot \\int_0^1 x\\,dx \\geq 0',
  ];
  for (const input of cases) {
    it(`typesets ${input}`, () => {
      const html = renderMathToHtml(input, { plain: true });
      expect(formulas(html)).toBe(1);
      expect(fallbacks(html)).toBe(0);
      expect(text(html).trim()).toBe('');
    });
  }
});

describe('delimited formulas', () => {
  it('handles \\( \\), $ $, \\[ \\] and $$ $$', () => {
    const html = renderMathToHtml('Inline \\(x^2\\) and $y^2$, display \\[z^2\\] and $$w^2$$', { plain: true });
    expect(formulas(html)).toBe(4);
    expect(html).toContain('katex-display');
  });

  it('leaves money alone', () => {
    const html = renderMathToHtml('It costs $5 and $10.', { plain: true });
    expect(formulas(html)).toBe(0);
    expect(text(html)).toBe('It costs $5 and $10.');
  });
});

describe('escaped LaTeX from JSON or code', () => {
  it('makes doubled backslashes single', () => {
    const html = renderMathToHtml('\\\\(3.0 \\\\times 10^{8}\\\\) m/s', { plain: true });
    expect(formulas(html)).toBe(1);
    expect(fallbacks(html)).toBe(0);
  });

  it('keeps a matrix row break', () => {
    const html = renderMathToHtml('$\\begin{bmatrix}1&2\\\\3&4\\end{bmatrix}$', { plain: true });
    expect(formulas(html)).toBe(1);
    expect(fallbacks(html)).toBe(0);
  });
});

describe('text that is not maths', () => {
  it('shows a plain question unchanged', () => {
    const question = 'Which gas do plants take in? < 2 options > & more';
    expect(text(renderMathToHtml(question, { plain: true }))).toBe(question);
  });

  it('keeps Bangla, Bangla numerals and line breaks', () => {
    const html = renderMathToHtml('সালোকসংশ্লেষণ কী?\nউত্তর লেখো। (১০)', { plain: true });
    expect(html).toContain('সালোকসংশ্লেষণ কী?<br>উত্তর লেখো। (১০)');
  });

  it('never treats code as maths', () => {
    const html = renderMathToHtml('Write `x_1 = a^2` in code', { plain: true });
    expect(formulas(html)).toBe(0);
    expect(html).toContain('<code>x_1 = a^2</code>');
  });

  it('does not run HTML in a question', () => {
    const html = renderMathToHtml('<img src=x onerror=alert(1)> $x^2$', { plain: true });
    expect(html).not.toContain('<img');
    expect(formulas(html)).toBe(1);
  });
});

describe('a creative question (CQ) pasted from ChatGPT', () => {
  it('shows heading, stem, sub-questions, marks and every formula', () => {
    const html = renderMathToHtml(CQ, { plain: true });
    expect(formulas(html)).toBe(4);
    expect(fallbacks(html)).toBe(0);
    expect(html).toContain('<strong>প্রশ্ন ১। সূচক ও লগারিদম</strong>');
    expect(html).toContain('<strong>উদ্দীপক:</strong>');
    const shown = text(html);
    for (const line of ['ক. সূচক কাকে বলে? (১)', 'ব্যাখ্যা করো। (২)', '-এর মান নির্ণয় করো। (৩)', '-এর মান নির্ণয় করো। (৪)']) {
      expect(shown).toContain(line);
    }
  });

  it('survives the written-paper path: parse, store as HTML, show', () => {
    // The tutor pastes it into "Paste written questions"; the paper is stored as paragraphs.
    const [question] = parseWrittenQuestions(CQ);
    const stored = question.text
      .split(/\n\s*\n/)
      .map((block) => `<p>${block.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/\n/g, '<br>')}</p>`)
      .join('');
    const html = renderMathToHtml(stored);
    expect(formulas(html)).toBe(4);
    expect(fallbacks(html)).toBe(0);
    expect(text(html)).toContain('ঘ.');
  });

  it('shows a display formula split over paragraphs by the rich-text editor', () => {
    const stored = '<p><strong>উদ্দীপক:</strong></p><p>$$</p><p>a=2^3\\times 2^{-2},\\qquad b=\\log_2 8</p><p>$$</p><p>ক. সূচক কাকে বলে? (১)</p>';
    const html = renderMathToHtml(stored);
    expect(formulas(html)).toBe(1);
    expect(fallbacks(html)).toBe(0);
    expect(text(html)).toContain('ক. সূচক কাকে বলে? (১)');
  });

  it('survives the MCQ path with escaped backslashes', () => {
    const pasted = 'If a=2^3\\\\times 2^{-2}, then a =\nA) 2\nB) 4\nC) 8\nD) 16\nAnswer: A';
    const [question] = parseQuestions(pasted).questions;
    const html = renderMathToHtml(question.question, { plain: true });
    expect(formulas(html)).toBe(1);
    expect(fallbacks(html)).toBe(0);
    expect(question.options.map((o) => renderMathToHtml(o, { plain: true }))).toEqual(['2', '4', '8', '16']);
  });
});
