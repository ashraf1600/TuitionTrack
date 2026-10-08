import React, { useState, useEffect, useCallback } from 'react';
import {
  ArrowLeft, GraduationCap, Calendar, BookOpen, Clock,
  Loader2, RefreshCw, AlertCircle, User,
} from 'lucide-react';
import { api, getMediaUrl } from '../../api/client';
import HomeworkCard from './HomeworkCard';

const TABS = [
  { key: 'routine', label: 'Weekly Routine', icon: Clock },
  { key: 'classes', label: 'My Classes', icon: Calendar },
  { key: 'homework', label: 'Homework', icon: BookOpen },
];

const DAY_ORDER = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

// Day abbreviation → full name map
const DAY_ABBR = {
  Sun: 'Sunday', Mon: 'Monday', Tue: 'Tuesday', Wed: 'Wednesday',
  Thu: 'Thursday', Fri: 'Friday', Sat: 'Saturday',
};

function normDay(d) {
  if (!d) return '';
  const cap = d.charAt(0).toUpperCase() + d.slice(1).toLowerCase();
  return DAY_ABBR[cap.slice(0, 3)] || cap;
}

const DAY_COLORS = [
  'from-indigo-500/20 to-violet-500/20 border-indigo-500/30',
  'from-blue-500/20 to-cyan-500/20 border-blue-500/30',
  'from-emerald-500/20 to-teal-500/20 border-emerald-500/30',
  'from-amber-500/20 to-orange-500/20 border-amber-500/30',
  'from-rose-500/20 to-pink-500/20 border-rose-500/30',
  'from-purple-500/20 to-fuchsia-500/20 border-purple-500/30',
  'from-sky-500/20 to-blue-500/20 border-sky-500/30',
];

/**
 * TutorDetailView — Detailed view of a connected tutor for a student.
 *
 * Shows:
 *  - Tutor profile header ("Ashraf Sir" + profile picture)
 *  - Weekly Routine tab (day/time/subject cards)
 *  - Homework tab (HomeworkCard list with live countdown + 2-hour alert)
 */
