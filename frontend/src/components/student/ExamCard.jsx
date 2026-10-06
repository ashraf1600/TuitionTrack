import React, { useEffect, useState } from 'react';
import { Clock, Award, ArrowRight, CheckCircle2, Trophy, Layers, Timer, AlertTriangle, CalendarClock, Hourglass } from 'lucide-react';

const fmtDateTime = (value) =>
  new Date(value).toLocaleString(undefined, { weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });

/** "in 2 h 5 min", "in 3 days" — coarse on purpose; the exam screen has the exact timer. */
function relative(ms) {
  const mins = Math.max(0, Math.round(ms / 60000));
  if (mins < 1) return 'in under a minute';
  if (mins < 60) return `in ${mins} min`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `in ${hours} h ${mins % 60} min`;
  const days = Math.floor(hours / 24);
  return `in ${days} day${days === 1 ? '' : 's'}`;
}

/**
 * One exam or assignment as a student sees it. What the card offers follows
 * what the server says is possible (`can_submit`, `has_submission`).
 */
export default function ExamCard({ exam, onTakeExam, onViewResults, onViewLeaderboard }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 30000);
    return () => clearInterval(id);
  }, []);

  const isAssignment = exam.category === 'ASSIGNMENT';
  const start = new Date(exam.start_time).getTime();
  const end = new Date(exam.end_time).getTime();
  const lateEnd = exam.late_submission_until ? new Date(exam.late_submission_until).getTime() : 0;

  const done = exam.has_submission;
  const upcoming = !done && now < start;
  const open = !done && !upcoming && exam.can_submit;
  const isLate = open && now > end;
  const missed = !done && !upcoming && !open;
  const result = exam.my_result;
  const noun = isAssignment ? 'assignment' : 'exam';

  let tone = 'border-slate-800';
  if (open) tone = isLate ? 'border-amber-500/40' : 'border-emerald-500/40';

  return (
    <article className={`rounded-2xl border bg-slate-900/70 p-5 flex flex-col justify-between gap-4 ${tone}`}>
      <div>
        <div className="flex items-start justify-between gap-2 mb-2">
          <div className="flex items-center gap-1.5 flex-wrap text-[11px] font-semibold">
            <span className={`px-2 py-0.5 rounded-full border ${isAssignment ? 'bg-purple-500/15 text-purple-300 border-purple-500/30' : 'bg-indigo-500/15 text-indigo-300 border-indigo-500/30'}`}>
              {isAssignment ? 'Assignment' : 'Exam'}
            </span>
            {exam.duration_minutes && !isAssignment && (
              <span className="px-2 py-0.5 rounded-full bg-slate-800 text-slate-300 border border-slate-700 flex items-center gap-1">
                <Timer className="w-3 h-3" /> {exam.duration_minutes} min
              </span>
            )}
          </div>
          <span className="flex items-center gap-1 text-xs font-bold text-slate-300 flex-shrink-0">
            <Award className="w-3.5 h-3.5 text-emerald-400" />
            {Number(exam.total_marks)} marks
          </span>
        </div>

        <h4 className="text-base font-bold text-slate-100 line-clamp-2">{exam.title}</h4>
        {exam.batch_name && (
          <div className="flex items-center gap-1 text-xs text-slate-400 mt-0.5">
            <Layers className="w-3.5 h-3.5" /> {exam.batch_name}
          </div>
        )}

        <div className="mt-3 space-y-1 text-xs text-slate-400">
          {upcoming && (
            <p className="flex items-center gap-2 text-indigo-300 font-medium">
              <CalendarClock className="w-4 h-4" /> Opens {relative(start - now)} · {fmtDateTime(exam.start_time)}
            </p>
          )}
          {!upcoming && (
            <p className="flex items-center gap-2">
              <Clock className="w-4 h-4 text-slate-500" />
              {isAssignment ? 'Due' : 'Ends'} {fmtDateTime(exam.end_time)}
            </p>
          )}
          {open && !isLate && (
            <p className="text-emerald-300 font-medium pl-6">Closes {relative(end - now)}</p>
          )}
          {isLate && (
            <p className="flex items-center gap-2 text-amber-300 font-medium">
              <AlertTriangle className="w-4 h-4" />
              Deadline passed — {lateEnd > now ? `late work accepted ${relative(lateEnd - now).replace('in ', 'for ')}` : 'hand in now'}
            </p>
          )}
          {!isAssignment && upcoming && exam.negative_marks_per_wrong > 0 && (
            <p className="pl-6">Wrong MCQ answers lose {Number(exam.negative_marks_per_wrong)} mark(s).</p>
          )}
        </div>
      </div>

      <div className="pt-4 border-t border-slate-800">
        {done ? (
          <div className="space-y-2">
            <div className="flex items-center justify-between text-xs">
              <span className="flex items-center gap-1.5 text-slate-300">
                <CheckCircle2 className="w-4 h-4 text-emerald-400" />
                Turned in{result?.status === 'DELAYED' ? ' (late)' : ''}
              </span>
              {exam.results_released && result?.obtained_marks !== null && result?.obtained_marks !== undefined ? (
                <span className="font-bold text-emerald-400">
                  {Number(result.obtained_marks)} / {Number(exam.total_marks)}
                  {!result.is_graded && <span className="font-normal text-slate-400"> so far</span>}
                </span>
              ) : (
                <span className="flex items-center gap-1 text-slate-400">
                  <Hourglass className="w-3.5 h-3.5" /> Results pending
                </span>
              )}
            </div>
            {!exam.results_released && exam.result_publish_mode === 'SCHEDULED' && exam.results_release_time && (
              <p className="text-[11px] text-slate-500">Results on {fmtDateTime(exam.results_release_time)}</p>
            )}
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => onViewResults(exam.id)}
                className="flex-1 py-2 px-3 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-100 font-semibold text-xs border border-slate-700 transition"
              >
                {exam.results_released ? 'View my result' : 'View my submission'}
              </button>
              {onViewLeaderboard && exam.results_released && (
                <button
                  type="button"
                  onClick={() => onViewLeaderboard(exam)}
                  className="p-2 rounded-xl bg-amber-500/10 hover:bg-amber-500/20 text-amber-300 border border-amber-500/30 transition"
                  title="Leaderboard"
                  aria-label="Leaderboard"
                >
                  <Trophy className="w-4 h-4" />
                </button>
              )}
            </div>
          </div>
        ) : open ? (
          <button
            type="button"
            onClick={() => onTakeExam(exam.id)}
            className={`w-full py-2.5 px-3 rounded-xl text-white font-bold text-sm flex items-center justify-center gap-1.5 transition ${
              isLate ? 'bg-amber-600 hover:bg-amber-500' : 'bg-emerald-600 hover:bg-emerald-500'
            }`}
          >
            {isLate ? `Hand in late` : isAssignment ? 'Open assignment' : exam.duration_minutes ? `Start exam (${exam.duration_minutes} min)` : 'Start exam'}
            <ArrowRight className="w-4 h-4" />
          </button>
        ) : upcoming ? (
          <p className="text-xs text-slate-400 text-center py-1.5">
            Questions unlock when the {noun} opens.
          </p>
        ) : missed ? (
          <p className="text-xs text-rose-300 text-center py-1.5">
            {isAssignment ? 'The deadline has passed.' : 'This exam has ended.'} You did not turn it in.
          </p>
        ) : null}
      </div>
    </article>
  );
}
