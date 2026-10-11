# Psikolojiksel - Universal Canli Test Emulator Baslatici
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "     PSIKOLOJIKSEL - CANLI EMULATOR BASLATICI" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# 1. Proje dizinini bul
$projectDir = $PSScriptRoot
if (Test-Path "$PSScriptRoot\mobile_skeleton\pubspec.yaml") {
    $projectDir = "$PSScriptRoot\mobile_skeleton"
} elseif (Test-Path "$PSScriptRoot\pubspec.yaml") {
    $projectDir = "$PSScriptRoot"
}
Set-Location $projectDir
Write-Host "`n[1/3] Proje konumu: $projectDir" -ForegroundColor Gray

# 2. Emulator veya bagli cihaz kontrolu
Write-Host "[2/3] Bagli cihazlar ve emulatorler kontrol ediliyor..." -ForegroundColor Yellow
$devices = flutter devices 2>$null
$hasRunningEmulator = $devices -match "emulator"

if (-not $hasRunningEmulator) {
    Write-Host "-> Acik emulator bulunamadi. Bilgisayardaki emulatorler taraniyor..." -ForegroundColor Yellow
    $emuOutput = flutter emulators 2>$null
    
    # Bilgisayardaki emulator ID'lerini bul
    $availableEmus = @()
    foreach ($line in $emuOutput) {
        if ($line -match "^\s*([a-zA-Z0-9_\.\-]+)\s+•\s+(.+?)\s+•") {
            $availableEmus += $Matches[1].Trim()
        }
    }

    if ($availableEmus.Count -gt 0) {
        # Varsa Pixel_9 tercih et, yoksa listedeki ilkini sec
        $targetEmu = if ($availableEmus -contains "Pixel_9") { "Pixel_9" } else { $availableEmus[0] }
        Write-Host "-> '$targetEmu' emulatoru otomatik baslatiliyor..." -ForegroundColor Green
        
        Start-Process flutter -ArgumentList "emulators", "--launch", $targetEmu -WindowStyle Hidden
        Write-Host "-> Emulator penceresinin acilmasi bekleniyor (12 saniye)..." -ForegroundColor Gray
        Start-Sleep -Seconds 12
    } else {
        Write-Host "-> Bilgisayarinizda kayitli emulator bulunamadi. Mevcut cihaz aranacak." -ForegroundColor DarkYellow
    }
} else {
    Write-Host "-> Calisan aktif bir emulator bulundu! Yeniden baslatilmiyor." -ForegroundColor Green
}

# 3. Canli calistirma modu
Write-Host "`n[3/3] Uygulama baslatiliyor (Canli Gelistirme Modu)..." -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  * KOD DEGISIKLIGINDE: 'r' tusuna basin (Hot Reload)" -ForegroundColor Yellow
Write-Host "  * SIFIRDAN BASLATMAK ICIN: 'R' tusuna basin (Restart)" -ForegroundColor Yellow
Write-Host "  * CIKIS YAPMAK ICIN: 'q' tusuna basin (Quit)" -ForegroundColor Yellow
Write-Host "  * RELEASE MODU ICIN: 'RELEASE_BASLAT.bat' dosyasini kullanabilirsiniz" -ForegroundColor Cyan
Write-Host "========================================================`n" -ForegroundColor Cyan

# Calistir
flutter run
