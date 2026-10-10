# TuitionTrack

Multi-tenant tuition management — Django REST backend, React web app and Flutter (Android, iOS, web) app.

## Download the Android APK

Grab the latest release from the [Releases page](../../releases). The APK file is attached to every tagged release.

Direct link pattern:
```
https://github.com/<owner>/<repo>/releases/download/<tag>/app-release.apk
```

## Building from source

Prereqs: Flutter 3.44+ (Dart 3.13.5+), Android SDK, JDK 17.

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define=API_BASE_URL=https://tuitiontrack-api.onrender.com
# Output: build/app/outputs/flutter-apk/app-release.apk
```

Release builds only talk https. Debug builds (`flutter run`) may use plain http to a
computer on your network, e.g. `http://192.168.0.10:8000`.

The Django backend is in `backend/`. It expects a `.env` (see `backend/.env.example`) and runs migrations on first boot.

```bash
cd backend
pip install -r requirements.txt ruff
ruff check . && python manage.py check && python manage.py test
```

The React web app is in `frontend/` (Node 22):

```bash
cd frontend
npm ci
npm run lint && npm test && npm run build
```

`.github/workflows/ci.yml` runs all three on every push.

## Repository layout

```
backend/        Django REST API (auth, students, tuitions, cycles, exams, homework)
frontend/       React + Vite web app
mobile/         Flutter app (Android / iOS / web)
.github/        CI workflows
0*_*.md         Design specs (overview, PRD, schema, API, UI)
```

## Tagging a new release

```bash
git tag v1.2.0
git push origin v1.2.0
```

Pushing a `v*` tag kicks off `.github/workflows/build-apk.yml`, which builds and uploads the APK to the GitHub Release automatically.
