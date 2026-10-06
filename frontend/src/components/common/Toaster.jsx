import React, { useEffect, useState } from 'react';
import { CheckCircle2, AlertCircle, Info, X } from 'lucide-react';
import { subscribe, dismiss } from '../../utils/toast';

const STYLES = {
  success: { icon: CheckCircle2, cls: 'border-emerald-500/40 text-emerald-300' },
  error: { icon: AlertCircle, cls: 'border-rose-500/40 text-rose-300' },
  info: { icon: Info, cls: 'border-indigo-500/40 text-indigo-300' },
};

/** Renders messages sent with notify(). Mounted once, at the app root. */
export default function Toaster() {
  const [items, setItems] = useState([]);

  useEffect(() => subscribe(setItems), []);

  return (
    <div
      className="fixed z-[100] bottom-4 inset-x-4 sm:inset-x-auto sm:right-5 sm:bottom-5 flex flex-col gap-2 sm:w-96 pointer-events-none"
      aria-live="polite"
      role="status"
    >
      {items.map((t) => {
        const style = STYLES[t.kind] || STYLES.info;
        const Icon = style.icon;
        return (
          <div
            key={t.id}
            className={`toast-in pointer-events-auto flex items-start gap-3 rounded-xl border bg-slate-900 shadow-2xl shadow-black/40 px-4 py-3 ${style.cls}`}
          >
            <Icon className="w-5 h-5 flex-shrink-0 mt-0.5" />
            <p className="flex-1 text-sm text-slate-100 leading-snug break-words">{t.text}</p>
            <button
              type="button"
              onClick={() => dismiss(t.id)}
              aria-label="Dismiss message"
              className="p-1 -m-1 rounded-md text-slate-500 hover:text-slate-200 transition"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        );
      })}
    </div>
  );
}
