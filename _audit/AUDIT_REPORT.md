# TuitionTrack full-stack audit — branch `audit/full-stack-fixes`

Base: `main` @ `93f9835` (identical to your local working tree). 14 commits, 87 files, +3157 / −1776.

## Get the branch

From `D:\Django_The_Last_Hope_Phitron\TuitionTrack` (PowerShell or Git Bash):

```bash
git fetch _audit/audit-full-stack-fixes.bundle audit/full-stack-fixes:audit/full-stack-fixes
git checkout audit/full-stack-fixes
# optional: git push -u origin audit/full-stack-fixes   (needs a token with the "workflow" scope, see below)
```

`_audit/patches/*.patch` holds the same commits for `git am` if you prefer. Delete the `_audit` folder afterwards.

## Findings and fixes

| ID | Sev | Area | File(s) | Problem | Fix applied |
|---|---|---|---|---|---|
| B1 | Critical | Backend | students/views.py | Students could PATCH/DELETE their tutor's weekly routines and dated classes | Writes are tutor-only (`_TutorWritesViewSet`) |
| B2 | Critical | Backend | students/serializers.py | Routines, classes and homework accepted any student/tuition id → a tutor could attach rows to another tutor's group/student | Targets validated against the tutor's own groups and manageable students |
| B3 | High | Backend | students/views.py, models.py | A student's submission on shared group homework was written onto the row every classmate sees (overwriting theirs) | Submitting creates the student's own copy (`Homework.group_source`, migration 0014); student lists show the copy instead of the shared row |
| B4 | High | Backend | students/serializers.py | `PATCH /homework/<id>/` with only a title always failed validation | Partial updates keep the existing target |
| B5 | High | Backend | students/views.py | Homework file submissions had no type/size/content check | Shared upload validator; file URL returned as `submission_file_url` |
| B6 | High | Backend | analytics/views.py | "Payment due" notification showed each student the whole group's fee | Amount removed for group cycles |
| B7 | High | Backend | exams/models.py | `Exam.save` swallowed sanitizer errors and stored raw HTML | Fails closed |
| B8 | High | Backend | students/serializers.py | A student's private tutor notes / fee were returned to every other tutor they were connected to | Owner-only fields hidden from other tutors |
| B9 | Medium | Backend | config/settings.py | Any `*.onrender.com` site was a trusted CORS/CSRF origin, with credentials | Only `FRONTEND_URL` / env-listed origins; `CORS_ALLOW_CREDENTIALS=False` |
| B10 | Medium | Backend | exams/uploads.py, views.py | Upload magic bytes not matched to extension (PDF as .png, WAV as .webp passed) | One validator, magic must match extension |
| B11 | Medium | Backend | exams/views.py | Exam notification e-mail HTML interpolated tutor text unescaped | Escaped |
| B12 | Medium | Backend | exams/serializers.py | Answer-sheet URLs allowed any scheme except a small blocklist; solution link unchecked | http(s) or server path only |
| B13 | Medium | Backend | students/views.py, serializers.py | Tuition list did several queries per group; mutation responses could show stale wallet after the prefetch | Prefetch cycles + members; responses re-read |
| B14 | Medium | Backend | students/serializers.py | Tuition `routine` JSON unvalidated | Validated and normalised (`Saturday`, `HH:MM`, end > start) |
| B15 | Medium | Backend | cycles/models.py | `ensure_active` raced into an IntegrityError (500) | Savepoint + re-read |
| B16 | Medium | Backend | students/views.py | Atomicity: tutor "split per student" was N client calls + delete | `POST /homework/<id>/split/`, one transaction |
| B17 | Medium | Backend | students/serializers.py | Connected-tutor card exposed the tutor's other groups' routines (and the web built the student's schedule from them) | Only the student's own groups |
| B18 | Medium | Backend | analytics/views.py, cycles/models.py | Money summed as float | Decimal |
| B19 | Low | Backend | students/views.py | `?tutor_id=bad` → 500 | 400 |
| B20 | Low | Backend | models/migration 0014 | Missing indexes on hot filters | 5 composite indexes, additive migration |
| B21 | Low | Backend | exams/serializers.py, views.py | Re-grade not atomic; tutor exam list counted members per exam | Atomic; counted in the list query |
| B22 | Low | Backend | many | ruff: unused imports/vars, missing exception chaining; no config | `backend/ruff.toml`, clean |
| B23 | Low | Backend | settings | Test suite 204 s | Fast hasher in tests (~45 s) |
| F1 | High | Web | api/client.js | Hidden `localStorage.tuitiontrack_api_url` override could redirect all requests/passwords | Removed |
| F2 | High | Web | context/AuthContext.jsx | Any `/auth/me/` failure (even offline) signed the user out | Only 401/403 does |
| F3 | High | Web | api/client.js | A failed refresh call (offline/5xx) signed the user out; failed later page made a silently short list | Only 400/401 ends the session; page failure is an error |
| F4 | High | Web | TuitionWorkspace.jsx | Roster "Password" button did nothing (modal never rendered) | Opens the reset dialog |
| F5 | Medium | Web | StudentPortal, TutorDashboard, TuitionWorkspace, HomeworkManager | API failures shown as empty lists; "refreshed" toast even when everything failed | Error states with retry (`components/common/States.jsx`); workspace loads in parallel |
| F6 | Medium | Web | ExamCard, client.js | A HEAD /auth/me/ clock request per exam card | One cached `/meta/` measurement |
| F7 | Medium | Web | ExamTakerModal | Draft save crashed on full/blocked storage; ref written during render | try/catch; `useEffectEvent` |
| F8 | Medium | Web | LeaderboardModal, LoginPage | Stale responses could overwrite newer ones | Request guards |
| F9 | Medium | Web | Navbar, TutorWorkspaceView | Horizontal scroll on 390 px phones | Fits |
| F10 | Medium | Web | HomeworkCard | Unreadable translucent cards on the light student page | Solid cards |
| F11 | Medium | Web | HomeworkManager | Tutors could not open an uploaded homework file | Link shown |
| F12 | Medium | Web | index.html | KaTeX CSS 0.16.9 from CDN vs katex 0.19 JS | Bundled CSS |
| F13 | Medium | Web | App.jsx, vite.config.js | Whole app in one 378 kB entry; chunk rules lumped lucide/tiptap into vendor-react | Lazy role pages (entry 42 kB), fixed chunking |
| F14 | Low | Web | many | 138 lint warnings, 3 dead components, App.css, unused deps (clsx, tailwind-merge), pinned rolldown binding | 22 warnings left (see risks); dead code removed |
| F15 | Low | Web | — | No tests | Vitest: API client, MCQ parser/rules, dates (18 tests) |
| F16 | Low | Web | tailwind.config.js | No semantic tokens | `success/warning/danger/info/surface`, `rounded-card`, shared States/useNow |
| M1 | High | Mobile | homework_card.dart, connect.dart | Tutors could not see what a student handed in | Open link / open file buttons |
| M2 | High | Mobile | AndroidManifest.xml, main.dart | Release APK allowed cleartext http and defaulted to `http://10.0.2.2:8000` | Release is https-only and defaults to the hosted API; http stays for debug/profile |
| M3 | Medium | Mobile | homework_tab.dart | Split was N creates + delete; its success toast never showed | Uses the atomic split endpoint |
| M4 | Medium | Mobile | exam_take_screen.dart | Exam drafts shared between accounts on one phone; unexpected error left "Turn in" stuck | Per-account key; generic catch |
| M5 | Low | Mobile | exam_editor, homework_card | setState after await without `mounted` | Guarded |
| M6 | Low | Mobile | api.dart | Address without scheme always became http | https unless local |
| C1 | High | CI | build-apk.yml | Pinned Flutter 3.27.4 (Dart 3.6) but pubspec needs Dart ≥ 3.13.5 → `pub get` fails; analyze `|| true` | Current stable, analyze + test enforced, API URL dart-define |
| C2 | Medium | CI | ci.yml (new) | No CI for backend/web/mobile | Lint, checks, tests, build for all three |
| C3 | Medium | Infra | render.yaml | Web build deleted the lockfile | `npm ci` |

## Commands and results (final run)

| Command | Result |
|---|---|
| `ruff check .` (backend) | All checks passed |
| `python manage.py check` / `check --deploy` | 0 issues / 2 HSTS warnings (subdomains, preload: domain decision) |
| `makemigrations --check --dry-run` | No changes detected |
| `python manage.py test` | 134 tests OK (was 104) |
| `npm ci && npm run lint` | 0 errors, 22 warnings (see risks) |
| `npm test` | 18 passed |
| `npm run build` | OK |
| Browser smoke test (Playwright, tutor + student, 1280 and 390 px) | No page errors, no failed API calls, no horizontal overflow |
| `flutter pub get / analyze / test` | **Not run**: the Flutter SDK and pub.dev are blocked here. All Dart files pass a syntax parse; run these locally |

## What you need to do

1. Fetch the branch (above), then in `mobile/`: `flutter pub get && flutter analyze && flutter test`.
2. Backend: `python manage.py migrate` (adds `students.0014`, additive only).
3. Render: confirm `FRONTEND_URL` is the exact web address (it is now the only allowed browser origin). Add other origins to `CORS_ALLOWED_ORIGINS`.
4. Pushing this branch changes `.github/workflows/`; your last push failed because the token lacked the `workflow` scope. Use a token with `repo` + `workflow`, or push from GitHub Desktop / SSH.
5. Optional: repository variable `API_BASE_URL` if the API is not `https://tuitiontrack-api.onrender.com`.
6. Rebuild the APK. Testing against a LAN `http://` server now needs a debug build (`flutter run`).
7. No secrets were found in tracked files. `backend/.env` is untracked; if it was ever shared, rotate what it contains.

## Not changed (needs a decision)

- DB check constraint "homework has exactly one target": existing rows might violate it and the migration would fail the deploy.
- Tailwind 3 → 4 to clear `npm audit` (build-time tools only, nothing shipped to browsers).
- HSTS includeSubDomains/preload.
- Undisposed `TextEditingController`s created inside a few Flutter dialog helpers (tiny leak; fixing safely means refactoring them into widgets).

## Remaining risks

- Flutter changes are syntax-checked only, not type-checked.
- 22 oxlint warnings are React-Compiler advisories (`set-state-in-effect`, `purity`) that also fire on async data loading and on event handlers; the ones that read the clock during render were fixed.

## Recommended next steps (most valuable first)

1. Turn on `ci.yml` (it runs as soon as the branch is pushed).
2. Move notification e-mails and exam fan-out to a background job (Django-Q/Celery): sending is synchronous inside requests today.
3. Sentry (or similar) for backend + web errors.
4. A per-student `HomeworkSubmission` table in place of copy rows, if homework grows.
5. Paginate homework and connections server-side (currently unbounded lists).
6. API schema (drf-spectacular) and generate the Dart/JS clients from it, so the three apps can't drift.
