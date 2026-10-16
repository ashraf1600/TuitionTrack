import React, { useMemo } from 'react';
import DOMPurify from 'dompurify';
import katex from 'katex';
// Chemistry: \ce{H2SO4}, \ce{2H2 + O2 -> 2H2O} (registers itself with katex).
import 'katex/contrib/mhchem';
// Bundled with the same katex version that renders the math (the CDN copy was an older release).
import 'katex/dist/katex.min.css';
import { prepareTex, texToPlain, wrapBareLatex } from '../../utils/scienceText';

// Every way maths arrives from ChatGPT, textbooks and our own editor:
//   $$…$$ and \[…\] (display)   ·   \(…\) and $…$ (inline)
// The inline-$ form must hug its content, so prices like "$5 and $10" stay as text.
const MATH_PATTERN = /\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)|\$(?!\s)([^$\n\r]*?[^\s$])\$(?!\d)/g;

const escapeHtml = (text) =>
  text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const decodeEntities = (text) =>
  text
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&');

/**
 * Turn text or HTML containing LaTeX into safe HTML with the maths typeset.
 * `plain` treats everything outside the maths as literal text (so "a < b" or a
 * stray tag in a pasted question is shown, not interpreted) and keeps line breaks.
 */
function renderMathToHtml(content, { plain = false } = {}) {
  if (!content) return '';
  // Text pasted from elsewhere may carry LaTeX without $…$ around it
  // (in rich text, only the text between tags is looked at).
  const source = plain
    ? wrapBareLatex(String(content))
    : String(content).replace(/>([^<]+)</g, (_, text) => `>${wrapBareLatex(text)}<`);
  let html = '';
  let cursor = 0;
  const outside = (text) => (plain ? escapeHtml(text).replace(/\r?\n/g, '<br />') : text);

  for (const match of source.matchAll(MATH_PATTERN)) {
    const [whole, dollars, brackets, parens, inline] = match;
    const display = dollars !== undefined || brackets !== undefined;
    const raw = dollars ?? brackets ?? parens ?? inline;
    html += outside(source.slice(cursor, match.index));
    cursor = match.index + whole.length;

    // "$ 5000 $"-style numbers are money, not maths.
    if (inline !== undefined && /^\s*\d+([.,]\d+)?\s*$/.test(inline)) {
      html += outside(whole);
      continue;
    }
    // Inside rich-text HTML the formula has been entity-encoded (and may hold a <br>).
    const formula = plain ? raw : decodeEntities(raw.replace(/<br\s*\/?>/gi, ' ').replace(/<\/?[a-z][^>]*>/gi, ''));
    try {
      html += katex.renderToString(prepareTex(formula.trim(), { keepCe: true }), {
        displayMode: display,
        throwOnError: true,
        // Unicode symbols and letters typed straight into a formula are fine.
        strict: 'ignore',
      });
    } catch {
      // Not valid LaTeX: show it as readable text rather than raw commands.
      html += `<span class="math-fallback">${escapeHtml(texToPlain(formula))}</span>`;
    }
  }
  html += outside(source.slice(cursor));

  return DOMPurify.sanitize(html, {
    ADD_TAGS: ['math', 'annotation', 'semantics', 'mrow', 'mi', 'mo', 'mn', 'msup', 'msub', 'mfrac'],
    ADD_ATTR: ['display', 'xmlns', 'mathvariant', 'colspan', 'rowspan'],
  });
}

/**
 * Renders exam content with typeset maths.
 *   content  rich-text HTML (default) or, with `plain`, literal text such as an MCQ question or option
 *   inline   render as a <span> without block typography, for use inside a line of text
 */
export default function MathRenderer({ content, plain = false, inline = false, className = '' }) {
  const html = useMemo(() => renderMathToHtml(content, { plain }), [content, plain]);

  if (inline) {
    return <span className={className} dangerouslySetInnerHTML={{ __html: html }} />;
  }
  return (
    <div
      className={`exam-content prose prose-invert max-w-none prose-p:my-2 prose-headings:text-slate-100 ${className}`}
      dangerouslySetInnerHTML={{ __html: html }}
    />
  );
}
