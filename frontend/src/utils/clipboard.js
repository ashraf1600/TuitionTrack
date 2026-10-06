/**
 * Pasting from a chat page (ChatGPT and the like).
 *
 * When text is selected on the page and copied, every formula arrives as the
 * page's rendered markup: the drawn symbols plus a hidden copy of the LaTeX
 * source. Pasted as it is, that becomes "f(x)=x3−6x2+11x−6f(x)=x^3-6x^2+11x-6".
 * These helpers put the original LaTeX back, wrapped in \( … \) or $$ … $$.
 */

const TEX_ANNOTATION = 'annotation[encoding="application/x-tex"]';
const BLOCK_TAGS = new Set(['P', 'DIV', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'BLOCKQUOTE', 'PRE', 'TABLE', 'UL', 'OL', 'SECTION', 'ARTICLE']);

/** True when copied HTML contains typeset maths with its LaTeX source attached. */
export function hasRenderedMath(html) {
  return Boolean(html) && html.includes('application/x-tex');
}

/** Replace every typeset formula in the document with its LaTeX source as plain text. */
function restoreLatex(doc) {
  for (const annotation of [...doc.querySelectorAll(TEX_ANNOTATION)]) {
    const latex = annotation.textContent.trim();
    const display = annotation.closest('.katex-display') || annotation.closest('math[display="block"]');
    const target = display || annotation.closest('.katex') || annotation.closest('math');
    if (!target || !target.isConnected) continue;
    target.replaceWith(doc.createTextNode(display ? `$$${latex}$$` : `\\(${latex}\\)`));
  }
}

/** For the rich-text editor: the same HTML with formulas turned back into LaTeX text. */
export function htmlWithLatex(html) {
  if (!hasRenderedMath(html)) return html;
  const doc = new DOMParser().parseFromString(html, 'text/html');
  restoreLatex(doc);
  return doc.body.innerHTML;
}

/**
 * For the paste boxes: copied HTML as plain text that keeps what the question
 * parser relies on — one line per paragraph, list numbers, bold markers and LaTeX.
 */
export function htmlToPlainText(html) {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  restoreLatex(doc);

  const walk = (node, depth) => {
    if (node.nodeType === Node.TEXT_NODE) return node.textContent.replace(/\s+/g, ' ');
    if (node.nodeType !== Node.ELEMENT_NODE) return '';
    const tag = node.tagName;
    if (tag === 'BR') return '\n';
    if (tag === 'HR') return '\n---\n';
    if (tag === 'STYLE' || tag === 'SCRIPT' || tag === 'BUTTON') return '';

    if (tag === 'OL' || tag === 'UL') {
      let number = Number(node.getAttribute('start')) || 1;
      const lines = [];
      for (const child of node.children) {
        if (child.tagName !== 'LI') continue;
        let marker = '- ';
        if (tag === 'OL') {
          // Top-level numbers are questions; a numbered list inside one is its options.
          marker = depth === 0 ? `${number}. ` : `${String.fromCharCode(64 + Math.min(number, 26))}) `;
          number += 1;
        }
        lines.push(marker + walkChildren(child, depth + 1).trim());
      }
      return `\n${lines.join('\n')}\n`;
    }
    if (tag === 'TR') {
      return `${[...node.children].map((cell) => walkChildren(cell, depth).trim()).join(' | ')}\n`;
    }

    const inner = walkChildren(node, depth);
    if ((tag === 'STRONG' || tag === 'B') && inner.trim()) return `**${inner.trim()}**`;
    return BLOCK_TAGS.has(tag) ? `\n${inner}\n` : inner;
  };
  const walkChildren = (node, depth) => [...node.childNodes].map((child) => walk(child, depth)).join('');

  return walkChildren(doc.body, 0)
    .split('\n')
    .map((line) => line.trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

/**
 * onPaste handler for a controlled <textarea>. If the clipboard holds typeset
 * maths, the cleaned-up text is inserted instead of the garbled default.
 */
export function pasteWithLatex(event, value, setValue) {
  const html = event.clipboardData?.getData('text/html');
  if (!hasRenderedMath(html)) return;
  event.preventDefault();
  const text = htmlToPlainText(html);
  const { selectionStart, selectionEnd } = event.target;
  setValue(value.slice(0, selectionStart) + text + value.slice(selectionEnd));
}
