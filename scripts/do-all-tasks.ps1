#requires -Version 5.1
param(
    [switch]$Once,
    [int]$MaxIterations = 12,
    [int]$LoopDelaySeconds = 2,
    [int]$McpRetryAttempts = 3,
    [string]$QualityFile = (Join-Path $PSScriptRoot "..\.refine-quality.txt"),
    [switch]$ForceSetup,
    [switch]$SkipRojoServe,
    [switch]$SkipPlaytest,
    [int]$StudioReadyTimeoutSeconds = 180,
    [int]$PlaytestRunSeconds = 75,
    [int]$AiAnalysisTimeoutSeconds = 300,
    [string]$GameBrief = "",
    [string]$GameBriefFile = (Join-Path $PSScriptRoot "..\.game-brief.txt"),
    [string]$LiveTelemetryPath = (Join-Path $PSScriptRoot "..\.playtest-live.json"),
    [int]$LivePollSeconds = 3
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

function Resolve-RepoPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return (Join-Path $repoRoot $Path)
}

$QualityFile = Resolve-RepoPath -Path $QualityFile
$GameBriefFile = Resolve-RepoPath -Path $GameBriefFile
$LiveTelemetryPath = Resolve-RepoPath -Path $LiveTelemetryPath

function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    $bar = "=" * 72
    Write-Host ""
    Write-Host $bar -ForegroundColor $Color
    Write-Host (" " + $Text) -ForegroundColor $Color
    Write-Host $bar -ForegroundColor $Color
}

function Write-WaitHeartbeat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [datetime]$StartedAt,

        [Parameter(Mandatory = $true)]
        [datetime]$Deadline,

        [string]$Status = ""
    )

    $now = Get-Date
    $elapsedSeconds = [Math]::Round(($now - $StartedAt).TotalSeconds, 1)
    $remainingSeconds = [Math]::Max(0, [Math]::Ceiling(($Deadline - $now).TotalSeconds))
    $message = "   wait: {0} | elapsed={1}s remaining~{2}s" -f $Label, $elapsedSeconds, $remainingSeconds

    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $message += " | " + $Status
    }

    Write-Host $message -ForegroundColor DarkGray
}

function Invoke-Step {
    param(
        [string]$Label,
        [scriptblock]$Action,
        [switch]$ContinueOnError
    )

    Write-Host ""
    Write-Host ("-> " + $Label) -ForegroundColor Yellow
    try {
        & $Action
        Write-Host "   ok" -ForegroundColor DarkGray
        return $true
    }
    catch {
        $message = "   FAIL: " + $_.Exception.Message
        if ($ContinueOnError) {
            Write-Host $message -ForegroundColor Red
            return $false
        }
        throw
    }
}

function Test-QualityReached {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        return $false
    }

    return ($content.Trim() -match '^(?i)done$')
}

function Get-GameBriefText {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        return ""
    }

    return $content.Trim()
}

function Save-GameBrief {
    param(
        [string]$Path,
        [string]$Brief
    )

    if ([string]::IsNullOrWhiteSpace($Brief)) {
        return
    }

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Set-Content -LiteralPath $Path -Value $Brief.Trim() -Encoding UTF8
}

function Test-IsPortListening {
    param([int]$Port)

    try {
        $listeners = @(Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq "Listen" }
        )
        return ($listeners.Count -gt 0)
    }
    catch {
        return $false
    }
}

function Resolve-PlaceFile {
    $candidates = @(Get-ChildItem -Path (Join-Path $repoRoot "*") -File |
        Where-Object { $_.Extension -in ".rbxl", ".rbxlx" } |
        Sort-Object LastWriteTime -Descending
    )

    if (-not $candidates -or $candidates.Count -eq 0) {
        return $null
    }

    return $candidates[0].FullName
}

function Test-StudioRunning {
    $proc = @(Get-Process -Name RobloxStudioBeta, RobloxStudio -ErrorAction SilentlyContinue)
    return ($proc.Count -gt 0)
}

function Get-McpHealth {
    try {
        return Invoke-RestMethod -Uri "http://localhost:58741/health" -Method Get -TimeoutSec 3
    }
    catch {
        return $null
    }
}

