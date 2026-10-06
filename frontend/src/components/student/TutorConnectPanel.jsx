import React, { useEffect, useState } from 'react';
import { Search, Send, Clock, CheckCircle2, XCircle, UserSearch, Loader2 } from 'lucide-react';
import { api } from '../../api/client';

const STATUS = {
  PENDING: { label: 'Waiting for tutor', icon: Clock, cls: 'bg-amber-500/15 text-amber-300 border-amber-500/30' },
  ACCEPTED: { label: 'Connected', icon: CheckCircle2, cls: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30' },
  REJECTED: { label: 'Declined', icon: XCircle, cls: 'bg-rose-500/15 text-rose-300 border-rose-500/30' },
};

/**
 * Student side of the connection flow: see the tutors you asked to join and
 * find another tutor by name or username to send a request to.
 */
export default function TutorConnectPanel({ connections = [], onChanged, defaultOpen = false }) {
  const [open, setOpen] = useState(defaultOpen);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);
  const [searching, setSearching] = useState(false);
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!open) return undefined;
    const term = query.trim();
    const timer = setTimeout(async () => {
      setSearching(true);
      try {
        const data = await api.getTutors(term);
        setResults(Array.isArray(data) ? data : data.results || []);
      } catch {
        setResults([]);
      } finally {
        setSearching(false);
      }
    }, 300);
    return () => clearTimeout(timer);
  }, [query, open]);

  const statusByTutor = new Map(connections.map((c) => [String(c.tutor_id), c]));

  const run = async (key, fn) => {
    setBusy(key);
    setError('');
    try {
      await fn();
      onChanged?.();
    } catch (err) {
      setError(err.message || 'Something went wrong.');
    } finally {
      setBusy(null);
    }
  };

  const sendRequest = (tutor) =>
    run(tutor.id, async () => {
      await api.sendConnectionRequest(tutor.id, message.trim());
      setMessage('');
    });

  const withdraw = (connection) => {
    if (!window.confirm(`Withdraw your request to ${connection.tutor_name}?`)) return;
    run(connection.id, () => api.withdrawConnection(connection.id));
  };

  return (
    <section className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5 sm:p-6 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h3 className="text-lg font-bold text-slate-100 flex items-center gap-2">
            <UserSearch className="w-5 h-5 text-indigo-400" />
            My tutors
          </h3>
          <p className="text-xs text-slate-400">
            Send a request to a tutor. Once they accept and place you in a tuition group, it appears below.
          </p>
        </div>
        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          className="px-3.5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold flex items-center gap-1.5 transition"
        >
          <Search className="w-3.5 h-3.5" />
          {open ? 'Close search' : 'Find a tutor'}
        </button>
      </div>

      {error && (
        <div className="px-3.5 py-2.5 rounded-xl bg-rose-500/10 border border-rose-500/25 text-rose-300 text-xs">{error}</div>
      )}

      {connections.length === 0 ? (
        <p className="text-sm text-slate-400 bg-slate-800/40 border border-dashed border-slate-700 rounded-xl px-4 py-5 text-center">
          No tutor requests yet. Use <strong className="text-slate-200">Find a tutor</strong> to ask a tutor to take you on.
        </p>
      ) : (
        <ul className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
          {connections.map((c) => {
            const s = STATUS[c.status] || STATUS.PENDING;
            const Icon = s.icon;
            return (
              <li key={c.id} className="flex items-center justify-between gap-3 rounded-xl bg-slate-800/50 border border-slate-700/70 px-4 py-3">
                <div className="min-w-0">
                  <div className="text-sm font-semibold text-slate-100 truncate">{c.tutor_name}</div>
                  <div className="text-[11px] text-slate-500 font-mono">@{c.tutor_username}</div>
                </div>
                <div className="flex items-center gap-2 flex-shrink-0">
                  <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold border flex items-center gap-1 ${s.cls}`}>
                    <Icon className="w-3 h-3" />
                    {s.label}
                  </span>
                  {c.status === 'PENDING' && (
                    <button
                      type="button"
                      onClick={() => withdraw(c)}
                      disabled={busy === c.id}
                      className="text-[11px] text-slate-400 hover:text-rose-300 underline underline-offset-2 disabled:opacity-50"
                    >
                      Withdraw
                    </button>
                  )}
                </div>
              </li>
            );
          })}
        </ul>
      )}

      {open && (
        <div className="rounded-xl bg-slate-950/50 border border-slate-800 p-4 space-y-3">
          <div className="relative">
            <Search className="w-4 h-4 text-slate-500 absolute left-3 top-3" />
            <input
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search by tutor name, username or subject…"
              className="w-full pl-9 pr-3 py-2.5 rounded-xl bg-slate-800 border border-slate-700 text-sm text-slate-100 focus:outline-none focus:border-indigo-500"
            />
          </div>
          <input
            type="text"
            value={message}
            maxLength={500}
            onChange={(e) => setMessage(e.target.value)}
            placeholder="Optional note to the tutor (e.g. Class 10, need help with Math)"
            className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
          />

          {searching ? (
            <div className="flex items-center gap-2 text-xs text-slate-400 py-3">
              <Loader2 className="w-4 h-4 animate-spin" /> Searching…
            </div>
          ) : results.length === 0 ? (
            <p className="text-xs text-slate-500 py-3">No tutors match that search.</p>
          ) : (
            <ul className="space-y-2 max-h-72 overflow-y-auto pr-1">
              {results.map((t) => {
                const existing = statusByTutor.get(String(t.id));
                const canSend = !existing || existing.status === 'REJECTED';
                return (
                  <li key={t.id} className="flex items-center justify-between gap-3 rounded-xl bg-slate-800/50 border border-slate-700/70 px-4 py-3">
                    <div className="min-w-0">
                      <div className="text-sm font-semibold text-slate-100 truncate">
                        {t.name} <span className="text-[11px] font-normal text-slate-500 font-mono">@{t.username}</span>
                      </div>
                      <div className="text-[11px] text-slate-400 truncate">
                        {t.tuitions?.length ? t.tuitions.map((x) => x.title).join(' · ') : 'No tuition groups listed yet'}
                      </div>
                    </div>
                    {canSend ? (
                      <button
                        type="button"
                        onClick={() => sendRequest(t)}
                        disabled={busy === t.id}
                        className="flex-shrink-0 px-3 py-1.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold flex items-center gap-1.5 transition disabled:opacity-50"
                      >
                        {busy === t.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Send className="w-3.5 h-3.5" />}
                        {existing ? 'Ask again' : 'Send request'}
                      </button>
                    ) : (
                      <span className="flex-shrink-0 text-[11px] text-slate-400">
                        {existing.status === 'ACCEPTED' ? 'Connected' : 'Request sent'}
                      </span>
                    )}
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      )}
    </section>
  );
}
