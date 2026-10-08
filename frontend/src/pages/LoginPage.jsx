import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';
import { api } from '../api/client';
import {
  GraduationCap, Lock, User, Mail, Phone, ArrowRight, AlertCircle, Search, Eye, EyeOff,
  CalendarCheck, Wallet, FileText, Check, Loader2, BookOpen, Presentation, Sparkles,
} from 'lucide-react';

const inputCls =
  'w-full px-3.5 py-2.5 rounded-xl bg-slate-900/90 border border-slate-700/80 text-slate-100 text-base sm:text-sm placeholder:text-slate-500 focus:outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20 hover:border-slate-600 transition-all duration-200';

const HIGHLIGHTS = [
  { icon: CalendarCheck, title: 'One class tracker per group', text: 'Tick a class once — every student in the group sees it instantly, with the date and topic.' },
  { icon: Wallet, title: 'Earnings that add up themselves', text: 'Each completed class moves your tuition wallet. Full privacy: students never see fees.' },
  { icon: FileText, title: 'Integrated MCQ & Written Exams', text: 'Author rich exams with math formulas, set timers and deadlines, grade and rank in one place.' },
];

function Field({ label, htmlFor, optional, hint, children }) {
  return (
    <div>
      <label htmlFor={htmlFor} className="flex items-baseline justify-between text-xs font-semibold uppercase tracking-wider text-slate-300 mb-1.5">
        <span>{label}</span>
        {optional && <span className="text-[11px] font-normal lowercase tracking-normal text-slate-500">Optional</span>}
      </label>
      {children}
      {hint && <p className="mt-1 text-xs text-slate-400">{hint}</p>}
    </div>
  );
}

