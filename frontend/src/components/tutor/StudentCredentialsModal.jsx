import React, { useEffect, useState } from 'react';
import Modal from '../common/Modal';
import { api } from '../../api/client';
import {
  Key,
  Copy,
  Check,
  Eye,
  EyeOff,
  User,
  ShieldCheck,
  Send,
  ExternalLink,
} from 'lucide-react';

export default function StudentCredentialsModal({
  isOpen,
  onClose,
  student,
  tempPassword,
}) {
  const [showPassword, setShowPassword] = useState(true);
  const [copiedField, setCopiedField] = useState(null);
  const [generated, setGenerated] = useState('');
  const [resetting, setResetting] = useState(false);
  const [resetError, setResetError] = useState('');

  const studentKey = student?.student_id || student?.id || '';
  useEffect(() => {
    // A password is shown once: forget it as soon as the dialog closes or the student changes.
    setGenerated('');
    setResetError('');
  }, [studentKey, isOpen]);

  if (!student) return null;

  const handleReset = async () => {
    setResetting(true);
    setResetError('');
    try {
      const res = await api.resetStudentPassword(studentKey);
      setGenerated(res.temporary_password);
    } catch (err) {
      setResetError(err.message || 'Could not reset the password.');
    } finally {
      setResetting(false);
    }
  };

  const username = student.username || student.student_username || '';
  const fullName = student.full_name || student.student_name || student.name || username;
  const password = tempPassword || generated;
  const loginUrl = `${window.location.origin}/login`;

  const copyToClipboard = (text, fieldName) => {
    navigator.clipboard.writeText(text);
    setCopiedField(fieldName);
    setTimeout(() => {
      setCopiedField(null);
    }, 2000);
  };

  const shareableMessage = `🎓 TuitionTrack Student Portal Access
Hello ${fullName},
Your student account has been created on TuitionTrack!

Username: ${username}
Temporary Password: ${password}
Login Portal: ${loginUrl}

You will be asked to choose your own password the first time you sign in.`;

  // Passwords are not kept in readable form, so an existing one cannot be shown —
  // the tutor can only replace it with a new temporary one.
  if (!password) {
    return (
      <Modal isOpen={isOpen} onClose={onClose} title="Reset student password" maxWidth="max-w-md">
        <div className="space-y-4">
          <p className="text-sm text-slate-300 leading-relaxed">
            For security, <strong>{fullName}</strong>'s password is not stored anywhere you can read it.
            If they are locked out, give them a new temporary password. Their old password stops working,
            and they choose their own the next time they sign in.
          </p>
          <p className="text-xs text-slate-400">Username: <span className="font-mono text-slate-200">{username}</span></p>
          {resetError && (
            <div className="p-3 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-200 text-sm">{resetError}</div>
          )}
          <div className="flex justify-end gap-2 pt-3 border-t border-slate-800">
            <button type="button" onClick={onClose} className="px-4 py-2 rounded-xl text-sm font-medium text-slate-300 hover:text-white">
              Cancel
            </button>
            <button
              type="button"
              onClick={handleReset}
              disabled={resetting}
              className="px-5 py-2 rounded-xl bg-amber-500 hover:bg-amber-400 text-slate-950 text-sm font-bold transition disabled:opacity-60"
            >
              {resetting ? 'Resetting…' : 'Create new temporary password'}
            </button>
          </div>
        </div>
      </Modal>
    );
  }

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Student Account Credentials"
      maxWidth="max-w-md"
    >
      <div className="space-y-5">
        {/* Header Banner */}
        <div className="p-3.5 rounded-2xl bg-indigo-500/10 border border-indigo-500/20 flex items-start gap-3">
          <div className="p-2 rounded-xl bg-indigo-600/20 text-indigo-400 mt-0.5">
            <ShieldCheck className="w-5 h-5" />
          </div>
          <div>
            <h4 className="text-sm font-bold text-slate-100">
              Student Account Ready
            </h4>
            <p className="text-xs text-slate-300 mt-0.5 leading-relaxed">
              Share these credentials with <strong>{fullName}</strong> so they can log in to the Student Portal.
            </p>
          </div>
        </div>

        {/* Credentials Cards */}
        <div className="space-y-3">
          {/* Username */}
          <div className="p-3 rounded-xl bg-slate-800/60 border border-slate-700/60 flex items-center justify-between gap-3">
            <div className="flex items-center gap-2.5 min-w-0">
              <User className="w-4 h-4 text-indigo-400 flex-shrink-0" />
              <div className="min-w-0">
                <span className="text-[10px] uppercase font-bold tracking-wider text-slate-400 block">
                  Username
                </span>
                <span className="text-sm font-mono font-bold text-slate-100 truncate block">
                  {username}
                </span>
              </div>
            </div>

            <button
              type="button"
              onClick={() => copyToClipboard(username, 'username')}
              className="px-2.5 py-1.5 rounded-lg bg-slate-700/80 hover:bg-slate-700 text-slate-200 text-xs font-semibold flex items-center gap-1.5 transition active:scale-95 flex-shrink-0"
              title="Copy Username"
            >
              {copiedField === 'username' ? (
                <>
                  <Check className="w-3.5 h-3.5 text-emerald-400" />
                  <span className="text-emerald-400">Copied</span>
                </>
              ) : (
                <>
                  <Copy className="w-3.5 h-3.5 text-slate-400" />
                  <span>Copy</span>
                </>
              )}
            </button>
          </div>

          {/* Password */}
          <div className="p-3 rounded-xl bg-slate-800/60 border border-slate-700/60 flex items-center justify-between gap-3">
            <div className="flex items-center gap-2.5 min-w-0">
              <Key className="w-4 h-4 text-amber-400 flex-shrink-0" />
              <div className="min-w-0">
                <span className="text-[10px] uppercase font-bold tracking-wider text-slate-400 block">
                  Temporary Password
                </span>
                <span className="text-sm font-mono font-bold text-amber-300 truncate block">
                  {showPassword ? (password || '••••••••') : '••••••••••••'}
                </span>
              </div>
            </div>

            <div className="flex items-center gap-1.5 flex-shrink-0">
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="p-1.5 rounded-lg bg-slate-700/50 hover:bg-slate-700 text-slate-400 hover:text-slate-200 transition"
                title={showPassword ? 'Hide Password' : 'Show Password'}
              >
                {showPassword ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
              </button>

              <button
                type="button"
                onClick={() => copyToClipboard(password, 'password')}
                className="px-2.5 py-1.5 rounded-lg bg-slate-700/80 hover:bg-slate-700 text-slate-200 text-xs font-semibold flex items-center gap-1.5 transition active:scale-95"
                title="Copy Password"
              >
                {copiedField === 'password' ? (
                  <>
                    <Check className="w-3.5 h-3.5 text-emerald-400" />
                    <span className="text-emerald-400">Copied</span>
                  </>
                ) : (
                  <>
                    <Copy className="w-3.5 h-3.5 text-slate-400" />
                    <span>Copy</span>
                  </>
                )}
              </button>
            </div>
          </div>
        </div>

        {/* Saved Notice */}
        <div className="p-3 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs flex items-center gap-2">
          <Check className="w-4 h-4 flex-shrink-0" />
          <span>
            <strong>Saved in Roster:</strong> This password is saved in your student profile so you can look it up anytime.
          </span>
        </div>

        {/* Action Buttons */}
        <div className="flex flex-col sm:flex-row items-center gap-2 pt-1">
          <button
            type="button"
            onClick={() => copyToClipboard(shareableMessage, 'all')}
            className="w-full sm:flex-1 py-2.5 px-4 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-xs flex items-center justify-center gap-2 shadow-lg shadow-indigo-600/20 transition active:scale-95"
          >
            {copiedField === 'all' ? (
              <>
                <Check className="w-4 h-4 text-white" />
                <span>Copied All Details!</span>
              </>
            ) : (
              <>
                <Send className="w-4 h-4" />
                <span>Copy Shareable Instructions</span>
              </>
            )}
          </button>

          <button
            type="button"
            onClick={onClose}
            className="w-full sm:w-auto px-5 py-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-300 font-semibold text-xs transition"
          >
            Done
          </button>
        </div>
      </div>
    </Modal>
  );
}
