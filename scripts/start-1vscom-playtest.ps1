param(
    [switch]$Clear
)

$ErrorActionPreference = "Stop"

$bridgeUrl = $env:ROBLOX_STUDIO_MCP_URL
if ([string]::IsNullOrWhiteSpace($bridgeUrl)) {
    $bridgeUrl = "http://localhost:58741/mcp"
}
$bridgeUrl = $bridgeUrl.TrimEnd("/")

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

$bridgeRootUrl = Get-RobloxMcpRootUrl -Url $bridgeUrl

function Invoke-RobloxMcpEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [hashtable]$Body
    )

    $jsonBody = $Body | ConvertTo-Json -Depth 8 -Compress
    $response = Invoke-RestMethod -Uri "$bridgeUrl/$Name" -Method Post -ContentType "application/json" -Body $jsonBody

    if ($null -ne $response.content -and $response.content.Count -gt 0) {
        $text = $response.content[0].text
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $payload = $text | ConvertFrom-Json
            if ($payload.PSObject.Properties.Name -contains "error") {
                throw "$Name failed: $($payload.error)"
            }

            return $payload
        }
    }

    if ($response.PSObject.Properties.Name -contains "error") {
        throw "$Name failed: $($response.error)"
    }

    return $response
}

try {
    $health = Invoke-RestMethod -Uri "$bridgeRootUrl/health" -Method Get
    if (-not $health.pluginConnected) {
        throw "The robloxstudio-mcp server is running, but the Studio plugin is not connected. Open Studio, install/enable the robloxstudio-mcp plugin, enable Allow HTTP Requests, and wait for the plugin to show Connected."
    }

    Invoke-RobloxMcpEndpoint -Name "get_services" -Body @{} | Out-Null

    if ($Clear) {
        Invoke-RobloxMcpEndpoint -Name "execute_luau" -Body @{
            code = 'game:GetService("ReplicatedStorage"):SetAttribute("ArenaDuelAutoQueueMode", nil)'
        } | Out-Null

        Write-Host "Cleared ArenaDuelAutoQueueMode."
        return
    }

    Invoke-RobloxMcpEndpoint -Name "execute_luau" -Body @{
        code = 'game:GetService("ReplicatedStorage"):SetAttribute("ArenaDuelAutoQueueMode", "Bot")'
    } | Out-Null

    Invoke-RobloxMcpEndpoint -Name "start_playtest" -Body @{
        mode = "play"
        numPlayers = 1
    } | Out-Null

    Write-Host "Started Studio Play mode with ArenaDuelAutoQueueMode=Bot."
} catch {
    Write-Error "Could not run the 1vsCOM Studio automation through $bridgeUrl. Install/enable the robloxstudio-mcp Studio plugin, enable Allow HTTP Requests, make sure the plugin shows Connected, then rerun this task. $($_.Exception.Message)"
    exit 1
}
