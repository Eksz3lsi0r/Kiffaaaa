# rblcxx

Roblox Studio game workspace for VS Code with Rojo, Wally, Luau LSP, StyLua, and Selene.

## Included

- Rojo project mapping in `default.project.json`
- Wally package manifest in `wally.toml`
- Aftman-managed CLI toolchain in `aftman.toml`
- Luau formatter and linter configuration
- VS Code recommendations, settings, and tasks
- Minimal client, server, and shared bootstrap scripts

## Daily workflow

1. Run `aftman install` if you update `aftman.toml`.
2. Run `wally install` when you add dependencies.
3. Start `rojo serve default.project.json`.
4. In Roblox Studio, connect using the Rojo plugin.
5. Let Luau LSP autogenerate `sourcemap.json` for editor navigation.

## Useful tasks

- `Roblox: Install toolchain`
- `Roblox: Install packages`
- `Roblox: Generate sourcemap`
- `Roblox: Serve project`
- `Luau: Lint`
- `Luau: Format check`
