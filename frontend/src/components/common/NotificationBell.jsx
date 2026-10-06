import React, { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Bell, UserPlus, ClipboardCheck, RotateCcw, FileText, Clock, Trophy, AlertTriangle, Link2 } from 'lucide-react';
import { api } from '../../api/client';
import { useAuth } from '../../context/AuthContext';

const ICONS = {
  request: UserPlus,
  grade: ClipboardCheck,
  cycle: RotateCcw,
  open: FileText,
  soon: Clock,
  late: AlertTriangle,
  result: Trophy,
  connection: Link2,
};

const POLL_MS = 60000;

function formatWhen(value) {
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleString(undefined, { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
}

/**
 * The bell in the navbar. The server works notifications out from the current
 * state (requests waiting, work to grade, exams opening…), each with a stable
 * id. Which ones this user has already seen is remembered in this browser.
 * All times are shown in the viewer's own timezone.
 */
export default function NotificationBell() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [items, setItems] = useState([]);
  const [open, setOpen] = useState(false);
  const [seen, setSeen] = useState(() => new Set());
  const boxRef = useRef(null);
  const storageKey = `notifications_seen_${user?.id || 'anon'}`;

  useEffect(() => {
    try {
      setSeen(new Set(JSON.parse(localStorage.getItem(storageKey) || '[]')));
    } catch {
      setSeen(new Set());
    }
  }, [storageKey]);

  const load = useCallback(async () => {
    try {
      const data = await api.getNotifications();
      setItems(data.notifications || []);
    } catch {
      // The bell is a convenience; a failed poll should never disturb the page.
    }
  }, []);

  useEffect(() => {
    load();
    const id = setInterval(load, POLL_MS);
    const onFocus = () => load();
    window.addEventListener('focus', onFocus);
    return () => {
      clearInterval(id);
      window.removeEventListener('focus', onFocus);
    };
  }, [load]);

  // Close on outside click / Escape
  useEffect(() => {
    if (!open) return undefined;
    const onDown = (e) => {
      if (boxRef.current && !boxRef.current.contains(e.target)) setOpen(false);
    };
    const onKey = (e) => e.key === 'Escape' && setOpen(false);
    document.addEventListener('mousedown', onDown);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  const unseen = items.filter((n) => !seen.has(n.id)).length;

  const toggle = () => {
    const next = !open;
    setOpen(next);
    if (next && items.length) {
      // Opening the list counts as having seen what is in it. Only current ids are kept.
      const ids = items.map((n) => n.id);
      setSeen(new Set(ids));
      try {
        localStorage.setItem(storageKey, JSON.stringify(ids));
      } catch {
        // storage full / blocked: the badge just reappears next time
      }
    }
  };

  const go = (n) => {
    setOpen(false);
    if (n.link) navigate(n.link);
  };

  return (
    <div className="relative" ref={boxRef}>
      <button
        type="button"
        onClick={toggle}
        aria-label={unseen ? `Notifications, ${unseen} new` : 'Notifications'}
        aria-expanded={open}
        className="relative p-2.5 rounded-xl text-slate-300 hover:text-white hover:bg-slate-800 border border-slate-800 transition"
      >
        <Bell className="w-4 h-4" />
        {unseen > 0 && (
          <span className="absolute -top-1 -right-1 min-w-[18px] h-[18px] px-1 rounded-full bg-rose-500 text-white text-[10px] font-bold flex items-center justify-center">
            {unseen > 9 ? '9+' : unseen}
          </span>
        )}
      </button>

      {open && (
        <div className="absolute right-0 mt-2 w-[min(22rem,calc(100vw-2rem))] rounded-2xl border border-slate-700 bg-slate-900 shadow-2xl shadow-black/50 overflow-hidden z-50">
          <div className="px-4 py-3 border-b border-slate-800 text-sm font-bold text-slate-100">Notifications</div>
          {items.length === 0 ? (
            <p className="px-4 py-8 text-sm text-slate-400 text-center">You are all caught up.</p>
          ) : (
            <ul className="max-h-96 overflow-y-auto divide-y divide-slate-800">
              {items.map((n) => {
                const Icon = ICONS[n.kind] || Bell;
                // For exam items `body` is a verb ("closes", "opens") that reads with the time.
                const timed = ['open', 'soon', 'late'].includes(n.kind);
                return (
                  <li key={n.id}>
                    <button
                      type="button"
                      onClick={() => go(n)}
                      className="w-full text-left px-4 py-3 flex gap-3 hover:bg-slate-800/70 transition"
                    >
                      <span className="w-8 h-8 rounded-lg bg-indigo-500/15 text-indigo-300 flex items-center justify-center flex-shrink-0">
                        <Icon className="w-4 h-4" />
                      </span>
                      <span className="min-w-0">
                        <span className="block text-sm font-semibold text-slate-100">{n.title}</span>
                        <span className="block text-xs text-slate-400 truncate">
                          {timed ? `${n.body} ${formatWhen(n.when)}` : [n.body, formatWhen(n.when)].filter(Boolean).join(' · ')}
                        </span>
                      </span>
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
