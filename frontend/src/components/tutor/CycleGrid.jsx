import React, { useState } from 'react';
import { Check, RotateCcw, AlertTriangle, Calendar, CheckCircle2, Clock } from 'lucide-react';
import Modal from '../common/Modal';

export default function CycleGrid({
  cycle,
  studentName,
  onToggleClass,
  onResetCycle,
  loading,
}) {
  const [resetModalOpen, setResetModalOpen] = useState(false);
  const [resetting, setResetting] = useState(false);
  const [togglingClassNo, setTogglingClassNo] = useState(null);

  if (!cycle) {
    return (
      <div className="glass-panel p-8 rounded-2xl text-center text-slate-400">
        <Calendar className="w-12 h-12 mx-auto text-slate-600 mb-2" />
        <p className="text-base font-semibold text-slate-300">No active cycle selected</p>
        <p className="text-xs text-slate-500 mt-1">
          Select a student from the roster on the left to view and check off classes.
        </p>
      </div>
    );
  }

  const {
    cycle_number,
    fee_snapshot,
    total_classes,
    completed_classes,
    earned_amount,
    pending_amount,
    progress_percentage,
    is_complete,
    classes_data = [],
  } = cycle;

  const handleToggle = async (classNo, currentCompleted) => {
    setTogglingClassNo(classNo);
    try {
      await onToggleClass(cycle.id, classNo, !currentCompleted);
    } finally {
      setTogglingClassNo(null);
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
          <div className="flex items-center gap-2">
            <span className="text-xs font-bold uppercase tracking-wider px-2 py-0.5 rounded-full bg-indigo-900/60 text-indigo-300 border border-indigo-700/50">
              Cycle #{cycle_number}
            </span>
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
            Class Attendance & Billing Engine
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
        <div className="flex items-center justify-between text-xs text-slate-400 mb-3">
          <span>Click any box to mark as completed or uncheck:</span>
          <span>Snapshot Rate: ৳{Math.round(fee_snapshot / total_classes)} / class</span>
        </div>

        <div className="grid grid-cols-4 sm:grid-cols-6 lg:grid-cols-8 gap-3">
          {classes_data.map((cls) => {
            const isCompleted = cls.completed;
            const isToggling = togglingClassNo === cls.classNo;
            const formattedDate = cls.date
              ? new Date(cls.date).toLocaleDateString(undefined, {
                  month: 'short',
                  day: 'numeric',
                  hour: '2-digit',
                  minute: '2-digit',
                })
              : null;

            return (
              <div
                key={cls.classNo}
                onClick={() => !isToggling && handleToggle(cls.classNo, isCompleted)}
                title={formattedDate ? `Completed: ${formattedDate}` : 'Click to complete'}
                className={`relative group p-3 rounded-xl border flex flex-col items-center justify-center cursor-pointer select-none transition-all duration-200 transform active:scale-95 ${
                  isCompleted
                    ? 'bg-gradient-to-br from-emerald-600 to-emerald-700 border-emerald-500 text-white shadow-lg shadow-emerald-600/20 hover:brightness-110'
                    : 'bg-slate-800/60 border-slate-700/80 text-slate-400 hover:border-slate-500 hover:text-slate-200 hover:bg-slate-800'
                } ${isToggling ? 'opacity-50 animate-pulse' : ''}`}
              >
                <div className="text-xs font-bold font-mono">
                  #{cls.classNo}
                </div>

                <div className="mt-1">
                  {isCompleted ? (
                    <Check className="w-5 h-5 stroke-[2.5]" />
                  ) : (
                    <div className="w-5 h-5 rounded-md border border-slate-600 group-hover:border-slate-400 transition" />
                  )}
                </div>

                {formattedDate && (
                  <span className="text-[9px] text-emerald-100 font-medium mt-1 truncate max-w-full">
                    {formattedDate.split(',')[0]}
                  </span>
                )}
              </div>
            );
          })}
        </div>
      </div>

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
              <strong className="text-slate-200">{completed_classes} of {total_classes}</strong>
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
