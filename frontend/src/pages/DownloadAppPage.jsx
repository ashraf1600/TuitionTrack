import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowRight, BellRing, Download, ExternalLink, ShieldCheck, Smartphone, WifiOff } from 'lucide-react';
import Logo from '../components/common/Logo';

/**
 * Public page for the Android app: the latest APK (always the newest release
 * on GitHub), a QR code for phones, what the app looks like (real screens),
 * and how to install it. Open to everyone at /app.
 */

const REPO = 'ashraf1600/TuitionTrack';
// GitHub always serves the newest release's file at this address, so the button never goes stale.
const LATEST_APK = `https://github.com/${REPO}/releases/latest/download/TuitionTrack.apk`;
const LATEST_APK_ARM64 = `https://github.com/${REPO}/releases/latest/download/TuitionTrack-arm64.apk`;
const FACEBOOK = 'https://www.facebook.com/TuitionTrackApp';

// Real screens from the app (dark theme), as cards.
const SCREENS = [
  { src: '/app/overview.webp', title: 'Your day at a glance', text: 'Classes today, what is left to collect, and what needs checking.', who: 'Tutor' },
  { src: '/app/tuition.webp', title: 'Mark a class in one tap', text: 'Each tuition counts its own classes: 7 of 12 done, 5 to go.', who: 'Tutor' },
  { src: '/app/wallet.webp', title: 'Who paid, who has not', text: 'When a cycle ends the payment is due, and a reminder goes out by itself.', who: 'Tutor' },
  { src: '/app/student-classes.webp', title: 'The same tracker for students', text: 'Students see every class their Sir marks, date by date.', who: 'Student' },
  { src: '/app/student-home.webp', title: 'Tests that feel like a paper', text: 'Live MCQ and written tests with a timer, right on the phone.', who: 'Student' },
  { src: '/app/result.webp', title: 'Results the moment they are out', text: 'Score, rank and every question explained.', who: 'Student' },
];

const STEPS = [
  { title: 'Download', text: 'Tap “Download for Android”. The file is TuitionTrack.apk.' },
  { title: 'Allow the install', text: 'Open the file. If Android asks, allow your browser to “Install unknown apps”.' },
  { title: 'Sign in', text: 'Use the same username or Google account as on this website.' },
];

function formatSize(bytes) {
  if (!bytes) return '';
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDate(iso) {
  if (!iso) return '';
  try {
    return new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  } catch {
    return '';
  }
}

/** The newest release (version, size, date). Null until known; the download works either way. */
function useLatestRelease() {
  const [release, setRelease] = useState(null);
  useEffect(() => {
    let alive = true;
    fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers: { Accept: 'application/vnd.github+json' } })
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (!alive || !data) return;
        const apk = (data.assets || []).find((a) => a.name === 'TuitionTrack.apk');
        setRelease({
          version: String(data.tag_name || '').replace(/^v/, ''),
          date: data.published_at,
          size: apk?.size,
        });
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, []);
  return release;
}

function PhoneCard({ screen }) {
  return (
    <figure className="snap-start shrink-0 w-[250px] sm:w-auto rounded-3xl bg-slate-900/70 border border-slate-800 p-4 shadow-xl shadow-black/30 flex flex-col">
      <div className="mx-auto w-[196px] rounded-[30px] bg-slate-950 p-[7px] ring-1 ring-slate-700/70 shadow-lg shadow-black/50">
        <img
          src={screen.src}
          alt={`TuitionTrack app: ${screen.title}`}
          width={216}
          height={468}
          loading="lazy"
          className="block w-full rounded-[23px]"
        />
      </div>
      <figcaption className="mt-4 px-1">
        <span className="inline-block text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-md bg-indigo-500/10 text-indigo-300 border border-indigo-500/20">
          {screen.who}
        </span>
        <div className="mt-2 text-[15px] font-bold text-white leading-snug">{screen.title}</div>
        <p className="mt-1 text-[13px] text-slate-400 leading-relaxed">{screen.text}</p>
      </figcaption>
    </figure>
  );
}

