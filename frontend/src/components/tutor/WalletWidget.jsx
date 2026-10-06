import React from 'react';
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from 'recharts';
import { Users, DollarSign, Clock, Award } from 'lucide-react';

const COLORS = {
  Earned: '#10B981',   // Emerald
  Pending: '#6366F1',  // Indigo
};

const COLORS_LOWER = {
  earned: '#10B981',
  pending: '#6366F1',
};

export default function WalletWidget({ analytics, loading }) {
  if (loading) {
    return (
      <div className="glass-panel p-6 rounded-2xl animate-pulse flex flex-col items-center justify-center min-h-[300px]">
        <div className="w-12 h-12 rounded-full border-4 border-indigo-500/30 border-t-indigo-500 animate-spin mb-4" />
        <span className="text-sm text-slate-400">Computing real-time tuition wallet...</span>
      </div>
    );
  }

  if (!analytics) return null;

  const {
    total_students: _totalStudents = 0,
    total_earned: _totalEarned = 0,
    total_pending: _totalPending = 0,
    lifetime_archived_earnings: _lifetime = 0,
    chart_data = [],
  } = analytics;

  const total_students = _totalStudents ?? 0;
  const total_earned = _totalEarned ?? 0;
  const total_pending = _totalPending ?? 0;
  const lifetime_archived_earnings = _lifetime ?? 0;

  const totalCycleVolume = total_earned + total_pending;
  const earnedPercentage = totalCycleVolume > 0 ? Math.round((total_earned / totalCycleVolume) * 100) : 0;

  return (
    <div className="glass-panel p-6 rounded-2xl">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
        <div>
          <h2 className="text-xl font-bold text-slate-100 flex items-center gap-2">
            <DollarSign className="w-6 h-6 text-emerald-400" />
            Tuition Wallet & Revenue
          </h2>
          <p className="text-xs text-slate-400 mt-0.5">
            Real-time dynamic breakdown across all active student billing cycles
          </p>
        </div>

        <div className="flex items-center gap-2 px-3 py-1.5 rounded-xl bg-slate-800/80 border border-slate-700/80 text-xs">
          <Award className="w-4 h-4 text-amber-400" />
          <span className="text-slate-400">Lifetime Revenue:</span>
          <span className="font-bold text-amber-300">
            ৳{Number(lifetime_archived_earnings ?? 0).toLocaleString()}
          </span>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-center">
        {/* Left: Recharts Donut Chart */}
        <div className="lg:col-span-5 flex flex-col items-center justify-center relative min-h-[220px]">
          <ResponsiveContainer width="100%" height={220}>
            <PieChart>
              <Pie
                data={chart_data}
                cx="50%"
                cy="50%"
                innerRadius={65}
                outerRadius={90}
                paddingAngle={4}
                dataKey="value"
                stroke="none"
              >
                {chart_data.map((entry, index) => (
                  <Cell
                    key={`cell-${index}`}
                    fill={COLORS_LOWER[(entry.name || '').toLowerCase()] || COLORS[entry.name] || '#64748b'}
                  />
                ))}
              </Pie>
              <Tooltip
                content={({ active, payload }) => {
                  if (active && payload && payload.length) {
                    const data = payload[0];
                    return (
                      <div className="bg-slate-900 border border-slate-700 px-3 py-2 rounded-xl shadow-xl text-xs">
                        <span className="font-semibold text-slate-300">{data.name}: </span>
                        <span className="font-bold text-slate-100">৳{Number(data.value).toLocaleString()}</span>
                      </div>
                    );
                  }
                  return null;
                }}
              />
            </PieChart>
          </ResponsiveContainer>

          {/* Center text overlay */}
          <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
            <span className="text-3xl font-extrabold text-white tracking-tight">
              {earnedPercentage}%
            </span>
            <span className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider">
              Earned
            </span>
          </div>
        </div>

        {/* Right: Metrics Grid */}
        <div className="lg:col-span-7 grid grid-cols-1 sm:grid-cols-3 gap-4">
          {/* Card 1: Active Students */}
          <div className="p-4 rounded-xl bg-slate-800/40 border border-slate-700/60 flex flex-col justify-between">
            <div className="flex items-center justify-between text-slate-400 mb-2">
              <span className="text-xs font-semibold uppercase tracking-wider">Active Students</span>
              <Users className="w-4 h-4 text-slate-400" />
            </div>
            <div className="text-2xl font-bold text-slate-100">{total_students}</div>
            <div className="text-[11px] text-slate-500 mt-1">Under your tutoring</div>
          </div>

          {/* Card 2: Earned Revenue */}
          <div className="p-4 rounded-xl bg-emerald-950/20 border border-emerald-500/20 flex flex-col justify-between">
            <div className="flex items-center justify-between text-emerald-400 mb-2">
              <span className="text-xs font-semibold uppercase tracking-wider">Earned</span>
              <DollarSign className="w-4 h-4 text-emerald-400" />
            </div>
            <div className="text-2xl font-bold text-emerald-400">
              ৳{Number(total_earned ?? 0).toLocaleString()}
            </div>
            <div className="text-[11px] text-emerald-500/80 mt-1">Completed classes</div>
          </div>

          {/* Card 3: Pending Balance */}
          <div className="p-4 rounded-xl bg-indigo-950/20 border border-indigo-500/20 flex flex-col justify-between">
            <div className="flex items-center justify-between text-indigo-400 mb-2">
              <span className="text-xs font-semibold uppercase tracking-wider">Pending</span>
              <Clock className="w-4 h-4 text-indigo-400" />
            </div>
            <div className="text-2xl font-bold text-indigo-300">
              ৳{Number(total_pending ?? 0).toLocaleString()}
            </div>
            <div className="text-[11px] text-indigo-400/80 mt-1">Remaining classes</div>
          </div>
        </div>
      </div>
    </div>
  );
}
