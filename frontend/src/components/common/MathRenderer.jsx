import React, { useMemo } from 'react';
// Bundled with the same katex version that renders the math (the CDN copy was an older release).
import 'katex/dist/katex.min.css';
import { renderMathToHtml } from '../../utils/renderMath';

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
