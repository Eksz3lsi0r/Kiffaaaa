--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage.Shared)
local MatchConfig = Shared.MatchConfig
local Elements = Shared.Elements
local Loadouts = Shared.Loadouts

type ElementName = "Earth" | "Air" | "Fire" | "Water"
type LoadoutId = string

type LoadoutDefinition = {
    Id: LoadoutId,
    Element: ElementName,
    DisplayName: string,
    Summary: string,
    Passive: string,
    UnlockProgress: number,
    DamageMultiplier: number,
    HealthBonus: number,
    CooldownMultiplier: number,
}

type Profile = {
    Progress: number,
    Element: ElementName,
    LoadoutId: LoadoutId,
    ElementChosen: boolean,
    GearTier: number,
    BonusDamage: number,
    BonusHealth: number,
    CooldownMultiplier: number,
    UltimateUnlocked: boolean,
    Rewards: { string },
}

local ProgressionService = {}
ProgressionService.__index = ProgressionService

function ProgressionService.new()
    local self = setmetatable({
        _profiles = {} :: { [Player]: Profile },
        _rng = Random.new(),
    }, ProgressionService)
    return self
end

local function serializeLoadout(loadout: LoadoutDefinition, unlocked: boolean, selected: boolean)
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
        Unlocked = unlocked,
        Selected = selected,
    }
end

function ProgressionService:_getDefaultLoadoutId(elementName: ElementName): LoadoutId
    return Loadouts.DefaultLoadoutByElement[elementName]
end

function ProgressionService:_getProfileLoadout(player: Player): LoadoutDefinition
    local profile = self:_ensureProfile(player)
    local loadout = Loadouts.Loadouts[profile.LoadoutId]
    if loadout == nil or loadout.Element ~= profile.Element then
        local defaultLoadoutId = self:_getDefaultLoadoutId(profile.Element)
        profile.LoadoutId = defaultLoadoutId
        loadout = Loadouts.Loadouts[defaultLoadoutId]
    end
    return loadout
end

function ProgressionService:_getLoadoutStates(player: Player)
    local profile = self:_ensureProfile(player)
    local states = {}
    for _, loadoutId in ipairs(Loadouts.LoadoutOrder[profile.Element]) do
        local loadout = Loadouts.Loadouts[loadoutId]
        local unlocked = math.floor(profile.Progress) >= loadout.UnlockProgress
        table.insert(states, serializeLoadout(loadout, unlocked, profile.LoadoutId == loadout.Id))
    end
    return states
end

function ProgressionService:_ensureProfile(player: Player): Profile
    local profiles = (self :: any)._profiles :: { [Player]: Profile }
    local profile = profiles[player]
    if profile then
        return profile
    end

    profile = {
        Progress = 1,
        Element = MatchConfig.DefaultElement,
        LoadoutId = self:_getDefaultLoadoutId(MatchConfig.DefaultElement),
        ElementChosen = false,
        GearTier = 0,
        BonusDamage = 0,
        BonusHealth = 0,
        CooldownMultiplier = 1,
        UltimateUnlocked = false,
        Rewards = {},
    }
    profiles[player] = profile
    return profile
end

function ProgressionService:removePlayer(player: Player)
    local profiles = (self :: any)._profiles :: { [Player]: Profile }
    profiles[player] = nil
end

function ProgressionService:getProfile(player: Player): Profile
    return self:_ensureProfile(player)
end

function ProgressionService:getElement(player: Player): ElementName
    return self:_ensureProfile(player).Element
end

function ProgressionService:setElement(player: Player, elementName: ElementName)
    local profile = self:_ensureProfile(player)
    profile.Element = elementName
    profile.ElementChosen = true
    local defaultLoadoutId = self:_getDefaultLoadoutId(elementName)
    local currentLoadout = Loadouts.Loadouts[profile.LoadoutId]
    if currentLoadout == nil or currentLoadout.Element ~= elementName then
        profile.LoadoutId = defaultLoadoutId
    end
end

function ProgressionService:isLoadoutUnlocked(player: Player, loadoutId: LoadoutId): boolean
    local profile = self:_ensureProfile(player)
    local loadout = Loadouts.Loadouts[loadoutId]
    if loadout == nil or loadout.Element ~= profile.Element then
        return false
    end
    return math.floor(profile.Progress) >= loadout.UnlockProgress
end

function ProgressionService:setLoadout(player: Player, loadoutId: LoadoutId): boolean
    local profile = self:_ensureProfile(player)
    if self:isLoadoutUnlocked(player, loadoutId) then
        profile.LoadoutId = loadoutId
        return true
    end

    profile.LoadoutId = self:_getDefaultLoadoutId(profile.Element)
    return false
end

function ProgressionService:getLoadout(player: Player): LoadoutDefinition
    return self:_getProfileLoadout(player)
end