export default function LoginPage() {
  const [mode, setMode] = useState('login'); // 'login' | 'register-tutor' | 'register-student'
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  // Register extra fields
  const [email, setEmail] = useState('');
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [phone, setPhone] = useState('');
  const [passwordConfirm, setPasswordConfirm] = useState('');

  // Student specific
  const [gradeLevel, setGradeLevel] = useState('');
  const [institution, setInstitution] = useState('');
  const [address, setAddress] = useState('');
  const [selectedTutor, setSelectedTutor] = useState(null);
  const [tutorSearch, setTutorSearch] = useState('');
  const [tutorList, setTutorList] = useState([]);
  const [loadingTutors, setLoadingTutors] = useState(false);

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const { login, registerTutor, registerStudent } = useAuth();
  const navigate = useNavigate();

  const isRegister = mode !== 'login';
  const isStudent = mode === 'register-student';
  const passwordsDiffer = isRegister && passwordConfirm.length > 0 && password !== passwordConfirm;
  const passwordTooShort = isRegister && password.length > 0 && password.length < 8;

  // Tutor directory for student sign-up
  useEffect(() => {
    if (!isStudent) return undefined;
    const timeoutId = setTimeout(async () => {
      try {
        setLoadingTutors(true);
        const res = await api.getTutors(tutorSearch);
        setTutorList(Array.isArray(res) ? res : res.results || []);
      } catch (err) {
        console.error('Failed to load tutor directory:', err);
      } finally {
        setLoadingTutors(false);
      }
    }, 250);
    return () => clearTimeout(timeoutId);
  }, [isStudent, tutorSearch]);

  const switchMode = (next) => {
    setMode(next);
    setError('');
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');

    if (isRegister && password !== passwordConfirm) {
      setError('The two passwords do not match.');
      return;
    }

    setLoading(true);
    try {
      if (mode === 'register-tutor') {
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
          address,
          selected_tutor_id: selectedTutor?.id || '',
          selected_tutor_username: selectedTutor?.username || '',
        });
        navigate('/student');
      } else {
        const user = await login(username, password);
        navigate(user.role === 'TUTOR' ? '/tutor' : '/student');
      }
    } catch (err) {
      const message = err.message || '';
      setError(
        mode === 'login' && /no active account|credentials/i.test(message)
          ? 'Wrong username or password. Please try again.'
          : message || 'Something went wrong. Please try again.'
      );
    } finally {
      setLoading(false);
    }
  };

  if (mode === 'forgot') {
    return <ForgotPassword onBack={() => switchMode('login')} initialIdentifier={username} />;
  }

  const heading = mode === 'login' ? 'Welcome back' : isStudent ? 'Create your student account' : 'Create your tutor account';
  const subheading =
    mode === 'login'
      ? 'Sign in to your tuition dashboard.'
      : isStudent
      ? 'Join your tutor, follow your classes and take exams.'
      : 'Set up your groups, track classes and earnings.';

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 grid lg:grid-cols-2">
      {/* Brand panel (desktop) */}
      <aside className="hidden lg:flex flex-col justify-between p-12 bg-gradient-to-br from-indigo-950/60 via-slate-950 to-slate-950 border-r border-slate-800/80 relative overflow-hidden">
        <div className="absolute -top-32 -left-32 w-[520px] h-[520px] bg-indigo-600/15 rounded-full blur-[140px] pointer-events-none" />
        <div className="absolute top-1/2 -right-24 w-80 h-80 bg-violet-600/10 rounded-full blur-[100px] pointer-events-none" />

        <div className="relative flex items-center gap-3">
          <span className="w-11 h-11 rounded-2xl bg-gradient-to-tr from-indigo-600 to-violet-500 flex items-center justify-center text-white shadow-lg shadow-indigo-600/30">
            <GraduationCap className="w-6 h-6" />
          </span>
          <span className="text-2xl font-extrabold tracking-tight">Tuition<span className="text-indigo-400">Track</span></span>
        </div>

        <div className="relative space-y-8 max-w-lg">
          <div>
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-semibold bg-indigo-500/10 text-indigo-300 border border-indigo-500/20 mb-4">
              <Sparkles className="w-3.5 h-3.5 text-indigo-400" />
              <span>Smart Tuition Management & Exam Platform</span>
            </div>
            <h2 className="text-4xl font-extrabold leading-[1.18] tracking-tight text-white">
              Run your tuition groups <span className="text-gradient-brand">without the paper notebook</span>.
            </h2>
          </div>

          <ul className="space-y-4">
            {HIGHLIGHTS.map(({ icon: Icon, title, text }) => (
              <li key={title} className="flex gap-4 p-4 rounded-2xl bg-slate-900/60 border border-slate-800/80 backdrop-blur-md hover:border-slate-700 transition">
                <span className="w-10 h-10 rounded-xl bg-indigo-500/15 border border-indigo-500/25 text-indigo-300 flex items-center justify-center flex-shrink-0 shadow-sm">
                  <Icon className="w-5 h-5" />
                </span>
                <div>
                  <div className="text-sm font-semibold text-slate-100">{title}</div>
                  <p className="text-xs text-slate-400 leading-relaxed mt-0.5">{text}</p>
                </div>
              </li>
            ))}
          </ul>

          <div className="flex flex-wrap items-center gap-2 pt-2 text-[11px] text-slate-400">
            <span className="px-2.5 py-1 rounded-lg bg-slate-900 border border-slate-800">✓ Multi-Tenant Security</span>
            <span className="px-2.5 py-1 rounded-lg bg-slate-900 border border-slate-800">✓ Real-Time Routine Tracking</span>
            <span className="px-2.5 py-1 rounded-lg bg-slate-900 border border-slate-800">✓ KaTeX LaTeX Math Equations</span>
          </div>
        </div>

        <p className="relative text-xs text-slate-500">Built for private tutors, coaching centers, and students.</p>
      </aside>

      {/* Form panel */}
      <main className="flex flex-col justify-center px-4 py-10 sm:px-10 bg-slate-950 relative">
        <div className="w-full max-w-md mx-auto">
          <div className="lg:hidden flex items-center gap-2.5 mb-8">
            <span className="w-10 h-10 rounded-xl bg-gradient-to-tr from-indigo-600 to-violet-500 flex items-center justify-center text-white shadow-md shadow-indigo-600/25">
              <GraduationCap className="w-5 h-5" />
            </span>
            <span className="text-xl font-extrabold tracking-tight">Tuition<span className="text-indigo-400">Track</span></span>
          </div>

          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">{heading}</h1>
          <p className="mt-1.5 text-sm text-slate-400">{subheading}</p>

          {/* Role choice when creating an account */}
          {isRegister && (
            <div className="mt-6 grid grid-cols-2 gap-3" role="radiogroup" aria-label="Account type">
              {[
                { key: 'register-tutor', icon: Presentation, title: "I'm a tutor", text: 'I teach groups & track fees' },
                { key: 'register-student', icon: BookOpen, title: "I'm a student", text: 'I attend classes & take exams' },
              ].map(({ key, icon: Icon, title, text }) => {
                const active = mode === key;
                return (
                  <button
                    key={key}
                    type="button"
                    role="radio"
                    aria-checked={active}
                    onClick={() => switchMode(key)}
                    className={`text-left p-3.5 rounded-2xl border transition-all duration-200 ${
                      active
                        ? 'bg-indigo-500/10 border-indigo-500 ring-2 ring-indigo-500/25 shadow-lg shadow-indigo-500/10'
                        : 'bg-slate-900/80 border-slate-800 hover:border-slate-700 hover:bg-slate-900'
                    }`}
                  >
                    <Icon className={`w-5 h-5 mb-1.5 ${active ? 'text-indigo-300' : 'text-slate-400'}`} />
                    <div className="text-sm font-semibold text-slate-100">{title}</div>
                    <div className="text-xs text-slate-400">{text}</div>
                  </button>
                );
              })}
            </div>
          )}

          {error && (
            <div role="alert" className="mt-6 p-3.5 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-200 text-sm flex items-start gap-2.5">
              <AlertCircle className="w-5 h-5 flex-shrink-0 text-rose-400 mt-0.5" />
              <span>{error}</span>
            </div>
          )}

          <form onSubmit={handleSubmit} className="mt-6 space-y-4" noValidate={false}>
            {isRegister && (
              <div className="grid grid-cols-2 gap-3">
                <Field label="First name" htmlFor="first-name">
                  <input id="first-name" type="text" required autoComplete="given-name" value={firstName} onChange={(e) => setFirstName(e.target.value)} className={inputCls} />
                </Field>
                <Field label="Last name" htmlFor="last-name" optional>
                  <input id="last-name" type="text" autoComplete="family-name" value={lastName} onChange={(e) => setLastName(e.target.value)} className={inputCls} />
                </Field>
              </div>
            )}

            <Field
              label="Username"
              htmlFor="username"
              hint={isRegister ? 'You will use this to sign in.' : undefined}
            >
              <div className="relative">
                <User className="w-4 h-4 text-slate-500 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                <input
                  id="username"
                  type="text"
                  required
                  autoComplete="username"
                  autoCapitalize="none"
                  spellCheck={false}
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  className={`${inputCls} pl-10`}
                />
              </div>
            </Field>

            {isRegister && (
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <Field label="Email" htmlFor="email" optional>
                  <div className="relative">
                    <Mail className="w-4 h-4 text-slate-500 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                    <input id="email" type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" className={`${inputCls} pl-10`} />
                  </div>
                </Field>
                <Field label="Phone" htmlFor="phone" optional>
                  <div className="relative">
                    <Phone className="w-4 h-4 text-slate-500 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                    <input id="phone" type="tel" autoComplete="tel" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="01XXXXXXXXX" className={`${inputCls} pl-10`} />
                  </div>
                </Field>
              </div>
            )}

            {isStudent && (
              <>
                <div className="grid grid-cols-2 gap-3">
                  <Field label="Class" htmlFor="grade" optional>
                    <input id="grade" type="text" value={gradeLevel} onChange={(e) => setGradeLevel(e.target.value)} placeholder="e.g. Class 10" className={inputCls} />
                  </Field>
                  <Field label="School / college" htmlFor="institution" optional>
                    <input id="institution" type="text" value={institution} onChange={(e) => setInstitution(e.target.value)} className={inputCls} />
                  </Field>
                </div>
                <Field label="Address" htmlFor="address" optional>
                  <input id="address" type="text" autoComplete="street-address" value={address} onChange={(e) => setAddress(e.target.value)} placeholder="Area, city" className={inputCls} />
                </Field>

                {/* Tutor picker */}
                <div className="rounded-xl border border-slate-700 bg-slate-900/60 p-4">
                  <div className="flex items-baseline justify-between mb-1">
                    <span className="text-sm font-medium text-slate-200">Your tutor</span>
                    <span className="text-xs text-slate-500">Optional</span>
                  </div>
                  <p className="text-xs text-slate-400 mb-3">
                    We send them a request. When they accept and add you to a group, your classes appear. You can also do this later.
                  </p>

                  {selectedTutor ? (
                    <div className="flex items-center justify-between gap-3 p-3 rounded-lg bg-indigo-500/10 border border-indigo-500/40">
                      <div className="min-w-0">
                        <div className="text-sm font-semibold text-slate-100 truncate flex items-center gap-1.5">
                          <Check className="w-4 h-4 text-indigo-300 flex-shrink-0" />
                          {selectedTutor.name}
                        </div>
                        <div className="text-xs text-slate-400 truncate">@{selectedTutor.username}</div>
                      </div>
                      <button type="button" onClick={() => setSelectedTutor(null)} className="text-xs font-medium text-indigo-300 hover:text-white underline underline-offset-2">
                        Change
                      </button>
                    </div>
                  ) : (
                    <>
                      <div className="relative">
                        <Search className="w-4 h-4 text-slate-500 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                        <input
                          type="search"
                          aria-label="Search tutors"
                          value={tutorSearch}
                          onChange={(e) => setTutorSearch(e.target.value)}
                          placeholder="Search by name or subject"
                          className={`${inputCls} pl-10`}
                        />
                      </div>
                      <div className="mt-2 max-h-40 overflow-y-auto space-y-1">
                        {loadingTutors ? (
                          <p className="flex items-center gap-2 py-2 text-xs text-slate-400"><Loader2 className="w-3.5 h-3.5 animate-spin" /> Searching…</p>
                        ) : tutorList.length === 0 ? (
                          <p className="py-2 text-xs text-slate-500">No tutors match that search.</p>
                        ) : (
                          tutorList.map((t) => (
                            <button
                              type="button"
                              key={t.id}
                              onClick={() => setSelectedTutor(t)}
                              className="w-full text-left px-3 py-2 rounded-lg hover:bg-slate-800 border border-transparent hover:border-slate-700 transition"
                            >
                              <div className="text-sm font-medium text-slate-100">
                                {t.name} <span className="text-xs font-normal text-slate-500">@{t.username}</span>
                              </div>
                              {t.tuitions?.length > 0 && (
                                <div className="text-xs text-slate-400 truncate">{t.tuitions.map((tu) => tu.title).join(' · ')}</div>
                              )}
                            </button>
                          ))
                        )}
                      </div>
                    </>
                  )}
                </div>
              </>
            )}

            <Field
              label="Password"
              htmlFor="password"
              hint={isRegister ? (passwordTooShort ? undefined : 'At least 8 characters.') : undefined}
            >
              <div className="relative">
                <Lock className="w-4 h-4 text-slate-500 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                <input
                  id="password"
                  type={showPassword ? 'text' : 'password'}
                  required
                  minLength={isRegister ? 8 : undefined}
                  autoComplete={isRegister ? 'new-password' : 'current-password'}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className={`${inputCls} pl-10 pr-11`}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword((v) => !v)}
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                  className="absolute right-1.5 top-1/2 -translate-y-1/2 p-2 rounded-lg text-slate-400 hover:text-slate-100"
                >
                  {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
              {passwordTooShort && <p className="mt-1 text-xs text-amber-300">Use at least 8 characters.</p>}
              {mode === 'login' && (
                <button
                  type="button"
                  onClick={() => switchMode('forgot')}
                  className="mt-1.5 text-xs font-medium text-indigo-300 hover:text-white underline underline-offset-2"
                >
                  Forgot your password?
                </button>
              )}
            </Field>

            {isRegister && (
              <Field label="Confirm password" htmlFor="password-confirm">
                <div className="relative">
                  <Lock className="w-4 h-4 text-slate-500 absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                  <input
                    id="password-confirm"
                    type={showPassword ? 'text' : 'password'}
                    required
                    autoComplete="new-password"
                    value={passwordConfirm}
                    onChange={(e) => setPasswordConfirm(e.target.value)}
                    aria-invalid={passwordsDiffer}
                    className={`${inputCls} pl-10 ${passwordsDiffer ? 'border-rose-500 focus:border-rose-500 focus:ring-rose-500/25' : ''}`}
                  />
                </div>
                {passwordsDiffer && <p className="mt-1 text-xs text-rose-300">The passwords do not match yet.</p>}
              </Field>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full !mt-6 py-3 px-4 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-sm shadow-lg shadow-indigo-600/25 flex items-center justify-center gap-2 transition disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {loading ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  <span>{mode === 'login' ? 'Signing in…' : 'Creating account…'}</span>
                </>
              ) : (
                <>
                  <span>{mode === 'login' ? 'Sign in' : 'Create account'}</span>
                  <ArrowRight className="w-4 h-4" />
                </>
              )}
            </button>
          </form>

          <p className="mt-6 text-sm text-slate-400 text-center">
            {mode === 'login' ? (
              <>
                New to TuitionTrack?{' '}
                <button type="button" onClick={() => switchMode('register-tutor')} className="font-semibold text-indigo-300 hover:text-white underline underline-offset-2">
                  Create an account
                </button>
              </>
            ) : (
              <>
                Already have an account?{' '}
                <button type="button" onClick={() => switchMode('login')} className="font-semibold text-indigo-300 hover:text-white underline underline-offset-2">
                  Sign in
                </button>
              </>
            )}
          </p>
        </div>
      </main>
    </div>
  );
}