export default function TutorDetailView({ tutorId, onBack }) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [activeTab, setActiveTab] = useState('routine');
  const [homework, setHomework] = useState([]);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const res = await api.getTutorDetail(tutorId);
      setData(res.tutor);
      setHomework(res.homework || []);
    } catch (err) {
      setError(err.message || 'Could not load tutor details.');
    } finally {
      setLoading(false);
    }
  }, [tutorId]);

  useEffect(() => { load(); }, [load]);

  const handleHomeworkUpdate = (updated) => {
    setHomework((prev) => prev.map((h) => (h.id === updated.id ? updated : h)));
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="w-8 h-8 text-indigo-400 animate-spin" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-2xl border border-rose-500/25 bg-rose-500/10 p-6 text-center">
        <AlertCircle className="w-8 h-8 text-rose-400 mx-auto mb-3" />
        <p className="text-sm text-rose-300 font-semibold">{error}</p>
        <button onClick={load} className="mt-4 text-xs text-slate-400 hover:text-slate-200 underline">
          Try again
        </button>
      </div>
    );
  }

  if (!data) return null;

  // Aggregate all routines from all tuitions
  const allRoutineSlots = [];
  (data.tuitions || []).forEach((t) => {
    (t.routine || []).forEach((slot) => {
      allRoutineSlots.push({ ...slot, tuition_title: t.title, tuition_subject: t.subject });
    });
  });

  // Sort by day order
  const sortedRoutine = [...allRoutineSlots].sort((a, b) => {
    return DAY_ORDER.indexOf(normDay(a.day)) - DAY_ORDER.indexOf(normDay(b.day));
  });

  const pendingHw = homework.filter((h) => !h.is_evaluated && new Date(h.due_date) > new Date());
  const doneHw = homework.filter((h) => h.is_evaluated);
  const overdueHw = homework.filter((h) => !h.is_evaluated && new Date(h.due_date) <= new Date());

  return (
    <div className="space-y-6">
      {/* Back button */}
      <button
        type="button"
        onClick={onBack}
        className="flex items-center gap-2 text-sm text-slate-400 hover:text-slate-200 transition group"
      >
        <ArrowLeft className="w-4 h-4 group-hover:-translate-x-0.5 transition-transform" />
        Back to My Tutors
      </button>

      {/* Tutor profile card */}
      <div className="relative overflow-hidden rounded-2xl border border-indigo-500/20 bg-gradient-to-br from-slate-900 via-indigo-950/20 to-slate-900 p-4 sm:p-8">
        <div className="pointer-events-none absolute -top-12 -right-12 w-56 h-56 bg-indigo-600/8 rounded-full blur-3xl" />
        <div className="relative flex items-start gap-3.5 sm:gap-5">
          {/* Avatar */}
          <div className="flex-shrink-0">
            {data.profile_picture_url ? (
              <img
                src={getMediaUrl(data.profile_picture_url)}
                alt={data.display_name}
                className="w-14 h-14 sm:w-20 sm:h-20 rounded-2xl object-cover border-2 border-indigo-500/30 shadow-lg"
              />
            ) : (
              <div className="w-14 h-14 sm:w-20 sm:h-20 rounded-2xl bg-gradient-to-br from-indigo-500 to-violet-500 flex items-center justify-center text-white text-xl sm:text-3xl font-black shadow-lg shadow-indigo-500/20">
                {(data.display_name || 'T')[0]}
              </div>
            )}
          </div>

          {/* Info */}
          <div className="min-w-0 flex-1">
            <h2 className="text-xl sm:text-3xl font-black text-slate-100 truncate">
              {data.display_name}
            </h2>
            <div className="text-xs sm:text-sm text-slate-400 font-mono mt-0.5">@{data.username}</div>

            {/* Subjects */}
            {data.subjects?.length > 0 && (
              <div className="flex flex-wrap gap-1.5 mt-2.5 sm:mt-3">
                {data.subjects.map((s) => (
                  <span key={s} className="px-2 sm:px-2.5 py-0.5 rounded-full bg-indigo-500/15 border border-indigo-500/25 text-indigo-300 text-[10px] sm:text-[11px] font-semibold">
                    {s}
                  </span>
                ))}
              </div>
            )}

            {/* Tuition groups */}
            {data.tuitions?.length > 0 && (
              <div className="mt-1.5 sm:mt-2 text-[10px] sm:text-[11px] text-slate-500">
                {data.tuitions.length} tuition group{data.tuitions.length > 1 ? 's' : ''} ·{' '}
                {data.tuitions.map((t) => t.title).join(', ')}
              </div>
            )}
          </div>

          {/* Refresh */}
          <button
            type="button"
            onClick={load}
            className="ml-auto p-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-400 hover:text-slate-200 border border-slate-700 transition flex-shrink-0"
            title="Refresh"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 p-1 rounded-xl bg-slate-900/80 border border-slate-800">
        {TABS.map(({ key, label, icon: Icon }) => {
          const isActive = activeTab === key;
          const badge = key === 'homework' ? pendingHw.length : null;
          return (
            <button
              key={key}
              type="button"
              onClick={() => setActiveTab(key)}
              className={`flex-1 flex items-center justify-center gap-1.5 sm:gap-2 py-2 sm:py-2.5 px-2 sm:px-3 rounded-lg text-xs sm:text-sm font-semibold transition-all duration-200 ${
                isActive
                  ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/20'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800'
              }`}
            >
              <Icon className="w-4 h-4 flex-shrink-0" />
              <span>{label}</span>
              {badge > 0 && (
                <span className={`px-1.5 py-0.5 rounded-full text-[10px] font-black ${isActive ? 'bg-white/20 text-white' : 'bg-rose-500/20 text-rose-300'}`}>
                  {badge}
                </span>
              )}
            </button>
          );
        })}
      </div>

      {/* Tab: Weekly Routine */}
      {activeTab === 'routine' && (
        <div>
          {sortedRoutine.length === 0 ? (
            <EmptyState icon={Clock} title="No routine set yet" desc="Your tutor hasn't added their weekly schedule yet." />
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
              {sortedRoutine.map((slot, i) => {
                const colorClass = DAY_COLORS[DAY_ORDER.indexOf(normDay(slot.day)) % DAY_COLORS.length];
                return (
                  <div
                    key={i}
                    className={`rounded-2xl border bg-gradient-to-br ${colorClass} p-4 space-y-2`}
                  >
                    <div className="flex items-center justify-between">
                      <span className="text-base font-black text-slate-100">
                        {normDay(slot.day)}
                      </span>
                      {slot.tuition_subject && (
                        <span className="px-2 py-0.5 rounded-full bg-slate-900/60 text-slate-300 text-[10px] font-semibold">
                          {slot.tuition_subject}
                        </span>
                      )}
                    </div>
                    <div className="flex items-center gap-2 text-sm text-slate-200 font-mono font-semibold">
                      <Clock className="w-4 h-4 text-slate-400" />
                      {slot.start_time || slot.time || '—'}
                      {slot.end_time && <span className="text-slate-400">→ {slot.end_time}</span>}
                    </div>
                    {slot.tuition_title && (
                      <div className="text-[11px] text-slate-400 font-medium truncate">
                        {slot.tuition_title}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {/* Tab: Classes */}
      {activeTab === 'classes' && (
        <div className="space-y-4">
          {(data.tuitions || []).length === 0 ? (
            <EmptyState icon={Calendar} title="No classes found" desc="You are not enrolled in any tuition batches for this tutor yet." />
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {data.tuitions.map((t) => (
                <div key={t.id} className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5 space-y-3">
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <h4 className="text-base font-bold text-slate-100">{t.title}</h4>
                      {t.subject && (
                        <span className="inline-block mt-1 px-2.5 py-0.5 rounded-full bg-indigo-500/15 border border-indigo-500/25 text-indigo-300 text-xs font-semibold">
                          {t.subject}
                        </span>
                      )}
                    </div>
                    {t.cycle_length && (
                      <span className="px-2.5 py-1 rounded-xl bg-slate-800 border border-slate-700 text-xs font-medium text-slate-300">
                        {t.cycle_length} classes / cycle
                      </span>
                    )}
                  </div>

                  {t.routine?.length > 0 && (
                    <div className="pt-2 border-t border-slate-800/80">
                      <span className="text-[10px] font-bold uppercase tracking-wider text-slate-500 block mb-1.5">Weekly Schedule:</span>
                      <div className="flex flex-wrap gap-1.5">
                        {t.routine.map((slot, idx) => (
                          <span key={idx} className="px-2 py-0.5 rounded-lg bg-slate-800 text-slate-300 text-xs font-medium">
                            {slot.day?.slice(0, 3)} {slot.start_time || slot.time}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Tab: Homework */}
      {activeTab === 'homework' && (
        <div className="space-y-6">
          {homework.length === 0 ? (
            <EmptyState icon={BookOpen} title="No homework yet" desc="Your tutor hasn't assigned any homework yet. Check back later." />
          ) : (
            <>
              {pendingHw.length > 0 && (
                <section>
                  <SectionLabel text={`Pending · ${pendingHw.length}`} tone="rose" />
                  <div className="space-y-3 mt-3">
                    {pendingHw.map((hw) => (
                      <HomeworkCard key={hw.id} homework={hw} isTutor={false} onUpdated={handleHomeworkUpdate} />
                    ))}
                  </div>
                </section>
              )}

              {overdueHw.length > 0 && (
                <section>
                  <SectionLabel text={`Overdue · ${overdueHw.length}`} tone="orange" />
                  <div className="space-y-3 mt-3">
                    {overdueHw.map((hw) => (
                      <HomeworkCard key={hw.id} homework={hw} isTutor={false} onUpdated={handleHomeworkUpdate} />
                    ))}
                  </div>
                </section>
              )}

              {doneHw.length > 0 && (
                <section>
                  <SectionLabel text={`Completed · ${doneHw.length}`} tone="emerald" />
                  <div className="space-y-3 mt-3">
                    {doneHw.map((hw) => (
                      <HomeworkCard key={hw.id} homework={hw} isTutor={false} onUpdated={handleHomeworkUpdate} />
                    ))}
                  </div>
                </section>
              )}
            </>
          )}
        </div>
      )}
    </div>
  );
}

function SectionLabel({ text, tone }) {
  const colors = {
    rose: 'text-rose-400 border-rose-500/30',
    orange: 'text-orange-400 border-orange-500/30',
    emerald: 'text-emerald-400 border-emerald-500/30',
    indigo: 'text-indigo-400 border-indigo-500/30',
  };
  return (
    <div className={`text-xs font-bold uppercase tracking-wider border-b pb-2 ${colors[tone] || colors.indigo}`}>
      {text}
    </div>
  );
}

function EmptyState({ icon: Icon, title, desc }) {
  return (
    <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-900/40 p-10 text-center">
      <Icon className="w-10 h-10 mx-auto text-slate-600 mb-3" />
      <p className="text-sm font-bold text-slate-200">{title}</p>
      {desc && <p className="text-xs text-slate-500 mt-1 max-w-xs mx-auto">{desc}</p>}
    </div>
  );
}
