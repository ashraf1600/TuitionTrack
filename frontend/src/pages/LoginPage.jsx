import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { api } from '../api/client';
import { GraduationCap, Lock, User, Mail, Phone, ArrowRight, AlertCircle, ShieldCheck, School, Users } from 'lucide-react';

export default function LoginPage() {
  const [mode, setMode] = useState('login'); // 'login' | 'register-tutor' | 'register-student'
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');

  // Register extra fields
  const [email, setEmail] = useState('');
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [phone, setPhone] = useState('');
  const [passwordConfirm, setPasswordConfirm] = useState('');

  // Student specific
  const [gradeLevel, setGradeLevel] = useState('Class 10');
  const [institution, setInstitution] = useState('');
  const [parentPhone, setParentPhone] = useState('');
  const [selectedTutor, setSelectedTutor] = useState(null);
  const [tutorSearch, setTutorSearch] = useState('');
  const [tutorList, setTutorList] = useState([]);
  const [loadingTutors, setLoadingTutors] = useState(false);

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const { login, registerTutor, registerStudent } = useAuth();
  const navigate = useNavigate();

  // Load tutors for discovery
  useEffect(() => {
    if (mode === 'register-student') {
      const fetchTutors = async () => {
        try {
          setLoadingTutors(true);
          const res = await api.getTutors(tutorSearch);
          const list = Array.isArray(res) ? res : res.results || [];
          setTutorList(list);
        } catch (err) {
          console.error('Failed to load tutor directory:', err);
        } finally {
          setLoadingTutors(false);
        }
      };
      const timeoutId = setTimeout(fetchTutors, 250);
      return () => clearTimeout(timeoutId);
    }
  }, [mode, tutorSearch]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      if (mode === 'register-tutor') {
        if (password !== passwordConfirm) {
          throw new Error('Passwords do not match.');
        }
        await registerTutor({
          username,
          password,
          password_confirm: passwordConfirm,
          first_name: firstName,
          last_name: lastName,
          email,
          phone,
        });
        navigate('/tutor');
      } else if (mode === 'register-student') {
        if (password !== passwordConfirm) {
          throw new Error('Passwords do not match.');
        }
        await registerStudent({
          username,
          password,
          password_confirm: passwordConfirm,
          first_name: firstName,
          last_name: lastName,
          email,
          phone,
          grade_level: gradeLevel,
          institution,
          parent_phone: parentPhone,
          selected_tutor_id: selectedTutor?.id || '',
          selected_tutor_username: selectedTutor?.username || '',
        });
        navigate('/student');
      } else {
        const user = await login(username, password);
        if (user.role === 'TUTOR') {
          navigate('/tutor');
        } else {
          navigate('/student');
        }
      }
    } catch (err) {
      setError(err.message || 'Authentication failed. Please verify credentials.');
    } finally {
      setLoading(false);
    }
  };

  const handleDemoTutor = () => {
    setUsername('admin');
    setPassword('admin1234');
    setMode('login');
  };

  const handleDemoStudent = () => {
    setUsername('integration_student_1');
    setPassword('pass123456');
    setMode('login');
  };

  return (
    <div className="min-h-screen bg-slate-950 flex flex-col justify-center py-12 sm:px-6 lg:px-8 relative overflow-hidden">
      {/* Background ambient glow */}
      <div className="absolute top-1/4 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] bg-indigo-600/10 rounded-full blur-[140px] pointer-events-none" />

      <div className="sm:mx-auto sm:w-full sm:max-w-md relative z-10 text-center">
        <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-gradient-to-tr from-indigo-600 to-indigo-400 text-white shadow-xl shadow-indigo-600/25 mb-4">
          <GraduationCap className="w-8 h-8" />
        </div>
        <h1 className="text-3xl font-extrabold tracking-tight bg-gradient-to-r from-white via-slate-200 to-slate-400 bg-clip-text text-transparent">
          Tuition<span className="text-indigo-400">Track</span>
        </h1>
        <p className="mt-2 text-sm text-slate-400">
          Smart Multi-Tenant Tuition Attendance, Batches & Exam Platform
        </p>
      </div>

      <div className="mt-8 sm:mx-auto sm:w-full sm:max-w-lg relative z-10 px-4 sm:px-0">
        <div className="glass-panel py-8 px-6 sm:px-10 rounded-3xl shadow-2xl">
          {/* 3 Mode Switch Tabs */}
          <div className="flex rounded-xl bg-slate-800/80 p-1 mb-6 border border-slate-700/60">
            <button
              type="button"
              onClick={() => { setMode('login'); setError(''); }}
              className={`flex-1 py-2 text-xs font-bold rounded-lg transition ${
                mode === 'login' ? 'bg-indigo-600 text-white shadow-md' : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              Sign In
            </button>
            <button
              type="button"
              onClick={() => { setMode('register-tutor'); setError(''); }}
              className={`flex-1 py-2 text-xs font-bold rounded-lg transition ${
                mode === 'register-tutor' ? 'bg-indigo-600 text-white shadow-md' : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              Tutor Sign Up
            </button>
            <button
              type="button"
              onClick={() => { setMode('register-student'); setError(''); }}
              className={`flex-1 py-2 text-xs font-bold rounded-lg transition ${
                mode === 'register-student' ? 'bg-indigo-600 text-white shadow-md' : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              Student Sign Up
            </button>
          </div>

          {error && (
            <div className="mb-5 p-3 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs flex items-center gap-2">
              <AlertCircle className="w-4 h-4 flex-shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-xs font-semibold text-slate-300 mb-1">
                Username *
              </label>
              <div className="relative">
                <input
                  type="text"
                  required
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="Enter username"
                  className="w-full pl-9 pr-3 py-2.5 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
                />
                <User className="w-4 h-4 text-slate-500 absolute left-3 top-3" />
              </div>
            </div>

            {mode !== 'login' && (
              <>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-semibold text-slate-300 mb-1">
                      First Name *
                    </label>
                    <input
                      type="text"
                      required
                      value={firstName}
                      onChange={(e) => setFirstName(e.target.value)}
                      placeholder="First name"
                      className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-semibold text-slate-300 mb-1">
                      Last Name
                    </label>
                    <input
                      type="text"
                      value={lastName}
                      onChange={(e) => setLastName(e.target.value)}
                      placeholder="Last name"
                      className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500"
                    />
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-semibold text-slate-300 mb-1">
                      Email
                    </label>
                    <div className="relative">
                      <input
                        type="email"
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                        placeholder="email@example.com"
                        className="w-full pl-8 pr-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-xs focus:outline-none focus:border-indigo-500"
                      />
                      <Mail className="w-3.5 h-3.5 text-slate-500 absolute left-2.5 top-3" />
                    </div>
                  </div>

                  <div>
                    <label className="block text-xs font-semibold text-slate-300 mb-1">
                      Phone
                    </label>
                    <div className="relative">
                      <input
                        type="tel"
                        value={phone}
                        onChange={(e) => setPhone(e.target.value)}
                        placeholder="+88017..."
                        className="w-full pl-8 pr-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-xs focus:outline-none focus:border-indigo-500"
                      />
                      <Phone className="w-3.5 h-3.5 text-slate-500 absolute left-2.5 top-3" />
                    </div>
                  </div>
                </div>

                {mode === 'register-student' && (
                  <div className="space-y-3 pt-2 border-t border-slate-800">
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <label className="block text-xs font-semibold text-slate-300 mb-1">
                          Grade / Class
                        </label>
                        <input
                          type="text"
                          value={gradeLevel}
                          onChange={(e) => setGradeLevel(e.target.value)}
                          placeholder="e.g. Class 10 / HSC"
                          className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-xs focus:outline-none focus:border-indigo-500"
                        />
                      </div>
                      <div>
                        <label className="block text-xs font-semibold text-slate-300 mb-1">
                          School / College
                        </label>
                        <input
                          type="text"
                          value={institution}
                          onChange={(e) => setInstitution(e.target.value)}
                          placeholder="Institution name"
                          className="w-full px-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-xs focus:outline-none focus:border-indigo-500"
                        />
                      </div>
                    </div>

                    <div className="grid grid-cols-2 gap-3">
                      <div className="col-span-2">
                        <label className="block text-xs font-semibold text-slate-300 mb-1">
                          Select Your Desired Tutor *
                        </label>
                        <div className="relative mb-2">
                          <input
                            type="text"
                            value={tutorSearch}
                            onChange={(e) => setTutorSearch(e.target.value)}
                            placeholder="Search tutor by name or subject (e.g. Physics, Ashraf)..."
                            className="w-full pl-8 pr-3 py-2 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-xs focus:outline-none focus:border-indigo-500"
                          />
                          <Users className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 top-2.5" />
                        </div>

                        {selectedTutor && (
                          <div className="mb-2.5 p-2.5 rounded-xl bg-indigo-500/15 border border-indigo-500/30 flex items-center justify-between text-xs text-indigo-300">
                            <div>
                              <span className="font-bold text-white">{selectedTutor.name}</span>
                              <span className="ml-1.5 text-slate-400">(@{selectedTutor.username})</span>
                              {selectedTutor.tuitions?.length > 0 && (
                                <span className="ml-2 text-[11px] text-indigo-400 bg-indigo-900/50 px-1.5 py-0.5 rounded">
                                  {selectedTutor.tuitions.map(t => t.title).join(', ')}
                                </span>
                              )}
                            </div>
                            <button
                              type="button"
                              onClick={() => setSelectedTutor(null)}
                              className="text-slate-400 hover:text-white text-xs underline ml-2"
                            >
                              Change
                            </button>
                          </div>
                        )}

                        <div className="max-h-36 overflow-y-auto space-y-1 rounded-xl border border-slate-800 p-1 bg-slate-900/70">
                          {loadingTutors ? (
                            <p className="text-center py-2 text-xs text-slate-500">Searching tutors...</p>
                          ) : tutorList.length === 0 ? (
                            <p className="text-center py-2 text-xs text-slate-500">No tutors found.</p>
                          ) : (
                            tutorList.map((t) => {
                              const isSelected = selectedTutor?.id === t.id;
                              return (
                                <button
                                  type="button"
                                  key={t.id}
                                  onClick={() => setSelectedTutor(t)}
                                  className={`w-full text-left p-2 rounded-lg text-xs flex items-center justify-between transition ${
                                    isSelected
                                      ? 'bg-indigo-600 text-white font-semibold'
                                      : 'hover:bg-slate-800 text-slate-300'
                                  }`}
                                >
                                  <div>
                                    <div className="font-medium text-slate-200">
                                      {t.name}{' '}
                                      <span className={isSelected ? 'text-indigo-200' : 'text-slate-400'}>
                                        (@{t.username})
                                      </span>
                                    </div>
                                    {t.tuitions?.length > 0 && (
                                      <div className={`text-[10px] ${isSelected ? 'text-indigo-200' : 'text-slate-500'}`}>
                                        Tuitions: {t.tuitions.map(tu => tu.title).join(', ')}
                                      </div>
                                    )}
                                  </div>
                                  {isSelected && <span className="text-xs text-white">✓ Selected</span>}
                                </button>
                              );
                            })
                          )}
                        </div>
                      </div>
                    </div>
                  </div>
                )}
              </>
            )}

            <div>
              <label className="block text-xs font-semibold text-slate-300 mb-1">
                Password *
              </label>
              <div className="relative">
                <input
                  type="password"
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••"
                  className="w-full pl-9 pr-3 py-2.5 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
                />
                <Lock className="w-4 h-4 text-slate-500 absolute left-3 top-3" />
              </div>
            </div>

            {mode !== 'login' && (
              <div>
                <label className="block text-xs font-semibold text-slate-300 mb-1">
                  Confirm Password *
                </label>
                <div className="relative">
                  <input
                    type="password"
                    required
                    value={passwordConfirm}
                    onChange={(e) => setPasswordConfirm(e.target.value)}
                    placeholder="••••••••"
                    className="w-full pl-9 pr-3 py-2.5 rounded-xl bg-slate-800 border border-slate-700 text-slate-100 text-sm focus:outline-none focus:border-indigo-500 transition"
                  />
                  <Lock className="w-4 h-4 text-slate-500 absolute left-3 top-3" />
                </div>
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full mt-3 py-3 px-4 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-sm shadow-lg shadow-indigo-600/30 flex items-center justify-center gap-2 transition disabled:opacity-50"
            >
              {loading ? (
                <div className="w-5 h-5 rounded-full border-2 border-white/30 border-t-white animate-spin" />
              ) : (
                <>
                  <span>
                    {mode === 'login'
                      ? 'Sign In to Portal'
                      : mode === 'register-tutor'
                      ? 'Create Tutor Account'
                      : 'Register as Student'}
                  </span>
                  <ArrowRight className="w-4 h-4" />
                </>
              )}
            </button>
          </form>

          {/* Quick Demo Credentials */}
          {mode === 'login' && (
            <div className="mt-6 pt-5 border-t border-slate-800/80 space-y-2 text-center">
              <span className="text-[11px] text-slate-500 block">Quick Demo Logins:</span>
              <div className="grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={handleDemoTutor}
                  className="py-1.5 px-2 rounded-xl bg-slate-800/60 hover:bg-slate-800 border border-slate-700 text-[11px] text-indigo-300 font-semibold flex items-center justify-center gap-1.5 transition"
                >
                  <ShieldCheck className="w-3.5 h-3.5 text-indigo-400" />
                  <span>Admin Tutor</span>
                </button>
                <button
                  type="button"
                  onClick={handleDemoStudent}
                  className="py-1.5 px-2 rounded-xl bg-slate-800/60 hover:bg-slate-800 border border-slate-700 text-[11px] text-emerald-300 font-semibold flex items-center justify-center gap-1.5 transition"
                >
                  <User className="w-3.5 h-3.5 text-emerald-400" />
                  <span>Demo Student</span>
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
