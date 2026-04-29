--!strict

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local function applyCameraSettings()
    player.CameraMode = Enum.CameraMode.Classic
    player.CameraMinZoomDistance = 8
    player.CameraMaxZoomDistance = 160
    print("[client] camera free-look enabled")
end

applyCameraSettings()

player.CharacterAdded:Connect(function()
    task.defer(applyCameraSettings)
end)
