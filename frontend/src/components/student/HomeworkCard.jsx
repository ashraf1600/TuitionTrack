import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  Clock, CheckCircle2, AlertTriangle, ExternalLink, Send, Loader2,
  BookOpen, X, Bell, ChevronDown, ChevronUp,
} from 'lucide-react';
import { api } from '../../api/client';
import { notify } from '../../utils/toast';

// ─── Custom Hook: Live Countdown Timer ────────────────────────────────────────
/**
 * useCountdown — returns time remaining (ms) until `dueDate`, updated every second.
 * Returns a negative number once the deadline has passed.
 */
function useCountdown(dueDate) {
  const [timeLeft, setTimeLeft] = useState(() => new Date(dueDate).getTime() - Date.now());

  useEffect(() => {
    // Update immediately on mount, then every second.
    const tick = () => setTimeLeft(new Date(dueDate).getTime() - Date.now());
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [dueDate]);

  return timeLeft;
}

// ─── Format helpers ───────────────────────────────────────────────────────────
function formatCountdown(ms) {
  if (ms <= 0) return { label: 'Past due', parts: null };

  const totalSec = Math.floor(ms / 1000);
  const days = Math.floor(totalSec / 86400);
  const hrs = Math.floor((totalSec % 86400) / 3600);
  const mins = Math.floor((totalSec % 3600) / 60);
  const secs = totalSec % 60;

  if (days > 0) return { label: `${days}d ${hrs}h ${mins}m`, parts: { days, hrs, mins, secs } };
  if (hrs > 0) return { label: `${hrs}h ${mins}m ${secs}s`, parts: { days: 0, hrs, mins, secs } };
  return { label: `${mins}m ${secs}s`, parts: { days: 0, hrs: 0, mins, secs } };
}

function urgencyStyle(ms) {
  if (ms <= 0) return { bg: 'bg-slate-800/60', border: 'border-slate-700', badge: 'bg-slate-700 text-slate-400', dot: 'bg-slate-500', ring: '' };
  if (ms <= 3_600_000) return { bg: 'bg-rose-950/40', border: 'border-rose-500/40', badge: 'bg-rose-500/20 text-rose-300', dot: 'bg-rose-500 animate-ping', ring: 'ring-2 ring-rose-500/20' };
  if (ms <= 7_200_000) return { bg: 'bg-orange-950/30', border: 'border-orange-500/40', badge: 'bg-orange-500/15 text-orange-300', dot: 'bg-orange-400', ring: 'ring-1 ring-orange-500/20' };
  if (ms <= 86_400_000) return { bg: 'bg-amber-950/20', border: 'border-amber-500/30', badge: 'bg-amber-500/15 text-amber-300', dot: 'bg-amber-400', ring: '' };
  return { bg: 'bg-slate-900/60', border: 'border-slate-800', badge: 'bg-slate-800 text-slate-400', dot: 'bg-indigo-400', ring: '' };
}

// ─── 2-Hour Alert Modal ───────────────────────────────────────────────────────
function UrgentAlertModal({ homework, onDismiss }) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-slate-950/80 backdrop-blur-sm" onClick={onDismiss} />
      <div className="relative w-full max-w-sm rounded-2xl border border-rose-500/40 bg-gradient-to-br from-slate-900 via-rose-950/30 to-slate-900 p-6 shadow-2xl shadow-rose-500/20 animate-bounce-once">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-full bg-rose-500/20 flex items-center justify-center">
              <Bell className="w-4 h-4 text-rose-400" />
            </div>
            <span className="text-sm font-bold text-rose-300 uppercase tracking-wider">Urgent!</span>
          </div>
          <button
            onClick={onDismiss}
            className="p-1 rounded-lg hover:bg-slate-800 text-slate-400 hover:text-slate-200 transition"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="space-y-3">
          <div className="text-4xl font-black text-rose-400">⏰</div>
          <h3 className="text-lg font-extrabold text-slate-100">Hurry! Due in under 2 hours</h3>
          <p className="text-sm text-slate-400">
            Your homework{' '}
            <span className="font-bold text-slate-200">"{homework.title}"</span> from{' '}
            <span className="font-bold text-indigo-300">{homework.tutor_display_name}</span> is due
            very soon. Finish it now!
          </p>
        </div>

        <button
          onClick={onDismiss}
          id={`dismiss-alert-${homework.id}`}
          className="mt-5 w-full py-2.5 rounded-xl bg-rose-600 hover:bg-rose-500 text-white text-sm font-bold transition"
        >
          Got it, I'm on it! 🚀
        </button>
      </div>
    </div>
  );
}

// ─── Main HomeworkCard Component ──────────────────────────────────────────────
/**
 * HomeworkCard
 * - Live countdown timer using useCountdown hook
 * - 2-hour alert modal (fires once per session per homework)
 * - Student: optional URL submission
 * - Tutor (isTutor=true): "Mark as Done" button
 */
