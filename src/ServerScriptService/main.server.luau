local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("ArenaDuelConfig"))

type AbilityConfig = {
    displayName: string,
    cooldown: number,
    castTime: number,
    range: number?,
    radius: number?,
    damage: number?,
    heal: number?,
    shield: number?,
    shieldDuration: number?,
    friendly: boolean?,
    fullHeal: boolean?,
    crowdControl: string?,
    crowdControlDuration: number?,
    effectName: string?,
    slowMultiplier: number?,
    dotDamage: number?,
    dotDuration: number?,
    dotInterval: number?,
    focusGain: number?,
    consumeFocus: boolean?,
    focusDamage: number?,
    executeBonus: number?,
    executeThreshold: number?,
    interrupt: boolean?,
    lockout: number?,
    area: boolean?,
}

type EffectState = {
    kind: string,
    category: string?,
    expiresAt: number,
    amount: number?,
    nextTickAt: number?,
    tickInterval: number?,
    sourceId: string?,
}

type CastState = {
    abilityId: string,
    targetId: string?,
    startedAt: number,
    endsAt: number,
    duration: number,
    token: number,
}

type VectorPayload = {
    x: number,
    y: number,
    z: number,
}

type CombatEvent = {
    id: number,
    kind: string,
    text: string,
    amount: number?,
    sourceId: string?,
    targetId: string?,
    abilityName: string?,
    position: VectorPayload?,
    createdAt: number,
}

type FighterState = {
    id: string,
    name: string,
    team: number,
    player: Player?,
    isBot: boolean,
    classId: string,
    health: number,
    maxHealth: number,
    focus: number,
    cooldowns: { [string]: number },
    effects: { EffectState },
    dr: { [string]: { count: number, expiresAt: number } },
    targetId: string?,
    shield: number,
    shieldExpiresAt: number,
    castLockedUntil: number,
    casting: CastState?,
    castToken: number,
    botModel: Model?,
}

type MatchState = {
    id: number,
    mode: string,
    phase: string,
    countdown: number,
    prepSeconds: number,
    startedAt: number,
    fighters: { FighterState },
    combatEvents: { CombatEvent },
    nextCombatEventId: number,
    gatesOpen: boolean,
    winnerTeam: number?,
}

local remotesFolder = ReplicatedStorage:FindFirstChild(Config.RemoteFolderName)
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = Config.RemoteFolderName
    remotesFolder.Parent = ReplicatedStorage
end

local function getRemote(remoteName: string): RemoteEvent
    local remote = remotesFolder:FindFirstChild(remoteName)
    if not remote or not remote:IsA("RemoteEvent") then
        if remote then
            remote:Destroy()
        end

        remote = Instance.new("RemoteEvent")
        remote.Name = remoteName
        remote.Parent = remotesFolder
    end

    return remote :: RemoteEvent
end

local queueRequestEvent = getRemote(Config.Remotes.QueueRequest)
local classSelectEvent = getRemote(Config.Remotes.ClassSelect)
local targetSelectEvent = getRemote(Config.Remotes.TargetSelect)
local abilityCastEvent = getRemote(Config.Remotes.AbilityCast)
local stateUpdateEvent = getRemote(Config.Remotes.StateUpdate)
local systemMessageEvent = getRemote(Config.Remotes.SystemMessage)

local WORLD_FOLDER_NAME = "ArenaDuelWorld"
local TEAM_ONE = 1
local TEAM_TWO = 2
local selectedClassByPlayer: { [Player]: string } = {}
local playerQueues: { [Player]: string } = {}
local queues: { [string]: { Player } } = {
    Duel1v1 = {},
    Duel2v2 = {},
}
local activeMatch: MatchState? = nil
local nextMatchId = 1
local arenaWorld: Folder
local gateParts: { BasePart } = {}
local gateClosedCFrames: { [BasePart]: CFrame } = {}
local heartbeatConnection: RBXScriptConnection? = nil

local function sendMessage(player: Player, text: string)
    systemMessageEvent:FireClient(player, text)
end

local function makePart(
    parent: Instance,
    name: string,
    position: Vector3,
    size: Vector3,
    color: Color3,
    material: Enum.Material,
    transparency: number?
): Part
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.Size = size
    part.Position = position
    part.Color = color
    part.Material = material
    part.Transparency = transparency or 0
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = parent
    return part
end

local function makeTorch(parent: Instance, name: string, position: Vector3): Part
    local flame = Instance.new("Part")
    flame.Name = name
    flame.Anchored = true
    flame.Size = Vector3.new(0.55, 1.8, 0.55)
    flame.Position = position
    flame.Color = Color3.fromRGB(255, 130, 18)
    flame.Material = Enum.Material.Neon
    flame.Transparency = 0.1
    flame.CastShadow = false
    flame.TopSurface = Enum.SurfaceType.Smooth
    flame.BottomSurface = Enum.SurfaceType.Smooth
    flame.Parent = parent

    local light = Instance.new("PointLight")
    light.Brightness = 3.5
    light.Range = 18
    light.Color = Color3.fromRGB(255, 160, 48)
    light.Shadows = true
    light.Parent = flame

    return flame
end

