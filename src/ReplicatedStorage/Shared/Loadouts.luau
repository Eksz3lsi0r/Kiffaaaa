--!strict

export type ElementName = "Earth" | "Air" | "Fire" | "Water"
export type LoadoutId =
    "earth_bulwark"
    | "earth_seismic"
    | "air_skirmisher"
    | "air_tempest"
    | "fire_ember"
    | "fire_inferno"
    | "water_tide"
    | "water_maelstrom"

export type LoadoutDefinition = {
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

local Loadouts: { [LoadoutId]: LoadoutDefinition } = {
    earth_bulwark = {
        Id = "earth_bulwark",
        Element = "Earth",
        DisplayName = "Bulwark of Stone",
        Summary = "Zaehe Frontlinie mit starken Schutzwerten.",
        Passive = "Bastion Skin erzeugt ein groesseres Schild.",
        UnlockProgress = 1,
        DamageMultiplier = 0.95,
        HealthBonus = 24,
        CooldownMultiplier = 1,
    },
    earth_seismic = {
        Id = "earth_seismic",
        Element = "Earth",
        DisplayName = "Seismic Breaker",
        Summary = "Mehr Druck, mehr Wucht, weniger Geduld.",
        Passive = "Stone Lance verlangsamt laenger und trifft haerter.",
        UnlockProgress = 4,
        DamageMultiplier = 1.08,
        HealthBonus = 8,
        CooldownMultiplier = 0.94,
    },
    air_skirmisher = {
        Id = "air_skirmisher",
        Element = "Air",
        DisplayName = "Sky Skirmisher",
        Summary = "Leichtfuessiger Duelist mit hoher Beweglichkeit.",
        Passive = "Gale Step ist kuerzer, aber deutlich schneller.",
        UnlockProgress = 1,
        DamageMultiplier = 1.03,
        HealthBonus = 0,
        CooldownMultiplier = 0.94,
    },
    air_tempest = {
        Id = "air_tempest",
        Element = "Air",
        DisplayName = "Tempest Rider",
        Summary = "Rotiert zwischen Position und Burst.",
        Passive = "Skyfall wirkt nach dem Treffer explosiver.",
        UnlockProgress = 4,
        DamageMultiplier = 0.98,
        HealthBonus = 12,
        CooldownMultiplier = 0.9,
    },
    fire_ember = {
        Id = "fire_ember",
        Element = "Fire",
        DisplayName = "Ember Duelist",
        Summary = "Aggressiver Brennmeister fuer kurze Duelle.",
        Passive = "Ember Spear laesst Brand laenger ticken.",
        UnlockProgress = 1,
        DamageMultiplier = 1.08,
        HealthBonus = 0,
        CooldownMultiplier = 0.96,
    },
    fire_inferno = {
        Id = "fire_inferno",
        Element = "Fire",
        DisplayName = "Inferno Adept",
        Summary = "Hoher Abschlussdruck mit starker Ultimate.",
        Passive = "Inferno Ring trifft weiter und brennt staerker.",
        UnlockProgress = 4,
        DamageMultiplier = 1.13,
        HealthBonus = 8,
        CooldownMultiplier = 0.9,
    },
    water_tide = {
        Id = "water_tide",
        Element = "Water",
        DisplayName = "Tidal Warden",
        Summary = "Langsamer, staerker, schwerer zu knacken.",
        Passive = "Healing Spring heilt mehr und laenger.",
        UnlockProgress = 1,
        DamageMultiplier = 0.96,
        HealthBonus = 22,
        CooldownMultiplier = 0.98,
    },
    water_maelstrom = {
        Id = "water_maelstrom",
        Element = "Water",
        DisplayName = "Maelstrom Sage",
        Summary = "Sustain mit einem klaren späten Kampfplan.",
        Passive = "Maelstrom heilt staerker und zieht Gegner naeher heran.",
        UnlockProgress = 4,
        DamageMultiplier = 1,
        HealthBonus = 12,
        CooldownMultiplier = 0.9,
    },
}

local LoadoutOrder: { [ElementName]: { LoadoutId } } = {
    Earth = { "earth_bulwark", "earth_seismic" },
    Air = { "air_skirmisher", "air_tempest" },
    Fire = { "fire_ember", "fire_inferno" },
    Water = { "water_tide", "water_maelstrom" },
}

local DefaultLoadoutByElement: { [ElementName]: LoadoutId } = {
    Earth = "earth_bulwark",
    Air = "air_skirmisher",
    Fire = "fire_ember",
    Water = "water_tide",
}

return {
    Loadouts = Loadouts,
    LoadoutOrder = LoadoutOrder,
    DefaultLoadoutByElement = DefaultLoadoutByElement,
}
