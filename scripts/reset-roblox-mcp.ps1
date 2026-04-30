param(
    [string]$PackageVersion = "latest",
    [switch]$InstallPlugin
)

$ErrorActionPreference = "Stop"

function Enable-McpPluginAutoConnect {
    $pluginPath = Join-Path $env:LOCALAPPDATA "Roblox\Plugins\MCPPlugin.rbxmx"
    if (-not (Test-Path $pluginPath)) {
        Write-Warning "MCP plugin file was not found at $pluginPath; skipping auto-connect patch."
        return
    }

    $source = Get-Content -Path $pluginPath -Raw
    if ($source -like "*Communication.activatePlugin(0)*") {
        Write-Host "Roblox Studio MCP plugin auto-connect patch is already applied."
        return
    }

    $anchor = "UI.updateUIState()`r`nCommunication.checkForUpdates()"
    if (-not $source.Contains($anchor)) {
        $anchor = "UI.updateUIState()`nCommunication.checkForUpdates()"
    }

    if (-not $source.Contains($anchor)) {
        Write-Warning "Could not find MCP plugin startup anchor; skipping auto-connect patch."
        return
    }

    $replacement = $anchor.Replace("Communication.checkForUpdates()", "Communication.activatePlugin(0)`r`nCommunication.checkForUpdates()")
    $source = $source.Replace($anchor, $replacement)
    [System.IO.File]::WriteAllText($pluginPath, $source, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Enabled Roblox Studio MCP plugin auto-connect."
}

Write-Host "Resetting robloxstudio-mcp bridge processes..."

$pluginStateDir = Join-Path $env:LOCALAPPDATA "Roblox\pluginIDEState"
if (Test-Path $pluginStateDir) {
    $pluginStateFiles = Get-ChildItem -Path $pluginStateDir -Filter "pluginIDEState_user_MCPPlugin.rbxmx_*.xml" -File -ErrorAction SilentlyContinue
    if ($pluginStateFiles.Count -gt 0) {
        Write-Host "Clearing Roblox Studio MCP plugin IDE/debugger state..."
        $pluginStateFiles | Remove-Item -Force -ErrorAction Stop
    }
}

$mcpProcesses = Get-CimInstance Win32_Process |
Where-Object {
    $_.CommandLine -like "*robloxstudio-mcp*" -and $_.ProcessId -ne $PID
} |
Select-Object ProcessId, Name, CommandLine

if ($mcpProcesses.Count -eq 0) {
    Write-Host "No robloxstudio-mcp Node processes were running."
}
else {
    foreach ($process in $mcpProcesses) {
        Write-Host "Stopping PID $($process.ProcessId): $($process.Name)"
        Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
    }
}

if ($InstallPlugin) {
    Write-Host "Installing Roblox Studio MCP plugin for robloxstudio-mcp@$PackageVersion..."
    & npx -y "robloxstudio-mcp@$PackageVersion" --install-plugin
    if ($LASTEXITCODE -ne 0) {
        throw "Could not install robloxstudio-mcp@$PackageVersion Studio plugin."
    }

    Enable-McpPluginAutoConnect
}

$activePortOwners = Get-NetTCPConnection -LocalPort 58741 -ErrorAction SilentlyContinue |
Where-Object {
    $_.State -in @("Listen", "Established", "SynSent", "SynReceived") -and $_.OwningProcess -ne 0
} |
Select-Object LocalAddress, LocalPort, State, OwningProcess

$timeWaitConnections = Get-NetTCPConnection -LocalPort 58741 -ErrorAction SilentlyContinue |
Where-Object { $_.State -eq "TimeWait" }

if ($activePortOwners) {
    Write-Warning "Port 58741 is already active after reset:"
    $activePortOwners | Format-Table -AutoSize
    Write-Warning "If Studio still hangs, restart VS Code's MCP server or reload VS Code so .vscode/mcp.json can start a fresh bridge."
}
else {
    if ($timeWaitConnections) {
        Write-Host "Port 58741 only has transient TimeWait connections; that is safe after a reset."
    }
    else {
        Write-Host "Port 58741 is clear."
    }

    Write-Host "Restart the VS Code MCP server, then run Roblox: Verify MCP bridge to trigger the plugin hot-reload/reconnect check."
}
