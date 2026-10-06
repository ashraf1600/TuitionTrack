import React, { useState, useEffect } from 'react';
import { useEditor, EditorContent } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import { Table, TableRow, TableHeader, TableCell } from '@tiptap/extension-table';
import { Image } from '@tiptap/extension-image';
import Modal from '../common/Modal';
import { api } from '../../api/client';
import { parseRawMCQText } from '../../utils/mcqParser';
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
  Sparkles,
  ClipboardPaste,
  HelpCircle,
  Users,
  User,
  Settings,
  KeyRound,
  Upload,
  Clock,
} from 'lucide-react';
import MathRenderer from '../common/MathRenderer';

export default function ExamAuthoringModal({
  isOpen,
  onClose,
  students = [],
  onExamCreated,
  initialStudentId = '',
  initialBatchId = '',
  initialCategory = 'EXAM',
}) {
  const [activeTab, setActiveTab] = useState('questions'); // 'questions' | 'schedule' | 'solutions'
  const [category, setCategory] = useState(initialCategory || 'EXAM'); // 'EXAM' | 'ASSIGNMENT'
  const [examType, setExamType] = useState('HYBRID'); // 'HYBRID' | 'MCQ' | 'CQ'
  const [targetType, setTargetType] = useState(initialBatchId ? 'batch' : 'student'); // 'student' | 'batch'


  // Batches state
  const [batches, setBatches] = useState([]);
  const [loadingBatches, setLoadingBatches] = useState(false);
  const [studentId, setStudentId] = useState(initialStudentId);
  const [batchId, setBatchId] = useState(initialBatchId);

  // Exam Details
  const [title, setTitle] = useState('');
  const [totalMarks, setTotalMarks] = useState('100.00');
  const [durationMinutes, setDurationMinutes] = useState('60');
  const [gracePeriod, setGracePeriod] = useState('5');

  // Dates
  const now = new Date();
  const defaultStart = new Date(now.getTime() + 10 * 60 * 1000).toISOString().slice(0, 16);
  const defaultEnd = new Date(now.getTime() + 70 * 60 * 1000).toISOString().slice(0, 16);
  const [startTime, setStartTime] = useState(defaultStart);
  const [endTime, setEndTime] = useState(defaultEnd);

  // MCQ questions state
  const [mcqList, setMcqList] = useState([
    {
      id: 'mcq-1',
      question: 'What is the SI unit of gravitational acceleration $g$?',
      options: ['m/s', 'm/s²', 'N/kg²', 'J/s'],
      correct_answer: 1,
      explanation: 'Acceleration has units of length per time squared (m/s²).',
      points: 1,
    },
  ]);
  const [rawMCQInput, setRawMCQInput] = useState('');
  const [showPasteModal, setShowPasteModal] = useState(false);

  // Solutions & Keys
  const [solutionHtml, setSolutionHtml] = useState('');
  const [solutionMediaUrl, setSolutionMediaUrl] = useState('');
  const [isResultsPublished, setIsResultsPublished] = useState(false);
  const [uploadingSolution, setUploadingSolution] = useState(false);

  // Editor states
  const [previewMode, setPreviewMode] = useState(false);
  const [uploadingImage, setUploadingImage] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  // Load batches
  useEffect(() => {
    if (isOpen) {
      loadBatches();
    }
  }, [isOpen]);

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
      setTargetType('student');
    } else if (students.length > 0 && !studentId) {
      setStudentId(students[0].student_id);
    }
  }, [initialStudentId, students]);

  useEffect(() => {
    if (initialBatchId) {
      setBatchId(initialBatchId);
      setTargetType('batch');
    }
  }, [initialBatchId]);

  // TipTap Editor instance for CQ
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
    content: `<h2>Physics & Math Assessment (Written CQ Section)</h2><p>Solve the following analytical problems step by step with clear derivations:</p><table><thead><tr><th>Question</th><th>Marks</th></tr></thead><tbody><tr><td>1. A particle moves with velocity $v(t) = 3t^2 - 4t$. Find acceleration at $t = 2$s.</td><td>10</td></tr><tr><td>2. Evaluate the definite integral: $$\\int_0^\\pi \\sin^2(x) dx$$</td><td>15</td></tr></tbody></table>`,
    editorProps: {
      attributes: {
        class: 'prose prose-invert max-w-none focus:outline-none min-h-[180px] p-4 text-slate-100',
      },
    },
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
      alert(`Image upload failed: ${err.message}`);
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
      alert(`Solution upload failed: ${err.message}`);
    } finally {
      setUploadingSolution(false);
      e.target.value = '';
    }
  };

  const insertTable = () => {
    if (!editor) return;
    editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run();
  };

  // MCQ operations
  const handleAddMCQ = () => {
    setMcqList((prev) => [
      ...prev,
      {
        id: `mcq-${Date.now()}`,
        question: 'Enter question text here...',
        options: ['Option A', 'Option B', 'Option C', 'Option D'],
        correct_answer: 0,
        explanation: '',
        points: 1,
      },
    ]);
  };

  const handleUpdateMCQ = (index, field, value) => {
    setMcqList((prev) => {
      const copy = [...prev];
      copy[index] = { ...copy[index], [field]: value };
      return copy;
    });
  };

  const handleUpdateMCQOption = (qIndex, optIndex, value) => {
    setMcqList((prev) => {
      const copy = [...prev];
      const opts = [...copy[qIndex].options];
      opts[optIndex] = value;
      copy[qIndex] = { ...copy[qIndex], options: opts };
      return copy;
    });
  };

  const handleRemoveMCQ = (index) => {
    setMcqList((prev) => prev.filter((_, i) => i !== index));
  };

  // Smart Parse raw text (ChatGPT / pasted)
  const handleSmartParse = () => {
    if (!rawMCQInput.trim()) return;
    const parsed = parseRawMCQText(rawMCQInput);
    if (parsed.length === 0) {
      alert('Could not parse any MCQs. Please verify the format (Numbered questions with A, B, C, D options).');
      return;
    }
    setMcqList((prev) => [...prev, ...parsed]);
    setRawMCQInput('');
    setShowPasteModal(false);
  };

  // Handle Form Submit
  const handleSubmit = async (e) => {
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

    if (examType === 'MCQ' && mcqList.length === 0) {
      setError('Please add at least one MCQ question or choose CQ exam type.');
      setActiveTab('questions');
      return;
    }

    const htmlContent = editor?.getHTML() || '';
    if (examType === 'CQ' && (!htmlContent || htmlContent.trim() === '<p></p>')) {
      setError('Written CQ section cannot be empty.');
      setActiveTab('questions');
      return;
    }

    setLoading(true);
    try {
      const payload = {
        title,
        category,
        exam_type: examType,
        student_id: targetType === 'student' ? studentId : null,
        batch_id: targetType === 'batch' ? batchId : null,
        tuition_id: targetType === 'batch' ? batchId : null,
        content_html: examType === 'MCQ' ? '<p>Multiple Choice Examination</p>' : htmlContent,
        mcq_data: examType !== 'CQ' ? mcqList : [],
        solution_html: solutionHtml,
        solution_media_url: solutionMediaUrl,
        total_marks: parseFloat(totalMarks),
        start_time: new Date(startTime).toISOString(),
        end_time: new Date(endTime).toISOString(),
        duration_minutes: parseInt(durationMinutes) || null,
        grace_period_minutes: parseInt(gracePeriod) || 5,
        is_published: true,
        is_results_published: isResultsPublished,
      };


      await api.createExam(payload);
      onExamCreated();
      onClose();
    } catch (err) {
      setError(err.message || 'Failed to schedule exam.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={category === 'ASSIGNMENT' ? 'Create & Schedule Assignment' : 'Author, Schedule & Grade Exam'}
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
        <div className="flex items-center gap-2 p-1.5 rounded-xl bg-slate-900 border border-slate-800 w-fit">
          <button
            type="button"
            onClick={() => setCategory('EXAM')}
            className={`px-3 py-1.5 rounded-lg text-xs font-bold transition flex items-center gap-1.5 ${
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
            className={`px-3 py-1.5 rounded-lg text-xs font-bold transition flex items-center gap-1.5 ${
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
        <div className="flex items-center justify-between border-b border-slate-800 pb-2">
          <div className="flex items-center gap-2">
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
              <span>Answer Keys & Solutions</span>
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
              Assign Target
            </label>
            <div className="flex gap-1 mb-1">
              <button
                type="button"
                onClick={() => setTargetType('student')}
                className={`flex-1 py-1 text-[10px] font-bold rounded ${
                  targetType === 'student' ? 'bg-indigo-600 text-white' : 'bg-slate-800 text-slate-400'
                }`}
              >
                1-on-1 Student
              </button>
              <button
                type="button"
                onClick={() => setTargetType('batch')}
                className={`flex-1 py-1 text-[10px] font-bold rounded ${
                  targetType === 'batch' ? 'bg-indigo-600 text-white' : 'bg-slate-800 text-slate-400'
                }`}
              >
                Tuition Batch
              </button>
            </div>

            {targetType === 'student' ? (
              <select
                value={studentId}
                onChange={(e) => setStudentId(e.target.value)}
                className="w-full px-2 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-slate-100 text-xs"
              >
                {students.map((st) => (
                  <option key={st.student_id} value={st.student_id}>
                    {st.full_name} (@{st.username})
                  </option>
                ))}
              </select>
            ) : (
              <select
                value={batchId}
                onChange={(e) => setBatchId(e.target.value)}
                className="w-full px-2 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-slate-100 text-xs"
              >
                {batches.length === 0 ? (
                  <option value="">No batches created yet</option>
                ) : (
                  batches.map((b) => (
                    <option key={b.id} value={b.id}>
                      {b.title || b.name} ({b.student_count || b.enrollment_count || b.enrollments?.length || 0} students)
                    </option>
                  ))
                )}
              </select>
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
            {examType !== 'CQ' && (
              <div className="rounded-xl border border-slate-700/80 bg-slate-900/60 p-4 space-y-4">
                <div className="flex flex-wrap items-center justify-between gap-2 border-b border-slate-800 pb-3">
                  <div className="flex items-center gap-2">
                    <Sparkles className="w-4 h-4 text-amber-400" />
                    <h4 className="text-xs font-bold text-slate-200 uppercase tracking-wider">
                      Multiple Choice Questions (MCQ) — {mcqList.length} Items
                    </h4>
                  </div>

                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => setShowPasteModal(true)}
                      className="px-2.5 py-1 rounded-lg bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-300 border border-indigo-500/40 text-xs font-semibold flex items-center gap-1.5 transition"
                    >
                      <ClipboardPaste className="w-3.5 h-3.5" />
                      <span>Paste from ChatGPT / Text</span>
                    </button>

                    <button
                      type="button"
                      onClick={handleAddMCQ}
                      className="px-2.5 py-1 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-semibold flex items-center gap-1 shadow transition"
                    >
                      <Plus className="w-3.5 h-3.5" />
                      <span>Add Question</span>
                    </button>
                  </div>
                </div>

                {/* MCQ Paste helper container */}
                {showPasteModal && (
                  <div className="p-3.5 rounded-xl bg-slate-800/80 border border-indigo-500/40 space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-indigo-300 flex items-center gap-1.5">
                        <ClipboardPaste className="w-4 h-4" />
                        Paste Raw Questions (Any format with 4 options A, B, C, D)
                      </span>
                      <button
                        type="button"
                        onClick={() => setShowPasteModal(false)}
                        className="text-slate-400 hover:text-slate-200 text-xs"
                      >
                        ✕
                      </button>
                    </div>
                    <textarea
                      rows={5}
                      value={rawMCQInput}
                      onChange={(e) => setRawMCQInput(e.target.value)}
                      placeholder={`1. What is the unit of power?\nA) Joule\nB) Watt\nC) Newton\nD) Pascal\nAnswer: B\nExplanation: Watt is the SI unit of power.`}
                      className="w-full p-2.5 rounded-lg bg-slate-900 border border-slate-700 text-slate-100 text-xs font-mono focus:outline-none focus:border-indigo-500"
                    />
                    <div className="flex items-center justify-between">
                      <span className="text-[10px] text-slate-400">
                        Supports questions with LaTeX ($E = mc^2$), keys like <code>Answer: C</code> or <code>Ans: 3</code>.
                      </span>
                      <button
                        type="button"
                        onClick={handleSmartParse}
                        className="px-3 py-1.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold shadow flex items-center gap-1"
                      >
                        <Sparkles className="w-3.5 h-3.5" />
                        <span>Parse & Auto-Add</span>
                      </button>
                    </div>
                  </div>
                )}

                {/* List of MCQ cards */}
                <div className="space-y-3 max-h-[360px] overflow-y-auto pr-1">
                  {mcqList.map((q, qIdx) => (
                    <div
                      key={q.id || qIdx}
                      className="p-3.5 rounded-xl bg-slate-800/40 border border-slate-700/60 space-y-2.5 relative group"
                    >
                      <div className="flex items-center justify-between gap-2">
                        <div className="flex items-center gap-2 flex-1">
                          <span className="w-6 h-6 rounded-full bg-indigo-600/30 text-indigo-300 border border-indigo-500/30 flex items-center justify-center font-bold text-xs flex-shrink-0">
                            {qIdx + 1}
                          </span>
                          <input
                            type="text"
                            value={q.question}
                            onChange={(e) => handleUpdateMCQ(qIdx, 'question', e.target.value)}
                            placeholder="Question Prompt (supports LaTeX like $x^2$)..."
                            className="flex-1 px-2.5 py-1 rounded bg-slate-900 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
                          />
                        </div>

                        <div className="flex items-center gap-2">
                          <span className="text-[10px] text-slate-400 font-mono">
                            Pts:
                            <input
                              type="number"
                              min="0.5"
                              step="0.5"
                              value={q.points || 1}
                              onChange={(e) => handleUpdateMCQ(qIdx, 'points', parseFloat(e.target.value) || 1)}
                              className="w-10 ml-1 px-1 py-0.5 rounded bg-slate-900 border border-slate-700 text-center text-xs text-emerald-400 font-bold"
                            />
                          </span>
                          <button
                            type="button"
                            onClick={() => handleRemoveMCQ(qIdx)}
                            className="p-1 rounded text-slate-400 hover:text-rose-400 hover:bg-rose-500/10 transition"
                            title="Delete question"
                          >
                            <Trash2 className="w-3.5 h-3.5" />
                          </button>
                        </div>
                      </div>

                      {/* 4 Options Grid */}
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 pl-8">
                        {['A', 'B', 'C', 'D'].map((letter, optIdx) => (
                          <div
                            key={optIdx}
                            className={`flex items-center gap-2 p-1.5 rounded-lg border transition ${
                              q.correct_answer === optIdx
                                ? 'bg-emerald-950/40 border-emerald-500/60 text-emerald-300'
                                : 'bg-slate-900/60 border-slate-700/60 text-slate-300'
                            }`}
                          >
                            <label className="flex items-center cursor-pointer">
                              <input
                                type="radio"
                                name={`correct-${qIdx}`}
                                checked={q.correct_answer === optIdx}
                                onChange={() => handleUpdateMCQ(qIdx, 'correct_answer', optIdx)}
                                className="accent-emerald-500"
                              />
                              <span className="ml-1 text-[11px] font-bold uppercase">{letter}</span>
                            </label>
                            <input
                              type="text"
                              value={q.options[optIdx] || ''}
                              onChange={(e) => handleUpdateMCQOption(qIdx, optIdx, e.target.value)}
                              placeholder={`Option ${letter}`}
                              className="flex-1 px-2 py-0.5 rounded bg-transparent text-xs text-slate-100 focus:outline-none"
                            />
                          </div>
                        ))}
                      </div>

                      {/* Explanation note */}
                      <div className="pl-8 flex items-center gap-2">
                        <HelpCircle className="w-3.5 h-3.5 text-slate-500 flex-shrink-0" />
                        <input
                          type="text"
                          value={q.explanation || ''}
                          onChange={(e) => handleUpdateMCQ(qIdx, 'explanation', e.target.value)}
                          placeholder="Explanation / Solution hint for student after grading (optional)..."
                          className="flex-1 px-2 py-0.5 rounded bg-slate-900/40 border border-slate-800 text-[11px] text-slate-400 focus:outline-none focus:border-indigo-500"
                        />
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

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
                    <span>{previewMode ? 'Edit Mode' : 'KaTeX Preview'}</span>
                  </button>
                </div>

                <div className="min-h-[200px] max-h-[320px] overflow-y-auto">
                  {previewMode ? (
                    <div className="p-4 bg-slate-950/50">
                      <MathRenderer content={editor?.getHTML() || ''} />
                    </div>
                  ) : (
                    <EditorContent editor={editor} />
                  )}
                </div>
              </div>
            )}
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

              <div>
                <label className="block text-xs font-bold text-slate-300 mb-1">
                  Allowed Duration (Minutes)
                </label>
                <input
                  type="number"
                  min="5"
                  value={durationMinutes}
                  onChange={(e) => setDurationMinutes(e.target.value)}
                  className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
                />
              </div>

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

        {/* TAB 3: Answer Keys & Solutions */}
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

                <div className="flex flex-col justify-center">
                  <label className="flex items-center gap-2 cursor-pointer p-3 rounded-xl bg-slate-900/60 border border-slate-700/60">
                    <input
                      type="checkbox"
                      checked={isResultsPublished}
                      onChange={(e) => setIsResultsPublished(e.target.checked)}
                      className="w-4 h-4 accent-indigo-600 rounded"
                    />
                    <div>
                      <span className="text-xs font-bold text-slate-200 block">
                        Publish Results & Leaderboard Immediately
                      </span>
                      <span className="text-[10px] text-slate-400">
                        Allow students to see model solutions and batch rankings upon submission.
                      </span>
                    </div>
                  </label>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Action Buttons */}
        <div className="pt-3 flex items-center justify-between border-t border-slate-800">
          <p className="text-[11px] text-slate-400 hidden sm:block">
            💡 Scheduled exam notifications are dispatched automatically to all students.
          </p>

          <div className="flex items-center gap-3 ml-auto">
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
              className="px-5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs shadow-lg shadow-indigo-600/30 flex items-center gap-2 transition disabled:opacity-50"
            >
              {loading ? (
                <>
                  <div className="w-4 h-4 rounded-full border-2 border-white/30 border-t-white animate-spin" />
                  <span>Scheduling Exam...</span>
                </>
              ) : (
                <>
                  <Send className="w-4 h-4" />
                  <span>Schedule & Publish Exam</span>
                </>
              )}
            </button>
          </div>
        </div>
      </form>
    </Modal>
  );
}
