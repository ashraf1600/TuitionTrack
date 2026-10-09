import React, { useState } from 'react';
import { Inbox, Check, X, GraduationCap, MapPin, Phone, School, RefreshCw, Loader2, MessageSquare } from 'lucide-react';
import { api } from '../../api/client';
import { confirmAction } from '../common/ConfirmDialog';

/**
 * The tutor's inbox of students waiting for a place.
 *
 * Two kinds of rows come from /students/unassigned/:
 *   - a PENDING connection request — the student picked this tutor and is waiting
 *     for an answer (accept into a group, accept for later, or decline);
 *   - a student who is already theirs but is not in any tuition group yet.
 */
export default function ConnectionRequestsPanel({ students = [], tuitions = [], onChanged, onRefresh, onCreateTuition }) {
  const [choice, setChoice] = useState({}); // student id -> chosen tuition id
  const [busy, setBusy] = useState(null);
  const [error, setError] = useState('');

  if (!students.length) return null;

  const pendingCount = students.filter((s) => s.request_status === 'PENDING').length;

  const run = async (studentId, fn) => {
    setBusy(studentId);
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

  const tuitionFor = (student) => choice[student.id] ?? (tuitions.length === 1 ? tuitions[0].id : '');

  const handleAdd = (student) => {
    const tuitionId = tuitionFor(student);
    if (!tuitionId) {
      setError(`Choose a tuition group for ${student.full_name} first.`);
      return;
    }
    run(student.id, () =>
      student.request_status === 'PENDING' && student.request_id
        ? api.acceptConnection(student.request_id, tuitionId)
        : api.enrollInTuition(tuitionId, student.id)
    );
  };

  const handleAcceptOnly = (student) => run(student.id, () => api.acceptConnection(student.request_id));

  const handleDecline = async (student) => {
    const ok = await confirmAction({
      title: 'Decline request?',
      message: `Decline the request from ${student.full_name}? They will need to send a new one.`,
      confirmLabel: 'Decline',
      danger: true,
    });
    if (!ok) return;
    run(student.id, () => api.rejectConnection(student.request_id));
  };

  return (
    <section className="rounded-2xl border border-amber-500/25 bg-gradient-to-br from-amber-500/[0.07] via-slate-900/60 to-slate-900/60 p-5 sm:p-6 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-amber-500/15 text-amber-300 border border-amber-500/30 flex items-center justify-center">
            <Inbox className="w-5 h-5" />
          </div>
          <div>
            <h3 className="font-bold text-slate-100 flex items-center gap-2">
              Students waiting for a group
              <span className="px-2 py-0.5 rounded-full text-[11px] bg-amber-400 text-slate-950 font-extrabold">
                {students.length}
              </span>
            </h3>
            <p className="text-xs text-slate-400">
              {pendingCount > 0
                ? `${pendingCount} new request${pendingCount === 1 ? '' : 's'} from students who chose you. Add them to a tuition group to get started.`
                : 'These students are yours but are not in a tuition group yet.'}
            </p>
          </div>
        </div>
        {onRefresh && (
          <button
            type="button"
            onClick={onRefresh}
            className="p-2 rounded-xl bg-slate-800/80 hover:bg-slate-700 text-slate-400 hover:text-slate-200 border border-slate-700 transition"
            title="Refresh"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
        )}
      </div>

      {error && (
        <div className="px-3.5 py-2.5 rounded-xl bg-rose-500/10 border border-rose-500/25 text-rose-300 text-xs">{error}</div>
      )}

      {tuitions.length === 0 && (
        <div className="px-3.5 py-3 rounded-xl bg-slate-800/60 border border-slate-700 text-xs text-slate-300 flex flex-wrap items-center justify-between gap-3">
          <span>Create your first tuition group, then add these students to it.</span>
          {onCreateTuition && (
            <button
              type="button"
              onClick={onCreateTuition}
              className="px-3 py-1.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white font-bold transition"
            >
              Create tuition group
            </button>
          )}
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
        {students.map((st) => {
          const isPending = st.request_status === 'PENDING';
          const isBusy = busy === st.id;
          return (
            <div key={st.id} className="rounded-xl bg-slate-900/90 border border-slate-700/70 p-4 space-y-3">
              <div className="flex items-start justify-between gap-3">
                <div className="flex items-start gap-3 min-w-0">
                  <div className="w-10 h-10 rounded-xl bg-indigo-500/15 text-indigo-300 border border-indigo-500/25 flex items-center justify-center font-bold flex-shrink-0">
                    {(st.full_name || st.username || 'S').charAt(0).toUpperCase()}
                  </div>
                  <div className="min-w-0">
                    <div className="font-bold text-slate-100 text-sm truncate">{st.full_name || st.username}</div>
                    <div className="text-[11px] text-slate-500 font-mono">@{st.username}</div>
                  </div>
                </div>
                <span
                  className={`flex-shrink-0 px-2 py-0.5 rounded-full text-[10px] font-bold border ${
                    isPending
                      ? 'bg-amber-500/15 text-amber-300 border-amber-500/30'
                      : 'bg-slate-800 text-slate-300 border-slate-700'
                  }`}
                >
                  {isPending ? 'New request' : 'Not in a group'}
                </span>
              </div>

              <div className="flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-slate-400">
                {st.grade_level && <span className="flex items-center gap-1"><GraduationCap className="w-3.5 h-3.5" />{st.grade_level}</span>}
                {st.institution && <span className="flex items-center gap-1"><School className="w-3.5 h-3.5" />{st.institution}</span>}
                {st.address && <span className="flex items-center gap-1"><MapPin className="w-3.5 h-3.5" />{st.address}</span>}
                {(st.phone || st.parent_phone) && <span className="flex items-center gap-1"><Phone className="w-3.5 h-3.5" />{st.phone || st.parent_phone}</span>}
              </div>

              {st.message && (
                <p className="text-xs text-slate-300 bg-slate-800/60 border border-slate-700/60 rounded-lg px-3 py-2 flex gap-2">
                  <MessageSquare className="w-3.5 h-3.5 mt-0.5 text-slate-500 flex-shrink-0" />
                  <span>{st.message}</span>
                </p>
              )}

              <div className="flex flex-wrap items-center gap-2 pt-1">
                <select
                  value={tuitionFor(st)}
                  onChange={(e) => setChoice((prev) => ({ ...prev, [st.id]: e.target.value }))}
                  disabled={tuitions.length === 0 || isBusy}
                  aria-label={`Tuition group for ${st.full_name}`}
                  className="flex-1 min-w-[150px] px-3 py-2 rounded-lg bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500 disabled:opacity-50"
                >
                  <option value="">{tuitions.length ? 'Choose a tuition group…' : 'No groups yet'}</option>
                  {tuitions.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.title} ({t.enrolled_count ?? t.enrollments?.length ?? 0} students)
                    </option>
                  ))}
                </select>
                <button
                  type="button"
                  onClick={() => handleAdd(st)}
                  disabled={isBusy || tuitions.length === 0}
                  className="px-3.5 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold flex items-center gap-1.5 transition disabled:opacity-50"
                >
                  {isBusy ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Check className="w-3.5 h-3.5" />}
                  {isPending ? 'Accept & add' : 'Add to group'}
                </button>
                {isPending && (
                  <>
                    <button
                      type="button"
                      onClick={() => handleAcceptOnly(st)}
                      disabled={isBusy}
                      title="Accept now and choose a group later"
                      className="px-3 py-2 rounded-lg bg-slate-800 hover:bg-slate-700 border border-slate-700 text-slate-200 text-xs font-semibold transition disabled:opacity-50"
                    >
                      Accept only
                    </button>
                    <button
                      type="button"
                      onClick={() => handleDecline(st)}
                      disabled={isBusy}
                      className="px-3 py-2 rounded-lg text-rose-300 hover:bg-rose-500/10 border border-rose-500/25 text-xs font-semibold flex items-center gap-1 transition disabled:opacity-50"
                    >
                      <X className="w-3.5 h-3.5" />
                      Decline
                    </button>
                  </>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}
