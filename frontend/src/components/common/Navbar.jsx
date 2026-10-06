import React from 'react';
import { useAuth } from '../../context/AuthContext';
import { GraduationCap, LogOut, User, ShieldCheck } from 'lucide-react';

export default function Navbar() {
  const { user, logout, isTutor } = useAuth();

  return (
    <header className="sticky top-0 z-40 w-full border-b border-slate-800 bg-slate-900/80 backdrop-blur-md">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
        {/* Brand */}
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-indigo-600 to-indigo-400 flex items-center justify-center shadow-lg shadow-indigo-500/20 text-white">
            <GraduationCap className="w-6 h-6" />
          </div>
          <div>
            <span className="text-xl font-bold tracking-tight bg-gradient-to-r from-white via-slate-200 to-slate-400 bg-clip-text text-transparent">
              Tuition<span className="text-indigo-400">Track</span>
            </span>
            <span className="hidden sm:inline-block ml-2 text-xs font-semibold px-2 py-0.5 rounded-full bg-slate-800 text-slate-400 border border-slate-700">
              SaaS
            </span>
          </div>
        </div>

        {/* User Info & Actions */}
        {user && (
          <div className="flex items-center gap-3 sm:gap-4">
            <div className="flex items-center gap-2.5 px-3 py-1.5 rounded-xl bg-slate-800/80 border border-slate-700/60 text-sm">
              <div className={`w-2 h-2 rounded-full ${isTutor ? 'bg-indigo-400' : 'bg-emerald-400'} animate-ping`} />
              <div className="flex flex-col text-left">
                <span className="font-semibold text-slate-200 leading-none">
                  {user.name || user.username}
                </span>
                <span className="text-[11px] font-medium text-slate-400 uppercase tracking-wider mt-0.5">
                  {user.role}
                </span>
              </div>
            </div>

            <button
              onClick={logout}
              title="Sign Out"
              className="p-2 rounded-xl text-slate-400 hover:text-rose-400 hover:bg-rose-500/10 border border-transparent hover:border-rose-500/20 transition-all duration-200"
            >
              <LogOut className="w-5 h-5" />
            </button>
          </div>
        )}
      </div>
    </header>
  );
}
