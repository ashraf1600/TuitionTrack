import React, { useEffect, useId, useRef } from 'react';
import { X } from 'lucide-react';

export default function Modal({ isOpen, onClose, title, children, maxWidth = 'max-w-2xl' }) {
  const titleId = useId();
  const dialogRef = useRef(null);
  // Keep the latest onClose without re-running the effect (and re-focusing) on every parent render.
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  useEffect(() => {
    if (!isOpen) return undefined;
    const handleKeyDown = (e) => {
      if (e.key === 'Escape') onCloseRef.current?.();
    };
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    window.addEventListener('keydown', handleKeyDown);
    dialogRef.current?.focus();
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center sm:p-6">
      <div className="fixed inset-0 bg-slate-950/80 backdrop-blur-sm" onClick={onClose} aria-hidden="true" />

      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        className={`modal-in relative w-full ${maxWidth} max-h-[92vh] flex flex-col bg-slate-900 border border-slate-800 rounded-t-2xl sm:rounded-2xl shadow-2xl shadow-black/50 z-10 focus:outline-none`}
      >
        <div className="flex items-center justify-between gap-4 px-5 sm:px-6 py-4 border-b border-slate-800 flex-shrink-0">
          <h3 id={titleId} className="text-lg font-bold text-slate-100 tracking-tight truncate">{title}</h3>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="p-2 -mr-2 rounded-lg text-slate-400 hover:text-slate-100 hover:bg-slate-800 transition"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="p-5 sm:p-6 overflow-y-auto">
          {children}
        </div>
      </div>
    </div>
  );
}
