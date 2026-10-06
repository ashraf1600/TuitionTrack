import React, { useState, useEffect } from 'react';
import Modal from '../common/Modal';
import { api } from '../../api/client';
import StudentCredentialsModal from './StudentCredentialsModal';
import { UserPlus, AlertCircle, CheckCircle2, Key, Sparkles, Eye, EyeOff } from 'lucide-react';

function generateRandomPassword(length = 12) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%&*';
  let res = '';
  const arr = new Uint32Array(length);
  if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
    crypto.getRandomValues(arr);
    for (let i = 0; i < length; i++) res += chars[arr[i] % chars.length];
  } else {
    for (let i = 0; i < length; i++) res += chars[Math.floor(Math.random() * chars.length)];
  }
  return res;
}

export default function AddStudentModal({
  isOpen,
  onClose,
  onStudentAdded,
  tuitions = [],
  initialTuitionId = '',
}) {
  const [formData, setFormData] = useState({
    username: '',
    password: '',
    first_name: '',
    last_name: '',
    email: '',
    phone: '',
    grade_level: 'Class 10',
    institution: '',
    parent_name: '',
    parent_phone: '',
    address: '',
    notes: '',
    tuition_id: '',
  });

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [credentialsModalOpen, setCredentialsModalOpen] = useState(false);
  const [createdStudentCreds, setCreatedStudentCreds] = useState(null);

  // Sync initialTuitionId when modal opens
  useEffect(() => {
    if (isOpen) {
      setError('');
      setSuccess('');
      if (initialTuitionId) {
        const selectedT = tuitions.find(
          (t) => t.id === initialTuitionId || String(t.id) === String(initialTuitionId)
        );
        if (selectedT) {
          setFormData((prev) => ({
            ...prev,
            tuition_id: selectedT.id,
          }));
        }
      }
    }
  }, [isOpen, initialTuitionId, tuitions]);

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData((prev) => ({
      ...prev,
      [name]: name === 'cycle_length' ? parseInt(value) || 12 : value,
    }));
  };

  const handleTuitionChange = (e) => {
    const tId = e.target.value;
    const selectedT = tuitions.find((t) => t.id === tId);
    if (selectedT) {
      setFormData((prev) => ({
        ...prev,
        tuition_id: tId,
      }));
    } else {
      setFormData((prev) => ({
        ...prev,
        tuition_id: '',
      }));
    }
  };

  const handleCloseCredentials = () => {
    setCredentialsModalOpen(false);
    if (onStudentAdded && createdStudentCreds) {
      onStudentAdded(createdStudentCreds.student, createdStudentCreds.tuitionId);
    }
    onClose();
    setFormData({
      username: '',
      password: '',
      first_name: '',
      last_name: '',
      email: '',
      phone: '',
      grade_level: 'Class 10',
      institution: '',
      parent_name: '',
      parent_phone: '',
      address: '',
      notes: '',
      tuition_id: '',
    });
    setSuccess('');
    setCreatedStudentCreds(null);
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setSuccess('');
    setLoading(true);

    try {
      const payload = { ...formData };
      if (!payload.tuition_id) {
        delete payload.tuition_id;
      }
      const res = await api.createStudent(payload);

      // If tuition was selected and backend didn't already enroll, ensure enrollment
      if (formData.tuition_id && res?.student?.id) {
        try {
          await api.enrollInTuition(formData.tuition_id, res.student.id);
        } catch (_) {
          // Handled or already enrolled
        }
      }

      setCreatedStudentCreds({
        student: res.student,
        tempPassword: payload.password,
        tuitionId: formData.tuition_id,
      });
      setCredentialsModalOpen(true);
    } catch (err) {
      setError(err.message || 'Failed to create student account.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      <Modal isOpen={isOpen && !credentialsModalOpen} onClose={onClose} title="Add New Student & Initialize Cycle" maxWidth="max-w-2xl">
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 text-sm flex items-center gap-2">
            <AlertCircle className="w-5 h-5 flex-shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {success && (
          <div className="p-3 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-sm flex items-center gap-2">
            <CheckCircle2 className="w-5 h-5 flex-shrink-0" />
            <span>{success}</span>
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Username *
            </label>
            <input
              type="text"
              name="username"
              required
              value={formData.username}
              onChange={handleChange}
              placeholder="e.g. rahim_10"
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
            />
          </div>

          <div>
            <div className="flex items-center justify-between mb-1">
              <label className="text-xs font-semibold text-slate-300">
                Password *
              </label>
              <button
                type="button"
                onClick={() => {
                  const gen = generateRandomPassword(12);
                  setFormData((prev) => ({ ...prev, password: gen }));
                  setShowPassword(true);
                }}
                className="text-[11px] text-indigo-400 hover:text-indigo-300 font-semibold flex items-center gap-1 transition"
              >
                <Sparkles className="w-3 h-3" />
                <span>Auto-Generate</span>
              </button>
            </div>
            <div className="relative">
              <input
                type={showPassword ? 'text' : 'password'}
                name="password"
                required
                minLength={6}
                value={formData.password}
                onChange={handleChange}
                placeholder="Min 6 characters or Auto-Generate"
                className="w-full px-3 py-2 pr-9 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 font-mono transition"
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-200"
                title={showPassword ? 'Hide password' : 'Show password'}
              >
                {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              First Name *
            </label>
            <input
              type="text"
              name="first_name"
              required
              value={formData.first_name}
              onChange={handleChange}
              placeholder="e.g. Rahim"
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Last Name
            </label>
            <input
              type="text"
              name="last_name"
              value={formData.last_name}
              onChange={handleChange}
              placeholder="e.g. Ahmed"
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Email (for exam alerts)
            </label>
            <input
              type="email"
              name="email"
              value={formData.email}
              onChange={handleChange}
              placeholder="rahim@gmail.com"
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Phone
            </label>
            <input
              type="tel"
              name="phone"
              value={formData.phone}
              onChange={handleChange}
              placeholder="+88017..."
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
            />
          </div>
        </div>

        {/* Optional Tuition Assignment */}
        {tuitions && tuitions.length > 0 && (
          <div className="p-3 rounded-xl bg-indigo-500/10 border border-indigo-500/20 space-y-1.5">
            <label className="block text-xs font-semibold text-indigo-300">
              Tuition group (optional)
            </label>
            <select
              name="tuition_id"
              value={formData.tuition_id || ''}
              onChange={handleTuitionChange}
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
            >
              <option value="">No group yet — place them later</option>
              {tuitions.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.title} ({t.enrolled_count ?? t.enrollments?.length ?? 0} students · {t.cycle_length} classes per cycle)
                </option>
              ))}
            </select>
            {formData.tuition_id && (
              <p className="text-[11px] text-emerald-400 font-medium">
                ✓ They join this group straight away and share its class tracker and exams.
              </p>
            )}
          </div>
        )}

        {/* Academic details */}
        <div className="pt-2 border-t border-slate-800 grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Grade / Class
            </label>
            <input
              type="text"
              name="grade_level"
              value={formData.grade_level}
              onChange={handleChange}
              placeholder="e.g. Class 10 / HSC-26"
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Institution
            </label>
            <input
              type="text"
              name="institution"
              value={formData.institution}
              onChange={handleChange}
              placeholder="e.g. Dhaka City College"
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
            />
          </div>

          <div className="sm:col-span-2">
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Address
            </label>
            <input
              type="text"
              name="address"
              value={formData.address}
              onChange={handleChange}
              placeholder="e.g. House 12, Road 5, Dhanmondi, Dhaka"
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Guardian Name
            </label>
            <input
              type="text"
              name="parent_name"
              value={formData.parent_name}
              onChange={handleChange}
              placeholder="Guardian full name"
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-300 mb-1">
              Guardian Phone
            </label>
            <input
              type="tel"
              name="parent_phone"
              value={formData.parent_phone}
              onChange={handleChange}
              placeholder="+88017..."
              className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
            />
          </div>
        </div>

        <div className="pt-4 flex items-center justify-end gap-3">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 rounded-xl border border-slate-700 text-slate-300 text-sm hover:bg-slate-800 transition"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={loading}
            className="px-5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-sm shadow-lg shadow-indigo-600/30 flex items-center gap-2 transition disabled:opacity-50"
          >
            {loading ? (
              <>
                <div className="w-4 h-4 rounded-full border-2 border-white/30 border-t-white animate-spin" />
                <span>Creating Account...</span>
              </>
            ) : (
              <>
                <UserPlus className="w-4 h-4" />
                <span>Create Student & Cycle #1</span>
              </>
            )}
          </button>
        </div>
      </form>
    </Modal>

    <StudentCredentialsModal
      isOpen={credentialsModalOpen}
      onClose={handleCloseCredentials}
      student={createdStudentCreds?.student}
      tempPassword={createdStudentCreds?.tempPassword}
    />
  </>
  );
}
