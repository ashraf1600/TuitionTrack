import React from 'react';
import { Link } from 'react-router-dom';
import Logo from '../components/common/Logo';

/**
 * Public privacy policy (/privacy) and terms of use (/terms). Google's sign-in
 * consent screen links to both, so they must stay reachable without signing in.
 */

const UPDATED = '6 November 2026';
const CONTACT = 'https://www.facebook.com/TuitionTrackApp';

const PRIVACY = [
  {
    title: 'What we collect',
    items: [
      'Account details you give us: name, username, email, phone number and, for students, class, institution and a parent’s contact.',
      'If you sign in with Google: your name, email address and profile photo from Google. We do not get your Google password or access to anything else in your Google account.',
      'What you and your tutor or students enter while using TuitionTrack: tuitions, class records, payments, homework, tests and answers, results, chat messages and photos you upload.',
      'A notification token for your phone, so we can send you messages and reminders.',
    ],
  },
  {
    title: 'How we use it',
    items: [
      'To run the app: show tutors their tuitions and students, show students their classes, tests and results, and deliver chat messages and reminders.',
      'To keep your account secure and to fix problems.',
      'We do not sell your information, show ads, or share it with advertisers.',
    ],
  },
  {
    title: 'Who can see it',
    items: [
      'A tutor sees the students they teach and what those students submit. A student sees their own records and what their tutor shares with them.',
      'Students never see the private names a tutor gives to tuitions.',
      'Our service providers store and deliver the data for us: our hosting and database providers, file storage for photos, and Google Firebase for phone notifications. They may not use it for anything else.',
    ],
  },
  {
    title: 'Keeping and deleting your data',
    items: [
      'We keep your data while your account is open.',
      'You can ask us to delete your account and its data at any time by messaging our Facebook page. We delete it within 30 days, apart from anything we must keep by law.',
    ],
  },
  {
    title: 'Children',
    items: [
      'Many students are under 18. A student account should be set up with the knowledge of a parent or guardian, who can ask us to see or delete the student’s data.',
    ],
  },
];

const TERMS = [
  {
    title: 'Using TuitionTrack',
    items: [
      'TuitionTrack is a free app and website for private tutors, coaching centres and their students.',
      'Keep your password safe. You are responsible for what happens in your account.',
      'Only add students you actually teach, and only with their (or their parent’s) agreement.',
    ],
  },
  {
    title: 'Your content',
    items: [
      'What you enter stays yours. You give us permission to store it and show it to the people it is shared with in the app, only so the app can work.',
      'Do not upload anything illegal, abusive, or that you do not have the right to share.',
    ],
  },
  {
    title: 'Payments between tutors and students',
    items: [
      'TuitionTrack only records payments. It does not handle money, and we are not part of any agreement between a tutor and a student.',
    ],
  },
  {
    title: 'No guarantee',
    items: [
      'We work to keep TuitionTrack running and your data safe, but the service is provided as it is, without any guarantee. Keep your own copy of anything important.',
      'We may change these terms. We will show the date of the latest change on this page.',
    ],
  },
];

export default function PolicyPage({ kind }) {
  const isPrivacy = kind === 'privacy';
  const sections = isPrivacy ? PRIVACY : TERMS;
  const title = isPrivacy ? 'Privacy policy' : 'Terms of use';

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      <header className="max-w-3xl mx-auto px-4 sm:px-6 py-5 flex items-center justify-between">
        <Link to="/login" className="flex items-center gap-2.5">
          <Logo size={32} />
          <span className="text-lg font-extrabold tracking-tight">Tuition<span className="text-indigo-400">Track</span></span>
        </Link>
        <Link to={isPrivacy ? '/terms' : '/privacy'} className="text-sm font-semibold text-slate-400 hover:text-white">
          {isPrivacy ? 'Terms of use' : 'Privacy policy'}
        </Link>
      </header>

      <main className="max-w-3xl mx-auto px-4 sm:px-6 pb-16">
        <h1 className="mt-4 text-3xl sm:text-4xl font-extrabold tracking-tight text-white">{title}</h1>
        <p className="mt-2 text-sm text-slate-500">Last updated {UPDATED}</p>

        {sections.map((section) => (
          <section key={section.title} className="mt-8">
            <h2 className="text-lg font-bold text-white">{section.title}</h2>
            <ul className="mt-3 space-y-2 list-disc pl-5 text-slate-300 leading-relaxed">
              {section.items.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </section>
        ))}

        <section className="mt-8">
          <h2 className="text-lg font-bold text-white">Contact</h2>
          <p className="mt-3 text-slate-300 leading-relaxed">
            Questions or requests: message us on{' '}
            <a href={CONTACT} target="_blank" rel="noreferrer" className="text-indigo-300 hover:text-indigo-200 underline">
              facebook.com/TuitionTrackApp
            </a>
            .
          </p>
        </section>
      </main>
    </div>
  );
}
