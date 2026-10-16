@echo off
chcp 65001 >nul
title Psikolojiksel - Pixel 9 Canli Test
color 0A

:: 1. Flutter ve ADB Yollarini Saglama Al
if exist "C:\flutter\bin" set "PATH=C:\flutter\bin;%PATH%"
if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools" set "PATH=%LOCALAPPDATA%\Android\Sdk\platform-tools;%PATH%"

:: 2. Proje Klasorune Gec
if exist "%~dp0pubspec.yaml" (
    cd /d "%~dp0"
) else if exist "%~dp0mobile_skeleton\pubspec.yaml" (
    cd /d "%~dp0mobile_skeleton"
)

echo ========================================================
echo    PIXEL 9 EMULATORU KONTROL EDILIYOR...
echo ========================================================
echo.

:: 3. Pixel 9 emulatorunu masaustunde gorunur baslat
where adb >nul 2>nul
adb devices | findstr /i "emulator-" >nul 2>nul
if %errorlevel% neq 0 (
    echo [*] Pixel 9 penceresi masaustunde aciliyor...
    if exist "%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe" (
        start "" "%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe" -avd Pixel_9
    ) else (
        start "" flutter emulators --launch Pixel_9
    )
    echo [*] Android sisteminin hazir olmasi bekleniyor...
    adb wait-for-device >nul 2>nul
    timeout /t 5 /nobreak >nul
) else (
    echo [OK] Pixel 9 emulatoru zaten calisiyor.
)

:: 4. Hafiza Sismesini Onle (Eski kalintilari silerek 1 GB yer acar)
echo [*] Emulator depolama alani temizleniyor (INSUFFICIENT_STORAGE engelleyici)...
adb shell "rm -rf /data/local/tmp/*" >nul 2>nul
adb shell "pm trim-caches 500M" >nul 2>nul
adb uninstall com.neuroapp.neuro_awareness_app >nul 2>nul

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

:: 5. Uygulamayi Pixel 9 telefonunda calistir
flutter run -d emulator-5554 || flutter run -d android || flutter run

pause
