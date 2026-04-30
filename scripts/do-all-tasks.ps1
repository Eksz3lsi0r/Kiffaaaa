#requires -Version 5.1
param(
    [switch]$Once,
    [int]$LoopDelaySeconds = 5,
    [int]$McpRetryAttempts = 3,
    [string]$QualityFile = (Join-Path $PSScriptRoot "..\.refine-quality.txt"),
    [switch]$ForceSetup,
    [switch]$SkipRojoServe,
    [switch]$SkipPlaytest,
    [int]$StudioReadyTimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    $bar = "=" * 72
    Write-Host ""
    Write-Host $bar -ForegroundColor $Color
    Write-Host (" " + $Text) -ForegroundColor $Color
    Write-Host $bar -ForegroundColor $Color
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

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $health = Get-McpHealth
        if ($health -and $health.pluginConnected -eq $true) {
            return $true
        }

        Write-Host "   waiting for MCP bridge/plugin connection..." -ForegroundColor DarkGray
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

function Invoke-ManagedScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$Arguments = @()
    )

    & powershell -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments | Out-Host
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
        $ready = $false
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            if (Test-IsPortListening -Port 34872) {
                $ready = $true
                break
            }

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

$startPlaytestScript = Join-Path $PSScriptRoot "start-1vscom-playtest.ps1"
$iteration = 0

while ($true) {
    $iteration++
    Write-Banner ("do-all loop iteration " + $iteration) "Magenta"

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
        Invoke-Step "start/update 1vsCOM playtest automation" {
            Invoke-ManagedScript -Path $startPlaytestScript
        } -ContinueOnError | Out-Null
    }
    else {
        Write-Host "-> playtest automation skipped (-SkipPlaytest)" -ForegroundColor DarkGray
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
    Start-Sleep -Seconds $LoopDelaySeconds
}
