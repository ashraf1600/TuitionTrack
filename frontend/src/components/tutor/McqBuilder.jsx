import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertTriangle,
  CheckCircle2,
  ClipboardPaste,
  Copy,
  FileText,
  HelpCircle,
  ImagePlus,
  Loader2,
  Pencil,
  Plus,
  Sparkles,
  Trash2,
  X,
} from 'lucide-react';
import { api, getMediaUrl } from '../../api/client';
import { notify } from '../../utils/toast';
import { parseQuestions } from '../../utils/mcqParser';
import { pasteWithLatex } from '../../utils/clipboard';
import MathRenderer from '../common/MathRenderer';

const LETTERS = ['A', 'B', 'C', 'D', 'E'];
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const SAFE_IMAGE = /^(\/media\/|https?:\/\/)/i;

const PASTE_EXAMPLE = String.raw`1. If \(P(x)=x^3-3x^2+5x-7\), then \(P(1)\) is—
A) \(-4\)
B) \(-3\)
C) \(-2\)
D) 0
Answer: A
Explanation: \(P(1)=1-3+5-7=-4\)

2. The SI unit of force is:  A) Joule  B) Newton  C) Watt  D) Pascal
Answer: B`;

let localId = 0;
const newId = () => `mcq-${Date.now()}-${(localId += 1)}`;

const blankQuestion = (extra = {}) => ({
  id: newId(),
  question: '',
  options: ['', '', '', ''],
  correct_answer: null,
  explanation: '',
  points: 1,
  marks: 1,
  image_url: '',
  ...extra,
});

const correctIndex = (q) => {
  if (typeof q.correct_answer === 'number') return q.correct_answer;
  if (typeof q.correct_answer === 'string' && q.correct_answer.trim()) {
    const value = q.correct_answer.trim().toUpperCase();
    if (LETTERS.includes(value)) return LETTERS.indexOf(value);
    if (/^\d+$/.test(value)) return Number(value);
  }
  return null;
};

/** What still stops this question from being published, in the tutor's words. */
export function questionProblems(q) {
  const problems = [];
  const options = q.options || [];
  if (!String(q.question || '').trim() && !q.image_url) problems.push('Add the question text or a picture');
  if (options.filter((o) => String(o).trim()).length < 2) problems.push('Add at least two options');
  else if (options.some((o) => !String(o).trim())) problems.push('Fill in or remove the empty option');
  const correct = correctIndex(q);
  if (correct === null || correct >= options.length || !String(options[correct] ?? '').trim()) {
    problems.push('Choose the correct answer');
  }
  return problems;
}

async function uploadImage(file) {
  if (!file.type.startsWith('image/')) throw new Error('Please choose an image file (PNG, JPG or WebP).');
  if (file.size > MAX_IMAGE_BYTES) throw new Error(`"${file.name}" is larger than 10 MB.`);
  const formData = new FormData();
  formData.append('file', file);
  const res = await api.uploadMedia(formData);
  if (!res.url || !SAFE_IMAGE.test(res.url)) throw new Error('The upload did not return a usable picture.');
  return res.url;
}

function TabButton({ active, onClick, icon: Icon, children }) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={active}
      onClick={onClick}
      className={`px-3 py-2 rounded-lg text-xs font-semibold flex items-center gap-1.5 border transition ${
        active
          ? 'bg-indigo-600 text-white border-indigo-500 shadow shadow-indigo-600/30'
          : 'bg-slate-800 text-slate-300 border-slate-700 hover:text-white hover:border-slate-500'
      }`}
    >
      <Icon className="w-3.5 h-3.5" />
      {children}
    </button>
  );
}

