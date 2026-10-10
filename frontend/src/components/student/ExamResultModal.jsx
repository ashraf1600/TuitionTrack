import React, { useEffect, useState } from 'react';
import Modal from '../common/Modal';
import MathRenderer from '../common/MathRenderer';
import QuestionImage from '../common/QuestionImage';
import LeaderboardModal from '../common/LeaderboardModal';
import StatusBadge from '../common/StatusBadge';
import { api } from '../../api/client';
import {
  Award,
  BookOpen,
  Check,
  ExternalLink,
  HelpCircle,
  Hourglass,
  Image as ImageIcon,
  MessageSquare,
  Minus,
  Trophy,
  X,
} from 'lucide-react';

const LETTERS = ['A', 'B', 'C', 'D', 'E'];
const fmtDateTime = (value) =>
  new Date(value).toLocaleString(undefined, { weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
const isSafeUrl = (url) => Boolean(url) && !/^\s*(javascript:|data:text\/html|vbscript:)/i.test(url);

function pendingMessage(status) {
  if (status?.mode === 'SCHEDULED' && status.publish_at) {
    return `Results will be published on ${fmtDateTime(status.publish_at)}.`;
  }
  if (status?.mode === 'IMMEDIATE') return 'Your result is being prepared.';
  return 'Your tutor has not published the results yet.';
}

function AnswerSheets({ urls }) {
  if (!urls || urls.length === 0) return null;
  return (
    <div>
      <h4 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-2 flex items-center gap-1.5">
        <ImageIcon className="w-4 h-4 text-slate-500" />
        Your answer sheets ({urls.length} page{urls.length === 1 ? '' : 's'})
      </h4>
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        {urls.filter(isSafeUrl).map((url, i) => (
          <a key={i} href={url} target="_blank" rel="noopener noreferrer" className="group relative rounded-xl overflow-hidden border border-slate-700 block bg-slate-950">
            {/\.pdf(\?|$)/i.test(url) ? (
              <span className="w-full h-24 flex items-center justify-center text-xs text-indigo-300 underline">PDF page {i + 1}</span>
            ) : (
              <img src={url} alt={`Page ${i + 1}`} className="w-full h-24 object-cover group-hover:scale-105 transition" />
            )}
            <div className="absolute inset-0 bg-slate-950/50 opacity-0 group-hover:opacity-100 transition flex items-center justify-center">
              <ExternalLink className="w-4 h-4 text-white" />
            </div>
          </a>
        ))}
      </div>
    </div>
  );
}

/** Before results are out: what the student handed in, with nothing marked right or wrong. */
function PendingView({ exam, status }) {
  const submission = exam.submission || {};
  const answers = submission.answers_data || {};
  const questions = Array.isArray(exam.mcq_data) ? exam.mcq_data : [];

  return (
    <div className="space-y-5">
      <div className="p-6 rounded-2xl bg-slate-900 border border-indigo-500/30 flex items-start gap-4">
        <div className="w-12 h-12 rounded-2xl bg-indigo-500/15 text-indigo-300 border border-indigo-500/30 flex items-center justify-center flex-shrink-0">
          <Hourglass className="w-6 h-6" />
        </div>
        <div>
          <h3 className="text-lg font-bold text-slate-100">Results pending</h3>
          <p className="text-sm text-slate-300 mt-0.5">{pendingMessage(status)}</p>
          <p className="text-xs text-slate-400 mt-1.5">
            Your answers are safely handed in{submission.submitted_at ? ` (${fmtDateTime(submission.submitted_at)})` : ''}. Your marks and the
            correct answers will appear here when results are out.
          </p>
        </div>
      </div>

      {questions.length > 0 && (
        <div>
          <h4 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">What you answered</h4>
          <ol className="space-y-2 max-h-[320px] overflow-y-auto pr-1">
            {questions.map((q, idx) => {
              const raw = answers[q.id] ?? answers[`mcq-${idx}`] ?? answers[`mcq_${idx}`] ?? answers[String(idx)];
              const chosen = raw === undefined || raw === null || raw === '' ? null : Number(raw);
              return (
                <li key={q.id || idx} className="rounded-xl border border-slate-700/60 bg-slate-800/30 p-3 text-sm">
                  <div className="flex gap-2 text-slate-100">
                    <span className="text-slate-400">{idx + 1}.</span>
                    <div className="min-w-0 space-y-2">
                      {q.question && <MathRenderer plain content={q.question} />}
                      <QuestionImage src={q.image_url} alt={`Question ${idx + 1}`} />
                    </div>
                  </div>
                  <div className="mt-1.5 pl-5 text-xs text-slate-400">
                    Your answer:{' '}
                    {chosen === null || Number.isNaN(chosen) ? (
                      <span className="text-slate-500">left blank</span>
                    ) : (
                      <span className="text-indigo-200">
                        {LETTERS[chosen]}. <MathRenderer plain inline content={q.options?.[chosen] ?? ''} />
                      </span>
                    )}
                  </div>
                </li>
              );
            })}
          </ol>
        </div>
      )}

      {submission.text_answer && (
        <div>
          <h4 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Your typed answer</h4>
          <p className="whitespace-pre-wrap text-sm text-slate-100 bg-slate-800/40 border border-slate-700/60 rounded-xl p-3.5">{submission.text_answer}</p>
        </div>
      )}
      <AnswerSheets urls={(submission.image_urls && submission.image_urls.length ? submission.image_urls : submission.uploaded_images) || []} />
    </div>
  );
}

function ReviewQuestion({ q, index }) {
  const tone =
    q.outcome === 'correct'
      ? 'bg-emerald-950/20 border-emerald-500/30'
      : q.outcome === 'wrong'
      ? 'bg-rose-950/20 border-rose-500/30'
      : 'bg-slate-900 border-slate-800';
  const awarded = Number(q.awarded) || 0;

  return (
    <li className={`p-4 rounded-xl border space-y-2.5 ${tone}`}>
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-start gap-2 min-w-0">
          <span
            className={`w-5 h-5 rounded-full flex items-center justify-center flex-shrink-0 mt-0.5 ${
              q.outcome === 'correct' ? 'bg-emerald-500 text-white' : q.outcome === 'wrong' ? 'bg-rose-500 text-white' : 'bg-slate-700 text-slate-400'
            }`}
            aria-label={q.outcome === 'correct' ? 'Correct' : q.outcome === 'wrong' ? 'Wrong' : 'Not answered'}
          >
            {q.outcome === 'correct' ? <Check className="w-3 h-3 stroke-[3]" /> : q.outcome === 'wrong' ? <X className="w-3 h-3 stroke-[3]" /> : <Minus className="w-3 h-3" />}
          </span>
          <div className="min-w-0 space-y-2 text-sm font-medium text-slate-100">
            <div className="flex gap-1.5">
              <span className="text-slate-400">{index + 1}.</span>
              {q.question && <MathRenderer plain content={q.question} />}
            </div>
            <QuestionImage src={q.image_url} alt={`Question ${index + 1}`} />
          </div>
        </div>
        <span
          className={`text-xs font-bold px-2 py-0.5 rounded flex-shrink-0 ${
            awarded > 0 ? 'bg-emerald-500/15 text-emerald-300' : awarded < 0 ? 'bg-rose-500/15 text-rose-300' : 'bg-slate-800 text-slate-400'
          }`}
        >
          {awarded > 0 ? '+' : ''}{awarded} / {Number(q.points)}
        </span>
      </div>

      <ul className="grid grid-cols-1 sm:grid-cols-2 gap-2 pl-7">
        {(q.options || []).map((opt, i) => {
          const isCorrect = q.correct_answer === i;
          const isChosen = q.selected === i;
          return (
            <li
              key={i}
              className={`p-2 rounded-lg border text-sm flex items-start gap-2 ${
                isCorrect
                  ? 'bg-emerald-500/15 border-emerald-500/40 text-emerald-100'
                  : isChosen
                  ? 'bg-rose-500/15 border-rose-500/40 text-rose-200'
                  : 'bg-slate-800/40 border-slate-800 text-slate-400'
              }`}
            >
              <span className="text-xs font-bold pt-0.5">{LETTERS[i]}</span>
              <span className="flex-1 min-w-0 break-words"><MathRenderer plain inline content={opt} /></span>
              {isCorrect && <span className="text-[11px] font-semibold text-emerald-300 whitespace-nowrap">{isChosen ? 'Your answer · correct' : 'Correct answer'}</span>}
              {isChosen && !isCorrect && <span className="text-[11px] font-semibold text-rose-300 whitespace-nowrap">Your answer</span>}
            </li>
          );
        })}
      </ul>

      {q.outcome === 'skipped' && <p className="pl-7 text-xs text-slate-400">You left this one blank.</p>}

      {q.explanation && (
        <div className="pl-7 text-xs text-slate-300 flex items-start gap-1.5">
          <HelpCircle className="w-3.5 h-3.5 text-indigo-400 flex-shrink-0 mt-0.5" />
          <span><strong className="text-slate-200">Explanation: </strong><MathRenderer plain inline content={q.explanation} /></span>
        </div>
      )}
    </li>
  );
}

/** The evaluated paper, once results are released. */
function ReleasedView({ result, onOpenLeaderboard }) {
  const { exam, summary, questions, written } = result;
  const scored = result.obtained_marks !== null && result.obtained_marks !== undefined;
  const awaiting = Boolean(written?.awaiting_marking);
  const scheme = written?.scheme || [];
  const hasBreakdown = scheme.some((item) => item.awarded !== null && item.awarded !== undefined);

  return (
    <div className="space-y-6">
      <div className="p-6 rounded-2xl bg-gradient-to-br from-slate-900 via-indigo-950/40 to-slate-900 border border-indigo-500/30 flex flex-col sm:flex-row items-center justify-between gap-4">
        <div className="flex items-center gap-4">
          <div className="w-16 h-16 rounded-2xl flex items-center justify-center bg-emerald-500/20 text-emerald-400 border border-emerald-500/30">
            <Award className="w-8 h-8" />
          </div>
          <div>
            <span className="text-xs font-semibold uppercase tracking-wider text-slate-400">
              {awaiting ? 'Your score so far' : 'Your score'}
            </span>
            <div className="text-2xl font-extrabold text-slate-100 mt-0.5">
              {scored ? (
                <span>
                  <strong className="text-emerald-400">{result.obtained_marks}</strong> / {exam.total_marks}
                  {!awaiting && result.percentage !== null && <span className="text-sm font-semibold text-slate-400"> ({result.percentage}%)</span>}
                </span>
              ) : (
                <span className="text-indigo-300 text-lg">Awaiting marking</span>
              )}
            </div>
            <div className="flex flex-wrap items-center gap-x-3 gap-y-0.5 mt-1 text-xs">
              {questions.length > 0 && <span className="text-indigo-300">MCQ: {result.mcq_score} / {result.mcq_total}</span>}
              {written && (
                <span className={awaiting ? 'text-amber-300' : 'text-emerald-400'}>
                  Written: {awaiting ? 'awaiting marking' : `${result.cq_score ?? 0}`}
                </span>
              )}
            </div>
          </div>
        </div>

        <div className="flex flex-col sm:items-end gap-2">
          <div className="flex items-center gap-2">
            <StatusBadge status={result.status} />
            <button
              type="button"
              onClick={onOpenLeaderboard}
              className="px-3 py-1.5 rounded-xl bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 border border-amber-500/40 text-xs font-bold flex items-center gap-1.5 transition"
            >
              <Trophy className="w-3.5 h-3.5" /> Leaderboard
            </button>
          </div>
          {result.submitted_at && <span className="text-[11px] text-slate-400">Submitted {fmtDateTime(result.submitted_at)}</span>}
        </div>
      </div>

      {result.tutor_feedback && (
        <div className="p-4 rounded-xl bg-slate-800/40 border border-slate-700/60">
          <h4 className="text-xs font-bold text-indigo-300 uppercase tracking-wider mb-1.5 flex items-center gap-2">
            <MessageSquare className="w-4 h-4 text-indigo-400" /> Feedback from your tutor
          </h4>
          <p className="text-sm text-slate-200 leading-relaxed whitespace-pre-wrap">{result.tutor_feedback}</p>
        </div>
      )}

      {questions.length > 0 && (
        <div className="space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h4 className="text-xs font-bold text-slate-300 uppercase tracking-wider">Multiple choice — question by question</h4>
            <div className="flex items-center gap-2 text-xs font-semibold">
              <span className="px-2 py-0.5 rounded-full bg-emerald-500/15 text-emerald-300">{summary.correct} correct</span>
              <span className="px-2 py-0.5 rounded-full bg-rose-500/15 text-rose-300">{summary.wrong} wrong</span>
              <span className="px-2 py-0.5 rounded-full bg-slate-800 text-slate-300">{summary.skipped} blank</span>
            </div>
          </div>
          {exam.negative_marks_per_wrong > 0 && (
            <p className="text-xs text-slate-400">Each wrong answer lost {exam.negative_marks_per_wrong} mark(s). Blank answers lost nothing.</p>
          )}
          <ol className="space-y-3 max-h-[420px] overflow-y-auto pr-1">
            {questions.map((q, index) => <ReviewQuestion key={q.id} q={q} index={index} />)}
          </ol>
        </div>
      )}

      {written && (
        <div className="space-y-3">
          <h4 className="text-xs font-bold text-slate-300 uppercase tracking-wider">Written part</h4>
          {awaiting && (
            <p className="p-3 rounded-xl bg-amber-500/10 border border-amber-500/30 text-xs text-amber-200">
              Your tutor has not marked the written part yet, so the score above does not include it.
            </p>
          )}
          {hasBreakdown && (
            <ul className="rounded-xl border border-slate-700/60 divide-y divide-slate-800 overflow-hidden">
              {scheme.map((item) => (
                <li key={item.id} className="flex items-center justify-between gap-3 px-3.5 py-2 text-sm bg-slate-800/30">
                  <span className="text-slate-200">{item.label}</span>
                  <span className="font-bold text-emerald-400">
                    {item.awarded ?? '—'} <span className="text-slate-500 font-normal">/ {Number(item.marks)}</span>
                  </span>
                </li>
              ))}
            </ul>
          )}
          {written.text_answer && (
            <div>
              <h5 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Your typed answer</h5>
              <p className="whitespace-pre-wrap text-sm text-slate-100 bg-slate-800/40 border border-slate-700/60 rounded-xl p-3.5">{written.text_answer}</p>
            </div>
          )}
          <AnswerSheets urls={written.image_urls} />
        </div>
      )}

      {(result.solution_html || isSafeUrl(result.solution_media_url)) && (
        <div className="p-4 rounded-xl bg-slate-900 border border-slate-800 space-y-3">
          <h4 className="text-xs font-bold text-indigo-300 uppercase tracking-wider flex items-center gap-2">
            <BookOpen className="w-4 h-4 text-indigo-400" /> Model solution
          </h4>
          {result.solution_html && (
            <div className="p-4 rounded-lg bg-slate-950/80 border border-slate-800 text-sm text-slate-200">
              <MathRenderer content={result.solution_html} />
            </div>
          )}
          {isSafeUrl(result.solution_media_url) && (
            <a
              href={result.solution_media_url}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-300 border border-indigo-500/30 text-xs font-semibold transition"
            >
              <ExternalLink className="w-3.5 h-3.5" /> Open the attached solution sheet
            </a>
          )}
        </div>
      )}
    </div>
  );
}

/**
 * A student's view of an exam they have handed in. The server decides what is
 * shown: either "results pending" (no marks, no answer key in the response at
 * all) or the fully evaluated paper.
 */
export default function ExamResultModal({ isOpen, onClose, exam }) {
  const [state, setState] = useState({ loading: true, error: '', data: null });
  const [leaderboardOpen, setLeaderboardOpen] = useState(false);
  const examId = exam?.id;

  useEffect(() => {
    if (!isOpen || !examId) return undefined;
    let cancelled = false;
    setState({ loading: true, error: '', data: null });
    api.getExamResult(examId)
      .then((data) => { if (!cancelled) setState({ loading: false, error: '', data }); })
      .catch((err) => { if (!cancelled) setState({ loading: false, error: err.message || 'Could not load your result.', data: null }); });
    return () => { cancelled = true; };
  }, [isOpen, examId]);

  if (!exam) return null;
  const { loading, error, data } = state;

  return (
    <>
      <Modal isOpen={isOpen} onClose={onClose} title={`${data?.available ? 'Result' : 'Your submission'} — ${exam.title}`} maxWidth="max-w-4xl">
        <div className="space-y-6">
          {loading && <p className="text-sm text-slate-400 py-8 text-center">Loading…</p>}
          {error && <p className="p-3.5 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-300 text-sm">{error}</p>}
          {data && !data.available && <PendingView exam={exam} status={data} />}
          {data?.available && <ReleasedView result={data.result} onOpenLeaderboard={() => setLeaderboardOpen(true)} />}

          <div className="pt-2 flex justify-end">
            <button type="button" onClick={onClose} className="px-5 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-semibold transition">
              Close
            </button>
          </div>
        </div>
      </Modal>

      {leaderboardOpen && (
        <LeaderboardModal isOpen={leaderboardOpen} onClose={() => setLeaderboardOpen(false)} examId={exam.id} examTitle={exam.title} />
      )}
    </>
  );
}
