import React, { useMemo, useState } from 'react';
import { CalendarCheck, Check, Clock, Loader2, AlertTriangle, X } from 'lucide-react';
import { api } from '../../api/client';
import { notify } from '../../utils/toast';
import { toDateInputValue, dateInputToIso } from '../../utils/dates';
import { useNow } from '../../hooks/useNow';

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const LOOKBACK_DAYS = 7;
const DISMISS_KEY = 'routine_dismissed_classes';

const classNoOf = (c) => Number(c.class_no ?? c.classNo);
// "sat", "SATURDAY" -> "saturday": routines saved by older versions use short names.
const dayOf = (raw) => {
  const short = String(raw || '').trim().toLowerCase().slice(0, 3);
  return WEEKDAYS.find((d) => d.toLowerCase().startsWith(short) && short.length === 3)?.toLowerCase() || '';
};
const minutesOf = (time) => {
  const match = /^(\d{1,2}):(\d{2})/.exec(String(time || '').trim());
  return match ? Number(match[1]) * 60 + Number(match[2]) : 24 * 60;
};

function readDismissed() {
  try {
    return new Set(JSON.parse(localStorage.getItem(DISMISS_KEY) || '[]'));
  } catch {
    return new Set();
  }
}

function to12h(time) {
  const match = /^(\d{1,2}):(\d{2})/.exec(time || '');
  if (!match) return time || '';
  const h = Number(match[1]);
  return `${h % 12 || 12}:${match[2]} ${h < 12 ? 'AM' : 'PM'}`;
}

/**
 * Connects the weekly routine to the class tracker.
 *
 *  - Today: only today's classes from the weekly routine, in time order, each with one tap to record it.
 *  - Not recorded: routine days in the last week with no class dated that day,
 *    so a class that was held but never ticked does not silently go unpaid.
 *
 * "Recorded" means the tuition's current cycle has a completed class dated that day.
 */
