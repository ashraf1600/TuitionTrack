import React from 'react';

// Only pictures uploaded to this app or served over http(s) are ever rendered.
const SAFE_IMAGE = /^(\/media\/|https?:\/\/)/i;

/** The picture attached to a question, on a white card so diagrams stay readable on the dark theme. */
export default function QuestionImage({ src, alt = 'Question picture', className = '' }) {
  if (!src || !SAFE_IMAGE.test(src)) return null;
  return (
    <a href={src} target="_blank" rel="noopener noreferrer" className={`inline-block ${className}`} title="Open full size">
      <img src={src} alt={alt} loading="lazy" className="max-h-64 max-w-full rounded-lg border border-slate-700 bg-white" />
    </a>
  );
}
