import React, { useState, useEffect } from 'react';
import Modal from './Modal';
import { api } from '../../api/client';
import {
  Trophy,
  Medal,
  Award,
  Crown,
  Users,
  Clock,
  CheckCircle2,
  AlertCircle,
  RefreshCw,
  Sparkles,
} from 'lucide-react';
import StatusBadge from './StatusBadge';

export default function LeaderboardModal({ isOpen, onClose, examId, examTitle }) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const loadLeaderboard = async () => {
    if (!examId) return;
    try {
      setLoading(true);
      setError('');
      const res = await api.getExamLeaderboard(examId);
      setData(res);
    } catch (err) {
      setError(err.message || 'Failed to load leaderboard.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isOpen && examId) {
      loadLeaderboard();
    }
  }, [isOpen, examId]);

  const leaderboard = data?.leaderboard || [];
  const topThree = leaderboard.slice(0, 3);
  const remaining = leaderboard.slice(3);

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={`🏆 Leaderboard & Rankings — ${data?.exam_title || examTitle || 'Exam'}`}
      maxWidth="max-w-4xl"
    >
      <div className="space-y-6">
        {/* Header bar */}
        <div className="flex flex-wrap items-center justify-between gap-3 p-4 rounded-xl bg-gradient-to-r from-slate-900 via-indigo-950/40 to-slate-900 border border-slate-800">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-amber-500/20 text-amber-400 border border-amber-500/30 flex items-center justify-center">
              <Trophy className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="font-bold text-slate-100 text-sm">
                  {data?.exam_title || 'Examination'}
                </h3>
                {data?.batch_name && (
                  <span className="px-2 py-0.5 rounded-full bg-indigo-500/20 text-indigo-300 border border-indigo-500/30 text-[10px] font-semibold">
                    Batch: {data.batch_name}
                  </span>
                )}
                {data?.exam_type && (
                  <span className="px-2 py-0.5 rounded-full bg-slate-800 text-slate-300 text-[10px] font-mono">
                    {data.exam_type}
                  </span>
                )}
              </div>
              <p className="text-xs text-slate-400 mt-0.5">
                Total Marks: <strong className="text-emerald-400">{data?.total_marks}</strong> • Submissions: <strong className="text-indigo-300">{leaderboard.length}</strong>
              </p>
            </div>
          </div>

          <button
            onClick={loadLeaderboard}
            className="p-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-400 hover:text-slate-200 border border-slate-700 transition"
            title="Refresh Leaderboard"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
        </div>

        {error && (
          <div className="p-3.5 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs flex items-center gap-2">
            <AlertCircle className="w-5 h-5 flex-shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {loading ? (
          <div className="space-y-3 py-6">
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              {[1, 2, 3].map((i) => (
                <div key={i} className="h-36 rounded-2xl bg-slate-800/40 animate-pulse" />
              ))}
            </div>
            <div className="h-44 rounded-2xl bg-slate-800/30 animate-pulse mt-4" />
          </div>
        ) : leaderboard.length === 0 ? (
          <div className="text-center py-12 px-4 rounded-xl border border-dashed border-slate-800 text-slate-400">
            <Users className="w-12 h-12 mx-auto text-slate-600 mb-2" />
            <p className="text-sm font-semibold text-slate-300">No submissions recorded yet</p>
            <p className="text-xs text-slate-500 mt-1">
              Once students turn in their answers, ranks and mark breakdowns will be computed dynamically.
            </p>
          </div>
        ) : (
          <div className="space-y-6">
            {/* Top 3 Podium Cards */}
            {topThree.length > 0 && (
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 pt-2">
                {/* 2nd Place */}
                {topThree[1] && (
                  <div className="order-2 sm:order-1 p-4 rounded-2xl bg-gradient-to-b from-slate-800/80 to-slate-900 border border-slate-700/60 relative flex flex-col items-center text-center shadow-lg">
                    <div className="absolute -top-3 w-7 h-7 rounded-full bg-slate-600 text-slate-200 border border-slate-500 flex items-center justify-center font-bold text-xs shadow-md">
                      2
                    </div>
                    <div className="w-12 h-12 rounded-full bg-slate-700 border-2 border-slate-400 flex items-center justify-center text-slate-200 font-bold text-base mt-2 mb-2 shadow-inner">
                      {topThree[1].student_name.slice(0, 2).toUpperCase()}
                    </div>
                    <div className="font-bold text-slate-200 text-sm truncate max-w-full">
                      {topThree[1].student_name}
                    </div>
                    <div className="text-lg font-extrabold text-slate-100 mt-1">
                      {topThree[1].obtained_marks}{' '}
                      <span className="text-xs font-normal text-slate-400">/ {topThree[1].total_marks}</span>
                    </div>
                    <div className="mt-1 px-2.5 py-0.5 rounded-full bg-slate-700/60 text-slate-300 text-xs font-semibold">
                      {topThree[1].percentage}%
                    </div>
                    <div className="text-[11px] text-slate-400 mt-2 font-mono">
                      MCQ: {topThree[1].mcq_score} {topThree[1].cq_score !== null ? `• CQ: ${topThree[1].cq_score}` : ''}
                    </div>
                  </div>
                )}

                {/* 1st Place (Champion) */}
                {topThree[0] && (
                  <div className="order-1 sm:order-2 p-5 rounded-2xl bg-gradient-to-b from-amber-950/40 via-slate-900 to-slate-900 border border-amber-500/50 relative flex flex-col items-center text-center shadow-xl shadow-amber-500/10 transform sm:-translate-y-2">
                    <div className="absolute -top-4 w-9 h-9 rounded-full bg-gradient-to-r from-amber-500 to-yellow-400 text-slate-950 border-2 border-amber-300 flex items-center justify-center font-black text-sm shadow-lg shadow-amber-500/30">
                      <Crown className="w-4 h-4" />
                    </div>
                    <div className="w-14 h-14 rounded-full bg-amber-500/20 border-2 border-amber-400 flex items-center justify-center text-amber-300 font-extrabold text-lg mt-2 mb-2 shadow-lg">
                      {topThree[0].student_name.slice(0, 2).toUpperCase()}
                    </div>
                    <div className="font-extrabold text-slate-100 text-base truncate max-w-full flex items-center gap-1">
                      <span>{topThree[0].student_name}</span>
                      <Sparkles className="w-3.5 h-3.5 text-amber-400" />
                    </div>
                    <div className="text-2xl font-black text-amber-400 mt-1">
                      {topThree[0].obtained_marks}{' '}
                      <span className="text-xs font-normal text-slate-400">/ {topThree[0].total_marks}</span>
                    </div>
                    <div className="mt-1 px-3 py-0.5 rounded-full bg-amber-500/20 border border-amber-500/40 text-amber-300 text-xs font-bold">
                      {topThree[0].percentage}%
                    </div>
                    <div className="text-[11px] text-slate-400 mt-2 font-mono">
                      MCQ: {topThree[0].mcq_score} {topThree[0].cq_score !== null ? `• CQ: ${topThree[0].cq_score}` : ''}
                    </div>
                  </div>
                )}

                {/* 3rd Place */}
                {topThree[2] && (
                  <div className="order-3 p-4 rounded-2xl bg-gradient-to-b from-amber-950/20 to-slate-900 border border-amber-700/40 relative flex flex-col items-center text-center shadow-lg">
                    <div className="absolute -top-3 w-7 h-7 rounded-full bg-amber-700 text-amber-200 border border-amber-600 flex items-center justify-center font-bold text-xs shadow-md">
                      3
                    </div>
                    <div className="w-12 h-12 rounded-full bg-amber-900/40 border-2 border-amber-600 flex items-center justify-center text-amber-300 font-bold text-base mt-2 mb-2 shadow-inner">
                      {topThree[2].student_name.slice(0, 2).toUpperCase()}
                    </div>
                    <div className="font-bold text-slate-200 text-sm truncate max-w-full">
                      {topThree[2].student_name}
                    </div>
                    <div className="text-lg font-extrabold text-slate-100 mt-1">
                      {topThree[2].obtained_marks}{' '}
                      <span className="text-xs font-normal text-slate-400">/ {topThree[2].total_marks}</span>
                    </div>
                    <div className="mt-1 px-2.5 py-0.5 rounded-full bg-amber-900/40 text-amber-300 text-xs font-semibold">
                      {topThree[2].percentage}%
                    </div>
                    <div className="text-[11px] text-slate-400 mt-2 font-mono">
                      MCQ: {topThree[2].mcq_score} {topThree[2].cq_score !== null ? `• CQ: ${topThree[2].cq_score}` : ''}
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* Complete Table View */}
            <div className="rounded-xl border border-slate-800 overflow-hidden bg-slate-900/50">
              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs border-collapse">
                  <thead>
                    <tr className="bg-slate-800/80 border-b border-slate-800 font-bold text-slate-400 uppercase tracking-wider text-[11px]">
                      <th className="py-3 px-4">Rank</th>
                      <th className="py-3 px-4">Student</th>
                      <th className="py-3 px-4">Marks Obtained</th>
                      <th className="py-3 px-4">Percentage</th>
                      <th className="py-3 px-4">Breakdown</th>
                      <th className="py-3 px-4">Submitted</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/60 font-medium">
                    {leaderboard.map((entry) => (
                      <tr
                        key={entry.student_id}
                        className={`hover:bg-slate-800/30 transition ${
                          entry.rank === 1
                            ? 'bg-amber-500/5'
                            : entry.rank === 2
                            ? 'bg-slate-700/10'
                            : entry.rank === 3
                            ? 'bg-amber-900/10'
                            : ''
                        }`}
                      >
                        <td className="py-3 px-4 font-mono font-bold text-slate-300">
                          {entry.rank === 1 ? (
                            <span className="flex items-center gap-1 text-amber-400 font-bold">
                              <Crown className="w-3.5 h-3.5" /> #1
                            </span>
                          ) : entry.rank === 2 ? (
                            <span className="text-slate-300">#2</span>
                          ) : entry.rank === 3 ? (
                            <span className="text-amber-500">#3</span>
                          ) : (
                            `#${entry.rank}`
                          )}
                        </td>
                        <td className="py-3 px-4 text-slate-200 font-semibold">
                          {entry.student_name}
                        </td>
                        <td className="py-3 px-4 font-bold text-emerald-400 text-sm">
                          {entry.obtained_marks} / {entry.total_marks}
                        </td>
                        <td className="py-3 px-4">
                          <span
                            className={`px-2 py-0.5 rounded-full font-bold text-[11px] ${
                              entry.percentage >= 80
                                ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                                : entry.percentage >= 50
                                ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                                : 'bg-rose-500/20 text-rose-300 border border-rose-500/30'
                            }`}
                          >
                            {entry.percentage}%
                          </span>
                        </td>
                        <td className="py-3 px-4 text-slate-300 font-mono text-[11px]">
                          <span className="text-indigo-400">MCQ: {entry.mcq_score}</span>
                          {entry.cq_score !== null && (
                            <span className="text-emerald-400 ml-2">CQ: {entry.cq_score}</span>
                          )}
                        </td>
                        <td className="py-3 px-4 text-slate-400 text-[11px]">
                          {new Date(entry.submitted_at).toLocaleTimeString([], {
                            hour: '2-digit',
                            minute: '2-digit',
                          })}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )}

        <div className="pt-3 flex justify-end border-t border-slate-800">
          <button
            onClick={onClose}
            className="px-5 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-semibold transition"
          >
            Close Leaderboard
          </button>
        </div>
      </div>
    </Modal>
  );
}
