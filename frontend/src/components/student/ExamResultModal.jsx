import React from 'react';
import Modal from '../common/Modal';
import { Award, CheckCircle2, Clock, MessageSquare, ExternalLink, Image as ImageIcon } from 'lucide-react';
import StatusBadge from '../common/StatusBadge';

export default function ExamResultModal({
  isOpen,
  onClose,
  exam,
}) {
  if (!exam || !exam.submission) return null;

  const { submission } = exam;
  const isGraded = submission.is_graded;
  const obtained = submission.obtained_marks !== null ? parseFloat(submission.obtained_marks) : null;
  const total = parseFloat(exam.total_marks);
  const percentage = obtained !== null && total > 0 ? Math.round((obtained / total) * 100) : 0;

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={`Exam Results — ${exam.title}`} maxWidth="max-w-3xl">
      <div className="space-y-6">
        {/* Score Banner */}
        <div className="p-6 rounded-2xl bg-gradient-to-br from-slate-900 to-indigo-950/60 border border-indigo-500/30 flex flex-col sm:flex-row items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <div className={`w-16 h-16 rounded-2xl flex items-center justify-center ${
              isGraded ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30' : 'bg-slate-800 text-slate-400'
            }`}>
              <Award className="w-8 h-8" />
            </div>

            <div>
              <span className="text-xs font-semibold uppercase tracking-wider text-slate-400">
                Official Result
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
            </div>
          </div>

          <div className="flex flex-col items-end gap-1">
            <StatusBadge status={submission.status} />
            <span className="text-[11px] text-slate-400">
              Submitted: {new Date(submission.submitted_at).toLocaleDateString()}
            </span>
          </div>
        </div>

        {/* Tutor Feedback Note */}
        {isGraded && submission.tutor_feedback && (
          <div className="p-4 rounded-xl bg-slate-800/40 border border-slate-700/60">
            <h4 className="text-xs font-bold text-indigo-300 uppercase tracking-wider mb-1.5 flex items-center gap-2">
              <MessageSquare className="w-4 h-4 text-indigo-400" />
              Tutor Comments & Recommendations
            </h4>
            <p className="text-sm text-slate-200 leading-relaxed italic">
              "{submission.tutor_feedback}"
            </p>
          </div>
        )}

        {/* Submitted MCQ Answers */}
        {submission.answers_data && Object.keys(submission.answers_data).length > 0 && (
          <div>
            <h4 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">
              Your Submitted Answers
            </h4>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              {Object.entries(submission.answers_data).map(([q, ans]) => (
                <div key={q} className="p-2 rounded-lg bg-slate-800/60 border border-slate-700 text-xs flex justify-between">
                  <span className="font-mono text-slate-400 uppercase">{q}:</span>
                  <span className="font-bold text-slate-100">{String(ans)}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Uploaded Answer Sheets */}
        {submission.image_urls && submission.image_urls.length > 0 && (
          <div>
            <h4 className="text-xs font-bold text-slate-400 uppercase tracking-wider mb-2 flex items-center gap-1.5">
              <ImageIcon className="w-4 h-4 text-slate-500" />
              Uploaded Script Pages
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
                  <img src={url} alt={`Page ${i + 1}`} className="w-full h-24 object-cover group-hover:scale-105 transition" />
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
            className="px-4 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-semibold transition"
          >
            Close Report
          </button>
        </div>
      </div>
    </Modal>
  );
}
