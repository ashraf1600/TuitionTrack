import React, { useState, useEffect } from 'react';
import { notify } from '../../utils/toast';
import { useEditor, EditorContent } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import { Table, TableRow, TableHeader, TableCell } from '@tiptap/extension-table';
import { Image } from '@tiptap/extension-image';
import Modal from '../common/Modal';
import { api } from '../../api/client';
import { parseWrittenQuestions } from '../../utils/mcqParser';
import McqBuilder, { questionProblems } from './McqBuilder';
import { htmlWithLatex, pasteWithLatex } from '../../utils/clipboard';
import {
  Bold,
  Italic,
  Heading2,
  List,
  ListOrdered,
  Code,
  Table as TableIcon,
  ImageIcon,
  Sigma,
  AlertCircle,
  Calendar,
  Send,
  Eye,
  CheckCircle2,
  Plus,
  Trash2,
  FileText,
  ClipboardPaste,
  Users,
  User,
  Settings,
  KeyRound,
  Upload,
  Clock,
} from 'lucide-react';
import MathRenderer from '../common/MathRenderer';

function formatLocalInputDateTime(d) {
  const pad = (n) => String(n).padStart(2, '0');
  const year = d.getFullYear();
  const month = pad(d.getMonth() + 1);
  const day = pad(d.getDate());
  const hours = pad(d.getHours());
  const minutes = pad(d.getMinutes());
  return `${year}-${month}-${day}T${hours}:${minutes}`;
}

