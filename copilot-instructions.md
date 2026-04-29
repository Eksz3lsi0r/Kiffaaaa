# rblcxx Copilot Instructions

## Goal

Keep this project source-first. Treat the Rojo mapping and the Luau modules under `src/` as the canonical game code. Do not recreate data or systems that already exist in the workspace.

## Read Before Editing

Before changing gameplay code, inspect these files first:

- `default.project.json`
- `src/ReplicatedStorage/Shared/init.luau`
- `src/ReplicatedStorage/Shared/MatchConfig.luau`
- `src/ReplicatedStorage/Shared/Elements.luau`
- `src/ReplicatedStorage/Shared/Loadouts.luau`
- `src/ServerScriptService/main.server.luau`
- `src/StarterPlayer/StarterPlayerScripts/main.client.luau`

## Project Boundaries

- `src/ReplicatedStorage/Shared` is for pure shared data, exported types, and constants.
- `src/ServerScriptService` is for authoritative game logic, remotes, and server state.
- `src/StarterPlayer/StarterPlayerScripts` is for client UI, input, and presentation.
- `MatchConfig` is the source of truth for shared constants such as remotes, timings, arena dimensions, and keybinds.

## What To Avoid

- Do not hardcode remote names, shared timings, or arena constants outside `MatchConfig`.
- Do not duplicate element, loadout, or reward definitions in new files when the shared modules already own them.
- Do not move server logic into the client just to make it easier to call.
- Do not edit generated artifacts such as `sourcemap.json` or dependency output in `Packages/`.
- Do not create a second copy of a service or UI flow when the existing module already owns that behavior.

## How To Extend The Game

1. Add or update shared data first.
2. Export the types that both client and server will need.
3. Wire the server service or client UI to the shared definitions.
4. Reuse the existing tasks in `.vscode/tasks.json` to validate the change.

If you need a new gameplay concept, look for an existing concept to extend before inventing a parallel system.

## Working Rules

- Keep Luau files `--!strict`.
- Prefer small, typed modules with one clear responsibility.
- Use the existing bootstrap points instead of adding new top-level scripts.
- When a constant is used on both sides of the network, define it once and share it.
- Prefer precise changes over broad refactors unless the current structure is actually wrong.

## Validation

- Use `Luau: Lint` and `Luau: Format check` before finishing.
- If a change affects project mapping, verify `default.project.json` still matches the `src/` tree.
- If a change adds a remote or shared constant, update the shared module first and then both caller sides.