function QuestionCard({ q, index, onChange, onRemove, onDuplicate }) {
  const [editing, setEditing] = useState(() => questionProblems(q).some((p) => p !== 'Choose the correct answer'));
  const [uploading, setUploading] = useState(false);
  const problems = questionProblems(q);
  const correct = correctIndex(q);
  const options = q.options || [];

  const set = (patch) => onChange({ ...q, ...patch });
  const setOption = (i, value) => set({ options: options.map((o, j) => (j === i ? value : o)) });

  const removeOption = (i) => {
    let next = correct;
    if (correct === i) next = null;
    else if (correct !== null && correct > i) next = correct - 1;
    set({ options: options.filter((_, j) => j !== i), correct_answer: next });
  };

  const handleImage = async (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setUploading(true);
    try {
      set({ image_url: await uploadImage(file) });
    } catch (err) {
      notify.error(err.message || 'Picture upload failed.');
    } finally {
      setUploading(false);
    }
  };

  return (
    <li
      className={`rounded-xl border p-3.5 space-y-3 ${
        problems.length ? 'border-amber-500/50 bg-amber-500/[0.04]' : 'border-slate-700/60 bg-slate-800/40'
      }`}
    >
      <div className="flex items-start gap-2.5">
        <span className="w-6 h-6 rounded-full bg-indigo-600/30 text-indigo-300 border border-indigo-500/30 flex items-center justify-center font-bold text-xs flex-shrink-0 mt-0.5">
          {index + 1}
        </span>

        <div className="flex-1 min-w-0 space-y-2">
          {editing ? (
            <>
              <textarea
                rows={2}
                value={q.question}
                onChange={(e) => set({ question: e.target.value })}
                aria-label={`Question ${index + 1} text`}
                placeholder="Type the question. Maths works as $x^2$ or \(x_1\)."
                className="w-full px-2.5 py-2 rounded-lg bg-slate-900 border border-slate-700 text-sm text-slate-100 font-mono focus:outline-none focus:border-indigo-500"
              />
              {q.question && /[$\\]/.test(q.question) && (
                <div className="px-2.5 py-1.5 rounded-lg bg-slate-950/60 border border-slate-800 text-sm text-slate-100">
                  <span className="block text-[10px] uppercase tracking-wider text-slate-500 mb-0.5">Students will see</span>
                  <MathRenderer plain content={q.question} />
                </div>
              )}
            </>
          ) : (
            <div className="text-sm font-medium text-slate-100 break-words">
              {q.question ? <MathRenderer plain content={q.question} /> : <span className="text-slate-500 italic">Picture question</span>}
            </div>
          )}

          {q.image_url && SAFE_IMAGE.test(q.image_url) && (
            <div className="relative inline-block">
              <img src={getMediaUrl(q.image_url)} alt={`Question ${index + 1}`} className="max-h-48 rounded-lg border border-slate-700 bg-white" />
              <button
                type="button"
                onClick={() => set({ image_url: '' })}
                aria-label={`Remove picture from question ${index + 1}`}
                className="absolute -top-2 -right-2 w-6 h-6 rounded-full bg-slate-900 border border-slate-600 text-slate-300 hover:text-rose-300 flex items-center justify-center"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            </div>
          )}
        </div>

        <div className="flex items-center gap-1 flex-shrink-0">
          <label className="flex items-center gap-1 text-[11px] text-slate-400">
            <input
              type="number"
              min="0.25"
              step="0.25"
              value={q.points ?? 1}
              onChange={(e) => {
                const points = parseFloat(e.target.value);
                set({ points: points > 0 ? points : 1, marks: points > 0 ? points : 1 });
              }}
              aria-label={`Marks for question ${index + 1}`}
              className="w-12 px-1 py-1 rounded bg-slate-900 border border-slate-700 text-center text-xs text-emerald-400 font-bold focus:outline-none focus:border-indigo-500"
            />
            <span className="hidden sm:inline">mark{Number(q.points) === 1 ? '' : 's'}</span>
          </label>
          <label
            title={q.image_url ? 'Replace picture' : 'Add a picture'}
            className="p-1.5 rounded text-slate-400 hover:text-indigo-300 hover:bg-indigo-500/10 cursor-pointer transition"
          >
            {uploading ? <Loader2 className="w-4 h-4 animate-spin" /> : <ImagePlus className="w-4 h-4" />}
            <input type="file" accept="image/png,image/jpeg,image/webp" className="hidden" onChange={handleImage} aria-label={`Picture for question ${index + 1}`} />
          </label>
          <button
            type="button"
            onClick={() => setEditing((v) => !v)}
            title={editing ? 'Done editing' : 'Edit'}
            aria-label={editing ? `Finish editing question ${index + 1}` : `Edit question ${index + 1}`}
            className={`p-1.5 rounded transition ${editing ? 'text-emerald-300 bg-emerald-500/10' : 'text-slate-400 hover:text-white hover:bg-slate-700'}`}
          >
            {editing ? <CheckCircle2 className="w-4 h-4" /> : <Pencil className="w-4 h-4" />}
          </button>
          <button
            type="button"
            onClick={onDuplicate}
            title="Duplicate"
            aria-label={`Duplicate question ${index + 1}`}
            className="p-1.5 rounded text-slate-400 hover:text-white hover:bg-slate-700 transition"
          >
            <Copy className="w-4 h-4" />
          </button>
          <button
            type="button"
            onClick={onRemove}
            title="Delete"
            aria-label={`Delete question ${index + 1}`}
            className="p-1.5 rounded text-slate-400 hover:text-rose-400 hover:bg-rose-500/10 transition"
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Options — the radio marks the correct answer */}
      <div role="radiogroup" aria-label={`Correct answer for question ${index + 1}`} className="grid grid-cols-1 sm:grid-cols-2 gap-2 sm:pl-8">
        {options.map((opt, i) => {
          const isCorrect = correct === i;
          return (
            <div
              key={i}
              className={`flex items-start gap-2 p-2 rounded-lg border transition ${
                isCorrect ? 'bg-emerald-950/40 border-emerald-500/60' : 'bg-slate-900/60 border-slate-700/60'
              }`}
            >
              <label className="flex items-center gap-1.5 cursor-pointer pt-0.5" title="Mark as the correct answer">
                <input
                  type="radio"
                  name={`correct-${q.id}`}
                  checked={isCorrect}
                  onChange={() => set({ correct_answer: i })}
                  className="accent-emerald-500 w-4 h-4"
                  aria-label={`Option ${LETTERS[i]} is correct`}
                />
                <span className={`text-xs font-bold ${isCorrect ? 'text-emerald-300' : 'text-slate-400'}`}>{LETTERS[i]}</span>
              </label>
              <div className="flex-1 min-w-0">
                {editing ? (
                  <input
                    type="text"
                    value={opt}
                    onChange={(e) => setOption(i, e.target.value)}
                    placeholder={`Option ${LETTERS[i]}`}
                    aria-label={`Question ${index + 1} option ${LETTERS[i]}`}
                    className="w-full px-2 py-1 rounded bg-slate-950/60 border border-slate-700 text-xs text-slate-100 font-mono focus:outline-none focus:border-indigo-500"
                  />
                ) : opt ? (
                  <MathRenderer plain inline content={opt} className={`text-sm break-words ${isCorrect ? 'text-emerald-200' : 'text-slate-200'}`} />
                ) : (
                  <span className="text-xs text-amber-300 italic">Empty option</span>
                )}
                {editing && opt && /[$\\]/.test(opt) && (
                  <MathRenderer plain inline content={opt} className="block mt-1 text-sm text-slate-200" />
                )}
              </div>
              {isCorrect && !editing && <CheckCircle2 className="w-4 h-4 text-emerald-400 flex-shrink-0 mt-0.5" aria-hidden="true" />}
              {editing && options.length > 2 && (
                <button
                  type="button"
                  onClick={() => removeOption(i)}
                  aria-label={`Remove option ${LETTERS[i]} from question ${index + 1}`}
                  className="p-0.5 rounded text-slate-500 hover:text-rose-400"
                >
                  <X className="w-3.5 h-3.5" />
                </button>
              )}
            </div>
          );
        })}
        {editing && options.length < LETTERS.length && (
          <button
            type="button"
            onClick={() => set({ options: [...options, ''] })}
            className="p-2 rounded-lg border border-dashed border-slate-700 text-xs text-slate-400 hover:text-white hover:border-slate-500 flex items-center justify-center gap-1 transition"
          >
            <Plus className="w-3.5 h-3.5" /> Add option
          </button>
        )}
      </div>

      {(editing || q.explanation) && (
        <div className="sm:pl-8 flex items-start gap-2">
          <HelpCircle className="w-3.5 h-3.5 text-slate-500 flex-shrink-0 mt-1.5" />
          {editing ? (
            <input
              type="text"
              value={q.explanation || ''}
              onChange={(e) => set({ explanation: e.target.value })}
              placeholder="Explanation shown with the results (optional)"
              aria-label={`Explanation for question ${index + 1}`}
              className="flex-1 px-2 py-1 rounded bg-slate-900/60 border border-slate-800 text-xs text-slate-300 font-mono focus:outline-none focus:border-indigo-500"
            />
          ) : (
            <MathRenderer plain inline content={q.explanation} className="text-xs text-slate-400" />
          )}
        </div>
      )}

      {problems.length > 0 && (
        <p className="sm:pl-8 flex items-center gap-1.5 text-xs text-amber-300">
          <AlertTriangle className="w-3.5 h-3.5 flex-shrink-0" />
          {problems.join(' · ')}
        </p>
      )}
    </li>
  );
}

