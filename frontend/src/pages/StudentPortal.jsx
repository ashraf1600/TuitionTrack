import React, { useState, useEffect, useCallback } from 'react';
import { notify } from '../utils/toast';
import Navbar from '../components/common/Navbar';
import Modal from '../components/common/Modal';
import StudentCycleProgress from '../components/student/StudentCycleProgress';
import TutorCodeConnect from '../components/student/TutorCodeConnect';
import TutorDetailView from '../components/student/TutorDetailView';
import ExamCard from '../components/student/ExamCard';
import ExamTakerModal from '../components/student/ExamTakerModal';
import ExamResultModal from '../components/student/ExamResultModal';
import LeaderboardModal from '../components/common/LeaderboardModal';
import { api, getMediaUrl } from '../api/client';
import { useAuth } from '../context/AuthContext';
import {
  FileText, RefreshCw, Layers, Clock, Users, GraduationCap, AlertCircle,
  Plus, ChevronRight, UserCheck, BookOpen, Sparkles
} from 'lucide-react';

const asList = (data) => (Array.isArray(data) ? data : data?.results || []);

export default function StudentPortal() {
  const { user } = useAuth();
  const [tutors, setTutors] = useState([]);
  const [tuitions, setTuitions] = useState([]);
  const [connections, setConnections] = useState([]);
  const [exams, setExams] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadingExams, setLoadingExams] = useState(true);
  const [error, setError] = useState('');

  // Selected tutor for the detailed view
  const [selectedTutorId, setSelectedTutorId] = useState(null);

  // Modal to connect with another tutor code
  const [codeConnectModalOpen, setCodeConnectModalOpen] = useState(false);

  // Exam Modals
  const [takerModalOpen, setTakerModalOpen] = useState(false);
  const [resultModalOpen, setResultModalOpen] = useState(false);
  const [leaderboardModalOpen, setLeaderboardModalOpen] = useState(false);
  const [activeExam, setActiveExam] = useState(null);
  const [selectedLeaderboardExam, setSelectedLeaderboardExam] = useState(null);

  const loadData = useCallback(async () => {
    setError('');
    try {
      setLoading(true);
      const [tuitionData, connectionData, tutorsData] = await Promise.all([
        api.getTuitions(),
        api.getConnections(),
        api.getMyTutors(),
      ]);
      setTuitions(asList(tuitionData));
      setConnections(asList(connectionData));
      setTutors(asList(tutorsData));
    } catch (err) {
      setError(err.message || 'Could not load your portal data.');
    } finally {
      setLoading(false);
    }

    try {
      setLoadingExams(true);
      setExams(asList(await api.getExams()));
    } catch (err) {
      console.error('Failed to load exams:', err);
    } finally {
      setLoadingExams(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

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

  // If a tutor is clicked, show their full Detailed Dashboard
  if (selectedTutorId) {
    return (
      <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
        <Navbar />
        <main className="flex-1 max-w-6xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
          <TutorDetailView
            tutorId={selectedTutorId}
            onBack={() => {
              setSelectedTutorId(null);
              loadData();
            }}
          />
        </main>
      </div>
    );
  }

  // To do = can be turned in now; Upcoming = not open yet; Done = turned in or over.
  const nowMs = Date.now();
  const todo = exams
    .filter((e) => !e.has_submission && e.can_submit)
    .sort((a, b) => new Date(a.end_time) - new Date(b.end_time));
  const upcoming = exams
    .filter((e) => !e.has_submission && !e.can_submit && new Date(e.start_time).getTime() > nowMs)
    .sort((a, b) => new Date(a.start_time) - new Date(b.start_time));
  const past = exams.filter((e) => !todo.includes(e) && !upcoming.includes(e));
  const openExams = todo.length;
  const examGroups = [
    { key: 'todo', title: 'To do', hint: 'Open now — turn these in before they close.', items: todo },
    { key: 'upcoming', title: 'Upcoming', hint: 'Not open yet.', items: upcoming },
    { key: 'past', title: 'Done & past', hint: 'Turned in, or the deadline has passed.', items: past },
  ].filter((g) => g.items.length > 0);

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col">
      <Navbar />

      <main className="flex-1 max-w-6xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
        {/* Welcome Header */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-6 rounded-2xl bg-gradient-to-r from-slate-900 via-indigo-950/30 to-slate-900 border border-slate-800 shadow-xl">
          <div>
            <div className="inline-flex items-center gap-2 px-2.5 py-0.5 rounded-full text-[11px] font-semibold bg-emerald-500/10 text-emerald-300 border border-emerald-500/25 mb-2">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
              <span>Student Learning Portal</span>
            </div>
            <h1 className="text-2xl sm:text-3xl font-extrabold text-white tracking-tight">
              Welcome back, {user?.name || user?.username}
            </h1>
            <p className="text-xs sm:text-sm text-slate-400 mt-1">
              Your connected tutors, weekly routines, homework, and exams in one place.
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Pill icon={UserCheck} label={`${tutors.length} tutor${tutors.length === 1 ? '' : 's'}`} />
            {openExams > 0 && <Pill icon={FileText} label={`${openExams} to do now`} tone="emerald" />}
            <button
              type="button"
              onClick={() => setCodeConnectModalOpen(true)}
              className="px-4 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-xs flex items-center gap-1.5 shadow-md shadow-indigo-600/25 transition active:scale-[0.98]"
            >
              <Plus className="w-4 h-4" />
              <span>Connect Tutor</span>
            </button>
            <button
              type="button"
              onClick={loadData}
              className="p-2.5 rounded-xl bg-slate-800/80 hover:bg-slate-700 text-slate-400 hover:text-slate-200 border border-slate-700 transition"
              title="Refresh portal"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-indigo-400' : ''}`} />
            </button>
          </div>
        </div>

        {error && (
          <div className="px-4 py-3 rounded-xl bg-rose-500/10 border border-rose-500/25 text-rose-300 text-sm flex items-center gap-2">
            <AlertCircle className="w-4 h-4 flex-shrink-0" />
            {error}
          </div>
        )}

        {/* Phase 1 & 2: Connected Tutors OR Unassigned State */}
        {loading ? (
          <div className="space-y-4">
            <div className="h-6 w-48 bg-slate-800/60 rounded-lg animate-pulse" />
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {[1, 2].map((i) => (
                <div key={i} className="h-48 rounded-2xl bg-slate-800/40 animate-pulse" />
              ))}
            </div>
          </div>
        ) : tutors.length === 0 ? (
          /* Unassigned State: Display Tutor Code Connect Hero Directly */
          <section className="space-y-4">
            <TutorCodeConnect connections={connections} onChanged={loadData} />
          </section>
        ) : (
          /* Connected State: Show Connected Tutors with 'Ashraf Sir' formatting */
          <section className="space-y-4">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <SectionTitle
                icon={UserCheck}
                title="Connected Tutors"
                subtitle="Click on any tutor to access your weekly routine, classes, and homework with live timers."
              />
              <button
                type="button"
                onClick={() => setCodeConnectModalOpen(true)}
                className="text-xs font-bold text-indigo-400 hover:text-indigo-300 transition flex items-center gap-1 self-start sm:self-auto"
              >
                <Plus className="w-3.5 h-3.5" />
                Connect another tutor
              </button>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
              {tutors.map((tutor) => (
                <div
                  key={tutor.id}
                  onClick={() => setSelectedTutorId(tutor.id)}
                  className="group relative overflow-hidden rounded-2xl border border-slate-800 bg-slate-900/70 hover:bg-slate-900/90 hover:border-indigo-500/40 p-5 sm:p-6 cursor-pointer transition-all duration-200 shadow-lg hover:shadow-indigo-500/10 flex flex-col justify-between gap-4"
                >
                  <div className="flex items-start gap-4">
                    {/* Tutor Avatar */}
                    {tutor.profile_picture_url ? (
                      <img
                        src={getMediaUrl(tutor.profile_picture_url)}
                        alt={tutor.display_name}
                        className="w-14 h-14 rounded-2xl object-cover border border-indigo-500/30 flex-shrink-0"
                      />
                    ) : (
                      <div className="w-14 h-14 rounded-2xl bg-gradient-to-br from-indigo-500 to-violet-500 flex items-center justify-center text-white text-xl font-black flex-shrink-0 shadow-md shadow-indigo-500/20">
                        {(tutor.display_name || 'T')[0]}
                      </div>
                    )}

                    <div className="min-w-0 flex-1">
                      <div className="flex items-center justify-between gap-2">
                        <h3 className="text-lg font-bold text-slate-100 group-hover:text-indigo-300 transition truncate">
                          {tutor.display_name}
                        </h3>
                        <ChevronRight className="w-5 h-5 text-slate-500 group-hover:text-indigo-400 group-hover:translate-x-0.5 transition-all flex-shrink-0" />
                      </div>
                      <p className="text-xs text-slate-400 font-mono mt-0.5">@{tutor.username}</p>

                      {/* Subjects */}
                      {tutor.subjects?.length > 0 && (
                        <div className="flex flex-wrap gap-1.5 mt-2.5">
                          {tutor.subjects.map((sub) => (
                            <span
                              key={sub}
                              className="px-2 py-0.5 rounded-full bg-indigo-500/15 border border-indigo-500/25 text-indigo-300 text-[10px] font-semibold"
                            >
                              {sub}
                            </span>
                          ))}
                        </div>
                      )}
                    </div>
                  </div>

                  {/* Footer info: Tuitions & Routine info */}
                  <div className="pt-3 border-t border-slate-800/80 flex items-center justify-between text-xs text-slate-400">
                    <span className="flex items-center gap-1.5">
                      <Layers className="w-3.5 h-3.5 text-slate-500" />
                      {tutor.tuitions?.length || 0} tuition group{tutor.tuitions?.length === 1 ? '' : 's'}
                    </span>
                    <span className="text-indigo-400 font-bold group-hover:underline">
                      View Schedule & Homework →
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </section>
        )}

        {/* My tuition groups (Shared cycle progress) */}
        {tuitions.length > 0 && (
          <section className="space-y-4">
            <SectionTitle
              icon={Layers}
              title="Tuition Groups & Attendance"
              subtitle="Class progress is shared with everyone in your group — your tutor ticks each class once it is held."
            />
            <div className="space-y-5">
              {tuitions.map((tuition) => (
                <TuitionGroupCard key={tuition.id} tuition={tuition} />
              ))}
            </div>
          </section>
        )}

        {/* Exams & Assignments */}
        <section className="space-y-4">
          <SectionTitle
            icon={FileText}
            title="Exams & Assignments"
            subtitle="Set by your tutor for the whole group. Your answers and marks are your own."
          />

          {loadingExams ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {[1, 2, 3].map((i) => (
                <div key={i} className="h-44 rounded-2xl bg-slate-800/40 animate-pulse" />
              ))}
            </div>
          ) : exams.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-900/40 p-8 text-center">
              <FileText className="w-10 h-10 mx-auto text-slate-600 mb-3" />
              <p className="text-sm font-semibold text-slate-200">No exams right now</p>
              <p className="text-xs text-slate-400 mt-1">
                When your tutor schedules one for your group, it will appear here.
              </p>
            </div>
          ) : (
            <div className="space-y-6">
              {examGroups.map((group) => (
                <div key={group.key}>
                  <div className="flex items-baseline gap-2 mb-3">
                    <h3 className="text-sm font-bold text-slate-200">{group.title}</h3>
                    <span className="text-xs font-semibold text-slate-500">{group.items.length}</span>
                    <span className="text-xs text-slate-500 hidden sm:inline">· {group.hint}</span>
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
                    {group.items.map((exam) => (
                      <ExamCard
                        key={exam.id}
                        exam={exam}
                        onTakeExam={handleTakeExam}
                        onViewResults={handleViewResults}
                        onViewLeaderboard={handleViewLeaderboard}
                      />
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>
      </main>

      {/* Connect with Tutor Code Modal */}
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

      {/* Exam Modals */}
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

function SectionTitle({ icon: Icon, title, subtitle }) {
  return (
    <div>
      <h2 className="text-lg font-bold text-slate-100 flex items-center gap-2">
        <Icon className="w-5 h-5 text-indigo-400" />
        {title}
      </h2>
      <p className="text-xs text-slate-400 mt-0.5">{subtitle}</p>
    </div>
  );
}

function Pill({ icon: Icon, label, tone }) {
  const cls =
    tone === 'emerald'
      ? 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30'
      : 'bg-slate-800 text-slate-300 border-slate-700';
  return (
    <span className={`hidden sm:flex items-center gap-1.5 px-3 py-1.5 rounded-xl border text-xs font-semibold ${cls}`}>
      <Icon className="w-3.5 h-3.5" />
      {label}
    </span>
  );
}

function TuitionGroupCard({ tuition }) {
  const routine = tuition.routine || tuition.weekly_routine || [];
  const count = tuition.enrolled_count || 0;
  return (
    <article className="rounded-2xl border border-slate-800 bg-slate-900/70 overflow-hidden">
      <header className="p-5 sm:p-6 flex flex-col md:flex-row md:items-start justify-between gap-4 border-b border-slate-800">
        <div className="min-w-0">
          <h3 className="text-xl font-bold text-slate-100 truncate">{tuition.title}</h3>
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-slate-400 mt-1">
            <span>
              Tutor: <strong className="text-indigo-300">{tuition.tutor_name}</strong>
            </span>
            {tuition.subject && <span>· {tuition.subject}</span>}
            <span className="flex items-center gap-1">
              · <Users className="w-3.5 h-3.5" /> {count} student{count === 1 ? '' : 's'} in this group
            </span>
          </div>
          {tuition.description && <p className="text-xs text-slate-400 mt-2 max-w-2xl">{tuition.description}</p>}
        </div>

        <div className="md:text-right flex-shrink-0">
          <div className="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-1.5 flex md:justify-end items-center gap-1">
            <Clock className="w-3 h-3" /> Weekly routine
          </div>
          {routine.length ? (
            <div className="flex flex-wrap md:justify-end gap-1.5">
              {routine.map((slot, i) => (
                <span
                  key={i}
                  className="px-2.5 py-1 rounded-lg bg-slate-800 border border-slate-700 text-slate-200 text-xs font-medium"
                >
                  {slot.day?.slice(0, 3)} {slot.start_time || slot.time}
                  {slot.end_time ? `–${slot.end_time}` : ''}
                </span>
              ))}
            </div>
          ) : (
            <span className="text-xs text-slate-500">Not set yet</span>
          )}
        </div>
      </header>

      <div className="p-5 sm:p-6">
        <StudentCycleProgress cycle={tuition.active_cycle} embedded />
      </div>
    </article>
  );
}
