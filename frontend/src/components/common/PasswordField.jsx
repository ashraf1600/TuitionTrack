import React, { useState } from 'react';
import { Eye, EyeOff, Lock } from 'lucide-react';

/** A labelled password input with a show/hide toggle. */
export default function PasswordField({ id, label, value, onChange, autoComplete = 'new-password', hint, error, minLength }) {
  const [show, setShow] = useState(false);
  return (
    <div>
      <label htmlFor={id} className="block text-sm font-medium text-slate-200 mb-1.5">{label}</label>
      <div className="relative">
        <Lock className="w-4 h-4 text-slate-500 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
        <input
          id={id}
          type={show ? 'text' : 'password'}
          required
          minLength={minLength}
          autoComplete={autoComplete}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          aria-invalid={Boolean(error)}
          className={`w-full pl-10 pr-11 py-2.5 rounded-xl bg-slate-800/80 border text-slate-100 text-sm focus:outline-none focus:ring-2 transition ${
            error ? 'border-rose-500 focus:ring-rose-500/25' : 'border-slate-700 focus:border-indigo-500 focus:ring-indigo-500/25'
          }`}
        />
        <button
          type="button"
          onClick={() => setShow((v) => !v)}
          aria-label={show ? 'Hide password' : 'Show password'}
          className="absolute right-1.5 top-1/2 -translate-y-1/2 p-2 rounded-lg text-slate-400 hover:text-slate-100"
        >
          {show ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
        </button>
      </div>
      {error ? <p className="mt-1 text-xs text-rose-300">{error}</p> : hint ? <p className="mt-1 text-xs text-slate-400">{hint}</p> : null}
    </div>
  );
}
