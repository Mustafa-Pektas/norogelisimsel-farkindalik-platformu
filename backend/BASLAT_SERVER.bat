@echo off
setlocal
title Yerel Yapay Zeka Sunucusu (Backend)
color 0B

if exist "C:\Program Files\nodejs" set "PATH=C:\Program Files\nodejs;%PATH%"

cd /d "%~dp0"

echo ========================================================
echo    YEREL YAPAY ZEKA SUNUCUSU BASLATILIYOR...
echo ========================================================
echo.

where node >nul 2>nul
if %ERRORLEVEL% neq 0 goto :no_node

if not exist "node_modules" goto :install_deps
goto :start_server

:install_deps
echo [*] Gerekli paketler yukleniyor...
call npm install
if %ERRORLEVEL% neq 0 goto :npm_fail
echo [OK] Paketler basariyla yuklendi!
echo.
goto :start_server

:start_server
rem Port kullanimdaysa Node hatasini goster; baska sureci otomatik sonlandirma.

echo [*] Guncel Gemini 3.1 Flash-Lite sunucusu calistiriliyor...
echo [*] Kapatmak icin bu pencereyi kapatabilir veya Ctrl+C yapabilirsiniz.
echo.
node server.js
goto :end

:no_node
echo.
echo [!] HATA: Node.js bulunamadi!
echo Lutfen https://nodejs.org adresinden Node.js kurun.
echo.
pause
exit /b 1

:npm_fail
echo.
echo [!] HATA: Paket yukleme basarisiz oldu. Internet baglantinizi kontrol edin.
echo.
pause
exit /b 1

:end
pause
