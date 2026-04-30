#requires -Version 5.1
<#
.SYNOPSIS
    Drive one iteration of the rblcxx Game Concept Refinement Loop.

.DESCRIPTION
    Implements the loop documented in .github/copilot-instructions.md
    ("Game Concept Refinement Loop"). Each invocation performs a single
    pass: snapshot the workspace, refresh the sourcemap, validate Luau
    sources, probe the robloxstudio-mcp bridge for live Studio state,
    and emit a structured next-step checklist that a Copilot agent (or
    a human) can act on. The loop terminates when -Until is satisfied
    or when -MaxIterations is reached. Pass -Once for a single pass.

.PARAMETER MaxIterations
    Maximum number of loop iterations before forced exit.

.PARAMETER Once
    Run exactly one iteration, then exit. Equivalent to -MaxIterations 1.

.PARAMETER QualityFile
    Path to a sentinel file. When the file exists and contains the
    string "DONE" (case-insensitive), the loop exits with success.
    The Copilot agent or the user writes this file to declare quality
    has been reached.

.PARAMETER SkipValidate
    Skip the Luau format/lint validation step (faster iteration).

.PARAMETER SkipMcp
    Skip probing the robloxstudio-mcp bridge.

.PARAMETER SkipStudio
    Do not auto-launch Roblox Studio with the latest .rbxl/.rbxlx place file.

.PARAMETER PlaceFile
    Explicit path to the .rbxl/.rbxlx place file. Defaults to the most
    recently modified place file at the repository root.

.PARAMETER StudioReadyTimeoutSeconds
    Maximum seconds to wait for Roblox Studio to load and the
    robloxstudio-mcp companion plugin to report pluginConnected=true.
#>
param(
    [int]$MaxIterations = 12,
    [switch]$Once,
    [string]$QualityFile = (Join-Path $PSScriptRoot "..\.refine-quality.txt"),
    [switch]$SkipValidate,
    [switch]$SkipMcp,
    [switch]$SkipStudio,
    [string]$PlaceFile,
    [int]$StudioReadyTimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

if ($Once) { $MaxIterations = 1 }

function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    $bar = "=" * 72
    Write-Host ""
    Write-Host $bar -ForegroundColor $Color
    Write-Host " $Text" -ForegroundColor $Color
    Write-Host $bar -ForegroundColor $Color
}

function Test-QualityReached {
    if (-not (Test-Path $QualityFile)) { return $false }
    $content = (Get-Content -LiteralPath $QualityFile -Raw -ErrorAction SilentlyContinue)
    if ($null -eq $content) { return $false }
    return ($content.Trim() -match '^(?i)done$')
}

