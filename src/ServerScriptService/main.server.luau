local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
    endsAt: number,
    token: number,
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
    startedAt: number,
    fighters: { FighterState },
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

    local stone = Color3.fromRGB(84, 86, 94)
    local darkStone = Color3.fromRGB(43, 45, 52)
    local sand = Color3.fromRGB(156, 137, 91)
    local blue = Color3.fromRGB(54, 105, 170)
    local red = Color3.fromRGB(170, 61, 54)
    local gold = Color3.fromRGB(214, 172, 72)

    makePart(
        world,
        "ArenaFloor",
        Vector3.new(0, 0, 0),
        Vector3.new(124, 1, 74),
        sand,
        Enum.Material.Sand
    )
    makePart(
        world,
        "NorthWall",
        Vector3.new(0, 5, -38),
        Vector3.new(128, 10, 4),
        stone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "SouthWall",
        Vector3.new(0, 5, 38),
        Vector3.new(128, 10, 4),
        stone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "WestWallNorth",
        Vector3.new(-64, 5, -28),
        Vector3.new(4, 10, 20),
        stone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "WestWallSouth",
        Vector3.new(-64, 5, 28),
        Vector3.new(4, 10, 20),
        stone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "EastWallNorth",
        Vector3.new(64, 5, -28),
        Vector3.new(4, 10, 20),
        stone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "EastWallSouth",
        Vector3.new(64, 5, 28),
        Vector3.new(4, 10, 20),
        stone,
        Enum.Material.Slate
    )

    makePart(
        world,
        "TeamOnePrepFloor",
        Vector3.new(-96, 0.05, 0),
        Vector3.new(34, 1, 36),
        blue,
        Enum.Material.Concrete,
        0.08
    )
    makePart(
        world,
        "TeamTwoPrepFloor",
        Vector3.new(96, 0.05, 0),
        Vector3.new(34, 1, 36),
        red,
        Enum.Material.Concrete,
        0.08
    )
    makePart(
        world,
        "TeamOnePrepBackWall",
        Vector3.new(-114, 5, 0),
        Vector3.new(4, 10, 38),
        darkStone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "TeamTwoPrepBackWall",
        Vector3.new(114, 5, 0),
        Vector3.new(4, 10, 38),
        darkStone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "TeamOnePrepNorthWall",
        Vector3.new(-96, 5, -20),
        Vector3.new(36, 10, 4),
        darkStone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "TeamOnePrepSouthWall",
        Vector3.new(-96, 5, 20),
        Vector3.new(36, 10, 4),
        darkStone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "TeamTwoPrepNorthWall",
        Vector3.new(96, 5, -20),
        Vector3.new(36, 10, 4),
        darkStone,
        Enum.Material.Slate
    )
    makePart(
        world,
        "TeamTwoPrepSouthWall",
        Vector3.new(96, 5, 20),
        Vector3.new(36, 10, 4),
        darkStone,
        Enum.Material.Slate
    )

    local leftGate = makePart(
        world,
        "TeamOneGate",
        Vector3.new(-65, 4, 0),
        Vector3.new(3, 8, 18),
        gold,
        Enum.Material.Metal,
        0.05
    )
    local rightGate = makePart(
        world,
        "TeamTwoGate",
        Vector3.new(65, 4, 0),
        Vector3.new(3, 8, 18),
        gold,
        Enum.Material.Metal,
        0.05
    )
    gateParts = { leftGate, rightGate }

    makePart(
        world,
        "LobbyFloor",
        Vector3.new(0, 0, 92),
        Vector3.new(72, 1, 38),
        Color3.fromRGB(66, 74, 88),
        Enum.Material.Concrete
    )
    makePart(
        world,
        "LobbySpawn",
        Vector3.new(0, 2, 92),
        Vector3.new(6, 1, 6),
        Color3.fromRGB(101, 179, 104),
        Enum.Material.Neon,
        0.25
    )
    makePart(
        world,
        "TeamOnePrepSpawn",
        Vector3.new(-98, 2, 0),
        Vector3.new(6, 1, 6),
        blue,
        Enum.Material.Neon,
        0.2
    )
    makePart(
        world,
        "TeamTwoPrepSpawn",
        Vector3.new(98, 2, 0),
        Vector3.new(6, 1, 6),
        red,
        Enum.Material.Neon,
        0.2
    )
    makePart(
        world,
        "TeamOneArenaEntry",
        Vector3.new(-48, 2, 0),
        Vector3.new(5, 1, 5),
        blue,
        Enum.Material.Neon,
        0.35
    )
    makePart(
        world,
        "TeamTwoArenaEntry",
        Vector3.new(48, 2, 0),
        Vector3.new(5, 1, 5),
        red,
        Enum.Material.Neon,
        0.35
    )