-- ─────────────────────────────────────────────────────────────────────────────
-- buildArenaWorld  –  WoW "Ruins of Lordaeron"-style enclosed PvP arena
--
-- Layout (top-down, X horizontal, Z vertical, lobby behind south wall):
--
--        [NW tower]  North Wall (crenellated)  [NE tower]
--   Prep1 ══[W gate]════ Arena Floor (100×64) ════[E gate]══ Prep2
--        [SW tower]  South Wall (crenellated)  [SE tower]
--                        |
--                      Lobby (Z=84)
--
-- All floor surfaces sit at Y=0.5 (part center Y=0).
-- Spawn markers sit at Y=1 (part center). teleportPlayer adds Y=4 → root Y=5,
-- feet ~Y=2 → falls ≤2 studs onto floor. No void gaps anywhere.
-- ─────────────────────────────────────────────────────────────────────────────
local function buildArenaWorld()
    local existingWorld = workspace:FindFirstChild(WORLD_FOLDER_NAME)
    if existingWorld then
        existingWorld:Destroy()
    end

    local world = Instance.new("Folder")
    world.Name = WORLD_FOLDER_NAME
    world.Parent = workspace
    arenaWorld = world
    table.clear(gateParts)

    -- Colour palette (Ruins of Lordaeron grey-brown stone)
    local stone = Color3.fromRGB(105, 100, 94) -- weathered limestone walls
    local darkStone = Color3.fromRGB(55, 52, 47) -- towers & shadow faces
    local merlon = Color3.fromRGB(78, 74, 69) -- battlement blocks
    local cobble = Color3.fromRGB(118, 112, 104) -- arena floor cobblestone
    local pillarColor = Color3.fromRGB(112, 107, 100) -- LoS column stone
    local prepGround = Color3.fromRGB(82, 72, 58) -- prep room dirt/earth
    local lobbyGray = Color3.fromRGB(66, 74, 88) -- lobby concrete
    local blue = Color3.fromRGB(54, 105, 170)
    local red = Color3.fromRGB(170, 61, 54)
    local lobbyGreen = Color3.fromRGB(101, 179, 104)

    -- ── ARENA FLOOR  (100 × 64, cobblestone) ────────────────────────────────
    -- Top surface at Y = 0.5
    makePart(
        world,
        "ArenaFloor",
        Vector3.new(0, 0, 0),
        Vector3.new(100, 1, 64),
        cobble,
        Enum.Material.Cobblestone
    )

    -- Centre sigil ring (darker inlay so fighters can see the middle)
    makePart(
        world,
        "ArenaCentreInlay",
        Vector3.new(0, 0.01, 0),
        Vector3.new(28, 0.1, 28),
        merlon,
        Enum.Material.SmoothPlastic,
        0.1
    )

    -- ── GATE ARCH FLOORS (under the 4-stud gate walls) ──────────────────────
    -- Seamlessly bridges arena floor (X ±50) to prep floors (X ±54 onwards).
    makePart(
        world,
        "WestGateFloor",
        Vector3.new(-52, 0, 0),
        Vector3.new(4, 1, 12),
        cobble,
        Enum.Material.Cobblestone
    )
    makePart(
        world,
        "EastGateFloor",
        Vector3.new(52, 0, 0),
        Vector3.new(4, 1, 12),
        cobble,
        Enum.Material.Cobblestone
    )

    -- ── PREP ROOM FLOORS  (Team 1 west / Team 2 east) ───────────────────────
    -- Each spans X ±54 → ±110 (56 wide), Z ±20 (40 deep). Meets gate floor.
    makePart(
        world,
        "TeamOnePrepFloor",
        Vector3.new(-82, 0, 0),
        Vector3.new(56, 1, 40),
        prepGround,
        Enum.Material.Ground
    )
    makePart(
        world,
        "TeamTwoPrepFloor",
        Vector3.new(82, 0, 0),
        Vector3.new(56, 1, 40),
        prepGround,
        Enum.Material.Ground
    )

    -- ── LOBBY FLOOR ──────────────────────────────────────────────────────────
    -- Sits behind the south wall (Z+), separated but clearly a waiting area.
    makePart(
        world,
        "LobbyFloor",
        Vector3.new(0, 0, 84),
        Vector3.new(72, 1, 30),
        lobbyGray,
        Enum.Material.Concrete
    )

    -- ── NORTH WALL  (full, no gate, crenellated top) ─────────────────────────
    -- 108 wide covers arena + tower overhangs. Centre at Z=−34, height 14.
    makePart(
        world,
        "NorthWall",
        Vector3.new(0, 7, -34),
        Vector3.new(108, 14, 4),
        stone,
        Enum.Material.Brick
    )

    -- ── SOUTH WALL ───────────────────────────────────────────────────────────
    makePart(
        world,
        "SouthWall",
        Vector3.new(0, 7, 34),
        Vector3.new(108, 14, 4),
        stone,
        Enum.Material.Brick
    )

    -- ── WEST WALL  (gate opening: 12 Z-wide, 10 Y-tall at centre) ───────────
    -- North half: Z −32 → −6 (26 studs), centre Z=−19
    makePart(
        world,
        "WestWallNorth",
        Vector3.new(-52, 7, -19),
        Vector3.new(4, 14, 26),
        stone,
        Enum.Material.Brick
    )
    -- South half: Z +6 → +32 (26 studs), centre Z=+19
    makePart(
        world,
        "WestWallSouth",
        Vector3.new(-52, 7, 19),
        Vector3.new(4, 14, 26),
        stone,
        Enum.Material.Brick
    )
    -- Lintel above gate opening (Y 10→14, 12 Z-wide)
    makePart(
        world,
        "WestGateLintel",
        Vector3.new(-52, 12, 0),
        Vector3.new(4, 4, 12),
        stone,
        Enum.Material.Brick
    )

    -- ── EAST WALL ────────────────────────────────────────────────────────────
    makePart(
        world,
        "EastWallNorth",
        Vector3.new(52, 7, -19),
        Vector3.new(4, 14, 26),
        stone,
        Enum.Material.Brick
    )
    makePart(
        world,
        "EastWallSouth",
        Vector3.new(52, 7, 19),
        Vector3.new(4, 14, 26),
        stone,
        Enum.Material.Brick
    )
    makePart(
        world,
        "EastGateLintel",
        Vector3.new(52, 12, 0),
        Vector3.new(4, 4, 12),
        stone,
        Enum.Material.Brick
    )

    -- ── CORNER TOWERS  (8×16×8, slightly taller than walls) ─────────────────
    makePart(
        world,
        "TowerNW",
        Vector3.new(-52, 8, -34),
        Vector3.new(8, 16, 8),
        darkStone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "TowerNE",
        Vector3.new(52, 8, -34),
        Vector3.new(8, 16, 8),
        darkStone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "TowerSW",
        Vector3.new(-52, 8, 34),
        Vector3.new(8, 16, 8),
        darkStone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "TowerSE",
        Vector3.new(52, 8, 34),
        Vector3.new(8, 16, 8),
        darkStone,
        Enum.Material.Slate
    )

    -- ── BATTLEMENTS (merlons) on North & South walls ─────────────────────────
    -- 4×4×4 blocks spaced 8 studs, from X=−44 to X=44 (clear of corner towers)
    for ix = -44, 44, 8 do
        makePart(
            world,
            "MerlonN_" .. ix,
            Vector3.new(ix, 16, -34),
            Vector3.new(4, 4, 4),
            merlon,
            Enum.Material.Slate
        )
        makePart(
            world,
            "MerlonS_" .. ix,
            Vector3.new(ix, 16, 34),
            Vector3.new(4, 4, 4),
            merlon,
            Enum.Material.Slate
        )
    end
    -- Merlons on West & East wall sections (north + south halves)
    for iz = -26, -12, 7 do
        makePart(
            world,
            "MerlonWN_" .. iz,
            Vector3.new(-52, 16, iz),
            Vector3.new(4, 4, 4),
            merlon,
            Enum.Material.Slate
        )
        makePart(
            world,
            "MerlonEN_" .. iz,
            Vector3.new(52, 16, iz),
            Vector3.new(4, 4, 4),
            merlon,
            Enum.Material.Slate
        )
    end
    for iz = 12, 26, 7 do
        makePart(
            world,
            "MerlonWS_" .. iz,
            Vector3.new(-52, 16, iz),
            Vector3.new(4, 4, 4),
            merlon,
            Enum.Material.Slate
        )
        makePart(
            world,
            "MerlonES_" .. iz,
            Vector3.new(52, 16, iz),
            Vector3.new(4, 4, 4),
            merlon,
            Enum.Material.Slate
        )
    end
    -- Tower cap battlements (flat slab on each tower top)
    for _, tx in { -52, 52 } do
        for _, tz in { -34, 34 } do
            makePart(
                world,
                "TowerCap_" .. tx .. "_" .. tz,
                Vector3.new(tx, 17, tz),
                Vector3.new(9, 2, 9),
                darkStone,
                Enum.Material.Slate
            )
        end
    end

    -- ── LINE-OF-SIGHT PILLARS (4 stone columns inside arena) ─────────────────
    -- Classic WoW layout: two pairs symmetrically placed at ±22 / ±18
    for _, px in { -22, 22 } do
        for _, pz in { -18, 18 } do
            -- Column body (4×12×4)
            makePart(
                world,
                "Pillar_" .. px .. "_" .. pz,
                Vector3.new(px, 6, pz),
                Vector3.new(4, 12, 4),
                pillarColor,
                Enum.Material.SmoothPlastic
            )
            -- Column capital (wider slab on top)
            makePart(
                world,
                "PillarCap_" .. px .. "_" .. pz,
                Vector3.new(px, 12.8, pz),
                Vector3.new(6, 1.6, 6),
                pillarColor,
                Enum.Material.SmoothPlastic
            )
            -- Column base (wider slab at bottom)
            makePart(
                world,
                "PillarBase_" .. px .. "_" .. pz,
                Vector3.new(px, 0.8, pz),
                Vector3.new(6, 1.6, 6),
                pillarColor,
                Enum.Material.SmoothPlastic
            )
        end
    end

    -- ── PREP ROOM WALLS ───────────────────────────────────────────────────────
    -- Team 1 (west) enclosure: back wall X=−111, north/south walls
    makePart(
        world,
        "TeamOnePrepBackWall",
        Vector3.new(-111, 7, 0),
        Vector3.new(4, 14, 40),
        darkStone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "TeamOnePrepNorthWall",
        Vector3.new(-82, 7, -21),
        Vector3.new(56, 14, 4),
        darkStone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "TeamOnePrepSouthWall",
        Vector3.new(-82, 7, 21),
        Vector3.new(56, 14, 4),
        darkStone,
        Enum.Material.Slate
    )
    -- Team 2 (east) enclosure
    makePart(
        world,
        "TeamTwoPrepBackWall",
        Vector3.new(111, 7, 0),
        Vector3.new(4, 14, 40),
        darkStone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "TeamTwoPrepNorthWall",
        Vector3.new(82, 7, -21),
        Vector3.new(56, 14, 4),
        darkStone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "TeamTwoPrepSouthWall",
        Vector3.new(82, 7, 21),
        Vector3.new(56, 14, 4),
        darkStone,
        Enum.Material.Slate
    )

    -- Team-colour accent strip on prep room floors (thin coloured slab)
    makePart(
        world,
        "Prep1ColourStrip",
        Vector3.new(-82, 0.6, 0),
        Vector3.new(54, 0.2, 38),
        blue,
        Enum.Material.SmoothPlastic,
        0.6
    )
    makePart(
        world,
        "Prep2ColourStrip",
        Vector3.new(82, 0.6, 0),
        Vector3.new(54, 0.2, 38),
        red,
        Enum.Material.SmoothPlastic,
        0.6
    )

    -- ── PORTCULLIS GATES  (iron bars that slide upward when fight starts) ─────
    -- Each gate: top crossbeam + bottom sill (static frame) + 6 vertical bars
    -- + horizontal mid-rail. All parts are stored in gateParts and slide up on open.
    local gateBarColor = Color3.fromRGB(58, 54, 46)
    local gateFrameColor = Color3.fromRGB(36, 32, 24)
    local gateAccentColor = Color3.fromRGB(170, 142, 40)

    local function buildPortcullis(centreX: number, prefix: string)
        local parts: { BasePart } = {}

        local function addPart(
            name: string,
            pos: Vector3,
            size: Vector3,
            color: Color3,
            mat: Enum.Material
        )
            local p = makePart(world, prefix .. name, pos, size, color, mat, 0.06)
            table.insert(parts, p)
            gateClosedCFrames[p] = p.CFrame
        end

        -- Top crossbeam
        addPart(
            "Beam",
            Vector3.new(centreX, 10.7, 0),
            Vector3.new(3.6, 1.4, 14.5),
            gateFrameColor,
            Enum.Material.Metal
        )
        -- Bottom sill
        addPart(
            "Sill",
            Vector3.new(centreX, 1.0, 0),
            Vector3.new(3.6, 1.0, 14.5),
            gateFrameColor,
            Enum.Material.Metal
        )
        -- Horizontal mid-rail (decorative accent)
        addPart(
            "Rail",
            Vector3.new(centreX, 7.5, 0),
            Vector3.new(3.6, 0.5, 12.5),
            gateAccentColor,
            Enum.Material.Metal
        )
        -- 6 vertical bars spaced across Z = -5 … +5
        for i = 0, 5 do
            local bz = -5 + i * 2
            addPart(
                "Bar" .. tostring(i),
                Vector3.new(centreX, 5.5, bz),
                Vector3.new(3.6, 9.5, 0.65),
                gateBarColor,
                Enum.Material.Metal
            )
        end

        return parts
    end

    table.clear(gateParts)
    for _, p in buildPortcullis(-52, "WestGate") do
        table.insert(gateParts, p)
    end
    for _, p in buildPortcullis(52, "EastGate") do
        table.insert(gateParts, p)
    end

    -- ── SPAWN MARKERS (thin neon pads; teleportPlayer adds Y=4 above centre) ──
    makePart(
        world,
        "LobbySpawn",
        Vector3.new(0, 1, 84),
        Vector3.new(6, 1, 6),
        lobbyGreen,
        Enum.Material.Neon,
        0.25
    )
    makePart(
        world,
        "TeamOnePrepSpawn",
        Vector3.new(-90, 1, 0),
        Vector3.new(6, 1, 6),
        blue,
        Enum.Material.Neon,
        0.2
    )
    makePart(
        world,
        "TeamTwoPrepSpawn",
        Vector3.new(90, 1, 0),
        Vector3.new(6, 1, 6),
        red,
        Enum.Material.Neon,
        0.2
    )
    makePart(
        world,
        "TeamOneArenaEntry",
        Vector3.new(-42, 1, 0),
        Vector3.new(5, 1, 5),
        blue,
        Enum.Material.Neon,
        0.35
    )
    makePart(
        world,
        "TeamTwoArenaEntry",
        Vector3.new(42, 1, 0),
        Vector3.new(5, 1, 5),
        red,
        Enum.Material.Neon,
        0.35
    )

    -- ── TORCHES  (neon flame + PointLight at key positions) ──────────────────
    -- 4 × atop arena wall corners (on the merlon level)
    for _, tx in { -44, 44 } do
        for _, tz in { -34, 34 } do
            makeTorch(world, "TorchCorner_" .. tx .. "_" .. tz, Vector3.new(tx, 18, tz))
        end
    end
    -- 4 × flanking each gate archway (inner face of west/east wall)
    for _, gx in { -52, 52 } do
        makeTorch(
            world,
            "TorchGate_" .. gx .. "N",
            Vector3.new(gx + (if gx < 0 then 3 else -3), 8, -7)
        )
        makeTorch(
            world,
            "TorchGate_" .. gx .. "S",
            Vector3.new(gx + (if gx < 0 then 3 else -3), 8, 7)
        )
    end
    -- 4 × prep room back walls
    for _, px in { -108, 108 } do
        makeTorch(
            world,
            "TorchPrep_" .. px .. "N",
            Vector3.new(px + (if px < 0 then 3 else -3), 9, -8)
        )
        makeTorch(
            world,
            "TorchPrep_" .. px .. "S",
            Vector3.new(px + (if px < 0 then 3 else -3), 9, 8)
        )
    end
    -- 2 × flanking the centre dais pillars
    makeTorch(world, "TorchDaisNW", Vector3.new(-14, 2.5, -14))
    makeTorch(world, "TorchDaisNE", Vector3.new(14, 2.5, -14))
    makeTorch(world, "TorchDaisSW", Vector3.new(-14, 2.5, 14))
    makeTorch(world, "TorchDaisSE", Vector3.new(14, 2.5, 14))

    -- ── CENTRE DAIS  (low raised platform at the arena heart) ────────────────
    makePart(
        world,
        "CentreDais",
        Vector3.new(0, 0.8, 0),
        Vector3.new(24, 0.6, 24),
        merlon,
        Enum.Material.SmoothPlastic
    )
    makePart(
        world,
        "CentreDaisInner",
        Vector3.new(0, 1.05, 0),
        Vector3.new(12, 0.1, 12),
        darkStone,
        Enum.Material.SmoothPlastic,
        0.15
    )

    -- ── PREP ROOM STONE BENCHES ───────────────────────────────────────────────
    for _, bx in { -101, 101 } do
        for _, bz in { -8, 8 } do
            makePart(
                world,
                "Bench_" .. bx .. "_" .. bz,
                Vector3.new(bx, 1.5, bz),
                Vector3.new(12, 1, 2.5),
                darkStone,
                Enum.Material.SmoothPlastic
            )
        end
    end

    -- ── ATMOSPHERIC LIGHTING ─────────────────────────────────────────────────
    Lighting.Ambient = Color3.fromRGB(65, 58, 88)
    Lighting.Brightness = 2.0
    Lighting.ClockTime = 20.2
    Lighting.GeographicLatitude = 42
    Lighting.FogStart = 220
    Lighting.FogEnd = 520
    Lighting.FogColor = Color3.fromRGB(26, 22, 40)
