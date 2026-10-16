# Psikolojiksel - Universal Release Emulator Baslatici
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "     PSIKOLOJIKSEL - RELEASE EMULATOR BASLATICI" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# 1. Proje dizinini bul
$projectDir = $PSScriptRoot
if (Test-Path "$PSScriptRoot\mobile_skeleton\pubspec.yaml") {
    $projectDir = "$PSScriptRoot\mobile_skeleton"
} elseif (Test-Path "$PSScriptRoot\pubspec.yaml") {
    $projectDir = "$PSScriptRoot"
}
Set-Location $projectDir
Write-Host "`n[1/4] Proje konumu: $projectDir" -ForegroundColor Gray

# ADB yolunu bul
$adbPath = "adb"
$localAdb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (Test-Path $localAdb) {
    $adbPath = $localAdb
}

# 2. Emulator veya bagli cihaz kontrolu
Write-Host "[2/4] Bagli cihazlar ve emulatorler kontrol ediliyor..." -ForegroundColor Yellow
$devices = flutter devices 2>$null
$hasRunningEmulator = ($devices -match "emulator") -or ($devices -match "android")

if (-not $hasRunningEmulator) {
    Write-Host "-> Acik emulator bulunamadi. Bilgisayardaki emulatorler taraniyor..." -ForegroundColor Yellow
    $emuOutput = flutter emulators 2>$null
    
    $availableEmus = @()
    foreach ($line in $emuOutput) {
        if ($line -match "^\s*([a-zA-Z0-9_\.\-]+)\s+•\s+(.+?)\s+•") {
            $availableEmus += $Matches[1].Trim()
        }
    }

    if ($availableEmus.Count -gt 0) {
        $targetEmu = if ($availableEmus -contains "Pixel_9") { "Pixel_9" } else { $availableEmus[0] }
        Write-Host "-> '$targetEmu' emulatoru otomatik baslatiliyor..." -ForegroundColor Green
        
        Start-Process flutter -ArgumentList "emulators", "--launch", $targetEmu -WindowStyle Hidden
        Write-Host "-> Emulator penceresinin acilmasi ve sistemin yuklenmesi bekleniyor..." -ForegroundColor Gray
        
        # ADB ile emulatorun hazir olmasini bekle
        if (Test-Path $localAdb) {
            & $adbPath wait-for-device
            Write-Host "-> Cihaz baglantisi saglandi, Android sistem acilisi bekleniyor..." -ForegroundColor Gray
            $bootComplete = ""
            $retry = 0
            while ($bootComplete -ne "1" -and $retry -lt 30) {
                Start-Sleep -Seconds 2
                $bootComplete = (& $adbPath shell getprop sys.boot_completed 2>$null).Trim()
                $retry++
            }
        } else {
            Start-Sleep -Seconds 15
        }
    } else {
        Write-Host "-> Bilgisayarinizda kayitli emulator bulunamadi. Mevcut cihaz aranacak." -ForegroundColor DarkYellow
    }
} else {
    Write-Host "-> Calisan aktif bir cihaz/emulator bulundu!" -ForegroundColor Green
}

# 3. Release APK kontrolu
$apkPath = "$projectDir\build\app\outputs\flutter-apk\app-release.apk"
Write-Host "`n[3/4] Release APK kontrol ediliyor..." -ForegroundColor Yellow

if (-not (Test-Path $apkPath)) {
    Write-Host "-> Release APK henuz derlenmemis, simdi derleniyor (flutter build apk --release)..." -ForegroundColor Yellow
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[HATA] Release APK derlenemedi!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "-> Hazir Release APK bulundu:`n   $apkPath" -ForegroundColor Green
}

# 4. Telefona/Emulatore yukle ve calistir
Write-Host "`n[4/4] Release APK emulatore yukleniyor ve telefon ekraninda baslatiliyor..." -ForegroundColor Cyan

$installedSuccess = $false
if (Test-Path $localAdb) {
    Write-Host "-> Emülatör depolama alanı ve önbellek temizleniyor..." -ForegroundColor Gray
    & $adbPath shell "rm -rf /data/local/tmp/*" 2>$null | Out-Null
    & $adbPath shell "pm trim-caches 300M" 2>$null | Out-Null
    & $adbPath uninstall com.neuroapp.neuro_awareness_app 2>$null | Out-Null
    Write-Host "-> ADB ile taze yükleme yapılıyor..." -ForegroundColor Gray
    $installOutput = & $adbPath install -r "$apkPath" 2>&1
    if ($installOutput -match "Success") {
        Write-Host "-> YUKLEME BASARILI!" -ForegroundColor Green
        Write-Host "-> Uygulama telefon ekraninda baslatiliyor..." -ForegroundColor Green
        
        # Once standart MainActivity intent'ini dene, ardindan launcher monkey'i tetikle
        & $adbPath shell am start -n com.neuroapp.neuro_awareness_app/.MainActivity 2>$null | Out-Null
        & $adbPath shell monkey -p com.neuroapp.neuro_awareness_app -c android.intent.category.LAUNCHER 1 2>$null | Out-Null
        $installedSuccess = $true
    } else {
        Write-Host "-> ADB ciktisi: $installOutput" -ForegroundColor DarkGray
    }
}

if (-not $installedSuccess) {
    Write-Host "-> 'flutter run --release' ile baslatiliyor..." -ForegroundColor Yellow
    flutter run --release
}

Write-Host "`n========================================================" -ForegroundColor Green
Write-Host "  * RELEASE UYGULAMASI TELEFONDA BASARIYLA ACILDI!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Bu pencereyi kapatabilirsiniz.`n" -ForegroundColor Gray
