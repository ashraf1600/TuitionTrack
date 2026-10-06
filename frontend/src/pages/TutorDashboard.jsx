import React, { useState, useEffect } from 'react';
import Navbar from '../components/common/Navbar';
import WalletWidget from '../components/tutor/WalletWidget';
import StudentRoster from '../components/tutor/StudentRoster';
import CycleGrid from '../components/tutor/CycleGrid';
import AddStudentModal from '../components/tutor/AddStudentModal';
import ExamAuthoringModal from '../components/tutor/ExamAuthoringModal';
import SubmissionsGradingModal from '../components/tutor/SubmissionsGradingModal';
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
} from 'lucide-react';

export default function TutorDashboard() {
  const [activeTab, setActiveTab] = useState('attendance'); // 'attendance' | 'exams'

  // Data states
  const [analytics, setAnalytics] = useState(null);
  const [students, setStudents] = useState([]);
  const [selectedStudentId, setSelectedStudentId] = useState(null);
  const [currentCycle, setCurrentCycle] = useState(null);
  const [exams, setExams] = useState([]);

  // Loading states
  const [loadingAnalytics, setLoadingAnalytics] = useState(true);
  const [loadingStudents, setLoadingStudents] = useState(true);
  const [loadingCycle, setLoadingCycle] = useState(false);
  const [loadingExams, setLoadingExams] = useState(false);

  // Modals
  const [addStudentModalOpen, setAddStudentModalOpen] = useState(false);
  const [authorExamModalOpen, setAuthorExamModalOpen] = useState(false);
  const [gradingModalOpen, setGradingModalOpen] = useState(false);
  const [selectedExamForGrading, setSelectedExamForGrading] = useState(null);
  const [selectedSubmissionForGrading, setSelectedSubmissionForGrading] = useState(null);

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

      // Default select first student if none selected
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

  // 4. Load Exams
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

  const handleToggleClass = async (cycleId, classNo, completed) => {
    // Optimistic update
    if (currentCycle) {
      const updatedClasses = currentCycle.classes_data.map((c) =>
        c.classNo === classNo
          ? { ...c, completed, date: completed ? new Date().toISOString() : null }
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
      const res = await api.toggleClass(cycleId, classNo, completed);
      setCurrentCycle(res.cycle);
      loadAnalytics(); // Refresh live wallet
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

  const selectedStudent = students.find((s) => s.student_id === selectedStudentId);
  const studentName = selectedStudent ? selectedStudent.full_name : 'Student';

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      <Navbar />

      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
        {/* Section 1: Gamified Wallet Widget */}
        <WalletWidget analytics={analytics} loading={loadingAnalytics} />

        {/* Section 2: Tab Navigation */}
        <div className="flex items-center justify-between border-b border-slate-800 pb-2">
          <div className="flex items-center gap-3">
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

          {activeTab === 'exams' && (
            <button
              onClick={() => setAuthorExamModalOpen(true)}
              className="px-3.5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs flex items-center gap-1.5 shadow-md shadow-indigo-600/20 transition"
            >
              <Plus className="w-4 h-4" />
              <span>Schedule New Exam</span>
            </button>
          )}
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
                onOpenAddModal={() => setAddStudentModalOpen(true)}
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

        {/* Tab Content B: Exam Management & Submissions Review */}
        {activeTab === 'exams' && (
          <div className="glass-panel p-6 rounded-2xl">
            <div className="flex items-center justify-between mb-6">
              <div>
                <h3 className="text-xl font-bold text-slate-100 flex items-center gap-2">
                  <FileText className="w-5 h-5 text-indigo-400" />
                  Exam Management & Submissions
                </h3>
                <p className="text-xs text-slate-400 mt-0.5">
                  Author rich-text KaTeX exams, monitor live status, and grade CQ/MCQ submissions
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
                  Use our TipTap WYSIWYG editor with LaTeX equation support to schedule exams
                </p>
                <button
                  onClick={() => setAuthorExamModalOpen(true)}
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
                      <th className="py-3 px-4">Exam Title</th>
                      <th className="py-3 px-4">Assigned Student</th>
                      <th className="py-3 px-4">Schedule</th>
                      <th className="py-3 px-4">Marks</th>
                      <th className="py-3 px-4">Status</th>
                      <th className="py-3 px-4 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/60">
                    {exams.map((exam) => (
                      <tr key={exam.id} className="hover:bg-slate-800/30 transition">
                        <td className="py-3 px-4 font-semibold text-slate-200">
                          {exam.title}
                        </td>
                        <td className="py-3 px-4 text-xs text-slate-300">
                          {exam.student_name}
                        </td>
                        <td className="py-3 px-4 text-xs text-slate-400">
                          {new Date(exam.start_time).toLocaleDateString(undefined, {
                            month: 'short',
                            day: 'numeric',
                            hour: '2-digit',
                            minute: '2-digit',
                          })}
                        </td>
                        <td className="py-3 px-4 text-xs font-bold text-emerald-400">
                          {exam.total_marks}
                        </td>
                        <td className="py-3 px-4">
                          <StatusBadge status={exam.dynamic_status} />
                        </td>
                        <td className="py-3 px-4 text-right">
                          {exam.has_submission ? (
                            <button
                              onClick={() => openGradingModal(exam)}
                              className="px-3 py-1.5 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white font-semibold text-xs flex items-center gap-1.5 ml-auto shadow-md shadow-emerald-600/20"
                            >
                              <Award className="w-3.5 h-3.5" />
                              <span>Review & Grade</span>
                            </button>
                          ) : (
                            <span className="text-xs text-slate-500 italic">
                              Awaiting submission
                            </span>
                          )}
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

      <ExamAuthoringModal
        isOpen={authorExamModalOpen}
        onClose={() => setAuthorExamModalOpen(false)}
        students={students}
        initialStudentId={selectedStudentId}
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
    </div>
  );
}
