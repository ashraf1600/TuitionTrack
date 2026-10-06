import React, { useState, useEffect } from 'react';
import Navbar from '../components/common/Navbar';
import StudentCycleProgress from '../components/student/StudentCycleProgress';
import ExamCard from '../components/student/ExamCard';
import ExamTakerModal from '../components/student/ExamTakerModal';
import ExamResultModal from '../components/student/ExamResultModal';
import { api } from '../api/client';
import { useAuth } from '../context/AuthContext';
import { Calendar, FileText, Sparkles, RefreshCw } from 'lucide-react';

export default function StudentPortal() {
  const { user } = useAuth();
  const [cycle, setCycle] = useState(null);
  const [exams, setExams] = useState([]);
  const [loadingCycle, setLoadingCycle] = useState(true);
  const [loadingExams, setLoadingExams] = useState(true);

  // Modals
  const [takerModalOpen, setTakerModalOpen] = useState(false);
  const [resultModalOpen, setResultModalOpen] = useState(false);
  const [activeExam, setActiveExam] = useState(null);

  const loadData = async () => {
    try {
      setLoadingCycle(true);
      const cyclesData = await api.getCycles();
      const list = Array.isArray(cyclesData) ? cyclesData : cyclesData.results || [];
      const active = list.find((c) => c.status === 'ACTIVE') || list[0] || null;
      setCycle(active);
    } catch (err) {
      console.error('Failed to load cycles:', err);
    } finally {
      setLoadingCycle(false);
    }

    try {
      setLoadingExams(true);
      const examsData = await api.getExams();
      const examList = Array.isArray(examsData) ? examsData : examsData.results || [];
      setExams(examList);
    } catch (err) {
      console.error('Failed to load exams:', err);
    } finally {
      setLoadingExams(false);
    }
  };

  useEffect(() => {
    loadData();
  }, []);

  const handleTakeExam = async (examId) => {
    try {
      const fullExam = await api.getExamDetail(examId);
      setActiveExam(fullExam);
      setTakerModalOpen(true);
    } catch (err) {
      alert(`Failed to start exam: ${err.message}`);
    }
  };

  const handleViewResults = async (examId) => {
    try {
      const fullExam = await api.getExamDetail(examId);
      setActiveExam(fullExam);
      setResultModalOpen(true);
    } catch (err) {
      alert(`Failed to load results: ${err.message}`);
    }
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      <Navbar />

      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
        {/* Welcome Header */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-6 rounded-2xl bg-gradient-to-r from-slate-900 via-indigo-950/30 to-slate-900 border border-slate-800">
          <div>
            <div className="flex items-center gap-2 text-indigo-400 text-xs font-semibold mb-1">
              <Sparkles className="w-4 h-4" />
              <span>Student Learning Portal</span>
            </div>
            <h1 className="text-2xl font-extrabold text-slate-100">
              Welcome back, {user?.name || user?.username}!
            </h1>
            <p className="text-xs text-slate-400 mt-1">
              Track your attendance progress and participate in scheduled exams
            </p>
          </div>

          <button
            onClick={loadData}
            className="self-start sm:self-auto p-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-400 hover:text-slate-200 border border-slate-700 transition"
            title="Refresh Portal"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
        </div>

        {/* Section 1: Billing Cycle Attendance Progress */}
        <section>
          <StudentCycleProgress cycle={cycle} />
        </section>

        {/* Section 2: Assigned Exams */}
        <section className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-lg font-bold text-slate-100 flex items-center gap-2">
                <FileText className="w-5 h-5 text-indigo-400" />
                Assigned Examinations & Assessments
              </h3>
              <p className="text-xs text-slate-400">
                Participate during scheduled exam windows or review graded answer sheets
              </p>
            </div>
          </div>

          {loadingExams ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {[1, 2, 3].map((i) => (
                <div key={i} className="h-44 rounded-2xl bg-slate-800/40 animate-pulse" />
              ))}
            </div>
          ) : exams.length === 0 ? (
            <div className="glass-panel p-10 rounded-2xl text-center text-slate-400">
              <FileText className="w-12 h-12 mx-auto text-slate-600 mb-2" />
              <p className="text-base font-semibold text-slate-300">No exams assigned right now</p>
              <p className="text-xs text-slate-500 mt-1">
                You will receive an email alert whenever your tutor schedules an exam.
              </p>
            </div>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
              {exams.map((exam) => (
                <ExamCard
                  key={exam.id}
                  exam={exam}
                  onTakeExam={handleTakeExam}
                  onViewResults={handleViewResults}
                />
              ))}
            </div>
          )}
        </section>
      </main>

      {/* Exam Taker Modal */}
      {activeExam && (
        <ExamTakerModal
          isOpen={takerModalOpen}
          onClose={() => setTakerModalOpen(false)}
          exam={activeExam}
          onExamSubmitted={() => {
            loadData();
          }}
        />
      )}

      {/* Exam Results Modal */}
      {activeExam && (
        <ExamResultModal
          isOpen={resultModalOpen}
          onClose={() => setResultModalOpen(false)}
          exam={activeExam}
        />
      )}
    </div>
  );
}
