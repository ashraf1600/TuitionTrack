import React, { useState, useEffect } from 'react';
import Navbar from '../components/common/Navbar';
import StudentCycleProgress from '../components/student/StudentCycleProgress';
import ExamCard from '../components/student/ExamCard';
import ExamTakerModal from '../components/student/ExamTakerModal';
import ExamResultModal from '../components/student/ExamResultModal';
import LeaderboardModal from '../components/common/LeaderboardModal';
import { api } from '../api/client';
import { useAuth } from '../context/AuthContext';
import { Calendar, FileText, Sparkles, RefreshCw, Layers, Clock, DollarSign, Users } from 'lucide-react';

export default function StudentPortal() {
  const { user } = useAuth();
  const [cycles, setCycles] = useState([]);
  const [cycle, setCycle] = useState(null);
  const [batches, setBatches] = useState([]);
  const [exams, setExams] = useState([]);
  const [loadingCycle, setLoadingCycle] = useState(true);
  const [loadingBatches, setLoadingBatches] = useState(true);
  const [loadingExams, setLoadingExams] = useState(true);

  // Modals
  const [takerModalOpen, setTakerModalOpen] = useState(false);
  const [resultModalOpen, setResultModalOpen] = useState(false);
  const [leaderboardModalOpen, setLeaderboardModalOpen] = useState(false);
  const [activeExam, setActiveExam] = useState(null);
  const [selectedLeaderboardExam, setSelectedLeaderboardExam] = useState(null);

  const isNotFoundError = (err) => /404|not found/i.test(err?.message || '');

  const loadData = async () => {
    // 1. Cycles
    try {
      setLoadingCycle(true);
      let list = [];
      try {
        const cyclesData = await api.getAttendanceCycles();
        list = Array.isArray(cyclesData) ? cyclesData : cyclesData.results || [];
      } catch (fallbackErr) {
        // Only fall back to the legacy endpoint on 404 (endpoint missing).
        // 401/403 means auth/permission — must surface, not silently retry.
        if (!isNotFoundError(fallbackErr)) throw fallbackErr;
        const cyclesData = await api.getCycles();
        list = Array.isArray(cyclesData) ? cyclesData : cyclesData.results || [];
      }
      setCycles(list);
      const active = list.find((c) => c.status === 'ACTIVE') || list[0] || null;
      setCycle(active);
    } catch (err) {
      console.error('Failed to load cycles:', err);
    } finally {
      setLoadingCycle(false);
    }

    // 2. Enrolled Tuitions & Batches
    try {
      setLoadingBatches(true);
      let batchList = [];
      try {
        const tuitionsData = await api.getTuitions();
        batchList = Array.isArray(tuitionsData) ? tuitionsData : tuitionsData.results || [];
      } catch (fallbackErr) {
        if (!isNotFoundError(fallbackErr)) throw fallbackErr;
        const batchesData = await api.getBatches();
        batchList = Array.isArray(batchesData) ? batchesData : batchesData.results || [];
      }
      setBatches(batchList);
    } catch (err) {
      console.error('Failed to load batches:', err);
    } finally {
      setLoadingBatches(false);
    }

    // 3. Assigned Exams
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

  const handleViewLeaderboard = (exam) => {
    setSelectedLeaderboardExam(exam);
    setLeaderboardModalOpen(true);
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
              <span>Student Learning & Assessment Portal</span>
            </div>
            <h1 className="text-2xl font-extrabold text-slate-100">
              Welcome back, {user?.name || user?.username}!
            </h1>
            <p className="text-xs text-slate-400 mt-1">
              Track your tuition schedule, weekly routine, class attendance, and take online examinations
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

        {/* Section 1: Enrolled Tuition Batches & Weekly Routine */}
        <section className="space-y-4">
          <div>
            <h3 className="text-lg font-bold text-slate-100 flex items-center gap-2">
              <Layers className="w-5 h-5 text-indigo-400" />
              My Enrolled Tuitions & Weekly Routine
            </h3>
            <p className="text-xs text-slate-400">
              Classes and scheduled weekly routine times set by your tutor
            </p>
          </div>

          {loadingBatches ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {[1, 2].map((i) => (
                <div key={i} className="h-36 rounded-2xl bg-slate-800/40 animate-pulse" />
              ))}
            </div>
          ) : batches.length === 0 ? (
            <div className="glass-panel p-6 rounded-2xl text-center text-slate-400">
              <Layers className="w-8 h-8 mx-auto text-slate-600 mb-2" />
              <p className="text-sm font-semibold text-slate-300">Individual 1-on-1 Tuition</p>
              <p className="text-xs text-slate-500 mt-1">
                You are currently in individual private coaching with your tutor.
              </p>
            </div>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {batches.map((batch) => {
                const title = batch.title || batch.name;
                const routineSlots = batch.routine || batch.weekly_routine || [];
                return (
                  <div
                    key={batch.id}
                    className="p-5 rounded-2xl bg-slate-900/80 border border-slate-800 hover:border-slate-700 transition space-y-3"
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <h4 className="font-bold text-slate-100 text-base">{title}</h4>
                        {batch.tutor_name && (
                          <span className="text-xs text-indigo-400 font-semibold block">
                            Tutor: {batch.tutor_name}
                          </span>
                        )}
                        {batch.subject && (
                          <span className="text-xs text-slate-400 block">
                            {batch.subject}
                          </span>
                        )}
                      </div>
                      <span className="px-2 py-0.5 rounded-full bg-indigo-500/10 text-indigo-300 border border-indigo-500/20 text-[10px] font-mono">
                        Active
                      </span>
                    </div>

                    {batch.description && (
                      <p className="text-xs text-slate-400 line-clamp-2">{batch.description}</p>
                    )}

                    <div className="pt-2 border-t border-slate-800">
                      <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block mb-1.5 flex items-center gap-1">
                        <Clock className="w-3 h-3 text-indigo-400" />
                        Weekly Routine:
                      </span>
                      {routineSlots.length > 0 ? (
                        <div className="flex flex-wrap gap-1.5">
                          {routineSlots.map((slot, i) => (
                            <span
                              key={i}
                              className="px-2.5 py-1 rounded-lg bg-slate-800 border border-slate-700 text-slate-200 text-xs font-mono font-medium"
                            >
                              {slot.day} @ {slot.start_time || slot.time} {slot.end_time ? `- ${slot.end_time}` : ''}
                            </span>
                          ))}
                        </div>
                      ) : (
                        <span className="text-xs text-slate-500 italic">Schedule not specified</span>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </section>

        {/* Section 2: Billing Cycle Attendance Progress */}
        <section className="space-y-4">
          {cycles.length > 1 ? (
            cycles.map((c) => (
              <StudentCycleProgress key={c.id} cycle={c} />
            ))
          ) : (
            <StudentCycleProgress cycle={cycle || cycles[0]} />
          )}
        </section>

        {/* Section 3: Assigned Exams */}
        <section className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-lg font-bold text-slate-100 flex items-center gap-2">
                <FileText className="w-5 h-5 text-indigo-400" />
                Assigned Examinations & Assessments
              </h3>
              <p className="text-xs text-slate-400">
                Appear for scheduled exams, review auto-graded MCQs, and check your rank on the leaderboard
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
                You will receive an alert whenever your tutor schedules an exam for your batch or profile.
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
                  onViewLeaderboard={handleViewLeaderboard}
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

      {/* Leaderboard Modal */}
      {selectedLeaderboardExam && (
        <LeaderboardModal
          isOpen={leaderboardModalOpen}
          onClose={() => setLeaderboardModalOpen(false)}
          examId={selectedLeaderboardExam.id}
          examTitle={selectedLeaderboardExam.title}
        />
      )}
    </div>
  );
}
