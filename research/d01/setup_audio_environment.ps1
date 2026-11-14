param(
    [string]$EnvironmentDirectory = '',
    [string]$ModelDirectory = ''
)
$ErrorActionPreference = 'Stop'
$repoDirectory = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$dataDirectory = Split-Path $repoDirectory -Parent
if (-not $EnvironmentDirectory) { $EnvironmentDirectory = Join-Path $dataDirectory 'calisma/venv_d01_audio_20261108_01' }
if (-not $ModelDirectory) { $ModelDirectory = Join-Path $dataDirectory 'calisma/models/d01_faster_whisper_small' }
$baselinePython = Join-Path $dataDirectory '.venv_headpose/Scripts/python.exe'
$hybridPackages = Join-Path $dataDirectory 'calisma/venv_d01_hybrid_20261107_01/Lib/site-packages'
if (-not (Test-Path -LiteralPath $baselinePython) -or -not (Test-Path -LiteralPath $hybridPackages)) { throw 'Existing Python/hybrid packages missing' }
$audioPython = Join-Path $EnvironmentDirectory 'Scripts/python.exe'
if (-not (Test-Path -LiteralPath $audioPython)) {
    & $baselinePython -m venv $EnvironmentDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Audio environment creation failed' }
}
# Read-only reuse of existing vision dependencies; pip writes only to NEW venv.
$linkFile = Join-Path $EnvironmentDirectory 'Lib/site-packages/d01_existing_hybrid_readonly.pth'
[IO.File]::WriteAllText($linkFile, $hybridPackages + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
& $audioPython -m pip install --ignore-installed --disable-pip-version-check faster-whisper
if ($LASTEXITCODE -ne 0) { throw 'Audio package installation failed; no model download or analysis started' }
& $audioPython -m pip check
if ($LASTEXITCODE -ne 0) { throw 'Audio dependency validation failed' }
& $audioPython -X utf8 -c "import faster_whisper, ctranslate2, mediapipe, cv2; print('Audio and vision imports passed')"
if ($LASTEXITCODE -ne 0) { throw 'Audio/vision import failed' }
if (Test-Path -LiteralPath $ModelDirectory) {
    Write-Host 'Model target exists; preserve it. Inspect preparation record or pass a NEW -ModelDirectory.'
}
& $audioPython -X utf8 -B (Join-Path $PSScriptRoot 'prepare_audio_model.py') --download --output-dir $ModelDirectory
if ($LASTEXITCODE -ne 0) { throw 'Model preparation failed; do not start real acceptance' }
Write-Output 'Preparation complete; existing model/runtime environments preserved. No videos analysed.'
