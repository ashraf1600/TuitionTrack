@echo off
rem Builds the TuitionTrack Android app from the current work branch. Full output goes to build-apk.log.
setlocal
cd /d "%~dp0.."
set "BRANCH=feature/ux-round-3"
set LOG=%~dp0build-apk.log
echo TuitionTrack APK build > "%LOG%"

echo Which app do you want?
echo   1 = For testing with the backend on THIS computer (debug build, plain http allowed)
echo   2 = For real use with the hosted server https://tuitiontrack-api.onrender.com (release build)
choice /c 12 /n /m "Press 1 or 2: "
set KIND=%ERRORLEVEL%

echo [1/5] Getting the latest changes (branch %BRANCH%) ...
git fetch "_audit\audit-full-stack-fixes.bundle" %BRANCH% >> "%LOG%" 2>&1 || goto :fail
git rev-parse --verify %BRANCH% >nul 2>&1 || git branch %BRANCH% FETCH_HEAD >> "%LOG%" 2>&1
git checkout -- mobile/pubspec.lock >nul 2>&1
git checkout %BRANCH% >> "%LOG%" 2>&1 || goto :fail
rem pubspec.lock is rewritten by every build; drop that so the update can apply.
git checkout -- mobile/pubspec.lock >nul 2>&1
git merge --ff-only FETCH_HEAD >> "%LOG%" 2>&1 || (echo This copy of the branch has changes of its own. See the log. & goto :fail)
git log --oneline -1 >> "%LOG%" 2>&1

cd mobile
rem Flutter is not on PATH in every terminal: fall back to the SDK this project was last built with.
where flutter >nul 2>&1 || if exist "D:\flutter\bin\flutter.bat" set "PATH=D:\flutter\bin;%PATH%"
echo [2/5] flutter pub get ...
call flutter --version >> "%LOG%" 2>&1 || (echo Flutter was not found on PATH. & goto :fail)
call flutter pub get >> "%LOG%" 2>&1 || goto :fail
echo [3/5] flutter analyze ...
call flutter analyze --no-fatal-infos >> "%LOG%" 2>&1 || goto :fail
echo [4/5] flutter test ...
call flutter test >> "%LOG%" 2>&1 || goto :fail

echo [5/5] Building the APK (10-20 minutes the first time) ...
rem Free the memory held by Gradle daemons left over from earlier builds.
if exist android\gradlew.bat (pushd android & call gradlew.bat --stop >> "%LOG%" 2>&1 & popd)
if "%KIND%"=="1" goto :debug
call flutter build apk --release --dart-define=API_BASE_URL=https://tuitiontrack-api.onrender.com >> "%LOG%" 2>&1 || goto :fail
copy /y build\app\outputs\flutter-apk\app-release.apk ..\TuitionTrack.apk >> "%LOG%" 2>&1 || goto :fail
goto :done

:debug
for /f %%i in ('powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet|VirtualBox|WSL' -and $_.IPAddress -notlike '169.254*' } | Select-Object -First 1).IPAddress"') do set LANIP=%%i
echo Server built into the app: http://%LANIP%:8000 >> "%LOG%"
call flutter build apk --debug --dart-define=API_BASE_URL=http://%LANIP%:8000 >> "%LOG%" 2>&1 || goto :fail
copy /y build\app\outputs\flutter-apk\app-debug.apk ..\TuitionTrack-debug.apk >> "%LOG%" 2>&1 || goto :fail

:done
echo BUILD OK >> "%LOG%"
echo.
echo Done. The APK is in the TuitionTrack folder (TuitionTrack.apk or TuitionTrack-debug.apk).
pause
goto :eof

:fail
echo FAILED >> "%LOG%"
echo.
echo Something failed. Details are in %LOG%
pause