export default function TodayClassesPanel({ tuitions = [], onChanged }) {
  const [busy, setBusy] = useState(null);
  const [dismissed, setDismissed] = useState(readDismissed);

  // The calendar day, from a clock that ticks: the panel moves on to the next day by itself.
  const todayKey = toDateInputValue(new Date(useNow(60_000)));

  const { today, missed } = useMemo(() => {
    const [y, m, d] = todayKey.split('-').map(Number);
    const now = new Date(y, m - 1, d);
    const todayRows = [];
    const missedRows = [];

    tuitions.forEach((t) => {
      const cycle = t.active_cycle;
      const routine = t.routine || t.weekly_routine || [];
      if (!cycle || routine.length === 0) return;

      const classes = cycle.classes_data || [];
      const recordedDays = new Set(classes.filter((c) => c.completed && c.date).map((c) => toDateInputValue(c.date)));
      const total = Number(cycle.total_classes) || 0;
      const next = Array.from({ length: total }, (_, i) => i + 1).find(
        (n) => !classes.some((c) => classNoOf(c) === n && c.completed)
      );
      // Never look back past the start of the current cycle or the tuition itself.
      const earliest = new Date(Math.max(new Date(cycle.created_at || 0).getTime(), new Date(t.created_at || 0).getTime()));
      const earliestKey = toDateInputValue(earliest);

      for (let back = 0; back <= LOOKBACK_DAYS; back += 1) {
        const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() - back);
        const dayKey = toDateInputValue(day);
        if (back > 0 && dayKey < earliestKey) break;
        const slots = routine
          .filter((s) => dayOf(s.day) === WEEKDAYS[day.getDay()].toLowerCase())
          .sort((a, b) => minutesOf(a.start_time || a.time) - minutesOf(b.start_time || b.time));
        if (slots.length === 0) continue;
        const slot = slots[0];
        const row = {
          key: `${t.id}:${dayKey}`,
          tuition: t,
          cycle,
          dayKey,
          day,
          time: slot.start_time || slot.time || '',
          endTime: slot.end_time || '',
          recorded: recordedDays.has(dayKey),
          nextClassNo: next,
          total,
        };
        if (back === 0) todayRows.push(row);
        else if (!row.recorded && next) missedRows.push(row);
      }
    });

    todayRows.sort((a, b) => minutesOf(a.time) - minutesOf(b.time));
    missedRows.sort((a, b) => b.dayKey.localeCompare(a.dayKey));
    return { today: todayRows.map((r) => ({ ...r, isToday: r.dayKey === todayKey })), missed: missedRows };
  }, [tuitions, todayKey]);

  const visibleMissed = missed.filter((r) => !dismissed.has(r.key));
  const hasRoutine = tuitions.some((t) => (t.routine || t.weekly_routine || []).length > 0);
  if (!hasRoutine && visibleMissed.length === 0) return null;
  const doneToday = today.filter((r) => r.recorded).length;

  const record = async (row) => {
    if (!row.nextClassNo) return;
    setBusy(row.key);
    try {
      const when = row.isToday ? new Date().toISOString() : dateInputToIso(row.dayKey);
      await api.toggleAttendanceClass(row.cycle.id, row.nextClassNo, true, when, '');
      notify.success(`Class ${row.nextClassNo} recorded for ${row.tuition.title}.`);
      onChanged?.();
    } catch (err) {
      notify.error(err.message || 'Could not record the class.');
    } finally {
      setBusy(null);
    }
  };

  const dismiss = (row) => {
    const next = new Set(dismissed);
    next.add(row.key);
    setDismissed(next);
    try {
      // Keep the list short: only the most recent entries matter.
      localStorage.setItem(DISMISS_KEY, JSON.stringify([...next].slice(-200)));
    } catch {
      // not being able to remember a dismissal is harmless
    }
  };

  return (
    <section className="rounded-2xl border border-slate-800 bg-slate-900/70 overflow-hidden">
      <header className="px-5 sm:px-6 py-4 border-b border-slate-800 flex items-center gap-3">
        <span className="w-9 h-9 rounded-xl bg-emerald-500/15 text-emerald-300 border border-emerald-500/30 flex items-center justify-center">
          <CalendarCheck className="w-5 h-5" />
        </span>
        <div>
          <h3 className="font-bold text-slate-100">Today's classes</h3>
          <p className="text-xs text-slate-400">
            {new Date(`${todayKey}T00:00`).toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' })} · from your weekly routines
          </p>
        </div>
        {today.length > 0 && (
          <span className="ml-auto px-2.5 py-1 rounded-full text-xs font-bold bg-emerald-500/10 text-emerald-300 border border-emerald-500/25">
            {doneToday}/{today.length} done
          </span>
        )}
      </header>

      <div className="p-5 sm:p-6 space-y-5">
        {today.length === 0 ? (
          <p className="text-sm text-slate-400">No classes in your routine today. Enjoy the day off.</p>
        ) : (
          <ul className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {today.map((row) => (
              <li key={row.key} className={`rounded-xl border p-4 flex items-center justify-between gap-3 ${row.recorded ? 'border-emerald-500/30 bg-emerald-500/5' : 'border-slate-700 bg-slate-800/40'}`}>
                <div className="min-w-0">
                  <div className="text-sm font-bold text-slate-100 truncate">{row.tuition.title}</div>
                  <div className="text-xs text-slate-400 flex items-center gap-1.5 mt-0.5">
                    <Clock className="w-3.5 h-3.5" />
                    {to12h(row.time)}{row.endTime ? ` – ${to12h(row.endTime)}` : ''}
                    {row.nextClassNo && !row.recorded ? ` · class ${row.nextClassNo} of ${row.total}` : ''} · {row.tuition.enrolled_count ?? 0} students
                  </div>
                </div>
                {row.recorded ? (
                  <span className="flex items-center gap-1.5 text-xs font-semibold text-emerald-300 flex-shrink-0">
                    <Check className="w-4 h-4" /> Recorded
                  </span>
                ) : row.nextClassNo ? (
                  <button
                    type="button"
                    onClick={() => record(row)}
                    disabled={busy === row.key}
                    className="flex-shrink-0 px-3.5 py-2 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold flex items-center gap-1.5 transition disabled:opacity-60"
                  >
                    {busy === row.key ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Check className="w-3.5 h-3.5" />}
                    Mark class {row.nextClassNo} done
                  </button>
                ) : (
                  <span className="text-xs text-slate-400 flex-shrink-0">Cycle complete</span>
                )}
              </li>
            ))}
          </ul>
        )}

        {visibleMissed.length > 0 && (
          <div>
            <h4 className="text-xs font-bold uppercase tracking-wider text-amber-300 flex items-center gap-1.5 mb-2">
              <AlertTriangle className="w-3.5 h-3.5" />
              Scheduled but not recorded
            </h4>
            <ul className="space-y-2">
              {visibleMissed.map((row) => (
                <li key={row.key} className="rounded-xl border border-amber-500/25 bg-amber-500/5 px-4 py-3 flex flex-wrap items-center justify-between gap-3">
                  <div className="text-sm text-slate-200">
                    <span className="font-semibold">{row.tuition.title}</span>
                    <span className="text-slate-400">
                      {' '}· {row.day.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'short' })}
                      {row.time ? `, ${to12h(row.time)}` : ''}
                    </span>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => record(row)}
                      disabled={busy === row.key}
                      className="px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 border border-slate-700 text-slate-100 text-xs font-semibold flex items-center gap-1.5 transition disabled:opacity-60"
                    >
                      {busy === row.key ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Check className="w-3.5 h-3.5 text-emerald-400" />}
                      It happened — record class {row.nextClassNo}
                    </button>
                    <button
                      type="button"
                      onClick={() => dismiss(row)}
                      className="px-3 py-1.5 rounded-lg text-slate-400 hover:text-slate-100 text-xs font-semibold flex items-center gap-1 transition"
                    >
                      <X className="w-3.5 h-3.5" /> No class that day
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        )}
      </div>
    </section>
  );
}