function ProgressionService:getLoadoutStates(player: Player)
    return self:_getLoadoutStates(player)
end

function ProgressionService:getDamageMultiplier(player: Player): number
    local profile = self:_ensureProfile(player)
    local progressBonus = math.max(profile.Progress - 1, 0) * MatchConfig.DamagePerProgress
    local gearBonus = profile.GearTier * 0.04
    local loadout = self:_getProfileLoadout(player)
    return (1 + progressBonus + gearBonus + profile.BonusDamage) * loadout.DamageMultiplier
end

function ProgressionService:getMaxHealth(player: Player): number
    local profile = self:_ensureProfile(player)
    local progressBonus =
        math.floor(math.max(profile.Progress - 1, 0) * MatchConfig.HealthPerProgress)
    local gearBonus = profile.GearTier * 6
    local loadout = self:_getProfileLoadout(player)
    return MatchConfig.BaseHealth
        + progressBonus
        + gearBonus
        + profile.BonusHealth
        + loadout.HealthBonus
end

function ProgressionService:getCooldownMultiplier(player: Player): number
    local profile = self:_ensureProfile(player)
    local loadout = self:_getProfileLoadout(player)
    return profile.CooldownMultiplier * loadout.CooldownMultiplier
end

function ProgressionService:isAbilityUnlocked(player: Player, slotName: string): boolean
    local profile = self:_ensureProfile(player)
    if slotName ~= "Ultimate" then
        return true
    end

    local elementName = profile.Element
    local elementDefinition = Elements.Elements[elementName]
    local unlockProgress = elementDefinition.Abilities.Ultimate.UnlockProgress
    return profile.Progress >= unlockProgress or profile.UltimateUnlocked
end

function ProgressionService:getUnlockedSlots(player: Player): { string }
    local unlocked = { "Primary", "Secondary" }
    if self:isAbilityUnlocked(player, "Ultimate") then
        table.insert(unlocked, "Ultimate")
    end
    return unlocked
end

function ProgressionService:awardMatch(
    winner: Player,
    loser: Player
): { RewardRecipient: Player, Reward: any }
    local winnerProfile = self:_ensureProfile(winner)
    local loserProfile = self:_ensureProfile(loser)

    winnerProfile.Progress += 1
    loserProfile.Progress += 0.5

    local rewardRecipient = if ((self :: any)._rng :: Random):NextInteger(1, 2) == 1
        then winner
        else loser
    local reward = self:_grantReward(rewardRecipient)

    return {
        RewardRecipient = rewardRecipient,
        Reward = reward,
    }
end

function ProgressionService:awardSoloMatch(
    player: Player,
    won: boolean
): { RewardRecipient: Player, Reward: any }
    local profile = self:_ensureProfile(player)
    profile.Progress += if won then 1 else 0.5
    local reward = self:_grantReward(player)
    return {
        RewardRecipient = player,
        Reward = reward,
    }
end

function ProgressionService:_grantReward(player: Player)
    local profile = self:_ensureProfile(player)
    local rng = (self :: any)._rng :: Random
    local rewardId = Elements.RewardOrder[rng:NextInteger(1, #Elements.RewardOrder)]
    local rewardDefinition = Elements.RewardCatalog[rewardId]

    table.insert(profile.Rewards, rewardDefinition.Name)
    profile.BonusDamage += rewardDefinition.DamageBonus
    profile.BonusHealth += rewardDefinition.HealthBonus
    profile.CooldownMultiplier *= rewardDefinition.CooldownMultiplier
    profile.UltimateUnlocked = profile.UltimateUnlocked or rewardDefinition.UnlockUltimate
    profile.GearTier += 1

    return {
        Id = rewardDefinition.Id,
        Name = rewardDefinition.Name,
        Description = rewardDefinition.Description,
    }
end

function ProgressionService:serializeProfile(player: Player)
    local profile = self:_ensureProfile(player)
    local loadout = self:_getProfileLoadout(player)
    return {
        UserId = player.UserId,
        Name = player.Name,
        Element = profile.Element,
        HasSelectedElement = profile.ElementChosen,
        Progress = profile.Progress,
        DisplayLevel = math.floor(profile.Progress),
        GearTier = profile.GearTier,
        LoadoutId = loadout.Id,
        CurrentLoadout = serializeLoadout(loadout, true, true),
        LoadoutChoices = self:_getLoadoutStates(player),
        Rewards = table.clone(profile.Rewards),
        UnlockedSlots = self:getUnlockedSlots(player),
    }
end

function ProgressionService:serializeProfiles(players: { Player })
    local snapshot = {}
    for _, player in ipairs(players) do
        table.insert(snapshot, self:serializeProfile(player))
    end
    return snapshot
end

function ProgressionService:bootstrapExistingPlayers()
    for _, player in ipairs(Players:GetPlayers()) do
        self:_ensureProfile(player)
    end
end

return ProgressionService
