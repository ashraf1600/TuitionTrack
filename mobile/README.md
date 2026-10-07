# TuitionTrack mobile app (Flutter)

The Android app for TuitionTrack. It uses the same REST API as the website (`/api/v1/`), so everything
done in one shows up in the other.

## What it does

**Tutors** — overview with the Tuition Wallet, today's classes from the weekly routine, requests to join;
tuition groups (create, edit, weekly routine, shared class tracker, start the next cycle, roster);
students (create with a one-time temporary password, edit, reset password, deactivate, add to a group);
exams and assignments (paste questions from ChatGPT, type them, use pictures, reuse past questions,
written questions and marking scheme, schedule, time limit, late work, negative marking, shuffle,
when results are published, drafts, copy, delete); submissions, marking and feedback; leaderboard.

**Students** — their groups and class progress, finding a tutor and sending a request, exams
(to do / upcoming / done), sitting an exam with a server-synced timer, typed answers and photo
uploads, auto-submit at the deadline, results (pending or fully marked), leaderboard.

**Everyone** — sign in with a username in any capitalisation or an email, create an account, forgot
password, forced change of a temporary password, profile, change password, sign out (this device or
all devices), notifications.

## Run it

Tools on this PC live on `D:` (Flutter in `D:\flutter`, Android SDK and JDK in `D:\Android`).
In Git Bash, load them first:

```bash
source /d/dev_downloads/env.sh
```

Start the backend so a phone can reach it (not just this PC):

```bash
cd backend && ../venv/Scripts/python.exe manage.py runserver 0.0.0.0:8000
```

Then, from `mobile/`:

```bash
flutter run                      # on a connected phone or emulator
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000   # in a browser
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

## Server address

The app asks the server at the address shown at the bottom of the sign-in screen; tap it to change it.

| Where the app runs | Address to enter |
| --- | --- |
| Android emulator | `http://10.0.2.2:8000` (the default) |
| A real phone on the same Wi-Fi | `http://<this PC's IP address>:8000` (find it with `ipconfig`) |
| Published server | `https://your-domain` |

To bake a different default into a build: `--dart-define=API_BASE_URL=https://your-domain`.

Plain `http://` is allowed so the app can reach a development server. Before publishing, put the
server behind https and remove `android:usesCleartextTraffic="true"` from
`android/app/src/main/AndroidManifest.xml`.

## Tests

```bash
flutter analyze
flutter test                     # question parser; the live test is skipped
```

`test/live_api_test.dart` exercises every server call end to end. It needs a running backend on a
throwaway copy of the database with the demo accounts:

```bash
LIVE_API=http://127.0.0.1:8011 DEMO_PW=<demo password> flutter test test/live_api_test.dart
```

## Layout

- `lib/core/` — API client (tokens, refresh, errors, uploads), session, server calls (`repo.dart`),
  the question parser (same rules as the website's `mcqParser.js`).
- `lib/widgets/` — theme, shared UI, maths rendering (`MathText` for plain text, `HtmlMath` for rich text), media.
- `lib/screens/` — `auth/`, `common/`, `student/`, `tutor/`.

## Not in the app yet

- Push notifications (the bell refreshes while the app is open).
- Rich-text editing of the written paper (tables, bold). Papers formatted on the website are shown and
  kept as they are; on the phone the written paper is typed as paragraphs with LaTeX.
- PDF uploads (pictures only).
- iOS has not been set up or built.
