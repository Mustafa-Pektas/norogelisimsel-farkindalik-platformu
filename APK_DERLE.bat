@echo off
chcp 65001 > nul
echo ========================================================
echo   Nörogelişimsel Farkındalık Platformu - Akıllı APK Derleyici
echo ========================================================
echo.

:: 1. Proje dizini kontrolü
if not exist "mobile_skeleton" (
    echo [HATA] mobile_skeleton klasörü bulunamadı!
    echo Lütfen bu betiği projenin ana dizininden çalıştırın.
    pause
    exit /b 1
)

:: 2. Flutter kontrolü ve otomatik yol arama
echo [1/4] Geliştirme ortamı (Flutter) kontrol ediliyor...
where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo [!] Flutter PATH üzerinde bulunamadı. Standart dizinler taranıyor...
    if exist "C:\flutter\bin\flutter.bat" (
        set "PATH=C:\flutter\bin;%PATH%"
    ) else if exist "C:\src\flutter\bin\flutter.bat" (
        set "PATH=C:\src\flutter\bin;%PATH%"
    ) else if exist "%LOCALAPPDATA%\Flutter\bin\flutter.bat" (
        set "PATH=%LOCALAPPDATA%\Flutter\bin;%PATH%"
    ) else if exist "%USERPROFILE%\flutter\bin\flutter.bat" (
        set "PATH=%USERPROFILE%\flutter\bin;%PATH%"
    )
)

:: Eğer hala bulunamadıysa Windows winget ile otomatik kurulum başlat
where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo.
    echo ========================================================
    echo  UYARI: Bilgisayarda Flutter SDK tespit edilemedi!
    echo  Otomatik Kurulum Başlatılıyor (Windows winget ile)...
    echo ========================================================
    echo.
    where winget >nul 2>nul
    if %errorlevel% neq 0 (
        echo [HATA] Windows Paket Yöneticisi (winget) bulunamadı.
        echo Lütfen https://flutter.dev adresinden Flutter'ı kurun.
        pause
        exit /b 1
    )
    
    echo [*] Flutter SDK otomatik indiriliyor ve kuruluyor (Lütfen bekleyin)...
    winget install --id Flutter.Flutter -e --accept-source-agreements --accept-package-agreements
    
    :: Kurulum sonrası olası yolları PATH'e ekle
    if exist "C:\flutter\bin\flutter.bat" set "PATH=C:\flutter\bin;%PATH%"
    if exist "%LOCALAPPDATA%\Flutter\bin\flutter.bat" set "PATH=%LOCALAPPDATA%\Flutter\bin;%PATH%"
    if exist "%USERPROFILE%\flutter\bin\flutter.bat" set "PATH=%USERPROFILE%\flutter\bin;%PATH%"
)

:: 3. Java kontrolü
where java >nul 2>nul
if %errorlevel% neq 0 (
    echo [*] Java JDK eksik tespit edildi, otomatik yükleniyor...
    where winget >nul 2>nul
    if %errorlevel% equ 0 (
        winget install --id EclipseAdoptium.Temurin.17.JDK -e --accept-source-agreements --accept-package-agreements
    )
)

cd mobile_skeleton

echo.
echo [2/4] Paket bağımlılıkları güncelleniyor (flutter pub get)...
call flutter pub get
if %errorlevel% neq 0 (
    echo [HATA] Paketler indirilirken bir sorun oluştu.
    pause
    exit /b 1
)

echo.
echo [3/4] Release APK derleniyor (flutter build apk --release)...
echo Bu işlem bilgisayar hızına göre 1-2 dakika sürebilir, lütfen bekleyin...
call flutter build apk --release
if %errorlevel% neq 0 (
    echo [HATA] APK derlenirken bir sorun oluştu!
    pause
    exit /b 1
)

echo.
echo ========================================================
echo [4/4] TEBRİKLER! Release APK başarıyla oluşturuldu.
echo ========================================================
echo Dosya: mobile_skeleton\build\app\outputs\flutter-apk\app-release.apk
echo.
echo APK klasörü Dosya Gezgini'nde açılıyor...
explorer build\app\outputs\flutter-apk
echo.
pause
