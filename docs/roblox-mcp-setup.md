# Roblox Studio MCP Setup

This repo now targets the official Roblox Studio MCP server built into Roblox Studio. It is separate from the Luau LSP Studio plugin.

## Required Studio Setup

1. Update Roblox Studio to a build that includes Studio MCP.
2. In Roblox Studio, open Assistant.
3. Click `...` -> `Manage MCP Servers`.
4. Turn on `Enable Studio as MCP server`.
5. If `Visual Studio Code` appears in the Quick connect list, enable it. Otherwise use the workspace config in [.vscode/mcp.json](../.vscode/mcp.json).
6. Restart VS Code or restart the Roblox MCP server entry if the tools do not appear immediately.

## VS Code Workspace Configuration

VS Code workspace MCP config uses the official built-in Studio launcher in [.vscode/mcp.json](../.vscode/mcp.json):

```json
{
 "servers": {
  "Roblox_Studio": {
   "command": "cmd.exe",
   "args": [
    "/c",
    "%LOCALAPPDATA%\\Roblox\\mcp.bat"
   ]
  }
 }
}
```

The Roblox documentation also provides the same Windows launch command for clients that accept a raw CLI entry: `cmd.exe /c %LOCALAPPDATA%\\Roblox\\mcp.bat`.

VS Code uses the `servers` schema in `.vscode/mcp.json`, not the generic `mcpServers` wrapper shown in some client-agnostic examples.

## Verify Connection

After setup, verify the connection in Studio:

1. Open Assistant.
2. Click `...` -> `Manage MCP Servers`.
3. Confirm the green indicator appears for the connected client.

In VS Code, you can also use MCP server management and output logs to confirm the server started cleanly.

When multiple Studio windows are open, use `list_roblox_studios` and `set_active_studio` to switch targets explicitly.

## Current Repo Caveat

The following repo scripts and tasks have not been migrated yet and still target the older `robloxstudio-mcp` HTTP bridge on port `58741`:

- `scripts/verify-roblox-mcp.ps1`
- `scripts/reset-roblox-mcp.ps1`
- `scripts/start-1vscom-playtest.ps1`
- `scripts/do-all-tasks.ps1`
- `scripts/refine-game-concept.ps1`

Those scripts are legacy utilities now. They do not use the official built-in Studio MCP transport described above.

Until they are ported, prefer the built-in Studio MCP tools directly from chat for editing, inspection, playtesting, and multi-instance selection.

## Troubleshooting

- Restart both Roblox Studio and VS Code if the MCP tools do not appear.
- Verify that `%LOCALAPPDATA%\\Roblox\\mcp.bat` exists on disk.
- Check `.vscode/mcp.json` for missing commas or brackets if the server does not start.
- If Quick connect does not list VS Code, restart Studio after installing or updating VS Code.
- If multiple Studio instances are running and a tool hits the wrong one, switch with `list_roblox_studios` and `set_active_studio`.
- Only connect MCP clients you trust, because they can read and modify your open places.