end

local function setGatesOpen(open: boolean)
    for _, gate in gateParts do
        gate.CanCollide = not open
        gate.CanTouch = open
        gate.CanQuery = true
        local closedCF = gateClosedCFrames[gate]
        if not closedCF then
            gate.Transparency = if open then 0.85 else 0.06
            continue
        end
        if open then
            -- Slide the portcullis bars straight up, out of sight above the lintel
            TweenService:Create(
                gate,
                TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { CFrame = closedCF + Vector3.new(0, 14, 0), Transparency = 0.78 }
            ):Play()
        else
            -- Snap back to closed position instantly (cleanup / re-init)
            gate.CFrame = closedCF
            gate.Transparency = 0.06
        end
    end
end

local function getWorldPart(name: string): BasePart?
    local part = arenaWorld:FindFirstChild(name)
    if part and part:IsA("BasePart") then
        return part
    end

    return nil
end

local function getClassConfig(classId: string)
    return Config.Classes[classId] or Config.Classes.Warrior
end

local function getAbilityConfig(classId: string, abilityId: string): AbilityConfig?
    local classConfig = getClassConfig(classId)
    return classConfig.abilities[abilityId]
end

local function getRootPart(player: Player): BasePart?
    local character = player.Character
    if not character then
        return nil
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then
        return root
    end

    return nil
