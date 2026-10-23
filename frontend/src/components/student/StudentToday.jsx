import React from 'react';
import { Sun, CalendarCheck, FileQuestion, ClipboardList, BookOpen, ArrowRight } from 'lucide-react';
import DeadlineChip, { shortGap } from '../common/DeadlineChip';
import { useNow } from '../../hooks/useNow';

const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/** "Ashraf Sir" from whatever the API sent. */
export function sirName(row) {
  const display = (row?.tutor_display_name || '').trim();
  if (display) return display.endsWith('Sir') ? display : `${display} Sir`;
  const first = (row?.tutor_name || '').trim().split(/\s+/)[0];
  return first ? (first.endsWith('Sir') ? first : `${first} Sir`) : '';
}

/** The next class start across every tuition's weekly routine, within a week. */
export function nextClass(tuitions, now = new Date()) {
  let best = null;
  for (const tuition of tuitions || []) {
    for (const slot of tuition.routine || []) {
      const dayIndex = DAYS.findIndex((d) => d.toLowerCase() === String(slot.day || '').toLowerCase());
      const [h, m] = String(slot.start_time || '').split(':').map(Number);
      if (dayIndex < 0 || Number.isNaN(h)) continue;
      for (let add = 0; add < 8; add += 1) {
        const at = new Date(now);
        at.setDate(now.getDate() + add);
        at.setHours(h, m || 0, 0, 0);
        if (at.getDay() !== dayIndex || at <= now) continue;
        if (!best || at < best.at) best = { at, tuition };
        break;
      }
    }
  }
  return best;
}

const whenLabel = (at, now) => {
  const startOf = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const days = Math.round((startOf(at) - startOf(now)) / 86400000);
  const time = at.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  if (days === 0) return `Today ${time}`;
  if (days === 1) return `Tomorrow ${time}`;
  return `${at.toLocaleDateString(undefined, { weekday: 'short' })} ${time}`;
};

function Row({ icon: Icon, tone, title, subtitle, children }) {
  return (
    <div className="flex items-center gap-3 py-2.5">
      <span className={`w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 ${tone}`}>
        <Icon className="w-5 h-5" />
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-sm font-bold text-slate-900 truncate">{title}</p>
        {subtitle && <p className="text-xs text-slate-500 truncate">{subtitle}</p>}
      </div>
      <div className="flex-shrink-0">{children}</div>
    </div>
  );
}

/**
 * The top of the student portal: the next class, exams open right now (with a
 * Start button) and homework due within a day, across every tutor. Hidden when
 * there is nothing to show.
 */
export default function StudentToday({ tuitions = [], exams = [], homework = [], onTakeExam, onOpenTutor }) {
  const nowMs = useNow(30000);
  const now = new Date(nowMs);
  const next = nextClass(tuitions, now);
  const nextSoon = next && next.at - now < 36 * 3600 * 1000;
  const openExams = exams
    .filter((e) => !e.has_submission && e.can_submit)
    .sort((a, b) => new Date(a.end_time) - new Date(b.end_time))
    .slice(0, 3);
  const dueSoon = homework
    .filter((h) => !h.is_submitted && !h.is_evaluated && !h.submitted_online_url && h.due_date)
    .filter((h) => new Date(h.due_date) - now < 24 * 3600 * 1000)
    .sort((a, b) => new Date(a.due_date) - new Date(b.due_date))
    .slice(0, 3);

  if (!nextSoon && openExams.length === 0 && dueSoon.length === 0) return null;

  return (
    <section
      aria-label="Today"
      className="rounded-2xl border border-indigo-100 bg-gradient-to-br from-indigo-50 via-white to-white shadow-sm p-5 sm:p-6 animate-fadeIn"
    >
      <h2 className="flex items-center gap-2 text-base font-extrabold text-slate-900">
        <Sun className="w-5 h-5 text-amber-500" /> Today
      </h2>
      <div className="mt-2 divide-y divide-slate-100">
        {nextSoon && (
          <Row
            icon={CalendarCheck}
            tone="bg-indigo-100 text-indigo-700"
            title={sirName(next.tuition) ? `Class with ${sirName(next.tuition)}` : 'Next class'}
            subtitle={whenLabel(next.at, now)}
          >
            <span className="px-2.5 py-1 rounded-full bg-indigo-600 text-white text-xs font-bold">
              in {shortGap(next.at - now)}
            </span>
          </Row>
        )}
        {openExams.map((exam) => (
          <Row
            key={exam.id}
            icon={exam.category === 'ASSIGNMENT' ? ClipboardList : FileQuestion}
            tone="bg-emerald-100 text-emerald-700"
            title={exam.title}
            subtitle={sirName(exam)}
          >
            <button
              type="button"
              onClick={() => onTakeExam?.(exam.id)}
              className="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-bold shadow-sm transition"
            >
              {exam.category === 'ASSIGNMENT' ? 'Open' : 'Start'} <ArrowRight className="w-3.5 h-3.5" />
            </button>
          </Row>
        ))}
        {dueSoon.map((hw) => (
          <button
            key={hw.id}
            type="button"
            onClick={() => onOpenTutor?.(hw.tutor_id || hw.tutor)}
            className="w-full text-left rounded-xl hover:bg-slate-50 transition"
          >
            <Row icon={BookOpen} tone="bg-amber-100 text-amber-700" title={hw.title} subtitle={hw.tutor_display_name}>
              <DeadlineChip at={hw.due_date} now={nowMs} />
            </Row>
          </button>
        ))}
      </div>
    </section>
  );
}
