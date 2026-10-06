import React from 'react';
import { Calendar, Clock, Award, ArrowRight, CheckCircle2 } from 'lucide-react';
import StatusBadge from '../common/StatusBadge';

export default function ExamCard({
  exam,
  onTakeExam,
  onViewResults,
}) {
  const {
    title,
    total_marks,
    start_time,
    end_time,
    dynamic_status,
    has_submission,
  } = exam;

  const startDate = new Date(start_time);
  const endDate = new Date(end_time);

  const isRunning = dynamic_status?.toLowerCase() === 'running';
  const isScheduled = dynamic_status?.toLowerCase() === 'scheduled';
  const isCompleted = has_submission;

  return (
    <div className="glass-panel p-5 rounded-2xl flex flex-col justify-between hover:border-slate-700 transition duration-200">
      <div>
        <div className="flex items-start justify-between gap-2 mb-2">
          <StatusBadge status={dynamic_status} />
          <div className="flex items-center gap-1 text-xs font-bold text-emerald-400 bg-emerald-950/40 px-2.5 py-1 rounded-full border border-emerald-500/20">
            <Award className="w-3.5 h-3.5" />
            <span>{total_marks} Marks</span>
          </div>
        </div>

        <h4 className="text-base font-bold text-slate-100 line-clamp-1 mb-2">
          {title}
        </h4>

        <div className="space-y-1.5 text-xs text-slate-400">
          <div className="flex items-center gap-2">
            <Calendar className="w-4 h-4 text-slate-500" />
            <span>{startDate.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })}</span>
          </div>
          <div className="flex items-center gap-2">
            <Clock className="w-4 h-4 text-slate-500" />
            <span>
              {startDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })} —{' '}
              {endDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
            </span>
          </div>
        </div>
      </div>

      <div className="pt-4 mt-4 border-t border-slate-800 flex items-center justify-between">
        {isCompleted ? (
          <button
            onClick={() => onViewResults(exam.id)}
            className="w-full py-2 px-3 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 font-semibold text-xs flex items-center justify-center gap-1.5 border border-slate-700 transition"
          >
            <CheckCircle2 className="w-4 h-4 text-indigo-400" />
            <span>View Submission & Results</span>
          </button>
        ) : isRunning ? (
          <button
            onClick={() => onTakeExam(exam.id)}
            className="w-full py-2 px-3 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-xs flex items-center justify-center gap-1.5 shadow-lg shadow-emerald-600/30 transition animate-pulse"
          >
            <span>Take Exam Now</span>
            <ArrowRight className="w-4 h-4" />
          </button>
        ) : isScheduled ? (
          <div className="text-[11px] text-slate-500 text-center w-full py-1">
            Exam starts {startDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
          </div>
        ) : (
          <div className="text-[11px] text-rose-400/80 text-center w-full py-1">
            Exam deadline passed (Missed)
          </div>
        )}
      </div>
    </div>
  );
}
