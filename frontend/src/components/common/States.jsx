import React from 'react';
import { AlertTriangle, Inbox, RefreshCw } from 'lucide-react';

/**
 * Shared loading / empty / error states, so every list and page tells the
 * user the same thing the same way. `tone="light"` is for the light student
 * pages, the default for the dark tutor pages.
 */

const TONES = {
  dark: {
    box: 'border-surface-overlay bg-surface-raised/50 text-slate-300',
    muted: 'text-slate-400',
    error: 'border-danger-500/30 bg-danger-500/10 text-danger-200',
    button: 'bg-surface-overlay hover:bg-slate-700 text-slate-100 border-surface-border',
  },
  light: {
    box: 'border-slate-200 bg-white text-slate-700',
    muted: 'text-slate-500',
    error: 'border-danger-200 bg-danger-50 text-danger-700',
    button: 'bg-white hover:bg-slate-50 text-slate-700 border-slate-300',
  },
};

export function Spinner({ className = 'w-6 h-6', label = 'Loading' }) {
  return (
    <span
      role="status"
      aria-label={label}
      className={`inline-block rounded-full border-2 border-brand-500/25 border-t-brand-500 animate-spin ${className}`}
    />
  );
}

export function LoadingState({ label = 'Loading…', tone = 'dark', className = '' }) {
  const t = TONES[tone] || TONES.dark;
  return (
    <div className={`flex items-center justify-center gap-3 py-10 text-sm ${t.muted} ${className}`}>
      <Spinner className="w-5 h-5" label={label} />
      <span>{label}</span>
    </div>
  );
}

export function EmptyState({ icon: Icon = Inbox, title, message, action, tone = 'dark', className = '' }) {
  const t = TONES[tone] || TONES.dark;
  return (
    <div className={`rounded-card border border-dashed px-6 py-10 text-center ${t.box} ${className}`}>
      <Icon className={`mx-auto mb-3 w-8 h-8 ${t.muted}`} aria-hidden="true" />
      {title && <p className="font-semibold">{title}</p>}
      {message && <p className={`mt-1 text-sm ${t.muted}`}>{message}</p>}
      {action && <div className="mt-4 flex justify-center">{action}</div>}
    </div>
  );
}

export function ErrorState({ message, onRetry, retryLabel = 'Try again', tone = 'dark', className = '' }) {
  const t = TONES[tone] || TONES.dark;
  return (
    <div role="alert" className={`flex flex-wrap items-center gap-3 rounded-xl border px-4 py-3 text-sm ${t.error} ${className}`}>
      <AlertTriangle className="w-4 h-4 shrink-0" aria-hidden="true" />
      <span className="flex-1 min-w-[12rem]">{message || 'Something went wrong.'}</span>
      {onRetry && (
        <button
          type="button"
          onClick={onRetry}
          className={`inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-semibold transition ${t.button}`}
        >
          <RefreshCw className="w-3.5 h-3.5" aria-hidden="true" />
          {retryLabel}
        </button>
      )}
    </div>
  );
}
