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
      <header className="sticky top-0 z-40 w-full border-b border-slate-800/80 bg-slate-950/80 backdrop-blur-xl">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <Link
              to={user ? home : '/login'}
              className="flex items-center gap-2.5 rounded-xl group focus-visible:ring-2 focus-visible:ring-indigo-500"
              aria-label="TuitionTrack home"
            >
              <span className="w-9 h-9 rounded-xl bg-gradient-to-tr from-indigo-600 to-indigo-500 flex items-center justify-center text-white shadow-md shadow-indigo-600/25 group-hover:scale-105 transition-transform duration-200">
                <GraduationCap className="w-5 h-5" />
              </span>
              <div className="flex flex-col">
                <span className="text-lg font-extrabold tracking-tight text-white flex items-center gap-1">
                  Tuition<span className="text-indigo-400">Track</span>
                </span>
              </div>
            </Link>

            {user && (
              <span
                className={`inline-flex items-center gap-1.5 px-2 sm:px-2.5 py-0.5 rounded-full text-[10px] sm:text-[11px] font-semibold border ${
                  isTutor
                    ? 'bg-indigo-500/10 text-indigo-300 border-indigo-500/25'
                    : 'bg-emerald-500/10 text-emerald-300 border-emerald-500/25'
                }`}
              >
                <span className={`w-1.5 h-1.5 rounded-full ${isTutor ? 'bg-indigo-400 animate-pulse' : 'bg-emerald-400 animate-pulse'}`} />
                <span className="hidden sm:inline">{isTutor ? 'Tutor Workspace' : 'Student Portal'}</span>
                <span className="sm:hidden">{isTutor ? 'Tutor' : 'Student'}</span>
              </span>
            )}
          </div>

          {user && (
            <div className="flex items-center gap-2 sm:gap-3">
              <NotificationBell />

              <button
                type="button"
                onClick={() => setAccountOpen(true)}
                title="My account settings"
                className="flex items-center gap-2.5 rounded-xl px-2 py-1.5 hover:bg-slate-800/80 border border-transparent hover:border-slate-700/60 transition-all text-left group"
              >
                <span
                  className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold border transition ${
                    isTutor
                      ? 'bg-indigo-500/15 text-indigo-300 border-indigo-500/30 group-hover:border-indigo-400'
                      : 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30 group-hover:border-emerald-400'
                  }`}
                  aria-hidden="true"
                >
                  {displayName.charAt(0).toUpperCase()}
                </span>
                <span className="hidden sm:flex flex-col leading-tight">
                  <span className="text-xs font-semibold text-slate-100 max-w-[150px] truncate group-hover:text-white transition">
                    {displayName}
                  </span>
                  <span className="text-[10px] text-slate-400">{isTutor ? 'Tutor' : 'Student'} · Account</span>
                </span>
              </button>

              <button
                type="button"
                onClick={logout}
                title="Sign out of TuitionTrack"
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium text-slate-400 hover:text-rose-300 hover:bg-rose-500/10 border border-slate-800 hover:border-rose-500/30 transition-all"
              >
                <LogOut className="w-3.5 h-3.5" />
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
