import React, { useState, useEffect, useCallback } from 'react';
import {
  ArrowLeft, GraduationCap, Calendar, BookOpen, Clock,
  Loader2, RefreshCw, AlertCircle, CheckCircle2, Layers,
  FileText, Award, HelpCircle, Check, Timer
} from 'lucide-react';
import { api, getMediaUrl } from '../../api/client';
import StudentCycleProgress from './StudentCycleProgress';
import HomeworkCard from './HomeworkCard';
import ExamCard from './ExamCard';

const TABS = [
  { key: 'routine', label: '1. Class Routine', shortLabel: 'Class Routine', icon: Clock },
  { key: 'progress', label: '2. Class Progress Board', shortLabel: 'Class Progress', icon: Calendar },
  { key: 'assessments', label: '3. Assessments & Tasks', shortLabel: 'Assessments & Tasks', icon: BookOpen },
];

const DAY_ORDER = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const DAY_ABBR = {
  Sun: 'Sunday', Mon: 'Monday', Tue: 'Tuesday', Wed: 'Wednesday',
  Thu: 'Thursday', Fri: 'Friday', Sat: 'Saturday',
};

function normDay(d) {
  if (!d) return '';
  const cap = d.charAt(0).toUpperCase() + d.slice(1).toLowerCase();
  return DAY_ABBR[cap.slice(0, 3)] || cap;
}

const DAY_BADGE_STYLES = [
  'bg-indigo-50 text-indigo-700 border-indigo-200',
  'bg-sky-50 text-sky-700 border-sky-200',
  'bg-emerald-50 text-emerald-700 border-emerald-200',
  'bg-amber-50 text-amber-700 border-amber-200',
  'bg-rose-50 text-rose-700 border-rose-200',
  'bg-slate-100 text-slate-700 border-slate-200',
  'bg-indigo-100 text-indigo-800 border-indigo-300',
];

/**
 * Screen 2: The "Tutor Workspace" (Detail View)
 *
 * Dedicated, isolated virtual classroom for a specific tutor ("Ashraf Sir's Class").
 * Organized in the EXACT order requested:
 *   1. Class Routine: horizontal list / card showing weekly routine and time.
 *   2. Class Progress Board: dynamic 12-class grid showing cycle progress.
 *   3. Assessments & Tasks: section/tabs containing Homework, Assignments, and Exams.
 */