end

local function getHumanoid(player: Player): Humanoid?
    local character = player.Character
    if not character then
        return nil
    end

    return character:FindFirstChildOfClass("Humanoid")
end

local function teleportPlayer(player: Player, partName: string, offsetIndex: number)
    local root = getRootPart(player)
    local destination = getWorldPart(partName)
    if not root or not destination then
        return
    end

    local offset = Vector3.new((offsetIndex - 1) * 5, 4, 0)
    root.CFrame = CFrame.new(destination.Position + offset)
end

local function placeBot(fighter: FighterState, partName: string, offsetIndex: number)
    local destination = getWorldPart(partName)
    if not destination or not fighter.botModel or not fighter.botModel.PrimaryPart then
        return
    end

    local offset = Vector3.new((offsetIndex - 1) * 5, 4.5, 0)
    fighter.botModel.PrimaryPart.CFrame = CFrame.new(destination.Position + offset)
end

local function placeFighterAtMarker(fighter: FighterState, partName: string, offsetIndex: number)
    if fighter.player then
        teleportPlayer(fighter.player, partName, offsetIndex)
    elseif fighter.isBot then
        placeBot(fighter, partName, offsetIndex)
    end
end

local function resetPlayerCharacter(player: Player)
    local classId = selectedClassByPlayer[player] or "Warrior"
    local classConfig = getClassConfig(classId)
    local humanoid = getHumanoid(player)
    if humanoid then
        humanoid.MaxHealth = classConfig.maxHealth
        humanoid.Health = classConfig.maxHealth
        humanoid.WalkSpeed = classConfig.baseWalkSpeed
        humanoid.JumpPower = 50
        humanoid.PlatformStand = false
    end
end

local function makeFighter(
    player: Player?,
    team: number,
    classId: string,
    isBot: boolean
): FighterState
    local classConfig = getClassConfig(classId)
    local fighterId = if player then tostring(player.UserId) else "bot_" .. tostring(nextMatchId)
    local name = if player then player.DisplayName else "COM Gegner"

    return {
        id = fighterId,
        name = name,
        team = team,
        player = player,
        isBot = isBot,
        classId = classId,
        health = classConfig.maxHealth,
        maxHealth = classConfig.maxHealth,
        focus = 0,
        cooldowns = {},
        effects = {},
        dr = {},
        targetId = nil,
        shield = 0,
        shieldExpiresAt = 0,
        castLockedUntil = 0,
        casting = nil,
        castToken = 0,
        botModel = nil,
    }
end

local function createBotModel(fighter: FighterState)
    local model = Instance.new("Model")
    model.Name = fighter.name

    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.Anchored = true
    root.Size = Vector3.new(3, 5, 3)
    root.Position = Vector3.new(90, 5.5, 0)
    root.Color = Color3.fromRGB(136, 54, 170)
    root.Material = Enum.Material.Neon
    root.Parent = model

    local labelAttachment = Instance.new("Attachment")
    labelAttachment.Position = Vector3.new(0, 3.2, 0)
    labelAttachment.Parent = root

    local billboard = Instance.new("BillboardGui")
    billboard.Size = UDim2.fromOffset(160, 36)
    billboard.AlwaysOnTop = true
    billboard.Parent = labelAttachment

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.2
    label.Text = "COM Gegner"
    label.Parent = billboard

    model.PrimaryPart = root
    model.Parent = arenaWorld
    fighter.botModel = model
end

local function getFighterPosition(fighter: FighterState): Vector3?
    if fighter.player then
        local root = getRootPart(fighter.player)
        if root then
            return root.Position
        end
    elseif fighter.botModel and fighter.botModel.PrimaryPart then
        return fighter.botModel.PrimaryPart.Position
    end

    return nil
end

local function getFighterMovementState(fighter: FighterState): (number, boolean)
    local classConfig = getClassConfig(fighter.classId)
    local walkSpeed = classConfig.baseWalkSpeed
    local rooted = false
    local stunned = false
    local now = os.clock()

    for _, effect in fighter.effects do
        if effect.expiresAt > now then
            if effect.kind == "Root" then
                rooted = true
            elseif effect.kind == "Stun" or effect.kind == "Blind" then
                stunned = true
            elseif effect.kind == "Fear" then
                walkSpeed = math.max(walkSpeed, classConfig.baseWalkSpeed + 4)
            elseif effect.kind == "Slow" and effect.amount then
                walkSpeed = math.min(walkSpeed, classConfig.baseWalkSpeed * effect.amount)
            end
        end
    end

    return if rooted or stunned then 0 else walkSpeed, rooted or stunned
end

local function moveBotTo(fighter: FighterState, position: Vector3)
    if fighter.botModel and fighter.botModel.PrimaryPart then
        local root = fighter.botModel.PrimaryPart
        local desiredPosition = Vector3.new(position.X, root.Position.Y, position.Z)
        local delta = desiredPosition - root.Position
        local classConfig = getClassConfig(fighter.classId)
        local walkSpeed = classConfig.baseWalkSpeed
        local now = os.clock()

        for _, effect in fighter.effects do
            if effect.expiresAt > now then
                if effect.kind == "Root" or effect.kind == "Stun" or effect.kind == "Blind" then
                    walkSpeed = 0
                    break
                elseif effect.kind == "Fear" then
                    walkSpeed = math.max(walkSpeed, classConfig.baseWalkSpeed + 4)
                elseif effect.kind == "Slow" and effect.amount then
                    walkSpeed = math.min(walkSpeed, classConfig.baseWalkSpeed * effect.amount)
                end
            end
        end

        local maxStep = walkSpeed * Config.BotAi.tickSeconds

        if maxStep <= 0 then
            return
        end

        if delta.Magnitude > maxStep and delta.Magnitude > 0 then
            desiredPosition = root.Position + delta.Unit * maxStep
        end

        root.CFrame = CFrame.new(desiredPosition)
    end
end

local function vectorToPayload(position: Vector3?): VectorPayload?
    if not position then
        return nil
    end

    return {
        x = math.floor(position.X * 10) / 10,
        y = math.floor(position.Y * 10) / 10,
        z = math.floor(position.Z * 10) / 10,
    }
end

local function findFighter(matchState: MatchState, fighterId: string?): FighterState?
    if not fighterId then
        return nil
    end

    for _, fighter in matchState.fighters do
        if fighter.id == fighterId then
            return fighter
        end
    end

    return nil
end

local function getFighterForPlayer(player: Player): FighterState?
    local matchState = activeMatch
    if not matchState then
        return nil
    end

    for _, fighter in matchState.fighters do
        if fighter.player == player then
            return fighter
        end
    end

    return nil
end

local function isAlive(fighter: FighterState): boolean
    return fighter.health > 0
end

local function getFirstEnemy(matchState: MatchState, fighter: FighterState): FighterState?
    for _, candidate in matchState.fighters do
        if candidate.team ~= fighter.team and isAlive(candidate) then
            return candidate
        end
    end

    return nil
end

