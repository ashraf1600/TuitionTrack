import React, { useState } from 'react';
import { Check, RotateCcw, Users, CalendarDays, BookOpen, Loader2, PartyPopper, UserPlus, Info } from 'lucide-react';
import Modal from '../common/Modal';
import { api } from '../../api/client';
import { notify } from '../../utils/toast';
import { toDateInputValue, dateInputToIso, defaultHomeworkDue, formatShortDate, formatLongDate, formatTaka } from '../../utils/dates';

const classNoOf = (c) => Number(c.class_no ?? c.classNo);
const normRoster = (students) =>
  (students || [])
    .map((s) => ({
      id: String(s?.student_id ?? s?.id ?? s ?? ''),
      name: s?.full_name || s?.student_name || s?.username || 'Student',
    }))
    .filter((s) => s.id);

/**
 * The tutor's class tracker for one tuition group.
 *
 * The cycle belongs to the group, so there is exactly one board per tuition:
 * ticking a class here ticks it for every enrolled student and moves the
 * Tuition Wallet by one class (total fee ÷ classes in the cycle).
 */
export default function SharedCycleBoard({
  cycle,
  tuitionTitle = '',
  studentCount = 0,
  tuitionId = null,
  students = [],
  onCycleChange,
  onAddStudent = null,
  compact = false,
}) {
  const [busyClass, setBusyClass] = useState(null);
  const [error, setError] = useState('');
  const [editing, setEditing] = useState(null); // the class entry being edited
  const [editDate, setEditDate] = useState(toDateInputValue());
  const [editTopic, setEditTopic] = useState('');
  const [savingEdit, setSavingEdit] = useState(false);
  const [confirmNext, setConfirmNext] = useState(false);
  const [startingNext, setStartingNext] = useState(false);
  // Homework-for-this-class (optional, created together with Save below).
  const [hwEnabled, setHwEnabled] = useState(false);
  const [hwTitle, setHwTitle] = useState('');
  const [hwDesc, setHwDesc] = useState('');
  const [hwDue, setHwDue] = useState('');
  const [hwMode, setHwMode] = useState('per-student'); // 'per-student' | 'group'
  const [hwError, setHwError] = useState('');
  const roster = normRoster(students);
  const canAssignHw = Boolean(tuitionId) || roster.length > 0;

  if (!cycle) {
    return (
      <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-900/40 p-10 text-center">
        <CalendarDays className="w-10 h-10 mx-auto text-slate-600 mb-3" />
        <p className="text-sm font-semibold text-slate-200">No class tracker yet</p>
        <p className="text-xs text-slate-400 mt-1">Create a tuition group to start tracking classes.</p>
      </div>
    );
  }

  const total = Number(cycle.total_classes) || 0;
  const byNo = new Map((cycle.classes_data || []).map((c) => [classNoOf(c), c]));
  const classes = Array.from({ length: total }, (_, i) => byNo.get(i + 1) || { class_no: i + 1, completed: false, date: null, topic: '' });
  const completed = classes.filter((c) => c.completed).length;
  const percent = total ? Math.round((completed / total) * 100) : 0;
  const isComplete = total > 0 && completed >= total;
  const firstOpen = classes.find((c) => !c.completed);
  const nextClassNo = firstOpen ? classNoOf(firstOpen) : null;

  const save = async (classNo, isDone, dateIso = null, topic = '') => {
    setError('');
    const res = await api.toggleAttendanceClass(cycle.id, classNo, isDone, dateIso, topic);
    onCycleChange?.(res.cycle || res);
  };

  const openEditor = (cls) => {
    const classNo = classNoOf(cls);
    setEditing(cls);
    setEditDate(toDateInputValue(cls.date || new Date()));
    setEditTopic(cls.topic || '');
    // Prefill homework from the topic; tutor opts in with the checkbox.
    setHwEnabled(false);
    setHwError('');
    setHwTitle(cls.topic?.trim() ? `Class ${classNo} — ${cls.topic.trim()}` : `Class ${classNo} homework`);
    setHwDesc('');
    setHwDue(defaultHomeworkDue());
    setHwMode(roster.length > 0 ? 'per-student' : 'group');
  };

  const handleTileClick = async (cls) => {
    const classNo = classNoOf(cls);
    if (busyClass) return;
    if (cls.completed) {
      openEditor(cls);
      return;
    }
    // One click marks the class done today for the whole group.
    setBusyClass(classNo);
    try {
      await save(classNo, true, new Date().toISOString(), '');
    } catch (err) {
      setError(err.message || 'Could not update the class.');
    } finally {
      setBusyClass(null);
    }
  };

  const createHomeworkForClass = async (classNo, topic, heldDate) => {
    const title = hwTitle.trim();
    if (!title) throw new Error('Homework title is required.');
    if (!hwDue) throw new Error('Homework deadline is required.');
    const due = new Date(hwDue);
    if (Number.isNaN(due.getTime())) throw new Error('Homework deadline is invalid.');
    if (due.getTime() <= Date.now()) throw new Error('Homework deadline must be in the future.');
    const source = `Class ${classNo}${heldDate ? ` · ${formatShortDate(heldDate)}` : ''}`;
    const base = {
      title,
      description: hwDesc.trim() || (topic?.trim() ? `Topic covered: ${topic.trim()}` : ''),
      due_date: due.toISOString(),
      source_label: source,
    };
    if (hwMode === 'per-student' && roster.length > 0) {
      // One row per student so each submission is evaluated individually.
      const results = await Promise.allSettled(roster.map((s) => api.createHomework({ ...base, student: s.id })));
      const okCount = results.filter((r) => r.status === 'fulfilled').length;
      if (okCount === 0) {
        const reason = results.find((r) => r.status === 'rejected')?.reason;
        throw new Error(reason?.message || 'Could not assign homework.');
      }
      return `${okCount} homework assignment${okCount === 1 ? '' : 's'} (one per student)`;
    }
    if (!tuitionId) throw new Error('This group context is missing, so homework cannot be assigned.');
    await api.createHomework({ ...base, tuition: tuitionId });
    return '1 shared homework assignment for the group';
  };

  const handleSaveEdit = async (e) => {
    e?.preventDefault();
    if (!editing) return;
    setHwError('');
    // Validate homework first so attendance is never saved half-way with a broken assignment.
    if (hwEnabled && canAssignHw) {
      if (!hwTitle.trim()) { setHwError('Homework title is required.'); return; }
      if (!hwDue) { setHwError('Homework deadline is required.'); return; }
      if (new Date(hwDue).getTime() <= Date.now()) { setHwError('Homework deadline must be in the future.'); return; }
    }
    setSavingEdit(true);
    try {
      const classNo = classNoOf(editing);
      const heldIso = dateInputToIso(editDate);
      await save(classNo, true, heldIso, editTopic.trim());
      if (hwEnabled && canAssignHw) {
        try {
          const summary = await createHomeworkForClass(classNo, editTopic, heldIso);
          notify.success(`Class ${classNo} saved + ${summary}.`);
        } catch (hwErr) {
          notify(`Class saved, but homework failed: ${hwErr.message}`);
        }
      }
      setEditing(null);
    } catch (err) {
      setError(err.message || 'Could not save the class.');
    } finally {
      setSavingEdit(false);
    }
  };

  const handleUnmark = async () => {
    if (!editing) return;
    setSavingEdit(true);
    try {
      await save(classNoOf(editing), false);
      setEditing(null);
    } catch (err) {
      setError(err.message || 'Could not unmark the class.');
    } finally {
      setSavingEdit(false);
    }
  };

  const handleStartNext = async () => {
    setStartingNext(true);
    try {
      const res = await api.resetAttendanceCycle(cycle.id);
      onCycleChange?.(res.cycle || res);
      setConfirmNext(false);
    } catch (err) {
      setError(err.message || 'Could not start the next cycle.');
      setConfirmNext(false);
    } finally {
      setStartingNext(false);
    }
  };

  return (
    <div className="rounded-2xl border border-slate-800 bg-slate-900/70 shadow-lg overflow-hidden">
      {/* Header */}
      <div className="p-5 sm:p-6 flex flex-col lg:flex-row lg:items-center justify-between gap-4 border-b border-slate-800">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2 mb-1.5">
            <span className="text-[11px] font-bold uppercase tracking-wider px-2.5 py-0.5 rounded-full bg-indigo-500/15 text-indigo-300 border border-indigo-500/30">
              Cycle #{cycle.cycle_number}
            </span>
            <span className="text-[11px] font-semibold px-2.5 py-0.5 rounded-full bg-slate-800 text-slate-300 border border-slate-700 flex items-center gap-1.5">
              <Users className="w-3 h-3 text-indigo-400" />
              Shared by {studentCount} student{studentCount === 1 ? '' : 's'}
            </span>
          </div>
          <h3 className="text-lg font-bold text-slate-100 truncate">
            {tuitionTitle ? `${tuitionTitle} — class tracker` : 'Class tracker'}
          </h3>
          <p className="text-xs text-slate-400 mt-0.5">
            Tick a class once and it is recorded, with today's date, for everyone in this group.
          </p>
        </div>

        <div className="flex items-center gap-4 flex-shrink-0">
          <div className="text-right">
            <div className="text-2xl font-extrabold text-slate-100 leading-none">
              {completed}<span className="text-sm font-semibold text-slate-500"> / {total}</span>
            </div>
            <div className="text-[11px] text-slate-400 mt-1">classes done · {percent}%</div>
          </div>
          {isComplete && (
            <button
              type="button"
              onClick={() => setConfirmNext(true)}
              className="px-4 py-2.5 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold flex items-center gap-2 shadow-lg shadow-emerald-600/25 transition"
            >
              <RotateCcw className="w-4 h-4" />
              Start cycle #{cycle.cycle_number + 1}
            </button>
          )}
        </div>
      </div>

      {/* Progress bar */}
      <div className="h-1.5 bg-slate-800">
        <div
          className="h-full bg-gradient-to-r from-indigo-500 to-emerald-400 transition-all duration-500"
          style={{ width: `${percent}%` }}
        />
      </div>

      {/* Wallet strip — tutor only */}
      {!compact && (
        <div className="grid grid-cols-2 lg:grid-cols-4 divide-x divide-y lg:divide-y-0 divide-slate-800 border-b border-slate-800 bg-slate-950/40">
          <Stat label="Cycle fee (group)" value={formatTaka(cycle.total_fee ?? cycle.tuition_fee)} />
          <Stat label="Per class" value={formatTaka(cycle.per_class_rate)} hint="fee ÷ classes" />
          <Stat label="Earned so far" value={formatTaka(cycle.earned_revenue)} tone="emerald" hint={`${completed} × per class`} />
          <Stat label="Still to earn" value={formatTaka(cycle.pending_balance)} tone="indigo" />
        </div>
      )}

      <div className="p-5 sm:p-6 space-y-4">
        {error && (
          <div className="px-3.5 py-2.5 rounded-xl bg-rose-500/10 border border-rose-500/25 text-rose-300 text-xs">
            {error}
          </div>
        )}

        {studentCount === 0 && (
          <div className="px-3.5 py-3 rounded-xl bg-amber-500/10 border border-amber-500/25 text-amber-200 text-xs flex flex-wrap items-center justify-between gap-3">
            <span className="flex items-center gap-2">
              <Info className="w-4 h-4 flex-shrink-0" />
              No students in this group yet. You can still track classes; students see them as soon as they join.
            </span>
            {onAddStudent && (
              <button
                type="button"
                onClick={onAddStudent}
                className="px-3 py-1.5 rounded-lg bg-amber-500 hover:bg-amber-400 text-slate-950 font-bold flex items-center gap-1.5 transition"
              >
                <UserPlus className="w-3.5 h-3.5" />
                Add students
              </button>
            )}
          </div>
        )}

        {isComplete && (
          <div className="px-3.5 py-3 rounded-xl bg-emerald-500/10 border border-emerald-500/25 text-emerald-200 text-xs flex items-center gap-2">
            <PartyPopper className="w-4 h-4 flex-shrink-0" />
            All {total} classes are done — the full cycle fee is earned. Start the next cycle when you are ready.
          </div>
        )}

        <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 xl:grid-cols-8 gap-2.5">
          {classes.map((cls) => {
            const classNo = classNoOf(cls);
            const isBusy = busyClass === classNo;
            const isNext = classNo === nextClassNo;
            return (
              <button
                key={classNo}
                type="button"
                disabled={isBusy}
                onClick={() => handleTileClick(cls)}
                title={
                  cls.completed
                    ? `Class ${classNo} · ${formatLongDate(cls.date)}${cls.topic ? ` · ${cls.topic}` : ''} — click to edit`
                    : `Class ${classNo} — click to mark done today`
                }
                className={`group relative rounded-xl border p-3 text-left transition focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-400 ${
                  cls.completed
                    ? 'bg-emerald-500/10 border-emerald-500/40 hover:border-emerald-400'
                    : isNext
                    ? 'bg-indigo-500/10 border-indigo-500/50 hover:bg-indigo-500/20'
                    : 'bg-slate-800/40 border-slate-700/70 hover:border-slate-500 hover:bg-slate-800'
                }`}
              >
                <div className="flex items-center justify-between">
                  <span className={`text-[11px] font-bold ${cls.completed ? 'text-emerald-300' : 'text-slate-400'}`}>
                    Class {classNo}
                  </span>
                  <span
                    className={`w-5 h-5 rounded-md flex items-center justify-center border transition ${
                      cls.completed
                        ? 'bg-emerald-500 border-emerald-400 text-white'
                        : 'border-slate-600 text-transparent group-hover:border-indigo-400'
                    }`}
                  >
                    {isBusy ? <Loader2 className="w-3 h-3 animate-spin text-slate-300" /> : <Check className="w-3.5 h-3.5 stroke-[3]" />}
                  </span>
                </div>
                <div className={`mt-2 text-xs font-semibold ${cls.completed ? 'text-slate-100' : isNext ? 'text-indigo-300' : 'text-slate-500'}`}>
                  {cls.completed ? formatShortDate(cls.date) || 'Done' : isNext ? 'Up next' : 'Not yet'}
                </div>
                <div className="text-[10px] text-slate-400 truncate h-3.5 mt-0.5">
                  {cls.completed ? cls.topic || '' : ''}
                </div>
              </button>
            );
          })}
        </div>
      </div>

      {/* Edit a completed class */}
      {editing && (
        <Modal isOpen onClose={() => setEditing(null)} title={`Class ${classNoOf(editing)}`} maxWidth="max-w-md">
          <form onSubmit={handleSaveEdit} className="space-y-4">
            <div>
              <label className="flex items-center gap-1.5 text-xs font-semibold text-slate-300 mb-1.5">
                <CalendarDays className="w-4 h-4 text-indigo-400" />
                Date the class was held
              </label>
              <input
                type="date"
                required
                value={editDate}
                max={toDateInputValue()}
                onChange={(e) => setEditDate(e.target.value)}
                className="w-full px-3 py-2.5 rounded-xl bg-slate-800 border border-slate-700 text-sm text-slate-100 focus:outline-none focus:border-indigo-500"
              />
            </div>
            <div>
              <label className="flex items-center gap-1.5 text-xs font-semibold text-slate-300 mb-1.5">
                <BookOpen className="w-4 h-4 text-emerald-400" />
                Topic covered <span className="font-normal text-slate-500">(optional — students see this)</span>
              </label>
              <input
                type="text"
                value={editTopic}
                maxLength={255}
                onChange={(e) => setEditTopic(e.target.value)}
                placeholder="e.g. Chapter 4 — Newton's laws"
                className="w-full px-3 py-2.5 rounded-xl bg-slate-800 border border-slate-700 text-sm text-slate-100 focus:outline-none focus:border-indigo-500"
              />
            </div>
            {/* Homework for this class (optional) */}
            {canAssignHw && (
              <div className="rounded-xl border border-slate-700/80 bg-slate-800/40 p-3.5 space-y-3">
                <label className="flex items-center gap-2.5 cursor-pointer select-none">
                  <input
                    type="checkbox"
                    checked={hwEnabled}
                    onChange={(e) => setHwEnabled(e.target.checked)}
                    className="w-4 h-4 rounded accent-indigo-500"
                  />
                  <span className="text-xs font-bold text-slate-200 flex items-center gap-2">
                    <BookOpen className="w-4 h-4 text-indigo-400" />
                    Assign homework for this class
                    <span className="px-1.5 py-0.5 rounded-md bg-indigo-500/20 text-indigo-300 text-[10px] font-bold">NEW</span>
                  </span>
                </label>
                {hwEnabled && (
                  <div className="space-y-3 pt-1">
                    <div>
                      <label className="block text-[11px] font-bold text-slate-400 uppercase tracking-wider mb-1">
                        Homework title *
                      </label>
                      <input
                        type="text"
                        value={hwTitle}
                        maxLength={255}
                        onChange={(e) => setHwTitle(e.target.value)}
                        placeholder="e.g. Class 4 — Newton's laws problems"
                        className="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-sm text-slate-100 placeholder:text-slate-600 focus:outline-none focus:border-indigo-500"
                      />
                    </div>
                    <div>
                      <label className="block text-[11px] font-bold text-slate-400 uppercase tracking-wider mb-1">
                        Instructions <span className="font-normal normal-case">(optional)</span>
                      </label>
                      <textarea
                        value={hwDesc}
                        onChange={(e) => setHwDesc(e.target.value)}
                        rows={2}
                        placeholder="What should students solve or submit?"
                        className="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-sm text-slate-100 placeholder:text-slate-600 focus:outline-none focus:border-indigo-500 resize-none"
                      />
                    </div>
                    <div>
                      <label className="block text-[11px] font-bold text-slate-400 uppercase tracking-wider mb-1">
                        Deadline *
                      </label>
                      <input
                        type="datetime-local"
                        value={hwDue}
                        onChange={(e) => setHwDue(e.target.value)}
                        className="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-sm text-slate-100 focus:outline-none focus:border-indigo-500"
                      />
                    </div>
                    {roster.length > 0 && tuitionId && (
                      <div className="flex rounded-xl bg-slate-900 p-1 border border-slate-700 text-xs font-semibold">
                        <button
                          type="button"
                          onClick={() => setHwMode('per-student')}
                          className={`flex-1 py-1.5 rounded-lg transition ${hwMode === 'per-student' ? 'bg-indigo-600 text-white' : 'text-slate-400 hover:text-slate-200'}`}
                        >
                          Each student ({roster.length})
                        </button>
                        <button
                          type="button"
                          onClick={() => setHwMode('group')}
                          className={`flex-1 py-1.5 rounded-lg transition ${hwMode === 'group' ? 'bg-indigo-600 text-white' : 'text-slate-400 hover:text-slate-200'}`}
                        >
                          Whole group (shared)
                        </button>
                      </div>
                    )}
                    <p className="text-[11px] text-slate-500 leading-relaxed">
                      {hwMode === 'per-student' && roster.length > 0
                        ? `Creates ${roster.length} separate copies — one per student — so you can review and mark each done individually.`
                        : 'Creates one shared task for the whole group. Marking it done applies to everyone.'}
                    </p>
                    {hwError && (
                      <div className="px-3 py-2 rounded-xl bg-rose-500/10 border border-rose-500/25 text-rose-300 text-xs">
                        {hwError}
                      </div>
                    )}
                  </div>
                )}
              </div>
            )}
            <div className="flex items-center justify-between gap-2 pt-3 border-t border-slate-800">
              <button
                type="button"
                onClick={handleUnmark}
                disabled={savingEdit}
                className="px-3 py-2 rounded-xl border border-rose-500/30 text-rose-300 hover:bg-rose-500/10 text-xs font-semibold transition disabled:opacity-50"
              >
                Mark as not done
              </button>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => setEditing(null)}
                  className="px-3 py-2 rounded-xl text-xs font-semibold text-slate-400 hover:text-slate-200"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={savingEdit}
                  className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold transition disabled:opacity-50"
                >
                  {savingEdit ? 'Saving…' : hwEnabled && canAssignHw ? 'Save & assign' : 'Save'}
                </button>
              </div>
            </div>
          </form>
        </Modal>
      )}

      {/* Start next cycle */}
      {confirmNext && (
        <Modal isOpen onClose={() => setConfirmNext(false)} title={`Start cycle #${cycle.cycle_number + 1}?`} maxWidth="max-w-md">
          <div className="space-y-4">
            <p className="text-sm text-slate-300 leading-relaxed">
              Cycle #{cycle.cycle_number} will be saved to history with{' '}
              <strong className="text-emerald-400">{formatTaka(cycle.earned_revenue)}</strong> earned, and a fresh
              cycle will start for the whole group using the tuition's current fee and number of classes.
            </p>
            <div className="flex justify-end gap-2 pt-3 border-t border-slate-800">
              <button
                type="button"
                onClick={() => setConfirmNext(false)}
                className="px-3 py-2 rounded-xl text-xs font-semibold text-slate-400 hover:text-slate-200"
              >
                Not yet
              </button>
              <button
                type="button"
                onClick={handleStartNext}
                disabled={startingNext}
                className="px-4 py-2 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold transition disabled:opacity-50"
              >
                {startingNext ? 'Starting…' : 'Start next cycle'}
              </button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}

function Stat({ label, value, hint, tone }) {
  const color = tone === 'emerald' ? 'text-emerald-400' : tone === 'indigo' ? 'text-indigo-300' : 'text-slate-100';
  return (
    <div className="px-5 py-3.5">
      <div className="text-[10px] font-bold uppercase tracking-wider text-slate-500">{label}</div>
      <div className={`text-lg font-extrabold font-mono mt-0.5 ${color}`}>{value}</div>
      {hint && <div className="text-[10px] text-slate-500">{hint}</div>}
    </div>
  );
}
