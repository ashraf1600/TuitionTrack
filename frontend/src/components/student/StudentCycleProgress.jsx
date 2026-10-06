import React from 'react';
import { Calendar, Check, Clock, CheckCircle2, CalendarDays, BookOpen } from 'lucide-react';

export default function StudentCycleProgress({ cycle }) {
  if (!cycle) {
    return (
      <div className="glass-panel p-6 rounded-2xl text-center text-slate-400">
        <Calendar className="w-10 h-10 mx-auto text-slate-600 mb-2" />
        <p className="text-sm font-semibold text-slate-300">No active tuition cycle</p>
        <p className="text-xs text-slate-500 mt-1">Your tutor will record attendance as classes take place.</p>
      </div>
    );
  }

  const {
    cycle_number,
    total_classes,
    completed_classes,
    progress_percentage,
    is_complete,
    classes_data = [],
  } = cycle;

  return (
    <div className="glass-panel p-6 rounded-2xl space-y-5">
      {/* Header — Attendance Only (NO Billing/Fee figures) */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-4 border-b border-slate-800">
        <div>
          <div className="flex items-center gap-2">
            <span className="text-xs font-bold uppercase tracking-wider px-2 py-0.5 rounded-full bg-indigo-900/60 text-indigo-300 border border-indigo-700/50">
              Cycle #{cycle_number}
            </span>
            {is_complete && (
              <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-emerald-950 text-emerald-300 border border-emerald-500/30 flex items-center gap-1">
                <CheckCircle2 className="w-3.5 h-3.5" />
                Cycle Completed
              </span>
            )}
          </div>
          <h3 className="text-lg font-bold text-slate-100 mt-1 flex items-center gap-2">
            Class Attendance & Routine Tracking
          </h3>
        </div>

        <div className="text-sm font-semibold text-slate-300">
          <span className="text-emerald-400 font-bold text-base">{completed_classes}</span> of{' '}
          <span className="text-slate-400">{total_classes}</span> classes completed ({progress_percentage}%)
        </div>
      </div>

      {/* Progress Bar */}
      <div className="w-full h-2 bg-slate-800 rounded-full overflow-hidden">
        <div
          className="h-full bg-gradient-to-r from-indigo-500 to-emerald-400 transition-all duration-300"
          style={{ width: `${progress_percentage}%` }}
        />
      </div>

      {/* Attendance Schedule Grid with Recorded Dates */}
      <div>
        <div className="flex items-center gap-1.5 text-xs text-slate-400 mb-3">
          <CalendarDays className="w-3.5 h-3.5 text-indigo-400" />
          <span>Attendance logs for each scheduled class:</span>
        </div>

        <div className="grid grid-cols-2 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-12 gap-2.5">
          {classes_data.map((cls, idx) => {
            const classNum = cls.class_no || cls.classNo || (idx + 1);
            const isCompleted = cls.completed;
            const dateObj = cls.date ? new Date(cls.date) : null;
            const formattedDate = dateObj
              ? dateObj.toLocaleDateString(undefined, {
                  month: 'short',
                  day: 'numeric',
                })
              : null;

            return (
              <div
                key={classNum}
                title={
                  isCompleted
                    ? `Class #${classNum}: Attended on ${dateObj?.toLocaleDateString()}${
                        cls.topic ? ` (${cls.topic})` : ''
                      }`
                    : `Class #${classNum}: Upcoming class`
                }
                className={`p-2.5 rounded-xl border flex flex-col items-center justify-center text-center transition ${
                  isCompleted
                    ? 'bg-emerald-600/20 border-emerald-500/40 text-emerald-300 shadow-sm shadow-emerald-500/10'
                    : 'bg-slate-800/40 border-slate-700/60 text-slate-500'
                }`}
              >
                <span className="text-xs font-bold font-mono">#{classNum}</span>

                <div className="my-1">
                  {isCompleted ? (
                    <Check className="w-4 h-4 text-emerald-400 stroke-[2.5]" />
                  ) : (
                    <Clock className="w-4 h-4 text-slate-600" />
                  )}
                </div>

                <span
                  className={`text-[10px] font-medium truncate max-w-full ${
                    isCompleted ? 'text-emerald-200' : 'text-slate-500'
                  }`}
                >
                  {formattedDate || 'Upcoming'}
                </span>

                {cls.topic && isCompleted && (
                  <span className="text-[9px] text-emerald-300/70 truncate max-w-full mt-0.5">
                    {cls.topic}
                  </span>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
