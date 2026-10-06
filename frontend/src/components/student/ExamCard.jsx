import React from 'react';
import { Calendar, Clock, Award, ArrowRight, CheckCircle2, Trophy, Layers, FileCheck } from 'lucide-react';
import StatusBadge from '../common/StatusBadge';

export default function ExamCard({
  exam,
  onTakeExam,
  onViewResults,
  onViewLeaderboard,
}) {
  const {
    id,
    title,
    category,
    exam_type,
    batch_name,
    total_marks,
    start_time,
    end_time,
    dynamic_status,
    has_submission,
  } = exam;

  const isAssignment = category === 'ASSIGNMENT';
  const startDate = new Date(start_time);
  const endDate = new Date(end_time);

  const isRunning = dynamic_status?.toLowerCase() === 'running';
  const isScheduled = dynamic_status?.toLowerCase() === 'scheduled';
  const isCompleted = has_submission;

  return (
    <div className="glass-panel p-5 rounded-2xl flex flex-col justify-between hover:border-slate-700 transition duration-200">
      <div>
        <div className="flex items-start justify-between gap-2 mb-2">
          <div className="flex items-center gap-1.5 flex-wrap">
            <StatusBadge status={dynamic_status} />
            {isAssignment ? (
              <span className="px-2 py-0.5 rounded-full text-[10px] font-mono font-bold bg-purple-500/20 text-purple-300 border border-purple-500/30">
                ASSIGNMENT
              </span>
            ) : (
              <span className="px-2 py-0.5 rounded-full text-[10px] font-mono font-bold bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                EXAM
              </span>
            )}
            {exam_type && (
              <span className="px-2 py-0.5 rounded-full text-[10px] font-mono font-bold bg-slate-800 text-slate-300 border border-slate-700">
                {exam_type}
              </span>
            )}
          </div>
          <div className="flex items-center gap-1 text-xs font-bold text-emerald-400 bg-emerald-950/40 px-2.5 py-1 rounded-full border border-emerald-500/20">
            <Award className="w-3.5 h-3.5" />
            <span>{total_marks} Pts</span>
          </div>
        </div>

        <h4 className="text-base font-bold text-slate-100 line-clamp-1 mb-1">
          {title}
        </h4>

        {batch_name && (
          <div className="flex items-center gap-1 text-[11px] text-indigo-400 font-semibold mb-2">
            <Layers className="w-3.5 h-3.5" />
            <span>Batch: {batch_name}</span>
          </div>
        )}

        <div className="space-y-1.5 text-xs text-slate-400">
          {isAssignment ? (
            <div className="flex items-center gap-2 text-purple-300">
              <Clock className="w-4 h-4 text-purple-400" />
              <span>
                Deadline:{' '}
                {endDate.toLocaleDateString(undefined, {
                  month: 'short',
                  day: 'numeric',
                  hour: '2-digit',
                  minute: '2-digit',
                })}
              </span>
            </div>
          ) : (
            <>
              <div className="flex items-center gap-2">
                <Calendar className="w-4 h-4 text-slate-500" />
                <span>
                  {startDate.toLocaleDateString(undefined, {
                    weekday: 'short',
                    month: 'short',
                    day: 'numeric',
                  })}
                </span>
              </div>
              <div className="flex items-center gap-2">
                <Clock className="w-4 h-4 text-slate-500" />
                <span>
                  {startDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })} —{' '}
                  {endDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                </span>
              </div>
            </>
          )}
        </div>
      </div>

      <div className="pt-4 mt-4 border-t border-slate-800 space-y-2">
        {isCompleted ? (
          <div className="flex items-center gap-2">
            <button
              onClick={() => onViewResults(id)}
              className="flex-1 py-2 px-3 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 font-semibold text-xs flex items-center justify-center gap-1.5 border border-slate-700 transition"
            >
              <CheckCircle2 className="w-4 h-4 text-indigo-400" />
              <span>{isAssignment ? 'View Submission & Grade' : 'Results & Key'}</span>
            </button>
            {onViewLeaderboard && (
              <button
                onClick={() => onViewLeaderboard(exam)}
                className="p-2 rounded-xl bg-amber-500/10 hover:bg-amber-500/20 text-amber-300 border border-amber-500/30 transition"
                title="View Batch Leaderboard"
              >
                <Trophy className="w-4 h-4" />
              </button>
            )}
          </div>
        ) : isRunning ? (
          <button
            onClick={() => onTakeExam(id)}
            className={`w-full py-2.5 px-3 rounded-xl text-white font-bold text-xs flex items-center justify-center gap-1.5 shadow-lg transition animate-pulse ${
              isAssignment
                ? 'bg-purple-600 hover:bg-purple-500 shadow-purple-600/30'
                : 'bg-emerald-600 hover:bg-emerald-500 shadow-emerald-600/30'
            }`}
          >
            <span>{isAssignment ? 'Submit Assignment Now' : 'Take Exam Now'}</span>
            <ArrowRight className="w-4 h-4" />
          </button>
        ) : isScheduled ? (
          <div className="text-[11px] text-slate-400 text-center w-full py-1.5 rounded-lg bg-slate-900/60 border border-slate-800">
            Starts at {startDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
          </div>
        ) : (
          <div className="text-[11px] text-rose-400/80 text-center w-full py-1.5 rounded-lg bg-rose-950/20 border border-rose-900/30">
            {isAssignment ? 'Assignment Deadline Passed' : 'Exam window passed (Missed)'}
          </div>
        )}
      </div>
    </div>
  );
}
