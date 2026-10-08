# TuitionTrack

Multi-tenant tuition management — Django REST backend + Flutter (Android, iOS, web) app.

## Download the Android APK

Grab the latest release from the [Releases page](../../releases). The APK file is attached to every tagged release.

Direct link pattern:
```
https://github.com/<owner>/<repo>/releases/download/<tag>/app-release.apk
```

## Building from source

Prereqs: Flutter 3.27+ with Dart 3.13+, Android SDK, JDK 17.

```bash
cd mobile
flutter pub get
flutter analyze
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

The Django backend is in `backend/`. It expects a `.env` (see `backend/.env.example`) and runs migrations on first boot.

## Repository layout

```
backend/        Django REST API (auth, students, tuitions, cycles, exams, homework)
mobile/         Flutter app (Android / iOS / web)
.github/        CI workflows
docs/           Phase 1-5 design specs
```

## Tagging a new release

```bash
git tag v1.2.0
git push origin v1.2.0
```

Pushing a `v*` tag kicks off `.github/workflows/build-apk.yml`, which builds and uploads the APK to the GitHub Release automatically.
