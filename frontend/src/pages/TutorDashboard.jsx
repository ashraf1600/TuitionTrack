import React, { useState, useEffect } from 'react';
import Navbar from '../components/common/Navbar';
import WalletWidget from '../components/tutor/WalletWidget';
import StudentRoster from '../components/tutor/StudentRoster';
import CycleGrid from '../components/tutor/CycleGrid';
import AddStudentModal from '../components/tutor/AddStudentModal';
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
} from 'lucide-react';

export default function TutorDashboard() {
  const [activeTab, setActiveTab] = useState('attendance'); // 'attendance' | 'batches' | 'exams'

  // Data states
  const [analytics, setAnalytics] = useState(null);
  const [students, setStudents] = useState([]);
  const [selectedStudentId, setSelectedStudentId] = useState(null);
  const [currentCycle, setCurrentCycle] = useState(null);
  const [batches, setBatches] = useState([]);
  const [exams, setExams] = useState([]);

  // Loading states
  const [loadingAnalytics, setLoadingAnalytics] = useState(true);
  const [loadingStudents, setLoadingStudents] = useState(true);
  const [loadingCycle, setLoadingCycle] = useState(false);
  const [loadingBatches, setLoadingBatches] = useState(false);
  const [loadingExams, setLoadingExams] = useState(false);

  // Modals
  const [addStudentModalOpen, setAddStudentModalOpen] = useState(false);
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
        setSelectedStudentId(list[0].student_id);
      }
    } catch (err) {
      console.error('Failed to load students:', err);
    } finally {
      setLoadingStudents(false);
    }
  };

  // 3. Load Active Cycle for selected student
  const loadStudentCycle = async (studentId) => {
    if (!studentId) return;
    try {
      setLoadingCycle(true);
      const data = await api.getCycles(studentId);
      const list = Array.isArray(data) ? data : data.results || [];
      const active = list.find((c) => c.status === 'ACTIVE') || list[0] || null;
      setCurrentCycle(active);
    } catch (err) {
      console.error('Failed to load cycle:', err);
    } finally {
      setLoadingCycle(false);
    }
  };

  // 4. Load Tuition Batches
  const loadBatches = async () => {
    try {
      setLoadingBatches(true);
      const data = await api.getBatches();
      const list = Array.isArray(data) ? data : data.results || [];
      setBatches(list);
    } catch (err) {
      console.error('Failed to load tuition batches:', err);
    } finally {
      setLoadingBatches(false);
    }
  };

  // 5. Load Exams
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
    loadBatches();
    loadExams();
  }, []);

  useEffect(() => {
    if (selectedStudentId) {
      loadStudentCycle(selectedStudentId);
    }
  }, [selectedStudentId]);

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
    if (currentCycle) {
      const targetIso = completed ? (date ? new Date(date).toISOString() : new Date().toISOString()) : null;
      const updatedClasses = currentCycle.classes_data.map((c) =>
        c.classNo === classNo
          ? {
              ...c,
              completed,
              date: targetIso,
              topic: completed ? topic : '',
            }
          : c
      );
      const completedCount = updatedClasses.filter((c) => c.completed).length;
      const rate = currentCycle.fee_snapshot / currentCycle.total_classes;
      const earned = Math.round(rate * completedCount * 100) / 100;
      const pending = Math.round((currentCycle.fee_snapshot - earned) * 100) / 100;

      setCurrentCycle({
        ...currentCycle,
        classes_data: updatedClasses,
        completed_classes: completedCount,
        earned_amount: earned,
        pending_amount: pending,
        progress_percentage: Math.round((completedCount / currentCycle.total_classes) * 100),
      });
    }

    try {
      const res = await api.toggleClass(cycleId, classNo, completed, date, topic);
      setCurrentCycle(res.cycle);
      loadAnalytics();
    } catch (err) {
      alert(`Toggle failed: ${err.message}`);
      loadStudentCycle(selectedStudentId);
    }
  };


  const handleResetCycle = async (cycleId) => {
    try {
      const res = await api.resetCycle(cycleId);
      setCurrentCycle(res.cycle);
      loadAnalytics();
      alert(res.message);
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
      await api.deleteBatch(batchId);
      loadBatches();
    } catch (err) {
      alert(`Delete failed: ${err.message}`);
    }
  };

  const handleScheduleForBatch = (batchId) => {
    setInitialBatchForExam(batchId);
    setAuthorExamModalOpen(true);
  };

  const selectedStudent = students.find((s) => s.student_id === selectedStudentId);
  const studentName = selectedStudent ? selectedStudent.full_name : 'Student';

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      <Navbar />

      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
        {/* Section 1: Gamified Wallet Widget */}
        <WalletWidget analytics={analytics} loading={loadingAnalytics} />

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
              {batches.length > 0 && (
                <span className="px-1.5 py-0.2 rounded-full bg-slate-800 text-[10px] text-slate-300">
                  {batches.length}
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
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
            <div className="lg:col-span-4">
              <StudentRoster
                students={students}
                selectedStudentId={selectedStudentId}
                onSelectStudent={setSelectedStudentId}
                onToggleActive={handleToggleActive}
                onOpenAddModal={() => setAddStudentModalOpen(false) || setAddStudentModalOpen(true)}
                loading={loadingStudents}
              />
            </div>

            <div className="lg:col-span-8">
              <CycleGrid
                cycle={currentCycle}
                studentName={studentName}
                onToggleClass={handleToggleClass}
                onResetCycle={handleResetCycle}
                loading={loadingCycle}
              />
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
                      <div className="mt-3 flex items-center gap-3 text-xs">
                        <div className="px-2.5 py-1 rounded-lg bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 font-bold flex items-center gap-1">
                          <DollarSign className="w-3 h-3" />
                          <span>{batch.monthly_fee}/mo</span>
                        </div>
                        <div className="px-2.5 py-1 rounded-lg bg-indigo-500/10 border border-indigo-500/20 text-indigo-300 font-semibold flex items-center gap-1">
                          <Users className="w-3 h-3" />
                          <span>{batch.student_count || 0} Students</span>
                        </div>
                      </div>

                      {/* Weekly Routine schedule */}
                      <div className="mt-4 pt-3 border-t border-slate-800">
                        <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block mb-1.5 flex items-center gap-1">
                          <Clock className="w-3 h-3 text-indigo-400" />
                          Weekly Routine Days & Time:
                        </span>
                        {batch.weekly_routine && batch.weekly_routine.length > 0 ? (
                          <div className="flex flex-wrap gap-1.5">
                            {batch.weekly_routine.map((slot, i) => (
                              <span
                                key={i}
                                className="px-2 py-0.5 rounded-md bg-slate-800 border border-slate-700 text-slate-300 text-[11px] font-mono"
                              >
                                {slot.day?.slice(0, 3)} @ {slot.time}
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
        onStudentAdded={() => {
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
          loadBatches();
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
