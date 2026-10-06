import React, { useState } from 'react';
import {
  Check,
  RotateCcw,
  AlertTriangle,
  Calendar,
  CheckCircle2,
  Clock,
  CalendarDays,
  Sparkles,
  BookOpen,
  X,
} from 'lucide-react';
import Modal from '../common/Modal';

export default function CycleGrid({
  cycle,
  studentName,
  tuitionTitle = '',
  onToggleClass,
  onResetCycle,
  onOpenAddStudent = null,
  loading,
}) {
  const [resetModalOpen, setResetModalOpen] = useState(false);
  const [resetting, setResetting] = useState(false);

  // Class Attendance Date Picker Modal
  const [dateModalOpen, setDateModalOpen] = useState(false);
  const [selectedClass, setSelectedClass] = useState(null);
  const [classDate, setClassDate] = useState(new Date().toISOString().slice(0, 10));
  const [classTopic, setClassTopic] = useState('');
  const [isCompletedState, setIsCompletedState] = useState(true);
  const [savingClass, setSavingClass] = useState(false);

  if (!cycle) {
    return (
      <div className="glass-panel p-8 rounded-2xl text-center text-slate-400 space-y-3">
        <Calendar className="w-12 h-12 mx-auto text-indigo-400 mb-2" />
        <h4 className="text-base font-bold text-slate-200">
          {tuitionTitle ? `${tuitionTitle} — Class Attendance & Billing Engine` : 'No active cycle selected'}
        </h4>
        <p className="text-xs text-slate-400 max-w-md mx-auto">
          {tuitionTitle
            ? 'No students are currently enrolled in this tuition. Add a student to start tracking attendance and revenue.'
            : 'Select a student from the roster on the left to view and check off classes.'}
        </p>
        {onOpenAddStudent && (
          <button
            onClick={onOpenAddStudent}
            className="mt-2 px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold shadow-md shadow-indigo-600/30 transition"
          >
            + Add Student to {tuitionTitle || 'Tuition'}
          </button>
        )}
      </div>
    );
  }

  const cycle_number = cycle.cycle_number || 1;
  const fee_snapshot = cycle.tuition_fee !== undefined ? cycle.tuition_fee : (cycle.fee_snapshot || 0);
  const total_classes = cycle.total_classes || 12;
  const completed_classes = cycle.completed_classes || 0;
  const earned_amount = cycle.earned_revenue !== undefined ? cycle.earned_revenue : (cycle.earned_amount || 0);
  const pending_amount = cycle.pending_balance !== undefined ? cycle.pending_balance : (cycle.pending_amount || 0);
  const progress_percentage = cycle.progress_percent !== undefined ? cycle.progress_percent : (cycle.progress_percentage || 0);
  const is_complete = cycle.is_complete || (completed_classes >= total_classes);
  const classes_data = cycle.classes_data || [];

  const handleOpenClassModal = (cls) => {
    setSelectedClass(cls);
    // Always default to Completed (true) on open so calendar date picker is immediately visible and ready to save
    setIsCompletedState(true);
    if (cls.date) {
      setClassDate(new Date(cls.date).toISOString().slice(0, 10));
    } else {
      setClassDate(new Date().toISOString().slice(0, 10));
    }
    setClassTopic(cls.topic || '');
    setDateModalOpen(true);
  };

  const handleSaveClassAttendance = async (e) => {
    e?.preventDefault();
    if (!selectedClass) return;

    const classNum = selectedClass.class_no ?? selectedClass.classNo;
    setSavingClass(true);
    try {
      const targetDate = isCompletedState ? (classDate ? new Date(classDate).toISOString() : new Date().toISOString()) : null;
      await onToggleClass(cycle.id, classNum, isCompletedState, targetDate, isCompletedState ? classTopic : '');
      setDateModalOpen(false);
    } catch (err) {
      alert(`Save failed: ${err.message}`);
    } finally {
      setSavingClass(false);
    }
  };

  const handleQuickMarkToday = async () => {
    if (!selectedClass) return;
    const classNum = selectedClass.class_no ?? selectedClass.classNo;
    setSavingClass(true);
    try {
      const todayIso = new Date().toISOString();
      await onToggleClass(cycle.id, classNum, true, todayIso, classTopic);
      setDateModalOpen(false);
    } finally {
      setSavingClass(false);
    }
  };

  const handleQuickUnmark = async () => {
    if (!selectedClass) return;
    const classNum = selectedClass.class_no ?? selectedClass.classNo;
    setSavingClass(true);
    try {
      await onToggleClass(cycle.id, classNum, false, null, '');
      setDateModalOpen(false);
    } finally {
      setSavingClass(false);
    }
  };

  const handleConfirmReset = async () => {
    setResetting(true);
    try {
      await onResetCycle(cycle.id);
      setResetModalOpen(false);
    } finally {
      setResetting(false);
    }
  };

  return (
    <div className="glass-panel p-6 rounded-2xl">
      {/* Header & Stats */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-5 border-b border-slate-800">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-bold uppercase tracking-wider px-2 py-0.5 rounded-full bg-indigo-900/60 text-indigo-300 border border-indigo-700/50">
              Cycle #{cycle_number}
            </span>
            {(tuitionTitle || cycle.tuition_title) && (
              <span className="text-xs font-bold px-2.5 py-0.5 rounded-full bg-indigo-500/20 text-indigo-300 border border-indigo-500/30 font-mono">
                {tuitionTitle || cycle.tuition_title}
              </span>
            )}
            <span className="text-xs text-slate-400 font-medium">
              for <strong className="text-slate-200">{studentName}</strong>
            </span>
            {is_complete && (
              <span className="text-xs font-semibold px-2 py-0.5 rounded-full bg-emerald-950 text-emerald-300 border border-emerald-500/30 flex items-center gap-1">
                <CheckCircle2 className="w-3.5 h-3.5" />
                Cycle Completed
              </span>
            )}
          </div>
          <h3 className="text-xl font-bold text-slate-100 mt-1">
            {(tuitionTitle || cycle.tuition_title) ? `${tuitionTitle || cycle.tuition_title} — ` : ''}Class Attendance & Billing Engine
          </h3>
        </div>

        {/* Action Button: Start New Cycle */}
        <button
          onClick={() => setResetModalOpen(true)}
          className={`px-4 py-2 rounded-xl text-xs font-semibold flex items-center gap-2 transition shadow-md ${
            is_complete
              ? 'bg-emerald-600 hover:bg-emerald-500 text-white shadow-emerald-600/30 animate-bounce'
              : 'bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700'
          }`}
        >
          <RotateCcw className="w-4 h-4" />
          <span>Start New Cycle</span>
        </button>
      </div>

      {/* Progress Bar & Financial Breakdown */}
      <div className="grid grid-cols-1 sm:grid-cols-4 gap-4 my-5 p-4 rounded-xl bg-slate-800/40 border border-slate-700/50">
        <div>
          <div className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider">
            Classes Completed
          </div>
          <div className="text-lg font-bold text-slate-100 mt-0.5">
            {completed_classes} <span className="text-sm text-slate-400 font-normal">/ {total_classes}</span>
          </div>
        </div>

        <div>
          <div className="text-[11px] font-semibold text-emerald-400 uppercase tracking-wider">
            Earned Revenue
          </div>
          <div className="text-lg font-bold text-emerald-400 mt-0.5">
            ৳{Number(earned_amount).toLocaleString()}
          </div>
        </div>

        <div>
          <div className="text-[11px] font-semibold text-indigo-400 uppercase tracking-wider">
            Pending Balance
          </div>
          <div className="text-lg font-bold text-indigo-300 mt-0.5">
            ৳{Number(pending_amount).toLocaleString()}
          </div>
        </div>

        <div>
          <div className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider">
            Progress
          </div>
          <div className="text-lg font-bold text-slate-200 mt-0.5">
            {progress_percentage}%
          </div>
          <div className="w-full h-1.5 bg-slate-700 rounded-full overflow-hidden mt-1.5">
            <div
              className="h-full bg-gradient-to-r from-emerald-500 to-indigo-500 transition-all duration-300"
              style={{ width: `${progress_percentage}%` }}
            />
          </div>
        </div>
      </div>

      {/* Interactive Checkbox Grid */}
      <div className="mb-2">
        <div className="flex flex-wrap items-center justify-between text-xs text-slate-400 mb-3 gap-2">
          <span className="flex items-center gap-1.5">
            <CalendarDays className="w-4 h-4 text-indigo-400" />
            Click any box to set attendance date and topic:
          </span>
          <span className="font-mono text-slate-300">
            Snapshot Rate: <strong className="text-emerald-400">৳{Math.round(fee_snapshot / total_classes)}</strong> / class
          </span>
        </div>

        <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8 gap-3">
          {classes_data.map((cls, idx) => {
            const cNum = cls.class_no ?? cls.classNo ?? (idx + 1);
            const isCompleted = cls.completed;
            const dateObj = cls.date ? new Date(cls.date) : null;
            const formattedDate = dateObj
              ? dateObj.toLocaleDateString(undefined, {
                  month: 'short',
                  day: 'numeric',
                })
              : null;

            return (
              <div
                key={cNum}
                onClick={() => handleOpenClassModal({ ...cls, classNo: cNum, class_no: cNum })}
                title={
                  isCompleted
                    ? `Class #${cNum}: Completed on ${dateObj?.toLocaleDateString()}${
                        cls.topic ? ` (${cls.topic})` : ''
                      } — Click to edit date`
                    : `Class #${cNum}: Click to record date & complete`
                }
                className={`relative group p-3 rounded-xl border flex flex-col items-center justify-center cursor-pointer select-none transition-all duration-200 transform hover:scale-[1.03] active:scale-95 ${
                  isCompleted
                    ? 'bg-gradient-to-br from-emerald-600/90 to-emerald-700 border-emerald-500 text-white shadow-lg shadow-emerald-600/20'
                    : 'bg-slate-800/60 border-slate-700/80 text-slate-400 hover:border-indigo-500/70 hover:text-slate-200 hover:bg-slate-800'
                }`}
              >
                <div className="flex items-center justify-between w-full text-xs font-bold font-mono">
                  <span>#{cNum}</span>
                  <CalendarDays className="w-3.5 h-3.5 opacity-40 group-hover:opacity-100 transition" />
                </div>

                <div className="my-1.5">
                  {isCompleted ? (
                    <Check className="w-5 h-5 stroke-[2.5]" />
                  ) : (
                    <div className="w-5 h-5 rounded-md border border-slate-600 group-hover:border-slate-400 transition" />
                  )}
                </div>

                <span
                  className={`text-[10px] font-medium truncate max-w-full text-center ${
                    isCompleted ? 'text-emerald-100' : 'text-slate-500 group-hover:text-slate-300'
                  }`}
                >
                  {formattedDate || 'Set Date'}
                </span>

                {cls.topic && (
                  <span className="text-[9px] text-emerald-200/80 truncate max-w-full mt-0.5">
                    {cls.topic}
                  </span>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* Class Attendance Date Selection Modal */}
      {selectedClass && (
        <Modal
          isOpen={dateModalOpen}
          onClose={() => setDateModalOpen(false)}
          title={`Class #${selectedClass.classNo} — Attendance Date & Topic`}
          maxWidth="max-w-md"
        >
          <form onSubmit={handleSaveClassAttendance} className="space-y-4">
            <div className="flex items-center justify-between p-3 rounded-xl bg-slate-900 border border-slate-800">
              <div>
                <span className="text-xs font-bold text-slate-200 block">Attendance Status</span>
                <span className="text-[11px] text-slate-400">
                  {isCompletedState ? 'Mark class as attended / completed' : 'Class will be unmarked as incomplete'}
                </span>
              </div>
              <div className="flex items-center gap-1 bg-slate-800 p-1 rounded-lg">
                <button
                  type="button"
                  onClick={() => setIsCompletedState(true)}
                  className={`px-3 py-1.5 rounded-md text-xs font-bold transition flex items-center gap-1 ${
                    isCompletedState ? 'bg-emerald-600 text-white shadow' : 'text-slate-400 hover:text-slate-200'
                  }`}
                >
                  <Check className="w-3.5 h-3.5" />
                  <span>Completed</span>
                </button>
                <button
                  type="button"
                  onClick={() => setIsCompletedState(false)}
                  className={`px-3 py-1.5 rounded-md text-xs font-bold transition flex items-center gap-1 ${
                    !isCompletedState ? 'bg-rose-600 text-white shadow' : 'text-slate-400 hover:text-slate-200'
                  }`}
                >
                  <X className="w-3.5 h-3.5" />
                  <span>Incomplete</span>
                </button>
              </div>
            </div>

            {isCompletedState ? (
              <div className="space-y-3 p-3.5 rounded-xl bg-slate-800/40 border border-slate-700/60">
                <div>
                  <div className="flex items-center justify-between mb-1">
                    <label className="text-xs font-bold text-slate-300 flex items-center gap-1.5">
                      <CalendarDays className="w-4 h-4 text-indigo-400" />
                      Class Date (Calendar) *
                    </label>
                    <div className="flex items-center gap-1">
                      <button
                        type="button"
                        onClick={() => setClassDate(new Date().toISOString().slice(0, 10))}
                        className="text-[10px] px-2 py-0.5 rounded bg-slate-800 hover:bg-slate-700 text-indigo-300 border border-slate-700 transition"
                      >
                        Today
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          const y = new Date();
                          y.setDate(y.getDate() - 1);
                          setClassDate(y.toISOString().slice(0, 10));
                        }}
                        className="text-[10px] px-2 py-0.5 rounded bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 transition"
                      >
                        Yesterday
                      </button>
                    </div>
                  </div>
                  <input
                    type="date"
                    required={isCompletedState}
                    value={classDate}
                    onChange={(e) => setClassDate(e.target.value)}
                    className="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs text-slate-100 font-mono focus:outline-none focus:border-indigo-500 cursor-pointer"
                  />
                  <span className="text-[10px] text-slate-400 block mt-1">
                    This exact date will appear in the student dashboard attendance record.
                  </span>
                </div>

                <div>
                  <label className="text-xs font-bold text-slate-300 block mb-1 flex items-center gap-1.5">
                    <BookOpen className="w-4 h-4 text-emerald-400" />
                    Lesson Topic / Note (Optional)
                  </label>
                  <input
                    type="text"
                    value={classTopic}
                    onChange={(e) => setClassTopic(e.target.value)}
                    placeholder="e.g. Chapter 4 Newton's Laws & Friction derivations"
                    className="w-full px-3 py-2 rounded-xl bg-slate-900 border border-slate-700 text-xs text-slate-100 focus:outline-none focus:border-indigo-500"
                  />
                </div>
              </div>
            ) : (
              <div className="p-3.5 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-300 text-xs flex items-center gap-2">
                <span>Saving will remove attendance and unmark this class.</span>
              </div>
            )}

            <div className="pt-2 flex items-center justify-between border-t border-slate-800">
              {selectedClass.completed ? (
                <button
                  type="button"
                  onClick={handleQuickUnmark}
                  disabled={savingClass}
                  className="px-3 py-1.5 rounded-xl border border-rose-500/30 text-rose-400 hover:bg-rose-500/10 text-xs font-semibold transition"
                >
                  Unmark Class
                </button>
              ) : (
                <button
                  type="button"
                  onClick={handleQuickMarkToday}
                  disabled={savingClass}
                  className="px-3 py-1.5 rounded-xl bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-300 border border-indigo-500/30 text-xs font-semibold transition"
                >
                  Mark Today ({new Date().toLocaleDateString(undefined, { month: 'short', day: 'numeric' })})
                </button>
              )}

              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => setDateModalOpen(false)}
                  className="px-3 py-1.5 rounded-xl border border-slate-700 text-slate-300 text-xs hover:bg-slate-800 transition"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={savingClass}
                  className="px-4 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs shadow-md shadow-indigo-600/30 transition disabled:opacity-50"
                >
                  {savingClass ? 'Saving...' : 'Save Attendance'}
                </button>
              </div>
            </div>
          </form>
        </Modal>
      )}

      {/* Start New Cycle Confirmation Modal */}
      <Modal
        isOpen={resetModalOpen}
        onClose={() => setResetModalOpen(false)}
        title="Start New Billing Cycle"
        maxWidth="max-w-md"
      >
        <div className="space-y-4">
          <div className="p-3 rounded-xl bg-amber-500/10 border border-amber-500/20 text-amber-300 text-sm flex items-start gap-3">
            <AlertTriangle className="w-5 h-5 flex-shrink-0 mt-0.5" />
            <div>
              <p className="font-semibold">Archive Cycle #{cycle_number}?</p>
              <p className="text-xs text-amber-200/80 mt-1">
                This will archive current attendance and initialize Cycle #{cycle_number + 1} with fresh fee snapshots.
              </p>
            </div>
          </div>

          <div className="text-xs text-slate-400 space-y-1">
            <div className="flex justify-between py-1 border-b border-slate-800">
              <span>Completed Classes:</span>
              <strong className="text-slate-200">
                {completed_classes} of {total_classes}
              </strong>
            </div>
            <div className="flex justify-between py-1 border-b border-slate-800">
              <span>Earned Amount:</span>
              <strong className="text-emerald-400">৳{Number(earned_amount).toLocaleString()}</strong>
            </div>
            <div className="flex justify-between py-1">
              <span>Next Cycle:</span>
              <strong className="text-indigo-400">Cycle #{cycle_number + 1}</strong>
            </div>
          </div>

          <div className="pt-3 flex items-center justify-end gap-3">
            <button
              onClick={() => setResetModalOpen(false)}
              className="px-4 py-2 rounded-xl border border-slate-700 text-slate-300 text-xs hover:bg-slate-800 transition"
            >
              Cancel
            </button>
            <button
              onClick={handleConfirmReset}
              disabled={resetting}
              className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs shadow-md shadow-indigo-600/30 flex items-center gap-1.5 transition disabled:opacity-50"
            >
              {resetting ? 'Archiving & Initializing...' : 'Confirm & Start New Cycle'}
            </button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
