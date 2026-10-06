import React, { useState, useEffect } from 'react';
import { useEditor, EditorContent } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import { Table, TableRow, TableHeader, TableCell } from '@tiptap/extension-table';
import { Image } from '@tiptap/extension-image';
import Modal from '../common/Modal';
import { api } from '../../api/client';
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
} from 'lucide-react';
import MathRenderer from '../common/MathRenderer';

export default function ExamAuthoringModal({
  isOpen,
  onClose,
  students = [],
  onExamCreated,
  initialStudentId = '',
}) {
  const [title, setTitle] = useState('');
  const [studentId, setStudentId] = useState(initialStudentId);
  const [totalMarks, setTotalMarks] = useState('100.00');
  const [durationMinutes, setDurationMinutes] = useState('60');
  const [gracePeriod, setGracePeriod] = useState('5');

  // Dates
  const now = new Date();
  const defaultStart = new Date(now.getTime() + 10 * 60 * 1000).toISOString().slice(0, 16);
  const defaultEnd = new Date(now.getTime() + 70 * 60 * 1000).toISOString().slice(0, 16);
  const [startTime, setStartTime] = useState(defaultStart);
  const [endTime, setEndTime] = useState(defaultEnd);

  const [previewMode, setPreviewMode] = useState(false);
  const [uploadingImage, setUploadingImage] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (initialStudentId) {
      setStudentId(initialStudentId);
    } else if (students.length > 0 && !studentId) {
      setStudentId(students[0].student_id);
    }
  }, [initialStudentId, students]);

  // TipTap Editor instance
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
    content: `<h2>Physics & Math Assessment</h2><p>Answer the following questions carefully. Show all derivations.</p><table><thead><tr><th>Question</th><th>Marks</th></tr></thead><tbody><tr><td>1. Differentiate $f(x) = x^2 \\sin(x)$</td><td>10</td></tr><tr><td>2. Solve equation $$\\int_0^1 (3x^2 + 2x) dx$$</td><td>15</td></tr></tbody></table>`,
    editorProps: {
      attributes: {
        class: 'prose prose-invert max-w-none focus:outline-none min-h-[220px] p-4 text-slate-100',
      },
    },
  });

  // Insert Math Formula template
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

  // Insert Table
  const insertTable = () => {
    if (!editor) return;
    editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run();
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!editor) return;
    setError('');

    const htmlContent = editor.getHTML();
    if (!htmlContent || htmlContent.trim() === '<p></p>') {
      setError('Exam content cannot be empty.');
      return;
    }

    if (new Date(endTime) <= new Date(startTime)) {
      setError('End time must be strictly after start time.');
      return;
    }

    setLoading(true);
    try {
      await api.createExam({
        title,
        student_id: studentId,
        content_html: htmlContent,
        total_marks: parseFloat(totalMarks),
        start_time: new Date(startTime).toISOString(),
        end_time: new Date(endTime).toISOString(),
        duration_minutes: parseInt(durationMinutes) || null,
        grace_period_minutes: parseInt(gracePeriod) || 5,
        is_published: true,
      });

      onExamCreated();
      onClose();
    } catch (err) {
      setError(err.message || 'Failed to create exam.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Author & Schedule Exam" maxWidth="max-w-4xl">
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 text-sm flex items-center gap-2">
            <AlertCircle className="w-5 h-5 flex-shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {/* Basic fields */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div className="sm:col-span-2">
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Exam Title *
            </label>
            <input
              type="text"
              required
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="e.g. HSC Physics — Chapter 4 Dynamics"
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Assign to Student *
            </label>
            <select
              value={studentId}
              onChange={(e) => setStudentId(e.target.value)}
              required
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
            >
              {students.map((st) => (
                <option key={st.student_id} value={st.student_id}>
                  {st.full_name} (@{st.username})
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* Schedule & Marks */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 p-3 rounded-xl bg-slate-800/40 border border-slate-700/60">
          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Start Time *
            </label>
            <input
              type="datetime-local"
              required
              value={startTime}
              onChange={(e) => setStartTime(e.target.value)}
              className="w-full px-2.5 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              End Time *
            </label>
            <input
              type="datetime-local"
              required
              value={endTime}
              onChange={(e) => setEndTime(e.target.value)}
              className="w-full px-2.5 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Total Marks
            </label>
            <input
              type="number"
              min="1"
              value={totalMarks}
              onChange={(e) => setTotalMarks(e.target.value)}
              className="w-full px-2.5 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-xs text-emerald-400 font-bold focus:outline-none focus:border-indigo-500"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Grace Period (Min)
            </label>
            <input
              type="number"
              min="0"
              value={gracePeriod}
              onChange={(e) => setGracePeriod(e.target.value)}
              className="w-full px-2.5 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-xs text-indigo-300 font-bold focus:outline-none focus:border-indigo-500"
            />
          </div>
        </div>

        {/* TipTap Toolbar & Editor */}
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

          {/* Editor or KaTeX Preview */}
          <div className="min-h-[260px] max-h-[400px] overflow-y-auto">
            {previewMode ? (
              <div className="p-4 bg-slate-950/50">
                <MathRenderer content={editor?.getHTML() || ''} />
              </div>
            ) : (
              <EditorContent editor={editor} />
            )}
          </div>
        </div>

        <p className="text-[11px] text-slate-400">
          💡 <strong>Pro Tip:</strong> You can paste rich text or Markdown generated directly from ChatGPT. LaTeX equations wrapped in <code>$...$</code> or <code>$$...$$</code> will render beautifully for students.
        </p>

        {/* Action Buttons */}
        <div className="pt-3 flex items-center justify-end gap-3 border-t border-slate-800">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 rounded-xl border border-slate-700 text-slate-300 text-sm hover:bg-slate-800 transition"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={loading}
            className="px-5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-sm shadow-lg shadow-indigo-600/30 flex items-center gap-2 transition disabled:opacity-50"
          >
            {loading ? (
              <>
                <div className="w-4 h-4 rounded-full border-2 border-white/30 border-t-white animate-spin" />
                <span>Scheduling Exam...</span>
              </>
            ) : (
              <>
                <Send className="w-4 h-4" />
                <span>Schedule & Alert Student</span>
              </>
            )}
          </button>
        </div>
      </form>
    </Modal>
  );
}
