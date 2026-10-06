import React, { useState } from 'react';
import { ShieldCheck, AlertCircle, Loader2 } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { api } from '../api/client';
import { notify } from '../utils/toast';
import PasswordField from '../components/common/PasswordField';

/**
 * Shown instead of the app while `must_change_password` is set — i.e. someone
 * else (the tutor) chose the current password. The user sets their own before
 * going any further.
 */
export default function ForcePasswordChange() {
  const { user, refreshUser, logout } = useAuth();
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const mismatch = confirm.length > 0 && next !== confirm;

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    if (next !== confirm) {
      setError('The two new passwords do not match.');
      return;
    }
    setSaving(true);
    try {
      await api.changePassword(current, next);
      notify.success('Password changed. You are all set.');
      await refreshUser();
    } catch (err) {
      setError(err.message || 'Could not change the password.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex items-center justify-center px-4 py-10">
      <div className="w-full max-w-md">
        <div className="w-12 h-12 rounded-2xl bg-indigo-500/15 border border-indigo-500/30 text-indigo-300 flex items-center justify-center mb-5">
          <ShieldCheck className="w-6 h-6" />
        </div>
        <h1 className="text-2xl font-extrabold tracking-tight">Choose your own password</h1>
        <p className="mt-1.5 text-sm text-slate-400">
          Hi {user?.name || user?.username}. Your current password was set by your tutor. Pick a new one that only you know before you continue.
        </p>

        {error && (
          <div role="alert" className="mt-5 p-3.5 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-200 text-sm flex items-start gap-2.5">
            <AlertCircle className="w-5 h-5 flex-shrink-0 text-rose-400" />
            <span>{error}</span>
          </div>
        )}

        <form onSubmit={handleSubmit} className="mt-6 space-y-4">
          <PasswordField
            id="current-password"
            label="Password your tutor gave you"
            value={current}
            onChange={setCurrent}
            autoComplete="current-password"
          />
          <PasswordField id="new-password" label="New password" value={next} onChange={setNext} minLength={8} hint="At least 8 characters, not only numbers." />
          <PasswordField
            id="confirm-password"
            label="New password again"
            value={confirm}
            onChange={setConfirm}
            error={mismatch ? 'The passwords do not match yet.' : ''}
          />
          <button
            type="submit"
            disabled={saving}
            className="w-full py-3 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-sm flex items-center justify-center gap-2 transition disabled:opacity-60"
          >
            {saving && <Loader2 className="w-4 h-4 animate-spin" />}
            Save and continue
          </button>
        </form>

        <button type="button" onClick={logout} className="mt-5 text-sm text-slate-400 hover:text-white underline underline-offset-2">
          Sign out instead
        </button>
      </div>
    </div>
  );
}
