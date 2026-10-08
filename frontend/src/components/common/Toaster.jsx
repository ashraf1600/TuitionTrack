import React, { useEffect, useState } from 'react';
import { CheckCircle2, AlertCircle, Info, X } from 'lucide-react';
import { subscribe, dismiss } from '../../utils/toast';

const STYLES = {
  success: { icon: CheckCircle2, iconBox: 'bg-emerald-500/15 text-emerald-400 border-emerald-500/25', border: 'border-emerald-500/30' },
  error: { icon: AlertCircle, iconBox: 'bg-rose-500/15 text-rose-400 border-rose-500/25', border: 'border-rose-500/30' },
  info: { icon: Info, iconBox: 'bg-indigo-500/15 text-indigo-300 border-indigo-500/25', border: 'border-indigo-500/30' },
};

/** Renders messages sent with notify(). Mounted once, at the app root. */
export default function Toaster() {
  const [items, setItems] = useState([]);

  useEffect(() => subscribe(setItems), []);

  return (
    <div
      className="fixed z-[100] bottom-4 inset-x-4 sm:inset-x-auto sm:right-6 sm:bottom-6 flex flex-col gap-2.5 sm:w-96 pointer-events-none"
      aria-live="polite"
      role="status"
    >
      {items.map((t) => {
        const style = STYLES[t.kind] || STYLES.info;
        const Icon = style.icon;
        return (
          <div
            key={t.id}
            className={`toast-in pointer-events-auto flex items-start gap-3 rounded-2xl border ${style.border} bg-slate-900/95 backdrop-blur-xl shadow-2xl shadow-black/70 p-3.5`}
          >
            <span className={`w-7 h-7 rounded-lg border flex items-center justify-center flex-shrink-0 mt-0.5 ${style.iconBox}`}>
              <Icon className="w-4 h-4" />
            </span>
            <p className="flex-1 text-xs sm:text-sm font-medium text-slate-100 leading-snug break-words pt-0.5">{t.text}</p>
            <button
              type="button"
              onClick={() => dismiss(t.id)}
              aria-label="Dismiss message"
              className="p-1 -m-1 rounded-lg text-slate-400 hover:text-white transition"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        );
      })}
    </div>
  );
}