export default function ExamAuthoringModal({
  isOpen,
  onClose,
  students = [],
  onExamCreated,
  initialStudentId = '',
  initialBatchId = '',
  initialCategory = 'EXAM',
  examToEdit = null, // full exam detail -> the modal edits it instead of creating a new one
}) {
  const isEditing = Boolean(examToEdit?.id);
  const [activeTab, setActiveTab] = useState('questions'); // 'questions' | 'schedule' | 'solutions'
  const [category, setCategory] = useState(initialCategory || 'EXAM'); // 'EXAM' | 'ASSIGNMENT'
  const [examType, setExamType] = useState('HYBRID'); // 'HYBRID' | 'MCQ' | 'CQ'
  const [targetType, setTargetType] = useState(initialStudentId && !initialBatchId ? 'student' : 'batch'); // 'batch' (tuition group) | 'student'


  // Batches state
  const [batches, setBatches] = useState([]);
  const [loadingBatches, setLoadingBatches] = useState(false);
  const [studentId, setStudentId] = useState(initialStudentId);
  const [batchId, setBatchId] = useState(initialBatchId);

  // Exam Details
  const [title, setTitle] = useState('');
  const [totalMarks, setTotalMarks] = useState('100.00');
  const [durationMinutes, setDurationMinutes] = useState('');
  const [gracePeriod, setGracePeriod] = useState('5');
  const [lateUntil, setLateUntil] = useState('');
  const [shuffleQuestions, setShuffleQuestions] = useState(false);
  const [negativeMarks, setNegativeMarks] = useState('0');
  // Written part marked question by question: [{id?, label, marks}]
  const [writtenScheme, setWrittenScheme] = useState([]);
  // Pasting written questions into the editor
  const [writtenPasteOpen, setWrittenPasteOpen] = useState(false);
  const [writtenPaste, setWrittenPaste] = useState('');
  // The written paper as HTML, kept in step with the editor for the live preview.
  const [writtenHtml, setWrittenHtml] = useState('');

  // Dates
  const now = new Date();
  const defaultStart = formatLocalInputDateTime(new Date(now.getTime() + 10 * 60 * 1000));
  const defaultEnd = formatLocalInputDateTime(new Date(now.getTime() + 70 * 60 * 1000));
  const [startTime, setStartTime] = useState(defaultStart);
  const [endTime, setEndTime] = useState(defaultEnd);

  // MCQ questions state (empty by default - never ship sample content)
  const [mcqList, setMcqList] = useState([]);

  // Solutions & Keys
  const [solutionHtml, setSolutionHtml] = useState('');
  const [solutionMediaUrl, setSolutionMediaUrl] = useState('');
  // When students see results: 'IMMEDIATE' | 'CLOSE' | 'TIME' | 'MANUAL'
  // (CLOSE and TIME are both the server's SCHEDULED mode, without and with a time.)
  const [resultsMode, setResultsMode] = useState('MANUAL');
  const [resultsAt, setResultsAt] = useState('');
  const [uploadingSolution, setUploadingSolution] = useState(false);

  // Editor states
  const [previewMode, setPreviewMode] = useState(false);
  const [uploadingImage, setUploadingImage] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  // Load an existing exam into the form (edit mode)
  const loadExamIntoForm = (exam) => {
    setError('');
    setActiveTab('questions');
    setTitle(exam.title || '');
    setCategory(exam.category || 'EXAM');
    setExamType(exam.exam_type === 'MIXED' ? 'HYBRID' : exam.exam_type || 'HYBRID');
    setTargetType(exam.tuition_id ? 'batch' : 'student');
    setBatchId(exam.tuition_id || '');
    setStudentId(exam.student || '');
    setTotalMarks(String(exam.total_marks ?? '100'));
    setDurationMinutes(exam.duration_minutes ? String(exam.duration_minutes) : '');
    setGracePeriod(String(exam.grace_period_minutes ?? 5));
    setLateUntil(exam.late_submission_until ? formatLocalInputDateTime(new Date(exam.late_submission_until)) : '');
    setShuffleQuestions(Boolean(exam.shuffle_questions));
    setNegativeMarks(String(exam.negative_marks_per_wrong ?? '0'));
    setStartTime(formatLocalInputDateTime(new Date(exam.start_time)));
    setEndTime(formatLocalInputDateTime(new Date(exam.end_time)));
    setMcqList(Array.isArray(exam.mcq_data) ? exam.mcq_data.map((q) => ({ ...q, points: q.points ?? q.marks ?? 1 })) : []);
    setWrittenPaste('');
    setWrittenPasteOpen(false);
    setSolutionHtml(exam.solution_html || '');
    setSolutionMediaUrl(exam.solution_media_url || '');
    setWrittenScheme(Array.isArray(exam.written_scheme) ? exam.written_scheme.map((w) => ({ ...w, marks: String(w.marks) })) : []);
    if (exam.result_publish_mode === 'SCHEDULED') {
      setResultsMode(exam.publish_time ? 'TIME' : 'CLOSE');
    } else {
      setResultsMode(exam.result_publish_mode || 'MANUAL');
    }
    setResultsAt(exam.publish_time ? formatLocalInputDateTime(new Date(exam.publish_time)) : '');
    if (editor) {
      editor.commands.setContent(exam.exam_type === 'MCQ' ? '' : exam.content_html || '');
    }
  };

  // Reset helper to ensure clean state and no stale demo data
  const resetForm = () => {
    setTitle('');
    setError('');
    setActiveTab('questions');
    setExamType('HYBRID');
    setTotalMarks('100');
    setDurationMinutes('');
    setGracePeriod('5');
    setLateUntil('');
    setShuffleQuestions(false);
    setNegativeMarks('0');
    setWrittenScheme([]);
    setWrittenPaste('');
    setWrittenPasteOpen(false);
    setCategory(initialCategory || 'EXAM');
    const firstSid = initialStudentId || (students[0]?.id || students[0]?.student_id || '');
    setStudentId(firstSid);
    setBatchId(initialBatchId || '');
    setTargetType(initialStudentId && !initialBatchId ? 'student' : 'batch');
    setMcqList([]);
    setSolutionHtml('');
    setSolutionMediaUrl('');
    setResultsMode('MANUAL');
    setResultsAt('');
    const dNow = new Date();
    setStartTime(formatLocalInputDateTime(new Date(dNow.getTime() + 10 * 60 * 1000)));
    setEndTime(formatLocalInputDateTime(new Date(dNow.getTime() + 70 * 60 * 1000)));
    if (editor) {
      editor.commands.setContent('');
    }
  };

  // Sync category, target, and reset state whenever modal opens
  useEffect(() => {
    if (isOpen) {
      if (examToEdit?.id) {
        loadExamIntoForm(examToEdit);
      } else {
        resetForm();
      }
      loadBatches();
    }
  }, [isOpen, initialCategory, initialStudentId, initialBatchId, examToEdit?.id]);

  const loadBatches = async () => {
    try {
      setLoadingBatches(true);
      let list = [];
      try {
        const resTuitions = await api.getTuitions();
        list = Array.isArray(resTuitions) ? resTuitions : resTuitions.results || [];
      } catch (_) {
        const res = await api.getBatches();
        list = Array.isArray(res) ? res : res.results || [];
      }
      setBatches(list);
      if (list.length > 0 && !batchId) {
        setBatchId(list[0].id);
      }
    } catch (err) {
      console.error('Failed to load tuition batches:', err);
    } finally {
      setLoadingBatches(false);
    }
  };

  useEffect(() => {
    if (initialStudentId) {
      setStudentId(initialStudentId);
      if (!initialBatchId) setTargetType('student');
    } else if (students.length > 0 && !studentId) {
      setStudentId(students[0].id || students[0].student_id);
    }
  }, [initialStudentId, students]);

  useEffect(() => {
    if (initialBatchId) {
      setBatchId(initialBatchId);
      setTargetType('batch');
    }
  }, [initialBatchId]);

  // TipTap Editor instance for CQ (clean empty content by default)
  const editor = useEditor({
    extensions: [
      StarterKit,
      Table.configure({
        resizable: true,
      }),
      TableRow,
      TableHeader,
      TableCell,
      Image.configure({
        inline: true,
        allowBase64: true,
      }),
    ],
    content: '',
    editorProps: {
      attributes: {
        class: 'prose prose-invert max-w-none focus:outline-none min-h-[180px] p-4 text-slate-100',
      },
      // Text copied from a ChatGPT page carries each formula as drawn symbols plus hidden
      // LaTeX; keep only the LaTeX so it is typeset again instead of pasted twice as garble.
      transformPastedHTML: (html) => htmlWithLatex(html),
    },
    onTransaction: ({ editor: current }) => setWrittenHtml(current.getHTML()),
  });

  // LaTeX Formula prompt
  const insertFormula = () => {
    if (!editor) return;
    const formula = prompt('Enter LaTeX equation (e.g. \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}):');
    if (formula) {
      editor.chain().focus().insertContent(` $${formula}$ `).run();
    }
  };

  // Image upload
  const handleImageUpload = async (e) => {
    const file = e.target.files?.[0];
    if (!file || !editor) return;

    setUploadingImage(true);
    try {
      const formData = new FormData();
      formData.append('file', file);
      const res = await api.uploadMedia(formData);
      editor.chain().focus().setImage({ src: res.url, alt: res.filename }).run();
    } catch (err) {
      notify(`Image upload failed: ${err.message}`);
    } finally {
      setUploadingImage(false);
      e.target.value = '';
    }
  };

  // Solution attachment upload
  const handleSolutionUpload = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setUploadingSolution(true);
    try {
      const formData = new FormData();
      formData.append('file', file);
      const res = await api.uploadMedia(formData);
      setSolutionMediaUrl(res.url);
    } catch (err) {
      notify(`Solution upload failed: ${err.message}`);
    } finally {
      setUploadingSolution(false);
      e.target.value = '';
    }
  };

  const insertTable = () => {
    if (!editor) return;
    editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run();
  };

  // Pasted written questions go into the editor; marks (when given) fill the marking scheme.
  const insertWrittenQuestions = () => {
    const items = parseWrittenQuestions(writtenPaste);
    if (items.length === 0 || !editor) return;
    const esc = (text) => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const html = items
      .map((item) => `<p><strong>${esc(item.label)}.</strong> ${esc(item.text).replace(/\n/g, '<br>')}${item.marks ? ` <em>[${item.marks}]</em>` : ''}</p>`)
      .join('');
    editor.chain().focus('end').insertContent(html).run();
    if (items.every((item) => item.marks > 0)) {
      setWrittenScheme((prev) => [...prev, ...items.map((item) => ({ label: item.label, marks: String(item.marks) }))]);
    }
    notify.success(`Added ${items.length} written question${items.length === 1 ? '' : 's'}.`);
    setWrittenPaste('');
    setWrittenPasteOpen(false);
  };

  // Written marking scheme helpers
  const addSchemeRow = () => setWrittenScheme((prev) => [...prev, { label: `Q${prev.length + 1}`, marks: '5' }]);
  const updateSchemeRow = (index, field, value) =>
    setWrittenScheme((prev) => prev.map((row, i) => (i === index ? { ...row, [field]: value } : row)));
  const removeSchemeRow = (index) => setWrittenScheme((prev) => prev.filter((_, i) => i !== index));

  const mcqPointsTotal = examType !== 'CQ' ? mcqList.reduce((sum, q) => sum + (Number(q.points ?? q.marks) || 0), 0) : 0;
  const writtenPointsTotal = examType !== 'MCQ' ? writtenScheme.reduce((sum, w) => sum + (parseFloat(w.marks) || 0), 0) : 0;
  const allocatedTotal = Math.round((mcqPointsTotal + writtenPointsTotal) * 100) / 100;

  // The editor mounts a moment after the modal opens; fill it once it exists.
  useEffect(() => {
    if (isOpen && editor && examToEdit?.id && examToEdit.exam_type !== 'MCQ') {
      editor.commands.setContent(examToEdit.content_html || '');
    }
  }, [editor, isOpen, examToEdit?.id]);

  // Handle Form Submit. `publish` false saves a draft students cannot see.
  const handleSubmit = async (e, publish = true) => {
    e.preventDefault();
    setError('');

    if (!title.trim()) {
      setError('Please provide an exam title.');
      return;
    }

    if (new Date(endTime) <= new Date(startTime)) {
      setError('End time must be strictly after start time.');
      setActiveTab('schedule');
      return;
    }

    if (targetType === 'student' && !studentId) {
      setError('Please select a student.');
      return;
    }

    if (targetType === 'batch' && !batchId) {
      setError('Please select a tuition batch.');
      return;
    }

    if (examType !== 'MCQ' && writtenScheme.some((w) => !(parseFloat(w.marks) > 0))) {
      setError('Every written question in the marking scheme needs marks above 0.');
      setActiveTab('questions');
      return;
    }

    if (allocatedTotal > parseFloat(totalMarks)) {
      setError(`MCQ points (${mcqPointsTotal}) plus written marks (${writtenPointsTotal}) come to ${allocatedTotal}, which is more than the total of ${totalMarks}.`);
      setActiveTab('schedule');
      return;
    }

    if (lateUntil && new Date(lateUntil) <= new Date(endTime)) {
      setError('"Accept late work until" must be after the deadline.');
      setActiveTab('schedule');
      return;
    }

    if (publish && examType === 'MCQ' && mcqList.length === 0) {
      setError('Please add at least one MCQ question or choose CQ exam type.');
      setActiveTab('questions');
      return;
    }

    if (publish && examType !== 'CQ') {
      const unfinished = mcqList.findIndex((q) => questionProblems(q).length > 0);
      if (unfinished !== -1) {
        setError(`Question ${unfinished + 1} is not ready: ${questionProblems(mcqList[unfinished])[0].toLowerCase()}. You can still save it as a draft.`);
        setActiveTab('questions');
        return;
      }
    }

    if (resultsMode === 'TIME') {
      if (!resultsAt) {
        setError('Choose the date and time when results should be published.');
        setActiveTab('solutions');
        return;
      }
      if (new Date(resultsAt) <= new Date(startTime)) {
        setError('Results cannot be published before the exam starts.');
        setActiveTab('solutions');
        return;
      }
    }

    const htmlContent = editor?.getHTML() || '';
    if (publish && examType === 'CQ' && (!htmlContent || htmlContent.trim() === '<p></p>')) {
      setError('Written CQ section cannot be empty.');
      setActiveTab('questions');
      return;
    }

    setLoading(true);
    try {
      const parsedGrace = parseInt(gracePeriod, 10);
      const payload = {
        title,
        category,
        exam_type: examType,
        student_id: targetType === 'student' ? studentId : null,
        batch_id: targetType === 'batch' ? batchId : null,
        tuition_id: targetType === 'batch' ? batchId : null,
        content_html: examType === 'MCQ' ? '<p>Multiple Choice Examination</p>' : htmlContent,
        mcq_data: examType !== 'CQ' ? mcqList : [],
        written_scheme: examType !== 'MCQ'
          ? writtenScheme.map((w) => ({ id: w.id, label: (w.label || '').trim(), marks: parseFloat(w.marks) }))
          : [],
        solution_html: solutionHtml,
        solution_media_url: solutionMediaUrl,
        total_marks: parseFloat(totalMarks),
        start_time: new Date(startTime).toISOString(),
        end_time: new Date(endTime).toISOString(),
        duration_minutes: category === 'EXAM' ? parseInt(durationMinutes, 10) || null : null,
        grace_period_minutes: isNaN(parsedGrace) ? 5 : parsedGrace,
        late_submission_until: lateUntil ? new Date(lateUntil).toISOString() : null,
        shuffle_questions: examType !== 'CQ' && shuffleQuestions,
        negative_marks_per_wrong: examType !== 'CQ' ? parseFloat(negativeMarks) || 0 : 0,
        is_published: publish,
        result_publish_mode: resultsMode === 'CLOSE' || resultsMode === 'TIME' ? 'SCHEDULED' : resultsMode,
        publish_time: resultsMode === 'TIME' ? new Date(resultsAt).toISOString() : null,
      };

      if (isEditing) {
        await api.updateExam(examToEdit.id, payload);
      } else {
        await api.createExam(payload);
      }
      notify.success(
        isEditing
          ? (publish ? 'Changes saved.' : 'Saved as draft — students cannot see it.')
          : (publish ? 'Published. Students have been notified.' : 'Draft saved — publish it when you are ready.')
      );
      onExamCreated();
      resetForm();
      onClose();
    } catch (err) {
      setError(err.message || 'Failed to save.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={`${isEditing ? 'Edit' : 'New'} ${category === 'ASSIGNMENT' ? 'assignment' : 'exam'}`}
      maxWidth="max-w-4xl"
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3.5 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs flex items-center gap-2">
            <AlertCircle className="w-5 h-5 flex-shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {/* Assessment Category Selector: EXAM vs ASSIGNMENT */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 p-1.5 rounded-xl bg-slate-900 border border-slate-800 w-full sm:w-fit">
          <button
            type="button"
            onClick={() => setCategory('EXAM')}
            className={`px-3 py-1.5 rounded-lg text-xs font-bold transition flex items-center justify-center gap-1.5 ${
              category === 'EXAM'
                ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            <FileText className="w-3.5 h-3.5" />
            <span>Timed Examination</span>
          </button>
          <button
            type="button"
            onClick={() => setCategory('ASSIGNMENT')}
            className={`px-3 py-1.5 rounded-lg text-xs font-bold transition flex items-center justify-center gap-1.5 ${
              category === 'ASSIGNMENT'
                ? 'bg-purple-600 text-white shadow-md shadow-purple-600/30'
                : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            <Clock className="w-3.5 h-3.5" />
            <span>Assignment with Deadline</span>
          </button>
        </div>

        {/* Tab Navigation */}
        <div className="flex items-center justify-between border-b border-slate-800 pb-2 overflow-x-auto no-scrollbar">
          <div className="flex items-center gap-2 flex-shrink-0 whitespace-nowrap">
            <button
              type="button"
              onClick={() => setActiveTab('questions')}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold transition ${
                activeTab === 'questions'
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
              }`}
            >
              <FileText className="w-3.5 h-3.5" />
              <span>Questions & Content</span>
              {examType !== 'CQ' && mcqList.length > 0 && (
                <span className="px-1.5 py-0.2 rounded-full bg-slate-900 text-[10px] text-indigo-300 font-mono">
                  {mcqList.length} MCQs
                </span>
              )}
            </button>

            <button
              type="button"
              onClick={() => setActiveTab('schedule')}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold transition ${
                activeTab === 'schedule'
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
              }`}
            >
              <Calendar className="w-3.5 h-3.5" />
              <span>{category === 'ASSIGNMENT' ? 'Deadline & Settings' : 'Schedule & Settings'}</span>
            </button>

            <button
              type="button"
              onClick={() => setActiveTab('solutions')}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-bold transition ${
                activeTab === 'solutions'
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
              }`}
            >
              <KeyRound className="w-3.5 h-3.5" />
              <span>Results &amp; Solutions</span>
            </button>
          </div>
        </div>

        {/* Header Config (Title, Assignee & Type) */}
        <div className="grid grid-cols-1 sm:grid-cols-12 gap-3 p-3.5 rounded-xl bg-slate-800/40 border border-slate-700/60">
          <div className="sm:col-span-6">
            <label className="block text-[11px] font-bold text-slate-300 uppercase tracking-wider mb-1">
              {category === 'ASSIGNMENT' ? 'Assignment Title *' : 'Exam Title *'}
            </label>
            <input
              type="text"
              required
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder={
                category === 'ASSIGNMENT'
                  ? 'e.g. Physics Assignment #3 — Thermodynamics Problem Set'
                  : 'e.g. HSC Physics — Modern Physics & Mechanics'
              }
              className="w-full px-3 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-slate-100 text-xs focus:outline-none focus:border-indigo-500"
            />
          </div>


          <div className="sm:col-span-3">
            <label className="block text-[11px] font-bold text-slate-300 uppercase tracking-wider mb-1">
              Tuition group
            </label>
            {targetType === 'student' ? (
              <div>
                <select
                  value={studentId}
                  onChange={(e) => setStudentId(e.target.value)}
                  className="w-full px-2.5 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-slate-100 text-xs focus:outline-none focus:border-indigo-500"
                >
                  {students.map((st) => (
                    <option key={st.student_id} value={st.student_id}>
                      {st.full_name} (@{st.username})
                    </option>
                  ))}
                </select>
                <span className="block text-[10px] text-indigo-400 mt-1">
                  ✓ Assigned specifically to this 1-on-1 student.
                </span>
              </div>
            ) : (
              <div>
                <select
                  value={batchId}
                  onChange={(e) => setBatchId(e.target.value)}
                  className="w-full px-2.5 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-slate-100 text-xs focus:outline-none focus:border-indigo-500"
                >
                  {batches.length === 0 ? (
                    <option value="">Create a tuition group first</option>
                  ) : (
                    batches.map((b) => (
                      <option key={b.id} value={b.id}>
                        {b.title || b.name} ({b.enrolled_count ?? b.enrollments?.length ?? 0} students)
                      </option>
                    ))
                  )}
                </select>
                <span className="block text-[10px] text-emerald-400 mt-1">
                  Every student in this group gets it and submits their own answers.
                </span>
              </div>
            )}
          </div>

          <div className="sm:col-span-3">
            <label className="block text-[11px] font-bold text-slate-300 uppercase tracking-wider mb-1">
              Exam Format
            </label>
            <div className="flex gap-1">
              {['HYBRID', 'MCQ', 'CQ'].map((t) => (
                <button
                  key={t}
                  type="button"
                  onClick={() => setExamType(t)}
                  className={`flex-1 py-1.5 text-[10px] font-bold rounded-lg border transition ${
                    examType === t
                      ? 'bg-emerald-600/30 border-emerald-500 text-emerald-300 shadow'
                      : 'bg-slate-800 border-slate-700 text-slate-400 hover:text-slate-200'
                  }`}
                >
                  {t}
                </button>
              ))}
            </div>
            <span className="block text-[10px] text-slate-400 mt-1">
              {examType === 'HYBRID' ? 'MCQ + Written CQ' : examType === 'MCQ' ? 'Objective MCQs Only' : 'Written Paper Only'}
            </span>
          </div>
        </div>

        {/* TAB 1: Questions & Content */}
        {activeTab === 'questions' && (
          <div className="space-y-4">
            {/* MCQ SECTION */}
            {examType !== 'CQ' && <McqBuilder questions={mcqList} onChange={setMcqList} />}

            {/* WRITTEN CQ SECTION (TipTap Editor) */}
            {examType !== 'MCQ' && (
              <div className="border border-slate-700 rounded-xl overflow-hidden bg-slate-900/60">
                <div className="flex flex-wrap items-center justify-between gap-1 p-2 bg-slate-800/80 border-b border-slate-700">
                  <div className="flex flex-wrap items-center gap-1">
                    <button
                      type="button"
                      onClick={() => editor?.chain().focus().toggleBold().run()}
                      className={`p-1.5 rounded text-xs hover:bg-slate-700 ${editor?.isActive('bold') ? 'bg-indigo-600 text-white' : 'text-slate-300'}`}
                      title="Bold"
                    >
                      <Bold className="w-4 h-4" />
                    </button>
                    <button
                      type="button"
                      onClick={() => editor?.chain().focus().toggleItalic().run()}
                      className={`p-1.5 rounded text-xs hover:bg-slate-700 ${editor?.isActive('italic') ? 'bg-indigo-600 text-white' : 'text-slate-300'}`}
                      title="Italic"
                    >
                      <Italic className="w-4 h-4" />
                    </button>
                    <button
                      type="button"
                      onClick={() => editor?.chain().focus().toggleHeading({ level: 2 }).run()}
                      className={`p-1.5 rounded text-xs hover:bg-slate-700 ${editor?.isActive('heading', { level: 2 }) ? 'bg-indigo-600 text-white' : 'text-slate-300'}`}
                      title="Heading 2"
                    >
                      <Heading2 className="w-4 h-4" />
                    </button>
                    <button
                      type="button"
                      onClick={() => editor?.chain().focus().toggleBulletList().run()}
                      className={`p-1.5 rounded text-xs hover:bg-slate-700 ${editor?.isActive('bulletList') ? 'bg-indigo-600 text-white' : 'text-slate-300'}`}
                      title="Bullet List"
                    >
                      <List className="w-4 h-4" />
                    </button>
                    <button
                      type="button"
                      onClick={() => editor?.chain().focus().toggleOrderedList().run()}
                      className={`p-1.5 rounded text-xs hover:bg-slate-700 ${editor?.isActive('orderedList') ? 'bg-indigo-600 text-white' : 'text-slate-300'}`}
                      title="Ordered List"
                    >
                      <ListOrdered className="w-4 h-4" />
                    </button>
                    <button
                      type="button"
                      onClick={() => editor?.chain().focus().toggleCodeBlock().run()}
                      className={`p-1.5 rounded text-xs hover:bg-slate-700 ${editor?.isActive('codeBlock') ? 'bg-indigo-600 text-white' : 'text-slate-300'}`}
                      title="Code Block"
                    >
                      <Code className="w-4 h-4" />
                    </button>

                    <div className="w-px h-5 bg-slate-700 mx-1" />

                    <button
                      type="button"
                      onClick={insertTable}
                      className="p-1.5 rounded text-xs text-slate-300 hover:bg-slate-700 flex items-center gap-1"
                      title="Insert Table"
                    >
                      <TableIcon className="w-4 h-4" />
                      <span className="hidden sm:inline text-[11px]">Table</span>
                    </button>

                    <button
                      type="button"
                      onClick={insertFormula}
                      className="p-1.5 rounded text-xs text-indigo-300 hover:bg-indigo-950/60 border border-indigo-500/20 flex items-center gap-1"
                      title="Insert LaTeX Formula"
                    >
                      <Sigma className="w-4 h-4 text-indigo-400" />
                      <span className="text-[11px]">LaTeX</span>
                    </button>

                    <label className="p-1.5 rounded text-xs text-slate-300 hover:bg-slate-700 flex items-center gap-1 cursor-pointer">
                      <ImageIcon className="w-4 h-4 text-slate-400" />
                      <span className="hidden sm:inline text-[11px]">
                        {uploadingImage ? 'Uploading...' : 'Image'}
                      </span>
                      <input
                        type="file"
                        accept="image/*"
                        onChange={handleImageUpload}
                        className="hidden"
                      />
                    </label>
                  </div>

                  <div className="flex items-center gap-1.5">
                    <button
                      type="button"
                      onClick={() => setWrittenPasteOpen((v) => !v)}
                      className={`px-2.5 py-1 rounded text-xs font-semibold flex items-center gap-1 border transition ${
                        writtenPasteOpen
                          ? 'bg-indigo-600 text-white border-indigo-500'
                          : 'bg-slate-800 text-slate-300 border-slate-700 hover:bg-slate-700'
                      }`}
                    >
                      <ClipboardPaste className="w-3.5 h-3.5" />
                      <span>Paste questions</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => setPreviewMode(!previewMode)}
                      className={`px-2.5 py-1 rounded text-xs font-semibold flex items-center gap-1 border transition ${
                        previewMode
                          ? 'bg-indigo-600 text-white border-indigo-500'
                          : 'bg-slate-800 text-slate-300 border-slate-700 hover:bg-slate-700'
                      }`}
                    >
                      <Eye className="w-3.5 h-3.5" />
                      <span>{previewMode ? 'Back to editing' : 'Preview'}</span>
                    </button>
                  </div>
                </div>

                {writtenPasteOpen && (
                  <div className="p-3 bg-slate-800/60 border-b border-slate-700 space-y-2">
                    <p className="text-xs text-slate-300">
                      Paste written questions from ChatGPT or a document. Numbered questions are kept apart and maths stays as written.
                      If every question ends with its marks — <code>[10]</code> or <code>(5 marks)</code> — the marking scheme is filled in too.
                    </p>
                    <textarea
                      rows={6}
                      value={writtenPaste}
                      onChange={(e) => setWrittenPaste(e.target.value)}
                      onPaste={(e) => pasteWithLatex(e, writtenPaste, setWrittenPaste)}
                      aria-label="Paste written questions here"
                      spellCheck={false}
                      placeholder={'1. A particle moves with velocity \\(v(t) = 3t^2 - 4t\\). Find its acceleration at t = 2 s. [5]\n\n2. Evaluate $$\\int_0^\\pi \\sin^2 x\\,dx$$ (10 marks)'}
                      className="w-full p-3 rounded-lg bg-slate-900 border border-slate-700 text-slate-100 text-xs font-mono leading-relaxed focus:outline-none focus:border-indigo-500"
                    />
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-xs text-slate-400" aria-live="polite">
                        {writtenPaste.trim() ? `Found ${parseWrittenQuestions(writtenPaste).length} question(s)` : 'They are added at the end of the paper.'}
                      </span>
                      <button
                        type="button"
                        onClick={insertWrittenQuestions}
                        disabled={!writtenPaste.trim()}
                        className="px-3.5 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold transition disabled:opacity-50"
                      >
                        Add to the paper
                      </button>
                    </div>
                  </div>
                )}

                <div className="min-h-[200px] max-h-[320px] overflow-y-auto">
                  {previewMode ? (
                    <div className="p-4 bg-slate-950/50">
                      <MathRenderer content={editor?.getHTML() || ''} />
                    </div>
                  ) : (
                    <EditorContent editor={editor} />
                  )}
                </div>

                {/* Formulas are typed as LaTeX; show how they will look without leaving the editor. */}
                {!previewMode && /\$[^$]+\$|\\\(|\\\[/.test(writtenHtml) && (
                  <div className="border-t border-slate-700 bg-slate-950/50 p-4 max-h-[260px] overflow-y-auto">
                    <span className="block text-[10px] uppercase tracking-wider text-slate-500 mb-1">Students will see</span>
                    <MathRenderer content={writtenHtml} />
                  </div>
                )}
              </div>
            )}

            {/* Marking scheme for the written part */}
            {examType !== 'MCQ' && (
              <div className="rounded-xl border border-slate-700/80 bg-slate-900/60 p-4 space-y-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <h4 className="text-xs font-bold text-slate-200 uppercase tracking-wider">Marks per written question</h4>
                    <p className="text-[11px] text-slate-400 mt-0.5">
                      Optional. List each written question and what it is worth, and you can mark them one by one. Leave empty to give one overall written mark.
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={addSchemeRow}
                    className="px-2.5 py-1 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-semibold flex items-center gap-1 transition"
                  >
                    <Plus className="w-3.5 h-3.5" /> Add question
                  </button>
                </div>
                {writtenScheme.length > 0 && (
                  <ul className="space-y-2">
                    {writtenScheme.map((row, i) => (
                      <li key={row.id || i} className="flex items-center gap-2">
                        <input
                          type="text"
                          value={row.label}
                          maxLength={120}
                          onChange={(e) => updateSchemeRow(i, 'label', e.target.value)}
                          aria-label={`Written question ${i + 1} label`}
                          placeholder="e.g. Q1 (a) Derivation"
                          className="flex-1 px-3 py-1.5 rounded-lg bg-slate-900 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
                        />
                        <input
                          type="number"
                          min="0.25"
                          step="0.25"
                          value={row.marks}
                          onChange={(e) => updateSchemeRow(i, 'marks', e.target.value)}
                          aria-label={`Marks for written question ${i + 1}`}
                          className="w-20 px-2 py-1.5 rounded-lg bg-slate-900 border border-slate-700 text-xs text-emerald-400 font-bold text-center focus:outline-none focus:border-indigo-500"
                        />
                        <span className="text-[11px] text-slate-500">marks</span>
                        <button
                          type="button"
                          onClick={() => removeSchemeRow(i)}
                          aria-label={`Remove written question ${i + 1}`}
                          className="p-1.5 rounded text-slate-400 hover:text-rose-400 hover:bg-rose-500/10 transition"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}

            <p className={`text-[11px] ${allocatedTotal > parseFloat(totalMarks) ? 'text-rose-300 font-semibold' : 'text-slate-400'}`}>
              Marks set so far: {mcqPointsTotal} MCQ{examType !== 'MCQ' && writtenScheme.length > 0 ? ` + ${writtenPointsTotal} written` : ''} = {allocatedTotal} of {totalMarks} total.
            </p>
          </div>
        )}

        {/* TAB 2: Schedule & Settings */}
        {activeTab === 'schedule' && (
          <div className="space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 p-4 rounded-xl bg-slate-800/40 border border-slate-700/60">
              <div>
                <label className="block text-xs font-bold text-slate-300 mb-1">
                  Scheduled Start Time *
                </label>
                <input
                  type="datetime-local"
                  required
                  value={startTime}
                  onChange={(e) => setStartTime(e.target.value)}
                  className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
                />
                <span className="block text-[10px] text-slate-400 mt-1">
                  Students cannot start or view questions before this scheduled start.
                </span>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-300 mb-1">
                  {category === 'ASSIGNMENT' ? 'Submission Deadline *' : 'Scheduled End Time *'}
                </label>
                <input
                  type="datetime-local"
                  required
                  value={endTime}
                  onChange={(e) => setEndTime(e.target.value)}
                  className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
                />
                <span className="block text-[10px] text-slate-400 mt-1">
                  {category === 'ASSIGNMENT'
                    ? 'Students can turn in their work anytime before this deadline.'
                    : 'Submissions after this time will enter the grace period or be locked.'}
                </span>
              </div>


              <div>
                <label className="block text-xs font-bold text-slate-300 mb-1">
                  Total Exam Marks *
                </label>
                <input
                  type="number"
                  min="1"
                  required
                  value={totalMarks}
                  onChange={(e) => setTotalMarks(e.target.value)}
                  className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-emerald-400 font-bold focus:outline-none focus:border-indigo-500"
                />
              </div>

              {category === 'EXAM' && (
                <div>
                  <label className="block text-xs font-bold text-slate-300 mb-1">
                    Time limit per student (minutes)
                  </label>
                  <input
                    type="number"
                    min="1"
                    value={durationMinutes}
                    onChange={(e) => setDurationMinutes(e.target.value)}
                    placeholder="No limit — open until the end time"
                    className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
                  />
                  <span className="block text-[10px] text-slate-400 mt-1">
                    Each student's clock starts when they open the exam and never runs past the end time. Leave empty for no limit.
                  </span>
                </div>
              )}

              <div>
                <label className="block text-xs font-bold text-slate-300 mb-1">
                  Accept late work until
                </label>
                <input
                  type="datetime-local"
                  value={lateUntil}
                  onChange={(e) => setLateUntil(e.target.value)}
                  className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
                />
                <span className="block text-[10px] text-slate-400 mt-1">
                  Optional. After the deadline, students can still turn in until this time and are marked "Late".
                </span>
              </div>

              {examType !== 'CQ' && (
                <>
                  <div>
                    <label className="block text-xs font-bold text-slate-300 mb-1">
                      Marks deducted per wrong MCQ
                    </label>
                    <input
                      type="number"
                      min="0"
                      step="0.25"
                      value={negativeMarks}
                      onChange={(e) => setNegativeMarks(e.target.value)}
                      className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
                    />
                    <span className="block text-[10px] text-slate-400 mt-1">
                      0 means no negative marking. Unanswered questions never lose marks.
                    </span>
                  </div>

                  <label className="flex items-start gap-2.5 p-3 rounded-xl bg-slate-900/60 border border-slate-700/60 cursor-pointer self-start">
                    <input
                      type="checkbox"
                      checked={shuffleQuestions}
                      onChange={(e) => setShuffleQuestions(e.target.checked)}
                      className="w-4 h-4 mt-0.5 accent-indigo-600 rounded"
                    />
                    <span>
                      <span className="text-xs font-bold text-slate-200 block">Shuffle MCQ order</span>
                      <span className="text-[10px] text-slate-400">Each student sees the questions in a different order.</span>
                    </span>
                  </label>
                </>
              )}

              <div>
                <label className="block text-xs font-bold text-slate-300 mb-1">
                  Grace Period (Minutes)
                </label>
                <input
                  type="number"
                  min="0"
                  value={gracePeriod}
                  onChange={(e) => setGracePeriod(e.target.value)}
                  className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-indigo-300 font-bold focus:outline-none focus:border-indigo-500"
                />
                <span className="block text-[10px] text-slate-400 mt-1">
                  Late submissions during grace window are flagged as "Delayed".
                </span>
              </div>
            </div>
          </div>
        )}

        {/* TAB 3: Results & Solutions */}
        {activeTab === 'solutions' && (
          <div className="space-y-4">
            <div className="p-4 rounded-xl bg-slate-800/40 border border-slate-700/60 space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-300 mb-1">
                  Official Model Solution / Step-by-Step Derivations (Rich Text / LaTeX)
                </label>
                <textarea
                  rows={4}
                  value={solutionHtml}
                  onChange={(e) => setSolutionHtml(e.target.value)}
                  placeholder="e.g. Solution 1: Taking derivatives... $$f'(x) = 2x \\sin(x) + x^2 \\cos(x)$$"
                  className="w-full p-3 rounded-xl bg-slate-900 border border-slate-700 text-xs text-slate-100 font-mono focus:outline-none focus:border-indigo-500"
                />
                <span className="block text-[10px] text-slate-400 mt-1">
                  Students will be able to read these explanations once results are published.
                </span>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2 border-t border-slate-800">
                <div>
                  <label className="block text-xs font-bold text-slate-300 mb-1">
                    Upload Solution PDF or Image Answer Sheet
                  </label>
                  <label className="px-4 py-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 border border-dashed border-slate-600 text-slate-300 text-xs font-semibold flex items-center justify-center gap-2 cursor-pointer transition">
                    <Upload className="w-4 h-4 text-emerald-400" />
                    <span>{uploadingSolution ? 'Uploading...' : 'Choose File / Photo'}</span>
                    <input
                      type="file"
                      accept="image/*,application/pdf"
                      onChange={handleSolutionUpload}
                      className="hidden"
                    />
                  </label>
                  {solutionMediaUrl && (
                    <div className="mt-2 text-[11px] text-emerald-400 font-mono truncate">
                      ✓ Attached: {solutionMediaUrl}
                    </div>
                  )}
                </div>

              </div>
            </div>

            <fieldset className="p-4 rounded-xl bg-slate-800/40 border border-slate-700/60 space-y-2.5">
              <legend className="px-1 text-xs font-bold text-slate-200">When do students see their results?</legend>
              <p className="text-[11px] text-slate-400">
                Until then a student who has submitted sees only “Results pending” — no marks, no correct answers, no solutions.
              </p>
              {[
                {
                  value: 'IMMEDIATE',
                  label: 'As soon as each student submits',
                  hint: targetType === 'batch'
                    ? 'Marks and correct answers appear the moment they hand in. In a group, someone who finishes early could pass the answers on.'
                    : 'Marks and correct answers appear the moment they hand in.',
                },
                { value: 'CLOSE', label: 'When the exam closes', hint: 'After the deadline and any late-work time, when nobody can still be answering.' },
                { value: 'TIME', label: 'At a time I choose', hint: 'Results come out automatically at the date and time you set.' },
                { value: 'MANUAL', label: 'When I publish them', hint: 'Results stay hidden until you press “Publish results” on the exam.' },
              ].map((option) => (
                <label
                  key={option.value}
                  className={`flex items-start gap-2.5 p-3 rounded-xl border cursor-pointer transition ${
                    resultsMode === option.value ? 'bg-indigo-500/10 border-indigo-500/60' : 'bg-slate-900/60 border-slate-700/60 hover:border-slate-500'
                  }`}
                >
                  <input
                    type="radio"
                    name="results-mode"
                    value={option.value}
                    checked={resultsMode === option.value}
                    onChange={() => setResultsMode(option.value)}
                    className="mt-0.5 w-4 h-4 accent-indigo-600"
                  />
                  <span className="flex-1">
                    <span className="text-xs font-bold text-slate-100 block">{option.label}</span>
                    <span className="text-[11px] text-slate-400 block">{option.hint}</span>
                    {option.value === 'TIME' && resultsMode === 'TIME' && (
                      <input
                        type="datetime-local"
                        value={resultsAt}
                        min={startTime}
                        onChange={(e) => setResultsAt(e.target.value)}
                        aria-label="Publish results at"
                        className="mt-2 px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
                      />
                    )}
                  </span>
                </label>
              ))}
              {examType !== 'MCQ' && (
                <p className="text-[11px] text-slate-400">
                  MCQs are marked automatically. A written part shows as “awaiting marking” until you have marked it.
                </p>
              )}
            </fieldset>
          </div>
        )}

        {/* Action Buttons */}
        <div className="pt-3 flex items-center justify-between border-t border-slate-800">
          <p className="text-[11px] text-slate-400 hidden sm:block">
            Students are emailed when it is published. Drafts stay private.
          </p>

          <div className="flex items-center gap-3 ml-auto">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl border border-slate-700 text-slate-300 text-xs hover:bg-slate-800 transition"
            >
              Cancel
            </button>
            {(!isEditing || !examToEdit.is_published) && (
              <button
                type="button"
                disabled={loading}
                onClick={(e) => handleSubmit(e, false)}
                className="px-4 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 border border-slate-700 text-slate-100 font-semibold text-xs transition disabled:opacity-50"
              >
                Save as draft
              </button>
            )}
            <button
              type="submit"
              disabled={loading}
              className="px-5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs shadow-lg shadow-indigo-600/30 flex items-center gap-2 transition disabled:opacity-50"
            >
              {loading ? (
                <>
                  <div className="w-4 h-4 rounded-full border-2 border-white/30 border-t-white animate-spin" />
                  <span>Saving…</span>
                </>
              ) : (
                <>
                  <Send className="w-4 h-4" />
                  <span>{isEditing && examToEdit.is_published ? 'Save changes' : 'Publish'}</span>
                </>
              )}
            </button>
          </div>
        </div>
      </form>
    </Modal>
  );
}
