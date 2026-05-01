param(
    [string]$BridgeUrl = $env:ROBLOX_STUDIO_MCP_URL,
    [switch]$AllowDisconnected
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BridgeUrl)) {
    $BridgeUrl = "http://localhost:58741/mcp"
}
$BridgeUrl = $BridgeUrl.TrimEnd("/")

function Get-RobloxMcpRootUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    if ($Url.EndsWith("/mcp")) {
        return $Url.Substring(0, $Url.Length - 4)
    }

    return $Url
}

$bridgeRootUrl = Get-RobloxMcpRootUrl -Url $BridgeUrl

function ConvertFrom-RobloxMcpResponse {
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

    if ($null -ne $Response.content -and $Response.content.Count -gt 0) {
        $text = $Response.content[0].text
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return $text | ConvertFrom-Json
        }
    }

    return $Response
}

function Invoke-RobloxMcpEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [hashtable]$Body = @{}
    )

    $jsonBody = $Body | ConvertTo-Json -Depth 8 -Compress
    $response = Invoke-RestMethod -Uri "$BridgeUrl/$Name" -Method Post -ContentType "application/json" -Body $jsonBody
    $payload = ConvertFrom-RobloxMcpResponse -Response $response

    if ($payload.PSObject.Properties.Name -contains "error") {
        throw "$Name failed: $($payload.error)"
    }

    return $payload
}

function Request-RobloxMcpPluginReconnect {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootUrl
    )

    $pluginPath = Join-Path $env:LOCALAPPDATA "Roblox\Plugins\MCPPlugin.rbxmx"
    if (-not (Test-Path $pluginPath)) {
        return $null
    }

    Write-Host "Studio plugin is not connected; requesting a local MCP plugin hot-reload..."
    (Get-Item $pluginPath).LastWriteTime = Get-Date

    for ($attempt = 1; $attempt -le 8; $attempt++) {
        Start-Sleep -Seconds 2
        $health = Invoke-RestMethod -Uri "$RootUrl/health" -Method Get
        if ($health.pluginConnected) {
            Write-Host "Studio plugin reconnected after hot-reload."
            return $health
        }
    }

    return Invoke-RestMethod -Uri "$RootUrl/health" -Method Get
}

Write-Host "Checking Roblox Studio MCP bridge at $BridgeUrl"

# Start the bridge process if it is not already running, then probe until up.
function Start-McpBridgeIfNeeded {
    $existing = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*robloxstudio-mcp*" -and $_.ProcessId -ne $PID })
    if ($existing.Count -gt 0) {
        return
    }
    Write-Host "Bridge process not found; starting robloxstudio-mcp..." -ForegroundColor Yellow
    Start-Process -FilePath "cmd" -ArgumentList "/c npx -y robloxstudio-mcp@latest" -WindowStyle Hidden
}

$health = $null
$probeAttempts = 20
for ($probe = 1; $probe -le $probeAttempts; $probe++) {
    try {
        $health = Invoke-RestMethod -Uri "$bridgeRootUrl/health" -Method Get -TimeoutSec 3
        break
    }
    catch {
        Start-McpBridgeIfNeeded
        if ($probe -eq $probeAttempts) {
            Write-Error "Roblox Studio MCP bridge offline at $bridgeRootUrl/health after $($probeAttempts * 2)s. $($_.Exception.Message)"
            exit 1
        }
        Write-Host ("Bridge starting, probe {0}/{1}..." -f $probe, $probeAttempts) -ForegroundColor DarkGray
        Start-Sleep -Seconds 2
    }
}

try {
    Write-Host "Server version: $($health.version)"
    Write-Host "MCP server active: $($health.mcpServerActive)"
    Write-Host "Studio plugin connected: $($health.pluginConnected)"
    Write-Host "Registered plugin instances: $($health.instanceCount)"

    if (-not $health.mcpServerActive) {
        throw "The robloxstudio-mcp server is listening, but the MCP server is not active. Restart the VS Code MCP server."
    }

    if (-not $health.pluginConnected -and -not $AllowDisconnected) {
        $reconnectedHealth = Request-RobloxMcpPluginReconnect -RootUrl $bridgeRootUrl
        if ($null -ne $reconnectedHealth) {
            $health = $reconnectedHealth
            Write-Host "Studio plugin connected: $($health.pluginConnected)"
            Write-Host "Registered plugin instances: $($health.instanceCount)"
        }
    }

    if (-not $health.pluginConnected) {
        $message = "The robloxstudio-mcp server is running, but the Studio plugin is not connected. Open Studio, install/enable the robloxstudio-mcp plugin, enable Allow HTTP Requests, and wait for the plugin to show Connected."
        if ($AllowDisconnected) {
            Write-Warning $message
            return
        }

        throw $message
    }

    $services = Invoke-RobloxMcpEndpoint -Name "get_services"
    $serviceCount = if ($services.services) { $services.services.Count } else { 0 }
    Write-Host "get_services OK ($serviceCount services)."

    $instances = Invoke-RobloxMcpEndpoint -Name "get_connected_instances"
    Write-Host "get_connected_instances count: $($instances.count)"
    if ($instances.count -eq 0) {
        Write-Host "This is not a failure by itself; edit-only Studio sessions can still answer MCP tool calls."
    }

    $playtest = Invoke-RobloxMcpEndpoint -Name "get_playtest_output"
    Write-Host "Playtest running: $($playtest.isRunning)"

    Write-Host "Roblox Studio MCP bridge is callable."
}
catch {
    Write-Error "Roblox Studio MCP bridge verification failed. $($_.Exception.Message)"
    exit 1
}
