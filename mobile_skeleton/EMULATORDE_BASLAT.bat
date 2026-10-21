@echo off
setlocal
title Psikolojiksel - Pixel 9 Canli Test
color 0A

if exist "C:\flutter\bin" set "PATH=C:\flutter\bin;%PATH%"
if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools" set "PATH=%LOCALAPPDATA%\Android\Sdk\platform-tools;%PATH%"
if exist "%LOCALAPPDATA%\Android\Sdk\emulator" set "PATH=%LOCALAPPDATA%\Android\Sdk\emulator;%PATH%"
if exist "%LOCALAPPDATA%\GitHubDesktop\app-3.6.7\resources\app\git\cmd" set "PATH=%LOCALAPPDATA%\GitHubDesktop\app-3.6.7\resources\app\git\cmd;%PATH%"
if exist "%LOCALAPPDATA%\GitHubDesktop\app-3.6.6\resources\app\git\cmd" set "PATH=%LOCALAPPDATA%\GitHubDesktop\app-3.6.6\resources\app\git\cmd;%PATH%"
if exist "C:\Program Files\Git\cmd" set "PATH=C:\Program Files\Git\cmd;%PATH%"

cd /d "%~dp0"

echo ========================================================
echo    PIXEL 9 EMULATORU KONTROL EDILIYOR...
echo ========================================================
echo.

if exist "%USERPROFILE%\.android\avd\Pixel_9.avd\multiinstance.lock" del /f /q "%USERPROFILE%\.android\avd\Pixel_9.avd\multiinstance.lock" >nul 2>nul
if exist "%USERPROFILE%\.android\avd\Pixel_9.avd\hardware-qemu.ini.lock" rmdir /s /q "%USERPROFILE%\.android\avd\Pixel_9.avd\hardware-qemu.ini.lock" >nul 2>nul

adb devices | findstr /i "emulator-" >nul 2>nul
if %ERRORLEVEL% equ 0 goto :emulator_running

:start_emulator
echo [*] Pixel 9 penceresi masaustunde aciliyor...
if exist "%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe" (
    start "" "%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe" -avd Pixel_9
) else (
    start "" flutter emulators --launch Pixel_9
)
echo [*] Android sisteminin acilmasi bekleniyor...
adb wait-for-device >nul 2>nul

:wait_boot
timeout /t 3 /nobreak >nul
set "BOOT_DONE=0"
for /f "tokens=*" %%a in ('adb shell getprop sys.boot_completed 2^>nul') do set "BOOT_DONE=%%a"
if not "%BOOT_DONE%"=="1" goto :wait_boot
echo [OK] Android sistemi hazir!
goto :run_app

:emulator_running
echo [OK] Pixel 9 emulatoru zaten calisiyor.
goto :run_app

:run_app
echo.
echo ========================================================
echo    UYGULAMA TELEFON EKRANINDA ACILIYOR...
echo ========================================================
echo.
echo  * Kod degisikligini telefona yansitmak icin: 'r' basin
echo  * Uygulamayi bastan baslatmak icin:         'R' basin
echo  * Cikis yapmak icin:                       'q' basin
echo.
echo ========================================================
echo.

flutter run -d emulator-5554 || flutter run -d android || flutter run

pause