function Invoke-Step {
    param(
        [string]$Label,
        [scriptblock]$Action
    )
    Write-Host ""
    Write-Host "-> $Label" -ForegroundColor Yellow
    try {
        & $Action
        Write-Host "   ok" -ForegroundColor DarkGray
        return $true
    }
    catch {
        Write-Host ("   FAIL: " + $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

function Get-McpHealth {
    $health = $null
    try {
        $health = Invoke-RestMethod -Uri "http://localhost:58741/health" -Method Get -TimeoutSec 3
    }
    catch {
        return [pscustomobject]@{ Online = $false; Detail = $_.Exception.Message; Raw = $null }
    }
    return [pscustomobject]@{
        Online = $true
        Detail = ($health | ConvertTo-Json -Compress -Depth 5)
        Raw    = $health
    }
}

function Resolve-PlaceFile {
    param([string]$Explicit)
    if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
        if (-not (Test-Path -LiteralPath $Explicit)) {
            throw "PlaceFile not found: $Explicit"
        }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }
    $candidates = Get-ChildItem -Path $repoRoot -File -Include *.rbxl, *.rbxlx -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
    if (-not $candidates -or $candidates.Count -eq 0) {
        # Fallback: non-recursive top-level filter (Get-ChildItem -Include needs -Recurse or wildcard path)
        $candidates = Get-ChildItem -Path (Join-Path $repoRoot '*') -File |
        Where-Object { $_.Extension -in '.rbxl', '.rbxlx' } |
        Sort-Object LastWriteTime -Descending
    }
    if (-not $candidates -or $candidates.Count -eq 0) {
        return $null
    }
    return $candidates[0].FullName
}

function Test-StudioRunning {
    $proc = Get-Process -Name RobloxStudioBeta, RobloxStudio -ErrorAction SilentlyContinue
    return ($null -ne $proc -and $proc.Count -gt 0)
}

function Start-StudioWithPlace {
    param([string]$Path, [int]$TimeoutSeconds)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Place file does not exist: $Path"
    }

    Write-Host ("   place file: " + $Path) -ForegroundColor DarkGray
    if (Test-StudioRunning) {
        Write-Host "   Roblox Studio already running; opening place via shell association" -ForegroundColor DarkGray
    }
    Start-Process -FilePath $Path | Out-Null

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $pluginReady = $false
    $lastDetail = ""
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $h = Get-McpHealth
        if ($h.Online -and $h.Raw -and $h.Raw.pluginConnected -eq $true) {
            $pluginReady = $true
            $lastDetail = $h.Detail
            break
        }
        $lastDetail = if ($h.Online) { $h.Detail } else { $h.Detail }
        Write-Host "   waiting for Studio + MCP companion plugin..." -ForegroundColor DarkGray
    }

    if (-not $pluginReady) {
        throw "Timed out after $TimeoutSeconds s waiting for pluginConnected=true. Last bridge state: $lastDetail"
    }
    Write-Host ("   Studio ready, MCP plugin connected: " + $lastDetail) -ForegroundColor Green
}

function Get-RecentChanges {
    try {
        $out = & git -C $repoRoot status --short 2>$null
        if ($LASTEXITCODE -ne 0) { return @() }
        return ($out | Where-Object { $_ })
    }
    catch { return @() }
}

# Ensure sentinel cleared at start so the prior run does not auto-finish.
if (Test-QualityReached) {
    Write-Host "Quality sentinel already DONE. Clearing for a fresh loop." -ForegroundColor DarkGray
    Remove-Item -LiteralPath $QualityFile -Force -ErrorAction SilentlyContinue
}

# Launch Roblox Studio with the latest place file and wait for the
# robloxstudio-mcp companion plugin to report pluginConnected=true.
if (-not $SkipStudio) {
    Write-Banner "Launching Roblox Studio and waiting for plugin initialization" "Cyan"
    Invoke-Step "resolve and open latest place file" {
        $resolved = Resolve-PlaceFile -Explicit $PlaceFile
        if (-not $resolved) {
            throw "No .rbxl or .rbxlx file found at repository root. Pass -PlaceFile or use -SkipStudio."
        }
        Start-StudioWithPlace -Path $resolved -TimeoutSeconds $StudioReadyTimeoutSeconds
    } | Out-Null
}
else {
    Write-Host "-> Studio launch skipped (-SkipStudio)" -ForegroundColor DarkGray
}

$iteration = 0
$exitCode = 0

