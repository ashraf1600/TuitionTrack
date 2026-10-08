import React from 'react';
import {
  UserCheck, Plus, ChevronRight, Layers, Sparkles, RefreshCw,
  ArrowRight, BookOpen, AlertCircle
} from 'lucide-react';
import { getMediaUrl } from '../../api/client';
import TutorCodeConnect from './TutorCodeConnect';

/**
 * Screen 1: The "Connected Tutors" Hub (Master View)
 *
 * An ultra-clean, distraction-free navigation hub for students.
 * ONLY displays the Grid of Connected Tutor Cards ("Ashraf Sir", etc.).
 * Strictly NO global class tracker, NO global homework, NO global exams here.
 */
export default function ConnectedTutorsHub({
  studentName,
  tutors = [],
  connections = [],
  loading = false,
  error = '',
  onSelectTutor,
  onOpenConnectModal,
  onRefresh,
  onChanged,
}) {
  return (
    <div className="space-y-8 animate-fadeIn">
      {/* ── Hub Welcome Header / Hero ── */}
      <header className="rounded-2xl bg-white border border-slate-200/80 shadow-sm p-6 sm:p-8 flex flex-col sm:flex-row sm:items-center justify-between gap-6">
        <div>
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-semibold bg-indigo-50 text-indigo-700 border border-indigo-100 mb-3">
            <Sparkles className="w-3.5 h-3.5 text-indigo-500 animate-pulse" />
            <span>Student Learning Hub</span>
          </div>
          <h1 className="text-2xl sm:text-3xl font-extrabold text-slate-900 tracking-tight">
            Welcome back, {studentName || 'Student'} 👋
          </h1>
          <p className="text-sm text-slate-500 mt-1.5 max-w-xl">
            Choose a tutor below to enter their dedicated virtual classroom with isolated routines, progress, and assignments.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2.5 sm:self-center">
          <div className="hidden sm:inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-slate-50 border border-slate-200 text-xs font-semibold text-slate-600">
            <UserCheck className="w-4 h-4 text-emerald-600" />
            <span>{tutors.length} Connected Tutor{tutors.length === 1 ? '' : 's'}</span>
          </div>

          <button
            type="button"
            onClick={onOpenConnectModal}
            className="flex-1 sm:flex-none inline-flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-700 active:scale-[0.98] text-white font-bold text-xs shadow-sm hover:shadow transition-all duration-150"
          >
            <Plus className="w-4 h-4" />
            <span>Connect Tutor</span>
          </button>

          <button
            type="button"
            onClick={onRefresh}
            className="p-2.5 rounded-xl bg-slate-50 hover:bg-slate-100 text-slate-600 hover:text-slate-900 border border-slate-200 transition"
            title="Refresh portal"
            aria-label="Refresh portal"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-indigo-600' : ''}`} />
          </button>
        </div>
      </header>

      {error && (
        <div className="px-4 py-3.5 rounded-2xl bg-rose-50 border border-rose-200 text-rose-700 text-sm flex items-center gap-2.5">
          <AlertCircle className="w-4 h-4 flex-shrink-0 text-rose-500" />
          <span>{error}</span>
        </div>
      )}

      {/* ── Main Tutor Navigation Grid ── */}
      {loading && tutors.length === 0 ? (
        <div className="space-y-4">
          <div className="h-6 w-48 bg-slate-200/70 rounded-lg animate-pulse" />
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {[1, 2, 3].map((i) => (
              <div key={i} className="h-56 rounded-2xl bg-white border border-slate-200/80 p-6 animate-pulse space-y-4 shadow-sm">
                <div className="flex items-center gap-4">
                  <div className="w-14 h-14 rounded-2xl bg-slate-200" />
                  <div className="space-y-2 flex-1">
                    <div className="h-4 bg-slate-200 rounded w-3/4" />
                    <div className="h-3 bg-slate-100 rounded w-1/2" />
                  </div>
                </div>
                <div className="h-6 bg-slate-100 rounded-full w-24" />
                <div className="pt-4 border-t border-slate-100 h-8" />
              </div>
            ))}
          </div>
        </div>
      ) : tutors.length === 0 ? (
        /* Unassigned Onboarding State: student has no connected tutors yet */
        <section className="rounded-2xl bg-white border border-slate-200/80 shadow-sm p-8 text-center max-w-2xl mx-auto space-y-6">
          <div className="w-16 h-16 rounded-2xl bg-indigo-50 border border-indigo-100 flex items-center justify-center text-indigo-600 mx-auto">
            <BookOpen className="w-8 h-8" />
          </div>
          <div>
            <h2 className="text-xl font-bold text-slate-900">No Connected Tutors Yet</h2>
            <p className="text-sm text-slate-500 mt-1.5 max-w-md mx-auto">
              Connect with your private tutor by entering their 6-character invitation code below to enter their classroom.
            </p>
          </div>
          <div className="text-left pt-2">
            <TutorCodeConnect connections={connections} onChanged={onChanged} />
          </div>
        </section>
      ) : (
        /* Connected Tutors Hub Grid: Master View */
        <section className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-base font-bold text-slate-900 flex items-center gap-2">
                <UserCheck className="w-5 h-5 text-indigo-600" />
                <span>My Tutors</span>
              </h2>
              <p className="text-xs text-slate-500 mt-0.5">
                Click any tutor card to launch their virtual classroom workspace.
              </p>
            </div>
            <span className="text-xs font-semibold text-slate-400">
              {tutors.length} Classroom{tutors.length === 1 ? '' : 's'} Available
            </span>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {tutors.map((tutor) => {
              const photoUrl = tutor.profile_picture_url ? getMediaUrl(tutor.profile_picture_url) : null;
              const tuitionCount = tutor.tuitions?.length || 0;
              const subjects = tutor.subjects || [];

              return (
                <div
                  key={tutor.id}
                  onClick={() => onSelectTutor(tutor.id)}
                  role="button"
                  tabIndex={0}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      onSelectTutor(tutor.id);
                    }
                  }}
                  className="group relative overflow-hidden rounded-2xl border border-slate-200/90 bg-white hover:border-indigo-400/90 shadow-sm hover:shadow-md transition-all duration-200 p-6 flex flex-col justify-between cursor-pointer text-left focus:outline-none focus:ring-2 focus:ring-indigo-500"
                >
                  {/* Subtle top indicator bar on hover */}
                  <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-indigo-500 to-indigo-600 opacity-0 group-hover:opacity-100 transition-opacity" />

                  <div className="space-y-4">
                    {/* Top Row: Avatar & Name */}
                    <div className="flex items-start gap-4">
                      {photoUrl ? (
                        <img
                          src={photoUrl}
                          alt={tutor.display_name}
                          className="w-14 h-14 rounded-2xl object-cover border border-slate-200 shadow-xs flex-shrink-0 group-hover:scale-105 transition-transform duration-200"
                        />
                      ) : (
                        <div className="w-14 h-14 rounded-2xl bg-gradient-to-br from-indigo-500 to-indigo-700 flex items-center justify-center text-white text-xl font-black flex-shrink-0 shadow-xs group-hover:scale-105 transition-transform duration-200">
                          {(tutor.display_name || 'T')[0]}
                        </div>
                      )}

                      <div className="min-w-0 flex-1">
                        <div className="flex items-center justify-between gap-1.5">
                          <h3 className="text-lg font-bold text-slate-900 group-hover:text-indigo-600 transition truncate">
                            {tutor.display_name}
                          </h3>
                          <ChevronRight className="w-4 h-4 text-slate-400 group-hover:text-indigo-600 group-hover:translate-x-1 transition-all flex-shrink-0" />
                        </div>
                        <p className="text-xs text-slate-400 font-mono mt-0.5">@{tutor.username}</p>

                        {/* Subject Pills */}
                        {subjects.length > 0 && (
                          <div className="flex flex-wrap gap-1.5 mt-2.5">
                            {subjects.map((sub) => (
                              <span
                                key={sub}
                                className="px-2.5 py-0.5 rounded-full bg-indigo-50 border border-indigo-100 text-indigo-700 text-[11px] font-semibold"
                              >
                                {sub}
                              </span>
                            ))}
                          </div>
                        )}
                      </div>
                    </div>

                    {/* Batch info */}
                    <div className="flex items-center gap-1.5 text-xs text-slate-500 font-medium pt-1">
                      <Layers className="w-3.5 h-3.5 text-slate-400" />
                      <span>{tuitionCount} Tuition Group{tuitionCount === 1 ? '' : 's'}</span>
                    </div>
                  </div>

                  {/* Card Footer: Clear Call To Action */}
                  <div className="pt-4 mt-5 border-t border-slate-100 flex items-center justify-between text-xs">
                    <span className="flex items-center gap-1.5 text-slate-400">
                      <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
                      Virtual Class Active
                    </span>
                    <span className="font-bold text-indigo-600 group-hover:text-indigo-700 flex items-center gap-1 transition-colors">
                      Enter Classroom
                      <ArrowRight className="w-3.5 h-3.5 group-hover:translate-x-1 transition-transform" />
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}
    </div>
  );
}
