import React from 'react';

export default function StatusBadge({ status, className = '' }) {
  const normStatus = (status || '').toLowerCase();

  switch (normStatus) {
    case 'running':
      return (
        <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-emerald-950/80 text-emerald-300 border border-emerald-500/30 animate-pulse ${className}`}>
          <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-ping" />
          Running
        </span>
      );

    case 'scheduled':
      return (
        <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-slate-800 text-slate-300 border border-slate-700 ${className}`}>
          <span className="w-1.5 h-1.5 rounded-full bg-slate-400" />
          Scheduled
        </span>
      );

    case 'submitted':
      return (
        <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-indigo-950/80 text-indigo-300 border border-indigo-500/30 ${className}`}>
          <span className="w-1.5 h-1.5 rounded-full bg-indigo-400" />
          Submitted
        </span>
      );

    case 'delayed':
      return (
        <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-amber-950/80 text-amber-300 border border-amber-500/30 ${className}`}>
          <span className="w-1.5 h-1.5 rounded-full bg-amber-400" />
          Delayed
        </span>
      );

    case 'missed':
      return (
        <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-rose-950/80 text-rose-300 border border-rose-500/30 ${className}`}>
          <span className="w-1.5 h-1.5 rounded-full bg-rose-400" />
          Missed
        </span>
      );

    default:
      return (
        <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-slate-800 text-slate-400 border border-slate-700 ${className}`}>
          {status || 'Unknown'}
        </span>
      );
  }
}
