[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$backendDir = Split-Path -Parent $PSScriptRoot
$baseCompose = Join-Path $backendDir 'compose.yaml'
$smokeCaddyfile = Join-Path $PSScriptRoot 'deployment_smoke.Caddyfile'
$id = [Guid]::NewGuid().ToString('N').Substring(0, 16)
$project = "noro-smoke-$id"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) $project
$envFile = Join-Path $tempRoot 'compose.env'
$overrideFile = Join-Path $tempRoot 'compose.override.yaml'
$fakeTeamKey = "smoke_$id"
$dataVolume = "noro_smoke_${id}_caddy_data"
$configVolume = "noro_smoke_${id}_caddy_config"
$composeWasStarted = $false
$cleanupFailed = $false
$exitCode = 0
$script:currentStage = 'Hazırlık'

function ConvertTo-ProcessArgument([string] $Value) {
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Get-SafeDiagnostic {
    param(
        [string] $Text,
        [int] $MaxLines = 3,
        [switch] $FromEnd
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return 'Compose açıklama vermedi.'
    }

    $allLines = @($Text -split '\r?\n')
    $safeLines = @($allLines | Where-Object {
        $_ -notmatch '(?i)(TEAM_ACCESS_KEY|GEMINI_API_KEY|Authorization|SMOKE_TEAM_ACCESS_KEY)'
    })
    if ($FromEnd) {
        $safeLines = @($safeLines | Select-Object -Last $MaxLines)
    }
    else {
        $safeLines = @($safeLines | Select-Object -First $MaxLines)
    }
    $safeText = ($safeLines -join ' ').Trim()
    $safeText = $safeText.Replace($fakeTeamKey, '[gizlendi]')
    $safeText = $safeText.Replace($tempRoot, '[geçici test klasörü]')
    $safeText = $safeText.Replace($tempRoot.Replace('\', '/'), '[geçici test klasörü]')
    $safeText = $safeText.Replace($backendDir, '[backend]')
    $safeText = $safeText.Replace($backendDir.Replace('\', '/'), '[backend]')
    if ($env:USERPROFILE) {
        $safeText = $safeText.Replace($env:USERPROFILE, '[kullanıcı yolu]')
        $safeText = $safeText.Replace($env:USERPROFILE.Replace('\', '/'), '[kullanıcı yolu]')
    }
    $safeText = [System.Text.RegularExpressions.Regex]::Replace(
        $safeText,
        '(?i)(password|secret|token|key)\s*[:=]\s*[^\s,;]+|\bBearer\s+[A-Za-z0-9._~+/-]+=*',
        '$1=[gizlendi]'
    )
    if ($safeText.Length -gt 2200) {
        $safeText = $safeText.Substring(0, 2200) + '…'
    }
    if ([string]::IsNullOrWhiteSpace($safeText)) {
        return 'Hassas yapılandırma içerebilecek Compose açıklaması gizlendi.'
    }
    return $safeText
}

function Invoke-DockerCapture {
    param(
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [Parameter(Mandatory = $true)][int] $TimeoutSeconds
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'docker'
    $startInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument ([string] $_) }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Docker komutu başlatılamadı.'
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        [void] $process.WaitForExit(3000)
        $process.Dispose()
        return [pscustomobject]@{
            ExitCode = 124
            StdOut = ''
            StdErr = "Docker komutu $TimeoutSeconds saniyelik sınırı aştı."
        }
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $processExitCode = $process.ExitCode
    $process.Dispose()
    return [pscustomobject]@{
        ExitCode = $processExitCode
        StdOut = $stdout
        StdErr = $stderr
    }
}

function Assert-DockerDaemon {
    $result = Invoke-DockerCapture -Arguments @('info', '--format', '{{.ServerVersion}}') -TimeoutSeconds 10
    if ($result.ExitCode -ne 0) {
        throw "Docker daemon ön kontrolü başarısız (çıkış $($result.ExitCode)): $(Get-SafeDiagnostic $result.StdErr)"
    }
}

function Invoke-DockerCompose {
    param(
        [Parameter(Mandatory = $true)][string[]] $ComposeArguments,
        [Parameter(Mandatory = $true)][int] $TimeoutSeconds,
        [Parameter(Mandatory = $true)][string] $Stage,
        [switch] $ReturnOutput
    )

    $arguments = @(
        'compose',
        '--project-name', $project,
        '--env-file', $envFile,
        '--file', $baseCompose,
        '--file', $overrideFile
    ) + $ComposeArguments

    $result = Invoke-DockerCapture -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
    if ($result.ExitCode -ne 0) {
        $diagnostic = Get-SafeDiagnostic $result.StdErr
        throw "Compose aşaması '$Stage' başarısız (çıkış $($result.ExitCode)): $diagnostic"
    }
    if ($ReturnOutput) {
        return $result.StdOut
    }
}

function Write-SmokeFailureDiagnostics {
    Write-Host "Tanılama kapsamı: yalnız Compose projesi '$project'."
    $idResult = Invoke-DockerCapture -Arguments @(
        'ps', '--all', '--quiet', '--filter', "label=com.docker.compose.project=$project"
    ) -TimeoutSeconds 10
    if ($idResult.ExitCode -ne 0) {
        Write-Host "Test projesi container listesi alınamadı: $(Get-SafeDiagnostic $idResult.StdErr)"
        return
    }

    $containerIds = @($idResult.StdOut -split '\r?\n' | Where-Object { $_ -match '^[a-fA-F0-9]+$' })
    if ($containerIds.Count -eq 0) {
        Write-Host 'Test projesinde container bulunamadı.'
    }
    else {
        $inspectFormat = '{{.Name}} state={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}} exit={{.State.ExitCode}}'
        $statusResult = Invoke-DockerCapture -Arguments (@('inspect', '--format', $inspectFormat) + $containerIds) -TimeoutSeconds 10
        if ($statusResult.ExitCode -eq 0) {
            foreach ($line in @($statusResult.StdOut -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
                Write-Host "Container: $(Get-SafeDiagnostic $line -MaxLines 1)"
            }
        }
        else {
            Write-Host "Test projesi container durumu alınamadı: $(Get-SafeDiagnostic $statusResult.StdErr)"
        }
    }

    foreach ($service in @('backend', 'caddy')) {
        $serviceIdResult = Invoke-DockerCapture -Arguments @(
            'ps', '--all', '--quiet',
            '--filter', "label=com.docker.compose.project=$project",
            '--filter', "label=com.docker.compose.service=$service"
        ) -TimeoutSeconds 10
        if ($serviceIdResult.ExitCode -ne 0) {
            Write-Host "$service container kimlikleri alınamadı: $(Get-SafeDiagnostic $serviceIdResult.StdErr)"
            continue
        }
        foreach ($containerId in @($serviceIdResult.StdOut -split '\r?\n' | Where-Object { $_ -match '^[a-fA-F0-9]+$' })) {
            $logResult = Invoke-DockerCapture -Arguments @('logs', '--tail', '12', $containerId) -TimeoutSeconds 8
            if ($logResult.ExitCode -eq 0) {
                $excerpt = Get-SafeDiagnostic ($logResult.StdOut + [Environment]::NewLine + $logResult.StdErr) -MaxLines 12 -FromEnd
            }
            else {
                $excerpt = Get-SafeDiagnostic $logResult.StdErr -MaxLines 3
            }
            Write-Host "Son $service log satırları: $excerpt"
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $baseCompose -PathType Leaf) -or
        -not (Test-Path -LiteralPath $smokeCaddyfile -PathType Leaf)) {
        throw 'Compose veya yerel HTTP Caddy yapılandırması bulunamadı.'
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI bulunamadı; geçici Compose kaynakları oluşturulmadı.'
    }
    $script:currentStage = 'Docker daemon ön kontrolü'
    Assert-DockerDaemon

    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $caddyPath = $smokeCaddyfile.Replace('\', '/')
    $environmentLines = @(
        'PUBLIC_DOMAIN=smoke.invalid'
        "SMOKE_TEAM_ACCESS_KEY=$fakeTeamKey"
        "SMOKE_CADDYFILE=$caddyPath"
        "SMOKE_DATA_VOLUME=$dataVolume"
        "SMOKE_CONFIG_VOLUME=$configVolume"
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($envFile, $environmentLines, $utf8NoBom)

    # --env-file selects this temporary file for interpolation. !reset removes
    # the base service's .env reference; !override replaces public TLS ports.
    # These merge tags require Docker Compose v2.24.4 or newer.
    $override = @'
services:
  backend:
    env_file: !reset []
    environment:
      BACKEND_MODE: deployment
      NODE_ENV: production
      PORT: "8000"
      TEAM_ACCESS_KEY: ${SMOKE_TEAM_ACCESS_KEY}
      GENERATION_MAX_CONCURRENT: "1"
  caddy:
    ports: !override []
    volumes: !override
      - "${SMOKE_CADDYFILE}:/etc/caddy/Caddyfile:ro"
      - caddy_data:/data
      - caddy_config:/config
networks:
  default:
    internal: true
volumes:
  caddy_data:
    name: ${SMOKE_DATA_VOLUME}
  caddy_config:
    name: ${SMOKE_CONFIG_VOLUME}
'@
    [System.IO.File]::WriteAllText($overrideFile, $override, $utf8NoBom)

    $script:currentStage = 'Compose yapılandırma kontrolü'
    Invoke-DockerCompose -ComposeArguments @('config', '--quiet') -TimeoutSeconds 20 -Stage $script:currentStage

    # The internal network blocks provider egress. --pull never/--no-build use
    # only the already-built backend image and do not modify its tag.
    $script:currentStage = 'Compose servislerini başlatma (up)'
    $composeWasStarted = $true
    Invoke-DockerCompose -ComposeArguments @('up', '--detach', '--no-build', '--pull', 'never', '--wait', '--wait-timeout', '60') -TimeoutSeconds 75 -Stage $script:currentStage

    $nodeSmokeScript = @'
(async()=>{const base='http://caddy';const deadline=Date.now()+30000;const signalFor=left=>AbortSignal.timeout(Math.max(1,Math.min(5000,left)));const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));async function health(){let last='';while(Date.now()<deadline){let response;try{response=await fetch(base+'/health',{signal:signalFor(deadline-Date.now())});}catch(error){last=error.name+': '+error.message;if(Date.now()<deadline)await sleep(200);continue;}if(response.status!==200)throw new Error('GET /health expected HTTP 200, got '+response.status);console.log('PASS GET /health '+response.status);return;}throw new Error('GET /health timed out: '+last);}async function check(method,path,expected){const remaining=deadline-Date.now();if(remaining<=0)throw new Error('total timeout before '+path);const options={method,signal:signalFor(remaining)};if(method==='POST'){options.headers={'content-type':'application/json'};options.body='{}';}const response=await fetch(base+path,options);if(response.status!==expected)throw new Error(method+' '+path+' expected HTTP '+expected+', got '+response.status);console.log('PASS '+method+' '+path+' '+response.status);}await health();for(const path of ['/api/generate-scenario-input','/api/compare-scenario','/api/generate-clip-plan'])await check('POST',path,401);for(const path of ['/api/generate-scenario','/api/analyze-video'])await check('POST',path,404);})().catch(error=>{console.error('SMOKE_FAIL '+error.message);process.exitCode=1;});
'@
    $script:currentStage = 'Container içinden Caddy proxy HTTP kontrolleri'
    $smokeOutput = Invoke-DockerCompose -ComposeArguments @('exec', '-T', 'backend', 'node', '-e', $nodeSmokeScript) -TimeoutSeconds 35 -Stage $script:currentStage -ReturnOutput
    foreach ($line in @($smokeOutput -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        Write-Host (Get-SafeDiagnostic $line -MaxLines 1)
    }
    Write-Host 'PASS: istekler backend container Node fetch üzerinden Caddy service adına gönderildi. Windows host loopback erişimi bu testle ölçülmedi.'
}
catch {
    $message = $_.Exception.Message.Replace($fakeTeamKey, '[gizlendi]')
    $message = $message.Replace($tempRoot, '[geçici test klasörü]').Replace($backendDir, '[backend]')
    if ($message -match '^Compose aşaması') {
        Write-Host "FAIL: $message" -ForegroundColor Red
    }
    else {
        Write-Host "FAIL: $script:currentStage — $message" -ForegroundColor Red
    }
    $exitCode = 1
    if ($composeWasStarted) {
        try {
            Write-SmokeFailureDiagnostics
        }
        catch {
            Write-Host "Test projesi tanılaması alınamadı: $(Get-SafeDiagnostic $_.Exception.Message)"
        }
    }
}
finally {
    if ($composeWasStarted -and (Test-Path -LiteralPath $overrideFile -PathType Leaf)) {
        try {
            Invoke-DockerCompose -ComposeArguments @('down', '--volumes', '--remove-orphans', '--timeout', '5') -TimeoutSeconds 20 -Stage 'temizlik (down)'
        }
        catch {
            $cleanupFailed = $true
            $exitCode = 1
            $cleanupMessage = $_.Exception.Message.Replace($fakeTeamKey, '[gizlendi]')
            $cleanupMessage = $cleanupMessage.Replace($tempRoot, '[geçici test klasörü]').Replace($backendDir, '[backend]')
            Write-Warning "Yalnız '$project' test Compose projesinin temizliği başarısız: $cleanupMessage. Geçici test yapılandırması korundu: [geçici test klasörü]"
        }
    }
    if (-not $cleanupFailed -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

if ($exitCode -ne 0) {
    exit $exitCode
}
