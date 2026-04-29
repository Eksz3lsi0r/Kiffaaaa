--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaBuilder = require(script.Parent.ArenaBuilder)
local MatchService = require(script.Parent.MatchService)
local ProgressionService = require(script.Parent.ProgressionService)

local Shared = require(ReplicatedStorage.Shared)

local progression = ProgressionService.new()
progression:bootstrapExistingPlayers()

local matchService = MatchService.new(progression)
matchService:start()

print(("[server] booted %s"):format(Shared.GameName))

task.defer(function()
    local ok, arena = pcall(ArenaBuilder.build)
    if ok then
        matchService:setArena(arena)
        print(("[server] arena ready at %s"):format(tostring(arena.Center)))
    else
        warn(("[server] arena build failed: %s"):format(tostring(arena)))
    end
end)
