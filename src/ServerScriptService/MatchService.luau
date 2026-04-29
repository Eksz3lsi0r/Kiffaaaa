--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage.Shared)
local MatchConfig = Shared.MatchConfig
local Elements = Shared.Elements
local Loadouts = Shared.Loadouts

type ElementName = "Earth" | "Air" | "Fire" | "Water"
type AbilitySlot = "Primary" | "Secondary" | "Ultimate"
type MatchMode = "PvP" | "PvE"

type LoadoutSnapshot = {
    Id: string,
    Element: ElementName,
    DisplayName: string,
    Summary: string,
    Passive: string,
    UnlockProgress: number,
    DamageMultiplier: number,
    HealthBonus: number,
    CooldownMultiplier: number,
    Unlocked: boolean,
    Selected: boolean,
}

type ArenaData = {
    Folder: Folder,
    LeftSpawn: SpawnLocation,
    RightSpawn: SpawnLocation,
    Center: Vector3,
}

type FighterState = {
    Cooldowns: { [AbilitySlot]: number },
    Shield: number,
    ShieldToken: number,
    SpeedBonusUntil: number,
    SpeedBonusValue: number,
    SlowUntil: number,
    SlowPenalty: number,
    RoundConnections: { RBXScriptConnection },
}

type BotState = {
    Name: string,
    UserId: number,
    Element: ElementName,
    LoadoutId: string,
    Progress: number,
    GearTier: number,
    BonusDamage: number,
    BonusHealth: number,
    CooldownMultiplier: number,
    UltimateUnlocked: boolean,
    Rewards: { string },
    CurrentHealth: number,
    MaxHealth: number,
    Shield: number,
    Position: Vector3,
    Cooldowns: { [AbilitySlot]: number },
    SpeedBonusUntil: number,
    SpeedBonusValue: number,
    SlowUntil: number,
    SlowPenalty: number,
    ActionToken: number,
    SelectedElement: boolean,
}

type MatchData = {
    Id: number,
    Players: { Player },
    Bot: BotState?,
    Mode: MatchMode,
    Phase: string,
    Message: string,
    RoundNumber: number,
    Scores: { [number]: number },
    SelectionEndsAt: number,
    RoundEndsAt: number,
    WinnerUserId: number?,
    LoserUserId: number?,
    Reward: any,
    ResultReason: string?,
    LastRoundWinnerUserId: number?,
}

local MatchService = {}
MatchService.__index = MatchService

local function roundTenth(value: number): number
    return math.floor(value * 10 + 0.5) / 10
end

local function isAbilitySlot(value: string): boolean
    return value == "Primary" or value == "Secondary" or value == "Ultimate"
end

function MatchService.new(progression: any)
    local remoteFolder = ReplicatedStorage:FindFirstChild(MatchConfig.RemoteFolderName)
    if remoteFolder then
        remoteFolder:Destroy()
    end

    remoteFolder = Instance.new("Folder")
    remoteFolder.Name = MatchConfig.RemoteFolderName
    remoteFolder.Parent = ReplicatedStorage

    local stateEvent = Instance.new("RemoteEvent")
    stateEvent.Name = MatchConfig.StateEventName
    stateEvent.Parent = remoteFolder

    local chooseElementEvent = Instance.new("RemoteEvent")
    chooseElementEvent.Name = MatchConfig.ChooseElementEventName
    chooseElementEvent.Parent = remoteFolder

    local chooseLoadoutEvent = Instance.new("RemoteEvent")
    chooseLoadoutEvent.Name = MatchConfig.ChooseLoadoutEventName
    chooseLoadoutEvent.Parent = remoteFolder

    local castAbilityEvent = Instance.new("RemoteEvent")
    castAbilityEvent.Name = MatchConfig.CastAbilityEventName
    castAbilityEvent.Parent = remoteFolder

    local requestStateFunction = Instance.new("RemoteFunction")
    requestStateFunction.Name = MatchConfig.RequestStateFunctionName
    requestStateFunction.Parent = remoteFolder

    local self = setmetatable({
        Progression = progression,
        Arena = nil :: ArenaData?,
        RemoteFolder = remoteFolder,
        StateEvent = stateEvent,
        ChooseElementEvent = chooseElementEvent,
        ChooseLoadoutEvent = chooseLoadoutEvent,
        CastAbilityEvent = castAbilityEvent,
        RequestStateFunction = requestStateFunction,
        CurrentMatch = nil :: MatchData?,
        FighterStates = {} :: { [Player]: FighterState },
        MatchId = 0,
        SoloStartToken = 0,
        Rng = Random.new(),
    }, MatchService)

    return self
end

