@echo off
title Port 8000 Guvenlik Duvari Izni
echo ========================================================
echo   PORT 8000 GUVENLIK DUVARI (FIREWALL) IZNI
echo ========================================================
echo.
echo Telefonun bilgisayardaki yapay zeka sunucusuna baglanabilmesi icin
echo 8000 portuna gelen baglantilara izin veriliyor...
echo.
netsh advfirewall firewall add rule name="NodeJS Port 8000" dir=in action=allow protocol=TCP localport=8000
echo.
if %ERRORLEVEL% EQU 0 (
    echo [BASARILI] Port 8000 izni verildi! Telefon artik baglanabilir.
) else (
    echo [UYARI] Lutfen bu dosyaya sag tiklayip 'Yonetici Olarak Calistir' secenegini secin.
)
echo.
pause
