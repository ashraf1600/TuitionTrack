import React, { useEffect, useRef } from 'react';
import { AlertTriangle, HelpCircle } from 'lucide-react';

/** The dialog drawn by confirmAction() in ConfirmDialog.jsx. */
export default function ConfirmView({ title, message, confirmLabel, cancelLabel, danger, onConfirm, onCancel }) {
  const confirmRef = useRef(null);

  useEffect(() => {
    const onKey = (e) => {
      if (e.key === 'Escape') onCancel();
    };
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    window.addEventListener('keydown', onKey);
    confirmRef.current?.focus();
    return () => {
      document.body.style.overflow = prev;
      window.removeEventListener('keydown', onKey);
    };
  }, [onCancel]);

  const Icon = danger ? AlertTriangle : HelpCircle;

  return (
    <div className="fixed inset-0 z-[60] flex items-end sm:items-center justify-center sm:p-6">
      <div
        className="fixed inset-0 bg-slate-950/80 backdrop-blur-md"
        onClick={onCancel}
        aria-hidden="true"
      />
      <div
        role="alertdialog"
        aria-modal="true"
        aria-label={title}
        className="modal-in relative w-full max-w-md bg-slate-900/95 border border-slate-800/90 rounded-t-3xl sm:rounded-2xl shadow-2xl shadow-black/80 z-10 p-5 sm:p-6 space-y-4"
      >
        <div className="flex items-start gap-3.5">
          <span
            className={`w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 border ${
              danger
                ? 'bg-rose-500/15 text-rose-400 border-rose-500/30'
                : 'bg-indigo-500/15 text-indigo-300 border-indigo-500/30'
            }`}
          >
            <Icon className="w-5 h-5" />
          </span>
          <div className="min-w-0">
            <h3 className="text-base font-bold text-white tracking-tight">{title}</h3>
            {message && <p className="text-sm text-slate-400 mt-1 leading-relaxed">{message}</p>}
          </div>
        </div>
        <div className="flex items-center justify-end gap-2 pt-1">
          <button
            type="button"
            onClick={onCancel}
            className="px-4 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-semibold border border-slate-700 transition"
          >
            {cancelLabel}
          </button>
          <button
            ref={confirmRef}
            type="button"
            onClick={onConfirm}
            className={`px-4 py-2 rounded-xl text-white text-xs font-bold transition flex items-center gap-1.5 ${
              danger
                ? 'bg-rose-600 hover:bg-rose-500 shadow-md shadow-rose-600/25'
                : 'bg-indigo-600 hover:bg-indigo-500 shadow-md shadow-indigo-600/25'
            }`}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