function MatchService:start()
    self.ChooseElementEvent.OnServerEvent:Connect(function(player: Player, elementName: string)
        self:_handleChooseElement(player, elementName)
    end)

    self.ChooseLoadoutEvent.OnServerEvent:Connect(function(player: Player, loadoutId: string)
        self:_handleChooseLoadout(player, loadoutId)
    end)

    self.CastAbilityEvent.OnServerEvent:Connect(function(player: Player, slotName: string)
        self:_handleCast(player, slotName)
    end)

    self.RequestStateFunction.OnServerInvoke = function(player: Player)
        return self:_serializeState(player)
    end

    Players.PlayerAdded:Connect(function(player)
        self.Progression:getProfile(player)
        self:_broadcastState()
        self:_tryStartMatch()
    end)

    Players.PlayerRemoving:Connect(function(player)
        self.Progression:removePlayer(player)
        self.FighterStates[player] = nil
        self:_handlePlayerRemoving(player)
        self:_broadcastState()
        self:_tryStartMatch()
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        self.Progression:getProfile(player)
    end

    task.defer(function()
        self:_broadcastState()
        self:_tryStartMatch()
    end)
end

function MatchService:setArena(arena: ArenaData)
    self.Arena = arena
    self:_setMessage("Arena bereit. Warte auf zwei Gladiatoren.")
    self:_broadcastState()
    self:_tryStartMatch()
end

function MatchService:_setMessage(message: string)
    if self.CurrentMatch then
        self.CurrentMatch.Message = message
    end
end

function MatchService:_ensureFighterState(player: Player): FighterState
    local fighterState = self.FighterStates[player]
    if fighterState then
        return fighterState
    end

    fighterState = {
        Cooldowns = {},
        Shield = 0,
        ShieldToken = 0,
        SpeedBonusUntil = 0,
        SpeedBonusValue = 0,
        SlowUntil = 0,
        SlowPenalty = 0,
        RoundConnections = {},
    }
    self.FighterStates[player] = fighterState
    return fighterState
end

function MatchService:_disconnectRoundConnections(player: Player)
    local fighterState = self:_ensureFighterState(player)
    for _, connection in ipairs(fighterState.RoundConnections) do
        connection:Disconnect()
    end
    fighterState.RoundConnections = {}
    fighterState.Shield = 0
    fighterState.SpeedBonusUntil = 0
    fighterState.SpeedBonusValue = 0
    fighterState.SlowUntil = 0
    fighterState.SlowPenalty = 0
    for slotName, _ in pairs(fighterState.Cooldowns) do
        fighterState.Cooldowns[slotName] = 0
    end
end

function MatchService:_getAvailablePlayers(): { Player }
    local available = {}
    local activeMatch = self.CurrentMatch
    for _, player in ipairs(Players:GetPlayers()) do
        local inMatch = activeMatch and table.find(activeMatch.Players, player) ~= nil
        if not inMatch then
            table.insert(available, player)
        end
    end
    return available
end

function MatchService:_isCurrentMatch(matchId: number, expectedPhase: string?): boolean
    local match = self.CurrentMatch
    if not match then
        return false
    end
    if match.Id ~= matchId then
        return false
    end
    if expectedPhase ~= nil and match.Phase ~= expectedPhase then
        return false
    end
    return true
end

function MatchService:_tryStartMatch()
    if self.CurrentMatch ~= nil or self.Arena == nil then
        return
    end

    local availablePlayers = self:_getAvailablePlayers()
    if #availablePlayers >= MatchConfig.RequiredPlayers then
        self.SoloStartToken += 1
        local contenders = { availablePlayers[1], availablePlayers[2] }
        self:_beginSelection(contenders, "PvP")
        return
    end

    if #availablePlayers == 1 then
        self.SoloStartToken += 1
        local soloToken = self.SoloStartToken
        self:_setMessage("Warte auf einen zweiten Spieler oder den Computergegner.")
        self:_broadcastState()

        task.delay(MatchConfig.SoloBotStartDelay, function()
            if
                self.CurrentMatch ~= nil
                or self.Arena == nil
                or self.SoloStartToken ~= soloToken
            then
                return
            end

            local currentAvailable = self:_getAvailablePlayers()
            if #currentAvailable == 1 then
                local bot = self:_createBotOpponent(currentAvailable[1])
                self:_beginSelection({ currentAvailable[1] }, "PvE", bot)
            end
        end)
        return
    end

    self.SoloStartToken += 1
end

function MatchService:_beginSelection(contenders: { Player }, mode: MatchMode, bot: BotState?)
    self.MatchId += 1

    local scores = {}
    for _, player in ipairs(contenders) do
        scores[player.UserId] = 0
        self:_ensureFighterState(player)
    end

    if bot then
        scores[bot.UserId] = 0
    end

    self.CurrentMatch = {
        Id = self.MatchId,
        Players = contenders,
        Bot = bot,
        Mode = mode,
        Phase = "Selection",
        Message = if mode == "PvE"
            then "Waehle Erde, Luft, Feuer oder Wasser. Der Computergegner ruestet sich auf."
            else "Waehle Erde, Luft, Feuer oder Wasser und dann dein Loadout.",
        RoundNumber = 0,
        Scores = scores,
        SelectionEndsAt = os.clock() + MatchConfig.SelectionDuration,
        RoundEndsAt = 0,
        Reward = nil,
    }

    self:_broadcastState()

    local matchId = self.MatchId
    task.delay(MatchConfig.SelectionDuration, function()
        if self:_isCurrentMatch(matchId, "Selection") then
            self:_startRound(matchId)
        end
    end)
end

function MatchService:_handleChooseElement(player: Player, elementName: string)
    if Elements.Elements[elementName] == nil then
        return
    end

    local match = self.CurrentMatch
    if match ~= nil then
        local isContender = table.find(match.Players, player) ~= nil
        if isContender and match.Phase == "Round" then
            return
        end
    end

    self.Progression:setElement(player, elementName)
    self:_broadcastState()
end

function MatchService:_handleChooseLoadout(player: Player, loadoutId: string)
    local match = self.CurrentMatch
    if match ~= nil and match.Phase == "Round" then
        return
    end

    if not self.Progression:setLoadout(player, loadoutId) then
        self:_broadcastState()
        return
    end

    self:_broadcastState()
end

function MatchService:_serializeLoadout(loadoutId: string, selected: boolean): LoadoutSnapshot
    local loadout = Loadouts.Loadouts[loadoutId]
    return {
        Id = loadout.Id,
        Element = loadout.Element,
        DisplayName = loadout.DisplayName,
        Summary = loadout.Summary,
        Passive = loadout.Passive,
        UnlockProgress = loadout.UnlockProgress,
        DamageMultiplier = loadout.DamageMultiplier,
        HealthBonus = loadout.HealthBonus,
        CooldownMultiplier = loadout.CooldownMultiplier,
        Unlocked = true,
        Selected = selected,
    }
end

function MatchService:_getBotDamageMultiplier(bot: BotState): number
    local loadout = Loadouts.Loadouts[bot.LoadoutId]
    local progressBonus = math.max(bot.Progress - 1, 0) * MatchConfig.DamagePerProgress
    local gearBonus = bot.GearTier * 0.04
    return (1 + progressBonus + gearBonus + bot.BonusDamage) * loadout.DamageMultiplier
end

function MatchService:_getBotCooldownMultiplier(bot: BotState): number
    local loadout = Loadouts.Loadouts[bot.LoadoutId]
    return bot.CooldownMultiplier * loadout.CooldownMultiplier
end

function MatchService:_getBotMaxHealth(bot: BotState): number
    local loadout = Loadouts.Loadouts[bot.LoadoutId]
    local progressBonus = math.floor(math.max(bot.Progress - 1, 0) * MatchConfig.HealthPerProgress)
    local gearBonus = bot.GearTier * 6
    return MatchConfig.BaseHealth
        + progressBonus
        + gearBonus
        + bot.BonusHealth
        + loadout.HealthBonus
end

function MatchService:_getBotUnlockedSlots(bot: BotState): { string }
    local loadout = Loadouts.Loadouts[bot.LoadoutId]
    local unlocked = { "Primary", "Secondary" }
    if
        bot.UltimateUnlocked
        or bot.Progress >= Elements.Elements[loadout.Element].Abilities.Ultimate.UnlockProgress
    then
        table.insert(unlocked, "Ultimate")
    end
    return unlocked
end

function MatchService:_createBotOpponent(humanPlayer: Player): BotState
    local humanProfile = self.Progression:getProfile(humanPlayer)
    local elementName = Elements.ElementOrder[self.Rng:NextInteger(1, #Elements.ElementOrder)]
    local loadoutId = Loadouts.DefaultLoadoutByElement[elementName]
    local progress = math.max(1, humanProfile.Progress + 0.5)
    local bot: BotState = {
        Name = "Computer",
        UserId = -1,
        Element = elementName,
        LoadoutId = loadoutId,
        Progress = progress,
        GearTier = math.max(0, math.floor(humanProfile.Progress - 1)),
        BonusDamage = 0,
        BonusHealth = 6,
        CooldownMultiplier = 0.94,
        UltimateUnlocked = progress
            >= Elements.Elements[elementName].Abilities.Ultimate.UnlockProgress,
        Rewards = {},
        CurrentHealth = 0,
        MaxHealth = 0,
        Shield = 0,
        Position = self.Arena and self.Arena.RightSpawn.Position + Vector3.new(0, 4, 0)
            or Vector3.zero,
        Cooldowns = {},
        SpeedBonusUntil = 0,
        SpeedBonusValue = 0,
        SlowUntil = 0,
        SlowPenalty = 0,
        ActionToken = 0,
        SelectedElement = true,
    }
    bot.MaxHealth = self:_getBotMaxHealth(bot)
    bot.CurrentHealth = bot.MaxHealth
    return bot
end

function MatchService:_getCharacterAndHumanoid(player: Player): (Model?, Humanoid?, BasePart?)
    local character = player.Character
    if character == nil then
        return nil, nil, nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if humanoid and root and root:IsA("BasePart") then
        return character, humanoid, root
    end

    return character, nil, nil
end

function MatchService:_loadCharacterAtSpawn(
    player: Player,
    spawnLocation: SpawnLocation
): (Humanoid?, BasePart?)
    local _, currentHumanoid, currentRoot = self:_getCharacterAndHumanoid(player)
    if currentHumanoid == nil or currentHumanoid.Health <= 0 or currentRoot == nil then
        player:LoadCharacter()
        local character = player.Character or player.CharacterAdded:Wait()
        local humanoid = character:WaitForChild("Humanoid", 5)
        local root = character:WaitForChild("HumanoidRootPart", 5)
        if humanoid and root and root:IsA("BasePart") then
            currentHumanoid = humanoid :: Humanoid
            currentRoot = root
        else
            return nil, nil
        end
    end

    local fighterState = self:_ensureFighterState(player)
    fighterState.Shield = 0
    fighterState.ShieldToken += 1

    currentRoot.CFrame = spawnLocation.CFrame + Vector3.new(0, 4, 0)
    currentHumanoid.MaxHealth = self.Progression:getMaxHealth(player)
    currentHumanoid.Health = currentHumanoid.MaxHealth
    currentHumanoid.WalkSpeed = MatchConfig.WalkSpeed
    currentHumanoid.JumpPower = MatchConfig.JumpPower
    return currentHumanoid, currentRoot
end

function MatchService:_startRound(matchId: number)
    if not self:_isCurrentMatch(matchId) then
        return
    end

    local match = self.CurrentMatch :: MatchData
    if self.Arena == nil then
        return
    end
    local bot = match.Bot

    match.Phase = "Round"
    match.RoundNumber += 1
    match.Message = ("Runde %d startet."):format(match.RoundNumber)
    match.LastRoundWinnerUserId = nil
    match.ResultReason = nil
    match.RoundEndsAt = os.clock() + MatchConfig.RoundDuration

    for _, player in ipairs(match.Players) do
        self:_disconnectRoundConnections(player)
    end

    if bot then
        bot.ActionToken += 1
        bot.Cooldowns = {}
        bot.Shield = 0
        bot.SpeedBonusUntil = 0
        bot.SpeedBonusValue = 0
        bot.SlowUntil = 0
        bot.SlowPenalty = 0
        bot.Position = self.Arena.RightSpawn.Position + Vector3.new(0, 4, 0)
        bot.CurrentHealth = bot.MaxHealth
    end

    local leftPlayer = match.Players[1]
    local leftHumanoid = self:_loadCharacterAtSpawn(leftPlayer, self.Arena.LeftSpawn)
    local rightHumanoid: Humanoid? = nil
    if bot == nil then
        local rightPlayer = match.Players[2]
        rightHumanoid = self:_loadCharacterAtSpawn(rightPlayer, self.Arena.RightSpawn)
    end
    if leftHumanoid == nil or (bot == nil and rightHumanoid == nil) then
        match.Message = "Spieler konnten nicht sauber gespawnt werden. Match wird abgebrochen."
        self:_broadcastState()
        self.CurrentMatch = nil
        self:_tryStartMatch()
        return
    end

    self:_wireRoundPlayer(matchId, leftPlayer)
    if bot == nil then
        local rightPlayer = match.Players[2]
        self:_wireRoundPlayer(matchId, rightPlayer)
    else
        self:_startBotBrain(matchId)
    end
    self:_broadcastState()

    task.delay(MatchConfig.RoundDuration, function()
        if self:_isCurrentMatch(matchId, "Round") then
            self:_resolveTimeoutRound(matchId)
        end
    end)
end

function MatchService:_wireRoundPlayer(matchId: number, player: Player)
    local fighterState = self:_ensureFighterState(player)
    local _, humanoid = self:_getCharacterAndHumanoid(player)
    if humanoid == nil then
        return
    end

    table.insert(
        fighterState.RoundConnections,
        humanoid.Died:Connect(function()
            self:_onHumanoidDied(matchId, player)
        end)
    )
    table.insert(
        fighterState.RoundConnections,
        humanoid.HealthChanged:Connect(function()
            self:_broadcastState()
        end)
    )
end

function MatchService:_startBotBrain(matchId: number)
    local match = self.CurrentMatch
    if match == nil or match.Bot == nil then
        return
    end

    local bot = match.Bot
    bot.ActionToken += 1
    local actionToken = bot.ActionToken

    task.spawn(function()
        while self:_isCurrentMatch(matchId, "Round") do
            local currentMatch = self.CurrentMatch
            if currentMatch == nil or currentMatch.Bot ~= bot then
                return
            end
            if actionToken ~= bot.ActionToken then
                return
            end
            if bot.CurrentHealth <= 0 then
                return
            end

            self:_botTakeAction(matchId, bot)
            task.wait(self:_getBotActionDelay(bot))
        end
    end)
end

function MatchService:_getBotActionDelay(bot: BotState): number
    local delay = MatchConfig.BotActionInterval
    local now = os.clock()
    if bot.SpeedBonusUntil > now then
        delay = math.max(0.5, delay - bot.SpeedBonusValue * 0.05)
    end
    if bot.SlowUntil > now then
        delay += bot.SlowPenalty * 0.12
    end
    return delay
end

function MatchService:_botTakeAction(matchId: number, bot: BotState)
    local match = self.CurrentMatch
    if match == nil then
        return
    end

    local humanPlayer = match.Players[1]
    local _, humanHumanoid, humanRoot = self:_getCharacterAndHumanoid(humanPlayer)
    if humanHumanoid == nil or humanRoot == nil then
        return
    end

    local distance = (humanRoot.Position - bot.Position).Magnitude
    local readySlots = {}
    for _, slotName in ipairs({ "Ultimate", "Secondary", "Primary" }) do
        local ability = Elements.Elements[bot.Element].Abilities[slotName]
        local readyAt = bot.Cooldowns[slotName] or 0
        if readyAt <= os.clock() then
            if
                ability.Action == "Shield"
                or ability.Action == "Heal"
                or ability.Action == "Dash"
                or distance <= ability.Range
            then
                table.insert(readySlots, slotName)
            end
        end
    end

    if #readySlots == 0 then
        return
    end

    local slotName = readySlots[self.Rng:NextInteger(1, #readySlots)]
    local ability = Elements.Elements[bot.Element].Abilities[slotName]
    bot.Cooldowns[slotName] = os.clock() + ability.Cooldown * self:_getBotCooldownMultiplier(bot)
    self:_botApplyAbility(matchId, bot, humanPlayer, ability, distance)
    self:_broadcastState()
end

function MatchService:_getOpponent(player: Player): any?
    local match = self.CurrentMatch
    if match == nil then
        return nil
    end

    if match.Bot ~= nil then
        return match.Bot
    end

    for _, contender in ipairs(match.Players) do
        if contender ~= player then
            return contender
        end
    end

    return nil
end

function MatchService:_getCurrentHealth(player: Player): number
    local _, humanoid = self:_getCharacterAndHumanoid(player)
    if humanoid == nil then
        return 0
    end
    return humanoid.Health
end

function MatchService:_getBotCurrentHealth(bot: BotState): number
    return bot.CurrentHealth
end

function MatchService:_isBotCombatant(combatant: any): boolean
    return typeof(combatant) == "table"
end

function MatchService:_getCombatantUserId(combatant: any): number
    if typeof(combatant) == "Instance" then
        return (combatant :: Player).UserId
    end
    return combatant.UserId
end

function MatchService:_getCombatantName(combatant: any): string
    if typeof(combatant) == "Instance" then
        return (combatant :: Player).Name
    end
    return combatant.Name
end

function MatchService:_resolveTimeoutRound(matchId: number)
    if not self:_isCurrentMatch(matchId, "Round") then
        return
    end

    local match = self.CurrentMatch :: MatchData
    local leftPlayer = match.Players[1]
    local leftHealth = self:_getCurrentHealth(leftPlayer)
    local rightHealth = if match.Bot
        then self:_getBotCurrentHealth(match.Bot)
        else self:_getCurrentHealth(match.Players[2])

    local winner = leftPlayer
    local loser: any = if match.Bot then match.Bot else match.Players[2]
    local rightPlayerWins = rightHealth > leftHealth
        or (rightHealth == leftHealth and self.Rng:NextInteger(1, 2) == 2)
    if rightPlayerWins then
        winner = if match.Bot then match.Bot else match.Players[2]
        loser = leftPlayer
    end

    self:_resolveRound(matchId, winner, loser, "Zeit abgelaufen")
end

function MatchService:_onHumanoidDied(matchId: number, player: Player)
    if not self:_isCurrentMatch(matchId, "Round") then
        return
    end

    local opponent = self:_getOpponent(player)
    if opponent == nil then
        return
    end

    self:_resolveRound(matchId, opponent, player, "K.O.")
end

function MatchService:_resolveRound(matchId: number, winner: any, loser: any, reason: string)
    if not self:_isCurrentMatch(matchId, "Round") then
        return
    end

    local match = self.CurrentMatch :: MatchData
    for _, player in ipairs(match.Players) do
        self:_disconnectRoundConnections(player)
    end
    if match.Bot then
        match.Bot.ActionToken += 1
    end

    match.Phase = "RoundResult"
    local winnerUserId = self:_getCombatantUserId(winner)
    match.Scores[winnerUserId] = (match.Scores[winnerUserId] or 0) + 1
    match.LastRoundWinnerUserId = winnerUserId
    match.ResultReason = reason
    match.Message = ("%s gewinnt Runde %d durch %s."):format(
        self:_getCombatantName(winner),
        match.RoundNumber,
        reason
    )

    if (match.Scores[winnerUserId] or 0) >= MatchConfig.RoundsToWin then
        self:_finishMatch(matchId, winner, loser, reason)
        return
    end

    self:_broadcastState()
    task.delay(MatchConfig.RoundResetDelay, function()
        if self:_isCurrentMatch(matchId, "RoundResult") then
            self:_startRound(matchId)
        end
    end)
end

function MatchService:_finishMatch(matchId: number, winner: any, loser: any, reason: string)
    if not self:_isCurrentMatch(matchId) then
        return
    end

    local match = self.CurrentMatch :: MatchData
    local rewardOutcome
    if match.Bot then
        local humanPlayer = match.Players[1]
        local humanWon = self:_getCombatantUserId(winner) ~= match.Bot.UserId
        rewardOutcome = self.Progression:awardSoloMatch(humanPlayer, humanWon)
    else
        rewardOutcome = self.Progression:awardMatch(winner, loser)
    end

    match.Phase = "MatchResult"
    match.WinnerUserId = self:_getCombatantUserId(winner)
    match.LoserUserId = self:_getCombatantUserId(loser)
    match.ResultReason = reason
    if rewardOutcome and rewardOutcome.Reward then
        match.Reward = {
            RecipientUserId = rewardOutcome.RewardRecipient.UserId,
            RecipientName = rewardOutcome.RewardRecipient.Name,
            Id = rewardOutcome.Reward.Id,
            Name = rewardOutcome.Reward.Name,
            Description = rewardOutcome.Reward.Description,
        }
    end
    match.Message = ("%s gewinnt das Best of 5."):format(self:_getCombatantName(winner))
    self:_broadcastState()

    task.delay(MatchConfig.MatchResultDuration, function()
        if self:_isCurrentMatch(matchId, "MatchResult") then
            self.CurrentMatch = nil
            self:_broadcastState()
            self:_tryStartMatch()
        end
    end)
end

function MatchService:_handlePlayerRemoving(player: Player)
    local match = self.CurrentMatch
    if match == nil then
        return
    end

    if table.find(match.Players, player) == nil then
        return
    end

    local opponent = self:_getOpponent(player)
    if opponent ~= nil and match.Phase ~= "MatchResult" then
        self:_finishMatch(match.Id, opponent, player, "Aufgabe")
    else
        self.CurrentMatch = nil
    end
end

function MatchService:_handleCast(player: Player, slotName: string)
    if not isAbilitySlot(slotName) then
        return
    end

    local match = self.CurrentMatch
    if match == nil or match.Phase ~= "Round" then
        return
    end
    if table.find(match.Players, player) == nil then
        return
    end
    if not self.Progression:isAbilityUnlocked(player, slotName) then
        return
    end

    local fighterState = self:_ensureFighterState(player)
    local readyAt = fighterState.Cooldowns[slotName] or 0
    local now = os.clock()
    if readyAt > now then
        return
    end

    local elementName = self.Progression:getElement(player) :: ElementName
    local ability = Elements.Elements[elementName].Abilities[slotName]
    local cooldown = ability.Cooldown * self.Progression:getCooldownMultiplier(player)
    fighterState.Cooldowns[slotName] = now + cooldown

    local opponent = self:_getOpponent(player)
    if opponent == nil then
        return
    end

    if typeof(opponent) == "Instance" then
        self:_applyAbility(match.Id, match.RoundNumber, player, opponent, ability)
    else
        self:_botApplyAbility(match.Id, match.RoundNumber, player, opponent, ability)
    end
    self:_broadcastState()
end

function MatchService:_applyAbility(
    matchId: number,
    roundNumber: number,
    player: Player,
    opponent: Player,
    ability: any
)
    local _, humanoid, root = self:_getCharacterAndHumanoid(player)
    local _, opponentHumanoid, opponentRoot = self:_getCharacterAndHumanoid(opponent)
    if humanoid == nil or root == nil or opponentHumanoid == nil or opponentRoot == nil then
        return
    end

    local distance = (root.Position - opponentRoot.Position).Magnitude
    local scaledDamage =
        math.floor(ability.BaseDamage * self.Progression:getDamageMultiplier(player) + 0.5)

    if ability.Action == "Shield" then
        self:_applyShield(player, ability.Shield or 0, ability.Duration or 3)
        return
    end

    if ability.Action == "Heal" then
        self:_healPlayer(player, ability.Heal or 0)
        return
    end

    if ability.Action == "Dash" then
        root.CFrame += root.CFrame.LookVector * (ability.DashDistance or 20)
        if ability.WalkSpeedBonus then
            self:_applySpeedBonus(player, ability.WalkSpeedBonus, ability.Duration or 1.5)
        end
        if ability.BaseDamage > 0 and distance <= 20 then
            self:_dealDamage(player, opponent, scaledDamage)
        end
        if ability.BurnDamage and ability.BurnTicks then
            self:_applyBurn(
                matchId,
                roundNumber,
                player,
                opponent,
                ability.BurnDamage,
                ability.BurnTicks
            )
        end
        return
    end

    if distance > ability.Range then
        return
    end

    if scaledDamage > 0 then
        self:_dealDamage(player, opponent, scaledDamage)
        if ability.BurnDamage and ability.BurnTicks then
            self:_applyBurn(
                matchId,
                roundNumber,
                player,
                opponent,
                ability.BurnDamage,
                ability.BurnTicks
            )
        end
        if ability.SlowDuration then
            self:_applySlow(opponent, 6, ability.SlowDuration)
        end
    end

    if ability.Heal then
        self:_healPlayer(player, ability.Heal)
    end
end

function MatchService:_applyAbilityToBot(
    matchId: number,
    roundNumber: number,
    player: Player,
    bot: BotState,
    ability: any
)
    local _, humanoid, root = self:_getCharacterAndHumanoid(player)
    if humanoid == nil or root == nil then
        return
    end

    local distance = (root.Position - bot.Position).Magnitude
    local scaledDamage =
        math.floor(ability.BaseDamage * self.Progression:getDamageMultiplier(player) + 0.5)

    if ability.Action == "Shield" then
        self:_applyShieldToBot(bot, ability.Shield or 0, ability.Duration or 3)
        return
    end

    if ability.Action == "Heal" then
        self:_healPlayer(player, ability.Heal or 0)
        return
    end

    if ability.Action == "Dash" then
        local direction = bot.Position - root.Position
        if direction.Magnitude > 0 then
            bot.Position += direction.Unit * (ability.DashDistance or 20)
        end
        if ability.WalkSpeedBonus then
            self:_applySpeedBonus(player, ability.WalkSpeedBonus, ability.Duration or 1.5)
        end
        if ability.BaseDamage > 0 and distance <= 20 then
            self:_dealDamageToBot(matchId, player, bot, scaledDamage)
        end
        if ability.BurnDamage and ability.BurnTicks then
            self:_applyBurnToBot(
                matchId,
                roundNumber,
                player,
                bot,
                ability.BurnDamage,
                ability.BurnTicks
            )
        end
        return
    end

    if distance > ability.Range then
        return
    end

    if scaledDamage > 0 then
        self:_dealDamageToBot(matchId, player, bot, scaledDamage)
        if ability.BurnDamage and ability.BurnTicks then
            self:_applyBurnToBot(
                matchId,
                roundNumber,
                player,
                bot,
                ability.BurnDamage,
                ability.BurnTicks
            )
        end
        if ability.SlowDuration then
            self:_applySlowToBot(bot, 6, ability.SlowDuration)
        end
    end

    if ability.Heal then
        self:_healPlayer(player, ability.Heal)
    end
end

function MatchService:_applyShieldToBot(bot: BotState, amount: number, duration: number)
    bot.Shield += amount
    local token = bot.ActionToken
    task.delay(duration, function()
        if bot.ActionToken == token then
            bot.Shield = 0
            self:_broadcastState()
        end
    end)
end

function MatchService:_applySpeedBonusToBot(bot: BotState, bonus: number, duration: number)
    bot.SpeedBonusUntil = math.max(bot.SpeedBonusUntil, os.clock() + duration)
    bot.SpeedBonusValue = math.max(bot.SpeedBonusValue, bonus)
end

function MatchService:_applySlowToBot(bot: BotState, penalty: number, duration: number)
    bot.SlowUntil = math.max(bot.SlowUntil, os.clock() + duration)
    bot.SlowPenalty = math.max(bot.SlowPenalty, penalty)
end

function MatchService:_healBot(bot: BotState, amount: number)
    bot.CurrentHealth = math.min(bot.MaxHealth, bot.CurrentHealth + amount)
end

function MatchService:_dealDamageToBot(
    matchId: number,
    attacker: Player,
    bot: BotState,
    amount: number
)
    local remainingDamage = amount
    if bot.Shield > 0 then
        local absorbed = math.min(bot.Shield, remainingDamage)
        bot.Shield -= absorbed
        remainingDamage -= absorbed
    end

    if remainingDamage <= 0 then
        return
    end

    bot.CurrentHealth = math.max(0, bot.CurrentHealth - remainingDamage)
    if bot.CurrentHealth <= 0 then
        self:_resolveRound(matchId, attacker, bot, "K.O.")
    end
end

function MatchService:_applyBurnToBot(
    matchId: number,
    roundNumber: number,
    attacker: Player,
    bot: BotState,
    tickDamage: number,
    burnTicks: number
)
    task.spawn(function()
        for _ = 1, burnTicks do
            task.wait(1)
            if not self:_isCurrentMatch(matchId, "Round") then
                return
            end
            local currentMatch = self.CurrentMatch
            if
                currentMatch == nil
                or currentMatch.RoundNumber ~= roundNumber
                or currentMatch.Bot ~= bot
            then
                return
            end
            self:_dealDamageToBot(matchId, attacker, bot, tickDamage)
            self:_broadcastState()
        end
    end)
end

function MatchService:_botTakeAction(matchId: number, bot: BotState)
    local match = self.CurrentMatch
    if match == nil then
        return
    end

    local humanPlayer = match.Players[1]
    local _, humanHumanoid, humanRoot = self:_getCharacterAndHumanoid(humanPlayer)
    if humanHumanoid == nil or humanRoot == nil then
        return
    end

    local distance = (humanRoot.Position - bot.Position).Magnitude
    local readySlots = {}
    for _, slotName in ipairs({ "Ultimate", "Secondary", "Primary" }) do
        local ability = Elements.Elements[bot.Element].Abilities[slotName]
        local readyAt = bot.Cooldowns[slotName] or 0
        if readyAt <= os.clock() then
            if
                ability.Action == "Shield"
                or ability.Action == "Heal"
                or ability.Action == "Dash"
                or distance <= ability.Range
            then
                table.insert(readySlots, slotName)
            end
        end
    end

    if #readySlots == 0 then
        return
    end

    local slotName = readySlots[self.Rng:NextInteger(1, #readySlots)]
    local ability = Elements.Elements[bot.Element].Abilities[slotName]
    bot.Cooldowns[slotName] = os.clock() + ability.Cooldown * self:_getBotCooldownMultiplier(bot)
    self:_botApplyAbility(matchId, match.RoundNumber, bot, humanPlayer, ability, distance)
    self:_broadcastState()
end

function MatchService:_botApplyAbility(
    matchId: number,
    roundNumber: number,
    bot: BotState,
    targetPlayer: Player,
    ability: any,
    distance: number
)
    local _, targetHumanoid, targetRoot = self:_getCharacterAndHumanoid(targetPlayer)
    if targetHumanoid == nil or targetRoot == nil then
        return
    end

    local scaledDamage = math.floor(ability.BaseDamage * self:_getBotDamageMultiplier(bot) + 0.5)

    if ability.Action == "Shield" then
        self:_applyShieldToBot(bot, ability.Shield or 0, ability.Duration or 3)
        return
    end

    if ability.Action == "Heal" then
        self:_healBot(bot, ability.Heal or 0)
        return
    end

    if ability.Action == "Dash" then
        local direction = targetRoot.Position - bot.Position
        if direction.Magnitude > 0 then
            bot.Position += direction.Unit * (ability.DashDistance or 20)
        end
        if ability.WalkSpeedBonus then
            self:_applySpeedBonusToBot(bot, ability.WalkSpeedBonus, ability.Duration or 1.5)
        end
        if ability.BaseDamage > 0 and distance <= 20 then
            self:_dealDamageToHuman(matchId, bot, targetPlayer, scaledDamage)
        end
        if ability.BurnDamage and ability.BurnTicks then
            self:_applyBurn(
                matchId,
                roundNumber,
                bot,
                targetPlayer,
                ability.BurnDamage,
                ability.BurnTicks
            )
        end
        return
    end

    if distance > ability.Range then
        return
    end

    if scaledDamage > 0 then
        self:_dealDamageToHuman(matchId, bot, targetPlayer, scaledDamage)
        if ability.BurnDamage and ability.BurnTicks then
            self:_applyBurn(
                matchId,
                roundNumber,
                bot,
                targetPlayer,
                ability.BurnDamage,
                ability.BurnTicks
            )
        end
        if ability.SlowDuration then
            self:_applySlow(targetPlayer, 6, ability.SlowDuration)
        end
    end

    if ability.Heal then
        self:_healBot(bot, ability.Heal)
    end
end

function MatchService:_serializeBotState(bot: BotState)
    local loadout = Loadouts.Loadouts[bot.LoadoutId]
    return {
        UserId = bot.UserId,
        Name = bot.Name,
        Element = bot.Element,
        HasSelectedElement = bot.SelectedElement,
        Progress = bot.Progress,
        DisplayLevel = math.floor(bot.Progress),
        GearTier = bot.GearTier,
        LoadoutId = loadout.Id,
        CurrentLoadout = self:_serializeLoadout(bot.LoadoutId, true),
        LoadoutChoices = {},
        Rewards = table.clone(bot.Rewards),
        UnlockedSlots = self:_getBotUnlockedSlots(bot),
        MaxHealth = bot.MaxHealth,
        CurrentHealth = math.floor(bot.CurrentHealth + 0.5),
        DamageMultiplier = roundTenth(self:_getBotDamageMultiplier(bot)),
        CooldownMultiplier = roundTenth(self:_getBotCooldownMultiplier(bot)),
        Shield = bot.Shield,
        Score = if self.CurrentMatch then self.CurrentMatch.Scores[bot.UserId] or 0 else 0,
        IsViewer = false,
        IsBot = true,
    }
end

function MatchService:_applyShield(player: Player, amount: number, duration: number)
    local fighterState = self:_ensureFighterState(player)
    fighterState.ShieldToken += 1
    fighterState.Shield = amount
    local token = fighterState.ShieldToken
    task.delay(duration, function()
        local currentState = self:_ensureFighterState(player)
        if currentState.ShieldToken == token then
            currentState.Shield = 0
            self:_broadcastState()
        end
    end)
end

function MatchService:_healPlayer(player: Player, amount: number)
    local _, humanoid = self:_getCharacterAndHumanoid(player)
    if humanoid == nil then
        return
    end
    humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
end

function MatchService:_refreshMovement(player: Player)
    local fighterState = self:_ensureFighterState(player)
    local _, humanoid = self:_getCharacterAndHumanoid(player)
    if humanoid == nil then
        return
    end

    local now = os.clock()
    local walkSpeed = MatchConfig.WalkSpeed
    if fighterState.SpeedBonusUntil > now then
        walkSpeed += fighterState.SpeedBonusValue
    else
        fighterState.SpeedBonusUntil = 0
        fighterState.SpeedBonusValue = 0
    end
    if fighterState.SlowUntil > now then
        walkSpeed = math.max(10, walkSpeed - fighterState.SlowPenalty)
    else
        fighterState.SlowUntil = 0
        fighterState.SlowPenalty = 0
    end

    humanoid.WalkSpeed = walkSpeed
    humanoid.JumpPower = MatchConfig.JumpPower
end

function MatchService:_applySpeedBonus(player: Player, bonus: number, duration: number)
    local fighterState = self:_ensureFighterState(player)
    fighterState.SpeedBonusUntil = math.max(fighterState.SpeedBonusUntil, os.clock() + duration)
    fighterState.SpeedBonusValue = math.max(fighterState.SpeedBonusValue, bonus)
    self:_refreshMovement(player)
    task.delay(duration, function()
        self:_refreshMovement(player)
        self:_broadcastState()
    end)
end

function MatchService:_applySlow(player: Player, penalty: number, duration: number)
    local fighterState = self:_ensureFighterState(player)
    fighterState.SlowUntil = math.max(fighterState.SlowUntil, os.clock() + duration)
    fighterState.SlowPenalty = math.max(fighterState.SlowPenalty, penalty)
    self:_refreshMovement(player)
    task.delay(duration, function()
        self:_refreshMovement(player)
        self:_broadcastState()
    end)
end

function MatchService:_applyBurn(
    matchId: number,
    roundNumber: number,
    attacker: any,
    target: Player,
    tickDamage: number,
    burnTicks: number
)
    task.spawn(function()
        for _ = 1, burnTicks do
            task.wait(1)
            if not self:_isCurrentMatch(matchId, "Round") then
                return
            end
            local match = self.CurrentMatch :: MatchData
            if match.RoundNumber ~= roundNumber then
                return
            end
            self:_dealDamage(attacker, target, tickDamage)
            self:_broadcastState()
        end
    end)
end

function MatchService:_dealDamageToHuman(
    _matchId: number,
    attacker: any,
    targetPlayer: Player,
    amount: number
)
    self:_dealDamage(attacker, targetPlayer, amount)
end

function MatchService:_dealDamage(_attacker: any, target: Player, amount: number)
    local targetState = self:_ensureFighterState(target)
    local remainingDamage = amount
    if targetState.Shield > 0 then
        local absorbed = math.min(targetState.Shield, remainingDamage)
        targetState.Shield -= absorbed
        remainingDamage -= absorbed
    end

    if remainingDamage <= 0 then
        return
    end

    local _, humanoid = self:_getCharacterAndHumanoid(target)
    if humanoid == nil then
        return
    end

    humanoid:TakeDamage(remainingDamage)
end

function MatchService:_serializeCooldowns(player: Player)
    local fighterState = self:_ensureFighterState(player)
    local now = os.clock()
    return {
        Primary = roundTenth(math.max(0, (fighterState.Cooldowns.Primary or 0) - now)),
        Secondary = roundTenth(math.max(0, (fighterState.Cooldowns.Secondary or 0) - now)),
        Ultimate = roundTenth(math.max(0, (fighterState.Cooldowns.Ultimate or 0) - now)),
    }
end

function MatchService:_serializeProfileForState(viewer: Player, player: Player)
    local profile = self.Progression:serializeProfile(player)
    local fighterState = self:_ensureFighterState(player)
    profile.MaxHealth = self.Progression:getMaxHealth(player)
    profile.CurrentHealth = math.floor(self:_getCurrentHealth(player) + 0.5)
    profile.DamageMultiplier = roundTenth(self.Progression:getDamageMultiplier(player))
    profile.CooldownMultiplier = roundTenth(self.Progression:getCooldownMultiplier(player))
    profile.Shield = fighterState.Shield
    profile.Score = if self.CurrentMatch then self.CurrentMatch.Scores[player.UserId] or 0 else 0
    profile.IsViewer = player == viewer
    return profile
end

function MatchService:_serializeState(viewer: Player)
    local match = self.CurrentMatch
    local playersSnapshot = {}
    if match then
        for _, player in ipairs(match.Players) do
            table.insert(playersSnapshot, self:_serializeProfileForState(viewer, player))
        end
        if match.Bot then
            table.insert(playersSnapshot, self:_serializeBotState(match.Bot))
        end
    end

    local countdown = 0
    if match then
        if match.Phase == "Selection" then
            countdown = math.max(0, math.ceil(match.SelectionEndsAt - os.clock()))
        elseif match.Phase == "Round" then
            countdown = math.max(0, math.ceil(match.RoundEndsAt - os.clock()))
        end
    end

    return {
        Status = if self.Arena == nil
            then "BuildingArena"
            elseif match == nil then "Waiting"
            else match.Phase,
        ArenaReady = self.Arena ~= nil,
        QueueCount = #self:_getAvailablePlayers(),
        BestOf = MatchConfig.BestOf,
        RoundsToWin = MatchConfig.RoundsToWin,
        Countdown = countdown,
        Message = if match
            then match.Message
            elseif
                #self:_getAvailablePlayers() == 1
            then "Warte auf einen zweiten Spieler oder Computergegner."
            else "Warte auf zwei Spieler.",
        Mode = if match then match.Mode else nil,
        Viewer = self:_serializeProfileForState(viewer, viewer),
        Cooldowns = self:_serializeCooldowns(viewer),
        Match = if match == nil
            then nil
            else {
                RoundNumber = match.RoundNumber,
                Players = playersSnapshot,
                Bot = if match.Bot then self:_serializeBotState(match.Bot) else nil,
                Mode = match.Mode,
                WinnerUserId = match.WinnerUserId,
                LoserUserId = match.LoserUserId,
                LastRoundWinnerUserId = match.LastRoundWinnerUserId,
                Reward = match.Reward,
                ResultReason = match.ResultReason,
                Phase = match.Phase,
            },
    }
end

function MatchService:_broadcastState()
    for _, player in ipairs(Players:GetPlayers()) do
        self.StateEvent:FireClient(player, self:_serializeState(player))
    end
end

return MatchService
