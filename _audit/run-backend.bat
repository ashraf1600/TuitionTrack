@echo off
rem Runs the TuitionTrack Django backend from the current work branch, reachable from phones on your Wi-Fi.
setlocal
cd /d "%~dp0.."
set "BRANCH=feature/ux-round-3"
set LOG=%~dp0run-backend.log
echo TuitionTrack backend > "%LOG%"

echo [1/4] Getting the latest changes (branch %BRANCH%) ...
git fetch "_audit\audit-full-stack-fixes.bundle" %BRANCH% >> "%LOG%" 2>&1 || goto :fail
git rev-parse --verify %BRANCH% >nul 2>&1 || git branch %BRANCH% FETCH_HEAD >> "%LOG%" 2>&1
git checkout -- mobile/pubspec.lock >nul 2>&1
git checkout %BRANCH% >> "%LOG%" 2>&1 || goto :fail
rem pubspec.lock is rewritten by every build; drop that so the update can apply.
git checkout -- mobile/pubspec.lock >nul 2>&1
git merge --ff-only FETCH_HEAD >> "%LOG%" 2>&1 || (echo This copy of the branch has changes of its own. See the log. & goto :fail)
git log --oneline -1 >> "%LOG%" 2>&1

cd backend
call ..\venv\Scripts\activate.bat || goto :fail
echo [2/4] Installing packages ...
python -m pip install -q -r requirements.txt >> "%LOG%" 2>&1 || goto :fail
echo [3/4] Updating the database ...
python manage.py migrate >> "%LOG%" 2>&1 || goto :fail
python manage.py check >> "%LOG%" 2>&1 || goto :fail

for /f %%i in ('powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet|VirtualBox|WSL' -and $_.IPAddress -notlike '169.254*' } | Select-Object -First 1).IPAddress"') do set LANIP=%%i
echo [4/4] Backend running. Leave this window open; close it to stop.
echo        This PC:        http://127.0.0.1:8000/api/v1/meta/
echo        Phone on Wi-Fi: http://%LANIP%:8000   (if the phone cannot connect, allow Python in Windows Firewall)
echo Running on http://%LANIP%:8000 >> "%LOG%"
python manage.py runserver 0.0.0.0:8000
goto :eof

:fail
echo.
echo Something failed. Details are in %LOG%
pause
