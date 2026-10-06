import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Check, X, Minus, ExternalLink, ChevronRight, Loader2, Clock, Award, AlertCircle } from 'lucide-react';
import Modal from '../common/Modal';
import MathRenderer from '../common/MathRenderer';
import QuestionImage from '../common/QuestionImage';
import { api } from '../../api/client';
import { notify } from '../../utils/toast';

const STATE = {
  graded: { label: 'Graded', cls: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30' },
  submitted: { label: 'To grade', cls: 'bg-indigo-500/15 text-indigo-300 border-indigo-500/30' },
  late: { label: 'Late · to grade', cls: 'bg-amber-500/15 text-amber-300 border-amber-500/30' },
  in_progress: { label: 'In progress', cls: 'bg-sky-500/15 text-sky-300 border-sky-500/30' },
  not_submitted: { label: 'Not submitted', cls: 'bg-slate-800 text-slate-400 border-slate-700' },
  missing: { label: 'Missing', cls: 'bg-rose-500/15 text-rose-300 border-rose-500/30' },
};

const LETTERS = ['A', 'B', 'C', 'D', 'E', 'F'];

/** Index of the option a stored answer refers to (answers may be "1", 1 or "B"). */
function answerIndex(value) {
  if (value === undefined || value === null || value === '') return null;
  const text = String(value).trim().toUpperCase();
  if (/^\d+$/.test(text)) return Number(text);
  const idx = LETTERS.indexOf(text);
  return idx >= 0 ? idx : null;
}

function minutesBetween(start, end) {
  if (!start || !end) return null;
  const mins = Math.round((new Date(end) - new Date(start)) / 60000);
  return mins >= 0 ? mins : null;
}

/**
 * Who has turned in, and grading, for one exam or assignment.
 * Left: every assigned student with their status. Right: the selected
 * student's answers and the marks form.
 */
export default function ExamSubmissionsModal({ isOpen, onClose, examId, onChanged }) {
  const [exam, setExam] = useState(null);
  const [roster, setRoster] = useState([]);
  const [summary, setSummary] = useState(null);
  const [selectedId, setSelectedId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const [writtenMarks, setWrittenMarks] = useState('');
  const [breakdown, setBreakdown] = useState({}); // written question id -> marks (as typed)
  const [feedback, setFeedback] = useState('');
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState('');

  const load = useCallback(async (keepSelection = true) => {
    if (!examId) return;
    try {
      setError('');
      const [detail, subs] = await Promise.all([api.getExamDetail(examId), api.getExamSubmissions(examId)]);
      setExam(detail);
      setRoster(subs.roster || []);
      setSummary(subs);
      setSelectedId((current) => {
        if (keepSelection && current && (subs.roster || []).some((r) => r.student_id === current)) return current;
        const firstToGrade = (subs.roster || []).find((r) => r.submission && !r.submission.is_graded);
        return (firstToGrade || (subs.roster || []).find((r) => r.submission) || (subs.roster || [])[0])?.student_id || null;
      });
    } catch (err) {
      setError(err.message || 'Could not load submissions.');
    } finally {
      setLoading(false);
    }
  }, [examId]);

  useEffect(() => {
    if (isOpen && examId) {
      setLoading(true);
      setExam(null);
      setSelectedId(null);
      load(false);
    }
  }, [isOpen, examId, load]);

  const selected = roster.find((r) => r.student_id === selectedId) || null;
  const submission = selected?.submission || null;

  const total = Number(exam?.total_marks || 0);
  const hasMcq = Array.isArray(exam?.mcq_data) && exam.mcq_data.length > 0;
  const hasWritten = exam && exam.exam_type !== 'MCQ';
  const mcqScore = Number(submission?.mcq_score || 0);
  const maxWritten = Math.max(0, Math.round((total - mcqScore) * 100) / 100);
  const scheme = hasWritten && Array.isArray(exam?.written_scheme) ? exam.written_scheme : [];
  const usesScheme = scheme.length > 0;

  // Load the selected student's marks into the form
  useEffect(() => {
    setFormError('');
    if (!submission) {
      setWrittenMarks('');
      setBreakdown({});
      setFeedback('');
      return;
    }
    setFeedback(submission.tutor_feedback || '');
    const saved = submission.cq_breakdown || {};
    setBreakdown(Object.fromEntries(Object.entries(saved).map(([id, marks]) => [id, String(marks)])));
    if (submission.cq_score !== null && submission.cq_score !== undefined) {
      setWrittenMarks(String(Number(submission.cq_score)));
    } else if (submission.is_graded && submission.obtained_marks !== null) {
      setWrittenMarks(String(Math.max(0, Number(submission.obtained_marks) - Number(submission.mcq_score || 0))));
    } else {
      setWrittenMarks('');
    }
  }, [submission?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  const mcqReview = useMemo(() => {
    if (!hasMcq || !submission) return [];
    return exam.mcq_data.map((q, idx) => {
      const answers = submission.answers_data || {};
      const raw = answers[q.id] ?? answers[`mcq_${idx}`] ?? answers[String(idx)];
      const chosen = answerIndex(raw);
      const correct = answerIndex(q.correct_answer);
      return { q, idx, chosen, correct, isCorrect: chosen !== null && chosen === correct };
    });
  }, [exam, submission, hasMcq]);

  const toGrade = roster.filter((r) => r.submission && !r.submission.is_graded);

  const save = async (goNext) => {
    if (!submission) return;
    setFormError('');
    const payload = { tutor_feedback: feedback };
    if (usesScheme) {
      const cleaned = {};
      for (const item of scheme) {
        const raw = breakdown[item.id];
        const marks = raw === undefined || raw === '' ? NaN : parseFloat(raw);
        if (Number.isNaN(marks) || marks < 0) {
          setFormError(`Enter the marks for "${item.label}" (0 or more).`);
          return;
        }
        if (marks > Number(item.marks)) {
          setFormError(`"${item.label}" is out of ${item.marks}.`);
          return;
        }
        cleaned[item.id] = marks;
      }
      payload.cq_breakdown = cleaned;
    } else if (hasWritten) {
      const marks = parseFloat(writtenMarks);
      if (Number.isNaN(marks) || marks < 0) {
        setFormError('Enter the marks for the written part (0 or more).');
        return;
      }
      if (marks > maxWritten) {
        setFormError(`The written part can be at most ${maxWritten} (total ${total} − MCQ ${mcqScore}).`);
        return;
      }
      payload.cq_score = marks;
    }
    setSaving(true);
    try {
      await api.gradeSubmission(submission.id, payload);
      notify.success(`Saved marks for ${selected.student_name}.`);
      onChanged?.();
      const next = goNext ? toGrade.find((r) => r.student_id !== selected.student_id) : null;
      await load(true);
      if (next) setSelectedId(next.student_id);
    } catch (err) {
      setFormError(err.message || 'Could not save the marks.');
    } finally {
      setSaving(false);
    }
  };

  const schemeSum = scheme.reduce((sum, item) => sum + (parseFloat(breakdown[item.id]) || 0), 0);
  const writtenNumber = usesScheme ? schemeSum : parseFloat(writtenMarks);
  const previewTotal = hasWritten ? mcqScore + (Number.isNaN(writtenNumber) ? 0 : writtenNumber) : mcqScore;

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={exam ? `Submissions — ${exam.title}` : 'Submissions'} maxWidth="max-w-6xl">
      {loading ? (
        <div className="flex items-center gap-2 text-sm text-slate-400 py-10 justify-center">
          <Loader2 className="w-4 h-4 animate-spin" /> Loading…
        </div>
      ) : error ? (
        <div className="p-4 rounded-xl bg-rose-500/10 border border-rose-500/25 text-rose-300 text-sm">{error}</div>
      ) : (
        <div className="space-y-4">
          {/* Summary */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <Summary label="Assigned" value={summary?.assigned_count ?? roster.length} />
            <Summary label="Turned in" value={summary?.count ?? 0} />
            <Summary label="Graded" value={summary?.graded_count ?? 0} tone="emerald" />
            <Summary
              label={summary?.is_closed ? 'Missing' : 'Not yet in'}
              value={roster.filter((r) => !r.submission).length}
              tone={summary?.is_closed ? 'rose' : undefined}
            />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
            {/* Roster */}
            <ul className="lg:col-span-4 space-y-1.5 max-h-[60vh] overflow-y-auto pr-1">
              {roster.length === 0 && (
                <li className="text-sm text-slate-400 p-4 rounded-xl border border-dashed border-slate-700">
                  No students are assigned to this yet.
                </li>
              )}
              {roster.map((row) => {
                const st = STATE[row.state] || STATE.not_submitted;
                const active = row.student_id === selectedId;
                return (
                  <li key={row.student_id}>
                    <button
                      type="button"
                      onClick={() => setSelectedId(row.student_id)}
                      className={`w-full text-left px-3.5 py-3 rounded-xl border transition flex items-center justify-between gap-3 ${
                        active ? 'bg-indigo-500/10 border-indigo-500' : 'bg-slate-800/40 border-slate-700/60 hover:border-slate-500'
                      }`}
                    >
                      <div className="min-w-0">
                        <div className="text-sm font-semibold text-slate-100 truncate">{row.student_name}</div>
                        <div className="text-[11px] text-slate-500">
                          {row.submission
                            ? row.submission.is_graded
                              ? `${Number(row.submission.obtained_marks ?? 0)} / ${total}`
                              : new Date(row.submission.submitted_at).toLocaleString(undefined, { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' })
                            : `@${row.username}`}
                        </div>
                      </div>
                      <span className={`flex-shrink-0 px-2 py-0.5 rounded-full text-[10px] font-bold border ${st.cls}`}>{st.label}</span>
                    </button>
                  </li>
                );
              })}
            </ul>

            {/* Selected student's work */}
            <div className="lg:col-span-8">
              {!selected ? (
                <Empty text="Select a student to see their work." />
              ) : !submission ? (
                <Empty
                  text={
                    selected.state === 'missing'
                      ? `${selected.student_name} did not turn this in before it closed.`
                      : selected.state === 'in_progress'
                      ? `${selected.student_name} has opened it and is still working.`
                      : `${selected.student_name} has not turned this in yet.`
                  }
                />
              ) : (
                <div className="space-y-4 max-h-[60vh] overflow-y-auto pr-1">
                  <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-slate-400">
                    <span className="text-base font-bold text-slate-100">{selected.student_name}</span>
                    <span className="flex items-center gap-3">
                      <span className="flex items-center gap-1">
                        <Clock className="w-3.5 h-3.5" />
                        {new Date(submission.submitted_at).toLocaleString()}
                      </span>
                      {minutesBetween(submission.started_at, submission.submitted_at) !== null && (
                        <span>took {minutesBetween(submission.started_at, submission.submitted_at)} min</span>
                      )}
                      {selected.is_late && <span className="text-amber-300 font-semibold">Late</span>}
                    </span>
                  </div>

                  {/* MCQs */}
                  {hasMcq && (
                    <section>
                      <h4 className="text-xs font-bold text-slate-300 uppercase tracking-wider mb-2">
                        Multiple choice — {mcqReview.filter((r) => r.isCorrect).length} of {mcqReview.length} correct · {mcqScore} marks (auto)
                      </h4>
                      <ol className="space-y-2">
                        {mcqReview.map(({ q, idx, chosen, correct, isCorrect }) => (
                          <li key={q.id || idx} className="rounded-xl border border-slate-700/60 bg-slate-800/30 p-3">
                            <div className="flex items-start gap-2.5">
                              <span
                                className={`w-5 h-5 rounded-full flex items-center justify-center flex-shrink-0 mt-0.5 ${
                                  chosen === null ? 'bg-slate-700 text-slate-400' : isCorrect ? 'bg-emerald-500 text-white' : 'bg-rose-500 text-white'
                                }`}
                              >
                                {chosen === null ? <Minus className="w-3 h-3" /> : isCorrect ? <Check className="w-3 h-3 stroke-[3]" /> : <X className="w-3 h-3 stroke-[3]" />}
                              </span>
                              <div className="min-w-0 flex-1 text-sm text-slate-100">
                                <MathRenderer plain content={`${idx + 1}. ${q.question || ''}`} />
                                <QuestionImage src={q.image_url} alt={`Question ${idx + 1}`} className="mt-1.5" />
                                <div className="mt-1 text-xs text-slate-400 space-y-0.5">
                                  <div>
                                    Answered:{' '}
                                    {chosen === null ? (
                                      <span className="text-slate-500">left blank</span>
                                    ) : (
                                      <span className={isCorrect ? 'text-emerald-300' : 'text-rose-300'}>
                                        {LETTERS[chosen]}. <MathRenderer plain inline content={q.options?.[chosen] ?? ''} />
                                      </span>
                                    )}
                                  </div>
                                  {!isCorrect && correct !== null && (
                                    <div>Correct: <span className="text-emerald-300">{LETTERS[correct]}. <MathRenderer plain inline content={q.options?.[correct] ?? ''} /></span></div>
                                  )}
                                </div>
                              </div>
                              <span className="text-[11px] text-slate-500 flex-shrink-0">{q.points ?? q.marks ?? 1} mk</span>
                            </div>
                          </li>
                        ))}
                      </ol>
                    </section>
                  )}

                  {/* Written work */}
                  {hasWritten && (
                    <section>
                      <h4 className="text-xs font-bold text-slate-300 uppercase tracking-wider mb-2">Written answer</h4>
                      {submission.text_answer ? (
                        <p className="whitespace-pre-wrap text-sm text-slate-100 bg-slate-800/40 border border-slate-700/60 rounded-xl p-3.5">
                          {submission.text_answer}
                        </p>
                      ) : null}
                      {submission.image_urls?.length > 0 ? (
                        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 mt-2">
                          {submission.image_urls.map((url, i) => (
                            <a
                              key={i}
                              href={url}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="group relative rounded-xl overflow-hidden border border-slate-700 bg-slate-950 block"
                            >
                              {/\.pdf($|\?)/i.test(url) ? (
                                <div className="h-32 flex items-center justify-center text-xs text-slate-300">PDF — page {i + 1}</div>
                              ) : (
                                <img src={url} alt={`Answer sheet ${i + 1}`} className="w-full h-32 object-cover" />
                              )}
                              <span className="absolute bottom-1 right-1 px-1.5 py-0.5 rounded bg-slate-950/80 text-[10px] text-slate-200 flex items-center gap-1">
                                <ExternalLink className="w-3 h-3" /> Open
                              </span>
                            </a>
                          ))}
                        </div>
                      ) : !submission.text_answer ? (
                        <p className="text-sm text-slate-400">No written answer was turned in.</p>
                      ) : null}
                    </section>
                  )}

                  {/* Marks */}
                  <section className="rounded-xl border border-slate-700 bg-slate-950/40 p-4 space-y-3">
                    {formError && (
                      <div className="p-2.5 rounded-lg bg-rose-500/10 border border-rose-500/25 text-rose-300 text-xs flex items-center gap-2">
                        <AlertCircle className="w-4 h-4 flex-shrink-0" /> {formError}
                      </div>
                    )}
                    {usesScheme && (
                      <ul className="space-y-2">
                        {scheme.map((item) => (
                          <li key={item.id} className="flex items-center justify-between gap-3">
                            <label htmlFor={`w-${item.id}`} className="text-sm text-slate-200 min-w-0 truncate">{item.label}</label>
                            <span className="flex items-center gap-2 flex-shrink-0">
                              <input
                                id={`w-${item.id}`}
                                type="number"
                                min="0"
                                max={item.marks}
                                step="0.25"
                                value={breakdown[item.id] ?? ''}
                                onChange={(e) => setBreakdown((prev) => ({ ...prev, [item.id]: e.target.value }))}
                                className="w-20 px-2 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-sm font-bold text-emerald-300 text-center focus:outline-none focus:border-indigo-500"
                              />
                              <span className="text-xs text-slate-500 w-12">/ {Number(item.marks)}</span>
                            </span>
                          </li>
                        ))}
                      </ul>
                    )}
                    <div className="grid grid-cols-3 gap-3 items-end">
                      <div>
                        <div className="text-[11px] font-semibold text-slate-400 mb-1">MCQ (auto)</div>
                        <div className="px-3 py-2 rounded-lg bg-slate-800/60 border border-slate-700 text-sm font-bold text-slate-200">{hasMcq ? mcqScore : '—'}</div>
                      </div>
                      <div>
                        <label htmlFor="written-marks" className="block text-[11px] font-semibold text-slate-400 mb-1">
                          Written {usesScheme ? '(sum)' : hasWritten ? `(max ${maxWritten})` : ''}
                        </label>
                        {usesScheme ? (
                          <div className="px-3 py-2 rounded-lg bg-slate-800/60 border border-slate-700 text-sm font-bold text-slate-200">
                            {Math.round(schemeSum * 100) / 100}
                          </div>
                        ) : hasWritten ? (
                          <input
                            id="written-marks"
                            type="number"
                            min="0"
                            max={maxWritten}
                            step="0.25"
                            value={writtenMarks}
                            onChange={(e) => setWrittenMarks(e.target.value)}
                            className="w-full px-3 py-2 rounded-lg bg-slate-800 border border-slate-700 text-sm font-bold text-emerald-300 focus:outline-none focus:border-indigo-500"
                          />
                        ) : (
                          <div className="px-3 py-2 rounded-lg bg-slate-800/60 border border-slate-700 text-sm text-slate-500">—</div>
                        )}
                      </div>
                      <div>
                        <div className="text-[11px] font-semibold text-slate-400 mb-1">Total</div>
                        <div className="px-3 py-2 rounded-lg bg-emerald-500/10 border border-emerald-500/30 text-sm font-extrabold text-emerald-300 flex items-center gap-1.5">
                          <Award className="w-4 h-4" /> {Math.round(previewTotal * 100) / 100} / {total}
                        </div>
                      </div>
                    </div>
                    <div>
                      <label htmlFor="tutor-feedback" className="block text-[11px] font-semibold text-slate-400 mb-1">
                        Feedback for the student <span className="font-normal text-slate-500">(optional)</span>
                      </label>
                      <textarea
                        id="tutor-feedback"
                        rows={2}
                        value={feedback}
                        onChange={(e) => setFeedback(e.target.value)}
                        className="w-full px-3 py-2 rounded-lg bg-slate-800 border border-slate-700 text-sm text-slate-100 focus:outline-none focus:border-indigo-500"
                      />
                    </div>
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className="text-[11px] text-slate-500">
                        {exam.results_released
                          ? 'Results are out: students see these marks straight away.'
                          : exam.result_publish_mode === 'IMMEDIATE'
                          ? 'Each student sees their result as soon as they submit.'
                          : exam.result_publish_mode === 'SCHEDULED'
                          ? 'Students see marks when results are published automatically.'
                          : 'Results are hidden from students until you publish them.'}
                      </span>
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => save(false)}
                          disabled={saving}
                          className="px-4 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 border border-slate-700 text-slate-100 text-xs font-semibold transition disabled:opacity-50"
                        >
                          {saving ? 'Saving…' : submission.is_graded ? 'Update marks' : 'Save marks'}
                        </button>
                        {toGrade.some((r) => r.student_id !== selected.student_id) && (
                          <button
                            type="button"
                            onClick={() => save(true)}
                            disabled={saving}
                            className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold flex items-center gap-1 transition disabled:opacity-50"
                          >
                            Save & next <ChevronRight className="w-4 h-4" />
                          </button>
                        )}
                      </div>
                    </div>
                  </section>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </Modal>
  );
}

function Summary({ label, value, tone }) {
  const color = tone === 'emerald' ? 'text-emerald-400' : tone === 'rose' ? 'text-rose-300' : 'text-slate-100';
  return (
    <div className="rounded-xl bg-slate-800/40 border border-slate-700/60 px-4 py-2.5">
      <div className="text-[10px] font-bold uppercase tracking-wider text-slate-500">{label}</div>
      <div className={`text-xl font-extrabold ${color}`}>{value}</div>
    </div>
  );
}

function Empty({ text }) {
  return (
    <div className="h-full min-h-[200px] flex items-center justify-center rounded-xl border border-dashed border-slate-700 text-sm text-slate-400 p-6 text-center">
      {text}
    </div>
  );
}
