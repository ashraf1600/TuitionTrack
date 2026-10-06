import React from 'react';
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts';
import { Users, Wallet, Clock, Award, Layers, ChevronRight } from 'lucide-react';
import { formatTaka } from '../../utils/dates';

const COLORS = { earned: '#10B981', pending: '#6366F1' };

/**
 * Tutor-only Tuition Wallet.
 * Each tuition group earns (total fee ÷ classes in the cycle) for every class
 * the tutor marks complete; this adds those up across all groups.
 */
export default function WalletWidget({ analytics, loading, onOpenTuition }) {
  if (loading) {
    return <div className="rounded-2xl border border-slate-800 bg-slate-900/70 min-h-[260px] animate-pulse" />;
  }
  if (!analytics) return null;

  const totalStudents = analytics.total_students ?? 0;
  const totalTuitions = analytics.total_tuitions ?? (analytics.tuition_breakdowns || []).length;
  const earned = analytics.total_earned ?? 0;
  const pending = analytics.total_pending ?? 0;
  const lifetime = (analytics.lifetime_archived_earnings ?? 0) + earned;
  const chartData = analytics.chart_data || [];
  const groups = analytics.tuition_breakdowns || [];
  const legacy = analytics.student_breakdowns || [];

  const volume = earned + pending;
  const earnedPct = volume > 0 ? Math.round((earned / volume) * 100) : 0;

  return (
    <section className="rounded-2xl border border-slate-800 bg-slate-900/70 shadow-lg overflow-hidden">
      <div className="p-5 sm:p-6 flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-slate-800">
        <div>
          <h2 className="text-xl font-bold text-slate-100 flex items-center gap-2">
            <Wallet className="w-5 h-5 text-emerald-400" />
            Tuition Wallet
          </h2>
          <p className="text-xs text-slate-400 mt-0.5">
            Every class you mark complete adds <span className="text-slate-300">cycle fee ÷ classes in the cycle</span> for that group.
          </p>
        </div>
        <div className="flex items-center gap-2 px-3.5 py-2 rounded-xl bg-amber-500/10 border border-amber-500/25 text-xs">
          <Award className="w-4 h-4 text-amber-400" />
          <span className="text-slate-300">Lifetime earned</span>
          <span className="font-extrabold text-amber-300 font-mono">{formatTaka(lifetime)}</span>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12">
        {/* Donut */}
        <div className="lg:col-span-4 relative flex items-center justify-center p-4 lg:border-r border-slate-800 min-h-[220px]">
          <ResponsiveContainer width="100%" height={200}>
            <PieChart>
              <Pie
                data={volume > 0 ? chartData : [{ name: 'empty', value: 1 }]}
                cx="50%"
                cy="50%"
                innerRadius={62}
                outerRadius={84}
                paddingAngle={volume > 0 ? 4 : 0}
                dataKey="value"
                stroke="none"
              >
                {(volume > 0 ? chartData : [{ name: 'empty' }]).map((entry, index) => (
                  <Cell key={index} fill={COLORS[(entry.name || '').toLowerCase()] || '#1e293b'} />
                ))}
              </Pie>
              {volume > 0 && (
                <Tooltip
                  content={({ active, payload }) =>
                    active && payload?.length ? (
                      <div className="bg-slate-900 border border-slate-700 px-3 py-2 rounded-xl shadow-xl text-xs">
                        <span className="font-semibold text-slate-300">{payload[0].name}: </span>
                        <span className="font-bold text-slate-100">{formatTaka(payload[0].value)}</span>
                      </div>
                    ) : null
                  }
                />
              )}
            </PieChart>
          </ResponsiveContainer>
          <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
            <span className="text-3xl font-extrabold text-white">{earnedPct}%</span>
            <span className="text-[10px] font-semibold text-slate-400 uppercase tracking-wider">of current cycles</span>
          </div>
        </div>

        {/* Numbers + per-group breakdown */}
        <div className="lg:col-span-8 p-5 sm:p-6 space-y-5">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <Metric icon={Wallet} label="Earned" value={formatTaka(earned)} hint="current cycles" tone="emerald" />
            <Metric icon={Clock} label="Still to earn" value={formatTaka(pending)} hint="remaining classes" tone="indigo" />
            <Metric icon={Layers} label="Tuition groups" value={totalTuitions} hint="active" />
            <Metric icon={Users} label="Students" value={totalStudents} hint="in your groups" />
          </div>

          {groups.length > 0 && (
            <div>
              <div className="text-[10px] font-bold uppercase tracking-wider text-slate-500 mb-2">By tuition group</div>
              <ul className="space-y-2">
                {groups.map((g) => (
                  <li key={g.cycle_id}>
                    <button
                      type="button"
                      onClick={() => onOpenTuition?.(g.tuition_id)}
                      className="w-full text-left rounded-xl bg-slate-800/40 hover:bg-slate-800 border border-slate-700/60 px-4 py-3 transition group"
                    >
                      <div className="flex items-center justify-between gap-3">
                        <div className="min-w-0">
                          <div className="text-sm font-semibold text-slate-100 truncate">{g.tuition_title}</div>
                          <div className="text-[11px] text-slate-400">
                            Cycle #{g.cycle_number} · {g.completed_classes}/{g.total_classes} classes · {g.student_count} student{g.student_count === 1 ? '' : 's'}
                          </div>
                        </div>
                        <div className="flex items-center gap-3 flex-shrink-0">
                          <div className="text-right">
                            <div className="text-sm font-bold text-emerald-400 font-mono">{formatTaka(g.earned)}</div>
                            <div className="text-[11px] text-slate-500 font-mono">of {formatTaka(g.total_fee)}</div>
                          </div>
                          <ChevronRight className="w-4 h-4 text-slate-600 group-hover:text-slate-300 transition" />
                        </div>
                      </div>
                      <div className="mt-2 h-1.5 rounded-full bg-slate-700/60 overflow-hidden">
                        <div className="h-full bg-emerald-500 transition-all duration-500" style={{ width: `${Math.min(100, g.progress_percentage)}%` }} />
                      </div>
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {legacy.length > 0 && (
            <p className="text-[11px] text-slate-500">
              Includes {legacy.length} older one-to-one cycle{legacy.length === 1 ? '' : 's'} created before tuition groups.
            </p>
          )}

          {groups.length === 0 && legacy.length === 0 && (
            <p className="text-xs text-slate-400">Create a tuition group and mark its first class to start filling your wallet.</p>
          )}
        </div>
      </div>
    </section>
  );
}

function Metric({ icon: Icon, label, value, hint, tone }) {
  const color = tone === 'emerald' ? 'text-emerald-400' : tone === 'indigo' ? 'text-indigo-300' : 'text-slate-100';
  return (
    <div className="rounded-xl bg-slate-800/40 border border-slate-700/60 p-3.5">
      <div className="flex items-center justify-between text-slate-400">
        <span className="text-[10px] font-bold uppercase tracking-wider">{label}</span>
        <Icon className="w-3.5 h-3.5" />
      </div>
      <div className={`text-xl font-extrabold mt-1 font-mono ${color}`}>{value}</div>
      <div className="text-[10px] text-slate-500">{hint}</div>
    </div>
  );
}
