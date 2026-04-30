# rblcxx

Roblox Studio game workspace for VS Code with Rojo, Wally, Luau LSP, StyLua, Selene, and repo-level Copilot instructions.

## Included

- Rojo project mapping in `default.project.json`
- Shared gameplay definitions in `src/ReplicatedStorage/Shared`
- Server gameplay systems in `src/ServerScriptService`
- Client HUD and input code in `src/StarterPlayer/StarterPlayerScripts`
- Wally package manifest in `wally.toml`
- Aftman-managed CLI toolchain in `aftman.toml`
- Luau formatter and linter configuration
- VS Code recommendations, settings, tasks, and Copilot instructions
- Minimal client, server, and shared bootstrap scripts

## Daily workflow

1. Run `aftman install` when `aftman.toml` changes.
2. Run `wally install` when you add or update dependencies.
3. Start `rojo serve default.project.json --port 34872`.
4. In Roblox Studio, connect using the Rojo plugin and edit the live game.
5. Let Luau LSP autogenerate `sourcemap.json` for editor navigation.
6. Before adding new gameplay data or remotes, read `copilot-instructions.md`, `default.project.json`, and the matching Shared, Server, or Client module so you extend the existing structure instead of duplicating it.

## Luau LSP Studio Plugin

The workspace already uses the current VS Code settings in `.vscode/settings.json`:

- `luau-lsp.studioPlugin.enabled`
- `luau-lsp.studioPlugin.port`

Older snippets may still mention `luau-lsp.plugin.enabled` and `luau-lsp.plugin.port`. Those names are deprecated aliases and should be updated to the `studioPlugin` form.

The recommended copy-paste config for this repo lives in `luau-lsp-studio-plugin.luau`.

That example is tuned for this workspace instead of using the broad generic watch list:

- `startAutomatically = true` so Studio reconnects without manual steps
- `port = 3667` to match `.vscode/settings.json`
- `include` limited to `Workspace`, `ReplicatedStorage`, `ServerScriptService`, and `StarterPlayer`, which matches the services this repo actively owns

This Luau LSP plugin is separate from `robloxstudio-mcp`, which uses its own Studio plugin and local bridge on port `58741`.

## Roblox Studio MCP 1vsCOM Test

This section covers `robloxstudio-mcp`, the VS Code MCP server and Studio plugin that talks to Studio through the local bridge on port `58741`. It is separate from the Luau LSP Studio plugin on port `3667` described above.

The `robloxstudio-mcp` bridge may expose only the edit instance during playtests. To automate the single-player 1vsCOM path anyway, run the `Roblox: Start 1vsCOM playtest` VS Code task while Studio and the `robloxstudio-mcp` plugin are active.

The `Roblox: Serve project` task pins Rojo to `localhost:34872`, which keeps the Studio Rojo plugin connection stable across restarts.

Run `Roblox: Verify MCP bridge` first when diagnosing setup issues. It uses `get_services` as the health check, prints `get_connected_instances` as informational output, and can hot-reload the local MCP plugin if the bridge is active but Studio has not registered yet.

The task uses `robloxstudio-mcp` to set a replicated Studio attribute before starting Play mode:

```lua
game:GetService("ReplicatedStorage"):SetAttribute("ArenaDuelAutoQueueMode", "Bot")
```

When the client starts in Studio, it reads that attribute and fires the existing `QueueRequest` remote with `"Bot"`. The server still owns the actual match creation and validation, so this exercises the same path as the `1vsCOM Test` button without needing MCP to click a client UI element.

Clear the attribute after the automated run when you want manual playtests again:

```lua
game:GetService("ReplicatedStorage"):SetAttribute("ArenaDuelAutoQueueMode", nil)
```

You can also run the `Roblox: Clear 1vsCOM autoqueue` task.

See [docs/roblox-mcp-setup.md](docs/roblox-mcp-setup.md) for the complete Roblox Studio MCP setup and troubleshooting checklist.

## Useful tasks

- `Roblox: Install toolchain`
- `Roblox: Install packages`
- `Roblox: Generate sourcemap`
- `Roblox: Serve project`
- `Roblox: Reset MCP bridge`
- `Roblox: Verify MCP bridge`
- `Roblox: Start 1vsCOM playtest`
- `Roblox: Clear 1vsCOM autoqueue`
- `Luau: Lint`
- `Luau: Format check`