end

local function setGatesOpen(open: boolean)
    for _, gate in gateParts do
        gate.CanCollide = not open
        gate.CanTouch = open
        gate.CanQuery = true
        gate.Transparency = if open then 0.65 else 0.05
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
    root.Position = Vector3.new(98, 3.5, 0)
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

local function moveBotTo(fighter: FighterState, position: Vector3)
    if fighter.botModel and fighter.botModel.PrimaryPart then
        fighter.botModel.PrimaryPart.CFrame = CFrame.new(position)
    end
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

    if rooted or stunned then
        walkSpeed = 0
    end

    humanoid.WalkSpeed = walkSpeed
    humanoid.JumpPower = if rooted or stunned then 0 else 50
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
        casting = {
            abilityId = fighter.casting.abilityId,
            remaining = math.max(0, fighter.casting.endsAt - os.clock()),
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
    if target.shield > 0 and target.shieldExpiresAt > os.clock() then
        local absorbed = math.min(target.shield, remainingDamage)
        target.shield -= absorbed
        remainingDamage -= absorbed
    end

    if remainingDamage > 0 then
        target.health = math.max(0, target.health - remainingDamage)
        if target.player then
            local humanoid = getHumanoid(target.player)
            if humanoid then
                humanoid.Health = math.max(1, target.health)
            end
        end
    end

    broadcastMatchMessage(
        matchState,
        string.format(
            "%s trifft %s mit %s fuer %d Schaden.",
            source.name,
            target.name,
            reason,
            amount
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

    target.health = math.min(target.maxHealth, target.health + amount)
    if target.player then
        local humanoid = getHumanoid(target.player)
        if humanoid then
            humanoid.Health = target.health
        end
    end

    broadcastMatchMessage(
        matchState,
        string.format("%s heilt %s mit %s um %d.", source.name, target.name, reason, amount)
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
            endsAt = now + ability.castTime,
            token = token,
        }
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

local function runBotAi(matchState: MatchState, bot: FighterState)
    task.spawn(function()
        while activeMatch == matchState and matchState.phase ~= "Finished" and isAlive(bot) do
            if matchState.phase == "Active" then
                local target = getFirstEnemy(matchState, bot)
                if target then
                    bot.targetId = target.id
                    local targetPosition = getFighterPosition(target)
                    if targetPosition then
                        moveBotTo(bot, targetPosition + Vector3.new(10, 0, 0))
                    end

                    if
                        bot.health / bot.maxHealth < 0.35
                        and getAbilityConfig(bot.classId, "Ability3")
                    then
                        castAbility(bot, "Ability3")
                    elseif math.random() < 0.25 then
                        castAbility(bot, "Ability2")
                    else
                        castAbility(bot, "Ability1")
                    end
                end
            end

            task.wait(1.25)
        end
    end)
end

local function prepareFighterCharacter(fighter: FighterState, spawnIndex: number)
    if fighter.player then
        selectedClassByPlayer[fighter.player] = fighter.classId
        resetPlayerCharacter(fighter.player)
        teleportPlayer(
            fighter.player,
            if fighter.team == TEAM_ONE then "TeamOnePrepSpawn" else "TeamTwoPrepSpawn",
            spawnIndex
        )
    elseif fighter.isBot then
        createBotModel(fighter)
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
            table.insert(fighters, makeFighter(nil, TEAM_TWO, "Mage", true))
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

    local matchState: MatchState = {
        id = matchId,
        mode = mode,
        phase = "Preparing",
        countdown = Config.PreparationSeconds,
        startedAt = os.clock(),
        fighters = fighters,
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

    task.spawn(function()
        for remaining = Config.PreparationSeconds, 1, -1 do
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
        broadcastMatchMessage(matchState, "Die Tore sind offen. Kampf beginnt!")
        broadcastMatchState(matchState)
        startHeartbeat(matchState)

        for _, fighter in fighters do
            if fighter.isBot then
                runBotAi(matchState, fighter)
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
