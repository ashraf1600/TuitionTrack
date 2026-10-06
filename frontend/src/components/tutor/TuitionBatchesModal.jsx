import React, { useState, useEffect } from 'react';
import Modal from '../common/Modal';
import { api } from '../../api/client';
import {
  Users,
  Calendar,
  Plus,
  Trash2,
  Clock,
  Check,
  AlertCircle,
  Sparkles,
  UserPlus,
  Search,
  X,
  BookOpen,
  DollarSign,
} from 'lucide-react';

const DAYS_OF_WEEK = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

export default function TuitionBatchesModal({
  isOpen,
  onClose,
  allStudents = [],
  batchToEdit = null,
  onBatchSaved,
}) {
  const [name, setName] = useState('');
  const [subject, setSubject] = useState('');
  const [description, setDescription] = useState('');
  const [monthlyFee, setMonthlyFee] = useState('5000.00');
  const [selectedStudentIds, setSelectedStudentIds] = useState([]);
  const [weeklyRoutine, setWeeklyRoutine] = useState([
    { day: 'Sunday', time: '18:00' },
    { day: 'Tuesday', time: '18:00' },
  ]);

  // Slot being added
  const [slotDay, setSlotDay] = useState('Sunday');
  const [slotTime, setSlotTime] = useState('18:00');

  // Student Search & Inline Quick Register
  const [studentSearch, setStudentSearch] = useState('');
  const [showAddStudentForm, setShowAddStudentForm] = useState(false);
  const [newStudentFirst, setNewStudentFirst] = useState('');
  const [newStudentLast, setNewStudentLast] = useState('');
  const [newStudentUsername, setNewStudentUsername] = useState('');
  const [newStudentEmail, setNewStudentEmail] = useState('');
  const [newStudentPhone, setNewStudentPhone] = useState('');
  const [newStudentGrade, setNewStudentGrade] = useState('HSC-2026');
  const [creatingStudent, setCreatingStudent] = useState(false);

  // Local student list in case new student is added
  const [studentsList, setStudentsList] = useState(allStudents);

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    setStudentsList(allStudents);
  }, [allStudents]);

  useEffect(() => {
    if (batchToEdit) {
      setName(batchToEdit.name || '');
      setSubject(batchToEdit.subject || '');
      setDescription(batchToEdit.description || '');
      setMonthlyFee(batchToEdit.monthly_fee || '5000.00');
      setSelectedStudentIds(batchToEdit.students || []);
      setWeeklyRoutine(batchToEdit.weekly_routine || []);
    } else {
      setName('');
      setSubject('');
      setDescription('');
      setMonthlyFee('5000.00');
      setSelectedStudentIds([]);
      setWeeklyRoutine([
        { day: 'Sunday', time: '18:00' },
        { day: 'Tuesday', time: '18:00' },
      ]);
    }
    setShowAddStudentForm(false);
    setError('');
  }, [batchToEdit, isOpen]);

  const toggleStudent = (id) => {
    setSelectedStudentIds((prev) =>
      prev.includes(id) ? prev.filter((s) => s !== id) : [...prev, id]
    );
  };

  const removeStudent = (id) => {
    setSelectedStudentIds((prev) => prev.filter((s) => s !== id));
  };

  const addRoutineSlot = () => {
    if (weeklyRoutine.some((s) => s.day === slotDay && s.time === slotTime)) {
      return;
    }
    setWeeklyRoutine((prev) => [...prev, { day: slotDay, time: slotTime }]);
  };

  const removeRoutineSlot = (index) => {
    setWeeklyRoutine((prev) => prev.filter((_, i) => i !== index));
  };

  // Quick Register Student Directly into Batch
  const handleCreateAndEnrollStudent = async (e) => {
    e.preventDefault();
    if (!newStudentFirst || !newStudentUsername) {
      alert('Please provide student first name and username.');
      return;
    }

    setCreatingStudent(true);
    try {
      const res = await api.createStudent({
        username: newStudentUsername.trim().toLowerCase(),
        first_name: newStudentFirst.trim(),
        last_name: newStudentLast.trim(),
        email: newStudentEmail.trim() || `${newStudentUsername.trim().toLowerCase()}@tuitiontrack.local`,
        password: 'pass' + Math.floor(100000 + Math.random() * 900000),
        phone: newStudentPhone.trim(),
        grade_level: newStudentGrade.trim(),
        total_classes: 12,
        fee_amount: parseFloat(monthlyFee) || 5000,
      });

      const newStudentObj = {
        student_id: res.student.id,
        username: res.student.username,
        full_name: `${newStudentFirst} ${newStudentLast}`.trim(),
        email: res.student.email,
        phone: newStudentPhone,
        profile: { grade_level: newStudentGrade },
      };

      setStudentsList((prev) => [newStudentObj, ...prev]);
      setSelectedStudentIds((prev) => [...prev, res.student.id]);

      // Reset form
      setNewStudentFirst('');
      setNewStudentLast('');
      setNewStudentUsername('');
      setNewStudentEmail('');
      setNewStudentPhone('');
      setShowAddStudentForm(false);
    } catch (err) {
      alert(`Failed to add student: ${err.message}`);
    } finally {
      setCreatingStudent(false);
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');

    if (!name.trim()) {
      setError('Please enter a tuition batch name.');
      return;
    }

    setLoading(true);
    try {
      const payload = {
        name,
        subject,
        description,
        monthly_fee: parseFloat(monthlyFee) || 0,
        student_ids: selectedStudentIds,
        weekly_routine: weeklyRoutine,
      };

      if (batchToEdit) {
        await api.updateBatch(batchToEdit.id, payload);
      } else {
        await api.createBatch(payload);
      }

      onBatchSaved();
      onClose();
    } catch (err) {
      setError(err.message || 'Failed to save tuition batch.');
    } finally {
      setLoading(false);
    }
  };

  const filteredStudents = studentsList.filter((st) => {
    const q = studentSearch.toLowerCase();
    return (
      st.full_name?.toLowerCase().includes(q) ||
      st.username?.toLowerCase().includes(q) ||
      st.email?.toLowerCase().includes(q)
    );
  });

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={batchToEdit ? `Edit Tuition Batch — ${batchToEdit.name}` : 'Create New Tuition Batch & Routine'}
      maxWidth="max-w-3xl"
    >
      <form onSubmit={handleSubmit} className="space-y-5">
        {error && (
          <div className="p-3 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs flex items-center gap-2">
            <AlertCircle className="w-4 h-4 flex-shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {/* Basic Batch Fields */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Tuition / Batch Name *
            </label>
            <input
              type="text"
              required
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. HSC Physics 2026 Batch A"
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Subject
            </label>
            <input
              type="text"
              value={subject}
              onChange={(e) => setSubject(e.target.value)}
              placeholder="e.g. Higher Math / Physics"
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500"
            />
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Monthly Fee per Student (৳ BDT)
            </label>
            <input
              type="number"
              min="0"
              value={monthlyFee}
              onChange={(e) => setMonthlyFee(e.target.value)}
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-emerald-400 font-bold text-sm focus:outline-none focus:border-indigo-500"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Description / Notes
            </label>
            <input
              type="text"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="e.g. Saturday & Tuesday evening classes"
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500"
            />
          </div>
        </div>

        {/* Section 1: Weekly Routine Schedule */}
        <div className="p-4 rounded-xl bg-slate-800/40 border border-slate-700/60 space-y-3">
          <div className="flex items-center justify-between">
            <h4 className="text-xs font-bold text-indigo-300 uppercase tracking-wider flex items-center gap-1.5">
              <Calendar className="w-4 h-4 text-indigo-400" />
              Weekly Routine Schedule (Tuition Days & Times)
            </h4>
            <span className="text-[11px] text-slate-400">
              {weeklyRoutine.length} classes scheduled / week
            </span>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <select
              value={slotDay}
              onChange={(e) => setSlotDay(e.target.value)}
              className="px-3 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-xs text-slate-200"
            >
              {DAYS_OF_WEEK.map((d) => (
                <option key={d} value={d}>
                  {d}
                </option>
              ))}
            </select>

            <input
              type="time"
              value={slotTime}
              onChange={(e) => setSlotTime(e.target.value)}
              className="px-3 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-xs text-slate-200"
            />

            <button
              type="button"
              onClick={addRoutineSlot}
              className="px-3 py-1.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold flex items-center gap-1 transition"
            >
              <Plus className="w-3.5 h-3.5" />
              <span>Add Day & Time</span>
            </button>
          </div>

          {/* Active Schedule Slots List */}
          <div className="flex flex-wrap gap-2 pt-1">
            {weeklyRoutine.length === 0 ? (
              <span className="text-xs text-slate-500 italic">No routine days added yet</span>
            ) : (
              weeklyRoutine.map((slot, idx) => (
                <div
                  key={idx}
                  className="flex items-center gap-2 px-3 py-1.5 rounded-xl bg-slate-800 border border-slate-700 text-xs text-slate-200"
                >
                  <Clock className="w-3.5 h-3.5 text-indigo-400" />
                  <span className="font-semibold text-slate-100">{slot.day}</span>
                  <span className="text-slate-400">@ {slot.time}</span>
                  <button
                    type="button"
                    onClick={() => removeRoutineSlot(idx)}
                    className="text-slate-400 hover:text-rose-400 ml-1"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                </div>
              ))
            )}
          </div>
        </div>

        {/* Section 2: Enroll Students (Search, Select & Direct Register) */}
        <div className="space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <label className="text-xs font-bold text-slate-300 uppercase tracking-wider flex items-center gap-1.5">
              <Users className="w-4 h-4 text-emerald-400" />
              Manage Students ({selectedStudentIds.length} Enrolled)
            </label>

            <button
              type="button"
              onClick={() => setShowAddStudentForm(!showAddStudentForm)}
              className="px-2.5 py-1 rounded-lg bg-emerald-600/20 hover:bg-emerald-600/30 text-emerald-300 border border-emerald-500/30 text-xs font-semibold flex items-center gap-1 transition"
            >
              <UserPlus className="w-3.5 h-3.5" />
              <span>{showAddStudentForm ? 'Cancel Add Student' : '+ Register New Student Here'}</span>
            </button>
          </div>

          {/* Quick Add Student Inline Form */}
          {showAddStudentForm && (
            <div className="p-3.5 rounded-xl bg-slate-900 border border-emerald-500/40 space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-emerald-300 flex items-center gap-1.5">
                  <UserPlus className="w-4 h-4" />
                  Register & Auto-Enroll Student Directly
                </span>
                <button
                  type="button"
                  onClick={() => setShowAddStudentForm(false)}
                  className="text-slate-400 hover:text-slate-200 text-xs"
                >
                  ✕
                </button>
              </div>

              <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                <input
                  type="text"
                  placeholder="First Name *"
                  value={newStudentFirst}
                  onChange={(e) => setNewStudentFirst(e.target.value)}
                  className="px-2.5 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-xs text-slate-100"
                />
                <input
                  type="text"
                  placeholder="Last Name"
                  value={newStudentLast}
                  onChange={(e) => setNewStudentLast(e.target.value)}
                  className="px-2.5 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-xs text-slate-100"
                />
                <input
                  type="text"
                  placeholder="Username *"
                  value={newStudentUsername}
                  onChange={(e) => setNewStudentUsername(e.target.value)}
                  className="px-2.5 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-xs text-slate-100 font-mono"
                />
                <input
                  type="text"
                  placeholder="Grade (e.g. HSC-2026)"
                  value={newStudentGrade}
                  onChange={(e) => setNewStudentGrade(e.target.value)}
                  className="px-2.5 py-1.5 rounded-lg bg-slate-800 border border-slate-700 text-xs text-slate-100"
                />
              </div>

              <div className="flex items-center justify-between pt-1">
                <span className="text-[10px] text-slate-400">
                  Initializes Cycle #1 and automatically adds them to this batch.
                </span>
                <button
                  type="button"
                  onClick={handleCreateAndEnrollStudent}
                  disabled={creatingStudent}
                  className="px-3 py-1.5 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold shadow flex items-center gap-1 transition"
                >
                  {creatingStudent ? 'Creating...' : 'Enroll Student'}
                </button>
              </div>
            </div>
          )}

          {/* Enrolled Students Badges */}
          {selectedStudentIds.length > 0 && (
            <div className="flex flex-wrap gap-1.5 p-2 rounded-xl bg-slate-900/40 border border-slate-800 max-h-24 overflow-y-auto">
              {selectedStudentIds.map((stId) => {
                const st = studentsList.find((s) => s.student_id === stId);
                if (!st) return null;
                return (
                  <span
                    key={stId}
                    className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-indigo-950/60 border border-indigo-500/40 text-xs text-indigo-200"
                  >
                    <span>{st.full_name}</span>
                    <button
                      type="button"
                      onClick={() => removeStudent(stId)}
                      className="text-indigo-400 hover:text-rose-400 ml-0.5"
                    >
                      <X className="w-3 h-3" />
                    </button>
                  </span>
                );
              })}
            </div>
          )}

          {/* Student Search & Checklist */}
          <div className="relative">
            <Search className="w-3.5 h-3.5 text-slate-500 absolute left-3 top-2.5" />
            <input
              type="text"
              placeholder="Search existing students by name or username..."
              value={studentSearch}
              onChange={(e) => setStudentSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-1.5 rounded-xl bg-slate-800/80 border border-slate-700 text-xs text-slate-200 focus:outline-none focus:border-indigo-500"
            />
          </div>

          <div className="max-h-[170px] overflow-y-auto rounded-xl border border-slate-700 bg-slate-900/60 p-2 space-y-1.5">
            {filteredStudents.length === 0 ? (
              <p className="text-xs text-slate-500 p-2 text-center">
                {studentSearch ? 'No matching students found.' : 'No students found. Use "+ Register New Student Here" above.'}
              </p>
            ) : (
              filteredStudents.map((st) => {
                const isSelected = selectedStudentIds.includes(st.student_id);
                return (
                  <div
                    key={st.student_id}
                    onClick={() => toggleStudent(st.student_id)}
                    className={`flex items-center justify-between p-2 rounded-lg cursor-pointer transition text-xs ${
                      isSelected
                        ? 'bg-indigo-950/60 border border-indigo-500/40 text-slate-100'
                        : 'bg-slate-800/40 border border-transparent text-slate-300 hover:bg-slate-800'
                    }`}
                  >
                    <div>
                      <span className="font-semibold">{st.full_name}</span>{' '}
                      <span className="text-slate-500 font-mono text-[11px]">(@{st.username})</span>
                      {st.profile?.grade_level && (
                        <span className="ml-2 text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-slate-400">
                          {st.profile.grade_level}
                        </span>
                      )}
                    </div>

                    <div
                      className={`w-4 h-4 rounded flex items-center justify-center border ${
                        isSelected ? 'bg-indigo-600 border-indigo-500 text-white' : 'border-slate-600'
                      }`}
                    >
                      {isSelected && <Check className="w-3 h-3" />}
                    </div>
                  </div>
                );
              })
            )}
          </div>
        </div>

        {/* Action Buttons */}
        <div className="pt-3 border-t border-slate-800 flex items-center justify-end gap-3">
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
            className="px-5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs shadow-lg shadow-indigo-600/30 flex items-center gap-1.5 transition disabled:opacity-50"
          >
            {loading ? 'Saving Tuition Batch...' : batchToEdit ? 'Update Tuition Batch' : 'Create Tuition Batch'}
          </button>
        </div>
      </form>
    </Modal>
  );
}