export default function DownloadAppPage() {
  const release = useLatestRelease();
  const meta = [
    release?.version && `Version ${release.version}`,
    release?.size && formatSize(release.size),
    release?.date && `Updated ${formatDate(release.date)}`,
  ].filter(Boolean);

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      <header className="max-w-6xl mx-auto px-4 sm:px-6 py-5 flex items-center justify-between">
        <Link to="/login" className="flex items-center gap-2.5">
          <Logo size={36} />
          <span className="text-xl font-extrabold tracking-tight">Tuition<span className="text-indigo-400">Track</span></span>
        </Link>
        <Link to="/login" className="text-sm font-semibold text-slate-300 hover:text-white px-3 py-2 rounded-xl hover:bg-slate-900">
          Sign in on the web
        </Link>
      </header>

      {/* Hero */}
      <section className="relative overflow-hidden">
        <div className="absolute -top-40 left-1/2 -translate-x-1/2 w-[720px] h-[720px] bg-indigo-600/15 rounded-full blur-[160px] pointer-events-none" />
        <div className="relative max-w-6xl mx-auto px-4 sm:px-6 pt-8 pb-14 grid lg:grid-cols-[1.1fr_0.9fr] gap-10 items-center">
          <div>
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-semibold bg-indigo-500/10 text-indigo-300 border border-indigo-500/20">
              <Smartphone className="w-3.5 h-3.5" /> Android app · free
            </div>
            <h1 className="mt-4 text-4xl sm:text-5xl font-extrabold leading-[1.1] tracking-tight text-white">
              Your tuitions, <span className="text-gradient-brand">in your pocket</span>.
            </h1>
            <p className="mt-4 text-base sm:text-lg text-slate-400 leading-relaxed max-w-xl">
              Mark classes, see who has paid, set homework and tests, and chat with students. Students follow their
              classes, take tests and get results. The same account as this website.
            </p>

            <div className="mt-7 flex flex-col sm:flex-row sm:items-center gap-3">
              <a
                href={LATEST_APK}
                className="inline-flex items-center justify-center gap-2.5 px-6 py-3.5 rounded-2xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-base shadow-lg shadow-indigo-600/30 transition"
              >
                <Download className="w-5 h-5" /> Download for Android
              </a>
              <a
                href={LATEST_APK_ARM64}
                className="inline-flex items-center justify-center px-4 py-3 rounded-2xl text-sm font-semibold text-slate-300 border border-slate-800 hover:border-slate-700 hover:bg-slate-900"
              >
                Smaller file (newer phones)
              </a>
            </div>
            <p className="mt-3 text-xs text-slate-500">
              {meta.length ? `${meta.join(' · ')} · ` : ''}Android 7.0 or newer. The app tells you when an update is out.
            </p>

            <ul className="mt-8 grid sm:grid-cols-3 gap-3 max-w-2xl">
              {[
                { icon: BellRing, text: 'Messages and payment reminders, even with the app closed' },
                { icon: WifiOff, text: 'Opens without internet; changes are sent when you are back online' },
                { icon: ShieldCheck, text: 'Students see their tutor as “Sir”, never the tuition’s name' },
              ].map(({ icon: Icon, text }) => (
                <li key={text} className="flex gap-3 items-start p-3 rounded-2xl bg-slate-900/50 border border-slate-800/80">
                  <Icon className="w-4 h-4 mt-0.5 text-indigo-300 shrink-0" />
                  <span className="text-xs text-slate-300 leading-relaxed">{text}</span>
                </li>
              ))}
            </ul>
          </div>

          {/* QR for someone reading this on a computer */}
          <div className="hidden md:flex justify-center">
            <div className="rounded-3xl bg-slate-900/70 border border-slate-800 p-6 text-center shadow-2xl shadow-black/40 max-w-xs">
              <div className="rounded-2xl bg-white p-3">
                <img src="/app/download-qr.svg" alt="QR code: download the TuitionTrack app" width={220} height={220} className="block mx-auto" />
              </div>
              <div className="mt-4 text-sm font-bold text-white">On a computer?</div>
              <p className="mt-1 text-xs text-slate-400 leading-relaxed">Scan with your phone’s camera to download the app straight to it.</p>
            </div>
          </div>
        </div>
      </section>

      {/* What it looks like */}
      <section className="max-w-6xl mx-auto px-4 sm:px-6 py-12 border-t border-slate-900">
        <h2 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">See it on the phone</h2>
        <p className="mt-2 text-sm text-slate-400">Real screens from the app.</p>
        <div className="mt-6 -mx-4 px-4 sm:mx-0 sm:px-0 flex sm:grid sm:grid-cols-2 lg:grid-cols-3 gap-4 overflow-x-auto sm:overflow-visible snap-x snap-mandatory pb-2">
          {SCREENS.map((screen) => (
            <PhoneCard key={screen.src} screen={screen} />
          ))}
        </div>
      </section>

      {/* How to install */}
      <section className="max-w-6xl mx-auto px-4 sm:px-6 py-12 border-t border-slate-900">
        <h2 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">Install in a minute</h2>
        <ol className="mt-6 grid sm:grid-cols-3 gap-4">
          {STEPS.map((step, i) => (
            <li key={step.title} className="p-5 rounded-2xl bg-slate-900/60 border border-slate-800">
              <span className="w-8 h-8 rounded-xl bg-indigo-500/15 border border-indigo-500/25 text-indigo-300 flex items-center justify-center text-sm font-bold">
                {i + 1}
              </span>
              <div className="mt-3 font-bold text-white">{step.title}</div>
              <p className="mt-1 text-sm text-slate-400 leading-relaxed">{step.text}</p>
            </li>
          ))}
        </ol>
        <div className="mt-8 flex flex-col sm:flex-row gap-3">
          <a
            href={LATEST_APK}
            className="inline-flex items-center justify-center gap-2 px-5 py-3 rounded-2xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold shadow-lg shadow-indigo-600/25"
          >
            <Download className="w-4 h-4" /> Download for Android
          </a>
          <a
            href={FACEBOOK}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center justify-center gap-2 px-5 py-3 rounded-2xl text-sm font-semibold text-slate-300 border border-slate-800 hover:bg-slate-900"
          >
            Follow on Facebook <ExternalLink className="w-4 h-4" />
          </a>
          <Link
            to="/login"
            className="inline-flex items-center justify-center gap-2 px-5 py-3 rounded-2xl text-sm font-semibold text-slate-300 hover:text-white"
          >
            Use the website instead <ArrowRight className="w-4 h-4" />
          </Link>
        </div>
      </section>

      <footer className="max-w-6xl mx-auto px-4 sm:px-6 py-8 text-xs text-slate-600 border-t border-slate-900">
        TuitionTrack · for private tutors, coaching centres and their students ·{' '}
        <Link to="/privacy" className="hover:text-slate-400">Privacy</Link> ·{' '}
        <Link to="/terms" className="hover:text-slate-400">Terms</Link>
      </footer>
    </div>
  );
}
