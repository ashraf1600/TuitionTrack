import React, { useMemo } from 'react';
import DOMPurify from 'dompurify';
import katex from 'katex';

/**
 * Parses raw HTML, detects LaTeX delimiters ($...$ and $$...$$),
 * replaces them with KaTeX rendered markup, and runs DOMPurify.
 */
export default function MathRenderer({ content, className = '' }) {
  const sanitizedHtml = useMemo(() => {
    if (!content) return '';

    let processed = content;

    // 1. Replace block math $$...$$
    processed = processed.replace(/\$\$([\s\S]*?)\$\$/g, (match, formula) => {
      try {
        return katex.renderToString(formula.trim(), {
          displayMode: true,
          throwOnError: false,
        });
      } catch {
        return match;
      }
    });

    // 2. Replace inline math $...$ (avoiding isolated currency signs like $5000)
    processed = processed.replace(/\$([^\$\n\r]+?)\$/g, (match, formula) => {
      // If it looks just like numbers/spaces e.g. "$ 5000 ", don't render as LaTeX
      if (/^\s*\d+([\.,]\d+)?\s*$/.test(formula)) {
        return match;
      }
      try {
        return katex.renderToString(formula.trim(), {
          displayMode: false,
          throwOnError: false,
        });
      } catch {
        return match;
      }
    });

    // 3. Client-side sanitization pass using DOMPurify
    return DOMPurify.sanitize(processed, {
      ADD_TAGS: ['math', 'annotation', 'semantics', 'mrow', 'mi', 'mo', 'mn', 'msup', 'msub', 'mfrac'],
      ADD_ATTR: ['display', 'xmlns', 'mathvariant', 'colspan', 'rowspan'],
    });
  }, [content]);

  return (
    <div
      className={`exam-content prose prose-invert max-w-none prose-p:my-2 prose-headings:text-slate-100 ${className}`}
      dangerouslySetInnerHTML={{ __html: sanitizedHtml }}
    />
  );
}
