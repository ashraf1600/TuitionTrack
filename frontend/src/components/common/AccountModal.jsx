import React, { useEffect, useState } from 'react';
import { AlertCircle, Loader2, Copy, Check } from 'lucide-react';
import Modal from './Modal';
import PasswordField from './PasswordField';
import { useAuth } from '../../context/AuthContext';
import { api } from '../../api/client';
import { notify } from '../../utils/toast';

const inputCls =
  'w-full px-3.5 py-2.5 rounded-xl bg-slate-800/80 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/25 transition';

function Field({ label, id, children }) {
  return (
    <div>
      <label htmlFor={id} className="block text-sm font-medium text-slate-200 mb-1.5">{label}</label>
      {children}
    </div>
  );
}

/** "My account": edit your own details and change your password. */
export default function AccountModal({ isOpen, onClose }) {
  const { user, isStudent, refreshUser } = useAuth();
  const [tab, setTab] = useState('profile');
  const [form, setForm] = useState({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!isOpen || !user) return;
    setTab('profile');
    setError('');
    setCurrent('');
    setNext('');
    setConfirm('');
    setForm({
      first_name: user.first_name || '',
      last_name: user.last_name || '',
      email: user.email || '',
      phone: user.phone || '',
      grade_level: user.profile?.grade_level || '',
      institution: user.profile?.institution || '',
      address: user.profile?.address || '',
      parent_name: user.profile?.parent_name || '',
      parent_phone: user.profile?.parent_phone || '',
    });
  }, [isOpen, user]);

  const set = (key) => (e) => setForm((prev) => ({ ...prev, [key]: e.target.value }));

  const saveProfile = async (e) => {
    e.preventDefault();
    setError('');
    setSaving(true);
    try {
      const payload = { ...form };
      if (!isStudent) {
        ['grade_level', 'institution', 'address', 'parent_name', 'parent_phone'].forEach((k) => delete payload[k]);
      }
      await api.updateMe(payload);
      await refreshUser();
      notify.success('Your details have been saved.');
      onClose();
    } catch (err) {
      setError(err.message || 'Could not save your details.');
    } finally {
      setSaving(false);
    }
  };

  const savePassword = async (e) => {
    e.preventDefault();
    setError('');
    if (next !== confirm) {
      setError('The two new passwords do not match.');
      return;
    }
    setSaving(true);
    try {
      await api.changePassword(current, next);
      notify.success('Your password has been changed.');
      onClose();
    } catch (err) {
      setError(err.message || 'Could not change the password.');
    } finally {
      setSaving(false);
    }
  };

  const mismatch = confirm.length > 0 && next !== confirm;

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="My account" maxWidth="max-w-xl">
      <div className="flex gap-1 p-1 rounded-xl bg-slate-800/60 border border-slate-700/60 mb-5 w-fit" role="tablist">
        {[['profile', 'My details'], ['password', 'Password']].map(([key, label]) => (
          <button
            key={key}
            type="button"
            role="tab"
            aria-selected={tab === key}
            onClick={() => { setTab(key); setError(''); }}
            className={`px-4 py-1.5 rounded-lg text-sm font-semibold transition ${tab === key ? 'bg-indigo-600 text-white' : 'text-slate-400 hover:text-slate-100'}`}
          >
            {label}
          </button>
        ))}
      </div>

      {error && (
        <div role="alert" className="mb-4 p-3 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-200 text-sm flex items-start gap-2.5">
          <AlertCircle className="w-5 h-5 flex-shrink-0 text-rose-400" />
          <span>{error}</span>
        </div>
      )}

      {tab === 'profile' ? (
        <form onSubmit={saveProfile} className="space-y-4">
          {!isStudent && user?.tutor_code && (
            <div className="p-4 rounded-xl bg-indigo-500/10 border border-indigo-500/30 flex flex-wrap items-center justify-between gap-3">
              <div>
                <div className="text-[11px] font-bold uppercase tracking-wider text-indigo-300">
                  My student invite code
                </div>
                <div className="font-mono text-lg font-black tracking-widest text-indigo-100 select-all">
                  {user.tutor_code}
                </div>
                <p className="text-[11px] text-slate-400 mt-0.5">
                  Students enter this code to request connection with you.
                </p>
              </div>
              <button
                type="button"
                onClick={() => {
                  navigator.clipboard.writeText(user.tutor_code);
                  setCopied(true);
                  notify.success('Invite code copied.');
                  setTimeout(() => setCopied(false), 2000);
                }}
                className="px-3.5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold flex items-center gap-1.5 transition"
              >
                {copied ? <Check className="w-4 h-4" /> : <Copy className="w-4 h-4" />}
                {copied ? 'Copied' : 'Copy'}
              </button>
            </div>
          )}
          <p className="text-xs text-slate-400">
            Username <span className="font-mono text-slate-200">@{user?.username}</span> cannot be changed.
          </p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <Field label="First name" id="acc-first"><input id="acc-first" required value={form.first_name || ''} onChange={set('first_name')} className={inputCls} /></Field>
            <Field label="Last name" id="acc-last"><input id="acc-last" value={form.last_name || ''} onChange={set('last_name')} className={inputCls} /></Field>
            <Field label="Email" id="acc-email"><input id="acc-email" type="email" value={form.email || ''} onChange={set('email')} className={inputCls} /></Field>
            <Field label="Phone" id="acc-phone"><input id="acc-phone" type="tel" value={form.phone || ''} onChange={set('phone')} className={inputCls} /></Field>
          </div>
          <p className="text-xs text-slate-400 -mt-1">
            An email address lets you reset a forgotten password yourself.
          </p>
          {isStudent && (
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-3 border-t border-slate-800">
              <Field label="Class" id="acc-grade"><input id="acc-grade" value={form.grade_level || ''} onChange={set('grade_level')} className={inputCls} /></Field>
              <Field label="School / college" id="acc-inst"><input id="acc-inst" value={form.institution || ''} onChange={set('institution')} className={inputCls} /></Field>
              <div className="sm:col-span-2">
                <Field label="Address" id="acc-address"><input id="acc-address" value={form.address || ''} onChange={set('address')} className={inputCls} /></Field>
              </div>
              <Field label="Guardian name" id="acc-parent"><input id="acc-parent" value={form.parent_name || ''} onChange={set('parent_name')} className={inputCls} /></Field>
              <Field label="Guardian phone" id="acc-parent-phone"><input id="acc-parent-phone" type="tel" value={form.parent_phone || ''} onChange={set('parent_phone')} className={inputCls} /></Field>
            </div>
          )}
          <Actions onClose={onClose} saving={saving} label="Save details" />
        </form>
      ) : (
        <form onSubmit={savePassword} className="space-y-4">
          <PasswordField id="acc-current" label="Current password" value={current} onChange={setCurrent} autoComplete="current-password" />
          <PasswordField id="acc-new" label="New password" value={next} onChange={setNext} minLength={8} hint="At least 8 characters, not only numbers." />
          <PasswordField id="acc-confirm" label="New password again" value={confirm} onChange={setConfirm} error={mismatch ? 'The passwords do not match yet.' : ''} />
          <Actions onClose={onClose} saving={saving} label="Change password" />
        </form>
      )}
    </Modal>
  );
}

function Actions({ onClose, saving, label }) {
  return (
    <div className="flex justify-end gap-2 pt-4 border-t border-slate-800">
      <button type="button" onClick={onClose} className="px-4 py-2 rounded-xl text-sm font-medium text-slate-300 hover:text-white">
        Cancel
      </button>
      <button
        type="submit"
        disabled={saving}
        className="px-5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-sm font-semibold flex items-center gap-2 transition disabled:opacity-60"
      >
        {saving && <Loader2 className="w-4 h-4 animate-spin" />}
        {label}
      </button>
    </div>
  );
}
