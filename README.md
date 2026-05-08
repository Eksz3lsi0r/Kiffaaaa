# rblcxx

Roblox Studio game workspace for VS Code with Rojo, Wally, Luau LSP, StyLua, Selene, and repo-level Copilot instructions.

## Included

- Rojo project mapping in `default.project.json`
- Shared gameplay definitions in `src/ReplicatedStorage/Shared`
- Server gameplay systems in `src/ServerScriptService`
- Client HUD and input code in `src/StarterPlayer/StarterPlayerScripts`
- Wally package manifest in `wally.toml`
- Generated package output in `Packages/`
- Aftman-managed CLI toolchain in `aftman.toml`
- Luau formatter and linter configuration
- VS Code recommendations, settings, tasks, and Copilot instructions
- Minimal client, server, and shared bootstrap scripts

## Daily workflow

1. Run the `Roblox: Setup workspace` task after cloning, changing `aftman.toml`, changing `wally.toml`, or editing Rojo mappings.
2. Start the `Roblox: Serve project` task to run `rojo serve default.project.json --port 34872`.
3. In Roblox Studio, connect using the Rojo plugin and edit the live game.
4. Let Luau LSP autogenerate `sourcemap.json` for editor navigation; run `Roblox: Generate sourcemap` manually after Rojo mapping changes if you need an immediate refresh.
5. Before adding new gameplay data or remotes, read `copilot-instructions.md`, `default.project.json`, and the matching Shared, Server, or Client module so you extend the existing structure instead of duplicating it.
6. Run `Luau: Validate` before finishing Luau source changes.

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

This Luau LSP plugin is separate from the official Roblox Studio MCP server, which is built into Studio and can be launched for VS Code from `.vscode/mcp.json`.

## Wally Package Manager

Wally is the package manager for third-party Roblox Luau libraries. In this repo, `wally.toml` is the source of truth for dependencies, `wally install` restores them into top-level `Packages/`, and Rojo maps that folder to `ReplicatedStorage.Packages` through `default.project.json`.

Use the existing VS Code task `Roblox: Install packages` after changing `wally.toml`. That refreshes `Packages/` and the generated `wally.lock` state. If package changes affect types or module paths, follow it with `Roblox: Generate sourcemap` or just run `Roblox: Setup workspace`.

Keep `Packages/` treated as generated output. Do not hand-edit it; update dependency versions in `wally.toml`, reinstall, and then validate the gameplay code that consumes those packages.

## Roblox Studio MCP

This workspace now uses the official Roblox Studio MCP server that is built into Studio. It is separate from the Luau LSP Studio plugin on port `3667` described above.

The shared VS Code workspace config lives in `.vscode/mcp.json` and starts Studio MCP on Windows with `cmd.exe /c %LOCALAPPDATA%\\Roblox\\mcp.bat`.

In Studio, open Assistant, then `...` -> `Manage MCP Servers`, and turn on `Enable Studio as MCP server`. If `Visual Studio Code` appears under Quick connect, you can enable it there as well.

After connection, Studio shows a green indicator with the number of connected clients. When multiple Studio windows are open, use the MCP tools `list_roblox_studios` and `set_active_studio` to target the intended instance.

The old PowerShell automation tasks in this repo still target the legacy `robloxstudio-mcp` HTTP bridge on port `58741`. Until those scripts are migrated, use the built-in Studio MCP tools directly from chat for script edits, inspection, and playtest control.

See [docs/roblox-mcp-setup.md](docs/roblox-mcp-setup.md) for the updated setup and the current legacy-task caveats.

## Useful tasks

- `Roblox: Install toolchain`
- `Roblox: Install packages`
- `Roblox: Generate sourcemap`
- `Roblox: Setup workspace`
- `Roblox: Serve project`
- `Roblox: Reset MCP bridge` (legacy bridge task)
- `Roblox: Verify MCP bridge` (legacy bridge task)
- `Roblox: Start 1vsCOM playtest` (legacy bridge task)
- `Roblox: Clear 1vsCOM autoqueue` (legacy bridge task)
- `Luau: Lint`
- `Luau: Format check`
- `Luau: Validate`
