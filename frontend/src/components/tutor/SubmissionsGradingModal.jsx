import React, { useState, useEffect } from 'react';
import Modal from '../common/Modal';
import { api } from '../../api/client';
import { Award, CheckCircle2, AlertCircle, FileText, ExternalLink, Image as ImageIcon } from 'lucide-react';
import StatusBadge from '../common/StatusBadge';

export default function SubmissionsGradingModal({
  isOpen,
  onClose,
  exam,
  submission,
  onGraded,
}) {
  const submissionsList = (exam?.submissions && exam.submissions.length > 0)
    ? exam.submissions
    : (submission ? [submission] : []);

  const [selectedSubId, setSelectedSubId] = useState(submission?.id || (submissionsList[0]?.id));
  const activeSubmission = submissionsList.find(s => s.id === selectedSubId) || submissionsList[0] || submission;

  const [obtainedMarks, setObtainedMarks] = useState('');
  const [feedback, setFeedback] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (submission?.id) {
      setSelectedSubId(submission.id);
    } else if (submissionsList[0]?.id) {
      setSelectedSubId(submissionsList[0].id);
    }
  }, [submission, exam]);

  useEffect(() => {
    if (activeSubmission) {
      setObtainedMarks(activeSubmission.obtained_marks !== null ? activeSubmission.obtained_marks : '');
      setFeedback(activeSubmission.tutor_feedback || '');
      setError('');
    }
  }, [activeSubmission]);

  if (!activeSubmission || !exam) return null;

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');

    const marksNum = parseFloat(obtainedMarks);
    if (isNaN(marksNum) || marksNum < 0) {
      setError('Please enter a valid marks value.');
      return;
    }

    if (marksNum > parseFloat(exam.total_marks)) {
      setError(`Marks cannot exceed exam total of ${exam.total_marks}.`);
      return;
    }

    setLoading(true);
    try {
      await api.gradeSubmission(activeSubmission.id, {
        obtained_marks: marksNum,
        tutor_feedback: feedback,
      });
      onGraded();
      if (submissionsList.length <= 1) {
        onClose();
      } else {
        alert(`Grade saved for ${activeSubmission.student_name}!`);
      }
    } catch (err) {
      setError(err.message || 'Failed to grade submission.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={`Grade Submission — ${exam.title}`} maxWidth="max-w-3xl">
      <div className="space-y-5">
        {/* Multi-student submission selector for group / tuition exams */}
        {submissionsList.length > 1 && (
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 p-3 rounded-xl bg-slate-800/80 border border-indigo-500/30">
            <span className="text-xs text-indigo-300 font-semibold">
              Select Submission ({submissionsList.length} students):
            </span>
            <select
              value={activeSubmission.id}
              onChange={(e) => setSelectedSubId(e.target.value)}
              className="bg-slate-900 text-slate-100 text-xs rounded-lg px-3 py-1.5 border border-slate-700 focus:outline-none focus:border-indigo-500"
            >
              {submissionsList.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.student_name} — {s.is_graded ? `Graded (${s.obtained_marks}/${exam.total_marks})` : 'Pending'} ({new Date(s.submitted_at).toLocaleDateString()})
                </option>
              ))}
            </select>
          </div>
        )}

        {/* Student submission metadata */}
        <div className="flex flex-wrap items-center justify-between gap-3 p-3.5 rounded-xl bg-slate-800/40 border border-slate-700/60 text-xs">
          <div>
            <span className="text-slate-400">Student: </span>
            <strong className="text-slate-200">{activeSubmission.student_name}</strong>
          </div>
          <div>
            <span className="text-slate-400">Submitted: </span>
            <span className="text-slate-200">
              {activeSubmission.submitted_at
                ? new Date(activeSubmission.submitted_at).toLocaleString()
                : 'Pending'}
            </span>
          </div>
          <div>
            <StatusBadge status={activeSubmission.status} />
          </div>
          <div>
            <span className="text-slate-400">Total Exam Marks: </span>
            <strong className="text-emerald-400 font-bold">{exam.total_marks}</strong>
          </div>
        </div>

        {/* Section 1: MCQ Answers Data (if any) */}
        {submission.answers_data && Object.keys(submission.answers_data).length > 0 && (
          <div>
            <h4 className="text-xs font-bold text-slate-300 uppercase tracking-wider mb-2 flex items-center gap-1.5">
              <FileText className="w-4 h-4 text-indigo-400" />
              MCQ Answers Recorded
            </h4>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              {Object.entries(submission.answers_data).map(([q, ans]) => (
                <div key={q} className="p-2.5 rounded-lg bg-slate-800/60 border border-slate-700 text-xs flex justify-between">
                  <span className="font-mono text-slate-400 uppercase">{q}:</span>
                  <span className="font-bold text-indigo-300">{String(ans)}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Section 2: Uploaded CQ Answer Sheets (Images / PDFs) */}
        {submission.image_urls && submission.image_urls.length > 0 ? (
          <div>
            <h4 className="text-xs font-bold text-slate-300 uppercase tracking-wider mb-2 flex items-center gap-1.5">
              <ImageIcon className="w-4 h-4 text-emerald-400" />
              Submitted CQ Answer Sheets ({submission.image_urls.length})
            </h4>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 max-h-[300px] overflow-y-auto p-1">
              {submission.image_urls.map((imgUrl, idx) => (
                <div key={idx} className="relative group rounded-xl overflow-hidden border border-slate-700 bg-slate-950">
                  <img
                    src={imgUrl}
                    alt={`CQ Sheet #${idx + 1}`}
                    className="w-full h-44 object-contain bg-slate-900"
                  />
                  <div className="absolute inset-0 bg-slate-950/70 opacity-0 group-hover:opacity-100 transition flex items-center justify-center gap-2">
                    <a
                      href={imgUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="px-3 py-1.5 rounded-lg bg-indigo-600 text-white text-xs font-semibold flex items-center gap-1.5"
                    >
                      <ExternalLink className="w-3.5 h-3.5" />
                      View Full Size
                    </a>
                  </div>
                  <div className="p-2 bg-slate-800/90 text-[11px] text-slate-300 font-mono truncate">
                    Sheet #{idx + 1}
                  </div>
                </div>
              ))}
            </div>
          </div>
        ) : (
          <div className="p-3 rounded-xl bg-slate-800/30 border border-slate-700/50 text-xs text-slate-400 text-center">
            No CQ image sheets uploaded for this submission.
          </div>
        )}

        {/* Section 3: Grading Form */}
        <form onSubmit={handleSubmit} className="pt-3 border-t border-slate-800 space-y-4">
          {error && (
            <div className="p-3 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs flex items-center gap-2">
              <AlertCircle className="w-4 h-4 flex-shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div>
              <label className="block text-xs font-semibold text-slate-300 mb-1">
                Awarded Marks *
              </label>
              <div className="relative">
                <input
                  type="number"
                  step="0.5"
                  min="0"
                  max={exam.total_marks}
                  required
                  value={obtainedMarks}
                  onChange={(e) => setObtainedMarks(e.target.value)}
                  placeholder={`Max ${exam.total_marks}`}
                  className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-emerald-400 font-bold text-sm focus:outline-none focus:border-indigo-500 transition"
                />
                <span className="absolute right-3 top-2 text-xs text-slate-500">
                  / {exam.total_marks}
                </span>
              </div>
            </div>

            <div className="sm:col-span-2">
              <label className="block text-xs font-semibold text-slate-300 mb-1">
                Tutor Feedback & Comments
              </label>
              <textarea
                rows={2}
                value={feedback}
                onChange={(e) => setFeedback(e.target.value)}
                placeholder="e.g. Great work in dynamics derivation! Need practice on circular motion."
                className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-xs focus:outline-none focus:border-indigo-500 transition"
              />
            </div>
          </div>

          <div className="flex items-center justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl border border-slate-700 text-slate-300 text-xs hover:bg-slate-800 transition"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={loading}
              className="px-5 py-2 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white font-semibold text-xs shadow-lg shadow-emerald-600/30 flex items-center gap-1.5 transition disabled:opacity-50"
            >
              {loading ? (
                'Saving Grade...'
              ) : (
                <>
                  <Award className="w-4 h-4" />
                  <span>{submission.is_graded ? 'Update Grade' : 'Finalize Grade & Feedback'}</span>
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </Modal>
  );
}
