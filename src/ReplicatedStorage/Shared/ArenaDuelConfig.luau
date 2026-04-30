local ArenaDuelConfig = {}

ArenaDuelConfig.RemoteFolderName = "ArenaDuelRemotes"

ArenaDuelConfig.Remotes = {
    QueueRequest = "QueueRequest",
    ClassSelect = "ClassSelect",
    TargetSelect = "TargetSelect",
    AbilityCast = "AbilityCast",
    StateUpdate = "StateUpdate",
    SystemMessage = "SystemMessage",
}

ArenaDuelConfig.StudioAutomation = {
    AutoQueueModeAttribute = "ArenaDuelAutoQueueMode",
}

ArenaDuelConfig.PreparationSeconds = 12
ArenaDuelConfig.BotPreparationSeconds = 4
ArenaDuelConfig.FinishedReturnSeconds = 5
ArenaDuelConfig.MaxFocus = 5
ArenaDuelConfig.DRWindowSeconds = 18
ArenaDuelConfig.DRMultipliers = { 1, 0.5, 0.25, 0 }
ArenaDuelConfig.GlobalCooldownSeconds = 0.95

ArenaDuelConfig.Dampening = {
    startsAfterSeconds = 20,
    stepIntervalSeconds = 5,
    stepPercent = 4,
    maxPercent = 60,
}

ArenaDuelConfig.BotAi = {
    tickSeconds = 0.55,
    meleePreferredDistance = 7,
    rangedPreferredDistance = 26,
    strafeDistance = 9,
}

ArenaDuelConfig.BotClassRotation = {
    "Mage",
    "Priest",
    "Rogue",
    "Warrior",
}

ArenaDuelConfig.MatchModes = {
    Duel1v1 = {
        displayName = "1vs1",
        playersNeeded = 2,
    },
    Duel2v2 = {
        displayName = "2vs2",
        playersNeeded = 4,
    },
    Bot = {
        displayName = "1vsCOM",
        playersNeeded = 1,
    },
}

ArenaDuelConfig.CrowdControl = {
    Slow = "Slow",
    Stun = "Stun",
    Fear = "Fear",
    Root = "Root",
}

ArenaDuelConfig.AbilityOrder = {
    "Ability1",
    "Ability2",
    "Ability3",
    "Ability4",
}

ArenaDuelConfig.ClassOrder = {
    "Warrior",
    "Priest",
    "Mage",
    "Rogue",
}

ArenaDuelConfig.Classes = {
    Warrior = {
        displayName = "Krieger",
        maxHealth = 170,
        baseWalkSpeed = 16,
        abilities = {
            Ability1 = {
                displayName = "Sword Attack",
                cooldown = 2,
                castTime = 0,
                range = 10,
                damage = 15,
            },
            Ability2 = {
                displayName = "Hinrichten",
                cooldown = 5,
                castTime = 0,
                range = 10,
                damage = 22,
                executeBonus = 25,
                executeThreshold = 0.3,
            },
            Ability3 = {
                displayName = "Stun Hit",
                cooldown = 30,
                castTime = 0,
                range = 10,
                damage = 8,
                crowdControl = "Stun",
                crowdControlDuration = 3,
            },
            Ability4 = {
                displayName = "Ultimate Strike",
                cooldown = 60,
                castTime = 0,
                range = 12,
                damage = 52,
            },
        },
    },
    Priest = {
        displayName = "Priester",
        maxHealth = 135,
        baseWalkSpeed = 16,
        abilities = {
            Ability1 = {
                displayName = "Heal",
                cooldown = 1,
                castTime = 1,
                range = 60,
                heal = 24,
                friendly = true,
            },
            Ability2 = {
                displayName = "Shield",
                cooldown = 8,
                castTime = 0,
                range = 60,
                shield = 1000000,
                shieldDuration = 8,
                friendly = true,
            },
            Ability3 = {
                displayName = "Fear",
                cooldown = 30,
                castTime = 0,
                range = 45,
                crowdControl = "Fear",
                crowdControlDuration = 8,
            },
            Ability4 = {
                displayName = "Ultimate Full Heal",
                cooldown = 60,
                castTime = 0.2,
                range = 60,
                fullHeal = true,
                friendly = true,
            },
        },
    },
    Mage = {
        displayName = "Magier",
        maxHealth = 120,
        baseWalkSpeed = 16,
        abilities = {
            Ability1 = {
                displayName = "Feuerball",
                cooldown = 0,
                castTime = 1,
                range = 70,
                damage = 10,
                dotDamage = 5,
                dotDuration = 8,
                dotInterval = 1,
            },
            Ability2 = {
                displayName = "Frostbolt",
                cooldown = 4,
                castTime = 1.5,
                range = 70,
                damage = 16,
                crowdControl = "Slow",
                crowdControlDuration = 8,
                slowMultiplier = 0.75,
            },
            Ability3 = {
                displayName = "Frost Nova",
                cooldown = 20,
                castTime = 0,
                radius = 18,
                damage = 6,
                crowdControl = "Root",
                crowdControlDuration = 6,
                area = true,
            },
            Ability4 = {
                displayName = "Element Strike",
                cooldown = 60,
                castTime = 0.5,
                range = 75,
                damage = 50,
            },
        },
    },
    Rogue = {
        displayName = "Schurke",
        maxHealth = 130,
        baseWalkSpeed = 18,
        abilities = {
            Ability1 = {
                displayName = "Stich",
                cooldown = 0.5,
                castTime = 0,
                range = 8,
                damage = 9,
                focusGain = 1,
            },
            Ability2 = {
                displayName = "Schnitt",
                cooldown = 10,
                castTime = 0,
                range = 8,
                damage = 10,
                consumeFocus = true,
                focusDamage = 9,
            },
            Ability3 = {
                displayName = "Kick",
                cooldown = 15,
                castTime = 0,
                range = 8,
                damage = 4,
                interrupt = true,
                lockout = 10,
            },
            Ability4 = {
                displayName = "Blind",
                cooldown = 60,
                castTime = 0,
                range = 12,
                crowdControl = "Stun",
                crowdControlDuration = 8,
                effectName = "Blind",
            },
        },
    },
}

return ArenaDuelConfig
