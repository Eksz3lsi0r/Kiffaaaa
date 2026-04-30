--- Recommended Luau LSP Studio plugin configuration for this workspace.
--- Copy this table into the Studio plugin config module from:
--- https://github.com/JohnnyMorganz/luau-lsp/tree/main/plugin
---
--- Keep these values aligned with `.vscode/settings.json`:
--- - `luau-lsp.studioPlugin.enabled = true`
--- - `luau-lsp.studioPlugin.port = 3667`
---
--- This config is only for Luau LSP editor integration.
--- It does not configure `robloxstudio-mcp`, which uses its own Studio plugin
--- and the local bridge at `http://localhost:58741/mcp`.
--- luacheck: ignore robloxstudio Rojo

local function service(name)
    return game:GetService(name)
end

return {
    --- Match the local VS Code language server host.
    host = "http://localhost",

    --- Match `luau-lsp.studioPlugin.port` in `.vscode/settings.json`.
    --- This is not the Rojo port.
    port = 3667,

    --- Auto-connect on Studio launch to avoid manual reconnects.
    startAutomatically = true,

    --- Track the services this repo actively owns plus Workspace for live place edits.
    --- If `default.project.json` gains new top-level services, add them here too.
    include = {
        service("Workspace"),
        service("ReplicatedStorage"),
        service("ServerScriptService"),
        service("StarterPlayer"),
    },

    --- Use INFO while wiring the workflow up; WARN is fine once stable.
    logLevel = "INFO",
}
