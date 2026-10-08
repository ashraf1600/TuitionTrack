import React, { useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { GraduationCap, AlertCircle, Loader2, CheckCircle2 } from 'lucide-react';
import { api } from '../api/client';
import PasswordField from '../components/common/PasswordField';

/** Landing page for the link in the password-reset email: /reset-password?uid=…&token=… */
export default function ResetPasswordPage() {
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const uid = params.get('uid') || '';
  const token = params.get('token') || '';

  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [done, setDone] = useState(false);

  const mismatch = confirm.length > 0 && password !== confirm;
  const linkBroken = !uid || !token;

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    if (password !== confirm) {
      setError('The two passwords do not match.');
      return;
    }
    setSaving(true);
    try {
      await api.confirmPasswordReset(uid, token, password);
      setDone(true);
    } catch (err) {
      setError(err.message || 'Could not reset the password.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex items-center justify-center px-4 py-10">
      <div className="w-full max-w-md">
        <Link to="/login" className="flex items-center gap-2.5 mb-8 group">
          <span className="w-10 h-10 rounded-xl bg-gradient-to-tr from-indigo-600 to-violet-500 flex items-center justify-center text-white shadow-md shadow-indigo-600/25 group-hover:scale-105 transition-transform">
            <GraduationCap className="w-5 h-5" />
          </span>
          <span className="text-xl font-bold tracking-tight">Tuition<span className="text-indigo-400">Track</span></span>
        </Link>

        {done ? (
          <div>
            <CheckCircle2 className="w-10 h-10 text-emerald-400 mb-4" />
            <h1 className="text-2xl font-extrabold tracking-tight">Password changed</h1>
            <p className="mt-1.5 text-sm text-slate-400">You can now sign in with your new password.</p>
            <button
              type="button"
              onClick={() => navigate('/login')}
              className="mt-6 w-full py-3 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-sm transition"
            >
              Go to sign in
            </button>
          </div>
        ) : linkBroken ? (
          <div>
            <h1 className="text-2xl font-extrabold tracking-tight">This link is not complete</h1>
            <p className="mt-1.5 text-sm text-slate-400">
              Open the link from your email again, or request a new one from the sign-in page.
            </p>
            <Link to="/login" className="mt-6 inline-block text-sm font-semibold text-indigo-300 hover:text-white underline underline-offset-2">
              Back to sign in
            </Link>
          </div>
        ) : (
          <>
            <h1 className="text-2xl font-extrabold tracking-tight">Choose a new password</h1>
            <p className="mt-1.5 text-sm text-slate-400">This link works once and expires after a while.</p>

            {error && (
              <div role="alert" className="mt-5 p-3.5 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-200 text-sm flex items-start gap-2.5">
                <AlertCircle className="w-5 h-5 flex-shrink-0 text-rose-400" />
                <span>{error}</span>
              </div>
            )}

            <form onSubmit={handleSubmit} className="mt-6 space-y-4">
              <PasswordField id="new-password" label="New password" value={password} onChange={setPassword} minLength={8} hint="At least 8 characters, not only numbers." />
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
                Save new password
              </button>
            </form>
          </>
        )}
      </div>
    </div>
  );
}
