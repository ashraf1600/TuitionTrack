import React, { useState, useEffect, useRef } from 'react';
import Modal from '../common/Modal';
import MathRenderer from '../common/MathRenderer';
import { api } from '../../api/client';
import {
  Clock,
  Camera,
  Upload,
  AlertCircle,
  CheckCircle2,
  Send,
  X,
  FileText,
  AlertTriangle,
  HelpCircle,
  Sparkles,
} from 'lucide-react';

export default function ExamTakerModal({
  isOpen,
  onClose,
  exam,
  onExamSubmitted,
}) {
  const [mcqAnswers, setMcqAnswers] = useState({});
  const [textAnswers, setTextAnswers] = useState({});
  const [imageUrls, setImageUrls] = useState([]);
  const [uploading, setUploading] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [timeLeft, setTimeLeft] = useState('');
  const [isGracePeriod, setIsGracePeriod] = useState(false);
  const [isExpired, setIsExpired] = useState(false);
  const [serverOffsetMs, setServerOffsetMs] = useState(0);

  const autoSubmitRef = useRef(null);

  // Restore draft answers from localStorage if available
  useEffect(() => {
    if (exam?.id) {
      setError('');
      setIsExpired(false);
      api.fetchServerOffset().then(setServerOffsetMs).catch(() => setServerOffsetMs(0));

      const storageKey = `exam_draft_${exam.id}`;
      try {
        const saved = localStorage.getItem(storageKey);
        if (saved) {
          const parsed = JSON.parse(saved);
          if (parsed.mcqAnswers) setMcqAnswers(parsed.mcqAnswers);
          if (parsed.textAnswers) setTextAnswers(parsed.textAnswers);
          if (parsed.imageUrls) setImageUrls(parsed.imageUrls);
        } else {
          setMcqAnswers({});
          setTextAnswers({});
          setImageUrls([]);
        }
      } catch (_) {
        setMcqAnswers({});
        setTextAnswers({});
        setImageUrls([]);
      }
    }
  }, [exam?.id]);

  // Persist in-progress answers so closing modal does not lose answers
  useEffect(() => {
    if (exam?.id && (Object.keys(mcqAnswers).length > 0 || imageUrls.length > 0)) {
      const storageKey = `exam_draft_${exam.id}`;
      localStorage.setItem(storageKey, JSON.stringify({ mcqAnswers, textAnswers, imageUrls }));
    }
  }, [exam?.id, mcqAnswers, textAnswers, imageUrls]);

  // Live Countdown Timer (server-offset corrected; auto-submits on expiration)
  useEffect(() => {
    if (!isOpen || !exam) return;

    const interval = setInterval(() => {
      const now = Date.now() + serverOffsetMs;
      const endTime = new Date(exam.end_time).getTime();
      const graceEnd = endTime + (exam.grace_period_minutes || 5) * 60 * 1000;

      if (now > graceEnd) {
        setTimeLeft('00:00:00 (Expired)');
        setIsGracePeriod(false);
        setIsExpired(true);
        clearInterval(interval);
        // Automatically submit student answers when the timer reaches 0
        if (autoSubmitRef.current) {
          autoSubmitRef.current();
        }
      } else if (now > endTime) {
        // In grace period
        setIsGracePeriod(true);
        const diff = graceEnd - now;
        const mins = Math.floor((diff / (1000 * 60)) % 60);
        const secs = Math.floor((diff / 1000) % 60);
        setTimeLeft(`Grace: ${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`);
      } else {
        setIsGracePeriod(false);
        const diff = endTime - now;
        const hours = Math.floor(diff / (1000 * 60 * 60));
        const mins = Math.floor((diff / (1000 * 60)) % 60);
        const secs = Math.floor((diff / 1000) % 60);
        setTimeLeft(
          `${String(hours).padStart(2, '0')}:${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`
        );
      }
    }, 1000);

    return () => clearInterval(interval);
  }, [isOpen, exam, serverOffsetMs]);

  if (!exam) return null;

  const hasMCQs = Array.isArray(exam.mcq_data) && exam.mcq_data.length > 0;
  const isMCQOnly = exam.exam_type === 'MCQ';

  const handleSelectMCQ = (qId, optionIndex) => {
    setMcqAnswers((prev) => ({
      ...prev,
      [qId]: optionIndex,
    }));
  };

  // Handle CQ image upload
  const handlePhotoUpload = async (e) => {
    const files = Array.from(e.target.files || []);
    if (files.length === 0) return;
    const MAX_BYTES = 10 * 1024 * 1024;
    for (const f of files) {
      if (f.size > MAX_BYTES) {
        setError(`"${f.name}" exceeds 10MB limit.`);
        e.target.value = '';
        return;
      }
      if (f.size === 0) {
        setError(`"${f.name}" is empty.`);
        e.target.value = '';
        return;
      }
    }

    setUploading(true);
    setError('');

    try {
      for (const file of files) {
        const formData = new FormData();
        formData.append('file', file);
        const res = await api.uploadMedia(formData);
        const url = res.url || res.file_url;
        if (!url || /^\s*(javascript|data:text\/html|vbscript):/i.test(url)) {
          throw new Error('Server returned an unsafe file URL.');
        }
        setImageUrls((prev) => [...prev, url]);
      }
    } catch (err) {
      setError(err.message || 'Failed to upload photo.');
    } finally {
      setUploading(false);
      e.target.value = '';
    }
  };

  const removeImage = (index) => {
    setImageUrls((prev) => prev.filter((_, i) => i !== index));
  };

  const doSubmit = async () => {
    if (submitting) return;
    setSubmitting(true);
    try {
      const answersData = {
        ...textAnswers,
        ...mcqAnswers,
      };

      await api.submitExam(exam.id, {
        answers_data: answersData,
        image_urls: imageUrls,
        uploaded_images: imageUrls,
      });

      if (exam?.id) {
        localStorage.removeItem(`exam_draft_${exam.id}`);
      }
      onExamSubmitted();
      onClose();
    } catch (err) {
      setError(err.message || 'Submission failed.');
    } finally {
      setSubmitting(false);
    }
  };

  useEffect(() => {
    autoSubmitRef.current = () => {
      // Auto-submit whatever has been answered so far
      doSubmit();
    };
  });

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    if (isExpired) {
      setError('Submission window has closed (including grace period).');
      return;
    }

    // Validation
    const answeredCount = Object.keys(mcqAnswers).length;
    if (isMCQOnly && answeredCount === 0) {
      setError('Please select an answer for at least one MCQ question.');
      return;
    }

    const needsCQ = !isMCQOnly && exam.content_html && exam.content_html !== '<p></p>' && exam.content_html !== '<p>Multiple Choice Examination</p>';
    if (!isMCQOnly && imageUrls.length === 0 && answeredCount === 0) {
      setError('Please answer the questions or upload a photo of your written answer script.');
      return;
    }
    if (needsCQ && imageUrls.length === 0 && exam.exam_type !== 'MCQ') {
      // HYBRID/CQ with written section requires an upload
      setError('Please upload your written answer script for the CQ section.');
      return;
    }

    await doSubmit();
  };

  const isAssignment = exam.category === 'ASSIGNMENT';

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={`${isAssignment ? 'Assignment Submission' : 'Examination'} — ${exam.title}`}
      maxWidth="max-w-4xl"
    >
      <div className="space-y-6">
        {/* Countdown Timer Banner */}
        <div
          className={`flex flex-col sm:flex-row items-center justify-between gap-3 p-4 rounded-xl border ${
            isGracePeriod
              ? 'bg-amber-950/40 border-amber-500/40 text-amber-300'
              : isAssignment
              ? 'bg-purple-950/40 border-purple-500/40 text-purple-300'
              : 'bg-indigo-950/40 border-indigo-500/40 text-indigo-300'
          }`}
        >
          <div className="flex items-center gap-2">
            <Clock
              className={`w-5 h-5 ${
                isGracePeriod
                  ? 'animate-bounce text-amber-400'
                  : isAssignment
                  ? 'text-purple-400'
                  : 'text-indigo-400'
              }`}
            />
            <div>
              <span className="text-xs font-semibold uppercase tracking-wider block">
                {isGracePeriod
                  ? 'Grace Period Active (Late Turn-in)'
                  : isAssignment
                  ? 'Time Remaining Until Deadline'
                  : 'Time Remaining'}
              </span>
              <span className="text-xl font-mono font-bold tracking-tight">
                {timeLeft || 'Calculating...'}
              </span>
            </div>
          </div>


          <div className="text-xs text-right">
            <div>
              Total Marks: <strong className="text-slate-100">{exam.total_marks}</strong>
            </div>
            <div className="text-slate-400">
              Format: <span className="font-mono text-emerald-400 font-bold">{exam.exam_type || 'HYBRID'}</span>
              {hasMCQs && ` • ${exam.mcq_data.length} MCQs`}
            </div>
          </div>
        </div>

        {error && (
          <div className="p-3.5 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs flex items-center gap-2">
            <AlertCircle className="w-5 h-5 flex-shrink-0" />
            <span>{error}</span>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Section 1: Multiple Choice Questions (Interactive Cards) */}
          {hasMCQs && (
            <div className="space-y-4">
              <div className="flex items-center justify-between border-b border-slate-800 pb-2">
                <h4 className="text-xs font-bold text-slate-200 uppercase tracking-wider flex items-center gap-2">
                  <Sparkles className="w-4 h-4 text-amber-400" />
                  Multiple Choice Section ({Object.keys(mcqAnswers).length} of {exam.mcq_data.length} Answered)
                </h4>
                <span className="text-[11px] text-slate-400">
                  Select your choice for each question below
                </span>
              </div>

              <div className="space-y-3.5 max-h-[380px] overflow-y-auto pr-1">
                {exam.mcq_data.map((q, idx) => {
                  const qKey = q.id || `mcq-${idx}`;
                  const selectedOpt = mcqAnswers[qKey];

                  return (
                    <div
                      key={qKey}
                      className="p-4 rounded-xl bg-slate-900/70 border border-slate-800 space-y-3"
                    >
                      <div className="flex items-start justify-between gap-2">
                        <div className="flex items-start gap-2.5">
                          <span className="w-6 h-6 rounded-full bg-indigo-600/30 text-indigo-300 border border-indigo-500/30 flex items-center justify-center font-bold text-xs flex-shrink-0 mt-0.5">
                            {idx + 1}
                          </span>
                          <div className="text-sm font-semibold text-slate-100">
                            <MathRenderer content={q.question} />
                          </div>
                        </div>

                        <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-slate-800 text-emerald-400 font-bold flex-shrink-0">
                          {q.points || q.marks || 1} Pt
                        </span>
                      </div>

                      {/* 4 Clickable Option Cards */}
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 pl-8">
                        {(q.options || []).map((opt, optIdx) => {
                          const isSelected = selectedOpt === optIdx;
                          const letter = ['A', 'B', 'C', 'D'][optIdx] || String(optIdx + 1);

                          return (
                            <button
                              key={optIdx}
                              type="button"
                              onClick={() => handleSelectMCQ(qKey, optIdx)}
                              className={`p-2.5 rounded-xl border text-left flex items-center gap-2.5 transition ${
                                isSelected
                                  ? 'bg-indigo-600/20 border-indigo-500 text-indigo-200 shadow-md shadow-indigo-600/10'
                                  : 'bg-slate-800/40 border-slate-700/60 text-slate-300 hover:bg-slate-800 hover:border-slate-600'
                              }`}
                            >
                              <span
                                className={`w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold uppercase transition ${
                                  isSelected
                                    ? 'bg-indigo-600 text-white'
                                    : 'bg-slate-700 text-slate-300'
                                }`}
                              >
                                {letter}
                              </span>
                              <span className="text-xs font-medium flex-1">
                                <MathRenderer content={opt} />
                              </span>
                            </button>
                          );
                        })}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* Section 2: Written CQ Paper & Instructions */}
          {!isMCQOnly && exam.content_html && exam.content_html !== '<p>Multiple Choice Examination</p>' && (
            <div className="space-y-3">
              <h4 className="text-xs font-bold text-slate-300 uppercase tracking-wider flex items-center gap-2">
                <FileText className="w-4 h-4 text-indigo-400" />
                Written Exam Paper / CQ Questions
              </h4>
              <div className="p-5 rounded-2xl bg-slate-950/60 border border-slate-800 max-h-[300px] overflow-y-auto">
                <MathRenderer content={exam.content_html} />
              </div>
            </div>
          )}

          {/* Section 3: CQ Handwritten Answer Script Upload */}
          {!isMCQOnly && (
            <div className="pt-2">
              <h4 className="text-xs font-bold text-slate-300 uppercase tracking-wider mb-2 flex items-center gap-2">
                <Camera className="w-4 h-4 text-emerald-400" />
                Upload Written Script / Handwritten Answer Sheets
              </h4>

              <div className="flex flex-col sm:flex-row items-center gap-3">
                <label className="w-full sm:w-auto px-4 py-3 rounded-xl bg-slate-800 hover:bg-slate-700 border border-dashed border-slate-600 text-slate-300 text-xs font-semibold flex items-center justify-center gap-2 cursor-pointer transition">
                  <Camera className="w-4 h-4 text-emerald-400" />
                  <span>Take Photo / Choose File</span>
                  <input
                    type="file"
                    accept="image/*,application/pdf"
                    capture="environment"
                    multiple
                    onChange={handlePhotoUpload}
                    className="hidden"
                  />
                </label>

                {uploading && (
                  <div className="flex items-center gap-2 text-xs text-indigo-400 animate-pulse">
                    <div className="w-4 h-4 rounded-full border-2 border-indigo-400 border-t-transparent animate-spin" />
                    <span>Uploading photo...</span>
                  </div>
                )}
              </div>

              {imageUrls.length > 0 && (
                <div className="mt-3 grid grid-cols-2 sm:grid-cols-4 gap-3">
                  {imageUrls.map((url, index) => {
                    const isPdf = /\.pdf(\?|$)/i.test(url);
                    return (
                    <div
                      key={index}
                      className="relative group rounded-xl overflow-hidden border border-slate-700 bg-slate-900"
                    >
                      {isPdf ? (
                        <a href={url} target="_blank" rel="noopener noreferrer" className="block w-full h-24 flex items-center justify-center text-xs text-indigo-300 underline">PDF Page #{index + 1}</a>
                      ) : (
                      <img
                        src={url}
                        alt={`Upload ${index + 1}`}
                        className="w-full h-24 object-cover"
                      />
                      )}
                      <button
                        type="button"
                        onClick={() => removeImage(index)}
                        className="absolute top-1 right-1 p-1 rounded-full bg-rose-600 text-white shadow-md hover:bg-rose-500"
                        title="Remove sheet"
                      >
                        <X className="w-3.5 h-3.5" />
                      </button>
                      <span className="absolute bottom-1 left-1 px-1.5 py-0.5 rounded bg-slate-950/80 text-[10px] text-slate-300 font-mono">
                        Page #{index + 1}
                      </span>
                    </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}

          {/* Submission action */}
          <div className="pt-3 border-t border-slate-800 flex items-center justify-between gap-3">
            <span className="text-[11px] text-slate-400">
              Make sure to turn in before the timer expires.
            </span>

            <div className="flex items-center gap-3">
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-2 rounded-xl border border-slate-700 text-slate-300 text-xs hover:bg-slate-800 transition"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={submitting || uploading || isExpired}
                className="px-6 py-2.5 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-xs shadow-lg shadow-emerald-600/30 flex items-center gap-2 transition disabled:opacity-50"
              >
                {submitting ? (
                  <>
                    <div className="w-4 h-4 rounded-full border-2 border-white/30 border-t-white animate-spin" />
                    <span>{isAssignment ? 'Submitting Assignment...' : 'Submitting Exam...'}</span>
                  </>
                ) : (
                  <>
                    <Send className="w-4 h-4" />
                    <span>{isAssignment ? 'Turn In Assignment' : 'Turn In Exam'}</span>
                  </>
                )}

              </button>
            </div>
          </div>
        </form>
      </div>
    </Modal>
  );
}
