import React from 'react';
import { Calendar, Check, Clock, CheckCircle2 } from 'lucide-react';

export default function StudentCycleProgress({ cycle }) {
  if (!cycle) {
    return (
      <div className="glass-panel p-6 rounded-2xl text-center text-slate-400">
        <Calendar className="w-10 h-10 mx-auto text-slate-600 mb-2" />
        <p className="text-sm font-semibold text-slate-300">No active tuition cycle</p>
        <p className="text-xs text-slate-500 mt-1">Your tutor will initialize your billing cycle soon.</p>
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
    <div className="glass-panel p-6 rounded-2xl">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-4 border-b border-slate-800">
        <div>
          <span className="text-xs font-bold uppercase tracking-wider px-2 py-0.5 rounded-full bg-indigo-900/60 text-indigo-300 border border-indigo-700/50">
            Cycle #{cycle_number}
          </span>
          <h3 className="text-lg font-bold text-slate-100 mt-1 flex items-center gap-2">
            Class Attendance Progress
            {is_complete && (
              <CheckCircle2 className="w-5 h-5 text-emerald-400" />
            )}
          </h3>
        </div>

        <div className="text-sm font-semibold text-slate-300">
          <span className="text-emerald-400 font-bold text-base">{completed_classes}</span> of{' '}
          <span className="text-slate-400">{total_classes}</span> classes completed ({progress_percentage}%)
        </div>
      </div>

      {/* Progress Bar */}
      <div className="w-full h-2 bg-slate-800 rounded-full overflow-hidden my-4">
        <div
          className="h-full bg-gradient-to-r from-indigo-500 to-emerald-400 transition-all duration-300"
          style={{ width: `${progress_percentage}%` }}
        />
      </div>

      {/* Classes Grid */}
      <div className="grid grid-cols-4 sm:grid-cols-6 lg:grid-cols-12 gap-2.5">
        {classes_data.map((cls) => {
          const isCompleted = cls.completed;
          const formattedDate = cls.date
            ? new Date(cls.date).toLocaleDateString(undefined, {
                month: 'short',
                day: 'numeric',
              })
            : null;

          return (
            <div
              key={cls.classNo}
              className={`p-2.5 rounded-xl border flex flex-col items-center justify-center text-center transition ${
                isCompleted
                  ? 'bg-emerald-600/20 border-emerald-500/40 text-emerald-300'
                  : 'bg-slate-800/40 border-slate-700/60 text-slate-500'
              }`}
            >
              <span className="text-xs font-bold font-mono">#{cls.classNo}</span>
              <div className="my-1">
                {isCompleted ? (
                  <Check className="w-4 h-4 text-emerald-400 stroke-[2.5]" />
                ) : (
                  <Clock className="w-4 h-4 text-slate-600" />
                )}
              </div>
              <span className="text-[10px] text-slate-400 truncate max-w-full">
                {formattedDate || 'Upcoming'}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
