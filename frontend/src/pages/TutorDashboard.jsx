import React, { useState, useEffect, useMemo } from 'react';
import Navbar from '../components/common/Navbar';
import WalletWidget from '../components/tutor/WalletWidget';
import StudentRoster from '../components/tutor/StudentRoster';
import CycleGrid from '../components/tutor/CycleGrid';
import AddStudentModal from '../components/tutor/AddStudentModal';
import AssignStudentModal from '../components/tutor/AssignStudentModal';
import ExamAuthoringModal from '../components/tutor/ExamAuthoringModal';
import SubmissionsGradingModal from '../components/tutor/SubmissionsGradingModal';
import TuitionBatchesModal from '../components/tutor/TuitionBatchesModal';
import LeaderboardModal from '../components/common/LeaderboardModal';
import StatusBadge from '../components/common/StatusBadge';
import { api } from '../api/client';
import {
  FileText,
  Plus,
  Calendar,
  Award,
  Users,
  Clock,
  ExternalLink,
  RefreshCw,
  CheckCircle2,
  Layers,
  Trophy,
  BookOpen,
  DollarSign,
  Edit2,
  Trash2,
  Eye,
  EyeOff,
  Sparkles,
  UserPlus,
  CalendarDays,
  Check,
} from 'lucide-react';

