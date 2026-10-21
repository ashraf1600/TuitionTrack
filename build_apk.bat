@echo off
rem Builds the TuitionTrack Android APKs. Double-click this file, or run it from PowerShell.
rem Keep it next to the "mobile" folder. Skip the checks with:  build_apk.bat fast
setlocal
cd /d "%~dp0mobile" || (echo Cannot find the mobile folder next to this file. & pause & exit /b 1)

rem Find flutter.bat: the usual places first, then anything on the PATH.
set "FLUTTER="
for %%P in ("D:\flutter\bin\flutter.bat" "C:\flutter\bin\flutter.bat" "C:\src\flutter\bin\flutter.bat" "D:\src\flutter\bin\flutter.bat" "C:\tools\flutter\bin\flutter.bat" "%USERPROFILE%\flutter\bin\flutter.bat" "%USERPROFILE%\development\flutter\bin\flutter.bat") do if not defined FLUTTER if exist %%P set "FLUTTER=%%~P"
if not defined FLUTTER for /f "delims=" %%F in ('where flutter.bat 2^>nul') do if not defined FLUTTER set "FLUTTER=%%F"
if not defined FLUTTER (
  echo.
  echo Flutter was not found. To find it, run this in a command window:  where /r D:\ flutter.bat
  echo Then open build_apk.bat in Notepad and put that full path on the line:  set "FLUTTER=..."
  pause
  exit /b 1
)
echo Using Flutter: %FLUTTER%

rem The server the app talks to. Change it here if your API address is different.
set API_URL=https://tuitiontrack-api.onrender.com

echo.
echo === 1/4  Getting packages ===
call "%FLUTTER%" pub get || goto :failed

if /i "%~1"=="fast" goto :build

echo.
echo === 2/4  Checking the code (flutter analyze) ===
call "%FLUTTER%" analyze --no-fatal-infos || goto :failed

echo.
echo === 3/4  Running the tests ===
call "%FLUTTER%" test || goto :failed

:build
echo.
echo === 4/4  Building the release APKs ===
rem One small APK per phone processor instead of one big one holding all of them (about 20-25 MB each, not 70).
rem --obfuscate shrinks the code a little more; the symbols needed to read crash logs go to build\symbols.
rem An 8 GB PC runs out of memory if Gradle daemons from earlier builds are still running: stop them first.
if exist android\gradlew.bat (pushd android & call gradlew.bat --stop >nul 2>&1 & popd)
rem Phones only (32- and 64-bit ARM); the x86_64 build is for emulators and costs memory and time.
call "%FLUTTER%" build apk --release --split-per-abi --target-platform android-arm,android-arm64 --obfuscate --split-debug-info=build\symbols --dart-define=API_BASE_URL=%API_URL% || goto :failed

set "OUT=%cd%\build\app\outputs\flutter-apk"
if not exist "%OUT%\app-arm64-v8a-release.apk" goto :failed

if exist android\key.properties (
  echo Signed with your release key ^(android\key.properties^).
) else (
  echo NOTE: android\key.properties not found - these APKs are signed with the DEBUG key.
  echo       Fine for your own phone, not for sharing or updating a release install.
)

copy /y "%OUT%\app-arm64-v8a-release.apk" "%USERPROFILE%\Desktop\TuitionTrack.apk" >nul
copy /y "%OUT%\app-armeabi-v7a-release.apk" "%USERPROFILE%\Desktop\TuitionTrack-old-phones.apk" >nul
echo.
echo Done. On your Desktop:
echo   TuitionTrack.apk             - for almost every phone from the last 6-7 years (64-bit)
echo   TuitionTrack-old-phones.apk  - only if the first one says "App not installed" (old 32-bit phones)
explorer "%OUT%"
pause
exit /b 0

:failed
echo.
echo *** The build stopped because a step failed. Scroll up to see the error. ***
pause
exit /b 1
