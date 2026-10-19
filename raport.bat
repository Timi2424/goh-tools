@echo off
setlocal
cd /d "%~dp0"

rem --- znajdz perla: na PATH, albo tam gdzie go instaluje Git dla Windows ---
set "PERL="
where perl >nul 2>&1 && set "PERL=perl"
if not defined PERL if exist "C:\Program Files\Git\usr\bin\perl.exe"        set "PERL=C:\Program Files\Git\usr\bin\perl.exe"
if not defined PERL if exist "C:\Program Files (x86)\Git\usr\bin\perl.exe"  set "PERL=C:\Program Files (x86)\Git\usr\bin\perl.exe"
if not defined PERL if exist "%LOCALAPPDATA%\Programs\Git\usr\bin\perl.exe" set "PERL=%LOCALAPPDATA%\Programs\Git\usr\bin\perl.exe"
if not defined PERL if exist "C:\Strawberry\perl\bin\perl.exe"              set "PERL=C:\Strawberry\perl\bin\perl.exe"

if not defined PERL (
  echo.
  echo   Nie znalazlem perla.
  echo   Jest w Git dla Windows, zwykle C:\Program Files\Git\usr\bin\perl.exe
  echo   Masz go gdzie indziej? Dopisz sciezke w raport.bat
  echo.
  pause
  exit /b 1
)

rem --- diff i unzip z Gita tez musza byc widoczne ---
for %%D in ("C:\Program Files\Git\usr\bin" "C:\Program Files (x86)\Git\usr\bin" "%LOCALAPPDATA%\Programs\Git\usr\bin") do (
  if exist "%%~D\diff.exe" set "PATH=%%~D;%PATH%"
)

"%PERL%" "test\raport.pl"

echo.
echo   ============================================================
echo    Raport zapisany w  data\raport.txt
echo    Powiedz asystentowi: raport gotowy
echo   ============================================================
echo.
pause
