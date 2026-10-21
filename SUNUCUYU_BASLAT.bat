@echo off
title Psikolojiksel AI Sunucusu - Port 8000
color 0B
echo ========================================================
echo    PSIKOLOJIKSEL AI YEREL SUNUCUSU BASLATILIYOR...
echo ========================================================
echo.
cd /d "%~dp0backend"
node server.js
pause
