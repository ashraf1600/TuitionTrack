import React from 'react';
import {
  Layers, Plus, Users, Calendar, Wallet, ChevronRight,
  Sparkles, RefreshCw, Check, ArrowRight, BookOpen, AlertCircle
} from 'lucide-react';
import { formatTaka } from '../../utils/dates';
import { notify } from '../../utils/toast';

/**
 * Screen 1: The "Tuition Batches Hub" (Master View)
 *
 * Minimalist, high-focus navigation hub for tutors.
 * Displays ONLY the Grid of Tuition/Batch Cards.
 * Each card displays:
 *  - Active students count
 *  - Current cycle status ("Cycle 3: 5/12 Classes Done" + mini progress bar)
 *  - Subtle Wallet snippet (earned / pending revenue)
 * Prominent Floating Action Button (FAB) to "+ Create New Tuition".
 */
export default function TuitionBatchesHub({
  tutorName,
  tutorCode,
  tuitions = [],
  analytics = null,
  loading = false,
  error = '',
  onSelectTuition,
  onCreateTuition,
  onRefresh,
}) {
  // Pre-index tuition breakdowns from analytics for instant lookup
  const walletMap = React.useMemo(() => {
    const map = new Map();
    (analytics?.tuition_breakdowns || []).forEach((b) => {
      map.set(String(b.tuition_id), b);
    });
    return map;
  }, [analytics]);

  return (
    <div className="space-y-8 animate-fadeIn relative pb-20">
      {/* ── Minimal Welcome Header ── */}
      <header className="rounded-2xl bg-white border border-slate-200/80 shadow-sm p-6 sm:p-8 flex flex-col md:flex-row md:items-center justify-between gap-6">
        <div>
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-semibold bg-indigo-50 text-indigo-700 border border-indigo-100 mb-3">
            <Sparkles className="w-3.5 h-3.5 text-indigo-500 animate-pulse" />
            <span>Tutor Management Hub</span>
          </div>
          <h1 className="text-2xl sm:text-3xl font-extrabold text-slate-900 tracking-tight">
            Welcome back, {tutorName || 'Tutor'} 👋
          </h1>
          <p className="text-sm text-slate-500 mt-1 max-w-xl">
            Select a tuition batch to manage its isolated class tracker, student roster, assessments, and schedule.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-3">
          {/* Subtle Invite Code Pill */}
          {tutorCode && (
            <div className="flex items-center gap-2 px-3.5 py-2 rounded-xl bg-slate-50 border border-slate-200 text-xs">
              <span className="font-medium text-slate-500">Tutor Code:</span>
              <span className="font-mono font-bold text-slate-900 tracking-wider select-all">{tutorCode}</span>
              <button
                type="button"
                onClick={() => {
                  navigator.clipboard.writeText(tutorCode);
                  notify.success(`Invite code "${tutorCode}" copied!`);
                }}
                className="p-1 rounded-lg text-slate-400 hover:text-indigo-600 hover:bg-slate-200/60 transition"
                title="Copy Invite Code"
              >
                <Check className="w-3.5 h-3.5" />
              </button>
            </div>
          )}

          <button
            type="button"
            onClick={onRefresh}
            className="p-2.5 rounded-xl bg-slate-50 hover:bg-slate-100 text-slate-600 hover:text-slate-900 border border-slate-200 transition"
            title="Refresh Batches"
            aria-label="Refresh Batches"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-indigo-600' : ''}`} />
          </button>

          <button
            type="button"
            onClick={onCreateTuition}
            className="inline-flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-700 active:scale-[0.98] text-white font-bold text-xs shadow-sm hover:shadow transition-all"
          >
            <Plus className="w-4 h-4" />
            <span>New Tuition</span>
          </button>
        </div>
      </header>

      {error && (
        <div className="px-4 py-3.5 rounded-2xl bg-rose-50 border border-rose-200 text-rose-700 text-sm flex items-center gap-2.5">
          <AlertCircle className="w-4 h-4 flex-shrink-0 text-rose-500" />
          <span>{error}</span>
        </div>
      )}

      {/* ── Main Batches Grid ── */}
      {loading && tuitions.length === 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-64 rounded-2xl bg-white border border-slate-200/80 p-6 animate-pulse space-y-4 shadow-sm" />
          ))}
        </div>
      ) : tuitions.length === 0 ? (
        /* Empty State */
        <section className="rounded-2xl bg-white border border-dashed border-slate-300 p-12 text-center max-w-xl mx-auto space-y-5 shadow-xs">
          <div className="w-16 h-16 rounded-2xl bg-indigo-50 border border-indigo-100 flex items-center justify-center text-indigo-600 mx-auto">
            <Layers className="w-8 h-8" />
          </div>
          <div>
            <h2 className="text-xl font-bold text-slate-900">No Tuition Batches Yet</h2>
            <p className="text-sm text-slate-500 mt-1.5 max-w-sm mx-auto">
              Create your first tuition group to organize students, start tracking classes, and manage earnings.
            </p>
          </div>
          <button
            type="button"
            onClick={onCreateTuition}
            className="inline-flex items-center gap-2 px-5 py-3 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-xs shadow-sm hover:shadow transition-all"
          >
            <Plus className="w-4 h-4" />
            <span>Create New Tuition</span>
          </button>
        </section>
      ) : (
        /* Grid of Tuition/Batch Cards */
        <section className="space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-base font-bold text-slate-900 flex items-center gap-2">
                <Layers className="w-5 h-5 text-indigo-600" />
                <span>My Tuition Batches</span>
              </h2>
              <p className="text-xs text-slate-500 mt-0.5">
                Click any batch to enter its isolated workspace and manage students, tracker, and tasks.
              </p>
            </div>
            <span className="text-xs font-semibold text-slate-400">
              {tuitions.length} Active Group{tuitions.length === 1 ? '' : 's'}
            </span>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {tuitions.map((tuition) => {
              const activeCycle = tuition.active_cycle;
              const totalClasses = Number(activeCycle?.total_classes || tuition.cycle_length || 12);
              const completedClasses = Number(
                activeCycle?.completed_count ??
                activeCycle?.classes_data?.filter((c) => c.completed)?.length ??
                0
              );
              const cycleNum = activeCycle?.cycle_number || 1;
              const percent = totalClasses > 0 ? Math.min(100, Math.round((completedClasses / totalClasses) * 100)) : 0;

              // Enrolled count
              const studentCount =
                tuition.enrolled_count ??
                tuition.enrollments?.length ??
                tuition.student_count ??
                0;

              // Batch Wallet Snippet
              const batchWallet = walletMap.get(String(tuition.id)) || tuition.wallet_summary || {};
              const earnedRevenue = batchWallet.earned ?? batchWallet.earned_revenue ?? 0;
              const pendingRevenue = batchWallet.pending ?? batchWallet.pending_balance ?? 0;

              return (
                <div
                  key={tuition.id}
                  onClick={() => onSelectTuition(tuition.id)}
                  role="button"
                  tabIndex={0}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      onSelectTuition(tuition.id);
                    }
                  }}
                  className="group relative overflow-hidden rounded-2xl border border-slate-200/90 bg-white hover:border-indigo-400/90 shadow-sm hover:shadow-md transition-all duration-200 p-6 flex flex-col justify-between cursor-pointer text-left focus:outline-none focus:ring-2 focus:ring-indigo-500"
                >
                  {/* Subtle top indicator bar */}
                  <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-indigo-500 to-indigo-600 opacity-0 group-hover:opacity-100 transition-opacity" />

                  <div className="space-y-4">
                    {/* Header: Title & Subject */}
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2 mb-1">
                          {tuition.subject && (
                            <span className="px-2.5 py-0.5 rounded-full bg-indigo-50 border border-indigo-100 text-indigo-700 text-[10px] font-bold uppercase tracking-wider">
                              {tuition.subject}
                            </span>
                          )}
                        </div>
                        <h3 className="text-lg font-bold text-slate-900 group-hover:text-indigo-600 transition truncate">
                          {tuition.title || tuition.name}
                        </h3>
                      </div>
                      <ChevronRight className="w-5 h-5 text-slate-300 group-hover:text-indigo-600 group-hover:translate-x-1 transition-all flex-shrink-0" />
                    </div>

                    {/* Insight 1: Active Students Count */}
                    <div className="flex items-center gap-2 text-xs text-slate-600 font-medium">
                      <Users className="w-4 h-4 text-indigo-500 flex-shrink-0" />
                      <span>{studentCount} Active Student{studentCount === 1 ? '' : 's'}</span>
                    </div>

                    {/* Insight 2: Current Cycle Status with Progress Bar */}
                    <div className="space-y-1.5 pt-1">
                      <div className="flex items-center justify-between text-xs">
                        <span className="font-semibold text-slate-700 flex items-center gap-1.5">
                          <Calendar className="w-3.5 h-3.5 text-slate-400" />
                          <span>Cycle {cycleNum}: {completedClasses}/{totalClasses} Done</span>
                        </span>
                        <span className="font-mono text-slate-500 text-[11px]">{percent}%</span>
                      </div>
                      <div className="w-full h-2 bg-slate-100 rounded-full overflow-hidden border border-slate-200/50">
                        <div
                          className="h-full bg-gradient-to-r from-indigo-500 to-emerald-500 rounded-full transition-all duration-300"
                          style={{ width: `${percent}%` }}
                        />
                      </div>
                    </div>

                    {/* Insight 3: Subtle Wallet Snippet */}
                    <div className="pt-3 border-t border-slate-100 flex items-center justify-between text-xs">
                      <div className="flex items-center gap-1.5">
                        <Wallet className="w-3.5 h-3.5 text-emerald-600" />
                        <span className="font-mono font-bold text-emerald-700">
                          {formatTaka(earnedRevenue)}
                        </span>
                        <span className="text-[10px] text-slate-400">earned</span>
                      </div>
                      {pendingRevenue > 0 && (
                        <span className="text-[11px] font-mono text-slate-400">
                          {formatTaka(pendingRevenue)} pending
                        </span>
                      )}
                    </div>
                  </div>

                  {/* Card Footer: Action */}
                  <div className="pt-4 mt-4 border-t border-slate-100 flex items-center justify-between text-xs">
                    <span className="text-slate-400 text-[11px]">Isolated workspace</span>
                    <span className="font-bold text-indigo-600 group-hover:text-indigo-700 flex items-center gap-1 transition-colors">
                      Manage Batch
                      <ArrowRight className="w-3.5 h-3.5 group-hover:translate-x-1 transition-transform" />
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </section>
      )}

      {/* ── Floating Action Button (FAB) ── */}
      <div className="fixed bottom-6 right-6 sm:bottom-8 sm:right-8 z-30">
        <button
          type="button"
          onClick={onCreateTuition}
          className="flex items-center gap-2.5 px-5 py-3.5 rounded-full bg-indigo-600 hover:bg-indigo-700 active:scale-95 text-white font-bold text-sm shadow-lg shadow-indigo-600/35 hover:shadow-xl hover:shadow-indigo-600/40 transition-all duration-200 group"
          aria-label="Create New Tuition Batch"
        >
          <Plus className="w-5 h-5 group-hover:rotate-90 transition-transform duration-200" />
          <span className="hidden sm:inline">Create New Tuition</span>
          <span className="sm:hidden">New Batch</span>
        </button>
      </div>
    </div>
  );
}
