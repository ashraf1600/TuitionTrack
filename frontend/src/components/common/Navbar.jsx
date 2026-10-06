import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../../context/AuthContext';
import { GraduationCap, LogOut } from 'lucide-react';
import NotificationBell from './NotificationBell';
import AccountModal from './AccountModal';

export default function Navbar() {
  const { user, logout, isTutor } = useAuth();
  const displayName = user?.name || user?.username || '';
  const home = isTutor ? '/tutor' : '/student';
  const [accountOpen, setAccountOpen] = useState(false);

  return (
    <>
    <header className="sticky top-0 z-40 w-full border-b border-slate-800 bg-slate-950/85 backdrop-blur-md">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between gap-4">
        <Link to={user ? home : '/login'} className="flex items-center gap-2.5 rounded-lg" aria-label="TuitionTrack home">
          <span className="w-9 h-9 rounded-xl bg-indigo-600 flex items-center justify-center text-white">
            <GraduationCap className="w-5 h-5" />
          </span>
          <span className="text-lg font-bold tracking-tight text-slate-100">
            Tuition<span className="text-indigo-400">Track</span>
          </span>
        </Link>

        {user && (
          <div className="flex items-center gap-2 sm:gap-3">
            <NotificationBell />
            <button
              type="button"
              onClick={() => setAccountOpen(true)}
              title="My account"
              className="flex items-center gap-2.5 rounded-xl px-1.5 py-1 hover:bg-slate-800 transition text-left"
            >
              <span
                className={`w-9 h-9 rounded-full flex items-center justify-center text-sm font-bold ${
                  isTutor ? 'bg-indigo-500/20 text-indigo-300' : 'bg-emerald-500/20 text-emerald-300'
                }`}
                aria-hidden="true"
              >
                {displayName.charAt(0).toUpperCase()}
              </span>
              <span className="hidden sm:flex flex-col leading-tight">
                <span className="text-sm font-semibold text-slate-100 max-w-[180px] truncate">{displayName}</span>
                <span className="text-xs text-slate-400">{isTutor ? 'Tutor' : 'Student'} · My account</span>
              </span>
            </button>

            <button
              type="button"
              onClick={logout}
              className="flex items-center gap-1.5 px-3 py-2 rounded-xl text-sm font-medium text-slate-300 hover:text-white hover:bg-slate-800 border border-slate-800 transition"
            >
              <LogOut className="w-4 h-4" />
              <span className="hidden sm:inline">Sign out</span>
            </button>
          </div>
        )}
      </div>
    </header>
    {user && <AccountModal isOpen={accountOpen} onClose={() => setAccountOpen(false)} />}
    </>
  );
}
