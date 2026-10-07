import React, { useState } from 'react';
import { Hash, Send, Loader2, CheckCircle2, Clock, XCircle, Sparkles, Lock } from 'lucide-react';
import { api } from '../../api/client';
import { notify } from '../../utils/toast';

const STATUS_STYLE = {
  PENDING: { label: 'Waiting for tutor', icon: Clock, cls: 'bg-amber-500/15 text-amber-300 border-amber-500/30' },
  ACCEPTED: { label: 'Connected', icon: CheckCircle2, cls: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30' },
  REJECTED: { label: 'Declined', icon: XCircle, cls: 'bg-rose-500/15 text-rose-300 border-rose-500/30' },
};

/**
 * TutorCodeConnect — Student "Unassigned State" UI
 *
 * Displays when a student has no connected tutors yet.
 * Students enter a 6-character tutor invite code to send a connection request.
 * Also shows existing pending/accepted/rejected connections.
 */
export default function TutorCodeConnect({ connections = [], onChanged }) {
  const [code, setCode] = useState('');
  const [message, setMessage] = useState('');
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  const handleCodeChange = (e) => {
    const val = e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 6);
    setCode(val);
    setError('');
    setSuccess('');
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (code.length < 4) {
      setError('Please enter a valid tutor code (4–6 characters).');
      return;
    }
    setSending(true);
    setError('');
    setSuccess('');
    try {
      await api.connectByCode(code, message.trim());
      setSuccess('Request sent! Waiting for the tutor to accept.');
      setCode('');
      setMessage('');
      onChanged?.();
      notify.success('Connection request sent successfully!');
    } catch (err) {
      setError(err.message || 'Something went wrong. Please try again.');
    } finally {
      setSending(false);
    }
  };

  const pendingCount = connections.filter((c) => c.status === 'PENDING').length;
  const acceptedCount = connections.filter((c) => c.status === 'ACCEPTED').length;

  return (
    <div className="space-y-6">
      {/* Hero invite-code card */}
      <div className="relative overflow-hidden rounded-2xl border border-indigo-500/20 bg-gradient-to-br from-slate-900 via-indigo-950/30 to-slate-900 p-6 sm:p-8">
        <div className="pointer-events-none absolute -top-10 -right-10 w-48 h-48 bg-indigo-600/10 rounded-full blur-3xl" />
        <div className="pointer-events-none absolute -bottom-8 -left-8 w-36 h-36 bg-violet-600/10 rounded-full blur-3xl" />

        <div className="relative">
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-indigo-500/15 border border-indigo-500/30 text-indigo-300 text-[10px] font-bold tracking-wider uppercase">
            <Sparkles className="w-3 h-3" /> New Connection
          </span>

          <h2 className="text-xl sm:text-2xl font-extrabold text-slate-100 mt-3">
            Connect to your Tutor
          </h2>
          <p className="text-sm text-slate-400 mt-1 max-w-md">
            Ask your tutor for their{' '}
            <span className="font-bold text-indigo-300">6-character invite code</span>. Enter it
            below to send a connection request.
          </p>

          <form onSubmit={handleSubmit} className="mt-6 space-y-4">
            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">
                Tutor Invite Code
              </label>
              <div className="relative">
                <Hash className="w-5 h-5 text-indigo-400 absolute left-3.5 top-1/2 -translate-y-1/2" />
                <input
                  type="text"
                  id="tutor-code-input"
                  value={code}
                  onChange={handleCodeChange}
                  placeholder="A3B7XZ"
                  maxLength={6}
                  autoComplete="off"
                  spellCheck={false}
                  className="w-full sm:w-64 pl-10 pr-4 py-3 rounded-xl bg-slate-800/80 border border-slate-700 text-slate-100 text-lg font-mono font-bold tracking-[0.35em] placeholder:text-slate-600 placeholder:tracking-[0.25em] focus:outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20 transition-all uppercase"
                />
                {code.length === 6 && (
                  <CheckCircle2 className="w-5 h-5 text-emerald-400 absolute right-3 top-1/2 -translate-y-1/2" />
                )}
              </div>
              <div className="flex gap-1.5 mt-2">
                {Array.from({ length: 6 }).map((_, i) => (
                  <div key={i} className={`h-1 w-5 rounded-full transition-all duration-200 ${i < code.length ? 'bg-indigo-400' : 'bg-slate-700'}`} />
                ))}
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">
                Message to Tutor <span className="font-normal normal-case text-slate-500">(optional)</span>
              </label>
              <textarea
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                maxLength={500}
                rows={2}
                placeholder="e.g. I'm in Class 10 and need help with Physics."
                className="w-full px-3.5 py-2.5 rounded-xl bg-slate-800/80 border border-slate-700 text-sm text-slate-100 placeholder:text-slate-600 focus:outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20 transition-all resize-none"
              />
            </div>

            {error && (
              <div className="flex items-start gap-2 px-3.5 py-2.5 rounded-xl bg-rose-500/10 border border-rose-500/25 text-rose-300 text-sm">
                <XCircle className="w-4 h-4 flex-shrink-0 mt-0.5" /> {error}
              </div>
            )}
            {success && (
              <div className="flex items-start gap-2 px-3.5 py-2.5 rounded-xl bg-emerald-500/10 border border-emerald-500/25 text-emerald-300 text-sm">
                <CheckCircle2 className="w-4 h-4 flex-shrink-0 mt-0.5" /> {success}
              </div>
            )}

            <button
              type="submit"
              id="send-connection-request-btn"
              disabled={sending || code.length < 4}
              className="flex items-center gap-2 px-5 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed text-white text-sm font-bold transition-all duration-200 shadow-lg shadow-indigo-500/20"
            >
              {sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
              {sending ? 'Sending…' : 'Send Request'}
            </button>
          </form>
        </div>
      </div>

      {/* Existing connections */}
      {connections.length > 0 && (
        <div className="rounded-2xl border border-slate-800 bg-slate-900/60 p-5">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-sm font-bold text-slate-200">My Connection Requests</h3>
            <div className="flex gap-2">
              {pendingCount > 0 && (
                <span className="px-2.5 py-0.5 rounded-full bg-amber-500/15 border border-amber-500/30 text-amber-300 text-[10px] font-bold">{pendingCount} pending</span>
              )}
              {acceptedCount > 0 && (
                <span className="px-2.5 py-0.5 rounded-full bg-emerald-500/15 border border-emerald-500/30 text-emerald-300 text-[10px] font-bold">{acceptedCount} connected</span>
              )}
            </div>
          </div>
          <ul className="space-y-2.5">
            {connections.map((c) => {
              const s = STATUS_STYLE[c.status] || STATUS_STYLE.PENDING;
              const Icon = s.icon;
              return (
                <li key={c.id} className="flex items-center justify-between gap-3 px-4 py-3 rounded-xl bg-slate-800/40 border border-slate-700/60">
                  <div className="flex items-center gap-3 min-w-0">
                    <div className="w-9 h-9 rounded-full bg-gradient-to-br from-indigo-500 to-violet-500 flex items-center justify-center text-white text-xs font-bold flex-shrink-0 uppercase">
                      {(c.tutor_name || 'T')[0]}
                    </div>
                    <div className="min-w-0">
                      <div className="text-sm font-semibold text-slate-100 truncate">{c.tutor_name}</div>
                      <div className="text-[11px] text-slate-500 font-mono">@{c.tutor_username}</div>
                    </div>
                  </div>
                  <span className={`px-2.5 py-0.5 rounded-full text-[10px] font-bold border flex items-center gap-1 flex-shrink-0 ${s.cls}`}>
                    <Icon className="w-3 h-3" /> {s.label}
                  </span>
                </li>
              );
            })}
          </ul>
        </div>
      )}

      {connections.length === 0 && (
        <div className="flex items-center gap-3 text-xs text-slate-500 px-2">
          <Lock className="w-3.5 h-3.5 flex-shrink-0" />
          Your tuition groups and homework will appear once your tutor accepts your request.
        </div>
      )}
    </div>
  );
}
