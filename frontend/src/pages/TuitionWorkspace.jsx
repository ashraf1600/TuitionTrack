import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { notify } from '../utils/toast';
import Navbar from '../components/common/Navbar';
import AddStudentModal from '../components/tutor/AddStudentModal';
import SharedCycleBoard from '../components/tutor/SharedCycleBoard';
import ExamManager from '../components/tutor/ExamManager';
import TuitionBatchesModal from '../components/tutor/TuitionBatchesModal';
import ExamAuthoringModal from '../components/tutor/ExamAuthoringModal';
import StudentCredentialsModal from '../components/tutor/StudentCredentialsModal';
import HomeworkManager from '../components/tutor/HomeworkManager';
import Modal from '../components/common/Modal';
import { api } from '../api/client';
import { useAuth } from '../context/AuthContext';
import {
  ArrowLeft, Calendar, Clock, DollarSign, Users, Layers,
  FileText, Plus, RotateCcw, CheckCircle2, Check, AlertCircle,
  Award, Key, Trophy, Edit2, Trash2, UserPlus, Mail, Phone,
  Sparkles, CalendarDays, X, ChevronRight, RefreshCw, Search,
  BookOpen, Settings, CheckSquare
} from 'lucide-react';
import { formatTaka } from '../utils/dates';

const DAYS_ORDER = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

/**
 * Screen 2: The "Tuition Manager Workspace" (Detail View)
 *
 * Dedicated, isolated workspace for a specific tuition group.
 * Header: Tuition Name + "Back to My Tuitions"
 * Organized strictly into 4 sections:
 *   1. Class Tracker: Dynamic 12-class grid to mark classes done (updates wallet live).
 *   2. Student Roster: Enrolled students + accept Pending Requests via tutor_code.
 *   3. Assessments: Create and grade Homework, Assignments, and Exams strictly for this batch.
 *   4. Routine & Settings: Weekly schedule editor, tuition fee, and cycle length.
 */
