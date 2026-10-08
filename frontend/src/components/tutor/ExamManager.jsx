import React, { useState } from 'react';
import { FileText, Plus, Trophy, Pencil, Trash2, Eye, EyeOff, Users, Send, Timer, RefreshCw, ClipboardList, Copy } from 'lucide-react';
import Modal from '../common/Modal';
import StatusBadge from '../common/StatusBadge';
import LeaderboardModal from '../common/LeaderboardModal';
import ExamAuthoringModal from './ExamAuthoringModal';
import ExamSubmissionsModal from './ExamSubmissionsModal';
import { api } from '../../api/client';
import { notify } from '../../utils/toast';

const fmt = (value) =>
  new Date(value).toLocaleString(undefined, { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });

/**
 * Everything a tutor does with exams and assignments, in one place:
 * create, edit, publish a draft, delete, see who has turned in, grade,
 * show/hide results and open the leaderboard.
 *
 * `tuitionId` (optional) pins new exams to one tuition group.
 */
export default function ExamManager({ exams = [], loading = false, students = [], tuitionId = '', onReload, showGroup = true }) {
  const [authorOpen, setAuthorOpen] = useState(false);
  const [authorCategory, setAuthorCategory] = useState('EXAM');
  const [examToEdit, setExamToEdit] = useState(null);
  const [submissionsExamId, setSubmissionsExamId] = useState(null);
  const [leaderboardExam, setLeaderboardExam] = useState(null);
  const [busyId, setBusyId] = useState(null);
  // Copying an exam: pick which group the copy is for
  const [copySource, setCopySource] = useState(null);
  const [copyGroups, setCopyGroups] = useState([]);
  const [copyTarget, setCopyTarget] = useState('');
  const [copying, setCopying] = useState(false);

  const openCopy = async (exam) => {
    setCopySource(exam);
    setCopyTarget(exam.tuition_id || '');
    try {
      const data = await api.getTuitions();
      setCopyGroups(Array.isArray(data) ? data : data.results || []);
    } catch {
      setCopyGroups([]);
    }
  };

  const confirmCopy = async () => {
    if (!copySource) return;
    setCopying(true);
    try {
      const res = await api.duplicateExam(copySource.id, copyTarget && copyTarget !== copySource.tuition_id ? copyTarget : null);
      notify.success('Copied as a draft. Check the dates, then publish.');
      setCopySource(null);
      onReload?.();
      // Straight into the editor: the copy needs new dates before it can go out.
      setExamToEdit(res.exam);
      setAuthorCategory(res.exam.category);
      setAuthorOpen(true);
    } catch (err) {
      notify.error(err.message || 'Could not copy it.');
    } finally {
      setCopying(false);
    }
  };

  const openNew = (category) => {
    setExamToEdit(null);
    setAuthorCategory(category);
    setAuthorOpen(true);
  };

  const openEdit = async (exam) => {
    setBusyId(exam.id);
    try {
      setExamToEdit(await api.getExamDetail(exam.id));
      setAuthorCategory(exam.category);
      setAuthorOpen(true);
    } catch (err) {
      notify.error(`Could not open it for editing: ${err.message}`);
    } finally {
      setBusyId(null);
    }
  };

  const act = async (exam, fn, successMessage) => {
    setBusyId(exam.id);
    try {
      await fn();
      if (successMessage) notify.success(successMessage);
      onReload?.();
    } catch (err) {
      notify.error(err.message || 'Something went wrong.');
    } finally {
      setBusyId(null);
    }
  };

  const publish = (exam) =>
    act(exam, () => api.updateExam(exam.id, { is_published: true }), `"${exam.title}" is published. Students have been notified.`);

  // Publishing or hiding by hand always wins over the exam's automatic rule.
  const toggleResults = (exam) => {
    const out = exam.results_released;
    if (out && !window.confirm(`Hide the results of "${exam.title}" from students? They will see "Results pending" until you publish again.`)) return;
    act(
      exam,
      () => api.publishExamResults(exam.id, !out),
      out ? 'Results hidden from students.' : 'Results published. Students who submitted can see their marks and the answers.'
    );
  };

  const resultsLabel = (exam) => {
    if (exam.results_released) return { text: 'Results out', hint: 'Students who submitted can see marks and answers. Click to hide them.' };
    if (exam.result_publish_mode === 'IMMEDIATE') {
      return { text: 'Results on submit', hint: 'Each student sees their result as soon as they submit. Click to publish for everyone now.' };
    }
    if (exam.result_publish_mode === 'SCHEDULED') {
      const when = exam.results_release_time ? new Date(exam.results_release_time).toLocaleString(undefined, { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' }) : 'closing';
      return { text: `Results ${exam.publish_time ? '' : 'at close · '}${when}`, hint: 'Results come out automatically then. Click to publish them now.' };
    }
    return { text: 'Publish results', hint: 'Marks and answers are hidden from students. Click to publish them.' };
  };

  const remove = (exam) => {
    const warning = exam.submissions_count > 0
      ? `Delete "${exam.title}"? ${exam.submissions_count} student submission(s) and their marks will be deleted too. This cannot be undone.`
      : `Delete "${exam.title}"? This cannot be undone.`;
    if (!window.confirm(warning)) return;
    act(exam, () => api.deleteExam(exam.id), 'Deleted.');
  };

  return (
    <section className="rounded-2xl border border-slate-800 bg-slate-900/70 overflow-hidden">
      <header className="p-5 sm:p-6 flex flex-wrap items-center justify-between gap-3 border-b border-slate-800">
        <div>
          <h3 className="text-lg font-bold text-slate-100 flex items-center gap-2">
            <FileText className="w-5 h-5 text-indigo-400" />
            Exams & assignments
          </h3>
          <p className="text-xs text-slate-400 mt-0.5">
            Set work for a whole tuition group. Each student turns in their own answers.
          </p>
        </div>
        <div className="flex items-center gap-2">
          {onReload && (
            <button
              type="button"
              onClick={onReload}
              title="Refresh"
              aria-label="Refresh"
              className="p-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-400 hover:text-slate-200 border border-slate-700 transition"
            >
              <RefreshCw className="w-4 h-4" />
            </button>
          )}
          <button
            type="button"
            onClick={() => openNew('ASSIGNMENT')}
            className="px-3.5 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 border border-slate-700 text-slate-100 font-semibold text-xs flex items-center gap-1.5 transition"
          >
            <Plus className="w-4 h-4 text-indigo-300" /> Assignment
          </button>
          <button
            type="button"
            onClick={() => openNew('EXAM')}
            className="px-3.5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-xs flex items-center gap-1.5 transition"
          >
            <Plus className="w-4 h-4" /> Exam
          </button>
        </div>
      </header>

      {loading ? (
        <div className="p-6 space-y-3">
          {[1, 2, 3].map((i) => <div key={i} className="h-16 rounded-xl bg-slate-800/40 animate-pulse" />)}
        </div>
      ) : exams.length === 0 ? (
        <div className="p-10 text-center">
          <ClipboardList className="w-10 h-10 mx-auto text-slate-600 mb-3" />
          <p className="text-sm font-semibold text-slate-200">Nothing set yet</p>
          <p className="text-xs text-slate-400 mt-1 max-w-sm mx-auto">
            Create an exam with a time limit, or an assignment with a deadline. You can save a draft and publish it later.
          </p>
        </div>
      ) : (
        <ul className="divide-y divide-slate-800">
          {exams.map((exam) => {
            const isDraft = !exam.is_published;
            const isAssignment = exam.category === 'ASSIGNMENT';
            const assigned = exam.assigned_count ?? 0;
            const submitted = exam.submissions_count ?? 0;
            const graded = exam.graded_count ?? 0;
            const toGrade = Math.max(0, submitted - graded);
            const pct = assigned > 0 ? Math.min(100, Math.round((submitted / assigned) * 100)) : 0;
            const busy = busyId === exam.id;
            return (
              <li key={exam.id} className="p-4 sm:px-6 flex flex-col lg:flex-row lg:items-center gap-4">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <h4 className="text-sm font-bold text-slate-100 truncate">{exam.title}</h4>
                    <StatusBadge status={exam.dynamic_status} />
                    <span className="px-2 py-0.5 rounded-full text-[10px] font-bold border bg-indigo-50 text-indigo-700 border-indigo-200">
                      {isAssignment ? 'Assignment' : 'Exam'}
                    </span>
                  </div>
                  <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-xs text-slate-400">
                    {showGroup && <span>{exam.batch_name || exam.student_name}</span>}
                    <span>{Number(exam.total_marks)} marks</span>
                    {exam.mcq_count > 0 && <span>{exam.mcq_count} MCQs</span>}
                    {exam.duration_minutes && !isAssignment && (
                      <span className="flex items-center gap-1"><Timer className="w-3 h-3" />{exam.duration_minutes} min each</span>
                    )}
                    <span>{isAssignment ? 'Due' : `${fmt(exam.start_time)} →`} {fmt(exam.end_time)}</span>
                    {exam.late_submission_until && <span className="text-amber-300">late until {fmt(exam.late_submission_until)}</span>}
                  </div>
                </div>

                {/* Turn-in progress */}
                {!isDraft && (
                  <button
                    type="button"
                    onClick={() => setSubmissionsExamId(exam.id)}
                    className="lg:w-56 text-left rounded-xl bg-slate-800/40 hover:bg-slate-800 border border-slate-700/60 px-3.5 py-2.5 transition"
                    title="See who has turned in, and grade"
                  >
                    <div className="flex items-center justify-between text-xs">
                      <span className="flex items-center gap-1.5 text-slate-200 font-semibold">
                        <Users className="w-3.5 h-3.5 text-indigo-400" />
                        {submitted} of {assigned} turned in
                      </span>
                      {toGrade > 0 ? (
                        <span className="px-1.5 py-0.5 rounded-full bg-amber-400 text-slate-950 text-[10px] font-extrabold">{toGrade} to grade</span>
                      ) : submitted > 0 ? (
                        <span className="text-[10px] text-emerald-400 font-semibold">all graded</span>
                      ) : null}
                    </div>
                    <div className="mt-1.5 h-1.5 rounded-full bg-slate-700/60 overflow-hidden">
                      <div className="h-full bg-indigo-500 transition-all duration-500" style={{ width: `${pct}%` }} />
                    </div>
                  </button>
                )}

                {/* Actions */}
                <div className="flex items-center gap-1.5 flex-shrink-0">
                  {isDraft ? (
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => publish(exam)}
                      className="px-3 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold flex items-center gap-1.5 transition disabled:opacity-50"
                    >
                      <Send className="w-3.5 h-3.5" /> Publish
                    </button>
                  ) : (
                    <>
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => toggleResults(exam)}
                        title={resultsLabel(exam).hint}
                        className={`px-3 py-2 rounded-xl text-xs font-semibold flex items-center gap-1.5 border transition disabled:opacity-50 ${
                          exam.results_released
                            ? 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30'
                            : 'bg-slate-800 text-slate-300 border-slate-700 hover:text-white'
                        }`}
                      >
                        {exam.results_released ? <Eye className="w-3.5 h-3.5" /> : <EyeOff className="w-3.5 h-3.5" />}
                        {resultsLabel(exam).text}
                      </button>
                      <IconButton label="Leaderboard" onClick={() => setLeaderboardExam(exam)}><Trophy className="w-4 h-4 text-amber-300" /></IconButton>
                    </>
                  )}
                  <IconButton label="Copy (reuse for this or another group)" disabled={busy} onClick={() => openCopy(exam)}><Copy className="w-4 h-4" /></IconButton>
                  <IconButton label="Edit" disabled={busy} onClick={() => openEdit(exam)}><Pencil className="w-4 h-4" /></IconButton>
                  <IconButton label="Delete" disabled={busy} onClick={() => remove(exam)} danger><Trash2 className="w-4 h-4" /></IconButton>
                </div>
              </li>
            );
          })}
        </ul>
      )}

      <ExamAuthoringModal
        key={`author-${authorOpen ? 'open' : 'closed'}-${examToEdit?.id || 'new'}-${authorCategory}`}
        isOpen={authorOpen}
        onClose={() => setAuthorOpen(false)}
        students={students}
        initialBatchId={tuitionId}
        initialCategory={authorCategory}
        examToEdit={examToEdit}
        onExamCreated={() => onReload?.()}
      />

      {copySource && (
        <Modal isOpen onClose={() => setCopySource(null)} title={`Copy "${copySource.title}"`} maxWidth="max-w-md">
          <div className="space-y-4">
            <p className="text-sm text-slate-300">
              The questions, marking scheme, solutions and settings are copied into a new <strong>draft</strong>. Students' answers are not copied.
            </p>
            <div>
              <label htmlFor="copy-target" className="block text-sm font-medium text-slate-200 mb-1.5">Copy for which group?</label>
              <select
                id="copy-target"
                value={copyTarget}
                onChange={(e) => setCopyTarget(e.target.value)}
                className="w-full px-3 py-2.5 rounded-xl bg-slate-800 border border-slate-700 text-sm text-slate-100 focus:outline-none focus:border-indigo-500"
              >
                {!copySource.tuition_id && <option value="">Same student as the original</option>}
                {copyGroups.map((g) => (
                  <option key={g.id} value={g.id}>
                    {g.title}{g.id === copySource.tuition_id ? ' (same group)' : ''}
                  </option>
                ))}
              </select>
            </div>
            <div className="flex justify-end gap-2 pt-3 border-t border-slate-800">
              <button type="button" onClick={() => setCopySource(null)} className="px-4 py-2 rounded-xl text-sm font-medium text-slate-300 hover:text-white">
                Cancel
              </button>
              <button
                type="button"
                onClick={confirmCopy}
                disabled={copying}
                className="px-5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold transition disabled:opacity-60"
              >
                {copying ? 'Copying…' : 'Copy as draft'}
              </button>
            </div>
          </div>
        </Modal>
      )}

      <ExamSubmissionsModal
        isOpen={Boolean(submissionsExamId)}
        examId={submissionsExamId}
        onClose={() => setSubmissionsExamId(null)}
        onChanged={() => onReload?.()}
      />

      {leaderboardExam && (
        <LeaderboardModal
          isOpen
          onClose={() => setLeaderboardExam(null)}
          examId={leaderboardExam.id}
          examTitle={leaderboardExam.title}
        />
      )}
    </section>
  );
}

function IconButton({ label, onClick, children, disabled, danger }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      title={label}
      aria-label={label}
      className={`p-2 rounded-xl border border-slate-700 bg-slate-800 transition disabled:opacity-50 ${
        danger ? 'text-slate-400 hover:text-rose-300 hover:border-rose-500/40' : 'text-slate-300 hover:text-white hover:bg-slate-700'
      }`}
    >
      {children}
    </button>
  );
}
