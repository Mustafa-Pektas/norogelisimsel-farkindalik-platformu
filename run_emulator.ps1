# Psikolojiksel - Universal Canli Test Emulator Baslatici
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "     PSIKOLOJIKSEL - CANLI EMULATOR BASLATICI" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# 1. Proje Dizinini Bul
$projectDir = $PSScriptRoot
if (Test-Path "$PSScriptRoot\mobile_skeleton\pubspec.yaml") {
    $projectDir = "$PSScriptRoot\mobile_skeleton"
}
Set-Location $projectDir
Write-Host "`n[*] Proje Konumu: $projectDir" -ForegroundColor Gray

# 2. Flutter ve ADB Yollarını Bul
$flutterCmd = "flutter"
if (Test-Path "C:\flutter\bin\flutter.bat") {
    $env:PATH = "C:\flutter\bin;" + $env:PATH
    $flutterCmd = "C:\flutter\bin\flutter.bat"
}

$adbCmd = "adb"
$localAdb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (Test-Path $localAdb) {
    $adbCmd = $localAdb
}

# 3. Emulator Durumunu Kontrol Et
Write-Host "[*] Emulator kontrol ediliyor..." -ForegroundColor Yellow
$devices = & $adbCmd devices 2>$null
$emuRunning = $false
foreach ($line in $devices) {
    if ($line -match "emulator-\d+\s+device") {
        $emuRunning = $true
        break
    }
}

if (-not $emuRunning) {
    Write-Host "[*] Pixel 9 emulatoru baslatiliyor..." -ForegroundColor Green
    Start-Process $flutterCmd -ArgumentList "emulators", "--launch", "Pixel_9" -WindowStyle Hidden
    Write-Host "[*] Android sistem acilisi bekleniyor..." -ForegroundColor Gray
    & $adbCmd wait-for-device
    $booted = $false
    $retries = 0
    while (-not $booted -and $retries -lt 30) {
        Start-Sleep -Seconds 2
        $res = (& $adbCmd shell getprop sys.boot_completed 2>$null).Trim()
        if ($res -eq "1") { $booted = $true }
        $retries++
    }
    Write-Host "[OK] Pixel 9 basariyla acildi!" -ForegroundColor Green
} else {
    Write-Host "[OK] Emulator zaten calisiyor." -ForegroundColor Green
}

# 4. Hafiza ve Eski Surum Temizligi
Write-Host "`n[*] Emulator depolama alani ve eski surecler temizleniyor..." -ForegroundColor Yellow
& $adbCmd shell am force-stop com.neuroapp.neuro_awareness_app 2>$null | Out-Null
& $adbCmd shell "rm -rf /data/local/tmp/*" 2>$null | Out-Null
& $adbCmd shell "pm trim-caches 300M" 2>$null | Out-Null
& $adbCmd uninstall com.neuroapp.neuro_awareness_app 2>$null | Out-Null
Write-Host "[OK] Hafiza temizlendi (INSUFFICIENT_STORAGE onlendi)." -ForegroundColor Green

# 5. En Guncel APK'yi Derle
Write-Host "`n[*] En guncel kodlar derleniyor (flutter build apk --debug)..." -ForegroundColor Cyan
& $flutterCmd build apk --debug
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[HATA] APK derlenirken bir sorun olustu!" -ForegroundColor Red
    Read-Host "Kapatmak icin Enter tusuna basin..."
    exit 1
}

# 6. APK'yi Emulatore Yukle
$apkPath = "$projectDir\build\app\outputs\flutter-apk\app-debug.apk"
Write-Host "`n[*] Taze derlenen APK yukleniyor: $apkPath" -ForegroundColor Cyan
$installOutput = & $adbCmd install -r "$apkPath" 2>&1
if ($installOutput -match "Success") {
    Write-Host "[OK] YUKLEME BASARILI!" -ForegroundColor Green
} else {
    Write-Host "[UYARI] Yukleme ciktisi: $installOutput" -ForegroundColor Yellow
}

# 7. Uygulamayi Telefonda Baslat
Write-Host "`n[*] Uygulama telefonda baslatiliyor..." -ForegroundColor Green
& $adbCmd shell am start -n com.neuroapp.neuro_awareness_app/.MainActivity 2>$null | Out-Null

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "  [OK] EN GUNCEL SURUM TELEFONDA BASARIYLA ACILDI!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "`nTamamlandi.`n" -ForegroundColor Gray
