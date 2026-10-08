import React, { useState, useEffect, useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';
import { notify } from '../utils/toast';
import Navbar from '../components/common/Navbar';
import Modal from '../components/common/Modal';
import ConnectedTutorsHub from '../components/student/ConnectedTutorsHub';
import TutorWorkspaceView from '../components/student/TutorWorkspaceView';
import TutorCodeConnect from '../components/student/TutorCodeConnect';
import ExamTakerModal from '../components/student/ExamTakerModal';
import ExamResultModal from '../components/student/ExamResultModal';
import LeaderboardModal from '../components/common/LeaderboardModal';
import { api } from '../api/client';
import { useAuth } from '../context/AuthContext';

const asList = (data) => (Array.isArray(data) ? data : data?.results || []);

/**
 * StudentPortal — Elite Two-Screen Master-Detail Architecture
 *
 * Screen 1 (Master View): Connected Tutors Hub
 *   - Ultra-clean navigation hub displaying ONLY connected tutor cards.
 *   - No global progress or tasks cluttering the screen.
 *
 * Screen 2 (Detail View): Dedicated Tutor Workspace
 *   - Isolated virtual classroom ("Ashraf Sir's Class").
 *   - 3 ordered sections: 1. Class Routine, 2. Class Progress Board, 3. Assessments & Tasks.
 */
export default function StudentPortal() {
  const { user } = useAuth();
  const [searchParams, setSearchParams] = useSearchParams();

  // Selected tutor ID synced with URL (?tutor=...)
  const selectedTutorId = searchParams.get('tutor');

  const [tutors, setTutors] = useState([]);
  const [tuitions, setTuitions] = useState([]);
  const [connections, setConnections] = useState([]);
  const [exams, setExams] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  // Modal states
  const [codeConnectModalOpen, setCodeConnectModalOpen] = useState(false);
  const [takerModalOpen, setTakerModalOpen] = useState(false);
  const [resultModalOpen, setResultModalOpen] = useState(false);
  const [leaderboardModalOpen, setLeaderboardModalOpen] = useState(false);
  const [activeExam, setActiveExam] = useState(null);
  const [selectedLeaderboardExam, setSelectedLeaderboardExam] = useState(null);

  const loadData = useCallback(async () => {
    setError('');
    try {
      setLoading(true);
      const [tuitionData, connectionData, tutorsData, examData] = await Promise.all([
        api.getTuitions().catch(() => []),
        api.getConnections().catch(() => []),
        api.getMyTutors().catch(() => []),
        api.getExams().catch(() => []),
      ]);
      setTuitions(asList(tuitionData));
      setConnections(asList(connectionData));
      setTutors(asList(tutorsData));
      setExams(asList(examData));
    } catch (err) {
      setError(err.message || 'Could not load your portal data.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  // Handle navigation into a tutor's workspace
  const handleSelectTutor = (tutorId) => {
    setSearchParams({ tutor: tutorId });
  };

  // Handle back to hub navigation
  const handleBackToHub = () => {
    setSearchParams({});
    loadData();
  };

  // Exam actions (triggered from inside workspace)
  const handleTakeExam = async (examId) => {
    try {
      const target = exams.find((e) => e.id === examId);
      if (target?.duration_minutes && target.category !== 'ASSIGNMENT') {
        const ok = window.confirm(
          `This exam is timed: you get ${target.duration_minutes} minutes from the moment you start, and the clock keeps running if you close the window. Start now?`
        );
        if (!ok) return;
      }
      const started = await api.startExam(examId);
      setActiveExam(started.exam);
      setTakerModalOpen(true);
    } catch (err) {
      notify(`Failed to start exam: ${err.message}`);
    }
  };

  const handleViewResults = async (examId) => {
    try {
      setActiveExam(await api.getExamDetail(examId));
      setResultModalOpen(true);
    } catch (err) {
      notify(`Failed to load results: ${err.message}`);
    }
  };

  const handleExamSubmitted = (response, exam) => {
    loadData();
    const status = response?.result_status;
    if (response?.results_released && exam?.id) {
      notify.success('Submitted. Here is your result.');
      handleViewResults(exam.id);
    } else if (status?.mode === 'SCHEDULED' && status.publish_at) {
      notify.success(
        `Submitted. Results will be published on ${new Date(status.publish_at).toLocaleString(undefined, {
          day: 'numeric',
          month: 'short',
          hour: 'numeric',
          minute: '2-digit',
        })}.`
      );
    } else {
      notify.success('Submitted. Your tutor will publish the results.');
    }
  };

  const handleViewLeaderboard = (exam) => {
    setSelectedLeaderboardExam(exam);
    setLeaderboardModalOpen(true);
  };

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900 flex flex-col font-sans selection:bg-indigo-500 selection:text-white">
      <Navbar />

      <main className="flex-1 max-w-6xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6 sm:py-8">
        {selectedTutorId ? (
          /* ── Screen 2: Dedicated Tutor Workspace (Detail View) ── */
          <TutorWorkspaceView
            tutorId={selectedTutorId}
            onBack={handleBackToHub}
            allTuitions={tuitions}
            allExams={exams}
            onTakeExam={handleTakeExam}
            onViewResults={handleViewResults}
            onViewLeaderboard={handleViewLeaderboard}
          />
        ) : (
          /* ── Screen 1: Connected Tutors Hub (Master View) ── */
          <ConnectedTutorsHub
            studentName={user?.name || user?.username}
            tutors={tutors}
            connections={connections}
            loading={loading}
            error={error}
            onSelectTutor={handleSelectTutor}
            onOpenConnectModal={() => setCodeConnectModalOpen(true)}
            onRefresh={loadData}
            onChanged={loadData}
          />
        )}
      </main>

      {/* ── Connect with Tutor Code Modal ── */}
      {codeConnectModalOpen && (
        <Modal
          isOpen={codeConnectModalOpen}
          onClose={() => setCodeConnectModalOpen(false)}
          title="Connect to Tutor"
          maxWidth="max-w-xl"
        >
          <TutorCodeConnect
            connections={connections}
            onChanged={() => {
              loadData();
              setCodeConnectModalOpen(false);
            }}
          />
        </Modal>
      )}

      {/* ── Exam Taking & Result Modals ── */}
      {activeExam && (
        <ExamTakerModal
          isOpen={takerModalOpen}
          onClose={() => setTakerModalOpen(false)}
          exam={activeExam}
          onExamSubmitted={handleExamSubmitted}
        />
      )}

      {activeExam && (
        <ExamResultModal
          isOpen={resultModalOpen}
          onClose={() => setResultModalOpen(false)}
          exam={activeExam}
        />
      )}

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