local function getFirstAlly(matchState: MatchState, fighter: FighterState): FighterState?
    for _, candidate in matchState.fighters do
        if
            candidate.team == fighter.team
            and isAlive(candidate)
            and candidate.health < candidate.maxHealth
        then
            return candidate
        end
    end

    return fighter
end

local function isInRange(source: FighterState, target: FighterState, range: number): boolean
    local sourcePosition = getFighterPosition(source)
    local targetPosition = getFighterPosition(target)
    if not sourcePosition or not targetPosition then
        return false
    end

    return (sourcePosition - targetPosition).Magnitude <= range
end

local function hasActionBlockingEffect(fighter: FighterState): boolean
    local now = os.clock()
    for _, effect in fighter.effects do
        if
            effect.expiresAt > now
            and (effect.kind == "Stun" or effect.kind == "Fear" or effect.kind == "Blind")
        then
            return true
        end
    end

    return false
end

local function removeExpiredEffects(fighter: FighterState)
    local now = os.clock()
    local keptEffects = {}
    for _, effect in fighter.effects do
        if effect.expiresAt > now then
            table.insert(keptEffects, effect)
        end
    end
    fighter.effects = keptEffects

    if fighter.shieldExpiresAt <= now then
        fighter.shield = 0
    end
end

local function applyMovementState(fighter: FighterState)
    if not fighter.player then
        return
    end

    local humanoid = getHumanoid(fighter.player)
    if not humanoid then
        return
    end

    local walkSpeed, movementLocked = getFighterMovementState(fighter)

    humanoid.WalkSpeed = walkSpeed
    humanoid.JumpPower = if movementLocked then 0 else 50
end

local function buildEffectList(fighter: FighterState)
    local now = os.clock()
    local effects = {}

    if fighter.shield > 0 and fighter.shieldExpiresAt > now then
        table.insert(effects, {
            name = "Shield",
            remaining = math.max(0, fighter.shieldExpiresAt - now),
            amount = math.floor(fighter.shield),
        })
    end

    for _, effect in fighter.effects do
        if effect.expiresAt > now then
            table.insert(effects, {
                name = effect.kind,
                remaining = math.max(0, effect.expiresAt - now),
            })
        end
    end

    return effects
end

local function buildCooldownList(fighter: FighterState)
    local now = os.clock()
    local cooldowns = {}
    for abilityId, readyAt in fighter.cooldowns do
        cooldowns[abilityId] = math.max(0, readyAt - now)
    end
    return cooldowns
end

local function buildFighterSnapshot(fighter: FighterState)
    local casting = nil
    if fighter.casting then
        local ability = getAbilityConfig(fighter.classId, fighter.casting.abilityId)
        casting = {
            abilityId = fighter.casting.abilityId,
            displayName = if ability then ability.displayName else fighter.casting.abilityId,
            remaining = math.max(0, fighter.casting.endsAt - os.clock()),
            duration = fighter.casting.duration,
        }
    end

    return {
        id = fighter.id,
        name = fighter.name,
        team = fighter.team,
        classId = fighter.classId,
        className = getClassConfig(fighter.classId).displayName,
        health = math.max(0, math.floor(fighter.health)),
        maxHealth = fighter.maxHealth,
        focus = fighter.focus,
        isBot = fighter.isBot,
        targetId = fighter.targetId,
        position = vectorToPayload(getFighterPosition(fighter)),
        effects = buildEffectList(fighter),
        cooldowns = buildCooldownList(fighter),
        casting = casting,
        castLockedRemaining = math.max(0, fighter.castLockedUntil - os.clock()),
    }
end

local function sendLobbyState(player: Player)
    stateUpdateEvent:FireClient(player, {
        kind = "Lobby",
        selectedClass = selectedClassByPlayer[player] or "Warrior",
        queuedMode = playerQueues[player],
        activeMatch = activeMatch ~= nil,
        queueSizes = {
            Duel1v1 = #queues.Duel1v1,
            Duel2v2 = #queues.Duel2v2,
        },
    })
end

local function broadcastMatchState(matchState: MatchState)
    local fighters = {}
    for _, fighter in matchState.fighters do
        table.insert(fighters, buildFighterSnapshot(fighter))
    end

    for _, fighter in matchState.fighters do
        if fighter.player then
            stateUpdateEvent:FireClient(fighter.player, {
                kind = "Match",
                matchId = matchState.id,
                mode = matchState.mode,
                phase = matchState.phase,
                countdown = matchState.countdown,
                gatesOpen = matchState.gatesOpen,
                winnerTeam = matchState.winnerTeam,
                localFighterId = fighter.id,
                fighters = fighters,
                combatEvents = matchState.combatEvents,
            })
        end
    end
end

local function broadcastMatchMessage(matchState: MatchState, text: string)
    for _, fighter in matchState.fighters do
        if fighter.player then
            sendMessage(fighter.player, text)
        end
    end
end

local function pushCombatEvent(
    matchState: MatchState,
    kind: string,
    text: string,
    target: FighterState?,
    source: FighterState?,
    amount: number?,
    abilityName: string?
)
    local now = os.clock()
    local keptEvents = {}
    for _, event in matchState.combatEvents do
        if now - event.createdAt <= 3.5 then
            table.insert(keptEvents, event)
        end
    end
    matchState.combatEvents = keptEvents

    local position = if target then getFighterPosition(target) else nil
    matchState.nextCombatEventId += 1
    table.insert(matchState.combatEvents, {
        id = matchState.nextCombatEventId,
        kind = kind,
        text = text,
        amount = amount,
        sourceId = if source then source.id else nil,
        targetId = if target then target.id else nil,
        abilityName = abilityName,
        position = vectorToPayload(position),
        createdAt = now,
    })
end

local function damageFighter(
    matchState: MatchState,
    source: FighterState,
    target: FighterState,
    amount: number,
    reason: string
)
    if amount <= 0 or not isAlive(target) then
        return
    end

    local remainingDamage = amount
    local absorbedDamage = 0
    if target.shield > 0 and target.shieldExpiresAt > os.clock() then
        local absorbed = math.min(target.shield, remainingDamage)
        target.shield -= absorbed
        remainingDamage -= absorbed
        absorbedDamage = absorbed
    end

    if remainingDamage > 0 then
        target.health = math.max(0, target.health - remainingDamage)
        if target.player then
            local humanoid = getHumanoid(target.player)
            if humanoid then
                humanoid.Health = math.max(1, target.health)
            end
        end

        pushCombatEvent(
            matchState,
            "Damage",
            string.format("-%d", math.floor(remainingDamage)),
            target,
            source,
            remainingDamage,
            reason
        )
    end

    if absorbedDamage > 0 then
        pushCombatEvent(
            matchState,
            "Absorb",
            string.format("%d absorbiert", math.floor(absorbedDamage)),
            target,
            source,
            absorbedDamage,
            reason
        )
    end

    broadcastMatchMessage(
        matchState,
        string.format(
            "%s trifft %s mit %s fuer %d Schaden.",
            source.name,
            target.name,
            reason,
            math.floor(remainingDamage)
        )
    )
end

local function healFighter(
    matchState: MatchState,
    source: FighterState,
    target: FighterState,
    amount: number,
    reason: string
)
    if amount <= 0 or not isAlive(target) then
        return
    end

    local previousHealth = target.health
    target.health = math.min(target.maxHealth, target.health + amount)
    local actualHealing = target.health - previousHealth
    if target.player then
        local humanoid = getHumanoid(target.player)
        if humanoid then
            humanoid.Health = target.health
        end
    end

    if actualHealing > 0 then
        pushCombatEvent(
            matchState,
            "Heal",
            string.format("+%d", math.floor(actualHealing)),
            target,
            source,
            actualHealing,
            reason
        )
    end

    broadcastMatchMessage(
        matchState,
        string.format("%s heilt %s mit %s um %d.", source.name, target.name, reason, actualHealing)
    )
end

