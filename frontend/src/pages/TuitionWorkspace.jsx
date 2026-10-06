import React, { useState, useEffect, useMemo } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import Navbar from '../components/common/Navbar';
import AddStudentModal from '../components/tutor/AddStudentModal';
import AssignStudentModal from '../components/tutor/AssignStudentModal';
import TuitionBatchesModal from '../components/tutor/TuitionBatchesModal';
import ExamAuthoringModal from '../components/tutor/ExamAuthoringModal';
import SubmissionsGradingModal from '../components/tutor/SubmissionsGradingModal';
import LeaderboardModal from '../components/common/LeaderboardModal';
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
  const [leaderboardModalOpen, setLeaderboardModalOpen] = useState(false);
  const [selectedExamForLeaderboard, setSelectedExamForLeaderboard] = useState(null);

  // Class Attendance Modal (Date Picker & Topic)
  const [dateModalOpen, setDateModalOpen] = useState(false);
  const [activeClassData, setActiveClassData] = useState(null);
  const [classDate, setClassDate] = useState(toLocalDateString(new Date()));
  const [classTopic, setClassTopic] = useState('');
  const [isCompletedState, setIsCompletedState] = useState(true);
  const [savingAttendance, setSavingAttendance] = useState(false);

  // Cycle Reset Modal
  const [resetModalOpen, setResetModalOpen] = useState(false);
  const [cycleToReset, setCycleToReset] = useState(null);
  const [resettingCycle, setResettingCycle] = useState(false);

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

  // Derived Financial Analytics
  const analytics = useMemo(() => {
    if (!tuition) {
      return {
        totalStudents: 0,
        totalPotentialRevenue: 0,
        earnedRevenue: 0,
        pendingBalance: 0,
        perClassRate: 0,
        totalCompletedClasses: 0,
        totalClassesRequired: 0,
        completionRate: 0,
      };
    }

    const fee = parseFloat(tuition.tuition_fee) || 0;
    const cycleLen = parseInt(tuition.cycle_length, 10) || 12;
    const perClassRate = cycleLen > 0 ? fee / cycleLen : 0;

    const enrolledStudents = tuition.enrollments || [];
    const totalStudents = enrolledStudents.length;
    const totalPotentialRevenue = fee * totalStudents;

    let earnedRevenue = 0;
    let totalCompletedClasses = 0;

    // Sum earned per active cycle using that cycle's own fee_snapshot
    // (fee_snapshot ?? tuition fee), not the global current fee — fees may
    // change between cycles and must not retroactively alter history.
    const cycleFeeSnapshot = (cycle) => {
      const snap = parseFloat(cycle?.fee_snapshot);
      if (Number.isFinite(snap) && snap > 0) return snap;
      const live = parseFloat(cycle?.tuition_fee);
      if (Number.isFinite(live) && live > 0) return live;
      return fee;
    };
    const cycleLengthOf = (cycle) =>
      parseInt(cycle?.total_classes ?? cycle?.cycle_length ?? cycleLen, 10) || cycleLen;

    enrolledStudents.forEach((enr) => {
      const activeCycle = (cycles || []).find(
        (c) => String(c.student_id ?? c.student) === String(enr.student_id ?? enr.student ?? enr.id) && c.status === 'ACTIVE'
      ) || enr.active_cycle;

      if (activeCycle) {
        const completed = parseInt(activeCycle.completed_classes, 10) || 0;
        const len = cycleLengthOf(activeCycle);
        const rate = len > 0 ? cycleFeeSnapshot(activeCycle) / len : 0;
        totalCompletedClasses += completed;
        earnedRevenue += completed * rate;
      }
    });

    const pendingBalance = Math.max(0, totalPotentialRevenue - earnedRevenue);
    const totalClassesRequired = totalStudents * cycleLen;
    const completionRate = totalClassesRequired > 0
      ? Math.round((totalCompletedClasses / totalClassesRequired) * 100)
      : 0;

    return {
      totalStudents,
      totalPotentialRevenue,
      earnedRevenue: Math.round(earnedRevenue * 100) / 100,
      pendingBalance: Math.round(pendingBalance * 100) / 100,
      perClassRate: Math.round(perClassRate * 100) / 100,
      totalCompletedClasses,
      totalClassesRequired,
      completionRate,
    };
  }, [tuition, cycles]);

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

  // Toggle Attendance Slot
  const handleToggleAttendance = async (cycleId, classNum, currentCompleted) => {
    const cycle = cycles.find((c) => String(c.id) === String(cycleId));
    if (!cycle) return;

    // If currently incomplete, single-click marks as completed today!
    if (!currentCompleted) {
      const todayIso = getLocalTodayIso();
      try {
        await api.toggleAttendanceClass(cycleId, classNum, true, todayIso, '');
        await loadTuitionData();
      } catch (err) {
        alert(`Failed to update attendance: ${err.message}`);
      }
    } else {
      // If already completed, open detail modal to adjust date, add topic, or unmark
      const cls = (cycle.classes_data || []).find(
        (c) => classNoOf(c) === parseInt(classNum, 10)
      ) || { class_no: parseInt(classNum, 10), completed: true, date: getLocalTodayIso(), topic: '' };

      setActiveClassData({ cycleId, classNum, cls });
      setIsCompletedState(true);
      setClassDate(cls.date ? toLocalDateString(new Date(cls.date)) : toLocalDateString(new Date()));
      setClassTopic(cls.topic || '');
      setDateModalOpen(true);
    }
  };

  // Save Class Attendance from Modal
  const handleSaveClassModal = async (e) => {
    e?.preventDefault();
    if (!activeClassData) return;

    const { cycleId, classNum } = activeClassData;
    setSavingAttendance(true);
    try {
      const targetDate = isCompletedState
        ? (classDate ? `${classDate}T12:00:00Z` : getLocalTodayIso())
        : null;

      await api.toggleAttendanceClass(
        cycleId,
        classNum,
        isCompletedState,
        targetDate,
        isCompletedState ? classTopic : ''
      );

      setDateModalOpen(false);
      await loadTuitionData();
    } catch (err) {
      alert(`Save failed: ${err.message}`);
    } finally {
      setSavingAttendance(false);
    }
  };

  // Reset Cycle Handler
  const handleConfirmResetCycle = async () => {
    if (!cycleToReset) return;
    setResettingCycle(true);
    try {
      await api.resetAttendanceCycle(cycleToReset.id);
      setResetModalOpen(false);
      setCycleToReset(null);
      await loadTuitionData();
    } catch (err) {
      alert(`Cycle reset failed: ${err.message}`);
    } finally {
      setResettingCycle(false);
    }
  };

  // Unenroll Student from Tuition
  const handleUnenrollStudent = async (studentId, studentName) => {
    if (!confirm(`Are you sure you want to remove ${studentName} from "${tuition.title}"?`)) {
      return;
    }
    try {
      await api.unenrollFromTuition(tuitionId, studentId);
      await loadTuitionData();
    } catch (err) {
      alert(`Failed to remove student: ${err.message}`);
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
      alert(`Failed to save routine: ${err.message}`);
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
  const handleOpenGrading = async (exam) => {
    try {
      const detail = await api.getExamDetail(exam.id);
      setSelectedExamForGrading(detail);
      setSelectedSubmissionForGrading(detail.submission);
      setGradingModalOpen(true);
    } catch (err) {
      alert(`Failed to load submission: ${err.message}`);
    }
  };

  // Open Leaderboard Modal
  const handleOpenLeaderboard = (exam) => {
    setSelectedExamForLeaderboard(exam);
    setLeaderboardModalOpen(true);
  };

  // Toggle Publish Results
  const handleTogglePublish = async (exam) => {
    try {
      await api.updateExam(exam.id, {
        is_results_published: !exam.is_results_published,
      });
      await loadTuitionData();
    } catch (err) {
      alert(`Failed to toggle results: ${err.message}`);
    }
  };

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

  const enrolledStudents = tuition.enrollments || [];

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      <Navbar />

      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6 space-y-6">
        {/* Breadcrumb & Navigation */}
        <div className="flex items-center justify-between gap-4">
          <div className="flex items-center gap-2 text-xs text-slate-400">
            <Link
              to="/tutor"
              className="hover:text-indigo-400 flex items-center gap-1.5 transition"
            >
              <ArrowLeft className="w-3.5 h-3.5" />
              <span>Tutor Dashboard</span>
            </Link>
            <ChevronRight className="w-3.5 h-3.5 text-slate-600" />
            <span className="text-slate-200 font-semibold truncate max-w-[200px] sm:max-w-md">
              {tuition.title}
            </span>
            <span className="px-2 py-0.5 rounded-full bg-indigo-500/10 text-indigo-300 border border-indigo-500/20 text-[10px] font-mono">
              Workspace
            </span>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={() => setEditTuitionModalOpen(true)}
              className="px-3 py-1.5 rounded-xl bg-slate-800/80 hover:bg-slate-700 text-slate-300 hover:text-white border border-slate-700 text-xs font-semibold flex items-center gap-1.5 transition shadow-sm"
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
        <div className="p-6 rounded-3xl bg-gradient-to-br from-slate-900 via-indigo-950/30 to-slate-900 border border-slate-800 shadow-xl space-y-6">
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
            <div>
              <div className="flex flex-wrap items-center gap-2.5 mb-1.5">
                <h1 className="text-2xl sm:text-3xl font-extrabold text-slate-100 tracking-tight">
                  {tuition.title}
                </h1>
                {tuition.subject && (
                  <span className="px-2.5 py-0.5 rounded-full bg-indigo-500/20 text-indigo-300 border border-indigo-500/30 text-xs font-bold font-mono">
                    {tuition.subject}
                  </span>
                )}
              </div>
              <p className="text-xs text-slate-400 flex flex-wrap items-center gap-3">
                <span>Cycle Length: <strong className="text-indigo-300">{tuition.cycle_length} Classes</strong></span>
                <span>•</span>
                <span>Fee per Student: <strong className="text-emerald-400 font-mono">৳{Number(tuition.tuition_fee).toLocaleString()}</strong></span>
                <span>•</span>
                <span>Rate per Class: <strong className="text-emerald-300 font-mono">৳{analytics.perClassRate}</strong></span>
              </p>
            </div>

            {/* Quick Action Triggers */}
            <div className="flex flex-wrap items-center gap-2">
              <button
                onClick={() => setAddStudentModalOpen(true)}
                className="px-3.5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs flex items-center gap-1.5 shadow-lg shadow-indigo-600/30 transition"
              >
                <UserPlus className="w-4 h-4" />
                <span>Add Student</span>
              </button>
              <button
                onClick={() => {
                  setAuthorCategory('EXAM');
                  setAuthorExamModalOpen(true);
                }}
                className="px-3.5 py-2 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-semibold text-xs flex items-center gap-1.5 shadow-lg shadow-purple-600/30 transition"
              >
                <Plus className="w-4 h-4" />
                <span>Schedule Exam</span>
              </button>
            </div>
          </div>

          {/* Tuition Wallet Summary: Financial Metrics Cards */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 sm:gap-4 pt-4 border-t border-slate-800/80">
            <div className="p-4 rounded-2xl bg-slate-900/80 border border-slate-800">
              <span className="text-[11px] font-bold uppercase tracking-wider text-slate-400 block mb-1">
                Enrolled Students
              </span>
              <div className="text-xl sm:text-2xl font-black text-slate-100 flex items-center gap-2">
                <Users className="w-5 h-5 text-indigo-400" />
                <span>{analytics.totalStudents}</span>
              </div>
              <span className="text-[11px] text-slate-500 mt-1 block">
                Active in this batch
              </span>
            </div>

            <div className="p-4 rounded-2xl bg-slate-900/80 border border-slate-800">
              <span className="text-[11px] font-bold uppercase tracking-wider text-slate-400 block mb-1">
                Potential Revenue
              </span>
              <div className="text-xl sm:text-2xl font-black text-slate-100 font-mono">
                ৳{analytics.totalPotentialRevenue.toLocaleString()}
              </div>
              <span className="text-[11px] text-slate-500 mt-1 block">
                ৳{Number(tuition.tuition_fee).toLocaleString()} × {analytics.totalStudents} students
              </span>
            </div>

            <div className="p-4 rounded-2xl bg-slate-900/80 border border-emerald-500/20 bg-emerald-500/5">
              <span className="text-[11px] font-bold uppercase tracking-wider text-emerald-400 block mb-1">
                Earned to Date
              </span>
              <div className="text-xl sm:text-2xl font-black text-emerald-400 font-mono">
                ৳{analytics.earnedRevenue.toLocaleString()}
              </div>
              <span className="text-[11px] text-emerald-300/70 mt-1 block">
                {analytics.totalCompletedClasses} total classes completed
              </span>
            </div>

            <div className="p-4 rounded-2xl bg-slate-900/80 border border-indigo-500/20 bg-indigo-500/5">
              <span className="text-[11px] font-bold uppercase tracking-wider text-indigo-300 block mb-1">
                Pending Balance
              </span>
              <div className="text-xl sm:text-2xl font-black text-indigo-300 font-mono">
                ৳{analytics.pendingBalance.toLocaleString()}
              </div>
              <span className="text-[11px] text-indigo-300/70 mt-1 block">
                {analytics.completionRate}% cycle completion
              </span>
            </div>
          </div>
        </div>

        {/* 4-Tab Navigation */}
        <div className="flex flex-wrap items-center gap-2 border-b border-slate-800 pb-3">
          <button
            onClick={() => setActiveTab('attendance')}
            className={`px-4 py-2 rounded-xl text-xs font-bold flex items-center gap-2 transition ${
              activeTab === 'attendance'
                ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
            }`}
          >
            <Calendar className="w-4 h-4" />
            <span>Attendance & Dynamic Cycles</span>
            <span className="px-1.5 py-0.2 rounded-full bg-slate-900/60 text-[10px] text-slate-300">
              {enrolledStudents.length}
            </span>
          </button>

          <button
            onClick={() => setActiveTab('exams')}
            className={`px-4 py-2 rounded-xl text-xs font-bold flex items-center gap-2 transition ${
              activeTab === 'exams'
                ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
            }`}
          >
            <FileText className="w-4 h-4" />
            <span>Exams & Assessments</span>
            <span className="px-1.5 py-0.2 rounded-full bg-slate-900/60 text-[10px] text-slate-300">
              {exams.length}
            </span>
          </button>

          <button
            onClick={() => setActiveTab('routine')}
            className={`px-4 py-2 rounded-xl text-xs font-bold flex items-center gap-2 transition ${
              activeTab === 'routine'
                ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
            }`}
          >
            <Clock className="w-4 h-4" />
            <span>Weekly Routine</span>
            <span className="px-1.5 py-0.2 rounded-full bg-slate-900/60 text-[10px] text-slate-300">
              {routineSlots.length} slots
            </span>
          </button>

          <button
            onClick={() => setActiveTab('roster')}
            className={`px-4 py-2 rounded-xl text-xs font-bold flex items-center gap-2 transition ${
              activeTab === 'roster'
                ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
            }`}
          >
            <Users className="w-4 h-4" />
            <span>Enrolled Students Roster</span>
            <span className="px-1.5 py-0.2 rounded-full bg-slate-900/60 text-[10px] text-slate-300">
              {enrolledStudents.length}
            </span>
          </button>
        </div>

        {/* Tab 1: Attendance & Dynamic Cycles (Default View) */}
        {activeTab === 'attendance' && (
          <div className="space-y-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h3 className="text-lg font-bold text-slate-100 flex items-center gap-2">
                  <Calendar className="w-5 h-5 text-indigo-400" />
                  Student Attendance Cycles
                </h3>
                <p className="text-xs text-slate-400">
                  Track dynamic class attendance (1 to {tuition.cycle_length}) for each enrolled student. Single-click to mark completed today, or click to set custom date & topic notes.
                </p>
              </div>

              <div className="flex items-center gap-2">
                <button
                  onClick={() => setAddStudentModalOpen(true)}
                  className="px-3 py-1.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-semibold flex items-center gap-1.5 border border-slate-700 transition"
                >
                  <UserPlus className="w-3.5 h-3.5 text-indigo-400" />
                  <span>Enroll Student</span>
                </button>
              </div>
            </div>

            {enrolledStudents.length === 0 ? (
              <div className="text-center py-16 px-4 rounded-3xl border border-dashed border-slate-800 bg-slate-900/30 space-y-3">
                <Users className="w-12 h-12 mx-auto text-slate-600" />
                <h4 className="text-base font-bold text-slate-200">No Students Enrolled in this Tuition Yet</h4>
                <p className="text-xs text-slate-400 max-w-md mx-auto">
                  Add a student directly or assign one from your incoming prospective students queue to activate attendance tracking and wallet analytics.
                </p>
                <div className="pt-2 flex flex-wrap items-center justify-center gap-3">
                  <button
                    onClick={() => setAddStudentModalOpen(true)}
                    className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold shadow-md shadow-indigo-600/30 transition flex items-center gap-2"
                  >
                    <UserPlus className="w-4 h-4" />
                    <span>Create & Enroll Student</span>
                  </button>
                  {unassignedStudents.length > 0 && (
                    <button
                      onClick={() => {
                        setSelectedStudentForAssign(unassignedStudents[0]);
                        setAssignModalOpen(true);
                      }}
                      className="px-4 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 border border-slate-700 text-xs font-semibold transition"
                    >
                      Assign from Incoming Queue ({unassignedStudents.length})
                    </button>
                  )}
                </div>
              </div>
            ) : (
              <div className="space-y-4">
                {enrolledStudents.map((enr) => {
                  const studentCycle = (cycles || []).find(
                    (c) => String(c.student_id ?? c.student) === String(enr.student_id ?? enr.student ?? enr.id) && c.status === 'ACTIVE'
                  ) || enr.active_cycle;

                  const cycleNum = studentCycle?.cycle_number || 1;
                  const totalClasses = parseInt(studentCycle?.total_classes ?? tuition.cycle_length, 10) || 12;
                  const completedClasses = parseInt(studentCycle?.completed_classes, 10) || 0;
                  const isCycleComplete = completedClasses >= totalClasses;
                  const classesData = studentCycle?.classes_data || [];

                  // Per-cycle snapshot: never use the global perClassRate here.
                  const snapFee = parseFloat(studentCycle?.fee_snapshot);
                  const cycleFee = Number.isFinite(snapFee) && snapFee > 0 ? snapFee : (parseFloat(tuition.tuition_fee) || 0);
                  const cycleRate = totalClasses > 0 ? cycleFee / totalClasses : 0;
                  const studentEarned = Math.round(completedClasses * cycleRate * 100) / 100;
                  const studentPending = Math.round((cycleFee - studentEarned) * 100) / 100;
                  const studentProgressPct = totalClasses > 0 ? Math.round((completedClasses / totalClasses) * 100) : 0;

                  return (
                    <div
                      key={enr.student_id}
                      className="p-5 sm:p-6 rounded-2xl bg-slate-900/80 border border-slate-800 hover:border-slate-700 transition shadow-lg space-y-4"
                    >
                      {/* Student Card Top Bar */}
                      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                        <div className="flex items-start gap-3">
                          <div className="w-10 h-10 rounded-xl bg-indigo-600/20 text-indigo-400 border border-indigo-500/30 font-bold flex items-center justify-center text-sm flex-shrink-0">
                            {enr.student_name?.charAt(0) || 'S'}
                          </div>
                          <div>
                            <div className="flex items-center gap-2">
                              <h4 className="font-bold text-slate-100 text-sm sm:text-base">
                                {enr.student_name}
                              </h4>
                              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-indigo-900/60 text-indigo-300 border border-indigo-700/50">
                                Cycle #{cycleNum}
                              </span>
                              {isCycleComplete && (
                                <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-950 text-emerald-300 border border-emerald-500/30 flex items-center gap-1">
                                  <CheckCircle2 className="w-3 h-3" />
                                  Cycle Complete
                                </span>
                              )}
                            </div>
                            <div className="flex flex-wrap items-center gap-x-3 gap-y-0.5 text-xs text-slate-400 mt-1">
                              {enr.email && <span>{enr.email}</span>}
                              {enr.phone && <span>• {enr.phone}</span>}
                              {enr.grade_level && <span>• {enr.grade_level}</span>}
                            </div>
                          </div>
                        </div>

                        {/* Financial Snapshot & Cycle Reset Button */}
                        <div className="flex flex-wrap items-center gap-2.5">
                          <div className="text-right text-xs">
                            <span className="text-slate-400 block text-[11px]">
                              {completedClasses} of {totalClasses} Classes ({studentProgressPct}%)
                            </span>
                            <span className="font-mono text-emerald-400 font-bold">
                              ৳{studentEarned.toLocaleString()} earned
                            </span>
                            <span className="text-slate-500 font-mono text-[11px] ml-1">
                              • ৳{studentPending.toLocaleString()} pending
                            </span>
                          </div>

                          {isCycleComplete && studentCycle?.id && (
                            <button
                              onClick={() => {
                                setCycleToReset(studentCycle);
                                setResetModalOpen(true);
                              }}
                              className="px-3 py-1.5 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white font-semibold text-xs flex items-center gap-1.5 shadow-md shadow-emerald-600/20 transition animate-pulse"
                              title="Archive completed cycle and start next cycle"
                            >
                              <RotateCcw className="w-3.5 h-3.5" />
                              <span>Start Cycle #{cycleNum + 1}</span>
                            </button>
                          )}
                        </div>
                      </div>

                      {/* Interactive Class Attendance Checkboxes */}
                      <div className="pt-2 border-t border-slate-800">
                        <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-12 gap-2">
                          {Array.from({ length: totalClasses }, (_, i) => i + 1).map((classNum) => {
                            const clsItem = classesData.find(
                              (c) => classNoOf(c) === parseInt(classNum, 10)
                            ) || { class_no: classNum, completed: false, date: null, topic: '' };

                            const isDone = clsItem.completed;
                            const dateObj = clsItem.date ? new Date(clsItem.date) : null;
                            const formattedDate = dateObj
                              ? dateObj.toLocaleDateString(undefined, { month: 'short', day: 'numeric' })
                              : null;

                            return (
                              <div
                                key={classNum}
                                onClick={() =>
                                  studentCycle?.id &&
                                  handleToggleAttendance(studentCycle.id, classNum, isDone)
                                }
                                title={
                                  isDone
                                    ? `Class #${classNum}: Attended on ${dateObj?.toLocaleDateString()}${clsItem.topic ? ` (${clsItem.topic})` : ''}. Click to edit.`
                                    : `Class #${classNum}: Unchecked. Click to mark completed today.`
                                }
                                className={`p-2 rounded-xl border flex flex-col items-center justify-center cursor-pointer transition select-none ${
                                  isDone
                                    ? 'bg-emerald-600/20 border-emerald-500/50 text-emerald-300 shadow-sm shadow-emerald-500/10 hover:border-emerald-400'
                                    : 'bg-slate-800/40 border-slate-700/60 hover:bg-slate-800 hover:border-indigo-500/60 text-slate-400'
                                }`}
                              >
                                <span className="text-[11px] font-bold font-mono">#{classNum}</span>
                                <div className="my-1">
                                  {isDone ? (
                                    <Check className="w-4 h-4 text-emerald-400 stroke-[2.5]" />
                                  ) : (
                                    <div className="w-3.5 h-3.5 rounded border border-slate-600" />
                                  )}
                                </div>
                                <span
                                  className={`text-[9px] font-medium truncate max-w-full ${
                                    isDone ? 'text-emerald-200' : 'text-slate-500'
                                  }`}
                                >
                                  {formattedDate || 'Upcoming'}
                                </span>
                              </div>
                            );
                          })}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}

        {/* Tab 2: Exams & Assessments */}
        {activeTab === 'exams' && (
          <div className="space-y-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h3 className="text-lg font-bold text-slate-100 flex items-center gap-2">
                  <FileText className="w-5 h-5 text-indigo-400" />
                  Tuition Assessments & Examinations
                </h3>
                <p className="text-xs text-slate-400">
                  Assessments assigned to students enrolled in "{tuition.title}". Features auto-graded MCQs, TipTap written questions, and anti-cheat scheduled releases.
                </p>
              </div>

              <div className="flex items-center gap-2">
                <button
                  onClick={() => {
                    setAuthorCategory('EXAM');
                    setAuthorExamModalOpen(true);
                  }}
                  className="px-3.5 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs flex items-center gap-1.5 shadow-md shadow-indigo-600/30 transition"
                >
                  <Plus className="w-4 h-4" />
                  <span>Schedule Exam</span>
                </button>
                <button
                  onClick={() => {
                    setAuthorCategory('ASSIGNMENT');
                    setAuthorExamModalOpen(true);
                  }}
                  className="px-3.5 py-1.5 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-semibold text-xs flex items-center gap-1.5 shadow-md shadow-purple-600/30 transition"
                >
                  <Plus className="w-4 h-4" />
                  <span>Create Assignment</span>
                </button>
              </div>
            </div>

            {exams.length === 0 ? (
              <div className="text-center py-16 px-4 rounded-3xl border border-dashed border-slate-800 bg-slate-900/30 space-y-3">
                <FileText className="w-12 h-12 mx-auto text-slate-600" />
                <h4 className="text-base font-bold text-slate-200">No Assessments Created for this Tuition Yet</h4>
                <p className="text-xs text-slate-400 max-w-md mx-auto">
                  Schedule timed examinations or assignments with deadlines. All enrolled students will automatically receive notifications and access.
                </p>
                <div className="pt-2 flex items-center justify-center gap-3">
                  <button
                    onClick={() => {
                      setAuthorCategory('EXAM');
                      setAuthorExamModalOpen(true);
                    }}
                    className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold shadow-md shadow-indigo-600/30 transition flex items-center gap-1.5"
                  >
                    <Plus className="w-4 h-4" />
                    <span>Schedule First Exam</span>
                  </button>
                </div>
              </div>
            ) : (
              <div className="glass-panel overflow-hidden rounded-2xl border border-slate-800">
                <table className="w-full text-left text-xs">
                  <thead className="bg-slate-900/90 text-slate-400 uppercase tracking-wider font-semibold border-b border-slate-800">
                    <tr>
                      <th className="py-3 px-4">Title & Format</th>
                      <th className="py-3 px-4">Category</th>
                      <th className="py-3 px-4">Window / Schedule</th>
                      <th className="py-3 px-4">Status</th>
                      <th className="py-3 px-4 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/80">
                    {exams.map((exam) => (
                      <tr key={exam.id} className="hover:bg-slate-900/50 transition">
                        <td className="py-3.5 px-4">
                          <div className="font-bold text-slate-100 text-sm">{exam.title}</div>
                          <div className="flex items-center gap-2 text-[11px] text-slate-400 mt-0.5">
                            <span className="font-mono text-emerald-400 font-semibold">
                              {exam.total_marks} Marks
                            </span>
                            <span>•</span>
                            <span className="font-mono text-indigo-300">
                              {exam.exam_type}
                            </span>
                            {exam.mcq_count > 0 && (
                              <span>• {exam.mcq_count} MCQs</span>
                            )}
                          </div>
                        </td>
                        <td className="py-3.5 px-4">
                          <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${
                            exam.category === 'ASSIGNMENT'
                              ? 'bg-purple-500/15 text-purple-300 border border-purple-500/30'
                              : 'bg-indigo-500/15 text-indigo-300 border border-indigo-500/30'
                          }`}>
                            {exam.category}
                          </span>
                        </td>
                        <td className="py-3.5 px-4 text-slate-300 font-mono text-[11px]">
                          <div>Start: {new Date(exam.start_time).toLocaleString()}</div>
                          <div className="text-slate-500">End: {new Date(exam.end_time).toLocaleString()}</div>
                        </td>
                        <td className="py-3.5 px-4">
                          <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${
                            exam.dynamic_status === 'Running'
                              ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 animate-pulse'
                              : exam.dynamic_status === 'Scheduled'
                              ? 'bg-amber-500/15 text-amber-300 border border-amber-500/30'
                              : 'bg-slate-800 text-slate-300 border border-slate-700'
                          }`}>
                            {exam.dynamic_status}
                          </span>
                        </td>
                        <td className="py-3.5 px-4 text-right">
                          <div className="flex items-center justify-end gap-2">
                            {/* Leaderboard button */}
                            <button
                              onClick={() => handleOpenLeaderboard(exam)}
                              className="px-2.5 py-1 rounded-lg bg-amber-500/10 hover:bg-amber-500/20 border border-amber-500/30 text-amber-300 font-semibold text-xs flex items-center gap-1 transition"
                              title="View student leaderboard"
                            >
                              <Trophy className="w-3.5 h-3.5" />
                              <span>Rankings</span>
                            </button>

                            {/* Review & Grade */}
                            {exam.has_submission ? (
                              <button
                                onClick={() => handleOpenGrading(exam)}
                                className="px-3 py-1 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white font-semibold text-xs flex items-center gap-1 shadow-md shadow-emerald-600/20 transition"
                              >
                                <Award className="w-3.5 h-3.5" />
                                <span>Grade</span>
                              </button>
                            ) : (
                              <span className="text-[11px] text-slate-500 italic">
                                Awaiting turn-in
                              </span>
                            )}
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
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
                <div className="pt-2 flex items-center justify-center gap-3">
                  <button
                    onClick={() => setAddStudentModalOpen(true)}
                    className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold shadow-md shadow-indigo-600/30 transition"
                  >
                    + Enroll First Student
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
                            <span className="text-[11px] text-slate-400 font-mono block">
                              Enrolled {enr.joined_at ? new Date(enr.joined_at).toLocaleDateString() : 'Active'}
                            </span>
                          </div>
                        </div>

                        <button
                          onClick={() => handleUnenrollStudent(enr.student_id, enr.student_name)}
                          className="p-1.5 rounded-lg text-slate-500 hover:text-rose-400 hover:bg-rose-500/10 transition"
                          title="Remove from Tuition"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
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
                      <span className="text-slate-400">
                        Active Cycle: <strong className="text-indigo-300">Cycle #{enr.active_cycle?.cycle_number || 1}</strong>
                      </span>
                      <span className="text-emerald-400 font-semibold font-mono">
                        {enr.active_cycle?.completed_classes || 0} / {tuition.cycle_length} Classes
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </main>

      {/* Class Attendance Date Picker & Topic Modal */}
      {activeClassData && (
        <Modal
          isOpen={dateModalOpen}
          onClose={() => setDateModalOpen(false)}
          title={`Class #${activeClassData.classNum} Attendance Record`}
          maxWidth="max-w-md"
        >
          <form onSubmit={handleSaveClassModal} className="space-y-4">
            <div>
              <label className="block text-xs font-semibold text-slate-300 mb-1">
                Attendance Status
              </label>
              <div className="grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => setIsCompletedState(true)}
                  className={`py-2 px-3 rounded-xl text-xs font-bold flex items-center justify-center gap-1.5 transition ${
                    isCompletedState
                      ? 'bg-emerald-600 text-white shadow-md shadow-emerald-600/30'
                      : 'bg-slate-800 text-slate-400'
                  }`}
                >
                  <CheckCircle2 className="w-4 h-4" />
                  <span>Completed</span>
                </button>
                <button
                  type="button"
                  onClick={() => setIsCompletedState(false)}
                  className={`py-2 px-3 rounded-xl text-xs font-bold flex items-center justify-center gap-1.5 transition ${
                    !isCompletedState
                      ? 'bg-rose-600 text-white shadow-md shadow-rose-600/30'
                      : 'bg-slate-800 text-slate-400'
                  }`}
                >
                  <X className="w-4 h-4" />
                  <span>Incomplete</span>
                </button>
              </div>
            </div>

            {isCompletedState && (
              <>
                <div>
                  <label className="block text-xs font-semibold text-slate-300 mb-1">
                    Class Held Date *
                  </label>
                  <input
                    type="date"
                    required
                    value={classDate}
                    onChange={(e) => setClassDate(e.target.value)}
                    className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-xs focus:outline-none focus:border-indigo-500"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-300 mb-1">
                    Lesson Topic / Subject Covered
                  </label>
                  <input
                    type="text"
                    value={classTopic}
                    onChange={(e) => setClassTopic(e.target.value)}
                    placeholder="e.g. Chapter 4: Electric Current & Circuits"
                    className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-xs focus:outline-none focus:border-indigo-500"
                  />
                </div>
              </>
            )}

            <div className="flex justify-end gap-2 pt-2 border-t border-slate-800">
              <button
                type="button"
                onClick={() => setDateModalOpen(false)}
                className="px-3.5 py-1.5 rounded-xl text-xs font-semibold text-slate-400 hover:text-slate-200"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={savingAttendance}
                className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold shadow-md shadow-indigo-600/30 transition disabled:opacity-50"
              >
                {savingAttendance ? 'Saving...' : 'Save Attendance'}
              </button>
            </div>
          </form>
        </Modal>
      )}

      {/* Cycle Reset Confirmation Modal */}
      {cycleToReset && (
        <Modal
          isOpen={resetModalOpen}
          onClose={() => setResetModalOpen(false)}
          title={`Archive Cycle #${cycleToReset.cycle_number} & Start Next Cycle`}
          maxWidth="max-w-md"
        >
          <div className="space-y-4">
            <p className="text-xs text-slate-300 leading-relaxed">
              All <strong>{tuition.cycle_length} classes</strong> have been attended for this cycle. Archiving will save this cycle to history and atomically initialize <strong>Cycle #{cycleToReset.cycle_number + 1}</strong> with fresh class attendance boxes.
            </p>
            <div className="flex justify-end gap-2 pt-2 border-t border-slate-800">
              <button
                type="button"
                onClick={() => setResetModalOpen(false)}
                className="px-3.5 py-1.5 rounded-xl text-xs text-slate-400 hover:text-slate-200"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmResetCycle}
                disabled={resettingCycle}
                className="px-4 py-2 rounded-xl bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-bold shadow-md shadow-emerald-600/30 transition disabled:opacity-50"
              >
                {resettingCycle ? 'Resetting...' : `Confirm & Start Cycle #${cycleToReset.cycle_number + 1}`}
              </button>
            </div>
          </div>
        </Modal>
      )}

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
        isOpen={authorExamModalOpen}
        onClose={() => setAuthorExamModalOpen(false)}
        students={allStudents}
        initialBatchId={tuition.id}
        initialCategory={authorCategory}
        onExamCreated={() => loadTuitionData()}
      />

      {selectedExamForGrading && selectedSubmissionForGrading && (
        <SubmissionsGradingModal
          isOpen={gradingModalOpen}
          onClose={() => setGradingModalOpen(false)}
          exam={selectedExamForGrading}
          submission={selectedSubmissionForGrading}
          onGraded={() => loadTuitionData()}
        />
      )}

      {selectedExamForLeaderboard && (
        <LeaderboardModal
          isOpen={leaderboardModalOpen}
          onClose={() => setLeaderboardModalOpen(false)}
          examId={selectedExamForLeaderboard.id}
          examTitle={selectedExamForLeaderboard.title}
        />
      )}
    </div>
  );
}