while ($iteration -lt $MaxIterations) {
    $iteration++
    Write-Banner ("rblcxx refinement loop  --  iteration {0} / {1}" -f $iteration, $MaxIterations) "Cyan"

    # 1. Workspace snapshot
    Invoke-Step "snapshot working tree (git status)" {
        $changes = Get-RecentChanges
        if ($changes.Count -eq 0) {
            Write-Host "   clean tree" -ForegroundColor DarkGray
        }
        else {
            $changes | ForEach-Object { Write-Host ("   " + $_) -ForegroundColor Gray }
        }
    } | Out-Null

    # 2. Sourcemap refresh
    Invoke-Step "refresh Rojo sourcemap" {
        & rojo sourcemap default.project.json -o sourcemap.json | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "rojo sourcemap exited $LASTEXITCODE" }
    } | Out-Null

    # 3. Luau validation
    $validateOk = $true
    if (-not $SkipValidate) {
        $validateOk = Invoke-Step "stylua --check src" {
            & stylua --check src
            if ($LASTEXITCODE -ne 0) { throw "stylua reported formatting drift" }
        }
        $lintOk = Invoke-Step "selene src" {
            & selene src
            if ($LASTEXITCODE -ne 0) { throw "selene reported lint findings" }
        }
        $validateOk = $validateOk -and $lintOk
    }
    else {
        Write-Host "-> validation skipped (-SkipValidate)" -ForegroundColor DarkGray
    }

    # 4. Studio bridge probe
    $mcp = $null
    if (-not $SkipMcp) {
        Invoke-Step "probe robloxstudio-mcp bridge (localhost:58741)" {
            $script:mcp = Get-McpHealth
            if ($script:mcp.Online) {
                Write-Host ("   bridge online: " + $script:mcp.Detail) -ForegroundColor DarkGray
                $bridgeVersion = $script:mcp.Raw.version
                $pluginVersion = $null
                $pluginManifest = Join-Path $env:LOCALAPPDATA "Roblox\Plugins\MCPPlugin.rbxmx"
                if (Test-Path -LiteralPath $pluginManifest) {
                    $manifestText = Get-Content -LiteralPath $pluginManifest -Raw -ErrorAction SilentlyContinue
                    if ($manifestText -match '(?i)VERSION\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"') {
                        $pluginVersion = $matches[1]
                    }
                }
                if ($bridgeVersion -and $pluginVersion -and ($bridgeVersion -ne $pluginVersion)) {
                    if ($script:mcp.Raw.pluginConnected -and $script:mcp.Raw.instanceCount -gt 0) {
                        Write-Host ("   wire OK: bridge v{0} <-> plugin v{1} (different version labels, protocol-compatible)" -f $bridgeVersion, $pluginVersion) -ForegroundColor DarkGray
                    }
                    else {
                        Write-Host ("   WARNING: bridge v{0} != Studio plugin v{1} and plugin not connected. Run 'Roblox: Reset MCP bridge'." -f $bridgeVersion, $pluginVersion) -ForegroundColor Yellow
                    }
                }
                elseif ($bridgeVersion -and $pluginVersion) {
                    Write-Host ("   versions aligned: bridge v{0} == plugin v{1}" -f $bridgeVersion, $pluginVersion) -ForegroundColor DarkGray
                }
            }
            else {
                Write-Host ("   bridge offline: " + $script:mcp.Detail) -ForegroundColor DarkYellow
            }
        } | Out-Null
    }

    # 5. Next-step checklist
    Write-Host ""
    Write-Host "Refinement checklist for this iteration:" -ForegroundColor Magenta
    Write-Host "  [ ] Re-read product brief: src/ReplicatedStorage/Shared/ArenaDuelConfig.luau"
    Write-Host "  [ ] Identify smallest playable improvement (UI, motion, projectile, camera, input)"
    Write-Host "  [ ] Search owning implementation: file_search / grep / mcp_robloxstudio-_search_files"
    Write-Host "  [ ] Inspect live DataModel: mcp_robloxstudio-_get_connected_instances"
    Write-Host "  [ ] Implement minimal local edit"
    if ($validateOk) {
        Write-Host "  [x] stylua + selene clean" -ForegroundColor Green
    }
    else {
        Write-Host "  [!] resolve stylua/selene findings before continuing" -ForegroundColor Red
    }
    Write-Host "  [ ] Validate in Studio (Rojo serve on 34872)"
    Write-Host "  [ ] If satisfied, write 'DONE' to:" -NoNewline
    Write-Host (" " + $QualityFile) -ForegroundColor White
    Write-Host "     PowerShell:  Set-Content -LiteralPath '$QualityFile' -Value 'DONE'"

    if (Test-QualityReached) {
        Write-Banner "Quality sentinel reached. Loop complete." "Green"
        break
    }

    if ($iteration -ge $MaxIterations) {
        Write-Banner "MaxIterations reached without DONE sentinel." "Yellow"
        $exitCode = 2
        break
    }

    Write-Host ""
    Write-Host "Press Enter to start the next iteration, or Ctrl+C to stop." -ForegroundColor Cyan
    [void](Read-Host)
}

exit $exitCode
