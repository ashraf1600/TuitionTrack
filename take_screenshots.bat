@echo off
rem Takes dark-mode screenshots of every main screen of the app, with demo data.
rem The pictures land in mobile\test_screens\shots. Double-click to run.
setlocal
cd /d "%~dp0mobile" || (echo Cannot find the mobile folder next to this file. & pause & exit /b 1)
set "FLUTTER="
for %%P in ("D:\flutter\bin\flutter.bat" "C:\flutter\bin\flutter.bat" "C:\src\flutter\bin\flutter.bat" "%USERPROFILE%\flutter\bin\flutter.bat") do if not defined FLUTTER if exist %%P set "FLUTTER=%%~P"
if not defined FLUTTER for /f "delims=" %%F in ('where flutter.bat 2^>nul') do if not defined FLUTTER set "FLUTTER=%%F"
if not defined FLUTTER (echo Flutter was not found. & pause & exit /b 1)
echo Taking screenshots...
call "%FLUTTER%" test test_screens\app_screens_test.dart || (echo. & echo *** Something failed. Scroll up to see the error. *** & pause & exit /b 1)
echo.
echo Done: %cd%\test_screens\shots
explorer "%cd%\test_screens\shots"
pause
