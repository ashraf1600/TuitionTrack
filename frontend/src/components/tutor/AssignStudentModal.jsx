import React, { useState } from 'react';
import Modal from '../common/Modal';
import { api } from '../../api/client';
import { Users, CheckCircle2, AlertCircle, BookOpen, Calendar, Clock, DollarSign, Sparkles } from 'lucide-react';

export default function AssignStudentModal({
  isOpen,
  onClose,
  student,
  tuitions = [],
  onAssigned,
}) {
  const [selectedTuitionId, setSelectedTuitionId] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  if (!student) return null;

  const handleAssign = async (e) => {
    e.preventDefault();
    if (!selectedTuitionId) {
      setError('Please select a Tuition to assign this student.');
      return;
    }

    setLoading(true);
    setError('');
    try {
      await api.enrollInTuition(selectedTuitionId, student.id);
      if (onAssigned) onAssigned();
      onClose();
    } catch (err) {
      setError(err.message || 'Failed to assign student to tuition.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Assign Prospective Student to Tuition" maxWidth="max-w-lg">
      <form onSubmit={handleAssign} className="space-y-5">
        {/* Student Snapshot Card */}
        <div className="p-4 rounded-2xl bg-slate-800/60 border border-slate-700/60 flex items-start gap-3.5">
          <div className="w-11 h-11 rounded-xl bg-indigo-600/20 text-indigo-400 flex items-center justify-center font-bold text-base border border-indigo-500/20 flex-shrink-0">
            {student.full_name?.charAt(0) || student.username?.charAt(0) || 'S'}
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <h4 className="font-bold text-slate-100 text-sm truncate">{student.full_name}</h4>
              <span className="text-[11px] font-mono text-slate-400">@{student.username}</span>
            </div>
            <div className="grid grid-cols-2 gap-x-2 gap-y-0.5 text-xs text-slate-400 mt-1.5">
              <div>Grade: <span className="text-slate-200">{student.grade_level || 'N/A'}</span></div>
              <div>School: <span className="text-slate-200 truncate">{student.institution || 'N/A'}</span></div>
              <div>Guardian: <span className="text-slate-200">{student.parent_phone || student.phone || 'N/A'}</span></div>
              <div>Applied: <span className="text-slate-200">{new Date(student.created_at).toLocaleDateString()}</span></div>
            </div>
          </div>
        </div>

        {error && (
          <div className="p-3 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs flex items-center gap-2">
            <AlertCircle className="w-4 h-4 flex-shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {/* Tuition Selection */}
        <div>
          <label className="block text-xs font-semibold text-slate-300 mb-2">
            Choose Target Tuition *
          </label>

          {tuitions.length === 0 ? (
            <div className="p-4 rounded-xl bg-slate-800/40 border border-slate-700/50 text-center text-xs text-slate-400">
              <p>No Tuitions created yet.</p>
              <p className="mt-1 text-slate-500">Create a Tuition first from the "Tuitions & Routine" tab.</p>
            </div>
          ) : (
            <div className="space-y-2 max-h-56 overflow-y-auto p-1">
              {tuitions.map((t) => {
                const isSelected = selectedTuitionId === t.id;
                return (
                  <div
                    key={t.id}
                    onClick={() => setSelectedTuitionId(t.id)}
                    className={`p-3.5 rounded-xl border cursor-pointer transition flex items-center justify-between ${
                      isSelected
                        ? 'bg-indigo-600/15 border-indigo-500 text-white shadow-sm'
                        : 'bg-slate-800/40 border-slate-700/60 hover:bg-slate-800 text-slate-300'
                    }`}
                  >
                    <div>
                      <div className="font-bold text-sm text-slate-100 flex items-center gap-2">
                        <span>{t.title}</span>
                        {isSelected && (
                          <span className="text-[10px] bg-indigo-500 text-white font-semibold px-2 py-0.5 rounded-full">
                            Selected
                          </span>
                        )}
                      </div>
                      <div className="flex items-center gap-3 text-xs text-slate-400 mt-1">
                        <span className="flex items-center gap-1">
                          <Clock className="w-3.5 h-3.5 text-indigo-400" />
                          {t.cycle_length} Classes / Cycle
                        </span>
                        <span className="flex items-center gap-1 font-mono text-emerald-400 font-semibold">
                          ৳{Number(t.tuition_fee).toLocaleString()}
                        </span>
                        <span className="text-slate-500">
                          {t.enrolled_count || 0} students
                        </span>
                      </div>
                    </div>

                    <div className={`w-5 h-5 rounded-full border flex items-center justify-center transition ${
                      isSelected ? 'border-indigo-500 bg-indigo-600 text-white' : 'border-slate-600'
                    }`}>
                      {isSelected && <CheckCircle2 className="w-3.5 h-3.5" />}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        <div className="p-3 rounded-xl bg-indigo-500/10 border border-indigo-500/20 text-xs text-indigo-300">
          <p className="font-semibold text-white mb-0.5 flex items-center gap-1.5">
            <Sparkles className="w-4 h-4 text-indigo-400" />
            Automatic Attendance & Cycle Initialization
          </p>
          <p className="text-[11px] text-slate-400">
            Enrolling will immediately initialize <strong>Attendance Cycle #1</strong> with the tuition's cycle length and weekly routine schedule for this student.
          </p>
        </div>

        {/* Buttons */}
        <div className="flex justify-end gap-3 pt-3 border-t border-slate-800">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 rounded-xl text-xs font-semibold text-slate-400 hover:text-slate-200 transition"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={loading || !selectedTuitionId}
            className="px-5 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white text-xs font-bold transition flex items-center gap-2 shadow-lg shadow-indigo-600/30"
          >
            {loading ? 'Enrolling...' : 'Confirm Enrollment'}
          </button>
        </div>
      </form>
    </Modal>
  );
}
