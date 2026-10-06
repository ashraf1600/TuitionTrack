import React, { useState, useEffect, useCallback } from 'react';
import { notify } from '../utils/toast';
import Navbar from '../components/common/Navbar';
import StudentCycleProgress from '../components/student/StudentCycleProgress';
import TutorConnectPanel from '../components/student/TutorConnectPanel';
import ExamCard from '../components/student/ExamCard';
import ExamTakerModal from '../components/student/ExamTakerModal';
import ExamResultModal from '../components/student/ExamResultModal';
import LeaderboardModal from '../components/common/LeaderboardModal';
import { api } from '../api/client';
import { useAuth } from '../context/AuthContext';
import { FileText, RefreshCw, Layers, Clock, Users, GraduationCap, AlertCircle } from 'lucide-react';

const asList = (data) => (Array.isArray(data) ? data : data?.results || []);

export default function StudentPortal() {
  const { user } = useAuth();
  const [tuitions, setTuitions] = useState([]);
  const [connections, setConnections] = useState([]);
  const [exams, setExams] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadingExams, setLoadingExams] = useState(true);
  const [error, setError] = useState('');

  // Modals
  const [takerModalOpen, setTakerModalOpen] = useState(false);
  const [resultModalOpen, setResultModalOpen] = useState(false);
  const [leaderboardModalOpen, setLeaderboardModalOpen] = useState(false);
  const [activeExam, setActiveExam] = useState(null);
  const [selectedLeaderboardExam, setSelectedLeaderboardExam] = useState(null);

  const loadData = useCallback(async () => {
    setError('');
    // Tuition groups (each carries the group's shared class progress) + tutor requests
    try {
      setLoading(true);
      const [tuitionData, connectionData] = await Promise.all([api.getTuitions(), api.getConnections()]);
      setTuitions(asList(tuitionData));
      setConnections(asList(connectionData));
    } catch (err) {
      setError(err.message || 'Could not load your tuitions.');
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

  // After handing in: show the evaluated paper at once if the tutor releases results
  // immediately, otherwise say when to expect them.
  const handleExamSubmitted = (response, exam) => {
    loadData();
    const status = response?.result_status;
    if (response?.results_released && exam?.id) {
      notify.success('Submitted. Here is your result.');
      handleViewResults(exam.id);
    } else if (status?.mode === 'SCHEDULED' && status.publish_at) {
      notify.success(`Submitted. Results will be published on ${new Date(status.publish_at).toLocaleString(undefined, { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' })}.`);
    } else {
      notify.success('Submitted. Your tutor will publish the results.');
    }
  };

  const handleViewLeaderboard = (exam) => {
    setSelectedLeaderboardExam(exam);
    setLeaderboardModalOpen(true);
  };

  const pendingRequests = connections.filter((c) => c.status === 'PENDING').length;

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
        {/* Welcome */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-6 rounded-2xl bg-gradient-to-r from-slate-900 via-indigo-950/40 to-slate-900 border border-slate-800">
          <div>
            <h1 className="text-2xl font-extrabold text-slate-100">
              Welcome back, {user?.name || user?.username}
            </h1>
            <p className="text-sm text-slate-400 mt-1">
              Your tuition groups, class progress and exams in one place.
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Pill icon={Layers} label={`${tuitions.length} tuition${tuitions.length === 1 ? '' : 's'}`} />
            {openExams > 0 && <Pill icon={FileText} label={`${openExams} to do now`} tone="emerald" />}
            <button
              type="button"
              onClick={loadData}
              className="p-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-400 hover:text-slate-200 border border-slate-700 transition"
              title="Refresh"
            >
              <RefreshCw className="w-4 h-4" />
            </button>
          </div>
        </div>

        {error && (
          <div className="px-4 py-3 rounded-xl bg-rose-500/10 border border-rose-500/25 text-rose-300 text-sm flex items-center gap-2">
            <AlertCircle className="w-4 h-4 flex-shrink-0" />
            {error}
          </div>
        )}

        {/* My tuition groups */}
        <section className="space-y-4">
          <SectionTitle
            icon={Layers}
            title="My tuition groups"
            subtitle="Class progress is shared with everyone in your group — your tutor ticks each class once it is held."
          />

          {loading ? (
            <div className="space-y-4">
              {[1, 2].map((i) => <div key={i} className="h-56 rounded-2xl bg-slate-800/40 animate-pulse" />)}
            </div>
          ) : tuitions.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-900/40 p-8 text-center">
              <GraduationCap className="w-10 h-10 mx-auto text-slate-600 mb-3" />
              <p className="text-sm font-semibold text-slate-200">You are not in a tuition group yet</p>
              <p className="text-xs text-slate-400 mt-1 max-w-md mx-auto">
                {pendingRequests > 0
                  ? 'Your request is with the tutor. As soon as they accept and place you in a group, it will show up here.'
                  : 'Find your tutor below and send a request. They will place you in a group.'}
              </p>
            </div>
          ) : (
            <div className="space-y-5">
              {tuitions.map((tuition) => (
                <TuitionGroupCard key={tuition.id} tuition={tuition} />
              ))}
            </div>
          )}
        </section>

        {/* Tutors & requests */}
        {!loading && (
          <TutorConnectPanel
            connections={connections}
            onChanged={loadData}
            defaultOpen={tuitions.length === 0 && connections.length === 0}
          />
        )}

        {/* Exams */}
        <section className="space-y-4">
          <SectionTitle
            icon={FileText}
            title="Exams & assignments"
            subtitle="Set by your tutor for the whole group. Your answers and marks are your own."
          />

          {loadingExams ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {[1, 2, 3].map((i) => <div key={i} className="h-44 rounded-2xl bg-slate-800/40 animate-pulse" />)}
            </div>
          ) : exams.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-900/40 p-8 text-center">
              <FileText className="w-10 h-10 mx-auto text-slate-600 mb-3" />
              <p className="text-sm font-semibold text-slate-200">No exams right now</p>
              <p className="text-xs text-slate-400 mt-1">When your tutor schedules one for your group, it will appear here.</p>
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
  const cls = tone === 'emerald'
    ? 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30'
    : 'bg-slate-800 text-slate-300 border-slate-700';
  return (
    <span className={`hidden sm:flex items-center gap-1.5 px-3 py-1.5 rounded-xl border text-xs font-semibold ${cls}`}>
      <Icon className="w-3.5 h-3.5" />
      {label}
    </span>
  );
}

/** One tuition group: who teaches it, when it meets, and the group's shared class progress. */
function TuitionGroupCard({ tuition }) {
  const routine = tuition.routine || tuition.weekly_routine || [];
  const count = tuition.enrolled_count || 0;
  return (
    <article className="rounded-2xl border border-slate-800 bg-slate-900/70 overflow-hidden">
      <header className="p-5 sm:p-6 flex flex-col md:flex-row md:items-start justify-between gap-4 border-b border-slate-800">
        <div className="min-w-0">
          <h3 className="text-xl font-bold text-slate-100 truncate">{tuition.title}</h3>
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-slate-400 mt-1">
            <span>Tutor: <strong className="text-indigo-300">{tuition.tutor_name}</strong></span>
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
                <span key={i} className="px-2.5 py-1 rounded-lg bg-slate-800 border border-slate-700 text-slate-200 text-xs font-medium">
                  {slot.day?.slice(0, 3)} {slot.start_time || slot.time}{slot.end_time ? `–${slot.end_time}` : ''}
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
