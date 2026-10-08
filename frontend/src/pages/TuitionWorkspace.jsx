import React, { useState, useEffect, useMemo } from 'react';
import { notify } from '../utils/toast';
import { useParams, useNavigate, Link } from 'react-router-dom';
import Navbar from '../components/common/Navbar';
import AddStudentModal from '../components/tutor/AddStudentModal';
import SharedCycleBoard from '../components/tutor/SharedCycleBoard';
import ExamManager from '../components/tutor/ExamManager';
import AssignStudentModal from '../components/tutor/AssignStudentModal';
import TuitionBatchesModal from '../components/tutor/TuitionBatchesModal';
import ExamAuthoringModal from '../components/tutor/ExamAuthoringModal';
import StudentCredentialsModal from '../components/tutor/StudentCredentialsModal';
import Modal from '../components/common/Modal';
import { api } from '../api/client';
import {
  ArrowLeft,
  Calendar,
  Clock,
  DollarSign,
  Users,
  Layers,
  FileText,
  Plus,
  RotateCcw,
  CheckCircle2,
  Check,
  AlertCircle,
  Award,
  Key,
  Trophy,
  Edit2,
  Trash2,
  UserPlus,
  Mail,
  Phone,
  School,
  Sparkles,
  CalendarDays,
  X,
  ExternalLink,
  ChevronRight,
  TrendingUp,
  RefreshCw,
  Search,
} from 'lucide-react';

const DAYS_ORDER = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

const toLocalDateString = (d = new Date()) => {
  const dt = d instanceof Date ? d : new Date(d);
  return dt.getFullYear() + '-' + String(dt.getMonth() + 1).padStart(2, '0') + '-' + String(dt.getDate()).padStart(2, '0');
};

const getLocalTodayIso = () => {
  return `${toLocalDateString(new Date())}T12:00:00Z`;
};