export default function TuitionWorkspace() {
  const { id: tuitionId } = useParams();
  const navigate = useNavigate();
  const { user } = useAuth();

  // 4 Exact Tabs in Order
  // 'tracker' | 'roster' | 'assessments' | 'settings'
  const [activeTab, setActiveTab] = useState('tracker');

  // Core Data
  const [tuition, setTuition] = useState(null);
  const [cycles, setCycles] = useState([]);
  const [exams, setExams] = useState([]);
  const [homework, setHomework] = useState([]);
  const [unassignedStudents, setUnassignedStudents] = useState([]);
  const [allStudents, setAllStudents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  // Assessment sub-filter
  const [assessmentFilter, setAssessmentFilter] = useState('all'); // 'all' | 'exams' | 'homework'

  // Modals
  const [addStudentModalOpen, setAddStudentModalOpen] = useState(false);
  const [editTuitionModalOpen, setEditTuitionModalOpen] = useState(false);
  const [authorExamModalOpen, setAuthorExamModalOpen] = useState(false);
  const [authorCategory, setAuthorCategory] = useState('EXAM');
  const [selectedStudentForCredentials, setSelectedStudentForCredentials] = useState(null);
  const [enrollExistingModalOpen, setEnrollExistingModalOpen] = useState(false);
  const [enrollSearch, setEnrollSearch] = useState('');
  const [enrollingStudentId, setEnrollingStudentId] = useState(null);

  // Routine Slot Editor State
  const [routineSlots, setRoutineSlots] = useState([]);
  const [newSlotDay, setNewSlotDay] = useState('Sunday');
  const [newSlotStart, setNewSlotStart] = useState('18:00');
  const [newSlotEnd, setNewSlotEnd] = useState('19:30');
  const [savingRoutine, setSavingRoutine] = useState(false);

  // Load Tuition Data
  const loadTuitionData = useCallback(async () => {
    if (!tuitionId) return;
    try {
      setLoading(true);
      setError('');

      // 1. Fetch Tuition Detail
      const tData = await api.getTuitionDetail(tuitionId);
      setTuition(tData);
      setRoutineSlots(tData.routine || []);

      // 2. Fetch Attendance Cycles
      try {
        const cData = await api.getAttendanceCycles(tuitionId);
        const cycleList = Array.isArray(cData) ? cData : cData.results || [];
        setCycles(cycleList);
      } catch (cErr) {
        console.error('Failed to load cycles for tuition:', cErr);
      }

      // 3. Fetch Exams assigned to this Tuition
      try {
        const eData = await api.getExams(null, null, tuitionId);
        const examList = Array.isArray(eData) ? eData : eData.results || [];
        setExams(examList);
      } catch (eErr) {
        console.error('Failed to load exams for tuition:', eErr);
      }

      // 4. Fetch Homework assigned to this Tuition
      try {
        const hwData = await api.getHomework();
        const hwList = Array.isArray(hwData) ? hwData : hwData.results || [];
        setHomework(hwList.filter((h) => String(h.tuition_id || h.tuition?.id) === String(tuitionId)));
      } catch (hErr) {
        console.error('Failed to load homework for tuition:', hErr);
      }

      // 5. Fetch Unassigned Students & All Students (for roster assignment)
      try {
        const uData = await api.getUnassignedStudents();
        setUnassignedStudents(Array.isArray(uData) ? uData : uData.results || []);
      } catch (_) {}

      try {
        const sData = await api.getStudents();
        setAllStudents(Array.isArray(sData) ? sData : sData.results || []);
      } catch (_) {}
    } catch (err) {
      setError(err.message || 'Failed to load tuition workspace.');
    } finally {
      setLoading(false);
    }
  }, [tuitionId]);

  useEffect(() => {
    loadTuitionData();
  }, [loadTuitionData]);

  const activeCycle = tuition?.active_cycle || null;
  const wallet = tuition?.wallet_summary || {};
  const pastCycles = useMemo(
    () => (cycles || []).filter((c) => c.status === 'ARCHIVED').sort((a, b) => b.cycle_number - a.cycle_number),
    [cycles]
  );

  const handleCycleChange = (cycle) => {
    setTuition((prev) => (prev ? { ...prev, active_cycle: cycle } : prev));
    loadTuitionData();
  };

  const handleUnenrollStudent = async (studentId, studentName) => {
    if (!confirm(`Remove ${studentName} from "${tuition.title}"? They will stop seeing this group's classes and exams.`)) {
      return;
    }
    try {
      await api.unenrollFromTuition(tuitionId, studentId);
      await loadTuitionData();
      notify.success(`${studentName} removed from batch.`);
    } catch (err) {
      notify(`Failed to remove student: ${err.message}`);
    }
  };

  const handleEnrollExistingStudent = async (studentId) => {
    try {
      setEnrollingStudentId(studentId);
      await api.enrollInTuition(tuitionId, studentId);
      await loadTuitionData();
      notify.success('Student assigned to this batch.');
      setEnrollExistingModalOpen(false);
    } catch (err) {
      notify(`Failed to enroll student: ${err.message}`);
    } finally {
      setEnrollingStudentId(null);
    }
  };

  const handleSaveRoutine = async () => {
    setSavingRoutine(true);
    try {
      await api.updateTuition(tuitionId, { routine: routineSlots });
      await loadTuitionData();
      notify.success('Weekly routine updated.');
    } catch (err) {
      notify(`Failed to save routine: ${err.message}`);
    } finally {
      setSavingRoutine(false);
    }
  };

  const handleAddRoutineSlot = () => {
    setRoutineSlots((prev) => [
      ...prev,
      { day: newSlotDay, start_time: newSlotStart, end_time: newSlotEnd },
    ]);
  };

  const handleRemoveRoutineSlot = (index) => {
    setRoutineSlots((prev) => prev.filter((_, i) => i !== index));
  };

  const enrolledStudents = useMemo(() => tuition?.enrollments || [], [tuition]);

  const candidateStudents = useMemo(() => {
    const enrolledIds = new Set((enrolledStudents || []).map((e) => String(e.student_id || e.id)));
    const map = new Map();
    [...(allStudents || []), ...(unassignedStudents || [])].forEach((s) => {
      const sid = String(s.student_id || s.id);
      if (sid && !enrolledIds.has(sid) && !map.has(sid)) {
        map.set(sid, s);
      }
    });
    return Array.from(map.values());
  }, [enrolledStudents, allStudents, unassignedStudents]);

  const filteredCandidates = useMemo(() => {
    if (!enrollSearch.trim()) return candidateStudents;
    const q = enrollSearch.toLowerCase();
    return candidateStudents.filter((s) =>
      (s.full_name || s.username || '').toLowerCase().includes(q) ||
      (s.email || '').toLowerCase().includes(q) ||
      (s.profile?.grade_level || s.grade_level || '').toLowerCase().includes(q)
    );
  }, [candidateStudents, enrollSearch]);

  if (loading && !tuition) {
    return (
      <div className="min-h-screen bg-slate-50 text-slate-900 flex flex-col font-sans">
        <Navbar />
        <div className="flex-1 flex items-center justify-center py-20">
          <div className="flex flex-col items-center gap-3">
            <div className="w-10 h-10 rounded-full border-4 border-indigo-200 border-t-indigo-600 animate-spin" />
            <p className="text-xs text-slate-500 font-semibold">Loading Tuition Workspace...</p>
          </div>
        </div>
      </div>
    );
  }

  if (error || !tuition) {
    return (
      <div className="min-h-screen bg-slate-50 text-slate-900 flex flex-col font-sans">
        <Navbar />
        <div className="flex-1 max-w-xl mx-auto px-4 py-20 text-center space-y-4">
          <AlertCircle className="w-12 h-12 text-rose-500 mx-auto" />
          <h2 className="text-xl font-bold text-slate-900">Tuition Not Found</h2>
          <p className="text-sm text-slate-500">{error || 'This tuition does not exist or you do not have permission.'}</p>
          <Link
            to="/tutor"
            className="inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-indigo-600 text-white text-xs font-bold hover:bg-indigo-700 transition"
          >
            <ArrowLeft className="w-4 h-4" />
            <span>Back to My Tuitions</span>
          </Link>
        </div>
      </div>
    );
  }

  const completedClasses = wallet.completed_classes ?? 0;
  const totalClasses = wallet.total_classes ?? tuition.cycle_length ?? 12;

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900 flex flex-col font-sans selection:bg-indigo-500 selection:text-white">
      <Navbar />

      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6 sm:py-8 space-y-6">
        {/* ── Top Navigation & Back to My Tuitions CTA ── */}
        <div className="flex items-center justify-between gap-4">
          <Link
            to="/tutor"
            className="inline-flex items-center gap-2 px-3.5 py-2 rounded-xl bg-white border border-slate-200/90 shadow-sm text-xs sm:text-sm font-semibold text-slate-700 hover:text-indigo-600 hover:border-indigo-300 hover:bg-slate-50 transition-all duration-150 group"
          >
            <ArrowLeft className="w-4 h-4 group-hover:-translate-x-1 transition-transform" />
            <span>Back to My Tuitions</span>
          </Link>

          <div className="flex items-center gap-2">
            <button
              onClick={() => setEditTuitionModalOpen(true)}
              className="px-3 py-2 rounded-xl bg-white hover:bg-slate-50 text-slate-700 border border-slate-200 text-xs font-semibold flex items-center gap-1.5 transition shadow-xs"
              title="Edit Tuition Settings"
            >
              <Settings className="w-3.5 h-3.5 text-slate-500" />
              <span className="hidden sm:inline">Settings</span>
            </button>
            <button
              onClick={loadTuitionData}
              className="p-2 rounded-xl bg-white hover:bg-slate-50 text-slate-600 border border-slate-200 transition shadow-xs"
              title="Refresh Workspace"
            >
              <RefreshCw className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>

        {/* ── Workspace Header & Financial Summary Banner ── */}
        <header className="rounded-2xl bg-white border-t-4 border-t-indigo-600 border-x border-b border-slate-200/80 shadow-sm p-6 sm:p-8 space-y-6">
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
            <div>
              <div className="flex flex-wrap items-center gap-2.5 mb-1.5">
                <h1 className="text-2xl sm:text-3xl font-extrabold text-slate-900 tracking-tight">
                  {tuition.title}
                </h1>
                {tuition.subject && (
                  <span className="px-2.5 py-0.5 rounded-full bg-indigo-50 text-indigo-700 border border-indigo-200 text-xs font-bold font-mono">
                    {tuition.subject}
                  </span>
                )}
              </div>
              <p className="text-xs text-slate-500 flex flex-wrap items-center gap-x-3 gap-y-1">
                <span>Cycle: <strong className="text-slate-800">{tuition.cycle_length} Classes</strong></span>
                <span>•</span>
                <span>Cycle fee: <strong className="text-emerald-700 font-mono">৳{Number(tuition.total_fee ?? tuition.tuition_fee).toLocaleString()}</strong></span>
                <span>•</span>
                <span>Per class: <strong className="text-slate-700 font-mono">৳{Number(wallet.per_class_rate || 0).toLocaleString()}</strong></span>
              </p>
            </div>

            {/* Quick Action CTAs */}
            <div className="flex items-center gap-2">
              <button
                onClick={() => setAddStudentModalOpen(true)}
                className="px-4 py-2.5 rounded-xl bg-white border border-slate-200 text-slate-800 hover:bg-slate-50 font-bold text-xs flex items-center gap-1.5 shadow-xs transition"
              >
                <UserPlus className="w-4 h-4 text-indigo-600" />
                <span>Add Student</span>
              </button>
              <button
                onClick={() => {
                  setAuthorCategory('EXAM');
                  setAuthorExamModalOpen(true);
                }}
                className="px-4 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-700 active:scale-95 text-white font-bold text-xs flex items-center gap-1.5 shadow-sm transition"
              >
                <Plus className="w-4 h-4" />
                <span>Create Exam</span>
              </button>
            </div>
          </div>

          {/* Tuition Financial Metrics Strip */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 pt-4 border-t border-slate-100">
            <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/70">
              <span className="text-[11px] font-bold uppercase tracking-wider text-slate-500 block mb-1">Enrolled Students</span>
              <div className="text-2xl font-black text-slate-900 flex items-center gap-2">
                <Users className="w-5 h-5 text-indigo-600" />
                <span>{enrolledStudents.length}</span>
              </div>
              <span className="text-[10px] text-slate-400 mt-1 block">Sharing this tracker</span>
            </div>

            <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/70">
              <span className="text-[11px] font-bold uppercase tracking-wider text-slate-500 block mb-1">Cycle Progress</span>
              <div className="text-2xl font-black text-slate-900">
                {completedClasses}
                <span className="text-sm font-semibold text-slate-400"> / {totalClasses}</span>
              </div>
              <span className="text-[10px] text-slate-400 mt-1 block">Cycle #{activeCycle?.cycle_number ?? 1}</span>
            </div>

            <div className="p-4 rounded-xl bg-emerald-50/60 border border-emerald-200">
              <span className="text-[11px] font-bold uppercase tracking-wider text-emerald-800 block mb-1">Earned So Far</span>
              <div className="text-2xl font-black text-emerald-700 font-mono">
                {formatTaka(wallet.earned_revenue || 0)}
              </div>
              <span className="text-[10px] text-emerald-600 mt-1 block">
                {formatTaka(wallet.pending_balance || 0)} pending
              </span>
            </div>

            <div className="p-4 rounded-xl bg-amber-50/60 border border-amber-200">
              <span className="text-[11px] font-bold uppercase tracking-wider text-amber-800 block mb-1">Lifetime Revenue</span>
              <div className="text-2xl font-black text-amber-700 font-mono">
                {formatTaka(wallet.lifetime_earnings || 0)}
              </div>
              <span className="text-[10px] text-amber-600 mt-1 block">
                {pastCycles.length} archived cycles
              </span>
            </div>
          </div>
        </header>

        {/* ── 4 Clean Tabs in Exact Order ── */}
        <nav className="flex p-1.5 rounded-2xl bg-white border border-slate-200/90 shadow-sm gap-1 sm:gap-2 overflow-x-auto no-scrollbar">
          {[
            { id: 'tracker', icon: CheckSquare, label: '1. Class Tracker' },
            { id: 'roster', icon: Users, label: '2. Student Roster', count: enrolledStudents.length },
            { id: 'assessments', icon: FileText, label: '3. Assessments', count: exams.length + homework.length },
            { id: 'settings', icon: Settings, label: '4. Routine & Settings' },
          ].map((tab) => {
            const Icon = tab.icon;
            const active = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                className={`flex-1 flex items-center justify-center gap-2 py-2.5 sm:py-3 px-3.5 rounded-xl text-xs sm:text-sm font-bold transition-all duration-150 whitespace-nowrap ${
                  active
                    ? 'bg-indigo-600 text-white shadow-sm'
                    : 'text-slate-600 hover:text-slate-900 hover:bg-slate-50'
                }`}
              >
                <Icon className="w-4 h-4 flex-shrink-0" />
                <span>{tab.label}</span>
                {tab.count !== undefined && tab.count > 0 && (
                  <span
                    className={`px-1.5 py-0.2 rounded-full text-[10px] font-black ${
                      active ? 'bg-white/20 text-white' : 'bg-slate-100 text-slate-700'
                    }`}
                  >
                    {tab.count}
                  </span>
                )}
              </button>
            );
          })}
        </nav>

        {/* ──────────────────────────────────────────────────────────────────────────
            SECTION 1: Class Tracker (Exact Order #1)
            The dynamic grid to mark classes as done (updates wallet live).
        ────────────────────────────────────────────────────────────────────────── */}
        {activeTab === 'tracker' && (
          <div className="space-y-6 animate-fadeIn">
            <SharedCycleBoard
              cycle={activeCycle}
              tuitionTitle={tuition.title}
              studentCount={enrolledStudents.length}
              onCycleChange={handleCycleChange}
              onAddStudent={() => setAddStudentModalOpen(true)}
              light={true}
            />

            {pastCycles.length > 0 && (
              <div className="rounded-2xl border border-slate-200/90 bg-white p-6 shadow-sm space-y-4">
                <div>
                  <h3 className="text-base font-bold text-slate-900">Archived Finished Cycles</h3>
                  <p className="text-xs text-slate-500 mt-0.5">Earnings from archived cycles remain locked and recorded.</p>
                </div>
                <div className="overflow-x-auto">
                  <table className="w-full text-left text-xs min-w-[420px]">
                    <thead className="text-[10px] uppercase tracking-wider text-slate-400 border-b border-slate-100">
                      <tr>
                        <th className="py-2.5 px-4">Cycle</th>
                        <th className="py-2.5 px-4">Classes Held</th>
                        <th className="py-2.5 px-4">Cycle Fee</th>
                        <th className="py-2.5 px-4 text-right">Earned Revenue</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {pastCycles.map((c) => (
                        <tr key={c.id}>
                          <td className="py-3 px-4 font-bold text-slate-800">Cycle #{c.cycle_number}</td>
                          <td className="py-3 px-4 text-slate-600">{c.completed_classes} / {c.total_classes}</td>
                          <td className="py-3 px-4 text-slate-600 font-mono">৳{Number(c.total_fee || 0).toLocaleString()}</td>
                          <td className="py-3 px-4 text-right text-emerald-700 font-bold font-mono">৳{Number(c.earned_revenue || 0).toLocaleString()}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}
          </div>
        )}

        {/* ──────────────────────────────────────────────────────────────────────────
            SECTION 2: Student Roster (Exact Order #2)
            List of students in this batch + accept Pending Requests via tutor_code.
        ────────────────────────────────────────────────────────────────────────── */}
        {activeTab === 'roster' && (
          <div className="space-y-6 animate-fadeIn">
            {/* Pending Requests & Invite Code Banner */}
            <div className="rounded-2xl bg-white border border-slate-200/90 p-6 shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-4">
              <div className="flex items-center gap-3.5">
                <div className="w-10 h-10 rounded-xl bg-indigo-50 border border-indigo-100 flex items-center justify-center text-indigo-600 flex-shrink-0">
                  <Sparkles className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-sm font-bold text-slate-900">Student Connection Invite Code</h3>
                  <p className="text-xs text-slate-500 mt-0.5">
                    Share your code with students. When they enter it, they appear in pending requests below.
                  </p>
                </div>
              </div>

              <div className="flex items-center gap-2">
                <span className="font-mono text-sm font-black text-indigo-700 bg-indigo-50 px-3.5 py-1.5 rounded-xl border border-indigo-200 select-all">
                  {user?.tutor_code || '—'}
                </span>
                <button
                  type="button"
                  onClick={() => {
                    if (user?.tutor_code) {
                      navigator.clipboard.writeText(user.tutor_code);
                      notify.success(`Invite code "${user.tutor_code}" copied!`);
                    }
                  }}
                  className="px-3.5 py-2 rounded-xl bg-indigo-600 text-white font-bold text-xs hover:bg-indigo-700 transition"
                >
                  Copy Code
                </button>
              </div>
            </div>

            {/* Pending Requests Waiting to be Enrolled */}
            {candidateStudents.length > 0 && (
              <div className="rounded-2xl border border-amber-200 bg-amber-50/40 p-6 shadow-sm space-y-4">
                <div className="flex items-center justify-between">
                  <div>
                    <h3 className="text-sm font-bold text-amber-900 flex items-center gap-2">
                      <UserPlus className="w-4 h-4 text-amber-600" />
                      <span>Pending Student Requests ({candidateStudents.length})</span>
                    </h3>
                    <p className="text-xs text-amber-700 mt-0.5">
                      These students connected with you and are ready to be enrolled into this batch.
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => setEnrollExistingModalOpen(true)}
                    className="text-xs font-bold text-indigo-600 hover:text-indigo-700"
                  >
                    View All
                  </button>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
                  {candidateStudents.slice(0, 6).map((student) => (
                    <div
                      key={student.student_id || student.id}
                      className="p-3.5 rounded-xl bg-white border border-amber-200/80 flex items-center justify-between gap-3 shadow-xs"
                    >
                      <div className="min-w-0">
                        <div className="text-xs font-bold text-slate-900 truncate">
                          {student.full_name || student.username}
                        </div>
                        <div className="text-[11px] text-slate-500 font-mono truncate">
                          @{student.username}
                        </div>
                      </div>
                      <button
                        type="button"
                        onClick={() => handleEnrollExistingStudent(student.student_id || student.id)}
                        disabled={enrollingStudentId === (student.student_id || student.id)}
                        className="px-3 py-1.5 rounded-lg bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-[11px] transition whitespace-nowrap"
                      >
                        Enroll
                      </button>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Enrolled Students Table */}
            <div className="rounded-2xl border border-slate-200/90 bg-white p-6 shadow-sm space-y-4">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div>
                  <h3 className="text-base font-bold text-slate-900 flex items-center gap-2">
                    <Users className="w-5 h-5 text-indigo-600" />
                    <span>Enrolled Students in this Batch ({enrolledStudents.length})</span>
                  </h3>
                  <p className="text-xs text-slate-500 mt-0.5">
                    Students who have access to this tuition's class tracker, routine, and assessments.
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => setEnrollExistingModalOpen(true)}
                    className="px-3 py-2 rounded-xl bg-white border border-slate-200 hover:bg-slate-50 text-slate-700 text-xs font-bold transition shadow-xs"
                  >
                    Enroll Existing
                  </button>
                  <button
                    onClick={() => setAddStudentModalOpen(true)}
                    className="px-3 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white text-xs font-bold transition shadow-xs"
                  >
                    + Add New Student
                  </button>
                </div>
              </div>

              {enrolledStudents.length === 0 ? (
                <div className="rounded-2xl border border-dashed border-slate-200 p-8 text-center space-y-2">
                  <Users className="w-8 h-8 mx-auto text-slate-400" />
                  <h4 className="text-sm font-bold text-slate-800">No Students Enrolled Yet</h4>
                  <p className="text-xs text-slate-500 max-w-sm mx-auto">
                    Add new students or accept pending requests to build your batch roster.
                  </p>
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full text-left text-xs min-w-[500px]">
                    <thead className="text-[10px] uppercase tracking-wider text-slate-400 border-b border-slate-100">
                      <tr>
                        <th className="py-2.5 px-4">Student</th>
                        <th className="py-2.5 px-4">Contact</th>
                        <th className="py-2.5 px-4">Grade</th>
                        <th className="py-2.5 px-4 text-right">Actions</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {enrolledStudents.map((student) => {
                        const sid = student.student_id || student.id;
                        const sname = student.full_name || student.student_name || student.name || student.username;

                        return (
                          <tr key={sid} className="hover:bg-slate-50/60 transition">
                            <td className="py-3 px-4">
                              <div className="font-bold text-slate-900">{sname}</div>
                              <div className="text-[11px] text-slate-400 font-mono">@{student.username}</div>
                            </td>
                            <td className="py-3 px-4 text-slate-600">
                              <div>{student.email || '—'}</div>
                              <div className="text-[11px] text-slate-400">{student.phone || ''}</div>
                            </td>
                            <td className="py-3 px-4 text-slate-600">
                              {student.grade_level || student.grade || '—'}
                            </td>
                            <td className="py-3 px-4 text-right">
                              <div className="flex items-center justify-end gap-1.5">
                                <button
                                  type="button"
                                  onClick={() => setSelectedStudentForCredentials(student)}
                                  className="p-1.5 rounded-lg text-slate-500 hover:text-indigo-600 hover:bg-slate-100 transition"
                                  title="View Login Credentials"
                                >
                                  <Key className="w-4 h-4" />
                                </button>
                                <button
                                  type="button"
                                  onClick={() => handleUnenrollStudent(sid, sname)}
                                  className="p-1.5 rounded-lg text-slate-400 hover:text-rose-600 hover:bg-rose-50 transition"
                                  title="Remove from batch"
                                >
                                  <Trash2 className="w-4 h-4" />
                                </button>
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </div>
        )}

        {/* ──────────────────────────────────────────────────────────────────────────
            SECTION 3: Assessments (Exact Order #3)
            Create and grade Homework, Assignments, and Exams strictly for this batch.
        ────────────────────────────────────────────────────────────────────────── */}
        {activeTab === 'assessments' && (
          <div className="space-y-6 animate-fadeIn">
            {/* Top Toolbar */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-6 rounded-2xl bg-white border border-slate-200/90 shadow-sm">
              <div>
                <h3 className="text-base font-bold text-slate-900 flex items-center gap-2">
                  <FileText className="w-5 h-5 text-indigo-600" />
                  <span>Batch Assessments & Grading</span>
                </h3>
                <p className="text-xs text-slate-500 mt-0.5">
                  Manage exams, quizzes, assignments, and homework specifically for {tuition.title}.
                </p>
              </div>

              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => {
                    setAuthorCategory('ASSIGNMENT');
                    setAuthorExamModalOpen(true);
                  }}
                  className="px-3.5 py-2 rounded-xl bg-purple-50 text-purple-700 hover:bg-purple-100 border border-purple-200 font-bold text-xs transition"
                >
                  + Add Assignment
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setAuthorCategory('EXAM');
                    setAuthorExamModalOpen(true);
                  }}
                  className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-xs transition shadow-sm"
                >
                  + Create Exam
                </button>
              </div>
            </div>

            {/* Filter Pills */}
            <div className="flex items-center gap-2">
              {[
                { id: 'all', label: 'All Assessments', count: exams.length + homework.length },
                { id: 'exams', label: 'Exams & Quizzes', count: exams.length },
                { id: 'homework', label: 'Homework', count: homework.length },
              ].map((f) => (
                <button
                  key={f.id}
                  type="button"
                  onClick={() => setAssessmentFilter(f.id)}
                  className={`px-3.5 py-1.5 rounded-xl text-xs font-bold transition flex items-center gap-1.5 ${
                    assessmentFilter === f.id
                      ? 'bg-slate-900 text-white shadow-xs'
                      : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'
                  }`}
                >
                  <span>{f.label}</span>
                  <span className={`px-1.5 py-0.2 rounded-full text-[10px] font-black ${assessmentFilter === f.id ? 'bg-white/20 text-white' : 'bg-slate-100 text-slate-600'}`}>
                    {f.count}
                  </span>
                </button>
              ))}
            </div>

            {/* Exams Section */}
            {(assessmentFilter === 'all' || assessmentFilter === 'exams') && (
              <div className="space-y-4">
                <ExamManager
                  tuitions={[tuition]}
                  onScheduleForBatch={() => {
                    setAuthorCategory('EXAM');
                    setAuthorExamModalOpen(true);
                  }}
                />
              </div>
            )}

            {/* Homework Section */}
            {(assessmentFilter === 'all' || assessmentFilter === 'homework') && (
              <div className="space-y-4 pt-2">
                <HomeworkManager
                  tuitions={[tuition]}
                  students={enrolledStudents}
                  selectedTuitionId={tuitionId}
                />
              </div>
            )}
          </div>
        )}

        {/* ──────────────────────────────────────────────────────────────────────────
            SECTION 4: Routine & Settings (Exact Order #4)
            Update weekly schedule, tuition fee, and cycle length.
        ────────────────────────────────────────────────────────────────────────── */}
        {activeTab === 'settings' && (
          <div className="space-y-6 animate-fadeIn">
            {/* Weekly Schedule Routine Manager */}
            <div className="rounded-2xl border border-slate-200/90 bg-white p-6 shadow-sm space-y-6">
              <div className="flex items-start justify-between">
                <div>
                  <h3 className="text-base font-bold text-slate-900 flex items-center gap-2">
                    <Clock className="w-5 h-5 text-indigo-600" />
                    <span>Weekly Class Schedule</span>
                  </h3>
                  <p className="text-xs text-slate-500 mt-0.5">
                    Configure the days and times when this tuition group regularly meets.
                  </p>
                </div>
                <button
                  type="button"
                  onClick={handleSaveRoutine}
                  disabled={savingRoutine}
                  className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-xs transition shadow-sm disabled:opacity-50"
                >
                  {savingRoutine ? 'Saving...' : 'Save Schedule'}
                </button>
              </div>

              {/* Existing Slots */}
              {routineSlots.length === 0 ? (
                <div className="rounded-xl border border-dashed border-slate-200 p-6 text-center text-xs text-slate-500">
                  No routine slots added yet. Add regular time slots below.
                </div>
              ) : (
                <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
                  {routineSlots.map((slot, index) => (
                    <div
                      key={index}
                      className="p-4 rounded-xl bg-slate-50 border border-slate-200 flex items-center justify-between gap-3"
                    >
                      <div>
                        <div className="text-xs font-bold text-indigo-700 uppercase tracking-wider">{slot.day}</div>
                        <div className="text-sm font-bold text-slate-900 font-mono mt-0.5">
                          {slot.start_time || slot.time} → {slot.end_time || '—'}
                        </div>
                      </div>
                      <button
                        type="button"
                        onClick={() => handleRemoveRoutineSlot(index)}
                        className="p-1 rounded-lg text-slate-400 hover:text-rose-600 hover:bg-rose-50 transition"
                      >
                        <X className="w-4 h-4" />
                      </button>
                    </div>
                  ))}
                </div>
              )}

              {/* Add New Slot Inline */}
              <div className="pt-4 border-t border-slate-100 flex flex-wrap items-end gap-3">
                <div className="w-36">
                  <label className="block text-[11px] font-bold uppercase tracking-wider text-slate-500 mb-1">Day</label>
                  <select
                    value={newSlotDay}
                    onChange={(e) => setNewSlotDay(e.target.value)}
                    className="w-full px-3 py-2 rounded-xl border border-slate-200 text-xs font-semibold bg-white text-slate-800 focus:outline-none focus:border-indigo-500"
                  >
                    {DAYS_ORDER.map((d) => (
                      <option key={d} value={d}>{d}</option>
                    ))}
                  </select>
                </div>

                <div className="w-32">
                  <label className="block text-[11px] font-bold uppercase tracking-wider text-slate-500 mb-1">Start Time</label>
                  <input
                    type="time"
                    value={newSlotStart}
                    onChange={(e) => setNewSlotStart(e.target.value)}
                    className="w-full px-3 py-2 rounded-xl border border-slate-200 text-xs font-semibold bg-white text-slate-800 focus:outline-none focus:border-indigo-500"
                  />
                </div>

                <div className="w-32">
                  <label className="block text-[11px] font-bold uppercase tracking-wider text-slate-500 mb-1">End Time</label>
                  <input
                    type="time"
                    value={newSlotEnd}
                    onChange={(e) => setNewSlotEnd(e.target.value)}
                    className="w-full px-3 py-2 rounded-xl border border-slate-200 text-xs font-semibold bg-white text-slate-800 focus:outline-none focus:border-indigo-500"
                  />
                </div>

                <button
                  type="button"
                  onClick={handleAddRoutineSlot}
                  className="px-4 py-2.5 rounded-xl bg-slate-900 hover:bg-slate-800 text-white font-bold text-xs transition"
                >
                  + Add Slot
                </button>
              </div>
            </div>

            {/* Tuition Batch Settings Card */}
            <div className="rounded-2xl border border-slate-200/90 bg-white p-6 shadow-sm space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-base font-bold text-slate-900 flex items-center gap-2">
                    <Settings className="w-5 h-5 text-indigo-600" />
                    <span>Tuition Configuration</span>
                  </h3>
                  <p className="text-xs text-slate-500 mt-0.5">
                    Update cycle length, fee structure, and batch title.
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => setEditTuitionModalOpen(true)}
                  className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-xs transition shadow-sm"
                >
                  Edit Configuration
                </button>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 pt-2">
                <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/70">
                  <span className="text-[11px] font-bold uppercase tracking-wider text-slate-500 block">Cycle Length</span>
                  <span className="text-lg font-black text-slate-900 mt-1 block">{tuition.cycle_length} Classes</span>
                </div>
                <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/70">
                  <span className="text-[11px] font-bold uppercase tracking-wider text-slate-500 block">Tuition Fee</span>
                  <span className="text-lg font-black text-emerald-700 font-mono mt-1 block">
                    ৳{Number(tuition.total_fee ?? tuition.tuition_fee).toLocaleString()}
                  </span>
                </div>
                <div className="p-4 rounded-xl bg-slate-50 border border-slate-200/70">
                  <span className="text-[11px] font-bold uppercase tracking-wider text-slate-500 block">Per Class Rate</span>
                  <span className="text-lg font-black text-slate-900 font-mono mt-1 block">
                    ৳{Number(wallet.per_class_rate || 0).toLocaleString()}
                  </span>
                </div>
              </div>
            </div>
          </div>
        )}
      </main>

      {/* ── Modals ── */}
      {addStudentModalOpen && (
        <AddStudentModal
          isOpen={addStudentModalOpen}
          onClose={() => setAddStudentModalOpen(false)}
          onStudentAdded={loadTuitionData}
          defaultTuitionId={tuitionId}
        />
      )}

      {editTuitionModalOpen && (
        <TuitionBatchesModal
          isOpen={editTuitionModalOpen}
          onClose={() => setEditTuitionModalOpen(false)}
          onChanged={loadTuitionData}
          tuitionToEdit={tuition}
        />
      )}

      {authorExamModalOpen && (
        <ExamAuthoringModal
          isOpen={authorExamModalOpen}
          onClose={() => setAuthorExamModalOpen(false)}
          onExamCreated={loadTuitionData}
          initialBatchId={tuitionId}
          initialCategory={authorCategory}
        />
      )}

      {selectedStudentForCredentials && (
        <StudentCredentialsModal
          isOpen={!!selectedStudentForCredentials}
          onClose={() => setSelectedStudentForCredentials(null)}
          student={selectedStudentForCredentials}
        />
      )}

      {/* Enroll Existing Student Modal */}
      {enrollExistingModalOpen && (
        <Modal
          isOpen={enrollExistingModalOpen}
          onClose={() => setEnrollExistingModalOpen(false)}
          title={`Enroll Student to ${tuition.title}`}
          maxWidth="max-w-md"
        >
          <div className="space-y-4">
            <div className="relative">
              <Search className="w-4 h-4 absolute left-3 top-3 text-slate-400" />
              <input
                type="text"
                placeholder="Search by name, username, or grade..."
                value={enrollSearch}
                onChange={(e) => setEnrollSearch(e.target.value)}
                className="w-full pl-9 pr-4 py-2.5 rounded-xl border border-slate-200 text-xs bg-slate-50 focus:bg-white focus:outline-none focus:border-indigo-500 transition"
              />
            </div>

            <div className="max-h-64 overflow-y-auto divide-y divide-slate-100">
              {filteredCandidates.length === 0 ? (
                <div className="p-6 text-center text-xs text-slate-500">
                  No unassigned students found.
                </div>
              ) : (
                filteredCandidates.map((s) => {
                  const sid = s.student_id || s.id;
                  return (
                    <div key={sid} className="py-2.5 flex items-center justify-between gap-3">
                      <div>
                        <div className="text-xs font-bold text-slate-900">{s.full_name || s.username}</div>
                        <div className="text-[11px] text-slate-400 font-mono">@{s.username}</div>
                      </div>
                      <button
                        type="button"
                        onClick={() => handleEnrollExistingStudent(sid)}
                        disabled={enrollingStudentId === sid}
                        className="px-3 py-1.5 rounded-lg bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-xs transition"
                      >
                        Enroll
                      </button>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