function ForgotPassword({ onBack, initialIdentifier = '' }) {
  const [identifier, setIdentifier] = useState(initialIdentifier);
  const [sending, setSending] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setSending(true);
    try {
      const res = await api.requestPasswordReset(identifier.trim());
      setMessage(res.message);
    } catch (err) {
      setError(err.message || 'Could not send the reset link.');
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex items-center justify-center px-4 py-10">
      <div className="w-full max-w-md">
        <div className="flex items-center gap-2.5 mb-8">
          <span className="w-10 h-10 rounded-xl bg-indigo-600 flex items-center justify-center text-white">
            <GraduationCap className="w-5 h-5" />
          </span>
          <span className="text-xl font-bold tracking-tight">Tuition<span className="text-indigo-400">Track</span></span>
        </div>

        <h1 className="text-2xl font-extrabold tracking-tight">Forgot your password?</h1>
        <p className="mt-1.5 text-sm text-slate-400">
          Enter your username or email and we will email you a link to choose a new one.
        </p>

        {message ? (
          <div className="mt-6 p-4 rounded-xl bg-emerald-500/10 border border-emerald-500/30 text-emerald-100 text-sm flex items-start gap-2.5">
            <Check className="w-5 h-5 flex-shrink-0 text-emerald-400" />
            <span>{message}</span>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="mt-6 space-y-4">
            {error && (
              <div role="alert" className="p-3.5 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-200 text-sm flex items-start gap-2.5">
                <AlertCircle className="w-5 h-5 flex-shrink-0 text-rose-400" />
                <span>{error}</span>
              </div>
            )}
            <Field label="Username or email" htmlFor="reset-identifier">
              <input
                id="reset-identifier"
                type="text"
                required
                autoCapitalize="none"
                spellCheck={false}
                value={identifier}
                onChange={(e) => setIdentifier(e.target.value)}
                className={inputCls}
              />
            </Field>
            <button
              type="submit"
              disabled={sending}
              className="w-full py-3 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-sm flex items-center justify-center gap-2 transition disabled:opacity-60"
            >
              {sending && <Loader2 className="w-4 h-4 animate-spin" />}
              Email me a reset link
            </button>
          </form>
        )}

        <p className="mt-5 text-xs text-slate-400">
          Student with no email on your account? Ask your tutor — they can give you a new temporary password.
        </p>
        <button type="button" onClick={onBack} className="mt-4 text-sm font-semibold text-indigo-300 hover:text-white underline underline-offset-2">
          Back to sign in
        </button>
      </div>
    </div>
  );
}