export default function TutorDashboard() {
  const [activeTab, setActiveTab] = useState('attendance'); // 'attendance' | 'batches' | 'exams'

  // Data states
  const [analytics, setAnalytics] = useState(null);
  const [students, setStudents] = useState([]);
  const [unassignedStudents, setUnassignedStudents] = useState([]);
  const [selectedStudentId, setSelectedStudentId] = useState(null);
  const [currentCycle, setCurrentCycle] = useState(null);
  const [batches, setBatches] = useState([]);
  const [tuitions, setTuitions] = useState([]);
  const [selectedTuitionId, setSelectedTuitionId] = useState('all');
  const [exams, setExams] = useState([]);

  // Loading states
  const [loadingAnalytics, setLoadingAnalytics] = useState(true);
  const [loadingStudents, setLoadingStudents] = useState(true);
  const [loadingUnassigned, setLoadingUnassigned] = useState(false);
  const [loadingCycle, setLoadingCycle] = useState(false);
  const [loadingBatches, setLoadingBatches] = useState(false);
  const [loadingExams, setLoadingExams] = useState(false);

  // Modals
  const [addStudentModalOpen, setAddStudentModalOpen] = useState(false);
  const [assignModalOpen, setAssignModalOpen] = useState(false);
  const [selectedStudentForAssign, setSelectedStudentForAssign] = useState(null);
  const [authorExamModalOpen, setAuthorExamModalOpen] = useState(false);
  const [batchModalOpen, setBatchModalOpen] = useState(false);
  const [selectedBatchToEdit, setSelectedBatchToEdit] = useState(null);
  const [initialBatchForExam, setInitialBatchForExam] = useState('');
  const [gradingModalOpen, setGradingModalOpen] = useState(false);
  const [selectedExamForGrading, setSelectedExamForGrading] = useState(null);
  const [selectedSubmissionForGrading, setSelectedSubmissionForGrading] = useState(null);
  const [leaderboardModalOpen, setLeaderboardModalOpen] = useState(false);
  const [selectedExamForLeaderboard, setSelectedExamForLeaderboard] = useState(null);

  // 1. Load Analytics
  const loadAnalytics = async () => {
    try {
      setLoadingAnalytics(true);
      const data = await api.getWalletAnalytics();
      setAnalytics(data);
    } catch (err) {
      console.error('Failed to load wallet analytics:', err);
    } finally {
      setLoadingAnalytics(false);
    }
  };

  // 2. Load Students
  const loadStudents = async () => {
    try {
      setLoadingStudents(true);
      const data = await api.getStudents();
      const list = Array.isArray(data) ? data : data.results || [];
      setStudents(list);

      if (list.length > 0 && !selectedStudentId) {
        setSelectedStudentId(list[0].student_id || list[0].id);
      }
    } catch (err) {
      console.error('Failed to load students:', err);
    } finally {
      setLoadingStudents(false);
    }
  };

  // 3. Load Unassigned Prospective Students
  const loadUnassignedStudents = async () => {
    try {
      setLoadingUnassigned(true);
      const data = await api.getUnassignedStudents();
      const list = Array.isArray(data) ? data : data.results || [];
      setUnassignedStudents(list);
    } catch (err) {
      console.error('Failed to load unassigned students:', err);
    } finally {
      setLoadingUnassigned(false);
    }
  };

  // 4. Load Tuitions & Batches
  const loadTuitions = async () => {
    try {
      setLoadingBatches(true);
      let list = [];
      try {
        const tData = await api.getTuitions();
        list = Array.isArray(tData) ? tData : tData.results || [];
      } catch (_) {}

      if (list.length === 0) {
        const bData = await api.getBatches();
        list = Array.isArray(bData) ? bData : bData.results || [];
      }
      setBatches(list);
      setTuitions(list);
    } catch (err) {
      console.error('Failed to load tuition batches:', err);
    } finally {
      setLoadingBatches(false);
    }
  };

  const loadBatches = loadTuitions;

  // 5. Load Active Cycle for selected student (scoped to selected tuition if specified)
  const loadStudentCycle = async (studentId, tuitionId = null) => {
    if (!studentId) {
      setCurrentCycle(null);
      return;
    }
    try {
      setLoadingCycle(true);
      let list = [];
      const isSpecificTuition = tuitionId && tuitionId !== 'all';

      if (isSpecificTuition) {
        try {
          const attData = await api.getAttendanceCycles(tuitionId, studentId);
          list = Array.isArray(attData) ? attData : attData.results || [];
        } catch (_) {}
      } else {
        try {
          const attData = await api.getAttendanceCycles(null, studentId);
          list = Array.isArray(attData) ? attData : attData.results || [];
        } catch (_) {}
      }

      if (list.length === 0 && !isSpecificTuition) {
        const data = await api.getCycles(studentId);
        list = Array.isArray(data) ? data : data.results || [];
      }

      const active = list.find((c) => c.status === 'ACTIVE') || list[0] || null;
      setCurrentCycle(active);
    } catch (err) {
      console.error('Failed to load cycle:', err);
    } finally {
      setLoadingCycle(false);
    }
  };

  // 6. Load Exams
  const loadExams = async () => {
    try {
      setLoadingExams(true);
      const data = await api.getExams();
      const list = Array.isArray(data) ? data : data.results || [];
      setExams(list);
    } catch (err) {
      console.error('Failed to load exams:', err);
    } finally {
      setLoadingExams(false);
    }
  };

  useEffect(() => {
    loadAnalytics();
    loadStudents();
    loadUnassignedStudents();
    loadTuitions();
    loadExams();
  }, []);

  useEffect(() => {
    if (selectedStudentId) {
      loadStudentCycle(selectedStudentId, selectedTuitionId);
    } else {
      setCurrentCycle(null);
    }
  }, [selectedStudentId, selectedTuitionId]);

  // Actions
  const handleToggleActive = async (studentId) => {
    try {
      await api.toggleStudentActive(studentId);
      loadStudents();
    } catch (err) {
      alert(`Action failed: ${err.message}`);
    }
  };

  const [authorCategory, setAuthorCategory] = useState('EXAM');

  const handleToggleClass = async (cycleId, classNo, completed, date = null, topic = '') => {
    const numToMatch = parseInt(classNo, 10);
    if (currentCycle) {
      const targetIso = completed ? (date ? new Date(date).toISOString() : new Date().toISOString()) : null;
      const updatedClasses = (currentCycle.classes_data || []).map((c) => {
        const cNum = parseInt(c.class_no ?? c.classNo, 10);
        if (cNum === numToMatch) {
          return {
            ...c,
            completed,
            date: targetIso,
            topic: completed ? topic : '',
          };
        }
        return c;
      });

      const completedCount = updatedClasses.filter((c) => c.completed).length;
      const totalCount = currentCycle.total_classes || currentCycle.cycle_length || 12;
      const feeSnapshot = currentCycle.fee_snapshot || currentCycle.tuition_fee || 0;
      const rate = totalCount > 0 ? feeSnapshot / totalCount : 0;
      const earned = Math.round(rate * completedCount * 100) / 100;
      const pending = Math.round((feeSnapshot - earned) * 100) / 100;

      setCurrentCycle({
        ...currentCycle,
        classes_data: updatedClasses,
        completed_classes: completedCount,
        earned_amount: earned,
        earned_revenue: earned,
        pending_amount: pending,
        pending_balance: pending,
        progress_percentage: Math.round((completedCount / totalCount) * 100),
      });
    }

    try {
      let res;
      const isTuitionCycle = Boolean(currentCycle?.enrollment || currentCycle?.tuition_id);
      if (isTuitionCycle) {
        try {
          res = await api.toggleAttendanceClass(cycleId, numToMatch, completed, date, topic);
        } catch (_) {
          res = await api.toggleClass(cycleId, numToMatch, completed, date, topic);
        }
      } else {
        try {
          res = await api.toggleClass(cycleId, numToMatch, completed, date, topic);
        } catch (_) {
          res = await api.toggleAttendanceClass(cycleId, numToMatch, completed, date, topic);
        }
      }
      if (res) {
        setCurrentCycle(res.cycle || res);
        loadAnalytics();
        loadTuitions();
      }
    } catch (err) {
      console.error('Toggle failed:', err);
      alert(`Toggle failed: ${err.message}`);
      loadStudentCycle(selectedStudentId, selectedTuitionId);
    }
  };

  const handleResetCycle = async (cycleId) => {
    try {
      let res;
      try {
        res = await api.resetAttendanceCycle(cycleId);
      } catch (_) {
        res = await api.resetCycle(cycleId);
      }
      setCurrentCycle(res.cycle || res);
      loadAnalytics();
      loadTuitions();
      alert(res.message || 'New cycle started successfully!');
    } catch (err) {
      alert(`Cycle reset failed: ${err.message}`);
    }
  };

  const openGradingModal = async (exam) => {
    try {
      const detail = await api.getExamDetail(exam.id);
      setSelectedExamForGrading(detail);
      setSelectedSubmissionForGrading(detail.submission);
      setGradingModalOpen(true);
    } catch (err) {
      alert(`Failed to load submission: ${err.message}`);
    }
  };

  const openLeaderboard = (exam) => {
    setSelectedExamForLeaderboard(exam);
    setLeaderboardModalOpen(true);
  };

  const handleTogglePublishResults = async (exam) => {
    try {
      await api.updateExam(exam.id, {
        is_results_published: !exam.is_results_published,
      });
      loadExams();
    } catch (err) {
      alert(`Failed to update status: ${err.message}`);
    }
  };

  const handleDeleteBatch = async (batchId) => {
    if (!window.confirm('Are you sure you want to delete this tuition batch?')) return;
    try {
      try {
        await api.deleteTuition(batchId);
      } catch (_) {
        await api.deleteBatch(batchId);
      }
      loadTuitions();
    } catch (err) {
      alert(`Delete failed: ${err.message}`);
    }
  };

  const handleScheduleForBatch = (batchId) => {
    setInitialBatchForExam(batchId);
    setAuthorExamModalOpen(true);
  };

  const selectedStudent = students.find((s) => s.student_id === selectedStudentId || s.id === selectedStudentId);
  const studentName = selectedStudent ? selectedStudent.full_name : 'Student';

  const selectedTuition = useMemo(() => {
    if (selectedTuitionId === 'all') return null;
    return tuitions.find((t) => t.id === selectedTuitionId || String(t.id) === String(selectedTuitionId)) || null;
  }, [tuitions, selectedTuitionId]);

  const filteredStudents = useMemo(() => {
    if (!selectedTuition) return students;
    const enrolledIds = (selectedTuition.enrollments || []).map((e) => e.student_id || e.student);
    if (selectedTuition.students) {
      enrolledIds.push(...selectedTuition.students);
    }
    return students.filter((s) => enrolledIds.includes(s.student_id || s.id));
  }, [students, selectedTuition]);

  const DAYS_ORDER = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

  const weeklyScheduleByDay = useMemo(() => {
    const schedule = {};
    DAYS_ORDER.forEach((day) => {
      schedule[day] = [];
    });

    tuitions.forEach((t) => {
      const routine = t.routine || t.weekly_routine || [];
      routine.forEach((slot) => {
        const dayMatch = DAYS_ORDER.find((d) => d.toLowerCase() === (slot.day || '').toLowerCase());
        if (dayMatch) {
          schedule[dayMatch].push({
            tuitionId: t.id,
            tuitionTitle: t.title || t.name,
            subject: t.subject || '',
            startTime: slot.start_time || slot.time || '18:00',
            endTime: slot.end_time || '19:30',
            studentCount: t.student_count || t.enrollment_count || t.enrollments?.length || 0,
            fee: t.tuition_fee || t.monthly_fee || 0,
          });
        }
      });
    });

    DAYS_ORDER.forEach((day) => {
      schedule[day].sort((a, b) => a.startTime.localeCompare(b.startTime));
    });

    return schedule;
  }, [tuitions]);

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      <Navbar />

      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
        {/* Section 1: Gamified Wallet Widget */}
        <WalletWidget analytics={analytics} loading={loadingAnalytics} />

        {/* Section 1.5: Incoming / Unassigned Prospective Students Panel */}
        {unassignedStudents.length > 0 && (
          <div className="p-5 rounded-2xl bg-gradient-to-r from-amber-500/10 via-indigo-500/10 to-purple-500/10 border border-amber-500/30 space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-2.5">
                <div className="w-9 h-9 rounded-xl bg-amber-500/20 text-amber-300 flex items-center justify-center border border-amber-500/30">
                  <UserPlus className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="font-extrabold text-slate-100 text-sm sm:text-base flex items-center gap-2">
                    Incoming / Unassigned Prospective Students
                    <span className="px-2 py-0.5 rounded-full text-xs bg-amber-500 text-slate-950 font-black">
                      {unassignedStudents.length} New
                    </span>
                  </h3>
                  <p className="text-xs text-slate-400">
                    Students selected you during public registration. Review and assign them to a Tuition batch.
                  </p>
                </div>
              </div>

              <button
                onClick={loadUnassignedStudents}
                className="p-2 rounded-xl bg-slate-800/80 hover:bg-slate-700 text-slate-400 hover:text-slate-200 border border-slate-700 transition"
                title="Refresh incoming students"
              >
                <RefreshCw className="w-4 h-4" />
              </button>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3.5">
              {unassignedStudents.map((st) => (
                <div
                  key={st.id}
                  className="p-4 rounded-xl bg-slate-900/90 border border-slate-700/70 hover:border-indigo-500/50 transition flex items-center justify-between gap-3"
                >
                  <div className="min-w-0">
                    <h4 className="font-bold text-slate-100 text-xs sm:text-sm truncate">
                      {st.full_name || st.username}
                    </h4>
                    <span className="text-[11px] text-indigo-400 font-mono block">
                      @{st.username}
                    </span>
                    <div className="flex flex-wrap items-center gap-2 text-[10px] text-slate-400 mt-1">
                      {st.grade_level && <span className="text-slate-300 font-semibold">{st.grade_level}</span>}
                      {st.institution && <span>• {st.institution}</span>}
                      <span>• Registered {new Date(st.created_at).toLocaleDateString()}</span>
                    </div>
                  </div>

                  <button
                    onClick={() => {
                      setSelectedStudentForAssign(st);
                      setAssignModalOpen(true);
                    }}
                    className="px-3 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs shadow-md shadow-indigo-600/30 transition flex items-center gap-1.5 flex-shrink-0"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    <span>Assign to Tuition</span>
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Section 2: Tab Navigation */}
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-800 pb-2">
          <div className="flex items-center gap-2">
            <button
              onClick={() => setActiveTab('attendance')}
              className={`flex items-center gap-2 py-2 px-4 rounded-xl text-xs font-bold transition ${
                activeTab === 'attendance'
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
              }`}
            >
              <Calendar className="w-4 h-4" />
              <span>Attendance & Cycles</span>
            </button>

            <button
              onClick={() => setActiveTab('batches')}
              className={`flex items-center gap-2 py-2 px-4 rounded-xl text-xs font-bold transition ${
                activeTab === 'batches'
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
              }`}
            >
              <Layers className="w-4 h-4" />
              <span>Tuition Batches & Routine</span>
              {tuitions.length > 0 && (
                <span className="px-1.5 py-0.2 rounded-full bg-slate-800 text-[10px] text-slate-300">
                  {tuitions.length}
                </span>
              )}
            </button>

            <button
              onClick={() => setActiveTab('exams')}
              className={`flex items-center gap-2 py-2 px-4 rounded-xl text-xs font-bold transition ${
                activeTab === 'exams'
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
              }`}
            >
              <FileText className="w-4 h-4" />
              <span>Exam Authoring & Grading</span>
              {exams.length > 0 && (
                <span className="px-1.5 py-0.2 rounded-full bg-slate-800 text-[10px] text-slate-300">
                  {exams.length}
                </span>
              )}
            </button>
          </div>

          <div className="flex items-center gap-2">
            {activeTab === 'batches' && (
              <button
                onClick={() => {
                  setSelectedBatchToEdit(null);
                  setBatchModalOpen(true);
                }}
                className="px-3.5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs flex items-center gap-1.5 shadow-md shadow-indigo-600/20 transition"
              >
                <Plus className="w-4 h-4" />
                <span>Create Tuition Batch</span>
              </button>
            )}

            {activeTab === 'exams' && (
              <div className="flex items-center gap-2">
                <button
                  onClick={() => {
                    setAuthorCategory('EXAM');
                    setInitialBatchForExam('');
                    setAuthorExamModalOpen(true);
                  }}
                  className="px-3.5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs flex items-center gap-1.5 shadow-md shadow-indigo-600/20 transition"
                >
                  <Plus className="w-4 h-4" />
                  <span>Schedule Exam</span>
                </button>
                <button
                  onClick={() => {
                    setAuthorCategory('ASSIGNMENT');
                    setInitialBatchForExam('');
                    setAuthorExamModalOpen(true);
                  }}
                  className="px-3.5 py-2 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-semibold text-xs flex items-center gap-1.5 shadow-md shadow-purple-600/20 transition"
                >
                  <Plus className="w-4 h-4" />
                  <span>Create Assignment</span>
                </button>
              </div>
            )}

          </div>
        </div>

        {/* Tab Content A: Attendance & Dynamic Cycle Engine */}
        {activeTab === 'attendance' && (
          <div className="space-y-4">
            {/* Tuition Selector Filter Bar */}
            <div className="p-3 rounded-2xl bg-slate-900/80 border border-slate-800 flex flex-wrap items-center gap-2">
              <span className="text-xs font-semibold text-slate-400 flex items-center gap-1.5 mr-2">
                <Layers className="w-3.5 h-3.5 text-indigo-400" />
                Select Tuition:
              </span>
              <button
                onClick={() => {
                  setSelectedTuitionId('all');
                  if (students.length > 0) setSelectedStudentId(students[0].student_id || students[0].id);
                }}
                className={`px-3 py-1.5 rounded-xl text-xs font-bold transition ${
                  selectedTuitionId === 'all'
                    ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                    : 'bg-slate-800 text-slate-400 hover:text-slate-200 hover:bg-slate-700'
                }`}
              >
                All Students ({students.length})
              </button>
              {tuitions.map((t) => {
                const isSelected = selectedTuitionId === t.id || String(selectedTuitionId) === String(t.id);
                const enrolledCount = t.student_count || t.enrollment_count || t.enrollments?.length || 0;
                return (
                  <button
                    key={t.id}
                    onClick={() => {
                      setSelectedTuitionId(t.id);
                      const enrolledIds = (t.enrollments || []).map((e) => e.student_id || e.student);
                      if (t.students) enrolledIds.push(...t.students);

                      // If current selected student is in this tuition, keep it; otherwise switch to first enrolled or null
                      if (selectedStudentId && enrolledIds.some((id) => String(id) === String(selectedStudentId))) {
                        loadStudentCycle(selectedStudentId, t.id);
                      } else if (enrolledIds.length > 0) {
                        setSelectedStudentId(enrolledIds[0]);
                      } else {
                        setSelectedStudentId(null);
                        setCurrentCycle(null);
                      }
                    }}
                    className={`px-3 py-1.5 rounded-xl text-xs font-bold transition flex items-center gap-1.5 ${
                      isSelected
                        ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                        : 'bg-slate-800 text-slate-400 hover:text-slate-200 hover:bg-slate-700'
                    }`}
                  >
                    <span>{t.title || t.name}</span>
                    <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-slate-900 text-slate-300">
                      {enrolledCount}
                    </span>
                  </button>
                );
              })}
            </div>

            {/* Tuition Summary Bar if specific tuition is selected */}
            {selectedTuition && (
              <div className="p-4 rounded-2xl bg-indigo-950/20 border border-indigo-500/20 flex flex-wrap items-center justify-between gap-4">
                <div>
                  <h4 className="font-extrabold text-slate-100 text-sm sm:text-base flex items-center gap-2">
                    <span>{selectedTuition.title}</span>
                    {selectedTuition.subject && (
                      <span className="text-xs text-indigo-400 font-semibold">({selectedTuition.subject})</span>
                    )}
                  </h4>
                  <div className="flex flex-wrap items-center gap-3 text-xs text-slate-400 mt-1">
                    <span>Cycle Length: <strong className="text-indigo-300 font-bold">{selectedTuition.cycle_length} Classes</strong></span>
                    <span>•</span>
                    <span>Fee: <strong className="text-emerald-400 font-bold">৳{selectedTuition.tuition_fee}</strong></span>
                    <span>•</span>
                    <span>Enrolled: <strong className="text-slate-200 font-bold">{selectedTuition.enrollments?.length || selectedTuition.students?.length || 0} Students</strong></span>
                  </div>
                </div>

                {selectedTuition.active_cycle_summary && (
                  <div className="flex items-center gap-2 text-xs">
                    <div className="px-3 py-1.5 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 font-bold">
                      Earned: ৳{selectedTuition.active_cycle_summary.total_earned}
                    </div>
                    <div className="px-3 py-1.5 rounded-xl bg-amber-500/10 border border-amber-500/20 text-amber-300 font-bold">
                      Pending: ৳{selectedTuition.active_cycle_summary.total_pending}
                    </div>
                  </div>
                )}
              </div>
            )}

            <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
              <div className="lg:col-span-4">
                <StudentRoster
                  students={filteredStudents}
                  selectedStudentId={selectedStudentId}
                  tuitionTitle={selectedTuition ? (selectedTuition.title || selectedTuition.name) : ''}
                  onSelectStudent={setSelectedStudentId}
                  onToggleActive={handleToggleActive}
                  onOpenAddModal={() => setAddStudentModalOpen(true)}
                  loading={loadingStudents}
                />
              </div>

              <div className="lg:col-span-8">
                <CycleGrid
                  cycle={currentCycle}
                  studentName={studentName}
                  tuitionTitle={selectedTuition ? (selectedTuition.title || selectedTuition.name) : ''}
                  onToggleClass={handleToggleClass}
                  onResetCycle={handleResetCycle}
                  onOpenAddStudent={() => setAddStudentModalOpen(true)}
                  loading={loadingCycle}
                />
              </div>
            </div>
          </div>
        )}

        {/* Tab Content B: Tuition Batches & Routine Management */}
        {activeTab === 'batches' && (
          <div className="glass-panel p-6 rounded-2xl space-y-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h3 className="text-xl font-bold text-slate-100 flex items-center gap-2">
                  <Layers className="w-5 h-5 text-indigo-400" />
                  Tuitions & Batch Schedules
                </h3>
                <p className="text-xs text-slate-400 mt-0.5">
                  Organize students into group tuitions with custom weekly days, times, and unified exams
                </p>
              </div>

              <button
                onClick={loadBatches}
                className="p-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-400 hover:text-slate-200 border border-slate-700 transition"
                title="Refresh Batches"
              >
                <RefreshCw className="w-4 h-4" />
              </button>
            </div>

            {loadingBatches ? (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="h-48 rounded-2xl bg-slate-800/40 animate-pulse" />
                ))}
              </div>
            ) : batches.length === 0 ? (
              <div className="text-center py-14 px-4 rounded-xl border border-dashed border-slate-800 text-slate-400">
                <Layers className="w-12 h-12 mx-auto text-slate-600 mb-2" />
                <p className="text-sm font-semibold text-slate-300">No tuition batches created yet</p>
                <p className="text-xs text-slate-500 mt-1 mb-4">
                  Create a batch to group multiple students together with a weekly routine and collective exams.
                </p>
                <button
                  onClick={() => {
                    setSelectedBatchToEdit(null);
                    setBatchModalOpen(true);
                  }}
                  className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold"
                >
                  Create Your First Batch
                </button>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
                {batches.map((batch) => (
                  <div
                    key={batch.id}
                    className="p-5 rounded-2xl bg-slate-900/70 border border-slate-800 hover:border-slate-700 transition flex flex-col justify-between space-y-4 group"
                  >
                    <div>
                      <div className="flex items-start justify-between gap-2">
                        <div>
                          <h4 className="font-extrabold text-slate-100 text-base group-hover:text-indigo-300 transition">
                            {batch.name}
                          </h4>
                          {batch.subject && (
                            <span className="text-xs text-indigo-400 font-semibold block">
                              {batch.subject}
                            </span>
                          )}
                        </div>

                        <div className="flex items-center gap-1">
                          <button
                            onClick={() => {
                              setSelectedBatchToEdit(batch);
                              setBatchModalOpen(true);
                            }}
                            className="p-1.5 rounded-lg text-slate-400 hover:text-slate-200 hover:bg-slate-800 transition"
                            title="Edit Batch"
                          >
                            <Edit2 className="w-3.5 h-3.5" />
                          </button>
                          <button
                            onClick={() => handleDeleteBatch(batch.id)}
                            className="p-1.5 rounded-lg text-slate-400 hover:text-rose-400 hover:bg-rose-500/10 transition"
                            title="Delete Batch"
                          >
                            <Trash2 className="w-3.5 h-3.5" />
                          </button>
                        </div>
                      </div>

                      {batch.description && (
                        <p className="text-xs text-slate-400 mt-1 line-clamp-2">
                          {batch.description}
                        </p>
                      )}

                      {/* Fee & Enrolled count */}
                      <div className="mt-3 flex flex-wrap items-center gap-2 text-xs">
                        <div className="px-2.5 py-1 rounded-lg bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 font-bold flex items-center gap-1">
                          <DollarSign className="w-3 h-3" />
                          <span>৳{batch.tuition_fee || batch.monthly_fee}/cycle</span>
                        </div>
                        <div className="px-2.5 py-1 rounded-lg bg-indigo-500/10 border border-indigo-500/20 text-indigo-300 font-semibold flex items-center gap-1">
                          <Clock className="w-3 h-3" />
                          <span>{batch.cycle_length || 12} Classes</span>
                        </div>
                        <div className="px-2.5 py-1 rounded-lg bg-slate-800 border border-slate-700 text-slate-300 font-medium flex items-center gap-1">
                          <Users className="w-3 h-3 text-indigo-400" />
                          <span>{batch.student_count || batch.enrollment_count || batch.enrollments?.length || 0} Students</span>
                        </div>
                      </div>

                      {/* Weekly Routine schedule */}
                      <div className="mt-4 pt-3 border-t border-slate-800">
                        <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block mb-1.5 flex items-center gap-1">
                          <Clock className="w-3 h-3 text-indigo-400" />
                          Weekly Routine Days & Time:
                        </span>
                        {(batch.routine || batch.weekly_routine) && (batch.routine || batch.weekly_routine).length > 0 ? (
                          <div className="flex flex-wrap gap-1.5">
                            {(batch.routine || batch.weekly_routine).map((slot, i) => (
                              <span
                                key={i}
                                className="px-2 py-0.5 rounded-md bg-slate-800 border border-slate-700 text-slate-200 text-[11px] font-mono"
                              >
                                {slot.day?.slice(0, 3)} @ {slot.start_time || slot.time} {slot.end_time ? `- ${slot.end_time}` : ''}
                              </span>
                            ))}
                          </div>
                        ) : (
                          <span className="text-xs text-slate-500 italic">No routine set</span>
                        )}
                      </div>
                    </div>

                    {/* Action buttons */}
                    <div className="pt-2 flex items-center gap-2">
                      <button
                        onClick={() => {
                          setAuthorCategory('EXAM');
                          handleScheduleForBatch(batch.id);
                        }}
                        className="flex-1 py-2 px-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs shadow-md shadow-indigo-600/20 flex items-center justify-center gap-1 transition"
                      >
                        <Plus className="w-3.5 h-3.5" />
                        <span>Schedule Exam</span>
                      </button>
                      <button
                        onClick={() => {
                          setAuthorCategory('ASSIGNMENT');
                          handleScheduleForBatch(batch.id);
                        }}
                        className="flex-1 py-2 px-2.5 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-semibold text-xs shadow-md shadow-purple-600/20 flex items-center justify-center gap-1 transition"
                      >
                        <Plus className="w-3.5 h-3.5" />
                        <span>Assignment</span>
                      </button>
                    </div>
                  </div>

                ))}
              </div>
            )}

            {/* Section 2: Weekly Routine Agenda / Master Calendar */}
            <div className="pt-6 border-t border-slate-800/80 space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <h4 className="text-base sm:text-lg font-bold text-slate-100 flex items-center gap-2">
                    <CalendarDays className="w-5 h-5 text-indigo-400" />
                    Weekly Routine Agenda & Master Calendar
                  </h4>
                  <p className="text-xs text-slate-400">
                    Unified 7-day schedule across all active tuitions and student cohorts
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-3">
                {DAYS_ORDER.map((day) => {
                  const daySlots = weeklyScheduleByDay[day] || [];
                  const isToday = new Date().toLocaleDateString('en-US', { weekday: 'long' }) === day;
                  return (
                    <div
                      key={day}
                      className={`p-3 rounded-2xl border transition flex flex-col min-h-[160px] ${
                        isToday
                          ? 'bg-indigo-950/30 border-indigo-500/50 shadow-sm shadow-indigo-500/10'
                          : 'bg-slate-900/60 border-slate-800'
                      }`}
                    >
                      <div className="flex items-center justify-between border-b border-slate-800 pb-2 mb-2.5">
                        <span className={`text-xs font-bold ${isToday ? 'text-indigo-300' : 'text-slate-300'}`}>
                          {day.slice(0, 3)}
                        </span>
                        {isToday && (
                          <span className="text-[9px] uppercase tracking-wider font-extrabold px-1.5 py-0.2 rounded-full bg-indigo-500 text-white">
                            Today
                          </span>
                        )}
                        <span className="text-[10px] text-slate-500 font-mono">
                          {daySlots.length} class{daySlots.length === 1 ? '' : 'es'}
                        </span>
                      </div>

                      <div className="flex-1 space-y-2">
                        {daySlots.length === 0 ? (
                          <div className="h-full flex items-center justify-center text-center py-6">
                            <span className="text-[11px] text-slate-600 italic">No classes</span>
                          </div>
                        ) : (
                          daySlots.map((slot, sIdx) => (
                            <div
                              key={sIdx}
                              className="p-2 rounded-xl bg-slate-800/90 border border-slate-700/60 text-xs space-y-1 hover:border-indigo-500/40 transition"
                            >
                              <div className="font-bold text-slate-200 text-[11px] truncate" title={slot.tuitionTitle}>
                                {slot.tuitionTitle}
                              </div>
                              <div className="flex items-center justify-between text-[10px] text-slate-400 font-mono">
                                <span className="text-indigo-300 font-semibold">
                                  {slot.startTime} - {slot.endTime}
                                </span>
                                <span className="px-1.5 py-0.2 rounded-md bg-slate-900 text-slate-400">
                                  {slot.studentCount}s
                                </span>
                              </div>
                            </div>
                          ))
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        )}

        {/* Tab Content C: Exam Management & Submissions Review */}
        {activeTab === 'exams' && (
          <div className="glass-panel p-6 rounded-2xl">
            <div className="flex items-center justify-between mb-6">
              <div>
                <h3 className="text-xl font-bold text-slate-100 flex items-center gap-2">
                  <FileText className="w-5 h-5 text-indigo-400" />
                  Exam Management, Leaderboards & Grading
                </h3>
                <p className="text-xs text-slate-400 mt-0.5">
                  Author KaTeX & MCQ exams, view ranked leaderboards, and grade CQ submissions
                </p>
              </div>

              <button
                onClick={loadExams}
                className="p-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-400 hover:text-slate-200 border border-slate-700 transition"
                title="Refresh Exams"
              >
                <RefreshCw className="w-4 h-4" />
              </button>
            </div>

            {loadingExams ? (
              <div className="space-y-3">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="h-16 rounded-xl bg-slate-800/40 animate-pulse" />
                ))}
              </div>
            ) : exams.length === 0 ? (
              <div className="text-center py-12 px-4 rounded-xl border border-dashed border-slate-800 text-slate-400">
                <FileText className="w-12 h-12 mx-auto text-slate-600 mb-2" />
                <p className="text-sm font-semibold text-slate-300">No exams scheduled yet</p>
                <p className="text-xs text-slate-500 mt-1 mb-4">
                  Use our TipTap WYSIWYG editor with LaTeX & smart MCQ parser to schedule exams
                </p>
                <button
                  onClick={() => {
                    setInitialBatchForExam('');
                    setAuthorExamModalOpen(true);
                  }}
                  className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-semibold"
                >
                  Schedule Your First Exam
                </button>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-left text-sm border-collapse">
                  <thead>
                    <tr className="border-b border-slate-800 text-[11px] font-bold text-slate-400 uppercase tracking-wider">
                      <th className="py-3 px-4">Title</th>
                      <th className="py-3 px-4">Category</th>
                      <th className="py-3 px-4">Format</th>
                      <th className="py-3 px-4">Assigned To</th>
                      <th className="py-3 px-4">Schedule / Deadline</th>
                      <th className="py-3 px-4">Marks</th>
                      <th className="py-3 px-4">Status</th>
                      <th className="py-3 px-4">Results</th>
                      <th className="py-3 px-4 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/60">
                    {exams.map((exam) => (
                      <tr key={exam.id} className="hover:bg-slate-800/30 transition">
                        <td className="py-3 px-4 font-semibold text-slate-200">
                          {exam.title}
                        </td>
                        <td className="py-3 px-4">
                          {exam.category === 'ASSIGNMENT' ? (
                            <span className="px-2 py-0.5 rounded-full text-[10px] font-mono font-bold bg-purple-500/20 text-purple-300 border border-purple-500/30">
                              ASSIGNMENT
                            </span>
                          ) : (
                            <span className="px-2 py-0.5 rounded-full text-[10px] font-mono font-bold bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                              EXAM
                            </span>
                          )}
                        </td>
                        <td className="py-3 px-4">
                          <span
                            className={`px-2 py-0.5 rounded-full text-[10px] font-mono font-bold ${
                              exam.exam_type === 'MCQ'
                                ? 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                                : exam.exam_type === 'CQ'
                                ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                                : 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                            }`}
                          >
                            {exam.exam_type || 'HYBRID'}
                            {exam.mcq_count > 0 && ` (${exam.mcq_count}Q)`}
                          </span>
                        </td>
                        <td className="py-3 px-4 text-xs">
                          {exam.batch_name ? (
                            <span className="px-2 py-0.5 rounded-lg bg-indigo-900/40 border border-indigo-500/30 text-indigo-300 font-semibold text-[11px]">
                              Batch: {exam.batch_name}
                            </span>
                          ) : (
                            <span className="text-slate-300 font-medium">{exam.student_name}</span>
                          )}
                        </td>
                        <td className="py-3 px-4 text-xs text-slate-400">
                          {exam.category === 'ASSIGNMENT' ? (
                            <span className="text-purple-300 font-mono">
                              Deadline:{' '}
                              {new Date(exam.end_time).toLocaleDateString(undefined, {
                                month: 'short',
                                day: 'numeric',
                                hour: '2-digit',
                                minute: '2-digit',
                              })}
                            </span>
                          ) : (
                            <span>
                              {new Date(exam.start_time).toLocaleDateString(undefined, {
                                month: 'short',
                                day: 'numeric',
                                hour: '2-digit',
                                minute: '2-digit',
                              })}
                            </span>
                          )}
                        </td>

                        <td className="py-3 px-4 text-xs font-bold text-emerald-400">
                          {exam.total_marks}
                        </td>
                        <td className="py-3 px-4">
                          <StatusBadge status={exam.dynamic_status} />
                        </td>
                        <td className="py-3 px-4">
                          <button
                            onClick={() => handleTogglePublishResults(exam)}
                            className={`px-2 py-1 rounded-lg text-[10px] font-bold flex items-center gap-1 transition ${
                              exam.is_results_published
                                ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                                : 'bg-slate-800 text-slate-400 border border-slate-700 hover:text-slate-200'
                            }`}
                            title="Click to toggle results and solution visibility"
                          >
                            {exam.is_results_published ? (
                              <>
                                <Eye className="w-3 h-3" />
                                <span>Published</span>
                              </>
                            ) : (
                              <>
                                <EyeOff className="w-3 h-3" />
                                <span>Hidden</span>
                              </>
                            )}
                          </button>
                        </td>
                        <td className="py-3 px-4 text-right">
                          <div className="flex items-center justify-end gap-2">
                            {/* Leaderboard button */}
                            <button
                              onClick={() => openLeaderboard(exam)}
                              className="px-2.5 py-1 rounded-lg bg-amber-500/10 hover:bg-amber-500/20 border border-amber-500/30 text-amber-300 font-semibold text-xs flex items-center gap-1 transition"
                              title="View student leaderboard"
                            >
                              <Trophy className="w-3.5 h-3.5" />
                              <span>Rankings</span>
                            </button>

                            {/* Review & Grade */}
                            {exam.has_submission ? (
                              <button
                                onClick={() => openGradingModal(exam)}
                                className="px-3 py-1 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white font-semibold text-xs flex items-center gap-1 shadow-md shadow-emerald-600/20"
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
      </main>

      {/* Modals */}
      <AddStudentModal
        isOpen={addStudentModalOpen}
        onClose={() => setAddStudentModalOpen(false)}
        tuitions={tuitions}
        initialTuitionId={selectedTuitionId !== 'all' ? selectedTuitionId : ''}
        onStudentAdded={(newStudent, assignedTuitionId) => {
          loadStudents();
          loadTuitions();
          loadAnalytics();
          if (newStudent?.id) {
            if (assignedTuitionId && assignedTuitionId !== 'all') {
              setSelectedTuitionId(assignedTuitionId);
            }
            setSelectedStudentId(newStudent.id);
          }
        }}
      />

      <AssignStudentModal
        isOpen={assignModalOpen}
        onClose={() => {
          setAssignModalOpen(false);
          setSelectedStudentForAssign(null);
        }}
        student={selectedStudentForAssign}
        tuitions={tuitions}
        onAssigned={() => {
          loadUnassignedStudents();
          loadTuitions();
          loadStudents();
          loadAnalytics();
        }}
      />

      <TuitionBatchesModal
        isOpen={batchModalOpen}
        onClose={() => setBatchModalOpen(false)}
        allStudents={students}
        batchToEdit={selectedBatchToEdit}
        onBatchSaved={() => {
          loadTuitions();
          loadBatches();
          loadAnalytics();
        }}
      />

      <ExamAuthoringModal
        isOpen={authorExamModalOpen}
        onClose={() => setAuthorExamModalOpen(false)}
        students={students}
        initialStudentId={selectedStudentId}
        initialBatchId={initialBatchForExam}
        initialCategory={authorCategory}
        onExamCreated={() => {
          loadExams();
          setActiveTab('exams');
        }}
      />


      {selectedExamForGrading && selectedSubmissionForGrading && (
        <SubmissionsGradingModal
          isOpen={gradingModalOpen}
          onClose={() => setGradingModalOpen(false)}
          exam={selectedExamForGrading}
          submission={selectedSubmissionForGrading}
          onGraded={() => {
            loadExams();
            loadAnalytics();
          }}
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
