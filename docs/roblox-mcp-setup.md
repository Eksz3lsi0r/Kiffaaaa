# Roblox Studio MCP Setup

This repo uses the `robloxstudio-mcp` package for VS Code to Roblox Studio automation. It is separate from the Luau LSP Studio plugin.

## Required Studio Setup

1. Install the `robloxstudio-mcp` Studio plugin from `https://github.com/boshyxd/robloxstudio-mcp/releases`.
2. In Roblox Studio, enable `Allow HTTP Requests` in Experience Settings > Security.
3. Start the VS Code MCP server from [.vscode/mcp.json](../.vscode/mcp.json), which runs `cmd /c npx -y robloxstudio-mcp@2.6.0` on Windows.
4. Open Studio and wait until the plugin shows `Connected`.
5. Run the `Roblox: Verify MCP bridge` VS Code task.

The `robloxstudio-mcp` bridge listens on **port 58741**. The local bridge endpoint is `http://localhost:58741/mcp` unless `ROBLOX_STUDIO_MCP_URL` is set.

The bridge status endpoint is `http://localhost:58741/health`. It should report `mcpServerActive: true` and `pluginConnected: true` before write tools or playtest automation can run.

If Studio hangs or the health endpoint reports an unexpected server version after updating the plugin, run `Roblox: Reset MCP bridge`. That task stops stale `robloxstudio-mcp` Node processes, clears stale MCP plugin IDE/debugger state, reinstalls the pinned Studio plugin, enables local plugin auto-connect, and clears port `58741` so VS Code can start a fresh MCP server from `.vscode/mcp.json`. Then run `Roblox: Verify MCP bridge`; if the server is active but Studio has not re-registered yet, verification touches the local plugin file once so Studio hot-reloads and reconnects.

## Health Check

Use `get_services` as the health check. A successful response proves the edit-side Studio plugin is reachable and processing MCP requests.

`get_connected_instances` is informational. It lists registered plugin roles such as `edit`, `server`, or `client-1` when the package has registered them, but an empty result does not automatically mean the bridge is broken. In this workspace, edit-side calls such as `get_services`, `execute_luau`, and `start_playtest` are the important automation path.

## 1vsCOM Automation

Run `Roblox: Start 1vsCOM playtest` while Studio is connected. The task:

1. Calls `get_services` to verify the bridge.
2. Sets `ReplicatedStorage` attribute `ArenaDuelAutoQueueMode` to `Bot` through `execute_luau`.
3. Starts Play mode through `start_playtest`.

The client reads that attribute in Studio and fires the existing server `QueueRequest` remote. This keeps the match path server-authoritative and avoids relying on MCP client UI clicks.

Run `Roblox: Clear 1vsCOM autoqueue` to remove the attribute before manual playtests.

## Troubleshooting

- If `Roblox: Verify MCP bridge` cannot reach `58741`, start Studio, enable the `robloxstudio-mcp` plugin, and confirm the plugin says `Connected`.
- If `/health` reports `pluginConnected: false`, the MCP server is running but Studio is not connected to it yet.
- If `pluginConnected: false` appears right after a reset, run `Roblox: Verify MCP bridge` again. Verification hot-reloads the local plugin after the MCP server is back; if Studio still does not reconnect, reload Studio once.
- If `/health` reports an older server version than `.vscode/mcp.json`, run `Roblox: Reset MCP bridge`, then restart the VS Code MCP server and reload Studio.
- If requests time out, confirm `Allow HTTP Requests` is enabled for the experience.
- If `get_connected_instances` returns `count: 0` but `get_services` succeeds, continue using the edit-side automation path.
- If `Roblox: Start 1vsCOM playtest` reports `A test is already running`, run `stop_playtest` or stop Play mode in Studio, then retry.
