import React, { useState, useEffect } from 'react';
import {
  BookOpen, Plus, Clock, CheckCircle2, AlertTriangle, ExternalLink,
  Trash2, MessageSquare, Loader2, RefreshCw, X, Calendar, User, Users,
  Check, ChevronRight
} from 'lucide-react';
import { api } from '../../api/client';
import { notify } from '../../utils/toast';
import { confirmAction } from '../common/ConfirmDialog';

export default function HomeworkManager({ tuitions = [], students = [] }) {
  const [homeworkList, setHomeworkList] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('all'); // 'all' | 'pending' | 'evaluated'
  const [createModalOpen, setCreateModalOpen] = useState(false);
  const [evaluatingHw, setEvaluatingHw] = useState(null);
  const [feedbackText, setFeedbackText] = useState('');
  const [submittingEval, setSubmittingEval] = useState(false);

  const loadHomework = async () => {
    try {
      setLoading(true);
      const data = await api.getHomework();
      setHomeworkList(Array.isArray(data) ? data : data?.results || []);
    } catch (err) {
      console.error('Failed to load homework:', err);
      notify.error('Could not load homework assignments.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadHomework();
  }, []);

  const handleDelete = async (id) => {
    const ok = await confirmAction({
      title: 'Delete homework?',
      message: 'This homework assignment will be removed for all students. This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    });
    if (!ok) return;
    try {
      await api.deleteHomework(id);
      setHomeworkList((prev) => prev.filter((h) => h.id !== id));
      notify.success('Homework deleted.');
    } catch (err) {
      notify.error(err.message || 'Failed to delete homework.');
    }
  };

  const handleMarkDone = async (e) => {
    e.preventDefault();
    if (!evaluatingHw) return;
    setSubmittingEval(true);
    try {
      const res = await api.markHomeworkDone(evaluatingHw.id, feedbackText.trim());
      notify.success('Homework marked as evaluated!');
      setHomeworkList((prev) =>
        prev.map((h) => (h.id === evaluatingHw.id ? res.homework : h))
      );
      setEvaluatingHw(null);
      setFeedbackText('');
    } catch (err) {
      notify.error(err.message || 'Failed to mark homework as done.');
    } finally {
      setSubmittingEval(false);
    }
  };

  const filtered = homeworkList.filter((h) => {
    if (filter === 'pending') return !h.is_evaluated;
    if (filter === 'evaluated') return h.is_evaluated;
    return true;
  });

  return (
    <div className="space-y-6">
      {/* Header and Controls */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-xl font-bold text-slate-100 flex items-center gap-2">
            <BookOpen className="w-5 h-5 text-indigo-400" />
            Homework Assignments
          </h2>
          <p className="text-xs text-slate-400 mt-0.5">
            Assign tasks to tuition batches or specific students, review submissions, and give feedback.
          </p>
        </div>

        <div className="flex items-center gap-2">
          <div className="flex p-1 bg-slate-900 border border-slate-800 rounded-xl text-xs">
            <button
              onClick={() => setFilter('all')}
              className={`px-3 py-1.5 rounded-lg font-semibold transition ${
                filter === 'all' ? 'bg-indigo-600 text-white' : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              All ({homeworkList.length})
            </button>
            <button
              onClick={() => setFilter('pending')}
              className={`px-3 py-1.5 rounded-lg font-semibold transition ${
                filter === 'pending' ? 'bg-indigo-600 text-white' : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              Pending ({homeworkList.filter((h) => !h.is_evaluated).length})
            </button>
            <button
              onClick={() => setFilter('evaluated')}
              className={`px-3 py-1.5 rounded-lg font-semibold transition ${
                filter === 'evaluated' ? 'bg-indigo-600 text-white' : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              Evaluated ({homeworkList.filter((h) => h.is_evaluated).length})
            </button>
          </div>

          <button
            onClick={() => setCreateModalOpen(true)}
            className="px-3.5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold flex items-center gap-1.5 shadow-md shadow-indigo-600/20 transition"
          >
            <Plus className="w-4 h-4" />
            Assign Homework
          </button>

          <button
            onClick={loadHomework}
            className="p-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-400 hover:text-slate-200 border border-slate-700 transition"
            title="Refresh"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Homework List */}
      {loading ? (
        <div className="flex items-center justify-center py-16">
          <Loader2 className="w-8 h-8 text-indigo-400 animate-spin" />
        </div>
      ) : filtered.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-slate-800 bg-slate-900/40 p-12 text-center">
          <BookOpen className="w-10 h-10 mx-auto text-slate-600 mb-3" />
          <p className="text-sm font-bold text-slate-300">No homework found</p>
          <p className="text-xs text-slate-500 mt-1 max-w-sm mx-auto">
            {filter === 'all'
              ? 'Click "Assign Homework" above to create tasks for your students.'
              : `No ${filter} homework assignments right now.`}
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {filtered.map((hw) => {
            const isDuePassed = new Date(hw.due_date) < new Date();
            return (
              <div
                key={hw.id}
                className={`rounded-2xl border p-5 flex flex-col justify-between transition-all ${
                  hw.is_evaluated
                    ? 'bg-slate-900/60 border-slate-800'
                    : isDuePassed
                    ? 'bg-gradient-to-br from-slate-900 via-rose-950/20 to-slate-900 border-rose-500/30'
                    : 'bg-slate-900/80 border-slate-800 hover:border-slate-700'
                }`}
              >
                <div className="space-y-3">
                  {/* Target & Status Pills */}
                  <div className="flex items-center justify-between gap-2">
                    <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-indigo-500/15 border border-indigo-500/25 text-indigo-300">
                      {hw.tuition_title ? (
                        <>
                          <Users className="w-3 h-3" /> {hw.tuition_title}
                        </>
                      ) : (
                        <>
                          <User className="w-3 h-3" /> {hw.student_name || 'Individual Student'}
                        </>
                      )}
                    </span>

                    {hw.is_evaluated ? (
                      <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-emerald-500/15 border border-emerald-500/30 text-emerald-300">
                        <CheckCircle2 className="w-3 h-3" /> Evaluated
                      </span>
                    ) : isDuePassed ? (
                      <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-rose-500/15 border border-rose-500/30 text-rose-300">
                        <AlertTriangle className="w-3 h-3" /> Due Passed
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-amber-500/15 border border-amber-500/30 text-amber-300">
                        <Clock className="w-3 h-3" /> Pending Evaluation
                      </span>
                    )}
                  </div>

                  {/* Title & Instructions */}
                  <div>
                    <h3 className="text-base font-bold text-slate-100">{hw.title}</h3>
                    {hw.description && (
                      <p className="text-xs text-slate-400 mt-1 line-clamp-3 leading-relaxed">
                        {hw.description}
                      </p>
                    )}
                  </div>

                  {/* Due Date & Submission Link */}
                  <div className="pt-2 border-t border-slate-800/80 space-y-2 text-xs">
                    <div className="flex items-center justify-between text-slate-400">
                      <span className="flex items-center gap-1.5">
                        <Calendar className="w-3.5 h-3.5 text-slate-500" />
                        Due: {new Date(hw.due_date).toLocaleString(undefined, {
                          month: 'short',
                          day: 'numeric',
                          hour: 'numeric',
                          minute: '2-digit',
                        })}
                      </span>
                    </div>

                    {hw.submitted_online_url ? (
                      <div className="flex items-center justify-between bg-slate-800/60 rounded-xl px-3 py-2 border border-slate-700/60">
                        <div className="flex items-center gap-2 text-slate-300 truncate">
                          <ExternalLink className="w-3.5 h-3.5 text-indigo-400 flex-shrink-0" />
                          <span className="text-[11px] truncate">{hw.submitted_online_url}</span>
                        </div>
                        <a
                          href={hw.submitted_online_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-[11px] font-bold text-indigo-400 hover:text-indigo-300 flex-shrink-0 ml-2"
                        >
                          Open Link
                        </a>
                      </div>
                    ) : (
                      <div className="text-[11px] text-slate-500 italic">
                        No online submission link submitted yet
                      </div>
                    )}

                    {hw.tutor_feedback && (
                      <div className="bg-emerald-950/20 border border-emerald-500/20 rounded-xl p-2.5 text-xs text-emerald-300">
                        <span className="font-semibold block text-[10px] text-emerald-400 uppercase tracking-wider">Your Feedback:</span>
                        {hw.tutor_feedback}
                      </div>
                    )}
                  </div>
                </div>

                {/* Actions */}
                <div className="mt-4 pt-3 border-t border-slate-800 flex items-center justify-between gap-2">
                  <button
                    type="button"
                    onClick={() => handleDelete(hw.id)}
                    className="p-1.5 rounded-lg text-slate-500 hover:text-rose-400 hover:bg-slate-800 transition"
                    title="Delete Homework"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>

                  {!hw.is_evaluated && (
                    <button
                      type="button"
                      onClick={() => {
                        setEvaluatingHw(hw);
                        setFeedbackText(hw.tutor_feedback || '');
                      }}
                      className="px-3 py-1.5 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold flex items-center gap-1.5 shadow-md shadow-emerald-600/20 transition"
                    >
                      <Check className="w-3.5 h-3.5" />
                      Mark Evaluated
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Assign Homework Modal */}
      {createModalOpen && (
        <CreateHomeworkModal
          tuitions={tuitions}
          students={students}
          onClose={() => setCreateModalOpen(false)}
          onCreated={(newHw) => {
            setHomeworkList((prev) => [newHw, ...prev]);
            setCreateModalOpen(false);
          }}
        />
      )}

      {/* Mark Done / Evaluation Modal */}
      {evaluatingHw && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-slate-950/80 backdrop-blur-sm" onClick={() => setEvaluatingHw(null)} />
          <div className="relative w-full max-w-md rounded-2xl border border-slate-800 bg-slate-900 p-6 shadow-2xl">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-base font-bold text-slate-100 flex items-center gap-2">
                <CheckCircle2 className="w-5 h-5 text-emerald-400" />
                Evaluate Homework
              </h3>
              <button
                onClick={() => setEvaluatingHw(null)}
                className="p-1 rounded-lg text-slate-400 hover:text-slate-200 hover:bg-slate-800"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <p className="text-xs text-slate-400 mb-4">
              Marking <strong className="text-slate-200 font-semibold">{evaluatingHw.title}</strong> as evaluated. Only you as the tutor can approve this.
            </p>

            <form onSubmit={handleMarkDone} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-300 uppercase tracking-wider mb-2">
                  Feedback / Comments <span className="text-slate-500 font-normal">(optional)</span>
                </label>
                <textarea
                  value={feedbackText}
                  onChange={(e) => setFeedbackText(e.target.value)}
                  rows={3}
                  placeholder="e.g. Good answers, well documented. Practice question 5 again."
                  className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-sm text-slate-100 placeholder:text-slate-500 focus:outline-none focus:border-emerald-500 resize-none"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setEvaluatingHw(null)}
                  className="px-4 py-2 rounded-xl text-xs font-semibold text-slate-400 hover:text-slate-200 hover:bg-slate-800 transition"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submittingEval}
                  className="px-4 py-2 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold flex items-center gap-1.5 transition disabled:opacity-50"
                >
                  {submittingEval ? <Loader2 className="w-4 h-4 animate-spin" /> : <Check className="w-4 h-4" />}
                  Confirm Evaluated
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

function CreateHomeworkModal({ tuitions, students, onClose, onCreated }) {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [targetType, setTargetType] = useState('tuition'); // 'tuition' | 'student'
  const [targetId, setTargetId] = useState(tuitions[0]?.id || '');
  const [dueDate, setDueDate] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  // Default to tomorrow 6:00 PM
  useEffect(() => {
    const tmrw = new Date();
    tmrw.setDate(tmrw.getDate() + 1);
    tmrw.setHours(18, 0, 0, 0);
    const localIso = new Date(tmrw.getTime() - tmrw.getTimezoneOffset() * 60000)
      .toISOString()
      .slice(0, 16);
    setDueDate(localIso);
  }, []);

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!title.trim()) {
      setError('Title is required.');
      return;
    }
    if (!dueDate) {
      setError('Due date is required.');
      return;
    }
    setError('');
    setSubmitting(true);

    try {
      const payload = {
        title: title.trim(),
        description: description.trim(),
        due_date: new Date(dueDate).toISOString(),
      };
      if (targetType === 'tuition') {
        payload.tuition = targetId;
      } else {
        payload.student = targetId;
      }

      const res = await api.createHomework(payload);
      notify.success('Homework created successfully!');
      onCreated(res);
    } catch (err) {
      setError(err.message || 'Failed to create homework.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-slate-950/80 backdrop-blur-sm" onClick={onClose} />
      <div className="relative w-full max-w-lg rounded-2xl border border-slate-800 bg-slate-900 p-6 shadow-2xl space-y-5">
        <div className="flex items-center justify-between border-b border-slate-800 pb-3">
          <h3 className="text-lg font-bold text-slate-100 flex items-center gap-2">
            <Plus className="w-5 h-5 text-indigo-400" />
            Assign New Homework
          </h3>
          <button onClick={onClose} className="p-1 rounded-lg text-slate-400 hover:text-slate-200 hover:bg-slate-800">
            <X className="w-4 h-4" />
          </button>
        </div>

        {error && (
          <div className="px-3.5 py-2.5 rounded-xl bg-rose-500/10 border border-rose-500/25 text-rose-300 text-xs">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-xs font-bold text-slate-300 uppercase tracking-wider mb-1.5">
              Assignment Title *
            </label>
            <input
              type="text"
              required
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="e.g. Chapter 4 Numerical Problems"
              className="w-full px-3.5 py-2.5 rounded-xl bg-slate-800 border border-slate-700 text-sm text-slate-100 placeholder:text-slate-500 focus:outline-none focus:border-indigo-500"
            />
          </div>

          <div>
            <label className="block text-xs font-bold text-slate-300 uppercase tracking-wider mb-1.5">
              Instructions / Description
            </label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              rows={3}
              placeholder="Detailed instructions or exercises to solve..."
              className="w-full px-3.5 py-2.5 rounded-xl bg-slate-800 border border-slate-700 text-sm text-slate-100 placeholder:text-slate-500 focus:outline-none focus:border-indigo-500 resize-none"
            />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-bold text-slate-300 uppercase tracking-wider mb-1.5">
                Assign To
              </label>
              <div className="flex rounded-xl bg-slate-800 p-1 border border-slate-700 mb-2 text-xs font-semibold">
                <button
                  type="button"
                  onClick={() => {
                    setTargetType('tuition');
                    setTargetId(tuitions[0]?.id || '');
                  }}
                  className={`flex-1 py-1 rounded-lg transition ${
                    targetType === 'tuition' ? 'bg-indigo-600 text-white' : 'text-slate-400'
                  }`}
                >
                  Tuition Group
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setTargetType('student');
                    setTargetId(students[0]?.student_id || students[0]?.id || '');
                  }}
                  className={`flex-1 py-1 rounded-lg transition ${
                    targetType === 'student' ? 'bg-indigo-600 text-white' : 'text-slate-400'
                  }`}
                >
                  Individual Student
                </button>
              </div>

              {targetType === 'tuition' ? (
                <select
                  value={targetId}
                  onChange={(e) => setTargetId(e.target.value)}
                  className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
                >
                  {tuitions.map((t) => (
                    <option key={t.id} value={t.id}>
                      {t.title} ({t.subject || 'General'})
                    </option>
                  ))}
                </select>
              ) : (
                <select
                  value={targetId}
                  onChange={(e) => setTargetId(e.target.value)}
                  className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
                >
                  {students.map((s) => (
                    <option key={s.student_id || s.id} value={s.student_id || s.id}>
                      {s.full_name || s.name || s.username}
                    </option>
                  ))}
                </select>
              )}
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-300 uppercase tracking-wider mb-1.5">
                Due Date & Time *
              </label>
              <input
                type="datetime-local"
                required
                value={dueDate}
                onChange={(e) => setDueDate(e.target.value)}
                className="w-full px-3.5 py-2.5 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
              />
            </div>
          </div>

          <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-800">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2.5 rounded-xl text-xs font-semibold text-slate-400 hover:text-slate-200 hover:bg-slate-800 transition"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={submitting}
              className="px-5 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold flex items-center gap-1.5 shadow-md shadow-indigo-600/20 transition disabled:opacity-50"
            >
              {submitting ? <Loader2 className="w-4 h-4 animate-spin" /> : <Plus className="w-4 h-4" />}
              Assign Homework
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
