import React from 'react';

// Canonical pills from index.css — solid light tones readable on
// light pages AND inside dark modals. success=emerald, warning=amber,
// danger=rose, info=sky, brand=indigo. No purple one-offs.
const DOT = {
  success: 'bg-emerald-500',
  warning: 'bg-amber-500',
  danger: 'bg-rose-500',
  info: 'bg-sky-500',
  brand: 'bg-indigo-500',
  neutral: 'bg-slate-400',
};

export default function StatusBadge({ status, className = '' }) {
  const normStatus = (status || '').toLowerCase();

  const pill = (tone, dot, label) => (
    <span className={`pill pill-${tone} ${className}`}>
      {dot && <span className={`w-1.5 h-1.5 rounded-full ${DOT[tone]}`} />}
      {label}
    </span>
  );

  switch (normStatus) {
    case 'running':
      return pill('success', true, 'Running');
    case 'draft':
      return pill('neutral', false, 'Draft');
    case 'late':
      return pill('warning', true, 'Late work open');
    case 'closed':
      return pill('neutral', false, 'Closed');
    case 'scheduled':
      return pill('neutral', true, 'Scheduled');
    case 'submitted':
      return pill('brand', true, 'Submitted');
    case 'delayed':
      return pill('warning', true, 'Delayed');
    case 'missed':
      return pill('danger', true, 'Missed');
    default:
      return pill('neutral', false, status || 'Unknown');
  }
}
