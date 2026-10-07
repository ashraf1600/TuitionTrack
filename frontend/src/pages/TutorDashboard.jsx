import React, { useState, useEffect, useMemo } from 'react';
import { notify } from '../utils/toast';
import { useNavigate } from 'react-router-dom';
import Navbar from '../components/common/Navbar';
import WalletWidget from '../components/tutor/WalletWidget';
import StudentRoster from '../components/tutor/StudentRoster';
import SharedCycleBoard from '../components/tutor/SharedCycleBoard';
import ConnectionRequestsPanel from '../components/tutor/ConnectionRequestsPanel';
import TodayClassesPanel from '../components/tutor/TodayClassesPanel';
import AddStudentModal from '../components/tutor/AddStudentModal';
import ExamAuthoringModal from '../components/tutor/ExamAuthoringModal';
import ExamManager from '../components/tutor/ExamManager';
import TuitionBatchesModal from '../components/tutor/TuitionBatchesModal';
import HomeworkManager from '../components/tutor/HomeworkManager';
import { useAuth } from '../context/AuthContext';
import { api } from '../api/client';

// Sat-first canonical week order shared with TuitionWorkspace (Sat -> Fri for BD context).
// Keep this single source consistent everywhere weekly routines are rendered/sorted.
const DAYS_ORDER = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
const normId = (s) => String(s?.student_id ?? s?.id ?? s ?? '');
const isNotFoundError = (err) => /404|not found/i.test(err?.message || '');
const timeToMinutes = (t) => {
  const m = String(t || '18:00').match(/(\d{1,2}):(\d{2})/);
  if (!m) return 18 * 60;
  return parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
};
import {
  FileText,
  Plus,
  Calendar,
  Award,
  Users,
  Clock,
  ExternalLink,
  ChevronRight,
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
  const navigate = useNavigate();
  const { user } = useAuth();
  const [activeTab, setActiveTab] = useState('batches'); // 'batches' | 'homework' | 'attendance' | 'exams'

  // Data states
  const [analytics, setAnalytics] = useState(null);
  const [students, setStudents] = useState([]);
  const [unassignedStudents, setUnassignedStudents] = useState([]);
  const [selectedStudentId, setSelectedStudentId] = useState(null);
  const [batches, setBatches] = useState([]);
  const [tuitions, setTuitions] = useState([]);
  const [selectedTuitionId, setSelectedTuitionId] = useState(null);
  const [exams, setExams] = useState([]);

  // Loading states
  const [loadingAnalytics, setLoadingAnalytics] = useState(true);
  const [loadingStudents, setLoadingStudents] = useState(true);
  const [loadingUnassigned, setLoadingUnassigned] = useState(false);
  const [loadingBatches, setLoadingBatches] = useState(false);
  const [loadingExams, setLoadingExams] = useState(false);

  // Modals
  const [addStudentModalOpen, setAddStudentModalOpen] = useState(false);
  const [authorExamModalOpen, setAuthorExamModalOpen] = useState(false);
  const [batchModalOpen, setBatchModalOpen] = useState(false);
  const [selectedBatchToEdit, setSelectedBatchToEdit] = useState(null);
  const [initialBatchForExam, setInitialBatchForExam] = useState('');

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
        setSelectedStudentId(normId(list[0]));
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

  // Actions
  const handleToggleActive = async (studentId) => {
    try {
      await api.toggleStudentActive(studentId);
      loadStudents();
    } catch (err) {
      notify(`Action failed: ${err.message}`);
    }
  };

  const [authorCategory, setAuthorCategory] = useState('EXAM');

  // The cycle belongs to the tuition group: one board, shared by every student in it.
  const handleCycleChange = (tuitionId, cycle) => {
    setTuitions((prev) => prev.map((t) => (String(t.id) === String(tuitionId) ? { ...t, active_cycle: cycle } : t)));
    setBatches((prev) => prev.map((t) => (String(t.id) === String(tuitionId) ? { ...t, active_cycle: cycle } : t)));
    loadAnalytics();
    loadTuitions();
  };

  const refreshRoster = () => {
    loadUnassignedStudents();
    loadTuitions();
    loadStudents();
    loadAnalytics();
  };

  const handleDeleteBatch = async (batchId) => {
    if (!window.confirm('Delete this tuition group? Its students and exams are removed from it. What it has already earned stays in your lifetime earnings.')) return;
    try {
      await api.deleteTuition(batchId);
      loadTuitions();
      loadAnalytics();
      loadUnassignedStudents();
    } catch (err) {
      notify(`Delete failed: ${err.message}`);
    }
  };

  const handleScheduleForBatch = (batchId) => {
    setInitialBatchForExam(batchId);
    setAuthorExamModalOpen(true);
  };

  // No "all students" view any more: the tracker is always one tuition group.
  const selectedTuition = useMemo(() => {
    return tuitions.find((t) => String(t.id) === String(selectedTuitionId)) || tuitions[0] || null;
  }, [tuitions, selectedTuitionId]);

  const filteredStudents = useMemo(() => {
    if (!selectedTuition) return students;
    const enrolledSet = new Set(
      [
        ...((selectedTuition.enrollments || []).map((e) => String(e.student_id ?? e.student ?? e))),
        ...((selectedTuition.students || []).map((s) => String(s?.student_id ?? s?.id ?? s))),
        ...((selectedTuition.student_ids || []).map((s) => String(s))),
      ]
    );
    return students.filter((s) => enrolledSet.has(normId(s)));
  }, [students, selectedTuition]);

  // DAYS_ORDER is defined once at module top (Sat-first canonical order).
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
      schedule[day].sort((a, b) => timeToMinutes(a.startTime) - timeToMinutes(b.startTime));
    });

    return schedule;
  }, [tuitions]);

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      <Navbar />

      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
        {/* Page header & quick actions */}
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-2xl font-extrabold text-slate-100">Tutor dashboard</h1>
            <p className="text-sm text-slate-400 mt-0.5">
              {tuitions.length} tuition group{tuitions.length === 1 ? '' : 's'} · {students.length} student{students.length === 1 ? '' : 's'}
              {unassignedStudents.length > 0 && (
                <span className="text-amber-300"> · {unassignedStudents.length} waiting for a group</span>
              )}
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <button
              onClick={() => {
                setSelectedBatchToEdit(null);
                setBatchModalOpen(true);
              }}
              className="px-4 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-xs flex items-center gap-1.5 shadow-lg shadow-indigo-600/25 transition"
            >
              <Plus className="w-4 h-4" />
              New tuition group
            </button>
            <button
              onClick={() => setAddStudentModalOpen(true)}
              className="px-4 py-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-100 border border-slate-700 font-semibold text-xs flex items-center gap-1.5 transition"
            >
              <UserPlus className="w-4 h-4 text-indigo-400" />
              Add student
            </button>
            <button
              onClick={() => {
                setAuthorCategory('EXAM');
                setInitialBatchForExam('');
                setAuthorExamModalOpen(true);
              }}
              disabled={tuitions.length === 0}
              title={tuitions.length === 0 ? 'Create a tuition group first' : 'Schedule an exam for a group'}
              className="px-4 py-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-100 border border-slate-700 font-semibold text-xs flex items-center gap-1.5 transition disabled:opacity-50"
            >
              <FileText className="w-4 h-4 text-indigo-400" />
              Schedule exam
            </button>
          </div>
        </div>

        {/* Tutor Invite Code Banner */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-5 rounded-2xl bg-gradient-to-r from-indigo-950/40 via-purple-950/20 to-slate-900 border border-indigo-500/20 shadow-lg shadow-indigo-950/20">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-indigo-500/15 border border-indigo-500/30 flex items-center justify-center text-indigo-400 flex-shrink-0">
              <Sparkles className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="text-xs font-bold text-slate-200 uppercase tracking-wider">Your Student Invite Code</span>
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-indigo-500/20 text-indigo-300 border border-indigo-500/30 font-semibold">6-char code</span>
              </div>
              <p className="text-xs text-slate-400 mt-0.5">
                Share this code with prospective students. They enter it on their portal to connect with you.
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2 flex-shrink-0">
            <span className="font-mono text-base font-black text-indigo-200 tracking-widest bg-slate-900/90 px-3.5 py-1.5 rounded-xl border border-indigo-500/40 select-all">
              {user?.tutor_code || '—'}
            </span>
            <button
              type="button"
              onClick={() => {
                if (user?.tutor_code) {
                  navigator.clipboard.writeText(user.tutor_code);
                  notify.success(`Invite code "${user.tutor_code}" copied to clipboard!`);
                }
              }}
              className="px-3.5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold transition flex items-center gap-1.5 shadow-md shadow-indigo-600/25"
            >
              Copy Code
            </button>
          </div>
        </div>

        {/* Students who asked to join, or have no group yet */}
        <ConnectionRequestsPanel
          students={unassignedStudents}
          tuitions={tuitions}
          onChanged={refreshRoster}
          onRefresh={loadUnassignedStudents}
          onCreateTuition={() => {
            setSelectedBatchToEdit(null);
            setBatchModalOpen(true);
          }}
        />

        {/* Routine -> tracker: today's classes and any scheduled class that was never recorded */}
        <TodayClassesPanel
          tuitions={tuitions}
          onChanged={() => {
            loadTuitions();
            loadAnalytics();
          }}
        />

        {/* Tuition Wallet (tutor only) */}
        <WalletWidget
          analytics={analytics}
          loading={loadingAnalytics}
          onOpenTuition={(id) => navigate(`/tuitions/${id}`)}
        />

        {/* Section 2: Tab Navigation */}
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-800 pb-2">
          <div className="flex items-center gap-2">
            <button
              onClick={() => setActiveTab('batches')}
              className={`flex items-center gap-2 py-2 px-4 rounded-xl text-xs font-bold transition ${
                activeTab === 'batches'
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
              }`}
            >
              <Layers className="w-4 h-4" />
              <span>Tuition groups</span>
              {tuitions.length > 0 && (
                <span className="px-1.5 py-0.2 rounded-full bg-slate-800 text-[10px] text-slate-300">
                  {tuitions.length}
                </span>
              )}
            </button>

            <button
              onClick={() => setActiveTab('attendance')}
              className={`flex items-center gap-2 py-2 px-4 rounded-xl text-xs font-bold transition ${
                activeTab === 'attendance'
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
              }`}
            >
              <Calendar className="w-4 h-4" />
              <span>Class tracker</span>
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
              <span>Exams</span>
              {exams.length > 0 && (
                <span className="px-1.5 py-0.2 rounded-full bg-slate-800 text-[10px] text-slate-300">
                  {exams.length}
                </span>
              )}
            </button>

            <button
              onClick={() => setActiveTab('homework')}
              className={`flex items-center gap-2 py-2 px-4 rounded-xl text-xs font-bold transition ${
                activeTab === 'homework'
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
              }`}
            >
              <BookOpen className="w-4 h-4" />
              <span>Homework</span>
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
                <span>New tuition group</span>
              </button>
            )}


          </div>
        </div>

        {/* Tab Content A: Shared class tracker (one cycle per tuition group) */}
        {activeTab === 'attendance' && (
          <div className="space-y-4">
            {tuitions.length === 0 ? (
              <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-900/40 p-10 text-center">
                <Layers className="w-10 h-10 mx-auto text-slate-600 mb-3" />
                <p className="text-sm font-semibold text-slate-200">Create a tuition group to start tracking classes</p>
                <p className="text-xs text-slate-400 mt-1 mb-4 max-w-md mx-auto">
                  Each group has one class tracker that all of its students share.
                </p>
                <button
                  onClick={() => {
                    setSelectedBatchToEdit(null);
                    setBatchModalOpen(true);
                  }}
                  className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold"
                >
                  New tuition group
                </button>
              </div>
            ) : (
              <>
                {/* Tuition group picker */}
                <div className="flex flex-wrap items-center gap-2">
                  {tuitions.map((t) => {
                    const isSelected = selectedTuition && String(selectedTuition.id) === String(t.id);
                    const cyc = t.active_cycle;
                    return (
                      <button
                        key={t.id}
                        onClick={() => setSelectedTuitionId(t.id)}
                        className={`px-3.5 py-2 rounded-xl text-xs font-bold transition flex items-center gap-2 border ${
                          isSelected
                            ? 'bg-indigo-600 border-indigo-500 text-white shadow-md shadow-indigo-600/30'
                            : 'bg-slate-900 border-slate-800 text-slate-300 hover:border-slate-600'
                        }`}
                      >
                        <span>{t.title || t.name}</span>
                        {cyc && (
                          <span className={`text-[10px] px-1.5 py-0.5 rounded-full ${isSelected ? 'bg-indigo-500/60' : 'bg-slate-800 text-slate-400'}`}>
                            {cyc.completed_classes}/{cyc.total_classes}
                          </span>
                        )}
                      </button>
                    );
                  })}
                  {selectedTuition && (
                    <button
                      onClick={() => navigate(`/tuitions/${selectedTuition.id}`)}
                      className="ml-auto px-3.5 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 border border-slate-700 text-slate-200 font-semibold text-xs flex items-center gap-1.5 transition"
                    >
                      <span>Open workspace</span>
                      <ChevronRight className="w-4 h-4" />
                    </button>
                  )}
                </div>

                {selectedTuition && (
                  <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
                    <div className="lg:col-span-8">
                      <SharedCycleBoard
                        cycle={selectedTuition.active_cycle}
                        tuitionTitle={selectedTuition.title || selectedTuition.name}
                        studentCount={selectedTuition.enrolled_count ?? selectedTuition.enrollments?.length ?? 0}
                        onCycleChange={(cycle) => handleCycleChange(selectedTuition.id, cycle)}
                        onAddStudent={() => setAddStudentModalOpen(true)}
                      />
                    </div>
                    <div className="lg:col-span-4">
                      <StudentRoster
                        students={filteredStudents}
                        selectedStudentId={selectedStudentId}
                        tuitionTitle={selectedTuition.title || selectedTuition.name}
                        onSelectStudent={setSelectedStudentId}
                        onToggleActive={handleToggleActive}
                        onOpenAddModal={() => setAddStudentModalOpen(true)}
                        loading={loadingStudents}
                      />
                    </div>
                  </div>
                )}
              </>
            )}
          </div>
        )}

        {/* Tab Content B: Tuition Batches & Routine Management */}
        {activeTab === 'batches' && (
          <div className="glass-panel p-6 rounded-2xl space-y-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h3 className="text-xl font-bold text-slate-100 flex items-center gap-2">
                  <Layers className="w-5 h-5 text-indigo-400" />
                  Tuition groups
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
                <p className="text-sm font-semibold text-slate-300">No tuition groups yet</p>
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
                  Create your first group
                </button>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
                {batches.map((batch) => {
                  const tuitionTitle = batch.title || batch.name || 'Untitled Tuition';
                  const tuitionFee = batch.tuition_fee || batch.monthly_fee || 0;
                  const cycleLength = batch.cycle_length || 12;
                  const studentCount = batch.student_count || batch.enrolled_count || batch.enrollments?.length || batch.students?.length || 0;
                  const routineSlots = batch.routine || batch.weekly_routine || [];

                  return (
                    <div
                      key={batch.id}
                      onClick={() => navigate(`/tuitions/${batch.id}`)}
                      className="p-5 rounded-2xl bg-slate-900/80 border border-slate-800 hover:border-indigo-500/50 hover:shadow-xl hover:shadow-indigo-500/10 cursor-pointer transition-all duration-200 flex flex-col justify-between space-y-4 group"
                    >
                      <div>
                        {/* Card Header */}
                        <div className="flex items-start justify-between gap-2">
                          <div className="min-w-0 flex-1">
                            <h4 className="font-extrabold text-slate-100 text-base sm:text-lg group-hover:text-indigo-300 transition truncate">
                              {tuitionTitle}
                            </h4>
                            {batch.subject && (
                              <span className="text-xs text-indigo-400 font-semibold block mt-0.5">
                                {batch.subject}
                              </span>
                            )}
                          </div>

                          <div className="flex items-center gap-1 flex-shrink-0" onClick={(e) => e.stopPropagation()}>
                            <button
                              onClick={() => {
                                setSelectedBatchToEdit(batch);
                                setBatchModalOpen(true);
                              }}
                              className="p-1.5 rounded-lg text-slate-400 hover:text-slate-200 hover:bg-slate-800 transition"
                              title="Edit Tuition Settings"
                            >
                              <Edit2 className="w-3.5 h-3.5" />
                            </button>
                            <button
                              onClick={() => handleDeleteBatch(batch.id)}
                              className="p-1.5 rounded-lg text-slate-400 hover:text-rose-400 hover:bg-rose-500/10 transition"
                              title="Delete Tuition"
                            >
                              <Trash2 className="w-3.5 h-3.5" />
                            </button>
                          </div>
                        </div>

                        {batch.description && (
                          <p className="text-xs text-slate-400 mt-2 line-clamp-2">
                            {batch.description}
                          </p>
                        )}

                        {/* Metric Badges */}
                        <div className="mt-3.5 flex flex-wrap items-center gap-2 text-xs">
                          <div className="px-2.5 py-1 rounded-lg bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 font-bold flex items-center gap-1">
                            <DollarSign className="w-3 h-3" />
                            <span>৳{Number(tuitionFee).toLocaleString()} per cycle</span>
                          </div>
                          <div className="px-2.5 py-1 rounded-lg bg-indigo-500/10 border border-indigo-500/20 text-indigo-300 font-semibold flex items-center gap-1">
                            <Clock className="w-3 h-3" />
                            <span>{cycleLength} Classes</span>
                          </div>
                          <div className="px-2.5 py-1 rounded-lg bg-slate-800 border border-slate-700 text-slate-300 font-medium flex items-center gap-1">
                            <Users className="w-3 h-3 text-indigo-400" />
                            <span>{studentCount} Students</span>
                          </div>
                        </div>

                        {/* Shared cycle progress for the whole group */}
                        {batch.active_cycle && (
                          <div className="mt-4">
                            <div className="flex items-center justify-between text-[11px] text-slate-400 mb-1">
                              <span>Cycle #{batch.active_cycle.cycle_number} · {batch.active_cycle.completed_classes}/{batch.active_cycle.total_classes} classes</span>
                              <span className="font-mono text-emerald-400 font-semibold">৳{Number(batch.active_cycle.earned_revenue || 0).toLocaleString()} earned</span>
                            </div>
                            <div className="h-1.5 rounded-full bg-slate-800 overflow-hidden">
                              <div
                                className="h-full bg-gradient-to-r from-indigo-500 to-emerald-400 transition-all duration-500"
                                style={{ width: `${batch.active_cycle.progress_percent || 0}%` }}
                              />
                            </div>
                          </div>
                        )}

                        {/* Scheduled Weekly Routine Pills */}
                        <div className="mt-4 pt-3 border-t border-slate-800">
                          <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block mb-1.5 flex items-center gap-1">
                            <Clock className="w-3 h-3 text-indigo-400" />
                            Weekly Routine Days & Time:
                          </span>
                          {routineSlots.length > 0 ? (
                            <div className="flex flex-wrap gap-1.5">
                              {routineSlots.map((slot, i) => (
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

                      {/* Navigation CTA & Actions */}
                      <div className="pt-2 space-y-2" onClick={(e) => e.stopPropagation()}>
                        <button
                          onClick={() => navigate(`/tuitions/${batch.id}`)}
                          className="w-full py-2.5 px-3 rounded-xl bg-gradient-to-r from-indigo-600 via-indigo-500 to-purple-600 hover:from-indigo-500 hover:to-purple-500 text-white font-bold text-xs shadow-md shadow-indigo-600/25 flex items-center justify-center gap-1.5 transition group/btn"
                        >
                          <span>Open Tuition Workspace</span>
                          <ChevronRight className="w-4 h-4 group-hover/btn:translate-x-0.5 transition-transform" />
                        </button>

                        <div className="flex items-center gap-2">
                          <button
                            onClick={() => {
                              setSelectedBatchToEdit(batch);
                              setBatchModalOpen(true);
                            }}
                            className="flex-1 py-1.5 px-2 rounded-lg bg-indigo-950/40 hover:bg-indigo-900/50 text-indigo-300 hover:text-indigo-200 font-semibold text-xs border border-indigo-800/40 flex items-center justify-center gap-1 transition"
                            title="Enroll and Manage Students"
                          >
                            <UserPlus className="w-3 h-3 text-indigo-400" />
                            <span>Enroll Students ({studentCount})</span>
                          </button>
                          <button
                            onClick={() => {
                              setAuthorCategory('EXAM');
                              handleScheduleForBatch(batch.id);
                            }}
                            className="flex-1 py-1.5 px-2 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 font-semibold text-xs border border-slate-700/60 flex items-center justify-center gap-1 transition"
                          >
                            <Plus className="w-3 h-3 text-indigo-400" />
                            <span>Schedule Exam</span>
                          </button>
                        </div>
                      </div>
                    </div>
                  );
                })}
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

        {/* Tab Content C: Exams & assignments */}
        {activeTab === 'exams' && (
          <ExamManager
            exams={exams}
            loading={loadingExams}
            students={students}
            onReload={loadExams}
          />
        )}

        {/* Tab Content D: Homework management */}
        {activeTab === 'homework' && (
          <div className="glass-panel p-6 rounded-2xl">
            <HomeworkManager
              tuitions={tuitions}
              students={students}
            />
          </div>
        )}
      </main>

      {/* Modals */}
      <AddStudentModal
        isOpen={addStudentModalOpen}
        onClose={() => setAddStudentModalOpen(false)}
        tuitions={tuitions}
        initialTuitionId={activeTab === 'attendance' && selectedTuition ? selectedTuition.id : ''}
        onStudentAdded={(newStudent, assignedTuitionId) => {
          refreshRoster();
          if (assignedTuitionId) setSelectedTuitionId(assignedTuitionId);
        }}
      />

      <TuitionBatchesModal
        isOpen={batchModalOpen}
        onClose={() => setBatchModalOpen(false)}
        allStudents={students}
        batchToEdit={selectedBatchToEdit}
        onBatchSaved={refreshRoster}
      />

      <ExamAuthoringModal
        key={`exam-author-${authorExamModalOpen ? 'open' : 'closed'}-${initialBatchForExam || 'none'}`}
        isOpen={authorExamModalOpen}
        onClose={() => setAuthorExamModalOpen(false)}
        students={students}
        initialBatchId={initialBatchForExam || selectedTuition?.id || ''}
        initialCategory={authorCategory}
        onExamCreated={() => {
          loadExams();
          setActiveTab('exams');
        }}
      />



    </div>
  );
}
