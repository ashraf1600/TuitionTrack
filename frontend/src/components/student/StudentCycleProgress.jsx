import React from 'react';
import { Calendar, Check, CheckCircle2 } from 'lucide-react';
import { formatShortDate, formatLongDate } from '../../utils/dates';

/**
 * Read-only view of a tuition group's shared cycle for a student:
 * how many classes are done and when each was held. No fee figures —
 * the student API does not send any.
 */
export default function StudentCycleProgress({ cycle, embedded = false }) {
  if (!cycle) {
    return (
      <div className={`${embedded ? '' : 'glass-panel p-6 rounded-2xl'} text-center text-slate-400`}>
        <Calendar className="w-9 h-9 mx-auto text-slate-600 mb-2" />
        <p className="text-sm font-semibold text-slate-300">No classes recorded yet</p>
        <p className="text-xs text-slate-500 mt-1">Your tutor ticks each class here once it has been held.</p>
      </div>
    );
  }

  const total = Number(cycle.total_classes) || 0;
  const byNo = new Map((cycle.classes_data || []).map((c) => [Number(c.class_no ?? c.classNo), c]));
  const classes = Array.from({ length: total }, (_, i) => byNo.get(i + 1) || { class_no: i + 1, completed: false });
  const completed = classes.filter((c) => c.completed).length;
  const percent = total ? Math.min(100, Math.round((completed / total) * 100)) : 0;
  const nextNo = classes.find((c) => !c.completed)?.class_no ?? null;
  const lastDone = [...classes].reverse().find((c) => c.completed);

  return (
    <div className={embedded ? 'space-y-4' : 'glass-panel p-6 rounded-2xl space-y-4'}>
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-[11px] font-bold uppercase tracking-wider px-2.5 py-0.5 rounded-full bg-indigo-500/15 text-indigo-300 border border-indigo-500/30">
              Cycle #{cycle.cycle_number}
            </span>
            {cycle.is_complete && (
              <span className="text-[11px] font-semibold px-2.5 py-0.5 rounded-full bg-emerald-500/15 text-emerald-300 border border-emerald-500/30 flex items-center gap-1">
                <CheckCircle2 className="w-3.5 h-3.5" />
                Cycle complete
              </span>
            )}
          </div>
          <p className="text-xs text-slate-400 mt-1.5">
            {lastDone
              ? `Last class: ${formatLongDate(lastDone.date)}${lastDone.topic ? ` — ${lastDone.topic}` : ''}`
              : 'No class has been held in this cycle yet.'}
          </p>
        </div>
        <div className="text-right">
          <div className="text-2xl font-extrabold text-slate-100 leading-none">
            {completed}<span className="text-sm font-semibold text-slate-500"> / {total}</span>
          </div>
          <div className="text-[11px] text-slate-400 mt-1">classes done · {percent}%</div>
        </div>
      </div>

      <div className="w-full h-2 bg-slate-800 rounded-full overflow-hidden">
        <div
          className="h-full bg-gradient-to-r from-indigo-500 to-emerald-400 transition-all duration-500"
          style={{ width: `${percent}%` }}
        />
      </div>

      <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8 gap-2.5">
        {classes.map((cls) => {
          const classNo = Number(cls.class_no ?? cls.classNo);
          const isNext = classNo === Number(nextNo);
          return (
            <div
              key={classNo}
              title={
                cls.completed
                  ? `Class ${classNo} · ${formatLongDate(cls.date)}${cls.topic ? ` · ${cls.topic}` : ''}`
                  : `Class ${classNo} — not held yet`
              }
              className={`rounded-xl border p-3 ${
                cls.completed
                  ? 'bg-emerald-500/10 border-emerald-500/40'
                  : isNext
                  ? 'bg-indigo-500/10 border-indigo-500/40'
                  : 'bg-slate-800/40 border-slate-700/70'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className={`text-[11px] font-bold ${cls.completed ? 'text-emerald-300' : 'text-slate-400'}`}>
                  Class {classNo}
                </span>
                {cls.completed && (
                  <span className="w-4 h-4 rounded-md bg-emerald-500 text-white flex items-center justify-center">
                    <Check className="w-3 h-3 stroke-[3]" />
                  </span>
                )}
              </div>
              <div className={`mt-2 text-xs font-semibold ${cls.completed ? 'text-slate-100' : isNext ? 'text-indigo-300' : 'text-slate-500'}`}>
                {cls.completed ? formatShortDate(cls.date) || 'Done' : isNext ? 'Up next' : 'Not yet'}
              </div>
              <div className="text-[10px] text-slate-400 truncate h-3.5 mt-0.5">{cls.completed ? cls.topic || '' : ''}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