export default function HomeworkCard({ homework, isTutor = false, onUpdated }) {
  const timeLeft = useCountdown(homework.due_date);
  const [alertShown, setAlertShown] = useState(false);
  const [showAlert, setShowAlert] = useState(false);
  const [expanded, setExpanded] = useState(false);

  // Student submission state
  const [submitUrl, setSubmitUrl] = useState(homework.submitted_online_url || '');
  const [submitting, setSubmitting] = useState(false);

  // Tutor mark-done state
  const [markingDone, setMarkingDone] = useState(false);
  const [feedbackInput, setFeedbackInput] = useState('');
  const [showFeedbackInput, setShowFeedbackInput] = useState(false);

  // ── 2-hour alert logic ────────────────────────────────────────────────────
  useEffect(() => {
    // Fire alert exactly once when timeLeft crosses the 2-hour threshold.
    if (
      !homework.is_evaluated &&
      !isTutor &&
      timeLeft > 0 &&
      timeLeft <= 7_200_000 && // 2 hours in ms
      !alertShown
    ) {
      setAlertShown(true);
      setShowAlert(true);
    }
  }, [timeLeft, alertShown, homework.is_evaluated, isTutor]);

  const style = urgencyStyle(timeLeft);
  const { label: countdownLabel } = formatCountdown(timeLeft);
  const isPastDue = timeLeft <= 0;
  const isDone = homework.is_evaluated;
  const isSubmitted = !!(homework.submitted_online_url || homework.submitted_at);

  // ── Student submit handler ────────────────────────────────────────────────
  const handleSubmit = async () => {
    setSubmitting(true);
    try {
      const res = await api.submitHomework(homework.id, submitUrl.trim());
      notify.success('Submission recorded!');
      onUpdated?.(res.homework);
    } catch (err) {
      notify(`Submission failed: ${err.message}`);
    } finally {
      setSubmitting(false);
    }
  };

  // ── Tutor mark-done handler ───────────────────────────────────────────────
  const handleMarkDone = async () => {
    setMarkingDone(true);
    try {
      const res = await api.markHomeworkDone(homework.id, feedbackInput.trim());
      notify.success('Homework marked as done!');
      onUpdated?.(res.homework);
    } catch (err) {
      notify(`Error: ${err.message}`);
    } finally {
      setMarkingDone(false);
    }
  };

  return (
    <>
      {showAlert && (
        <UrgentAlertModal homework={homework} onDismiss={() => setShowAlert(false)} />
      )}

      <article
        className={`rounded-2xl border ${style.border} ${style.bg} ${style.ring} overflow-hidden transition-all duration-300`}
        id={`homework-card-${homework.id}`}
      >
        {/* Header */}
        <div className="p-4 sm:p-5">
          <div className="flex items-start justify-between gap-3">
            <div className="flex items-start gap-3 min-w-0">
              {/* Status dot */}
              <div className="mt-1.5 flex-shrink-0 relative">
                <div className={`w-2.5 h-2.5 rounded-full ${isDone ? 'bg-emerald-400' : style.dot}`} />
                {!isDone && timeLeft <= 3_600_000 && timeLeft > 0 && (
                  <div className={`absolute inset-0 w-2.5 h-2.5 rounded-full ${style.dot} opacity-75`} />
                )}
              </div>

              <div className="min-w-0">
                <h4 className="text-sm font-bold text-slate-100 leading-tight">{homework.title}</h4>
                <div className="flex flex-wrap items-center gap-x-2 gap-y-0.5 mt-1">
                  <span className="text-[11px] text-indigo-300 font-medium">
                    {homework.tutor_display_name}
                  </span>
                  {homework.tuition_title && (
                    <span className="text-[11px] text-slate-500">· {homework.tuition_title}</span>
                  )}
                </div>
              </div>
            </div>

            {/* Status badge */}
            <div className="flex-shrink-0 flex flex-col items-end gap-1.5">
              {isDone ? (
                <span className="px-2 py-0.5 rounded-full bg-emerald-500/15 border border-emerald-500/30 text-emerald-300 text-[10px] font-bold flex items-center gap-1">
                  <CheckCircle2 className="w-3 h-3" /> Done
                </span>
              ) : isPastDue ? (
                <span className="px-2 py-0.5 rounded-full bg-slate-700 text-slate-400 text-[10px] font-bold flex items-center gap-1">
                  <Clock className="w-3 h-3" /> Past due
                </span>
              ) : (
                <span className={`px-2 py-0.5 rounded-full border text-[10px] font-bold flex items-center gap-1 ${style.badge}`}>
                  <Clock className="w-3 h-3" />
                  {timeLeft <= 7_200_000 ? '🔥 ' : ''}{countdownLabel}
                </span>
              )}
              {isSubmitted && !isDone && (
                <span className="px-2 py-0.5 rounded-full bg-sky-50 border border-sky-200 text-sky-700 text-[10px] font-bold">
                  Submitted
                </span>
              )}
            </div>
          </div>

          {/* Due date */}
          <div className="mt-3 flex items-center gap-1.5 text-[11px] text-slate-500">
            <Clock className="w-3 h-3" />
            Due: {new Date(homework.due_date).toLocaleString(undefined, {
              weekday: 'short', month: 'short', day: 'numeric',
              hour: 'numeric', minute: '2-digit',
            })}
          </div>

          {/* Expand toggle */}
          <button
            type="button"
            onClick={() => setExpanded((v) => !v)}
            className="mt-2 flex items-center gap-1 text-[11px] text-slate-500 hover:text-slate-300 transition"
          >
            {expanded ? <ChevronUp className="w-3.5 h-3.5" /> : <ChevronDown className="w-3.5 h-3.5" />}
            {expanded ? 'Hide details' : 'Show details'}
          </button>
        </div>

        {/* Expanded details */}
        {expanded && (
          <div className="border-t border-slate-800/60 px-4 sm:px-5 pb-4 sm:pb-5 pt-3 space-y-4">
            {homework.description && (
              <div>
                <div className="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-1 flex items-center gap-1">
                  <BookOpen className="w-3 h-3" /> Instructions
                </div>
                <p className="text-xs text-slate-300 leading-relaxed whitespace-pre-wrap">
                  {homework.description}
                </p>
              </div>
            )}

            {homework.tutor_feedback && (
              <div className="px-3.5 py-2.5 rounded-xl bg-emerald-500/10 border border-emerald-500/20">
                <div className="text-[10px] font-bold uppercase tracking-wider text-emerald-400 mb-1">
                  Tutor Feedback
                </div>
                <p className="text-xs text-emerald-300">{homework.tutor_feedback}</p>
              </div>
            )}

            {/* Student: online submission */}
            {!isTutor && !isDone && (
              <div>
                <div className="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-2 flex items-center gap-1">
                  <ExternalLink className="w-3 h-3" /> Submit Online (Optional)
                </div>
                <div className="flex gap-2">
                  <input
                    type="url"
                    value={submitUrl}
                    onChange={(e) => setSubmitUrl(e.target.value)}
                    placeholder="https://docs.google.com/..."
                    className="flex-1 px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-100 placeholder:text-slate-600 focus:outline-none focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500/20 transition"
                  />
                  <button
                    type="button"
                    id={`submit-hw-btn-${homework.id}`}
                    onClick={handleSubmit}
                    disabled={submitting || (!submitUrl.trim() && isSubmitted)}
                    className="flex-shrink-0 flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white text-xs font-bold transition"
                  >
                    {submitting ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Send className="w-3.5 h-3.5" />}
                    {isSubmitted ? 'Update' : 'Submit'}
                  </button>
                </div>
                {homework.submitted_online_url && (
                  <a
                    href={homework.submitted_online_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="mt-1.5 flex items-center gap-1 text-[11px] text-indigo-400 hover:text-indigo-300 underline underline-offset-2 transition"
                  >
                    <ExternalLink className="w-3 h-3" /> View my submission
                  </a>
                )}
              </div>
            )}

            {/* Tutor: mark as done */}
            {isTutor && !isDone && (
              <div className="space-y-2">
                {showFeedbackInput && (
                  <textarea
                    value={feedbackInput}
                    onChange={(e) => setFeedbackInput(e.target.value)}
                    placeholder="Optional feedback for the student…"
                    rows={2}
                    className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-100 placeholder:text-slate-600 focus:outline-none focus:border-emerald-500 resize-none transition"
                  />
                )}
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    id={`mark-done-btn-${homework.id}`}
                    onClick={handleMarkDone}
                    disabled={markingDone}
                    className="flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 text-white text-xs font-bold transition shadow-lg shadow-emerald-500/15"
                  >
                    {markingDone ? (
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                    ) : (
                      <CheckCircle2 className="w-3.5 h-3.5" />
                    )}
                    Mark as Done
                  </button>
                  <button
                    type="button"
                    onClick={() => setShowFeedbackInput((v) => !v)}
                    className="text-[11px] text-slate-500 hover:text-slate-300 underline underline-offset-2 transition"
                  >
                    {showFeedbackInput ? 'Hide feedback' : 'Add feedback'}
                  </button>
                  {homework.submitted_online_url && (
                    <a
                      href={homework.submitted_online_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="flex items-center gap-1 text-[11px] text-sky-600 hover:text-sky-500 underline underline-offset-2 transition"
                    >
                      <ExternalLink className="w-3 h-3" /> View submission
                    </a>
                  )}
                </div>
              </div>
            )}

            {/* Already done */}
            {isDone && (
              <div className="flex items-center gap-2 text-xs text-emerald-400">
                <CheckCircle2 className="w-4 h-4" />
                Evaluated by tutor
                {homework.evaluated_at && (
                  <span className="text-slate-500">
                    · {new Date(homework.evaluated_at).toLocaleDateString()}
                  </span>
                )}
              </div>
            )}
          </div>
        )}
      </article>
    </>
  );
}
