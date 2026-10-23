@echo off
rem Copies every TuitionTrack record from one PostgreSQL database to another
rem (for example from Render's free database, which expires, to Neon's free one).
rem
rem Safe by design:
rem   - The old database is only READ. Nothing in it is changed or deleted.
rem   - The new database must be empty; the script stops if it already has users.
rem   - The two addresses you paste are kept in this window only: they are not
rem     written to the log or to any file.
rem
rem Before running: deploy the current code to Render once, so the old database
rem has every migration (the script checks this and stops if not).
setlocal EnableDelayedExpansion
rem Python writes and reads the backup as UTF-8 (Bangla text, dashes); Windows
rem would otherwise use its own code page and stop at the first such character.
set "PYTHONUTF8=1"
cd /d "%~dp0.."
set "ROOT=%CD%"
set "LOG=%ROOT%\scripts\move-database.log"
echo TuitionTrack database move > "%LOG%"

if not exist "%ROOT%\venv\Scripts\activate.bat" (
  echo The Python environment "venv" was not found in %ROOT%.
  goto :fail
)
call "%ROOT%\venv\Scripts\activate.bat" || goto :fail
cd backend
python -m pip install -q -r requirements.txt >> "%LOG%" 2>&1 || goto :fail

for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmm"') do set STAMP=%%i
if not exist "%ROOT%\backups" mkdir "%ROOT%\backups"
set "BACKUP=%ROOT%\backups\tuitiontrack-%STAMP%.json"

echo.
echo Paste the OLD database address (Render: tuitiontrack-db ^> Connections ^> External Database URL)
set /p "OLD_URL=OLD> "
echo.
echo Paste the NEW database address (Neon: Dashboard ^> Connect ^> "Pooled connection" string)
set /p "NEW_URL=NEW> "
if "!OLD_URL!"=="" goto :missing
if "!NEW_URL!"=="" goto :missing
if "!OLD_URL!"=="!NEW_URL!" (
  echo The two addresses are the same. Nothing to do.
  goto :fail
)

echo.
echo [1/5] Checking the old database is up to date ...
set "DATABASE_URL=!OLD_URL!"
python manage.py migrate --check >> "%LOG%" 2>&1
if errorlevel 1 (
  echo The old database is missing some migrations. Deploy the current code to Render first,
  echo wait for the deploy to finish, then run this again.
  goto :fail
)

echo [2/5] Saving a copy of every record to backups\tuitiontrack-%STAMP%.json ...
python manage.py dumpdata --natural-foreign --exclude contenttypes --exclude auth.permission --exclude admin.logentry --exclude sessions --indent 1 -o "%BACKUP%" >> "%LOG%" 2>&1 || goto :fail
python manage.py shell -c "from django.contrib.auth import get_user_model as g; print('Users in old database:', g().objects.count())"

echo [3/5] Creating the tables in the new database ...
set "DATABASE_URL=!NEW_URL!"
python manage.py migrate --noinput >> "%LOG%" 2>&1 || goto :fail
python manage.py shell -c "import sys; from django.contrib.auth import get_user_model as g; n = g().objects.count(); print('Users already in new database:', n); sys.exit(3 if n else 0)"
if errorlevel 3 (
  echo The new database already has data. Use an empty database so nothing gets mixed up.
  goto :fail
)

echo [4/5] Copying the records into the new database ...
python manage.py loaddata "%BACKUP%" >> "%LOG%" 2>&1 || goto :fail

echo [5/5] Checking ...
python manage.py shell -c "from django.contrib.auth import get_user_model as g; print('Users in new database:', g().objects.count())"
python manage.py check --database default >> "%LOG%" 2>&1 || goto :fail

echo.
echo Done. Your data is now in the new database too. Next:
echo   1. Render ^> tuitiontrack-api ^> Environment: set DATABASE_URL to the NEW address,
echo      and DB_CONN_MAX_AGE to 0. Save; Render redeploys by itself.
echo   2. Open the app and check your tuitions, classes and wallet.
echo   3. Keep backups\tuitiontrack-%STAMP%.json somewhere safe (it holds your data,
echo      including password hashes), or delete it once everything looks right.
echo   The old Render database was not touched.
echo MOVE OK >> "%LOG%"
pause
goto :eof

:missing
echo Both addresses are needed.
:fail
echo FAILED >> "%LOG%"
echo.
echo Stopped. Nothing was deleted. Details are in scripts\move-database.log
pause
