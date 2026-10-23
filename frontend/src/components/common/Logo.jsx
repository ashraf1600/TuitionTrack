import React from 'react';

/**
 * The TuitionTrack mark: a blue tile with a progress ring (classes done), a
 * check mark, and an amber dot for the next class. Same drawing as the app
 * icon (mobile/lib/widgets/tt_logo.dart). `spinning` turns it into a loader.
 */
export default function Logo({ size = 36, spinning = false, className = '', title = 'TuitionTrack' }) {
  const id = React.useId().replace(/:/g, '');
  const circumference = 2 * Math.PI * 27;
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" role="img" aria-label={title} className={className}>
      <defs>
        <linearGradient id={`tt-tile-${id}`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#5C95CB" />
          <stop offset="1" stopColor="#2B5680" />
        </linearGradient>
      </defs>
      <rect width="100" height="100" rx="28" fill={`url(#tt-tile-${id})`} />
      <circle cx="50" cy="50" r="27" fill="none" stroke="#fff" strokeOpacity="0.28" strokeWidth="7.5" />
      {spinning ? (
        <g className="tt-logo-spin" style={{ transformOrigin: '50px 50px' }}>
          <circle
            cx="50" cy="50" r="27" fill="none" stroke="#fff" strokeWidth="7.5" strokeLinecap="round"
            strokeDasharray={`${0.3 * circumference} ${circumference}`} transform="rotate(-90 50 50)"
          />
          <circle cx="50" cy="23" r="4.5" fill="#F2B84B" transform={`rotate(${0.3 * 360} 50 50)`} />
        </g>
      ) : (
        <>
          <circle
            cx="50" cy="50" r="27" fill="none" stroke="#fff" strokeWidth="7.5" strokeLinecap="round"
            strokeDasharray={`${0.82 * circumference} ${circumference}`} transform="rotate(-90 50 50)"
          />
          <circle cx="25.57" cy="38.5" r="4.5" fill="#F2B84B" />
        </>
      )}
      <path d="M38.5 51 L47 59.5 L62.5 41.5" fill="none" stroke="#fff" strokeWidth="8.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