/**
 * Builds the multiple-choice part of an exam. Questions can come from pasted
 * text, be typed one at a time, start from a picture, or be reused from the
 * tutor's earlier exams — every route ends in the same editable card list.
 */
export default function McqBuilder({ questions, onChange }) {
  const [tab, setTab] = useState(null); // null | 'paste' | 'image' | 'bank'
  const [rawText, setRawText] = useState('');
  const [parseNote, setParseNote] = useState(null);
  const [imageBusy, setImageBusy] = useState(false);
  const [bankSearch, setBankSearch] = useState('');
  const [bankItems, setBankItems] = useState([]);
  const [bankLoading, setBankLoading] = useState(false);
  const [bankPicked, setBankPicked] = useState(() => new Set());
  const listEndRef = useRef(null);

  const preview = useMemo(() => (rawText.trim() ? parseQuestions(rawText) : { questions: [], issues: [] }), [rawText]);
  const unfinished = questions.filter((q) => questionProblems(q).length > 0).length;
  const totalPoints = questions.reduce((sum, q) => sum + (Number(q.points ?? q.marks) || 0), 0);

  const append = (items) => {
    onChange([...questions, ...items]);
    setTimeout(() => listEndRef.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' }), 50);
  };
  const update = (index, next) => onChange(questions.map((q, i) => (i === index ? next : q)));
  const remove = (index) => onChange(questions.filter((_, i) => i !== index));
  const duplicate = (index) => {
    const copy = { ...questions[index], id: newId(), options: [...questions[index].options] };
    onChange([...questions.slice(0, index + 1), copy, ...questions.slice(index + 1)]);
  };

  const addParsed = () => {
    if (preview.questions.length === 0) {
      notify.error('No questions found. Number each question (1. 2. 3.) and label the options A, B, C, D.');
      return;
    }
    const needAnswer = preview.questions.filter((q) => q.correct_answer === null).length;
    append(preview.questions);
    setParseNote({ added: preview.questions.length, needAnswer, issues: preview.issues });
    setRawText('');
    setTab(null);
  };

  const addFromImages = async (e) => {
    const files = Array.from(e.target.files || []);
    e.target.value = '';
    if (files.length === 0) return;
    setImageBusy(true);
    const added = [];
    try {
      for (const file of files) {
        added.push(blankQuestion({ image_url: await uploadImage(file), options: ['A', 'B', 'C', 'D'] }));
      }
    } catch (err) {
      notify.error(err.message || 'Picture upload failed.');
    } finally {
      setImageBusy(false);
      if (added.length) {
        append(added);
        setTab(null);
      }
    }
  };

  // Question bank: search the tutor's earlier MCQs while the panel is open.
  useEffect(() => {
    if (tab !== 'bank') return undefined;
    const timer = setTimeout(async () => {
      setBankLoading(true);
      try {
        const res = await api.getQuestionBank(bankSearch.trim());
        setBankItems(res.questions || []);
      } catch {
        setBankItems([]);
      } finally {
        setBankLoading(false);
      }
    }, 250);
    return () => clearTimeout(timer);
  }, [tab, bankSearch]);

  const bankKey = (q) => `${q.question}|${q.image_url || ''}|${(q.options || []).join('|')}`;
  const inExam = new Set(questions.map(bankKey));
  const toggleBankPick = (q) =>
    setBankPicked((prev) => {
      const next = new Set(prev);
      const key = bankKey(q);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  const addPickedFromBank = () => {
    const chosen = bankItems.filter((q) => bankPicked.has(bankKey(q)) && !inExam.has(bankKey(q)));
    if (chosen.length === 0) return;
    append(
      chosen.map((q) =>
        blankQuestion({
          question: q.question,
          options: [...q.options],
          correct_answer: q.correct_answer ?? null,
          explanation: q.explanation || '',
          points: Number(q.points) || 1,
          marks: Number(q.points) || 1,
          image_url: q.image_url || '',
        })
      )
    );
    setBankPicked(new Set());
    setTab(null);
  };

  const toggleTab = (name) => setTab((current) => (current === name ? null : name));

  return (
    <section className="rounded-xl border border-slate-700/80 bg-slate-900/60 p-4 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <Sparkles className="w-4 h-4 text-amber-400" />
          <h4 className="text-xs font-bold text-slate-200 uppercase tracking-wider">
            Multiple choice — {questions.length} question{questions.length === 1 ? '' : 's'} · {totalPoints} mark{totalPoints === 1 ? '' : 's'}
          </h4>
        </div>
        {unfinished > 0 && (
          <span className="text-xs text-amber-300 flex items-center gap-1">
            <AlertTriangle className="w-3.5 h-3.5" /> {unfinished} need{unfinished === 1 ? 's' : ''} attention
          </span>
        )}
      </div>

      {/* Ways to add questions */}
      <div role="tablist" aria-label="Add questions" className="flex flex-wrap items-center gap-2">
        <TabButton active={tab === 'paste'} onClick={() => toggleTab('paste')} icon={ClipboardPaste}>Paste text</TabButton>
        <button
          type="button"
          onClick={() => { setTab(null); append([blankQuestion()]); }}
          className="px-3 py-2 rounded-lg text-xs font-semibold flex items-center gap-1.5 border bg-slate-800 text-slate-300 border-slate-700 hover:text-white hover:border-slate-500 transition"
        >
          <Plus className="w-3.5 h-3.5" /> Type a question
        </button>
        <TabButton active={tab === 'image'} onClick={() => toggleTab('image')} icon={ImagePlus}>From a picture</TabButton>
        <TabButton active={tab === 'bank'} onClick={() => { toggleTab('bank'); setBankPicked(new Set()); }} icon={FileText}>My past questions</TabButton>
      </div>

      {/* Paste */}
      {tab === 'paste' && (
        <div className="p-3.5 rounded-xl bg-slate-800/80 border border-indigo-500/40 space-y-2.5">
          <p className="text-xs text-slate-300">
            Paste any number of questions from ChatGPT, a website or a document. Numbered questions with options A–D
            (or ক–ঘ) are recognised, on separate lines or on one line. Maths is kept exactly as written.
          </p>
          <textarea
            rows={9}
            value={rawText}
            onChange={(e) => setRawText(e.target.value)}
            onPaste={(e) => pasteWithLatex(e, rawText, setRawText)}
            placeholder={PASTE_EXAMPLE}
            aria-label="Paste questions here"
            spellCheck={false}
            className="w-full p-3 rounded-lg bg-slate-900 border border-slate-700 text-slate-100 text-xs font-mono leading-relaxed focus:outline-none focus:border-indigo-500"
          />
          <div className="flex flex-wrap items-center justify-between gap-2">
            <span className="text-xs text-slate-400" aria-live="polite">
              {rawText.trim()
                ? preview.questions.length
                  ? `Found ${preview.questions.length} question${preview.questions.length === 1 ? '' : 's'}` +
                    (preview.issues.length ? ` · ${preview.issues.length} will need a quick check` : ' · all have an answer')
                  : 'No questions recognised yet'
                : 'Answers can be written as “Answer: B”, a ✅ after the option, or an answer key at the end.'}
            </span>
            <div className="flex items-center gap-2">
              <button type="button" onClick={() => setRawText(PASTE_EXAMPLE)} className="px-2.5 py-1.5 rounded-lg text-xs text-slate-300 hover:text-white">
                Show an example
              </button>
              <button
                type="button"
                onClick={addParsed}
                disabled={preview.questions.length === 0}
                className="px-3.5 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold flex items-center gap-1.5 transition disabled:opacity-50"
              >
                <Sparkles className="w-3.5 h-3.5" />
                Add {preview.questions.length || ''} question{preview.questions.length === 1 ? '' : 's'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Picture */}
      {tab === 'image' && (
        <div className="p-3.5 rounded-xl bg-slate-800/80 border border-indigo-500/40 space-y-2.5">
          <p className="text-xs text-slate-300">
            Upload a photo or screenshot of a question (a diagram, a graph, a handwritten problem). Each picture becomes
            one question with options A–D — then mark the correct one. Choose several pictures to add several questions.
          </p>
          <label className="px-4 py-6 rounded-xl bg-slate-900 hover:bg-slate-900/60 border border-dashed border-slate-600 text-slate-300 text-xs font-semibold flex flex-col items-center justify-center gap-2 cursor-pointer transition">
            {imageBusy ? <Loader2 className="w-5 h-5 animate-spin text-indigo-300" /> : <ImagePlus className="w-5 h-5 text-indigo-300" />}
            <span>{imageBusy ? 'Uploading…' : 'Choose pictures (PNG, JPG or WebP, up to 10 MB each)'}</span>
            <input type="file" accept="image/png,image/jpeg,image/webp" multiple className="hidden" disabled={imageBusy} onChange={addFromImages} />
          </label>
          <p className="text-[11px] text-slate-400">
            To add a picture to a typed question instead, use the picture button on that question.
          </p>
        </div>
      )}

      {/* Question bank */}
      {tab === 'bank' && (
        <div className="p-3.5 rounded-xl bg-slate-800/80 border border-indigo-500/40 space-y-2.5">
          <input
            type="search"
            value={bankSearch}
            onChange={(e) => setBankSearch(e.target.value)}
            placeholder="Search by words in the question or its options"
            aria-label="Search your past questions"
            className="w-full px-3 py-2 rounded-lg bg-slate-900 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
          />
          <div className="max-h-56 overflow-y-auto space-y-1.5 pr-1">
            {bankLoading ? (
              <p className="text-xs text-slate-400 py-2">Searching…</p>
            ) : bankItems.length === 0 ? (
              <p className="text-xs text-slate-400 py-2">
                {bankSearch ? 'No past questions match that search.' : 'Questions you write in any exam will appear here for reuse.'}
              </p>
            ) : (
              bankItems.map((q, i) => {
                const key = bankKey(q);
                const used = inExam.has(key);
                return (
                  <label
                    key={`${key}-${i}`}
                    className={`flex items-start gap-2.5 p-2.5 rounded-lg border text-xs cursor-pointer ${
                      used ? 'border-slate-800 opacity-50 cursor-not-allowed' : bankPicked.has(key) ? 'border-indigo-500 bg-indigo-500/10' : 'border-slate-700 hover:border-slate-500'
                    }`}
                  >
                    <input type="checkbox" className="mt-0.5 accent-indigo-600" disabled={used} checked={used || bankPicked.has(key)} onChange={() => toggleBankPick(q)} />
                    <span className="min-w-0">
                      <MathRenderer plain inline content={q.question || '(picture question)'} className="block text-slate-100 font-medium" />
                      <span className="block text-slate-400 truncate">{(q.options || []).join(' · ')}</span>
                      <span className="block text-[10px] text-slate-500">
                        {used ? 'Already in this exam' : `From: ${q.source_exam} · ${q.points} mark${Number(q.points) === 1 ? '' : 's'}`}
                      </span>
                    </span>
                  </label>
                );
              })
            )}
          </div>
          <div className="flex justify-end">
            <button
              type="button"
              onClick={addPickedFromBank}
              disabled={bankPicked.size === 0}
              className="px-3 py-1.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold transition disabled:opacity-50"
            >
              Add {bankPicked.size || ''} selected
            </button>
          </div>
        </div>
      )}

      {/* Result of the last paste */}
      {parseNote && (
        <div
          role="status"
          className={`p-3 rounded-xl border text-xs flex items-start gap-2 ${
            parseNote.issues.length ? 'bg-amber-500/10 border-amber-500/30 text-amber-200' : 'bg-emerald-500/10 border-emerald-500/30 text-emerald-200'
          }`}
        >
          {parseNote.issues.length ? <AlertTriangle className="w-4 h-4 flex-shrink-0 mt-0.5" /> : <CheckCircle2 className="w-4 h-4 flex-shrink-0 mt-0.5" />}
          <div className="flex-1">
            <p className="font-semibold">
              Added {parseNote.added} question{parseNote.added === 1 ? '' : 's'}.
              {parseNote.issues.length === 0
                ? ' Check each one below before publishing.'
                : ` ${parseNote.issues.length} need${parseNote.issues.length === 1 ? 's' : ''} a quick check — they are marked below.`}
            </p>
          </div>
          <button type="button" onClick={() => setParseNote(null)} aria-label="Dismiss" className="text-current opacity-70 hover:opacity-100">
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      )}

      {/* The questions */}
      {questions.length === 0 ? (
        <p className="text-xs text-slate-400 text-center py-6 border border-dashed border-slate-700 rounded-xl">
          No questions yet. Paste a set, type one, or start from a picture.
        </p>
      ) : (
        <ol className="space-y-3 max-h-[460px] overflow-y-auto pr-1">
          {questions.map((q, index) => (
            <QuestionCard
              key={q.id || index}
              q={q}
              index={index}
              onChange={(next) => update(index, next)}
              onRemove={() => remove(index)}
              onDuplicate={() => duplicate(index)}
            />
          ))}
          <li ref={listEndRef} aria-hidden="true" />
        </ol>
      )}
    </section>
  );
}
