--!strict

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage.Shared)
local MatchConfig = Shared.MatchConfig
local Elements = Shared.Elements

local ArenaBuilder = {}

local function createPart(
    parent: Instance,
    name: string,
    size: Vector3,
    cframe: CFrame,
    color: Color3,
    material: Enum.Material,
    transparency: number?,
    anchored: boolean?
): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.CFrame = cframe
    part.Color = color
    part.Material = material
    part.Transparency = transparency or 0
    part.Anchored = if anchored == nil then true else anchored
    part.CanCollide = true
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = parent
    return part
end

local function createSpawn(
    parent: Instance,
    name: string,
    cframe: CFrame,
    color: Color3
): SpawnLocation
    local spawn = Instance.new("SpawnLocation")
    spawn.Name = name
    spawn.Size = Vector3.new(12, 1, 12)
    spawn.CFrame = cframe
    spawn.Transparency = 0.35
    spawn.Anchored = true
    spawn.CanCollide = true
    spawn.Color = color
    spawn.Material = Enum.Material.Neon
    spawn.Neutral = true
    spawn.AllowTeamChangeOnTouch = false
    spawn.Enabled = false
    spawn.Parent = parent
    return spawn
end

function ArenaBuilder.build()
    local existing = Workspace:FindFirstChild(MatchConfig.ArenaFolderName)
    if existing then
        existing:Destroy()
    end

    local folder = Instance.new("Folder")
    folder.Name = MatchConfig.ArenaFolderName
    folder.Parent = Workspace

    local center = MatchConfig.ArenaCenter
    local floorSize = MatchConfig.ArenaFloorSize
    local wallThickness = MatchConfig.ArenaWallThickness
    local wallHeight = MatchConfig.ArenaWallHeight

    createPart(
        folder,
        "ArenaFloor",
        floorSize,
        CFrame.new(center),
        Color3.fromRGB(62, 71, 80),
        Enum.Material.Slate
    )

    createPart(
        folder,
        "ArenaInnerRing",
        Vector3.new(140, 4, 140),
        CFrame.new(center + Vector3.new(0, 4, 0)),
        Color3.fromRGB(99, 88, 72),
        Enum.Material.Rock
    )

    createPart(
        folder,
        "NorthWall",
        Vector3.new(floorSize.X, wallHeight, wallThickness),
        CFrame.new(center + Vector3.new(0, wallHeight / 2, -(floorSize.Z / 2 + wallThickness / 2))),
        Color3.fromRGB(43, 47, 51),
        Enum.Material.Basalt
    )
    createPart(
        folder,
        "SouthWall",
        Vector3.new(floorSize.X, wallHeight, wallThickness),
        CFrame.new(center + Vector3.new(0, wallHeight / 2, floorSize.Z / 2 + wallThickness / 2)),
        Color3.fromRGB(43, 47, 51),
        Enum.Material.Basalt
    )
    createPart(
        folder,
        "WestWall",
        Vector3.new(wallThickness, wallHeight, floorSize.Z),
        CFrame.new(center + Vector3.new(-(floorSize.X / 2 + wallThickness / 2), wallHeight / 2, 0)),
        Color3.fromRGB(43, 47, 51),
        Enum.Material.Basalt
    )
    createPart(
        folder,
        "EastWall",
        Vector3.new(wallThickness, wallHeight, floorSize.Z),
        CFrame.new(center + Vector3.new(floorSize.X / 2 + wallThickness / 2, wallHeight / 2, 0)),
        Color3.fromRGB(43, 47, 51),
        Enum.Material.Basalt
    )

    for index, elementName in ipairs(Elements.ElementOrder) do
        local definition = Elements.Elements[elementName]
        local angle = math.rad((index - 1) * 90)
        local radius = 150
        local position = center + Vector3.new(math.cos(angle) * radius, 6, math.sin(angle) * radius)
        createPart(
            folder,
            elementName .. "Shrine",
            Vector3.new(24, 12, 24),
            CFrame.new(position),
            definition.ThemeColor,
            Enum.Material.Neon,
            0.15
        )
        createPart(
            folder,
            elementName .. "Pillar",
            Vector3.new(10, 34, 10),
            CFrame.new(position + Vector3.new(0, 22, 0)),
            definition.AccentColor,
            Enum.Material.SmoothPlastic,
            0.1
        )
    end

    for _, offset in ipairs({
        Vector3.new(-90, 12, -90),
        Vector3.new(90, 12, -90),
        Vector3.new(-90, 12, 90),
        Vector3.new(90, 12, 90),
    }) do
        createPart(
            folder,
            ("Column_%d_%d"):format(offset.X, offset.Z),
            Vector3.new(16, 24, 16),
            CFrame.new(center + offset),
            Color3.fromRGB(92, 82, 68),
            Enum.Material.Sandstone
        )
    end

    local spawnHeightOffset = Vector3.new(0, MatchConfig.SpawnHeight, 0)
    local leftPosition = center + Vector3.new(-MatchConfig.SpawnOffset, 0, 0) + spawnHeightOffset
    local rightPosition = center + Vector3.new(MatchConfig.SpawnOffset, 0, 0) + spawnHeightOffset

    local leftSpawn = createSpawn(
        folder,
        "EarthsideSpawn",
        CFrame.lookAt(leftPosition, rightPosition),
        Color3.fromRGB(140, 179, 255)
    )
    local rightSpawn = createSpawn(
        folder,
        "SkyfireSpawn",
        CFrame.lookAt(rightPosition, leftPosition),
        Color3.fromRGB(255, 160, 132)
    )

    local ambience = Instance.new("Atmosphere")
    ambience.Name = "ArenaAtmosphere"
    ambience.Density = 0.22
    ambience.Haze = 1.8
    ambience.Color = Color3.fromRGB(215, 204, 188)
    ambience.Decay = Color3.fromRGB(88, 99, 122)
    ambience.Parent = folder

    return {
        Folder = folder,
        LeftSpawn = leftSpawn,
        RightSpawn = rightSpawn,
        Center = center,
    }
end

return ArenaBuilder