export default function TutorWorkspaceView({
  tutorId,
  onBack,
  allTuitions = [],
  allExams = [],
  onTakeExam,
  onViewResults,
  onViewLeaderboard,
}) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [activeTab, setActiveTab] = useState('routine');
  const [homework, setHomework] = useState([]);
  const [weeklyRoutine, setWeeklyRoutine] = useState([]);
  const [taskFilter, setTaskFilter] = useState('all'); // 'all' | 'homework' | 'assignments' | 'exams'
  const [selectedBatchId, setSelectedBatchId] = useState(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const res = await api.getTutorDetail(tutorId);
      setData(res.tutor);
      setHomework(res.homework || []);
      setWeeklyRoutine(res.weekly_routine || []);
    } catch (err) {
      setError(err.message || 'Could not load tutor classroom details.');
    } finally {
      setLoading(false);
    }
  }, [tutorId]);

  useEffect(() => {
    load();
  }, [load]);

  const handleHomeworkUpdate = (updated) => {
    setHomework((prev) => prev.map((h) => (h.id === updated.id ? updated : h)));
  };

  if (loading && !data) {
    return (
      <div className="flex flex-col items-center justify-center py-28 space-y-3">
        <Loader2 className="w-9 h-9 text-indigo-600 animate-spin" />
        <p className="text-sm font-semibold text-slate-500">Entering Virtual Classroom...</p>
      </div>
    );
  }

  if (error && !data) {
    return (
      <div className="rounded-2xl border border-rose-200 bg-rose-50 p-8 text-center max-w-lg mx-auto space-y-4">
        <AlertCircle className="w-10 h-10 text-rose-500 mx-auto" />
        <div>
          <h3 className="text-base font-bold text-rose-800">Classroom Unavailable</h3>
          <p className="text-sm text-rose-600 mt-1">{error}</p>
        </div>
        <div className="flex items-center justify-center gap-3 pt-2">
          <button
            type="button"
            onClick={onBack}
            className="px-4 py-2 rounded-xl bg-white border border-slate-200 text-xs font-semibold text-slate-700 hover:bg-slate-50"
          >
            Back to Tutors
          </button>
          <button
            type="button"
            onClick={load}
            className="px-4 py-2 rounded-xl bg-indigo-600 text-white text-xs font-bold hover:bg-indigo-700"
          >
            Retry
          </button>
        </div>
      </div>
    );
  }

  if (!data) return null;

  // ── Scoped Tuitions for this Tutor ──
  const tutorTuitionIds = new Set((data.tuitions || []).map((t) => String(t.id)));
  const tutorTuitions = allTuitions.filter(
    (t) =>
      tutorTuitionIds.has(String(t.id)) ||
      (t.tutor && String(t.tutor.id || t.tutor) === String(tutorId)) ||
      t.tutor_name === data.display_name
  );

  // Default selected batch if not set
  const activeBatch =
    tutorTuitions.find((t) => String(t.id) === String(selectedBatchId)) ||
    tutorTuitions[0] ||
    null;

  // ── Scoped Exams & Assignments for this Tutor ──
  const tutorExams = allExams.filter(
    (e) =>
      String(e.tutor) === String(tutorId) ||
      e.tutor_name === data.display_name ||
      (e.tuition_id && tutorTuitionIds.has(String(e.tuition_id)))
  );

  const assignments = tutorExams.filter((e) => e.category === 'ASSIGNMENT');
  const examsOnly = tutorExams.filter((e) => e.category !== 'ASSIGNMENT');

  const pendingHomework = homework.filter((h) => !h.is_evaluated && new Date(h.due_date) > new Date());
  const dueSoonHomework = pendingHomework.filter((h) => new Date(h.due_date).getTime() - Date.now() <= 86_400_000);
  const totalTasksCount = homework.length + tutorExams.length;

  // Pending first (nearest deadline on top), then evaluated — nothing pending gets buried.
  const sortedHomework = [...homework].sort((a, b) => {
    if (!!a.is_evaluated !== !!b.is_evaluated) return a.is_evaluated ? 1 : -1;
    return new Date(a.due_date).getTime() - new Date(b.due_date).getTime();
  });

  // ── Aggregate & Sort Weekly Routine Slots ──
  const allRoutineSlots = [];
  if (weeklyRoutine.length > 0) {
    weeklyRoutine.forEach((r) => {
      allRoutineSlots.push({
        day: r.day_of_week || r.day,
        start_time: r.start_time,
        end_time: r.end_time,
        subject: r.subject || data.subjects?.[0] || 'Tuition',
        tuition_title: r.tuition_title,
      });
    });
  } else {
    (data.tuitions || []).forEach((t) => {
      (t.routine || []).forEach((slot) => {
        allRoutineSlots.push({
          ...slot,
          tuition_title: t.title,
          tuition_subject: t.subject || data.subjects?.[0],
        });
      });
    });
  }

  const sortedRoutine = [...allRoutineSlots].sort((a, b) => {
    return DAY_ORDER.indexOf(normDay(a.day)) - DAY_ORDER.indexOf(normDay(b.day));
  });

  const photoUrl = data.profile_picture_url ? getMediaUrl(data.profile_picture_url) : null;

  return (
    <div className="space-y-6 sm:space-y-8 animate-fadeIn">
      {/* ── Prominent "Back to My Tutors" Navigation ── */}
      <div className="flex items-center justify-between">
        <button
          type="button"
          onClick={onBack}
          className="inline-flex items-center gap-2 px-3.5 py-2 rounded-xl bg-white border border-slate-200/90 shadow-sm text-xs sm:text-sm font-semibold text-slate-700 hover:text-indigo-600 hover:border-indigo-300 hover:bg-slate-50 transition-all duration-150 group"
        >
          <ArrowLeft className="w-4 h-4 group-hover:-translate-x-1 transition-transform" />
          <span>Back to My Tutors</span>
        </button>

        <span className="text-xs text-slate-400 font-medium hidden sm:inline-block">
          Virtual Classroom · Isolated Workspace
        </span>
      </div>

      {/* ── Classroom Header / AppBar: "[Tutor Name]'s Class" ── */}
      <section className="relative overflow-hidden rounded-2xl bg-white border-t-4 border-t-indigo-600 border-x border-b border-slate-200/80 shadow-sm p-6 sm:p-8">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-6">
          <div className="flex items-start sm:items-center gap-4 sm:gap-5">
            {/* Tutor Avatar */}
            <div className="relative flex-shrink-0">
              {photoUrl ? (
                <img
                  src={photoUrl}
                  alt={data.display_name}
                  className="w-16 h-16 sm:w-20 sm:h-20 rounded-2xl object-cover border-2 border-slate-200 shadow-sm"
                />
              ) : (
                <div className="w-16 h-16 sm:w-20 sm:h-20 rounded-2xl bg-gradient-to-br from-indigo-500 to-indigo-700 flex items-center justify-center text-white text-2xl sm:text-3xl font-black shadow-sm">
                  {(data.display_name || 'T')[0]}
                </div>
              )}
              <span
                className="absolute -bottom-1 -right-1 w-5 h-5 rounded-full bg-emerald-500 border-2 border-white flex items-center justify-center shadow-xs"
                title="Active Connected Tutor"
              >
                <Check className="w-3 h-3 text-white stroke-[3]" />
              </span>
            </div>

            {/* Tutor & Classroom Details */}
            <div className="min-w-0 flex-1">
              <div className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-indigo-50 text-indigo-700 border border-indigo-200 mb-1.5">
                <GraduationCap className="w-3.5 h-3.5" />
                <span>Dedicated Classroom</span>
              </div>

              {/* Exact requested header title */}
              <h1 className="text-2xl sm:text-3xl font-black text-slate-900 tracking-tight truncate">
                {data.display_name}'s Class
              </h1>

              <div className="flex flex-wrap items-center gap-x-3 gap-y-1 mt-1 text-xs text-slate-500">
                <span className="font-mono text-slate-400">@{data.username}</span>
                {data.subjects?.map((sub) => (
                  <span
                    key={sub}
                    className="px-2 py-0.5 rounded-full bg-slate-100 border border-slate-200 text-slate-700 font-semibold text-[11px]"
                  >
                    {sub}
                  </span>
                ))}
              </div>

              {data.tuitions?.length > 0 && (
                <p className="text-[11px] text-slate-400 mt-1.5">
                  {data.tuitions.length} batch{data.tuitions.length > 1 ? 'es' : ''}:{' '}
                  <span className="font-medium text-slate-600">
                    {data.tuitions.map((t) => t.title).join(', ')}
                  </span>
                </p>
              )}
            </div>
          </div>

          <div className="flex items-center gap-2 sm:self-start">
            <button
              type="button"
              onClick={load}
              className="p-2.5 rounded-xl bg-slate-50 hover:bg-slate-100 text-slate-600 hover:text-slate-900 border border-slate-200 transition"
              title="Refresh classroom"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-indigo-600' : ''}`} />
            </button>
          </div>
        </div>
      </section>

      {/* ── TabBar: 3 Required Sections in Exact Order ── */}
      <nav className="flex p-1.5 rounded-2xl bg-white border border-slate-200/90 shadow-sm gap-1 sm:gap-2">
        {TABS.map(({ key, label, shortLabel, icon: Icon }) => {
          const isActive = activeTab === key;
          const badgeCount = key === 'assessments' ? totalTasksCount : null;

          return (
            <button
              key={key}
              type="button"
              onClick={() => setActiveTab(key)}
              className={`flex-1 flex items-center justify-center gap-2 py-2.5 sm:py-3 px-3 rounded-xl text-xs sm:text-sm font-bold transition-all duration-150 ${
                isActive
                  ? 'bg-indigo-600 text-white shadow-sm'
                  : 'text-slate-600 hover:text-slate-900 hover:bg-slate-50'
              }`}
            >
              <Icon className="w-4 h-4 flex-shrink-0" />
              <span className="hidden md:inline">{label}</span>
              <span className="md:hidden">{shortLabel}</span>
              {badgeCount !== null && badgeCount > 0 && (
                <span
                  className={`px-1.5 py-0.5 rounded-full text-[10px] font-black ${
                    isActive ? 'bg-white/25 text-white' : 'bg-indigo-100 text-indigo-700'
                  }`}
                >
                  {badgeCount}
                </span>
              )}
            </button>
          );
        })}
      </nav>

      {/* ──────────────────────────────────────────────────────────────────────────
          SECTION 1: Class Routine (Exact Order #1)
          A beautiful horizontal list or card showing weekly routine and time.
      ────────────────────────────────────────────────────────────────────────── */}
      {activeTab === 'routine' && (
        <section className="space-y-4 animate-fadeIn">
          <SectionHeader
            title="Weekly Class Routine"
            subtitle={`Official weekly class timetable organized by ${data.display_name}.`}
            count={sortedRoutine.length}
          />

          {sortedRoutine.length === 0 ? (
            <EmptyWorkspaceCard
              icon={Clock}
              title="No Routine Set Yet"
              desc={`${data.display_name} hasn't published their weekly routine schedule yet.`}
            />
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {sortedRoutine.map((slot, idx) => {
                const dayName = normDay(slot.day);
                const badgeStyle = DAY_BADGE_STYLES[DAY_ORDER.indexOf(dayName) % DAY_BADGE_STYLES.length];

                return (
                  <div
                    key={idx}
                    className="rounded-2xl border border-slate-200/90 bg-white p-5 shadow-sm hover:shadow-md transition-all space-y-3"
                  >
                    <div className="flex items-center justify-between">
                      <span
                        className={`px-3 py-1 rounded-xl text-xs font-extrabold border ${badgeStyle}`}
                      >
                        {dayName}
                      </span>
                      {slot.tuition_subject && (
                        <span className="px-2.5 py-0.5 rounded-full bg-slate-100 border border-slate-200 text-slate-700 text-[11px] font-semibold">
                          {slot.tuition_subject}
                        </span>
                      )}
                    </div>

                    <div className="flex items-center gap-2 text-sm text-slate-900 font-mono font-bold pt-1">
                      <Clock className="w-4 h-4 text-indigo-600" />
                      <span>{slot.start_time || slot.time || 'TBD'}</span>
                      {slot.end_time && <span className="text-slate-400">→</span>}
                      {slot.end_time && <span>{slot.end_time}</span>}
                    </div>

                    {slot.tuition_title && (
                      <div className="text-xs text-slate-500 font-medium truncate pt-1 border-t border-slate-100 flex items-center gap-1.5">
                        <Layers className="w-3.5 h-3.5 text-slate-400" />
                        <span>{slot.tuition_title}</span>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </section>
      )}

      {/* ──────────────────────────────────────────────────────────────────────────
          SECTION 2: Class Progress Board (Exact Order #2)
          Dynamic 12-class (or custom cycle) grid showing how many classes are done.
      ────────────────────────────────────────────────────────────────────────── */}
      {activeTab === 'progress' && (
        <section className="space-y-6 animate-fadeIn">
          <SectionHeader
            title="Class Progress Board"
            subtitle="The dynamic 12-class cycle tracker. Your tutor ticks off each class after it is conducted."
          />

          {tutorTuitions.length === 0 ? (
            <EmptyWorkspaceCard
              icon={Calendar}
              title="No Tuition Group Enrolled"
              desc={`You are not enrolled in any batch for ${data.display_name} yet.`}
            />
          ) : (
            <div className="space-y-6">
              {/* Batch Selector if student is in multiple groups with this tutor */}
              {tutorTuitions.length > 1 && (
                <div className="flex items-center gap-2 overflow-x-auto pb-2">
                  <span className="text-xs font-bold text-slate-500 uppercase tracking-wider mr-1">
                    Select Batch:
                  </span>
                  {tutorTuitions.map((t) => (
                    <button
                      key={t.id}
                      type="button"
                      onClick={() => setSelectedBatchId(t.id)}
                      className={`px-3 py-1.5 rounded-xl text-xs font-bold transition whitespace-nowrap ${
                        String(activeBatch?.id) === String(t.id)
                          ? 'bg-indigo-600 text-white shadow-xs'
                          : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'
                      }`}
                    >
                      {t.title}
                    </button>
                  ))}
                </div>
              )}

              {/* Main Progress Board Card */}
              {activeBatch && (
                <div className="rounded-2xl border border-slate-200/90 bg-white p-6 shadow-sm space-y-6">
                  <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-4 border-b border-slate-100">
                    <div>
                      <h3 className="text-lg font-bold text-slate-900">{activeBatch.title}</h3>
                      <div className="flex items-center gap-2 text-xs text-slate-500 mt-1">
                        {activeBatch.subject && (
                          <span className="font-semibold text-indigo-600">{activeBatch.subject}</span>
                        )}
                        <span>·</span>
                        <span>{activeBatch.cycle_length || 12} Classes Per Cycle</span>
                        {activeBatch.enrolled_count && (
                          <>
                            <span>·</span>
                            <span>{activeBatch.enrolled_count} Students Enrolled</span>
                          </>
                        )}
                      </div>
                    </div>

                    <span className="self-start sm:self-auto px-3 py-1 rounded-xl bg-emerald-50 text-emerald-700 border border-emerald-200 text-xs font-bold flex items-center gap-1.5">
                      <span className="w-2 h-2 rounded-full bg-emerald-500" />
                      Active Cycle
                    </span>
                  </div>

                  {/* Dynamic 12-Class Grid Embedded */}
                  <StudentCycleProgress
                    cycle={activeBatch.active_cycle}
                    embedded={true}
                    light={true}
                  />
                </div>
              )}
            </div>
          )}
        </section>
      )}

      {/* ──────────────────────────────────────────────────────────────────────────
          SECTION 3: Assessments & Tasks (Exact Order #3)
          Contains "Homework", "Assignments", and "Exams" assigned by this specific tutor.
      ────────────────────────────────────────────────────────────────────────── */}
      {activeTab === 'assessments' && (
        <section className="space-y-6 animate-fadeIn">
          <SectionHeader
            title="Assessments & Tasks"
            subtitle={`Homework, assignments, and exams assigned by ${data.display_name}.`}
          />

          {/* Sub-Filter Pills */}
          <div className="flex flex-wrap items-center gap-2">
            {[
              { id: 'all', label: 'All Tasks', count: totalTasksCount },
              { id: 'homework', label: 'Homework', count: homework.length },
              { id: 'assignments', label: 'Assignments', count: assignments.length },
              { id: 'exams', label: 'Exams', count: examsOnly.length },
            ].map((f) => (
              <button
                key={f.id}
                type="button"
                onClick={() => setTaskFilter(f.id)}
                className={`px-3 py-1.5 rounded-xl text-xs font-bold transition flex items-center gap-1.5 ${
                  taskFilter === f.id
                    ? 'bg-slate-900 text-white shadow-xs'
                    : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'
                }`}
              >
                <span>{f.label}</span>
                <span
                  className={`px-1.5 py-0.2 rounded-full text-[10px] font-black ${
                    taskFilter === f.id ? 'bg-white/20 text-white' : 'bg-slate-100 text-slate-600'
                  }`}
                >
                  {f.count}
                </span>
              </button>
            ))}
          </div>

          {/* ── Sub-section: Homework ── */}
          {(taskFilter === 'all' || taskFilter === 'homework') && (
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <h4 className="text-xs font-extrabold uppercase tracking-wider text-slate-500 flex items-center gap-1.5">
                  <BookOpen className="w-3.5 h-3.5 text-indigo-600" />
                  <span>Homework ({homework.length})</span>
                </h4>
                {pendingHomework.length > 0 && (
                  <span className="px-2.5 py-0.5 rounded-full bg-amber-100 border border-amber-300 text-amber-800 text-[11px] font-bold">
                    {pendingHomework.length} pending
                  </span>
                )}
              </div>

              {pendingHomework.length > 0 && (
                <div className="px-4 py-3 rounded-2xl bg-amber-50 border border-amber-200 flex items-center gap-2.5">
                  <BookOpen className="w-4 h-4 text-amber-600 flex-shrink-0" />
                  <p className="text-xs text-amber-800">
                    <strong>{pendingHomework.length} homework still pending review</strong>
                    {dueSoonHomework.length > 0 && (
                      <> — <strong>{dueSoonHomework.length} due within 24 hours</strong>, finish them first.</>
                    )}
                    {dueSoonHomework.length === 0 && <> — newest deadline first below.</>}
                  </p>
                </div>
              )}

              {homework.length === 0 ? (
                <EmptyWorkspaceCard
                  icon={BookOpen}
                  title="No Homework Assigned"
                  desc={`${data.display_name} has not assigned any homework yet.`}
                />
              ) : (
                <div className="space-y-3">
                  {sortedHomework.map((hw) => (
                    <HomeworkCard
                      key={hw.id}
                      homework={hw}
                      isTutor={false}
                      onUpdated={handleHomeworkUpdate}
                    />
                  ))}
                </div>
              )}
            </div>
          )}

          {/* ── Sub-section: Assignments ── */}
          {(taskFilter === 'all' || taskFilter === 'assignments') && (
            <div className="space-y-3 pt-2">
              <div className="flex items-center justify-between">
                <h4 className="text-xs font-extrabold uppercase tracking-wider text-slate-500 flex items-center gap-1.5">
                  <FileText className="w-3.5 h-3.5 text-indigo-600" />
                  <span>Assignments ({assignments.length})</span>
                </h4>
              </div>

              {assignments.length === 0 ? (
                <EmptyWorkspaceCard
                  icon={FileText}
                  title="No Assignments"
                  desc="No long-form assignments have been assigned for this class."
                />
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                  {assignments.map((exam) => (
                    <ExamCard
                      key={exam.id}
                      exam={exam}
                      light={true}
                      onTakeExam={onTakeExam}
                      onViewResults={onViewResults}
                      onViewLeaderboard={onViewLeaderboard}
                    />
                  ))}
                </div>
              )}
            </div>
          )}

          {/* ── Sub-section: Exams ── */}
          {(taskFilter === 'all' || taskFilter === 'exams') && (
            <div className="space-y-3 pt-2">
              <div className="flex items-center justify-between">
                <h4 className="text-xs font-extrabold uppercase tracking-wider text-slate-500 flex items-center gap-1.5">
                  <Award className="w-3.5 h-3.5 text-amber-600" />
                  <span>Exams & Quizzes ({examsOnly.length})</span>
                </h4>
              </div>

              {examsOnly.length === 0 ? (
                <EmptyWorkspaceCard
                  icon={Award}
                  title="No Exams Scheduled"
                  desc={`${data.display_name} has not scheduled any exams for this group right now.`}
                />
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                  {examsOnly.map((exam) => (
                    <ExamCard
                      key={exam.id}
                      exam={exam}
                      light={true}
                      onTakeExam={onTakeExam}
                      onViewResults={onViewResults}
                      onViewLeaderboard={onViewLeaderboard}
                    />
                  ))}
                </div>
              )}
            </div>
          )}
        </section>
      )}
    </div>
  );
}

function SectionHeader({ title, subtitle, count }) {
  return (
    <div className="flex items-baseline justify-between gap-4">
      <div>
        <h2 className="text-lg font-bold text-slate-900 tracking-tight">{title}</h2>
        <p className="text-xs text-slate-500 mt-0.5">{subtitle}</p>
      </div>
      {count !== undefined && (
        <span className="text-xs font-bold text-slate-400">{count} total</span>
      )}
    </div>
  );
}

function EmptyWorkspaceCard({ icon: Icon, title, desc }) {
  return (
    <div className="rounded-2xl border border-dashed border-slate-200 bg-white p-8 text-center space-y-2 shadow-xs">
      <Icon className="w-8 h-8 mx-auto text-slate-400" />
      <h3 className="text-sm font-bold text-slate-800">{title}</h3>
      {desc && <p className="text-xs text-slate-500 max-w-sm mx-auto">{desc}</p>}
    </div>
  );
}
