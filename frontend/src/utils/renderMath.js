import DOMPurify from 'dompurify';
import katex from 'katex';
// Chemistry: \ce{H2SO4}, \ce{2H2 + O2 -> 2H2O} (registers itself with katex).
import 'katex/contrib/mhchem';
import { normalizeEscapes, prepareTex, splitCode, texToPlain, wrapBareLatex } from './scienceText';

// Every way maths arrives from ChatGPT, textbooks and our own editor:
//   $$…$$ and \[…\] (display)   ·   \(…\) and $…$ (inline)
// The inline-$ form must hug its content, so prices like "$5 and $10" stay as text.
const MATH_PATTERN = /\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)|\$(?!\s)([^$\n\r]*?[^\s$])\$(?!\d)/g;
const MONEY = /^\s*\d+([.,]\d+)?\s*$/;

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

/** One formula as HTML; an invalid one as readable text instead of raw commands. */
export function renderFormula(tex, display) {
  try {
    return katex.renderToString(prepareTex(tex.trim(), { keepCe: true }), {
      displayMode: display,
      throwOnError: true,
      // Unicode symbols and letters typed straight into a formula are fine.
      strict: 'ignore',
    });
  } catch {
    return `<span class="math-fallback">${escapeHtml(texToPlain(tex))}</span>`;
  }
}

// Placeholders that no text, HTML escaping or Markdown rule can touch.
const hold = (store, html) => {
  store.push(html);
  return `\u0000${store.length - 1}\u0000`;
};
// eslint-disable-next-line no-control-regex
const release = (text, store) => text.replace(/\u0000(\d+)\u0000/g, (_, i) => store[Number(i)]);

/** Replaces every formula with a placeholder holding its typeset HTML. */
function holdMath(text, store, { fromHtml }) {
  return text.replace(MATH_PATTERN, (whole, dollars, brackets, parens, inline) => {
    // "$ 5000 $"-style numbers are money, not maths.
    if (inline !== undefined && MONEY.test(inline)) return whole;
    const display = dollars !== undefined || brackets !== undefined;
    let tex = dollars ?? brackets ?? parens ?? inline;
    // Inside rich-text HTML the formula has been entity-encoded (and may hold a <br>).
    if (fromHtml) tex = decodeEntities(tex.replace(/<br\s*\/?>/gi, ' ').replace(/<\/?[a-z][^>]*>/gi, ''));
    return hold(store, renderFormula(tex, display));
  });
}

/** The little Markdown ChatGPT uses: **bold** and # headings (on escaped text). */
function markdownLite(escaped) {
  return escaped
    .split('\n')
    .map((line) => {
      const heading = /^\s*#{1,6}\s+(.*)$/.exec(line);
      return heading ? `<strong>${heading[1]}</strong>` : line;
    })
    .join('\n')
    .replace(/\*\*(?=\S)([^\n]*?\S)\*\*/g, '<strong>$1</strong>');
}

/** Literal text (an MCQ question or option): line breaks kept, maths typeset. */
function renderPlain(content) {
  const store = [];
  const html = splitCode(content)
    .map((part) => {
      if (part.code) {
        const code = escapeHtml(part.text);
        return hold(store, part.block ? `<pre><code>${code}</code></pre>` : `<code>${code}</code>`);
      }
      const withMath = holdMath(wrapBareLatex(part.text), store, { fromHtml: false });
      return markdownLite(escapeHtml(withMath)).replace(/\r?\n/g, '<br />');
    })
    .join('');
  return release(html, store);
}

/** Rich-text HTML (the written paper, a solution): formulas typeset, code left alone. */
function renderRich(content) {
  const store = [];
  // Code and preformatted blocks are never maths.
  let html = content.replace(/<(pre|code)\b[^>]*>[\s\S]*?<\/\1>/gi, (block) => hold(store, block));
  // Delimited formulas first: a display formula may span paragraphs (<p>$$</p><p>…</p><p>$$</p>).
  html = holdMath(html, store, { fromHtml: true });
  // Then LaTeX pasted without $…$: only the text between tags is looked at.
  html = html.replace(/(^|>)([^<]+)(?=<|$)/g, (_, before, text) => before + wrapBareLatex(text));
  html = holdMath(html, store, { fromHtml: true });
  html = html
    .replace(/<p>\s*#{1,6}\s+([\s\S]*?)<\/p>/gi, '<p><strong>$1</strong></p>')
    .replace(/\*\*(?=\S)([^<>\n]*?\S)\*\*/g, '<strong>$1</strong>');
  return release(html, store);
}

/**
 * Turn text or HTML containing LaTeX into safe HTML with the maths typeset.
 * `plain` treats everything outside the maths as literal text (so "a < b" or a
 * stray tag in a pasted question is shown, not interpreted) and keeps line breaks.
 * The stored content is never changed: all of this happens when it is shown.
 */
export function renderMathToHtml(content, { plain = false } = {}) {
  if (content === null || content === undefined || content === '') return '';
  // Doubled backslashes from JSON or code ("\\times") made single again.
  const source = normalizeEscapes(String(content));
  const html = plain ? renderPlain(source) : renderRich(source);
  return DOMPurify.sanitize(html, {
    ADD_TAGS: ['math', 'annotation', 'semantics', 'mrow', 'mi', 'mo', 'mn', 'msup', 'msub', 'mfrac'],
    ADD_ATTR: ['display', 'xmlns', 'mathvariant', 'colspan', 'rowspan'],
  });
}
