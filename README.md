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
3. Start `rojo serve default.project.json`.
4. In Roblox Studio, connect using the Rojo plugin and edit the live game.
5. Let Luau LSP autogenerate `sourcemap.json` for editor navigation.
6. Before adding new gameplay data or remotes, read `copilot-instructions.md`, `default.project.json`, and the matching Shared, Server, or Client module so you extend the existing structure instead of duplicating it.

## Useful tasks

- `Roblox: Install toolchain`
- `Roblox: Install packages`
- `Roblox: Generate sourcemap`
- `Roblox: Serve project`
- `Luau: Lint`
- `Luau: Format check`