function Wait-ForMcpPlugin {
    param([int]$TimeoutSeconds)

    $startedAt = Get-Date
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $health = Get-McpHealth
        if ($health -and $health.pluginConnected -eq $true) {
            return $true
        }

        $status = if ($health) {
            "pluginConnected=" + $health.pluginConnected
        }
        else {
            "health=unreachable"
        }

        Write-WaitHeartbeat -Label "MCP bridge/plugin connection" -StartedAt $startedAt -Deadline $deadline -Status $status
        Start-Sleep -Seconds 2
    }

    return $false
}

function Test-WallyHasDependencies {
    $wallyPath = Join-Path $repoRoot "wally.toml"
    if (-not (Test-Path -LiteralPath $wallyPath)) {
        return $false
    }

    $inDependencies = $false
    foreach ($line in Get-Content -LiteralPath $wallyPath) {
        $trimmed = $line.Trim()

        if ($trimmed -match '^\[.*\]$') {
            $inDependencies = ($trimmed -eq "[dependencies]")
            continue
        }

        if (-not $inDependencies) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
            continue
        }

        if ($trimmed -match '^[A-Za-z0-9_.-]+\s*=') {
            return $true
        }
    }

    return $false
}

function Test-PackagesInstallNeeded {
    param([switch]$Force)

    if ($Force) {
        return $true
    }

    if (-not (Test-WallyHasDependencies)) {
        return $false
    }

    $packagesPath = Join-Path $repoRoot "Packages"
    if (-not (Test-Path -LiteralPath $packagesPath)) {
        return $true
    }

    $packageFiles = @(Get-ChildItem -Path $packagesPath -Recurse -File -ErrorAction SilentlyContinue)
    if (-not $packageFiles -or $packageFiles.Count -eq 0) {
        return $true
    }

    $packageNewest = ($packageFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime

    $manifestItems = @()
    foreach ($manifest in @("wally.toml", "wally.lock")) {
        $manifestPath = Join-Path $repoRoot $manifest
        if (Test-Path -LiteralPath $manifestPath) {
            $manifestItems += Get-Item -LiteralPath $manifestPath
        }
    }

    if ($manifestItems.Count -eq 0) {
        return $false
    }

    $manifestNewest = ($manifestItems | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    return $manifestNewest -gt $packageNewest
}

function Test-SourcemapRefreshNeeded {
    param([switch]$Force)

    if ($Force) {
        return $true
    }

    $sourcemapPath = Join-Path $repoRoot "sourcemap.json"
    if (-not (Test-Path -LiteralPath $sourcemapPath)) {
        return $true
    }

    $sourcemapTime = (Get-Item -LiteralPath $sourcemapPath).LastWriteTime

    $dependencies = @()
    foreach ($path in @("default.project.json", "aftman.toml", "wally.toml", "wally.lock")) {
        $fullPath = Join-Path $repoRoot $path
        if (Test-Path -LiteralPath $fullPath) {
            $dependencies += Get-Item -LiteralPath $fullPath
        }
    }

    $srcPath = Join-Path $repoRoot "src"
    if (Test-Path -LiteralPath $srcPath) {
        $dependencies += @(Get-ChildItem -Path $srcPath -Recurse -File -ErrorAction SilentlyContinue)
    }

    if ($dependencies.Count -eq 0) {
        return $false
    }

    $newestDependency = ($dependencies | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    return $newestDependency -gt $sourcemapTime
}

function Show-LuauLspStudioSettings {
    $settingsPath = Join-Path $repoRoot ".vscode/settings.json"
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        Write-Host "   .vscode/settings.json not found; skipping Luau LSP settings check." -ForegroundColor DarkYellow
        return
    }

    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $enabled = $settings.'luau-lsp.studioPlugin.enabled'
    $port = $settings.'luau-lsp.studioPlugin.port'

    Write-Host ("   luau-lsp.studioPlugin.enabled = " + $enabled) -ForegroundColor DarkGray
    Write-Host ("   luau-lsp.studioPlugin.port = " + $port) -ForegroundColor DarkGray

    if ($enabled -ne $true -or $port -ne 3667) {
        Write-Host "   WARNING: Luau LSP Studio plugin settings differ from this repo's expected values." -ForegroundColor Yellow
    }
}

function Invoke-McpTool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tool,

        [hashtable]$Body = @{}
    )

    $jsonBody = $Body | ConvertTo-Json -Depth 8 -Compress
    $response = Invoke-RestMethod -Uri "http://localhost:58741/mcp/$Tool" -Method Post `
        -ContentType "application/json" -Body $jsonBody -TimeoutSec 20

    if ($null -ne $response.content -and $response.content.Count -gt 0) {
        $text = $response.content[0].text
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            try {
                return ($text | ConvertFrom-Json)
            }
            catch {
                return $text
            }
        }
    }

    return $response
}

function Get-PlaytestSnapshot {
    param([int]$OutputLogLines = 160)

    $snapshot = [ordered]@{
        timestamp      = (Get-Date -Format "o")
        isRunning      = $false
        playtestOutput = $null
        outputLog      = $null
        playtestError  = $null
        outputLogError = $null
    }

    try {
        $playtest = Invoke-McpTool -Tool "get_playtest_output" -Body @{}
        $snapshot.playtestOutput = $playtest

        if ($playtest -and $playtest.PSObject.Properties.Name -contains "isRunning") {
            $snapshot.isRunning = [bool]$playtest.isRunning
        }
    }
    catch {
        $snapshot.playtestError = $_.Exception.Message
    }

    try {
        $snapshot.outputLog = Invoke-McpTool -Tool "get_output_log" -Body @{ maxLines = $OutputLogLines }
    }
    catch {
        $snapshot.outputLogError = $_.Exception.Message
    }

    return [pscustomobject]$snapshot
}

function Write-JsonFile {
    param(
        [string]$Path,
        $Value
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-PlaytestCycle {
    param(
        [Parameter(Mandatory = $true)]
        [int]$RunSeconds,

        [Parameter(Mandatory = $true)]
        [string]$ReportPath,

        [Parameter(Mandatory = $true)]
        [string]$LivePath,

        [Parameter(Mandatory = $true)]
        [string]$GameBriefPath,

        [Parameter(Mandatory = $true)]
        [int]$PollSeconds
    )

    # Check if a playtest is already running
    $playtestRunning = $false
    try {
        $statusCheck = Invoke-McpTool -Tool "get_playtest_output" -Body @{}
        if ($null -ne $statusCheck.isRunning) {
            $playtestRunning = [bool]$statusCheck.isRunning
        }
        elseif ($statusCheck.content -and $statusCheck.content.Count -gt 0) {
            $parsed = $statusCheck.content[0].text | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($null -ne $parsed -and $null -ne $parsed.isRunning) {
                $playtestRunning = [bool]$parsed.isRunning
            }
        }
    }
    catch {}

    if ($playtestRunning) {
        Write-Host "   Playtest already running; stopping it first..." -ForegroundColor DarkGray
        try { Invoke-McpTool -Tool "stop_playtest" -Body @{} | Out-Null } catch {}
        Write-Host "   Waiting 3s for the previous playtest to shut down cleanly..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 3
    }

    # Set bot auto-queue attribute then start a fresh playtest
    Invoke-McpTool -Tool "execute_luau" -Body @{
        code = 'game:GetService("ReplicatedStorage"):SetAttribute("ArenaDuelAutoQueueMode", "Bot")'
    } | Out-Null

    Write-Host "   Starting playtest..." -ForegroundColor DarkGray
    Invoke-McpTool -Tool "start_playtest" -Body @{ mode = "play"; numPlayers = 1 } | Out-Null
    Write-Host "   Playtest started." -ForegroundColor DarkGray

    $gameBriefText = Get-GameBriefText -Path $GameBriefPath
    $liveTelemetry = [ordered]@{
        timestamp        = (Get-Date -Format "o")
        iteration        = $script:iteration
        runSeconds       = $RunSeconds
        pollSeconds      = $PollSeconds
        gameBriefPath    = $GameBriefPath
        gameBrief        = $gameBriefText
        reportPath       = $ReportPath
        playtestLivePath = $LivePath
        samples          = @()
    }
    Write-JsonFile -Path $LivePath -Value $liveTelemetry

    Write-Host ("   Running for " + $RunSeconds + " seconds with live telemetry...") -ForegroundColor DarkGray
    $startedAt = Get-Date
    $deadline = $startedAt.AddSeconds($RunSeconds)
    while ((Get-Date) -lt $deadline) {
        $snapshot = Get-PlaytestSnapshot
        $elapsedSeconds = [Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
        $sample = [ordered]@{
            timestamp      = (Get-Date -Format "o")
            elapsedSeconds = $elapsedSeconds
            isRunning      = $snapshot.isRunning
            playtestOutput = $snapshot.playtestOutput
            outputLog      = $snapshot.outputLog
            playtestError  = $snapshot.playtestError
            outputLogError = $snapshot.outputLogError
        }

        $liveTelemetry.samples += [pscustomobject]$sample
        $liveTelemetry.lastSample = [pscustomobject]$sample
        $liveTelemetry.isRunning = $snapshot.isRunning
        Write-JsonFile -Path $LivePath -Value $liveTelemetry

        $playtestOutputCount = if (
            $snapshot.playtestOutput -and $snapshot.playtestOutput.PSObject.Properties.Name -contains "outputCount"
        ) {
            $snapshot.playtestOutput.outputCount
        }
        else {
            "n/a"
        }

        $outputLogCount = if (
            $snapshot.outputLog -and $snapshot.outputLog.PSObject.Properties.Name -contains "count"
        ) {
            $snapshot.outputLog.count
        }
        else {
            "n/a"
        }

        $statusParts = @(
            ("running=" + $snapshot.isRunning),
            ("playtestOutputCount=" + $playtestOutputCount),
            ("outputLogCount=" + $outputLogCount)
        )

        if ($snapshot.playtestError) {
            $statusParts += "playtestError"
        }

        if ($snapshot.outputLogError) {
            $statusParts += "outputLogError"
        }

        Write-WaitHeartbeat -Label "playtest telemetry" -StartedAt $startedAt -Deadline $deadline -Status ($statusParts -join " ")

        Start-Sleep -Seconds ([Math]::Max(1, $PollSeconds))
    }

    $finalSnapshotBeforeStop = Get-PlaytestSnapshot -OutputLogLines 300

    # Stop playtest
    Write-Host "   Stopping playtest..." -ForegroundColor DarkGray
    try {
        Invoke-McpTool -Tool "stop_playtest" -Body @{} | Out-Null
        Write-Host "   Playtest stopped." -ForegroundColor DarkGray
    }
    catch {
        Write-Host ("   stop_playtest: " + $_.Exception.Message) -ForegroundColor DarkYellow
    }

    $finalSnapshotAfterStop = Get-PlaytestSnapshot -OutputLogLines 300

    # Write structured report
    $report = [ordered]@{
        timestamp           = (Get-Date -Format "o")
        iteration           = $script:iteration
        gameBriefPath       = $GameBriefPath
        gameBrief           = $gameBriefText
        liveTelemetryPath   = $LivePath
        playtestOutput      = $finalSnapshotBeforeStop.playtestOutput
        outputLog           = $finalSnapshotAfterStop.outputLog
        finalBeforeStop     = $finalSnapshotBeforeStop
        finalAfterStop      = $finalSnapshotAfterStop
        liveSampleCount     = $liveTelemetry.samples.Count
        liveTelemetrySample = $liveTelemetry.lastSample
    }
    Write-JsonFile -Path $ReportPath -Value $report
    Write-Host ("   Report saved: " + $ReportPath) -ForegroundColor Cyan
}

function Invoke-ManagedScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$Arguments = @()
    )

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw ((Split-Path -Leaf $Path) + " exited with code " + $LASTEXITCODE)
    }
}

function Invoke-McpVerifyWithRetries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VerifyScriptPath,

        [int]$Attempts = 3,
        [int]$RetryDelaySeconds = 2
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            Invoke-ManagedScript -Path $VerifyScriptPath
            return
        }
        catch {
            if ($attempt -ge $Attempts) {
                throw
            }

            Write-Host (
                "   MCP verify attempt " + $attempt + "/" + $Attempts + " failed; retrying..."
            ) -ForegroundColor DarkYellow
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

Write-Banner "Roblox do-all bootstrap" "Cyan"

if (-not [string]::IsNullOrWhiteSpace($GameBrief)) {
    Invoke-Step "save game brief" {
        Save-GameBrief -Path $GameBriefFile -Brief $GameBrief
        Write-Host ("   saved to: " + $GameBriefFile) -ForegroundColor DarkGray
    } | Out-Null
}

$activeGameBrief = Get-GameBriefText -Path $GameBriefFile
if ([string]::IsNullOrWhiteSpace($activeGameBrief)) {
    Write-Host "-> no game brief set yet (.game-brief.txt is empty)" -ForegroundColor DarkYellow
}
else {
    Write-Host ("-> active game brief: " + $activeGameBrief) -ForegroundColor DarkGray
}

Write-Host ("-> game brief file: " + $GameBriefFile) -ForegroundColor DarkGray
Write-Host ("-> live telemetry file: " + $LiveTelemetryPath) -ForegroundColor DarkGray
if ($MaxIterations -le 0) {
    Write-Host "-> max iterations: unbounded" -ForegroundColor DarkGray
}
else {
    Write-Host ("-> max iterations: " + $MaxIterations) -ForegroundColor DarkGray
}

$requiredCommands = @("rojo", "wally", "stylua", "selene")
$missingCommands = @()
foreach ($commandName in $requiredCommands) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        $missingCommands += $commandName
    }
}

if ($ForceSetup -or $missingCommands.Count -gt 0) {
    Invoke-Step "install toolchain (aftman install)" {
        if (-not (Get-Command "aftman" -ErrorAction SilentlyContinue)) {
            throw "aftman is not available on PATH. Install aftman and re-run."
        }

        & aftman install --no-trust-check
        if ($LASTEXITCODE -ne 0) {
            throw "aftman install exited with code $LASTEXITCODE"
        }
    } | Out-Null
}
else {
    Write-Host "-> install toolchain skipped (commands already available)" -ForegroundColor DarkGray
}

if (Test-PackagesInstallNeeded -Force:$ForceSetup) {
    Invoke-Step "install packages (wally install)" {
        & wally install
        if ($LASTEXITCODE -ne 0) {
            throw "wally install exited with code $LASTEXITCODE"
        }
    } | Out-Null
}
else {
    Write-Host "-> install packages skipped (Packages/ is up to date)" -ForegroundColor DarkGray
}

if (Test-SourcemapRefreshNeeded -Force:$ForceSetup) {
    Invoke-Step "generate sourcemap" {
        & rojo sourcemap default.project.json -o sourcemap.json
        if ($LASTEXITCODE -ne 0) {
            throw "rojo sourcemap exited with code $LASTEXITCODE"
        }
    } | Out-Null
}
else {
    Write-Host "-> generate sourcemap skipped (sourcemap is up to date)" -ForegroundColor DarkGray
}

if ($SkipRojoServe) {
    Write-Host "-> rojo serve skipped (-SkipRojoServe)" -ForegroundColor DarkGray
}
elseif (Test-IsPortListening -Port 34872) {
    Write-Host "-> rojo serve skipped (port 34872 already listening)" -ForegroundColor DarkGray
}
else {
    Invoke-Step "start rojo serve on port 34872" {
        $proc = Start-Process -FilePath "rojo" -ArgumentList @("serve", "default.project.json", "--port", "34872") -WorkingDirectory $repoRoot -PassThru
        $rojoWaitStartedAt = Get-Date
        $rojoWaitDeadline = $rojoWaitStartedAt.AddSeconds(20)
        $ready = $false
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            if (Test-IsPortListening -Port 34872) {
                $ready = $true
                break
            }

            Write-WaitHeartbeat -Label "rojo serve port 34872" -StartedAt $rojoWaitStartedAt -Deadline $rojoWaitDeadline -Status ("attempt " + $attempt + "/20")
            Start-Sleep -Seconds 1
        }

        if (-not $ready) {
            throw "rojo serve did not open port 34872"
        }
        Write-Host ("   rojo serve started (PID " + $proc.Id + ")") -ForegroundColor DarkGray
    } | Out-Null
}

Invoke-Step "launch Roblox Studio if needed" {
    $placeFile = Resolve-PlaceFile
    if (-not $placeFile) {
        throw "No .rbxl or .rbxlx place file found at repository root."
    }

    if (-not (Test-StudioRunning)) {
        Write-Host ("   opening place file: " + $placeFile) -ForegroundColor DarkGray
        Start-Process -FilePath $placeFile | Out-Null
    }
    else {
        Write-Host "   Roblox Studio already running." -ForegroundColor DarkGray
    }
} | Out-Null

$verifyScript = Join-Path $PSScriptRoot "verify-roblox-mcp.ps1"
$resetScript = Join-Path $PSScriptRoot "reset-roblox-mcp.ps1"

$bridgeOk = Invoke-Step "verify MCP bridge" {
    Invoke-McpVerifyWithRetries -VerifyScriptPath $verifyScript -Attempts $McpRetryAttempts
} -ContinueOnError

if (-not $bridgeOk) {
    Invoke-Step "reset MCP bridge and reinstall plugin" {
        Invoke-ManagedScript -Path $resetScript -Arguments @("-InstallPlugin")
    } -ContinueOnError | Out-Null

    $bridgeOk = Invoke-Step "verify MCP bridge after reset" {
        Invoke-McpVerifyWithRetries -VerifyScriptPath $verifyScript -Attempts $McpRetryAttempts
    } -ContinueOnError

    if (-not $bridgeOk) {
        Write-Host "MCP bridge is still not ready after reset. Continuing; next loop iteration will retry." -ForegroundColor Yellow
    }
}

Invoke-Step "check Luau LSP Studio plugin settings" {
    Show-LuauLspStudioSettings
} | Out-Null

if (-not $Once -and (Test-QualityReached -Path $QualityFile)) {
    Write-Host "Quality sentinel already DONE. Clearing for a fresh do-all loop." -ForegroundColor DarkGray
    Remove-Item -LiteralPath $QualityFile -Force -ErrorAction SilentlyContinue
}

$reportPath = Join-Path $repoRoot ".playtest-report.json"
$awaitingSentinel = Join-Path $repoRoot ".awaiting-ai-analysis"
$doneSentinel = Join-Path $repoRoot ".ai-analysis-applied"

Remove-Item -LiteralPath $awaitingSentinel -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $doneSentinel -Force -ErrorAction SilentlyContinue

$iteration = 0

while ($MaxIterations -le 0 -or $iteration -lt $MaxIterations) {
    $iteration++
    $iterationLabel = if ($MaxIterations -gt 0) {
        "do-all loop iteration {0}/{1}" -f $iteration, $MaxIterations
    }
    else {
        "do-all loop iteration " + $iteration
    }
    Write-Banner $iterationLabel "Magenta"

    $activeGameBrief = Get-GameBriefText -Path $GameBriefFile
    if (-not [string]::IsNullOrWhiteSpace($activeGameBrief)) {
        Write-Host ("Goal brief: " + $activeGameBrief) -ForegroundColor DarkGray
    }

    if (Test-QualityReached -Path $QualityFile) {
        Write-Banner "Quality sentinel reached. Loop complete." "Green"
        break
    }

    $formatOk = Invoke-Step "stylua --check src" {
        & stylua --check src
        if ($LASTEXITCODE -ne 0) {
            throw "stylua reported formatting drift"
        }
    } -ContinueOnError

    if (-not $formatOk) {
        Invoke-Step "stylua src (auto-format)" {
            & stylua src
            if ($LASTEXITCODE -ne 0) {
                throw "stylua format pass exited with code $LASTEXITCODE"
            }
        } -ContinueOnError | Out-Null

        $formatOk = Invoke-Step "stylua --check src (recheck)" {
            & stylua --check src
            if ($LASTEXITCODE -ne 0) {
                throw "stylua still reports formatting drift"
            }
        } -ContinueOnError
    }

    $lintOk = Invoke-Step "selene src" {
        & selene src
        if ($LASTEXITCODE -ne 0) {
            throw "selene reported lint findings"
        }
    } -ContinueOnError

    $bridgeHealthy = Invoke-Step "verify MCP bridge" {
        Invoke-McpVerifyWithRetries -VerifyScriptPath $verifyScript -Attempts $McpRetryAttempts
    } -ContinueOnError

    if (-not $bridgeHealthy) {
        Invoke-Step "reset MCP bridge and retry" {
            Invoke-ManagedScript -Path $resetScript -Arguments @("-InstallPlugin")
            Invoke-McpVerifyWithRetries -VerifyScriptPath $verifyScript -Attempts $McpRetryAttempts
        } -ContinueOnError | Out-Null
    }

    if (-not $SkipPlaytest) {
        if ($bridgeHealthy) {
            $playtestOk = Invoke-Step ("playtest cycle (start -> run " + $PlaytestRunSeconds + "s -> collect -> stop)") {
                Invoke-PlaytestCycle `
                    -RunSeconds $PlaytestRunSeconds `
                    -ReportPath $reportPath `
                    -LivePath $LiveTelemetryPath `
                    -GameBriefPath $GameBriefFile `
                    -PollSeconds $LivePollSeconds
            } -ContinueOnError

            if ($playtestOk) {
                "AWAITING" | Set-Content -LiteralPath $awaitingSentinel -Encoding UTF8
                Write-Host "" -ForegroundColor Yellow
                Write-Host ("=" * 72) -ForegroundColor Yellow
                Write-Host " AWAITING AI ANALYSIS" -ForegroundColor Yellow
                Write-Host (" Brief  : " + $GameBriefFile) -ForegroundColor Yellow
                Write-Host (" Live   : " + $LiveTelemetryPath) -ForegroundColor Yellow
                Write-Host (" Report : " + $reportPath) -ForegroundColor Yellow
                Write-Host " Copilot will read the report, apply code changes, then" -ForegroundColor Yellow
                Write-Host (" write   : " + $doneSentinel) -ForegroundColor Yellow
                Write-Host " Loop resumes automatically once that file appears." -ForegroundColor Yellow
                Write-Host ("=" * 72) -ForegroundColor Yellow

                $analysisApplied = $false
                $analysisStartedAt = Get-Date
                $aiDeadline = (Get-Date).AddSeconds($AiAnalysisTimeoutSeconds)
                while ((Get-Date) -lt $aiDeadline) {
                    if (Test-Path -LiteralPath $doneSentinel) {
                        Remove-Item -LiteralPath $doneSentinel -Force -ErrorAction SilentlyContinue
                        Remove-Item -LiteralPath $awaitingSentinel -Force -ErrorAction SilentlyContinue
                        Write-Host "   AI analysis applied. Resuming loop." -ForegroundColor Green
                        $analysisApplied = $true
                        break
                    }

                    $qualityReached = Test-QualityReached -Path $QualityFile
                    if ($qualityReached) { break }

                    $reportLastWrite = if (Test-Path -LiteralPath $reportPath) {
                        (Get-Item -LiteralPath $reportPath).LastWriteTime.ToString("HH:mm:ss")
                    }
                    else {
                        "missing"
                    }

                    $liveLastWrite = if (Test-Path -LiteralPath $LiveTelemetryPath) {
                        (Get-Item -LiteralPath $LiveTelemetryPath).LastWriteTime.ToString("HH:mm:ss")
                    }
                    else {
                        "missing"
                    }

                    $status = @(
                        "waiting for Copilot mission handoff",
                        ("doneSentinel=missing"),
                        ("reportUpdated=" + $reportLastWrite),
                        ("liveUpdated=" + $liveLastWrite)
                    ) -join " | "

                    Write-WaitHeartbeat -Label "AI analysis handoff" -StartedAt $analysisStartedAt -Deadline $aiDeadline -Status $status
                    Start-Sleep -Seconds 3
                }

                if (-not $analysisApplied -and -not (Test-QualityReached -Path $QualityFile)) {
                    Remove-Item -LiteralPath $awaitingSentinel -Force -ErrorAction SilentlyContinue
                    Write-Host (
                        "   AI analysis timeout reached; continuing with the current workspace state."
                    ) -ForegroundColor DarkYellow
                }
            }
        }
        else {
            Write-Host "-> playtest cycle skipped (MCP bridge not healthy)" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "-> playtest cycle skipped (-SkipPlaytest)" -ForegroundColor DarkGray
    }

    if ($formatOk -and $lintOk -and $bridgeHealthy) {
        Write-Host "All automated checks passed this iteration." -ForegroundColor Green
    }
    else {
        Write-Host "Checks found issues; loop will continue for the next cycle." -ForegroundColor Yellow
    }

    if ($Once) {
        break
    }

    if (Test-QualityReached -Path $QualityFile) {
        Write-Banner "Quality sentinel reached. Loop complete." "Green"
        break
    }

    Write-Host "Press Ctrl+C to stop, or write DONE to .refine-quality.txt to finish automatically." -ForegroundColor Cyan
    $loopPauseStartedAt = Get-Date
    $loopPauseDeadline = $loopPauseStartedAt.AddSeconds($LoopDelaySeconds)
    Write-WaitHeartbeat -Label "next do-all cycle" -StartedAt $loopPauseStartedAt -Deadline $loopPauseDeadline -Status "cooldown before the next iteration"
    Start-Sleep -Seconds $LoopDelaySeconds
}

if (-not $Once -and $MaxIterations -gt 0 -and -not (Test-QualityReached -Path $QualityFile)) {
    Write-Banner (
        "Maximum iteration count reached ({0}). Stopping loop safely." -f $MaxIterations
    ) "Yellow"
}