export default function TuitionWorkspace() {
  const { id: tuitionId } = useParams();
  const navigate = useNavigate();

  // Active Tab: 'attendance' | 'exams' | 'routine' | 'roster'
  const [activeTab, setActiveTab] = useState('attendance');

  // Core Data
  const [tuition, setTuition] = useState(null);
  const [cycles, setCycles] = useState([]);
  const [exams, setExams] = useState([]);
  const [unassignedStudents, setUnassignedStudents] = useState([]);
  const [allStudents, setAllStudents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  // Modals
  const [addStudentModalOpen, setAddStudentModalOpen] = useState(false);
  const [assignModalOpen, setAssignModalOpen] = useState(false);
  const [selectedStudentForAssign, setSelectedStudentForAssign] = useState(null);
  const [editTuitionModalOpen, setEditTuitionModalOpen] = useState(false);
  const [authorExamModalOpen, setAuthorExamModalOpen] = useState(false);
  const [authorCategory, setAuthorCategory] = useState('EXAM');

  // Grading & Leaderboard
  const [gradingModalOpen, setGradingModalOpen] = useState(false);
  const [selectedExamForGrading, setSelectedExamForGrading] = useState(null);
  const [selectedSubmissionForGrading, setSelectedSubmissionForGrading] = useState(null);
  const [selectedExamForLeaderboard, setSelectedExamForLeaderboard] = useState(null);
  const [selectedStudentForCredentials, setSelectedStudentForCredentials] = useState(null);
  const [enrollExistingModalOpen, setEnrollExistingModalOpen] = useState(false);
  const [enrollSearch, setEnrollSearch] = useState('');
  const [enrollingStudentId, setEnrollingStudentId] = useState(null);

  // Routine Slot Editor State
  const [isEditingRoutine, setIsEditingRoutine] = useState(false);
  const [routineSlots, setRoutineSlots] = useState([]);
  const [newSlotDay, setNewSlotDay] = useState('Sunday');
  const [newSlotStart, setNewSlotStart] = useState('18:00');
  const [newSlotEnd, setNewSlotEnd] = useState('19:30');
  const [savingRoutine, setSavingRoutine] = useState(false);

  // Load Tuition Data
  const loadTuitionData = async () => {
    if (!tuitionId) return;
    try {
      setLoading(true);
      setError('');

      // 1. Fetch Tuition Detail
      const tData = await api.getTuitionDetail(tuitionId);
      setTuition(tData);
      setRoutineSlots(tData.routine || []);

      // 2. Fetch Attendance Cycles for this Tuition
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

      // 4. Fetch Unassigned Students & All Students
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
  };

  useEffect(() => {
    loadTuitionData();
  }, [tuitionId]);

  // Tuition Wallet for this group. The server owns the maths:
  // earned = (total fee / classes in the cycle) * completed classes.
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

  // Helpers shared by attendance lookups: numeric class-no compare + time overlap.
  const classNoOf = (c) => parseInt(c?.class_no ?? c?.classNo, 10);
  const slotToMinutes = (t) => {
    const m = String(t || '00:00').match(/(\d{1,2}):(\d{2})/);
    return m ? parseInt(m[1], 10) * 60 + parseInt(m[2], 10) : 0;
  };
  const slotsOverlap = (a, b) => {
    if (String(a?.day || '').toLowerCase() !== String(b?.day || '').toLowerCase()) return false;
    const aS = slotToMinutes(a?.start_time ?? a?.time);
    const aE = slotToMinutes(a?.end_time ?? '23:59');
    const bS = slotToMinutes(b?.start_time ?? b?.time);
    const bE = slotToMinutes(b?.end_time ?? '23:59');
    return Math.max(aS, bS) < Math.min(aE, bE);
  };

  // Unenroll Student from Tuition
  const handleUnenrollStudent = async (studentId, studentName) => {
    if (!confirm(`Remove ${studentName} from "${tuition.title}"? They will stop seeing this group's classes and exams. The group's class tracker and earnings are not affected.`)) {
      return;
    }
    try {
      await api.unenrollFromTuition(tuitionId, studentId);
      await loadTuitionData();
    } catch (err) {
      notify(`Failed to remove student: ${err.message}`);
    }
  };

  // Save Routine Slots
  const handleSaveRoutine = async () => {
    setSavingRoutine(true);
    try {
      await api.updateTuition(tuitionId, { routine: routineSlots });
      setIsEditingRoutine(false);
      await loadTuitionData();
    } catch (err) {
      notify(`Failed to save routine: ${err.message}`);
    } finally {
      setSavingRoutine(false);
    }
  };

  const handleAddRoutineSlot = () => {
    const candidate = { day: newSlotDay, start_time: newSlotStart, end_time: newSlotEnd };
    // Dedupe on overlapping intervals, not just exact start-time match:
    // e.g. existing 18:00-19:30 must block a new 18:30-19:00 on the same day.
    if (routineSlots.some((s) => slotsOverlap(s, candidate))) {
      return;
    }
    setRoutineSlots((prev) => [
      ...prev,
      { day: newSlotDay, start_time: newSlotStart, end_time: newSlotEnd },
    ]);
  };

  const handleRemoveRoutineSlot = (index) => {
    setRoutineSlots((prev) => prev.filter((_, i) => i !== index));
  };

  // Open Grading Modal
  // Hooks must run before the early returns below, so `tuition` may still be null here.
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
      <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
        <Navbar />
        <div className="flex-1 flex items-center justify-center">
          <div className="flex flex-col items-center gap-3">
            <div className="w-10 h-10 rounded-full border-4 border-indigo-500/20 border-t-indigo-500 animate-spin" />
            <p className="text-xs text-slate-400">Loading Tuition Workspace...</p>
          </div>
        </div>
      </div>
    );
  }

  if (error || !tuition) {
    return (
      <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
        <Navbar />
        <div className="flex-1 max-w-4xl mx-auto px-4 py-16 text-center space-y-4">
          <AlertCircle className="w-12 h-12 text-rose-500 mx-auto" />
          <h2 className="text-xl font-bold text-slate-100">Tuition Not Found</h2>
          <p className="text-sm text-slate-400">{error || 'This tuition does not exist or you do not have permission to view it.'}</p>
          <Link
            to="/tutor"
            className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-indigo-600 text-white text-xs font-semibold hover:bg-indigo-500 transition"
          >
            <ArrowLeft className="w-4 h-4" />
            <span>Return to Dashboard</span>
          </Link>
        </div>
      </div>
    );
  }

  const handleEnrollExistingStudent = async (studentId) => {
    try {
      setEnrollingStudentId(studentId);
      await api.enrollInTuition(tuitionId, studentId);
      await loadTuitionData();
    } catch (err) {
      notify(`Failed to enroll student: ${err.message}`);
    } finally {
      setEnrollingStudentId(null);
    }
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      <Navbar />

      <main className="flex-1 max-w-7xl w-full mx-auto px-3.5 sm:px-6 lg:px-8 py-5 sm:py-6 space-y-5 sm:space-y-6">
        {/* Breadcrumb & Navigation */}
        <div className="flex items-center justify-between gap-2 sm:gap-4">
          <div className="flex items-center gap-1.5 sm:gap-2 text-xs text-slate-400 min-w-0">
            <Link
              to="/tutor"
              className="hover:text-indigo-400 flex items-center gap-1 transition flex-shrink-0"
            >
              <ArrowLeft className="w-3.5 h-3.5" />
              <span className="hidden xs:inline">Tutor Dashboard</span>
            </Link>
            <ChevronRight className="w-3.5 h-3.5 text-slate-600 flex-shrink-0" />
            <span className="text-slate-200 font-semibold truncate max-w-[130px] xs:max-w-[220px] sm:max-w-md">
              {tuition.title}
            </span>
            <span className="hidden xs:inline-block px-2 py-0.5 rounded-full bg-indigo-500/10 text-indigo-300 border border-indigo-500/20 text-[10px] font-mono flex-shrink-0">
              Workspace
            </span>
          </div>

          <div className="flex items-center gap-2 flex-shrink-0">
            <button
              onClick={() => setEditTuitionModalOpen(true)}
              className="px-2.5 sm:px-3 py-1.5 rounded-xl bg-slate-800/80 hover:bg-slate-700 text-slate-300 hover:text-white border border-slate-700 text-xs font-semibold flex items-center gap-1.5 transition shadow-sm"
              title="Edit Tuition Settings & Routine"
            >
              <Edit2 className="w-3.5 h-3.5 text-slate-400" />
              <span className="hidden sm:inline">Edit Settings</span>
            </button>
            <button
              onClick={loadTuitionData}
              className="p-1.5 rounded-xl bg-slate-800/80 hover:bg-slate-700 text-slate-400 hover:text-white border border-slate-700 transition"
              title="Refresh Workspace"
            >
              <RefreshCw className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>

        {/* Tuition Workspace Header & Financial Summary Banner */}
        <div className="p-4 sm:p-6 rounded-2xl sm:rounded-3xl bg-gradient-to-br from-slate-900 via-indigo-950/30 to-slate-900 border border-slate-800 shadow-xl space-y-5 sm:space-y-6">
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
            <div>
              <div className="flex flex-wrap items-center gap-2.5 mb-1.5">
                <h1 className="text-xl sm:text-3xl font-extrabold text-slate-100 tracking-tight">
                  {tuition.title}
                </h1>
                {tuition.subject && (
                  <span className="px-2.5 py-0.5 rounded-full bg-indigo-500/20 text-indigo-300 border border-indigo-500/30 text-xs font-bold font-mono">
                    {tuition.subject}
                  </span>
                )}
              </div>
              <p className="text-xs text-slate-400 flex flex-wrap items-center gap-x-3 gap-y-1">
                <span>Cycle: <strong className="text-indigo-300">{tuition.cycle_length} Classes</strong></span>
                <span>•</span>
                <span>Cycle fee: <strong className="text-emerald-400 font-mono">৳{Number(tuition.total_fee ?? tuition.tuition_fee).toLocaleString()}</strong></span>
                <span>•</span>
                <span>Per class: <strong className="text-emerald-300 font-mono">৳{Number(wallet.per_class_rate || 0).toLocaleString()}</strong></span>
              </p>
            </div>

            {/* Quick Action Triggers */}
            <div className="grid grid-cols-2 sm:flex items-center gap-2 w-full md:w-auto">
              <button
                onClick={() => setAddStudentModalOpen(true)}
                className="px-3 sm:px-3.5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs flex items-center justify-center gap-1.5 shadow-lg shadow-indigo-600/30 transition"
              >
                <UserPlus className="w-4 h-4" />
                <span>Add Student</span>
              </button>
              <button
                onClick={() => {
                  setAuthorCategory('EXAM');
                  setAuthorExamModalOpen(true);
                }}
                className="px-3 sm:px-3.5 py-2 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-semibold text-xs flex items-center justify-center gap-1.5 shadow-lg shadow-purple-600/30 transition"
              >
                <Plus className="w-4 h-4" />
                <span>Schedule Exam</span>
              </button>
            </div>
          </div>

          {/* Tuition Wallet for this group */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-2.5 sm:gap-4 pt-4 border-t border-slate-800/80">
            <div className="p-3.5 sm:p-4 rounded-2xl bg-slate-900/80 border border-slate-800">
              <span className="text-[10px] sm:text-[11px] font-bold uppercase tracking-wider text-slate-400 block mb-1">Students</span>
              <div className="text-lg sm:text-2xl font-black text-slate-100 flex items-center gap-1.5">
                <Users className="w-4 h-4 sm:w-5 sm:h-5 text-indigo-400" />
                <span>{enrolledStudents.length}</span>
              </div>
              <span className="text-[10px] text-slate-500 mt-1 block">share tracker</span>
            </div>

            <div className="p-3.5 sm:p-4 rounded-2xl bg-slate-900/80 border border-slate-800">
              <span className="text-[10px] sm:text-[11px] font-bold uppercase tracking-wider text-slate-400 block mb-1">This cycle</span>
              <div className="text-lg sm:text-2xl font-black text-slate-100">
                {wallet.completed_classes ?? 0}
                <span className="text-xs sm:text-sm font-semibold text-slate-500"> / {wallet.total_classes ?? tuition.cycle_length}</span>
              </div>
              <span className="text-[10px] text-slate-500 mt-1 block">Cycle #{activeCycle?.cycle_number ?? 1}</span>
            </div>

            <div className="p-3.5 sm:p-4 rounded-2xl border border-emerald-500/20 bg-emerald-500/5">
              <span className="text-[10px] sm:text-[11px] font-bold uppercase tracking-wider text-emerald-400 block mb-1">Earned</span>
              <div className="text-lg sm:text-2xl font-black text-emerald-400 font-mono">
                ৳{Number(wallet.earned_revenue || 0).toLocaleString()}
              </div>
              <span className="text-[10px] text-emerald-300/70 mt-1 block">
                ৳{Number(wallet.pending_balance || 0).toLocaleString()} pending
              </span>
            </div>

            <div className="p-3.5 sm:p-4 rounded-2xl border border-amber-500/20 bg-amber-500/5">
              <span className="text-[10px] sm:text-[11px] font-bold uppercase tracking-wider text-amber-300 block mb-1">Lifetime</span>
              <div className="text-lg sm:text-2xl font-black text-amber-300 font-mono">
                ৳{Number(wallet.lifetime_earnings || 0).toLocaleString()}
              </div>
              <span className="text-[10px] text-amber-200/70 mt-1 block">
                {pastCycles.length} finished
              </span>
            </div>
          </div>
        </div>

        {/* 4-Tab Navigation */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-slate-800/80 pb-3">
          <div className="p-1 rounded-2xl bg-slate-900/90 border border-slate-800/80 flex overflow-x-auto no-scrollbar scroll-smooth gap-1 w-full sm:w-auto backdrop-blur-md">
            {[
              { id: 'attendance', icon: Calendar, label: 'Class tracker', count: enrolledStudents.length },
              { id: 'exams', icon: FileText, label: 'Exams & Assessments', count: exams.length },
              { id: 'routine', icon: Clock, label: 'Weekly Routine', badge: `${routineSlots.length} slots` },
              { id: 'roster', icon: Users, label: 'Students Roster', count: enrolledStudents.length },
            ].map((tab) => {
              const Icon = tab.icon;
              const active = activeTab === tab.id;
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`flex items-center gap-2 py-2 px-3 sm:px-3.5 rounded-xl text-xs font-semibold transition-all duration-200 flex-shrink-0 whitespace-nowrap ${
                    active
                      ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                      : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/60'
                  }`}
                >
                  <Icon className="w-3.5 h-3.5" />
                  <span>{tab.label}</span>
                  {tab.count !== undefined && (
                    <span className={`px-1.5 py-0.2 rounded-full text-[10px] font-bold ${active ? 'bg-indigo-500/40 text-white' : 'bg-slate-800 text-slate-400'}`}>
                      {tab.count}
                    </span>
                  )}
                  {tab.badge && (
                    <span className={`px-1.5 py-0.2 rounded-full text-[10px] font-bold ${active ? 'bg-indigo-500/40 text-white' : 'bg-slate-800 text-slate-400'}`}>
                      {tab.badge}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        </div>

        {/* Tab 1: Shared class tracker — one cycle for the whole group */}
        {activeTab === 'attendance' && (
          <div className="space-y-6">
            <SharedCycleBoard
              cycle={activeCycle}
              tuitionTitle={tuition.title}
              studentCount={enrolledStudents.length}
              onCycleChange={handleCycleChange}
              onAddStudent={() => setAddStudentModalOpen(true)}
            />

            {pastCycles.length > 0 && (
              <div className="rounded-2xl border border-slate-800 bg-slate-900/70 overflow-hidden">
                <div className="px-4 sm:px-5 py-3.5 border-b border-slate-800">
                  <h3 className="text-sm font-bold text-slate-100">Finished cycles</h3>
                  <p className="text-[11px] text-slate-400">Earnings here are final — later changes to the fee do not alter them.</p>
                </div>
                <div className="overflow-x-auto">
                  <table className="w-full text-left text-xs min-w-[420px]">
                    <thead className="text-[10px] uppercase tracking-wider text-slate-500 border-b border-slate-800">
                      <tr>
                        <th className="py-2.5 px-4 sm:px-5">Cycle</th>
                        <th className="py-2.5 px-4 sm:px-5">Classes</th>
                        <th className="py-2.5 px-4 sm:px-5">Cycle fee</th>
                        <th className="py-2.5 px-4 sm:px-5 text-right">Earned</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-800/70">
                      {pastCycles.map((c) => (
                        <tr key={c.id}>
                          <td className="py-2.5 px-4 sm:px-5 font-semibold text-slate-200">Cycle #{c.cycle_number}</td>
                          <td className="py-2.5 px-4 sm:px-5 text-slate-300">{c.completed_classes} / {c.total_classes}</td>
                          <td className="py-2.5 px-4 sm:px-5 text-slate-300 font-mono">৳{Number(c.total_fee || 0).toLocaleString()}</td>
                          <td className="py-2.5 px-4 sm:px-5 text-right text-emerald-400 font-bold font-mono">৳{Number(c.earned_revenue || 0).toLocaleString()}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}
          </div>
        )}

        {/* Tab 2: Exams & assignments for this group */}
        {activeTab === 'exams' && (
          <ExamManager
            exams={exams}
            students={allStudents}
            tuitionId={tuition.id}
            showGroup={false}
            onReload={loadTuitionData}
          />
        )}

        {/* Tab 3: Weekly Routine */}
        {activeTab === 'routine' && (
          <div className="space-y-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h3 className="text-lg font-bold text-slate-100 flex items-center gap-2">
                  <Clock className="w-5 h-5 text-indigo-400" />
                  Weekly Routine Master Schedule
                </h3>
                <p className="text-xs text-slate-400">
                  Scheduled class days and times for students enrolled in "{tuition.title}".
                </p>
              </div>

              <div>
                {!isEditingRoutine ? (
                  <button
                    onClick={() => setIsEditingRoutine(true)}
                    className="px-3.5 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold flex items-center gap-1.5 transition"
                  >
                    <Edit2 className="w-3.5 h-3.5" />
                    <span>Edit Routine Slots</span>
                  </button>
                ) : (
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => {
                        setRoutineSlots(tuition.routine || []);
                        setIsEditingRoutine(false);
                      }}
                      className="px-3 py-1.5 rounded-xl text-slate-400 hover:text-slate-200 text-xs font-semibold transition"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={handleSaveRoutine}
                      disabled={savingRoutine}
                      className="px-3.5 py-1.5 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-semibold flex items-center gap-1.5 shadow-md shadow-emerald-600/20 transition disabled:opacity-50"
                    >
                      <Check className="w-3.5 h-3.5" />
                      <span>{savingRoutine ? 'Saving...' : 'Save Routine'}</span>
                    </button>
                  </div>
                )}
              </div>
            </div>

            {/* Editing Box */}
            {isEditingRoutine && (
              <div className="p-4 rounded-2xl bg-indigo-950/20 border border-indigo-500/30 space-y-3">
                <span className="text-xs font-bold text-indigo-300 block">
                  Add New Class Schedule Slot:
                </span>
                <div className="flex flex-wrap items-center gap-3">
                  <select
                    value={newSlotDay}
                    onChange={(e) => setNewSlotDay(e.target.value)}
                    className="px-3 py-1.5 rounded-xl bg-slate-900 border border-slate-700 text-slate-100 text-xs"
                  >
                    {DAYS_ORDER.map((d) => (
                      <option key={d} value={d}>{d}</option>
                    ))}
                  </select>
                  <input
                    type="time"
                    value={newSlotStart}
                    onChange={(e) => setNewSlotStart(e.target.value)}
                    className="px-3 py-1.5 rounded-xl bg-slate-900 border border-slate-700 text-slate-100 text-xs font-mono"
                  />
                  <span className="text-xs text-slate-400">to</span>
                  <input
                    type="time"
                    value={newSlotEnd}
                    onChange={(e) => setNewSlotEnd(e.target.value)}
                    className="px-3 py-1.5 rounded-xl bg-slate-900 border border-slate-700 text-slate-100 text-xs font-mono"
                  />
                  <button
                    type="button"
                    onClick={handleAddRoutineSlot}
                    className="px-3 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold transition flex items-center gap-1"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    <span>Add Slot</span>
                  </button>
                </div>
              </div>
            )}

            {/* Routine Agenda Grid */}
            <div className="grid grid-cols-1 md:grid-cols-7 gap-3">
              {DAYS_ORDER.map((day) => {
                const daySlots = routineSlots.filter(
                  (s) => s.day?.toLowerCase() === day.toLowerCase()
                );

                return (
                  <div
                    key={day}
                    className={`p-4 rounded-2xl border transition flex flex-col justify-between min-h-[140px] ${
                      daySlots.length > 0
                        ? 'bg-slate-900/90 border-indigo-500/40 shadow-sm'
                        : 'bg-slate-900/40 border-slate-800'
                    }`}
                  >
                    <div>
                      <span className="text-xs font-bold text-slate-200 block mb-2">
                        {day}
                      </span>
                      {daySlots.length === 0 ? (
                        <span className="text-[11px] text-slate-500 italic block">No class</span>
                      ) : (
                        <div className="space-y-1.5">
                          {daySlots.map((slot, i) => (
                            <div
                              key={i}
                              className="p-2 rounded-lg bg-indigo-600/20 border border-indigo-500/30 text-indigo-300 font-mono text-[11px] flex items-center justify-between"
                            >
                              <span>{slot.start_time || slot.time} - {slot.end_time || '19:30'}</span>
                              {isEditingRoutine && (
                                <button
                                  type="button"
                                  onClick={() => handleRemoveRoutineSlot(i)}
                                  className="text-slate-400 hover:text-rose-400 transition ml-1"
                                >
                                  <X className="w-3 h-3" />
                                </button>
                              )}
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Tab 4: Enrolled Students Roster */}
        {activeTab === 'roster' && (
          <div className="space-y-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h3 className="text-lg font-bold text-slate-100 flex items-center gap-2">
                  <Users className="w-5 h-5 text-indigo-400" />
                  Students Enrolled in "{tuition.title}"
                </h3>
                <p className="text-xs text-slate-400">
                  {enrolledStudents.length} student(s) enrolled. You can add new students or assign incoming prospective students directly to this tuition.
                </p>
              </div>

              <div className="flex items-center gap-2">
                <button
                  onClick={() => setEnrollExistingModalOpen(true)}
                  className="px-3.5 py-1.5 rounded-xl bg-slate-800 hover:bg-slate-700 border border-slate-700 text-indigo-300 hover:text-indigo-200 font-semibold text-xs flex items-center gap-1.5 transition"
                >
                  <Users className="w-4 h-4 text-indigo-400" />
                  <span>Enroll Existing Student</span>
                </button>
                <button
                  onClick={() => setAddStudentModalOpen(true)}
                  className="px-3.5 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs flex items-center gap-1.5 shadow-md shadow-indigo-600/30 transition"
                >
                  <UserPlus className="w-4 h-4" />
                  <span>Add New Student</span>
                </button>
              </div>
            </div>

            {enrolledStudents.length === 0 ? (
              <div className="text-center py-16 px-4 rounded-3xl border border-dashed border-slate-800 bg-slate-900/30 space-y-3">
                <Users className="w-12 h-12 mx-auto text-slate-600" />
                <h4 className="text-base font-bold text-slate-200">No Students Enrolled</h4>
                <p className="text-xs text-slate-400 max-w-md mx-auto">
                  Enroll students to link them to this tuition's routine calendar, attendance engine, and assessments.
                </p>
                <div className="pt-2 flex flex-wrap items-center justify-center gap-3">
                  <button
                    onClick={() => setEnrollExistingModalOpen(true)}
                    className="px-4 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 border border-slate-700 text-indigo-300 text-xs font-semibold transition flex items-center gap-1.5"
                  >
                    <Users className="w-4 h-4 text-indigo-400" />
                    <span>Enroll Existing Student</span>
                  </button>
                  <button
                    onClick={() => setAddStudentModalOpen(true)}
                    className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold shadow-md shadow-indigo-600/30 transition flex items-center gap-1.5"
                  >
                    <UserPlus className="w-4 h-4" />
                    <span>+ Register New Student</span>
                  </button>
                </div>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {enrolledStudents.map((enr) => (
                  <div
                    key={enr.student_id}
                    className="p-5 rounded-2xl bg-slate-900/80 border border-slate-800 hover:border-slate-700 transition flex flex-col justify-between space-y-4"
                  >
                    <div>
                      <div className="flex items-start justify-between gap-2">
                        <div className="flex items-center gap-3">
                          <div className="w-10 h-10 rounded-xl bg-indigo-600/20 text-indigo-400 border border-indigo-500/30 font-bold flex items-center justify-center text-sm">
                            {enr.student_name?.charAt(0) || 'S'}
                          </div>
                          <div>
                            <h4 className="font-bold text-slate-100 text-sm">{enr.student_name}</h4>
                            <div className="flex items-center gap-2 flex-wrap">
                              {enr.username && (
                                <span className="text-[11px] text-slate-400 font-mono">
                                  @{enr.username}
                                </span>
                              )}
                            </div>
                            <span className="text-[11px] text-slate-500 font-mono block mt-0.5">
                              Enrolled {enr.joined_at ? new Date(enr.joined_at).toLocaleDateString() : 'Active'}
                            </span>
                          </div>
                        </div>

                        <div className="flex items-center gap-1">
                          <button
                            onClick={() => setSelectedStudentForCredentials(enr)}
                            className="p-1.5 rounded-lg text-slate-400 hover:text-amber-300 hover:bg-amber-500/10 transition flex items-center gap-1 text-xs font-medium border border-transparent hover:border-amber-500/30"
                            title="Give this student a new temporary password"
                          >
                            <Key className="w-3.5 h-3.5" />
                            <span className="hidden sm:inline">Password</span>
                          </button>
                          <button
                            onClick={() => handleUnenrollStudent(enr.student_id, enr.student_name)}
                            className="p-1.5 rounded-lg text-slate-500 hover:text-rose-400 hover:bg-rose-500/10 transition"
                            title="Remove from Tuition"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </div>
                      </div>

                      <div className="grid grid-cols-2 gap-2 text-xs text-slate-400 mt-4 pt-3 border-t border-slate-800">
                        {enr.grade_level && (
                          <div>Grade: <span className="text-slate-200">{enr.grade_level}</span></div>
                        )}
                        {enr.institution && (
                          <div>School: <span className="text-slate-200 truncate">{enr.institution}</span></div>
                        )}
                        {enr.phone && (
                          <div>Phone: <span className="text-slate-200">{enr.phone}</span></div>
                        )}
                        {enr.email && (
                          <div>Email: <span className="text-slate-200 truncate">{enr.email}</span></div>
                        )}
                      </div>
                    </div>

                    <div className="pt-2 border-t border-slate-800/60 flex items-center justify-between text-xs">
                      <span className="text-slate-400 font-mono">@{enr.username}</span>
                      <span className="text-slate-500">Shares the group's class tracker</span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </main>

      {/* Global Modals pre-linked to this Tuition */}
      <AddStudentModal
        isOpen={addStudentModalOpen}
        onClose={() => setAddStudentModalOpen(false)}
        tuitions={[tuition]}
        initialTuitionId={tuition.id}
        onStudentAdded={() => loadTuitionData()}
      />

      <AssignStudentModal
        isOpen={assignModalOpen}
        onClose={() => {
          setAssignModalOpen(false);
          setSelectedStudentForAssign(null);
        }}
        student={selectedStudentForAssign}
        tuitions={[tuition]}
        onAssigned={() => loadTuitionData()}
      />

      <TuitionBatchesModal
        isOpen={editTuitionModalOpen}
        onClose={() => setEditTuitionModalOpen(false)}
        allStudents={allStudents}
        batchToEdit={tuition}
        onBatchSaved={() => loadTuitionData()}
      />

      <ExamAuthoringModal
        key={`exam-author-${authorExamModalOpen ? 'open' : 'closed'}-${tuition?.id || 'none'}`}
        isOpen={authorExamModalOpen}
        onClose={() => setAuthorExamModalOpen(false)}
        students={allStudents}
        initialBatchId={tuition.id}
        initialCategory={authorCategory}
        onExamCreated={() => loadTuitionData()}
      />


      {/* Enroll Existing Student Modal */}
      <Modal
        isOpen={enrollExistingModalOpen}
        onClose={() => {
          setEnrollExistingModalOpen(false);
          setEnrollSearch('');
        }}
        title={`Enroll Existing Student into "${tuition?.title || 'Tuition'}"`}
        maxWidth="max-w-lg"
      >
        <div className="space-y-4">
          <p className="text-xs text-slate-400">
            Select any registered student from your account to enroll them into this tuition with active Attendance Cycle #1.
          </p>

          <div className="relative">
            <Search className="w-3.5 h-3.5 text-slate-500 absolute left-3 top-3" />
            <input
              type="text"
              placeholder="Search by student name or username..."
              value={enrollSearch}
              onChange={(e) => setEnrollSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 rounded-xl bg-slate-800/80 border border-slate-700 text-xs text-slate-200 focus:outline-none focus:border-indigo-500"
            />
          </div>

          <div className="max-h-72 overflow-y-auto space-y-2 pr-1">
            {filteredCandidates.length === 0 ? (
              <div className="text-center py-8 text-xs text-slate-500 space-y-2">
                <p>
                  {enrollSearch
                    ? 'No matching students found.'
                    : 'All your students are already enrolled in this tuition!'}
                </p>
                <button
                  onClick={() => {
                    setEnrollExistingModalOpen(false);
                    setAddStudentModalOpen(true);
                  }}
                  className="px-3 py-1.5 rounded-lg bg-indigo-600/30 border border-indigo-500/40 text-indigo-300 font-semibold text-xs hover:bg-indigo-600/50 transition inline-flex items-center gap-1"
                >
                  <UserPlus className="w-3.5 h-3.5" />
                  <span>Register a Brand New Student</span>
                </button>
              </div>
            ) : (
              filteredCandidates.map((s) => {
                const sid = String(s.student_id || s.id);
                const isEnrolling = enrollingStudentId === sid;
                return (
                  <div
                    key={sid}
                    className="p-3 rounded-xl bg-slate-800/50 border border-slate-700/60 hover:border-slate-600 flex items-center justify-between gap-3 transition"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span className="font-bold text-slate-200 text-xs truncate">
                          {s.full_name || s.username}
                        </span>
                        <span className="text-[11px] font-mono text-slate-400">
                          @{s.username}
                        </span>
                      </div>
                      <div className="text-[11px] text-slate-400 mt-0.5 flex items-center gap-2">
                        {s.profile?.grade_level || s.grade_level ? (
                          <span>Grade: {s.profile?.grade_level || s.grade_level}</span>
                        ) : null}
                        {s.institution || s.profile?.institution ? (
                          <span className="truncate">• {s.institution || s.profile?.institution}</span>
                        ) : null}
                      </div>
                    </div>

                    <button
                      disabled={isEnrolling}
                      onClick={() => handleEnrollExistingStudent(sid)}
                      className="px-3 py-1.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white font-semibold text-xs transition flex items-center gap-1 flex-shrink-0"
                    >
                      <UserPlus className="w-3.5 h-3.5" />
                      <span>{isEnrolling ? 'Enrolling...' : 'Enroll'}</span>
                    </button>
                  </div>
                );
              })
            )}
          </div>
        </div>
      </Modal>
    </div>
  );
}
