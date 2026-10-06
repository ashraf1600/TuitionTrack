import React, { useMemo } from 'react';
import DOMPurify from 'dompurify';
import katex from 'katex';

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
export function renderMathToHtml(content, { plain = false } = {}) {
  if (!content) return '';
  const source = String(content);
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
      html += katex.renderToString(formula.trim(), { displayMode: display, throwOnError: false });
    } catch {
      html += outside(whole);
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
