@echo off
chcp 65001 >nul
title Psikolojiksel - Pixel 9 Canli Test
color 0A

echo ========================================================
echo    PIXEL 9 EMULATORU BASLATILIYOR...
echo ========================================================
echo.

:: 1. Pixel 9 emulatorunu baslat
start "" flutter emulators --launch Pixel_9

echo Emulatorun acilmasi bekleniyor (10 saniye)...
timeout /t 10 /nobreak >nul

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

:: 2. Proje klasorune gec
if exist "%~dp0pubspec.yaml" (
    cd /d "%~dp0"
) else if exist "%~dp0mobile_skeleton\pubspec.yaml" (
    cd /d "%~dp0mobile_skeleton"
)

:: 3. Uygulamayi Pixel 9 telefonunda calistir
flutter run -d android || flutter run

pause