local function applyCrowdControl(
    matchState: MatchState,
    source: FighterState,
    target: FighterState,
    ability: AbilityConfig
)
    if not ability.crowdControl or not ability.crowdControlDuration then
        return
    end

    local category = ability.crowdControl
    local now = os.clock()
    local drState = target.dr[category]
    if not drState or drState.expiresAt <= now then
        drState = { count = 0, expiresAt = now + Config.DRWindowSeconds }
    end

    local multiplier = Config.DRMultipliers[math.clamp(drState.count + 1, 1, #Config.DRMultipliers)]
        or 0
    drState.count += 1
    drState.expiresAt = now + Config.DRWindowSeconds
    target.dr[category] = drState

    local duration = ability.crowdControlDuration * multiplier
    if duration <= 0 then
        broadcastMatchMessage(
            matchState,
            string.format("%s widersteht %s durch DR.", target.name, ability.displayName)
        )
        pushCombatEvent(
            matchState,
            "Resist",
            "Widerstanden",
            target,
            source,
            nil,
            ability.displayName
        )
        return
    end

    local kind = ability.effectName or category
    table.insert(target.effects, {
        kind = kind,
        category = category,
        expiresAt = now + duration,
        amount = ability.slowMultiplier,
        sourceId = source.id,
    })
    applyMovementState(target)
    pushCombatEvent(
        matchState,
        "Control",
        string.format("%s %.1fs", kind, duration),
        target,
        source,
        duration,
        ability.displayName
    )
    broadcastMatchMessage(
        matchState,
        string.format("%s bekommt %s fuer %.1f Sekunden.", target.name, kind, duration)
    )
end

local function applyDot(target: FighterState, source: FighterState, ability: AbilityConfig)
    if not ability.dotDamage or not ability.dotDuration then
        return
    end

    table.insert(target.effects, {
        kind = "Burn",
        expiresAt = os.clock() + ability.dotDuration,
        amount = ability.dotDamage,
        nextTickAt = os.clock() + (ability.dotInterval or 1),
        tickInterval = ability.dotInterval or 1,
        sourceId = source.id,
    })
end

local function resolveAbility(
    matchState: MatchState,
    source: FighterState,
    abilityId: string,
    targetId: string?
)
    if matchState.phase ~= "Active" or not isAlive(source) then
        return
    end

    local ability = getAbilityConfig(source.classId, abilityId)
    if not ability then
        return
    end

    local targets: { FighterState } = {}

    if ability.area then
        local sourcePosition = getFighterPosition(source)
        if sourcePosition then
            for _, candidate in matchState.fighters do
                local candidatePosition = getFighterPosition(candidate)
                if candidate.team ~= source.team and isAlive(candidate) and candidatePosition then
                    if (sourcePosition - candidatePosition).Magnitude <= (ability.radius or 0) then
                        table.insert(targets, candidate)
                    end
                end
            end
        end
    else
        local target = findFighter(matchState, targetId or source.targetId)
        if ability.friendly then
            if not target or target.team ~= source.team then
                target = getFirstAlly(matchState, source)
            end
        elseif not target or target.team == source.team then
            target = getFirstEnemy(matchState, source)
        end

        if target and isAlive(target) then
            local range = ability.range or 0
            if target == source or range <= 0 or isInRange(source, target, range) then
                table.insert(targets, target)
            elseif source.player then
                sendMessage(source.player, "Ziel ist ausser Reichweite.")
            end
        end
    end

    if #targets == 0 then
        if source.player then
            sendMessage(source.player, "Kein gueltiges Ziel.")
        end
        return
    end

    for _, target in targets do
        if ability.interrupt and target.casting then
            target.castToken += 1
            target.casting = nil
            target.castLockedUntil = os.clock() + (ability.lockout or 0)
            pushCombatEvent(
                matchState,
                "Interrupt",
                "Unterbrochen",
                target,
                source,
                nil,
                ability.displayName
            )
            broadcastMatchMessage(
                matchState,
                string.format("%s unterbricht %s.", source.name, target.name)
            )
        end

        local damage = ability.damage or 0
        if
            ability.executeBonus
            and ability.executeThreshold
            and target.health / target.maxHealth <= ability.executeThreshold
        then
            damage += ability.executeBonus
        end

        if ability.consumeFocus then
            damage += source.focus * (ability.focusDamage or 0)
            source.focus = 0
        end

        if damage > 0 then
            damageFighter(matchState, source, target, damage, ability.displayName)
        end

        if ability.heal then
            healFighter(matchState, source, target, ability.heal, ability.displayName)
        end

        if ability.fullHeal then
            healFighter(matchState, source, target, target.maxHealth, ability.displayName)
        end

        if ability.shield and ability.shieldDuration then
            target.shield = ability.shield
            target.shieldExpiresAt = os.clock() + ability.shieldDuration
            pushCombatEvent(
                matchState,
                "Shield",
                "Schild",
                target,
                source,
                ability.shield,
                ability.displayName
            )
            broadcastMatchMessage(
                matchState,
                string.format("%s schuetzt %s.", source.name, target.name)
            )
        end

        applyCrowdControl(matchState, source, target, ability)
        applyDot(target, source, ability)
    end

    if ability.focusGain then
        source.focus = math.min(Config.MaxFocus, source.focus + ability.focusGain)
    end
end

local function castAbility(source: FighterState, abilityId: string)
    local matchState = activeMatch
    if not matchState or matchState.phase ~= "Active" then
        if source.player then
            sendMessage(source.player, "Der Kampf hat noch nicht begonnen.")
        end
        return
    end

    local ability = getAbilityConfig(source.classId, abilityId)
    if not ability then
        return
    end

    local now = os.clock()
    if source.cooldowns[abilityId] and source.cooldowns[abilityId] > now then
        if source.player then
            sendMessage(source.player, "Faehigkeit ist noch auf Cooldown.")
        end
        return
    end

    if hasActionBlockingEffect(source) then
        if source.player then
            sendMessage(source.player, "Du bist kontrolliert und kannst nicht handeln.")
        end
        return
    end

    if source.castLockedUntil > now and ability.castTime > 0 then
        if source.player then
            sendMessage(source.player, "Du bist unterbrochen und kannst gerade nicht zaubern.")
        end
        return
    end

    if source.casting then
        if source.player then
            sendMessage(source.player, "Du zauberst bereits.")
        end
        return
    end

    source.cooldowns[abilityId] = now + ability.cooldown
    source.castToken += 1
    local token = source.castToken
    local targetId = source.targetId

    if ability.castTime > 0 then
        source.casting = {
            abilityId = abilityId,
            targetId = targetId,
            startedAt = now,
            endsAt = now + ability.castTime,
            duration = ability.castTime,
            token = token,
        }
        pushCombatEvent(
            matchState,
            "Cast",
            ability.displayName,
            source,
            source,
            ability.castTime,
            ability.displayName
        )
        broadcastMatchState(matchState)

        task.delay(ability.castTime, function()
            local currentMatch = activeMatch
            if
                not currentMatch
                or currentMatch.id ~= matchState.id
                or source.castToken ~= token
            then
                return
            end

            source.casting = nil
            resolveAbility(currentMatch, source, abilityId, targetId)
            broadcastMatchState(currentMatch)
        end)
    else
        resolveAbility(matchState, source, abilityId, targetId)
        broadcastMatchState(matchState)
    end
end

local function processEffects(matchState: MatchState)
    local now = os.clock()
    for _, fighter in matchState.fighters do
        removeExpiredEffects(fighter)

        for _, effect in fighter.effects do
            if
                effect.kind == "Burn"
                and effect.amount
                and effect.nextTickAt
                and effect.tickInterval
                and effect.nextTickAt <= now
            then
                local source = findFighter(matchState, effect.sourceId) or fighter
                damageFighter(matchState, source, fighter, effect.amount, "Burn")
                effect.nextTickAt = now + effect.tickInterval
            end
        end

        applyMovementState(fighter)
    end
end

local function getWinningTeam(matchState: MatchState): number?
    local teamOneAlive = false
    local teamTwoAlive = false

    for _, fighter in matchState.fighters do
        if isAlive(fighter) then
            if fighter.team == TEAM_ONE then
                teamOneAlive = true
            elseif fighter.team == TEAM_TWO then
                teamTwoAlive = true
            end
        end
    end

    if teamOneAlive and not teamTwoAlive then
        return TEAM_ONE
    elseif teamTwoAlive and not teamOneAlive then
        return TEAM_TWO
    end

    return nil
end

local function cleanupMatch(matchState: MatchState)
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end

    activeMatch = nil
    setGatesOpen(false)

    for _, fighter in matchState.fighters do
        if fighter.botModel then
            fighter.botModel:Destroy()
        end

        if fighter.player then
            resetPlayerCharacter(fighter.player)
            teleportPlayer(fighter.player, "LobbySpawn", 1)
            sendLobbyState(fighter.player)
        end
    end
end

local function finishMatch(matchState: MatchState, winnerTeam: number)
    if matchState.phase == "Finished" then
        return
    end

    matchState.phase = "Finished"
    matchState.winnerTeam = winnerTeam
    matchState.countdown = Config.FinishedReturnSeconds
    print(string.format("[Arena] Match #%d beendet: Team %d gewinnt", matchState.id, winnerTeam))
    broadcastMatchMessage(
        matchState,
        string.format(
            "Team %d gewinnt! Rueckkehr zur Lobby in %d Sekunden.",
            winnerTeam,
            Config.FinishedReturnSeconds
        )
    )
    broadcastMatchState(matchState)

    task.delay(Config.FinishedReturnSeconds, function()
        if activeMatch and activeMatch.id == matchState.id then
            cleanupMatch(matchState)
        end
    end)
end

local function startHeartbeat(matchState: MatchState)
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
    end

    local lastSnapshotAt = 0
    heartbeatConnection = RunService.Heartbeat:Connect(function()
        if activeMatch ~= matchState or matchState.phase ~= "Active" then
            return
        end

        processEffects(matchState)
        local winnerTeam = getWinningTeam(matchState)
        if winnerTeam then
            finishMatch(matchState, winnerTeam)
            return
        end

        if os.clock() - lastSnapshotAt >= 0.35 then
            lastSnapshotAt = os.clock()
            broadcastMatchState(matchState)
        end
    end)
end

local function canBotCast(bot: FighterState, abilityId: string): boolean
    local ability = getAbilityConfig(bot.classId, abilityId)
    if not ability then
        return false
    end

    local now = os.clock()
    return not bot.casting
        and not hasActionBlockingEffect(bot)
        and (not bot.cooldowns[abilityId] or bot.cooldowns[abilityId] <= now)
        and (ability.castTime <= 0 or bot.castLockedUntil <= now)
end

local function chooseBotAbility(bot: FighterState, target: FighterState): string
    local botPosition = getFighterPosition(bot)
    local targetPosition = getFighterPosition(target)
    local distance = if botPosition and targetPosition
        then (botPosition - targetPosition).Magnitude
        else math.huge

    if target.health / target.maxHealth <= 0.35 and canBotCast(bot, "Ability4") then
        return "Ability4"
    end

    if bot.classId == "Mage" then
        if distance <= 18 and canBotCast(bot, "Ability3") then
            return "Ability3"
        end

        if canBotCast(bot, "Ability2") then
            return "Ability2"
        end

        return "Ability1"
    end

    if distance <= 16 and canBotCast(bot, "Ability3") then
        return "Ability3"
    end

    if canBotCast(bot, "Ability2") and math.random() < 0.45 then
        return "Ability2"
    end

    return "Ability1"
end

local function runPlayerAutoAi(matchState: MatchState, fighter: FighterState)
    -- Only run when the match was started by Studio automation (no human input).
    task.spawn(function()
        while activeMatch == matchState and matchState.phase ~= "Finished" and isAlive(fighter) do
            if matchState.phase == "Active" then
                local target = getFirstEnemy(matchState, fighter)
                if target then
                    fighter.targetId = target.id
                    local targetPosition = getFighterPosition(target)
                    local myPosition = getFighterPosition(fighter)
                    if targetPosition and myPosition then
                        local ability1 = getAbilityConfig(fighter.classId, "Ability1")
                        local isMelee = ability1 ~= nil
                            and (ability1.range or 0) > 0
                            and (ability1.range or 0) <= 15
                        local preferredDist = if isMelee
                            then Config.BotAi.meleePreferredDistance
                            else Config.BotAi.rangedPreferredDistance
                        local strafeDistance = if isMelee then 2 else Config.BotAi.strafeDistance

                        local dist = (myPosition - targetPosition).Magnitude
                        local desiredPosition = nil
                        if dist > preferredDist + 2 then
                            local dir = (targetPosition - myPosition).Unit
                            desiredPosition = targetPosition - dir * preferredDist
                        elseif not isMelee and dist < preferredDist - 4 then
                            local dir = (myPosition - targetPosition)
                            if dir.Magnitude > 0.001 then
                                desiredPosition = targetPosition
                                    + dir.Unit * preferredDist
                                    + Vector3.new(
                                        0,
                                        0,
                                        math.random(-strafeDistance, strafeDistance)
                                    )
                            end
                        elseif not isMelee then
                            desiredPosition = myPosition
                                + Vector3.new(0, 0, math.random(-strafeDistance, strafeDistance))
                        end

                        if desiredPosition then
                            local character = fighter.player and fighter.player.Character
                            local humanoid = character
                                and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
                            if humanoid and humanoid.Health > 0 then
                                humanoid:MoveTo(
                                    Vector3.new(desiredPosition.X, myPosition.Y, desiredPosition.Z)
                                )
                            end
                        end
                    end

                    castAbility(fighter, chooseBotAbility(fighter, target))
                end
            end

            task.wait(Config.BotAi.tickSeconds)
        end
    end)
end

local function runBotAi(matchState: MatchState, bot: FighterState)
    task.spawn(function()
        while activeMatch == matchState and matchState.phase ~= "Finished" and isAlive(bot) do
            if matchState.phase == "Active" then
                local target = getFirstEnemy(matchState, bot)
                if target then
                    bot.targetId = target.id
                    local targetPosition = getFighterPosition(target)
                    if targetPosition then
                        local ability1 = getAbilityConfig(bot.classId, "Ability1")
                        local isMelee = ability1 ~= nil
                            and (ability1.range or 0) > 0
                            and (ability1.range or 0) <= 15
                        local preferredDist = if isMelee
                            then Config.BotAi.meleePreferredDistance
                            else Config.BotAi.rangedPreferredDistance
                        local strafeRange = if isMelee then 2 else 8
                        local laneOffset = if targetPosition.X >= 0
                            then -preferredDist
                            else preferredDist
                        moveBotTo(
                            bot,
                            targetPosition
                                + Vector3.new(laneOffset, 0, math.random(-strafeRange, strafeRange))
                        )
                    end

                    castAbility(bot, chooseBotAbility(bot, target))
                end
            end

            task.wait(Config.BotAi.tickSeconds)
        end
    end)
end

local function prepareFighterCharacter(fighter: FighterState, spawnIndex: number)
    if fighter.player then
        selectedClassByPlayer[fighter.player] = fighter.classId
        resetPlayerCharacter(fighter.player)
        placeFighterAtMarker(
            fighter,
            if fighter.team == TEAM_ONE then "TeamOnePrepSpawn" else "TeamTwoPrepSpawn",
            spawnIndex
        )
    elseif fighter.isBot then
        createBotModel(fighter)
        placeFighterAtMarker(
            fighter,
            if fighter.team == TEAM_ONE then "TeamOnePrepSpawn" else "TeamTwoPrepSpawn",
            spawnIndex
        )
    end
end

local function startMatch(mode: string, playersForMatch: { Player }, includeBot: boolean)
    if activeMatch then
        for _, player in playersForMatch do
            sendMessage(player, "Die Arena ist gerade besetzt.")
        end
        return
    end

    local matchId = nextMatchId
    nextMatchId += 1
    local fighters: { FighterState } = {}

    if mode == "Duel2v2" then
        for index, player in playersForMatch do
            local team = if index <= 2 then TEAM_ONE else TEAM_TWO
            table.insert(
                fighters,
                makeFighter(player, team, selectedClassByPlayer[player] or "Warrior", false)
            )
        end
    else
        local firstPlayer = playersForMatch[1]
        table.insert(
            fighters,
            makeFighter(
                firstPlayer,
                TEAM_ONE,
                selectedClassByPlayer[firstPlayer] or "Warrior",
                false
            )
        )

        if includeBot then
            local botClassId =
                Config.BotClassRotation[((matchId - 1) % #Config.BotClassRotation) + 1]
            table.insert(fighters, makeFighter(nil, TEAM_TWO, botClassId, true))
        else
            local secondPlayer = playersForMatch[2]
            table.insert(
                fighters,
                makeFighter(
                    secondPlayer,
                    TEAM_TWO,
                    selectedClassByPlayer[secondPlayer] or "Warrior",
                    false
                )
            )
        end
    end

    local prepSeconds = if includeBot
        then Config.BotPreparationSeconds
        else Config.PreparationSeconds
    local matchState: MatchState = {
        id = matchId,
        mode = mode,
        phase = "Preparing",
        countdown = prepSeconds,
        prepSeconds = prepSeconds,
        startedAt = os.clock(),
        fighters = fighters,
        combatEvents = {},
        nextCombatEventId = 0,
        gatesOpen = false,
        winnerTeam = nil,
    }
    activeMatch = matchState
    setGatesOpen(false)

    local spawnCounts = { [TEAM_ONE] = 0, [TEAM_TWO] = 0 }
    for _, fighter in fighters do
        spawnCounts[fighter.team] += 1
        prepareFighterCharacter(fighter, spawnCounts[fighter.team])
    end

    for _, fighter in fighters do
        fighter.targetId = (getFirstEnemy(matchState, fighter) or fighter).id
    end

    broadcastMatchMessage(matchState, "Match gefunden. Vorbereitung startet.")
    broadcastMatchState(matchState)
    print(string.format("[Arena] Match #%d gestartet: %s", matchId, mode))

    task.spawn(function()
        for remaining = prepSeconds, 1, -1 do
            if activeMatch ~= matchState then
                return
            end

            matchState.countdown = remaining
            broadcastMatchState(matchState)
            task.wait(1)
        end

        if activeMatch ~= matchState then
            return
        end

        matchState.phase = "Active"
        matchState.countdown = 0
        matchState.gatesOpen = true
        setGatesOpen(true)

        local entryCounts = { [TEAM_ONE] = 0, [TEAM_TWO] = 0 }
        for _, fighter in fighters do
            entryCounts[fighter.team] += 1
            placeFighterAtMarker(
                fighter,
                if fighter.team == TEAM_ONE then "TeamOneArenaEntry" else "TeamTwoArenaEntry",
                entryCounts[fighter.team]
            )
        end

        broadcastMatchMessage(matchState, "Die Tore sind offen. Kampf beginnt!")
        broadcastMatchState(matchState)
        startHeartbeat(matchState)

        for _, fighter in fighters do
            if fighter.isBot then
                runBotAi(matchState, fighter)
            elseif matchState.mode == "Bot" and fighter.player then
                -- In Studio 1vsCOM automation the human has no keyboard input;
                -- run the same AI loop on the player character so it actually fights.
                runPlayerAutoAi(matchState, fighter)
            end
        end
    end)
end

local function removeFromQueues(player: Player)
    local queuedMode = playerQueues[player]
    if not queuedMode then
        return
    end

    local queue = queues[queuedMode]
    if queue then
        local index = table.find(queue, player)
        if index then
            table.remove(queue, index)
        end
    end

    playerQueues[player] = nil
end

local function tryStartQueuedMatch(mode: string)
    local modeConfig = Config.MatchModes[mode]
    local queue = queues[mode]
    if not modeConfig or not queue or activeMatch or #queue < modeConfig.playersNeeded then
        return
    end

    local playersForMatch = {}
    for _ = 1, modeConfig.playersNeeded do
        local player = table.remove(queue, 1)
        if player then
            playerQueues[player] = nil
            table.insert(playersForMatch, player)
        end
    end

    startMatch(mode, playersForMatch, false)
end

queueRequestEvent.OnServerEvent:Connect(function(player: Player, mode: string)
    if typeof(mode) ~= "string" or not Config.MatchModes[mode] then
        return
    end

    if activeMatch then
        sendMessage(player, "Die Arena ist gerade besetzt. Warte kurz bis zum naechsten Match.")
        return
    end

    removeFromQueues(player)

    if mode == "Bot" then
        print(string.format("[Arena] %s stellt sich fuer 1vsCOM an", player.DisplayName))
        startMatch("Bot", { player }, true)
        return
    end

    local queue = queues[mode]
    if not queue then
        return
    end

    if not table.find(queue, player) then
        table.insert(queue, player)
        playerQueues[player] = mode
        sendMessage(
            player,
            string.format("Du bist in der %s Warteschlange.", Config.MatchModes[mode].displayName)
        )
    end

    sendLobbyState(player)
    tryStartQueuedMatch(mode)
end)

classSelectEvent.OnServerEvent:Connect(function(player: Player, classId: string)
    if typeof(classId) ~= "string" or not Config.Classes[classId] then
        return
    end

    if getFighterForPlayer(player) then
        sendMessage(player, "Klassenwechsel ist erst nach dem Match moeglich.")
        return
    end

    selectedClassByPlayer[player] = classId
    resetPlayerCharacter(player)
    sendLobbyState(player)
    sendMessage(player, "Klasse gewaehlt: " .. Config.Classes[classId].displayName)
end)

targetSelectEvent.OnServerEvent:Connect(function(player: Player, targetId: string)
    if typeof(targetId) ~= "string" then
        return
    end

    local matchState = activeMatch
    local fighter = getFighterForPlayer(player)
    if not matchState or not fighter then
        return
    end

    local target = findFighter(matchState, targetId)
    if target and isAlive(target) then
        fighter.targetId = target.id
        broadcastMatchState(matchState)
    end
end)

abilityCastEvent.OnServerEvent:Connect(function(player: Player, abilityId: string)
    if typeof(abilityId) ~= "string" then
        return
    end

    local fighter = getFighterForPlayer(player)
    if not fighter then
        sendMessage(player, "Du bist in keinem Match.")
        return
    end

    castAbility(fighter, abilityId)
end)

Players.PlayerAdded:Connect(function(player: Player)
    selectedClassByPlayer[player] = selectedClassByPlayer[player] or "Warrior"
    player.CharacterAdded:Connect(function()
        task.wait(0.2)
        resetPlayerCharacter(player)
        if not getFighterForPlayer(player) then
            teleportPlayer(player, "LobbySpawn", 1)
            sendLobbyState(player)
        end
    end)

    task.defer(function()
        sendLobbyState(player)
    end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
    removeFromQueues(player)
    selectedClassByPlayer[player] = nil

    local matchState = activeMatch
    if not matchState then
        return
    end

    local fighter = getFighterForPlayer(player)
    if fighter then
        fighter.health = 0
        local winnerTeam = getWinningTeam(matchState)
        if winnerTeam then
            finishMatch(matchState, winnerTeam)
        end
    end
end)

buildArenaWorld()
setGatesOpen(false)

for _, player in Players:GetPlayers() do
    selectedClassByPlayer[player] = selectedClassByPlayer[player] or "Warrior"
    resetPlayerCharacter(player)
    teleportPlayer(player, "LobbySpawn", 1)
    sendLobbyState(player)
end
