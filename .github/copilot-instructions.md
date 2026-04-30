# Copilot Instructions for rblcxx

## Source of Truth

- Treat `default.project.json` and `src/` as the canonical game structure.
- Treat `.vscode/settings.json`, `.luaurc`, `stylua.toml`, `selene.toml`, `aftman.toml`, and `wally.toml` as human-edited configuration.
- Treat `sourcemap.json` and installed package output as generated artifacts. Regenerate them instead of editing them by hand.

## Working Model

- Start from one concrete anchor: a file, symbol, failing behavior, failing task, or validation error.
- Read only the minimum local context needed before the first edit: the touched file, one caller or callee, `default.project.json`, and one nearby similar implementation when it exists.
- Before editing, form one falsifiable local hypothesis and one cheap check that could disconfirm it.
- Prefer small, reversible edits and validate immediately after the first substantive change.

## Roblox Architecture

- Keep shared, deterministic, environment-agnostic code in `src/ReplicatedStorage/Shared`.
- Keep authoritative gameplay state, validation, remote creation, timers, rewards, and anti-exploit logic on the server in `src/ServerScriptService`.
- Keep UI, camera, input, client-only presentation, and cosmetic feedback on the client in `src/StarterPlayer/StarterPlayerScripts`.
- Shared modules may be required by both client and server. Shared code must not require client-only or server-only modules.
- Prefer explicit Luau types at module boundaries, for remote payloads, and for public helper functions.

## File and Naming Conventions

- Use `.server.luau` for server entry points and `.client.luau` for client entry points.
- Use `game:GetService()` for service access.
- Use `WaitForChild()` for replicated instances that may not exist yet on the client.
- Keep GUI instance names in PascalCase and function names in camelCase.
- Follow the repo formatter and linter configuration: strict Luau, StyLua formatting, and Selene with the `roblox` standard library.

## Networking Rules

- Define remote names, payload shapes, and shared constants in shared modules when a feature grows beyond a single bootstrap script.
- Create remotes on the server exactly once, then consume them from client and server code via `ReplicatedStorage`.
- Validate every client-to-server payload on the server for type, range, ownership, rate, and authority.
- Prefer `RemoteEvent` for gameplay updates and notifications. Use `RemoteFunction` only when a request must synchronously return a small value.
- Keep network payloads small and stable. Prefer identifiers and compact state over large tables or instance graphs.
- Remember that client-to-server remote traffic is rate limited; avoid high-frequency request spam.

## Luau LSP and Studio

- This workspace is configured for the VS Code `JohnnyMorganz.luau-lsp` extension.
- Use the current VS Code setting names `luau-lsp.studioPlugin.enabled` and `luau-lsp.studioPlugin.port` in `.vscode/settings.json`.
- Older docs may still mention `luau-lsp.plugin.enabled` and `luau-lsp.plugin.port`; those names are deprecated aliases and should not be reintroduced unless compatibility requires them.
- Keep Luau LSP in Roblox mode with Rojo sourcemap support enabled.
- If Rojo mappings or entry points change, regenerate `sourcemap.json` from `default.project.json`.
- **Studio plugin port reference (all three are distinct):**
  | Plugin | Purpose | Port |
  |---|---|---|
  | Rojo Studio Plugin | Filesystem ↔ Studio live sync | `34872` |
  | Luau LSP Companion Plugin | Live DataModel instance types for IntelliSense | `3667` |
  | robloxstudio-mcp Plugin | AI/Copilot → Studio automation via MCP bridge | `58741` |
- This repo sets `luau-lsp.studioPlugin.port` to `3667` in `.vscode/settings.json` and `luau-lsp-studio-plugin.luau`. The upstream extension default differs; always verify the local setting before referencing port numbers.

## Workspace Tooling

- Use `Roblox: Setup workspace` after cloning or when toolchain, Wally, or Rojo mapping config changes.
- Wally is the package manager for third-party Luau libraries. The manifest lives in `wally.toml`, resolved dependencies are written into `Packages/`, and Rojo maps that folder to `ReplicatedStorage.Packages`; treat installed package output as generated.
- After editing `wally.toml`, run `Roblox: Install packages` to refresh `Packages/`, then run `Roblox: Generate sourcemap` or `Roblox: Setup workspace` so Luau LSP sees the new package tree.
- Keep `Packages/` and other generated package output out of manual edits; update dependencies in `wally.toml`, install them, then validate the affected gameplay code.
- Use `Roblox: Serve project` for Rojo sync on port `34872`, then connect the Roblox Studio Rojo plugin to the local server.
- Use `Roblox: Verify MCP bridge` before Studio automation and `Roblox: Reset MCP bridge` when the local `robloxstudio-mcp` bridge or Studio plugin state is stale.
- Use `Luau: Validate` for the standard source check before finishing Luau code changes.

## Game Concept Refinement Loop

- Treat the user's game prompt as the current product brief, then refine it in a loop: understand the core fantasy, identify the smallest playable slice, implement it, validate it, and repeat.
- Keep aiming for a premium-feeling result: readable UI, strong motion, clear input feedback, polished projectiles, and responsive camera and animation timing.
- When inspiration from similar games is useful, use it only at a high level for mechanics, pacing, readability, UI hierarchy, or feel. Do not copy proprietary assets, code, level layouts, or distinctive expression.
- Use workspace search, `mcp_robloxstudio-_search_files`, and `get_changed_files` to find the owning implementation before editing; use external web search only for public facts or broad pattern research that the repo cannot answer.
- Prefer iterative, local improvements over broad rewrites. After each meaningful change, validate it in the narrowest available way, then continue the loop until the user is satisfied or no local improvement remains.

## Validation Workflow

- After the first substantive edit, run the narrowest useful validation before making more changes.
- For Luau code changes, prefer `Luau: Format check` and `Luau: Lint`.
- If dependencies change, run `Roblox: Install packages`.
- If toolchain versions change, run `Roblox: Install toolchain`.
- If project mapping changes, run `Roblox: Generate sourcemap` or rely on Luau LSP autogeneration and verify the output.
- Before finishing code changes, prefer repo-scope formatting and lint validation on `src`.

## Tool Selection

- Use workspace search, nearby file reads, symbol usage lookup, and local validation before using external tools.
- Use `runSubagent` for read-only exploration when the task spans multiple files or when a quick architecture pass is cheaper than manual searching.
- Use `fetch_webpage` only for external facts the repo cannot answer, such as current Roblox API behavior or current extension/tool documentation.
- Prefer official sources for Roblox APIs, Luau LSP behavior, and VS Code customization behavior.
- Do not broad-explore the repo once there is enough context to make and validate a local change.

## Change Discipline

- Fix the root cause when it is local and clear.
- Keep changes minimal, consistent with existing code, and scoped to the requested behavior.
- Do not hand-edit generated files unless the task is specifically about the generator output.
- Do not add new abstractions, remotes, or shared modules until the current local path is insufficient.
