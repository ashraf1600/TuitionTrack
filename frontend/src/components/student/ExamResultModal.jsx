import React, { useState } from 'react';
import Modal from '../common/Modal';
import MathRenderer from '../common/MathRenderer';
import LeaderboardModal from '../common/LeaderboardModal';
import {
  Award,
  CheckCircle2,
  Clock,
  MessageSquare,
  ExternalLink,
  Image as ImageIcon,
  Trophy,
  XCircle,
  HelpCircle,
  BookOpen,
  Sparkles,
} from 'lucide-react';
import StatusBadge from '../common/StatusBadge';

export default function ExamResultModal({
  isOpen,
  onClose,
  exam,
}) {
  const [leaderboardOpen, setLeaderboardOpen] = useState(false);

  if (!exam || !exam.submission) return null;

  const { submission } = exam;
  const isGraded = submission.is_graded;
  const obtained = submission.obtained_marks !== null ? parseFloat(submission.obtained_marks) : null;
  const total = parseFloat(exam.total_marks);
  const percentage = obtained !== null && total > 0 ? Math.round((obtained / total) * 100) : 0;

  const hasMCQs = Array.isArray(exam.mcq_data) && exam.mcq_data.length > 0;
  const LETTER_MAP = ['A', 'B', 'C', 'D'];

  return (
    <>
      <Modal isOpen={isOpen} onClose={onClose} title={`Exam Results — ${exam.title}`} maxWidth="max-w-4xl">
        <div className="space-y-6">
          {/* Score Banner */}
          <div className="p-6 rounded-2xl bg-gradient-to-br from-slate-900 via-indigo-950/40 to-slate-900 border border-indigo-500/30 flex flex-col sm:flex-row items-center justify-between gap-4">
            <div className="flex items-center gap-4">
              <div
                className={`w-16 h-16 rounded-2xl flex items-center justify-center ${
                  isGraded
                    ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
                    : 'bg-slate-800 text-slate-400'
                }`}
              >
                <Award className="w-8 h-8" />
              </div>

              <div>
                <span className="text-xs font-semibold uppercase tracking-wider text-slate-400">
                  Official Score & Result
                </span>
                <div className="text-2xl font-extrabold text-slate-100 mt-0.5">
                  {isGraded ? (
                    <span>
                      <strong className="text-emerald-400">{obtained}</strong> / {total}{' '}
                      <span className="text-sm font-semibold text-slate-400">({percentage}%)</span>
                    </span>
                  ) : (
                    <span className="text-indigo-300 text-lg">Under Evaluation by Tutor</span>
                  )}
                </div>

                <div className="flex items-center gap-2 mt-1 text-xs font-mono">
                  {submission.mcq_score !== null && (
                    <span className="text-indigo-300">MCQ: {submission.mcq_score} Pts</span>
                  )}
                  {submission.cq_score !== null && (
                    <span className="text-emerald-400">• CQ: {submission.cq_score} Pts</span>
                  )}
                </div>
              </div>
            </div>

            <div className="flex flex-col sm:items-end gap-2">
              <div className="flex items-center gap-2">
                <StatusBadge status={submission.status} />
                <button
                  type="button"
                  onClick={() => setLeaderboardOpen(true)}
                  className="px-3 py-1.5 rounded-xl bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 border border-amber-500/40 text-xs font-bold flex items-center gap-1.5 transition shadow-sm"
                >
                  <Trophy className="w-3.5 h-3.5" />
                  <span>Leaderboard</span>
                </button>
              </div>
              <span className="text-[11px] text-slate-400">
                Submitted: {new Date(submission.submitted_at).toLocaleString()}
              </span>
            </div>
          </div>

          {/* Tutor Feedback Note */}
          {isGraded && submission.tutor_feedback && (
            <div className="p-4 rounded-xl bg-slate-800/40 border border-slate-700/60">
              <h4 className="text-xs font-bold text-indigo-300 uppercase tracking-wider mb-1.5 flex items-center gap-2">
                <MessageSquare className="w-4 h-4 text-indigo-400" />
                Tutor Feedback & Suggestions
              </h4>
              <p className="text-sm text-slate-200 leading-relaxed italic">
                "{submission.tutor_feedback}"
              </p>
            </div>
          )}

          {/* Question-by-Question MCQ Review */}
          {hasMCQs && (
            <div className="space-y-3">
              <h4 className="text-xs font-bold text-slate-300 uppercase tracking-wider flex items-center gap-2">
                <Sparkles className="w-4 h-4 text-amber-400" />
                MCQ Detailed Breakdown & Answer Key
              </h4>

              <div className="space-y-3 max-h-[360px] overflow-y-auto pr-1">
                {exam.mcq_data.map((q, idx) => {
                  const qKey = q.id || `mcq-${idx}`;
                  const studentChoice = submission.answers_data?.[qKey] ?? submission.answers_data?.[`mcq_${idx}`];
                  const hasAnswered = studentChoice !== undefined && studentChoice !== null && studentChoice !== '';

                  // Normalize indices and letters
                  const correctVal = q.correct_answer;
                  const isCorrect =
                    hasAnswered &&
                    (String(studentChoice) === String(correctVal) ||
                      LETTER_MAP[studentChoice] === String(correctVal).toUpperCase() ||
                      String(studentChoice).toUpperCase() === String(correctVal).toUpperCase());

                  return (
                    <div
                      key={qKey}
                      className={`p-4 rounded-xl border space-y-2.5 ${
                        isCorrect
                          ? 'bg-emerald-950/20 border-emerald-500/30'
                          : hasAnswered
                          ? 'bg-rose-950/20 border-rose-500/30'
                          : 'bg-slate-900 border-slate-800'
                      }`}
                    >
                      <div className="flex items-start justify-between gap-2">
                        <div className="flex items-start gap-2">
                          <span
                            className={`w-5 h-5 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0 mt-0.5 ${
                              isCorrect
                                ? 'bg-emerald-500/20 text-emerald-400'
                                : hasAnswered
                                ? 'bg-rose-500/20 text-rose-400'
                                : 'bg-slate-800 text-slate-400'
                            }`}
                          >
                            {isCorrect ? '✓' : hasAnswered ? '✕' : '?'}
                          </span>
                          <div className="text-xs font-semibold text-slate-100">
                            <MathRenderer content={`${idx + 1}. ${q.question}`} />
                          </div>
                        </div>

                        <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-slate-800 text-slate-300">
                          {q.points || q.marks || 1} Pt
                        </span>
                      </div>

                      {/* Options List */}
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 pl-7">
                        {(q.options || []).map((opt, optIdx) => {
                          const isStudentSelected =
                            String(studentChoice) === String(optIdx) ||
                            String(studentChoice).toUpperCase() === LETTER_MAP[optIdx];
                          const isCorrectOption =
                            String(correctVal) === String(optIdx) ||
                            String(correctVal).toUpperCase() === LETTER_MAP[optIdx];

                          return (
                            <div
                              key={optIdx}
                              className={`p-2 rounded-lg border text-xs flex items-center gap-2 ${
                                isCorrectOption
                                  ? 'bg-emerald-500/20 border-emerald-500/40 text-emerald-200 font-bold'
                                  : isStudentSelected
                                  ? 'bg-rose-500/20 border-rose-500/40 text-rose-300 line-through'
                                  : 'bg-slate-800/40 border-slate-800 text-slate-400'
                              }`}
                            >
                              <span className="font-mono text-[10px] uppercase font-bold">
                                {LETTER_MAP[optIdx]}:
                              </span>
                              <span className="flex-1">
                                <MathRenderer content={opt} />
                              </span>
                              {isCorrectOption && (
                                <span className="text-[10px] text-emerald-400 uppercase font-mono font-bold">
                                  Correct
                                </span>
                              )}
                              {isStudentSelected && !isCorrectOption && (
                                <span className="text-[10px] text-rose-400 uppercase font-mono font-bold">
                                  Your Choice
                                </span>
                              )}
                            </div>
                          );
                        })}
                      </div>

                      {/* Explanation note */}
                      {q.explanation && (
                        <div className="pl-7 text-[11px] text-slate-400 flex items-center gap-1.5 pt-1">
                          <HelpCircle className="w-3.5 h-3.5 text-indigo-400 flex-shrink-0" />
                          <span>
                            <strong>Explanation:</strong> {q.explanation}
                          </span>
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* Official Model Solution / Derivations */}
          {(exam.solution_html || exam.solution_media_url) && (
            <div className="p-4 rounded-xl bg-slate-900 border border-slate-800 space-y-3">
              <h4 className="text-xs font-bold text-indigo-300 uppercase tracking-wider flex items-center gap-2">
                <BookOpen className="w-4 h-4 text-indigo-400" />
                Official Tutor Model Solution & Derivations
              </h4>

              {exam.solution_html && (
                <div className="p-4 rounded-lg bg-slate-950/80 border border-slate-800 text-xs text-slate-200">
                  <MathRenderer content={exam.solution_html} />
                </div>
              )}

              {exam.solution_media_url && (
                <div className="pt-2">
                  <a
                    href={exam.solution_media_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-300 border border-indigo-500/30 text-xs font-semibold transition"
                  >
                    <ExternalLink className="w-3.5 h-3.5" />
                    <span>View Attached Solution Sheet / PDF</span>
                  </a>
                </div>
              )}
            </div>
          )}

          {/* Uploaded Answer Sheets */}
          {submission.image_urls && submission.image_urls.length > 0 && (
            <div>
              <h4 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-2 flex items-center gap-1.5">
                <ImageIcon className="w-4 h-4 text-slate-500" />
                Your Turned-In Answer Sheets ({submission.image_urls.length} Pages)
              </h4>
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                {submission.image_urls.map((url, i) => (
                  <a
                    key={i}
                    href={url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="group relative rounded-xl overflow-hidden border border-slate-700 block bg-slate-950"
                  >
                    <img
                      src={url}
                      alt={`Page ${i + 1}`}
                      className="w-full h-24 object-cover group-hover:scale-105 transition"
                    />
                    <div className="absolute inset-0 bg-slate-950/50 opacity-0 group-hover:opacity-100 transition flex items-center justify-center">
                      <ExternalLink className="w-4 h-4 text-white" />
                    </div>
                  </a>
                ))}
              </div>
            </div>
          )}

          <div className="pt-2 flex justify-end">
            <button
              onClick={onClose}
              className="px-5 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-semibold transition"
            >
              Close Report
            </button>
          </div>
        </div>
      </Modal>

      {/* Leaderboard Modal */}
      {leaderboardOpen && (
        <LeaderboardModal
          isOpen={leaderboardOpen}
          onClose={() => setLeaderboardOpen(false)}
          examId={exam.id}
          examTitle={exam.title}
        />
      )}
    </>
  );
}
