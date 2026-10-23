import React from 'react';
import { AlarmClock, Clock, AlertCircle } from 'lucide-react';

/** "25 min", "3 h", "2 d". */
export function shortGap(ms) {
  const mins = Math.max(0, Math.floor(ms / 60000));
  if (mins < 1) return '<1 min';
  if (mins < 60) return `${mins} min`;
  const hours = Math.floor(mins / 60);
  if (hours < 48) return `${hours} h`;
  return `${Math.floor(hours / 24)} d`;
}

/**
 * "Due in 3 h", "Closes in 25 min", "Opens in 2 d", "Late" — red with less
 * than two hours to go. kind: 'due' | 'closes' | 'opens'.
 */
export default function DeadlineChip({ at, now = Date.now(), kind = 'due' }) {
  const target = new Date(at).getTime();
  const left = target - now;
  const base = 'inline-flex items-center gap-1 px-2 py-0.5 rounded-full border text-[11px] font-semibold';
  if (kind !== 'opens' && left < 0) {
    return (
      <span className={`${base} bg-rose-50 text-rose-700 border-rose-200`}>
        <AlertCircle className="w-3 h-3" /> Late
      </span>
    );
  }
  const urgent = kind !== 'opens' && left < 2 * 3600 * 1000;
  const verb = kind === 'opens' ? 'Opens' : kind === 'closes' ? 'Closes' : 'Due';
  const tone = urgent
    ? 'bg-rose-50 text-rose-700 border-rose-200'
    : kind === 'opens'
      ? 'bg-indigo-50 text-indigo-700 border-indigo-200'
      : 'bg-emerald-50 text-emerald-700 border-emerald-200';
  const Icon = urgent ? AlarmClock : Clock;
  return (
    <span className={`${base} ${tone}`}>
      <Icon className="w-3 h-3" /> {verb} in {shortGap(left)}
    </span>
  );
}
