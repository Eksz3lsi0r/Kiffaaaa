--!strict
-- pvp_hud.client.luau
-- World-space & overlay PvP HUD:
--   • Nameplates (BillboardGui over heads with HP, cast bar, debuffs)
--   • Target reticle (animated ground circle under the current target)
--   • Screen-edge vignette (red glow at < 30 % HP)
--   • Loss-of-Control indicator (CC icon + duration bar at screen centre)
-- All components are purely additive – they live in a separate ScreenGui
-- (DisplayOrder 10) and do not conflict with the existing ArenaDuelGui.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("ArenaDuelConfig"))
local remotesFolder = ReplicatedStorage:WaitForChild(Config.RemoteFolderName)
local stateUpdateEvent = remotesFolder:WaitForChild(Config.Remotes.StateUpdate) :: RemoteEvent

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- ─── Module state ────────────────────────────────────────────────────────────
local currentState: { [string]: any }? = nil
local stateReceivedAt = 0
local localFighterId: string? = nil
local selectedTargetId: string? = nil

-- ─── Class colours (mirrors camera.client classTints) ────────────────────────
local CLASS_COLOR: { [string]: Color3 } = {
    Warrior = Color3.fromRGB(199, 148, 92),
    Priest = Color3.fromRGB(221, 229, 241),
    Mage = Color3.fromRGB(111, 163, 255),
    Rogue = Color3.fromRGB(245, 214, 82),
}

-- Debuff-category border colours (spec §1.2)
local DEBUFF_CAT_COLOR: { [string]: Color3 } = {
    magic = Color3.fromRGB(80, 140, 255),
    disease = Color3.fromRGB(150, 100, 60),
    poison = Color3.fromRGB(80, 200, 80),
    curse = Color3.fromRGB(160, 60, 200),
}

-- Crowd-control display names
local CC_LABEL: { [string]: string } = {
    Stun = "BETÄUBT",
    Fear = "GEFÜRCHTET",
    Root = "VERWURZELT",
    Slow = "VERLANGSAMT",
}

-- ─── Root ScreenGui ──────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ArenaPvPHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. SCREEN-EDGE VIGNETTE  (low-HP red glow)
-- ═══════════════════════════════════════════════════════════════════════════
local vignetteEdges: { Frame } = {}
do
    local edgeDefs = {
        { pos = UDim2.new(0, 0, 0, 0), sz = UDim2.new(1, 0, 0, 90), rot = 0 }, -- top
        { pos = UDim2.new(0, 0, 1, -90), sz = UDim2.new(1, 0, 0, 90), rot = 180 }, -- bottom
        { pos = UDim2.new(0, 0, 0, 0), sz = UDim2.new(0, 90, 1, 0), rot = 270 }, -- left
        { pos = UDim2.new(1, -90, 0, 0), sz = UDim2.new(0, 90, 1, 0), rot = 90 }, -- right
    }

    for _, def in edgeDefs do
        local f = Instance.new("Frame")
        f.BackgroundColor3 = Color3.fromRGB(220, 20, 20)
        f.BackgroundTransparency = 1
        f.BorderSizePixel = 0
        f.Position = def.pos
        f.Size = def.sz
        f.ZIndex = 50
        f.Parent = screenGui

        local g = Instance.new("UIGradient")
        g.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.25),
            NumberSequenceKeypoint.new(1, 1),
        })
        g.Rotation = def.rot
        g.Parent = f

        table.insert(vignetteEdges, f)
    end
end

local vignetteActive = false
local function setVignette(active: boolean)
    if active == vignetteActive then
        return
    end
    vignetteActive = active
    local target = if active then 0 else 1
    for _, e in vignetteEdges do
        TweenService:Create(e, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
            BackgroundTransparency = target,
        }):Play()
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. LOSS-OF-CONTROL (CC) INDICATOR  (spec §7, Kampf-Feedback)
-- ═══════════════════════════════════════════════════════════════════════════
local ccFrame = Instance.new("Frame")
ccFrame.Name = "CCIndicator"
ccFrame.AnchorPoint = Vector2.new(0.5, 0.5)
ccFrame.Position = UDim2.fromScale(0.5, 0.5)
ccFrame.Size = UDim2.fromOffset(140, 36)
ccFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
ccFrame.BackgroundTransparency = 0.3
ccFrame.BorderSizePixel = 0
ccFrame.Visible = false
ccFrame.ZIndex = 30
ccFrame.Parent = screenGui
do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = ccFrame

    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(255, 60, 60)
    s.Thickness = 2
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = ccFrame
end

local ccLabel = Instance.new("TextLabel")
ccLabel.BackgroundTransparency = 1
ccLabel.Size = UDim2.new(1, 0, 0, 22)
ccLabel.Position = UDim2.fromOffset(0, 2)
ccLabel.Font = Enum.Font.GothamBold
ccLabel.TextColor3 = Color3.fromRGB(255, 180, 180)
ccLabel.TextSize = 13
ccLabel.TextStrokeTransparency = 0
ccLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
ccLabel.Text = "BETÄUBT"
ccLabel.ZIndex = 31
ccLabel.Parent = ccFrame

local ccBar = Instance.new("Frame")
ccBar.AnchorPoint = Vector2.new(0.5, 1)
ccBar.Position = UDim2.new(0.5, 0, 1, -4)
ccBar.Size = UDim2.new(1, -10, 0, 5)
ccBar.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
ccBar.BorderSizePixel = 0
ccBar.ZIndex = 31
ccBar.Parent = ccFrame
do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 2)
    c.Parent = ccBar
end

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. NAMEPLATES  (BillboardGui over each fighter's head)
-- ═══════════════════════════════════════════════════════════════════════════

-- Returns a smooth colour between Green → Yellow → Red based on 0..1 hp
local function hpGradientColor(pct: number): Color3
    if pct > 0.5 then
        local t = (1 - pct) * 2
        return Color3.fromRGB(math.floor(200 * t), 200, 0)
    else
        local t = pct * 2
        return Color3.fromRGB(200, math.floor(200 * t), 0)
    end
end

local nameplates: { [string]: BillboardGui } = {}

local function buildNameplate(fighterId: string): BillboardGui
    local bb = Instance.new("BillboardGui")
    bb.Name = "NP_" .. fighterId
    bb.AlwaysOnTop = false
    bb.Size = UDim2.fromOffset(210, 56)
    bb.StudsOffset = Vector3.new(0, 3.4, 0)
    bb.MaxDistance = 40
    bb.Enabled = false
    -- Parent set later (to character Head or HumanoidRootPart)

    local root = Instance.new("Frame")
    root.Name = "Root"
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromScale(1, 1)
    root.Parent = bb

    -- ── Debuff row (3 icons, centred above the name) ──────────────────────
    local debuffRow = Instance.new("Frame")
    debuffRow.Name = "DebuffRow"
    debuffRow.BackgroundTransparency = 1
    debuffRow.AnchorPoint = Vector2.new(0.5, 0)
    debuffRow.Position = UDim2.fromScale(0.5, 0)
    debuffRow.Size = UDim2.new(1, 0, 0, 18)
    debuffRow.Parent = root
    do
        local l = Instance.new("UIListLayout")
        l.FillDirection = Enum.FillDirection.Horizontal
        l.HorizontalAlignment = Enum.HorizontalAlignment.Center
        l.VerticalAlignment = Enum.VerticalAlignment.Center
        l.Padding = UDim.new(0, 2)
        l.SortOrder = Enum.SortOrder.LayoutOrder
        l.Parent = debuffRow
    end
    for i = 1, 3 do
        local ico = Instance.new("Frame")
        ico.Name = "D" .. i
        ico.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
        ico.BackgroundTransparency = 0.25
        ico.BorderSizePixel = 0
        ico.Size = UDim2.fromOffset(16, 16)
        ico.Visible = false
        ico.LayoutOrder = i
        ico.Parent = debuffRow
        do
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 3)
            c.Parent = ico

            local s = Instance.new("UIStroke")
            s.Color = DEBUFF_CAT_COLOR.magic
            s.Thickness = 1
            s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            s.Name = "CatStroke"
            s.Parent = ico

            local lbl = Instance.new("TextLabel")
            lbl.Name = "Lbl"
            lbl.BackgroundTransparency = 1
            lbl.Size = UDim2.fromScale(1, 0.65)
            lbl.Position = UDim2.fromScale(0, 0)
            lbl.Font = Enum.Font.GothamBold
            lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
            lbl.TextSize = 7
            lbl.Text = ""
            lbl.Parent = ico

            local dur = Instance.new("TextLabel")
            dur.Name = "Dur"
            dur.BackgroundTransparency = 1
            dur.AnchorPoint = Vector2.new(1, 1)
            dur.Position = UDim2.fromScale(1, 1)
            dur.Size = UDim2.fromOffset(14, 7)
            dur.Font = Enum.Font.GothamBold
            dur.TextColor3 = Color3.fromRGB(255, 255, 255)
            dur.TextStrokeTransparency = 0
            dur.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            dur.TextSize = 6
            dur.Text = ""
            dur.Parent = ico
        end
    end

    -- ── Name background + label ───────────────────────────────────────────
    local nameBg = Instance.new("Frame")
    nameBg.Name = "NameBg"
    nameBg.AnchorPoint = Vector2.new(0.5, 0)
    nameBg.Position = UDim2.new(0.5, 0, 0, 19)
    nameBg.Size = UDim2.fromOffset(110, 15)
    nameBg.AutomaticSize = Enum.AutomaticSize.X
    nameBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    nameBg.BackgroundTransparency = 0.55
    nameBg.BorderSizePixel = 0
    nameBg.Parent = root
    do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 3)
        c.Parent = nameBg

        local p = Instance.new("UIPadding")
        p.PaddingLeft = UDim.new(0, 4)
        p.PaddingRight = UDim.new(0, 4)
        p.Parent = nameBg
    end

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Name = "NameLbl"
    nameLbl.BackgroundTransparency = 1
    nameLbl.AutomaticSize = Enum.AutomaticSize.X
    nameLbl.Size = UDim2.fromOffset(0, 15)
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextColor3 = Color3.fromRGB(200, 170, 100)
    nameLbl.TextSize = 12
    nameLbl.TextStrokeTransparency = 0
    nameLbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameLbl.Text = "Name"
    nameLbl.Parent = nameBg

    -- ── HP bar (200×12) ───────────────────────────────────────────────────
    local hpBack = Instance.new("Frame")
    hpBack.Name = "HPBack"
    hpBack.AnchorPoint = Vector2.new(0.5, 0)
    hpBack.Position = UDim2.new(0.5, 0, 0, 36)
    hpBack.Size = UDim2.fromOffset(200, 12)
    hpBack.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    hpBack.BackgroundTransparency = 0.4
    hpBack.BorderSizePixel = 0
    hpBack.Parent = root
    do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 2)
        c.Parent = hpBack

        local s = Instance.new("UIStroke")
        s.Color = Color3.fromRGB(50, 50, 50)
        s.Thickness = 1
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = hpBack
    end

    local hpFill = Instance.new("Frame")
    hpFill.Name = "HPFill"
    hpFill.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    hpFill.BorderSizePixel = 0
    hpFill.Size = UDim2.fromScale(1, 1)
    hpFill.Parent = hpBack
    do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 2)
        c.Parent = hpFill
    end

    local hpLbl = Instance.new("TextLabel")
    hpLbl.Name = "HPLbl"
    hpLbl.BackgroundTransparency = 1
    hpLbl.Size = UDim2.fromScale(1, 1)
    hpLbl.Font = Enum.Font.Gotham
    hpLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    hpLbl.TextStrokeTransparency = 0
    hpLbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    hpLbl.TextSize = 9
    hpLbl.Text = ""
    hpLbl.Parent = hpBack

    -- ── Cast bar (200×10, below HP bar) ───────────────────────────────────
    local castBack = Instance.new("Frame")
    castBack.Name = "CastBack"
    castBack.AnchorPoint = Vector2.new(0.5, 0)
    castBack.Position = UDim2.new(0.5, 0, 0, 50)
    castBack.Size = UDim2.fromOffset(200, 10)
    castBack.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    castBack.BackgroundTransparency = 0.3
    castBack.BorderSizePixel = 0
    castBack.Visible = false
    castBack.Parent = root
    do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 2)
        c.Parent = castBack

        local s = Instance.new("UIStroke")
        s.Color = Color3.fromRGB(60, 50, 20)
        s.Thickness = 1
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = castBack
    end

    local castFill = Instance.new("Frame")
    castFill.Name = "CastFill"
    castFill.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
    castFill.BorderSizePixel = 0
    castFill.Size = UDim2.fromScale(0, 1)
    castFill.Parent = castBack
    do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 2)
        c.Parent = castFill
    end

    local castLbl = Instance.new("TextLabel")
    castLbl.Name = "CastLbl"
    castLbl.BackgroundTransparency = 1
    castLbl.Position = UDim2.fromOffset(4, 0)
    castLbl.Size = UDim2.new(1, -8, 1, 0)
    castLbl.Font = Enum.Font.Gotham
    castLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    castLbl.TextStrokeTransparency = 0
    castLbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    castLbl.TextSize = 8
    castLbl.TextXAlignment = Enum.TextXAlignment.Left
    castLbl.Text = ""
    castLbl.Parent = castBack

    return bb
end

local function getOrBuildNameplate(id: string): BillboardGui
    if not nameplates[id] then
        nameplates[id] = buildNameplate(id)
    end
    return nameplates[id]
end

local function destroyNameplate(id: string)
    local bb = nameplates[id]
    if bb then
        bb:Destroy()
        nameplates[id] = nil
    end
end

-- Returns the character Model for a given fighter snapshot
local function characterForFighter(fighter: { [string]: any }): Model?
    if not fighter.isBot then
        local uid = tonumber(fighter.id)
        if uid then
            local p = Players:GetPlayerByUserId(uid)
            if p then
                return p.Character
            end
        end
    end
    -- Bot: search workspace.ArenaDuelWorld for a Model with matching name
    local world = workspace:FindFirstChild("ArenaDuelWorld")
    if world then
        local child = world:FindFirstChild(tostring(fighter.name))
        if child and child:IsA("Model") then
            return child
        end
    end
    -- Fallback: search top-level workspace
    local top = workspace:FindFirstChild(tostring(fighter.name))
    if top and top:IsA("Model") then
        return top
    end
    return nil
end

local function updateNameplate(bb: BillboardGui, fighter: { [string]: any }, isTarget: boolean)
    local root = bb:FindFirstChild("Root") :: Frame?
    if not root then
        return
    end

    local hpNum = tonumber(fighter.health) or 0
    local maxNum = math.max(tonumber(fighter.maxHealth) or 1, 1)
    local hpPct = math.clamp(hpNum / maxNum, 0, 1)
    local classClr = CLASS_COLOR[fighter.classId] or Color3.fromRGB(200, 170, 100)

    -- Name
    local nameBg = root:FindFirstChild("NameBg") :: Frame?
    local nameLbl = if nameBg then nameBg:FindFirstChild("NameLbl") :: TextLabel? else nil
    if nameLbl then
        nameLbl.TextColor3 = classClr
        nameLbl.Text = tostring(fighter.name or "?")
        nameLbl.TextSize = if isTarget then 13 else 12
    end
    if nameBg then
        nameBg.BackgroundTransparency = if isTarget then 0.22 else 0.55
        local stroke = nameBg:FindFirstChildOfClass("UIStroke")
        if isTarget then
            if not stroke then
                stroke = Instance.new("UIStroke")
                stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                stroke.Parent = nameBg
            end
            stroke.Color = classClr
            stroke.Thickness = 2
        elseif stroke then
            stroke.Thickness = 0
        end
    end

    -- HP bar
    local hpBack = root:FindFirstChild("HPBack") :: Frame?
    if hpBack then
        local hpFill = hpBack:FindFirstChild("HPFill") :: Frame?
        local hpLbl = hpBack:FindFirstChild("HPLbl") :: TextLabel?
        if hpFill then
            TweenService
                :Create(
                    hpFill,
                    TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    { Size = UDim2.fromScale(hpPct, 1), BackgroundColor3 = hpGradientColor(hpPct) }
                )
                :Play()
        end
        if hpLbl then
            if isTarget then
                hpLbl.Text = string.format(
                    "%d / %d  %d%%",
                    math.floor(hpNum),
                    math.floor(maxNum),
                    math.floor(hpPct * 100)
                )
            else
                hpLbl.Text = string.format("%d / %d", math.floor(hpNum), math.floor(maxNum))
            end
        end
    end

    -- Scale up when targeted
    local uiScale = root:FindFirstChildOfClass("UIScale")
    if isTarget then
        if not uiScale then
            uiScale = Instance.new("UIScale")
            uiScale.Parent = root
        end
        TweenService:Create(uiScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
            Scale = 1.2,
        }):Play()
    elseif uiScale then
        TweenService:Create(uiScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
            Scale = 1.0,
        }):Play()
    end

    -- Cast bar
    local castBack = root:FindFirstChild("CastBack") :: Frame?
    if castBack then
        if fighter.casting then
            local dur = math.max(tonumber(fighter.casting.duration) or 0.01, 0.01)
            local rem = math.max(
                0,
                (tonumber(fighter.casting.remaining) or 0) - (os.clock() - stateReceivedAt)
            )
            local prog = math.clamp(1 - rem / dur, 0, 1)
            castBack.Visible = true
            local castFill = castBack:FindFirstChild("CastFill") :: Frame?
            if castFill then
                castFill.Size = UDim2.fromScale(prog, 1)
                -- Gold = interruptible, Orange = non-interruptible (use cast time as proxy)
                castFill.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
            end
            local castLbl = castBack:FindFirstChild("CastLbl") :: TextLabel?
            if castLbl then
                castLbl.Text = string.format(
                    "%s – %.1f s",
                    tostring(fighter.casting.displayName or fighter.casting.abilityId or ""),
                    rem
                )
            end
        else
            castBack.Visible = false
        end
    end

    -- Debuff icons (top 3 effects)
    local debuffRow = root:FindFirstChild("DebuffRow") :: Frame?
    if debuffRow then
        local effects = fighter.effects or {}
        for i = 1, 3 do
            local ico = debuffRow:FindFirstChild("D" .. i) :: Frame?
            if not ico then
                continue
            end
            local eff = effects[i]
            if eff then
                ico.Visible = true
                local catClr = DEBUFF_CAT_COLOR[eff.category or "magic"] or DEBUFF_CAT_COLOR.magic
                local stroke = ico:FindFirstChild("CatStroke") :: UIStroke?
                if stroke then
                    stroke.Color = catClr
                end
                local lbl = ico:FindFirstChild("Lbl") :: TextLabel?
                if lbl then
                    lbl.Text = string.upper(string.sub(tostring(eff.name or "?"), 1, 2))
                end
                local dur = ico:FindFirstChild("Dur") :: TextLabel?
                if dur then
                    local rem = math.max(0, tonumber(eff.remaining) or 0)
                    dur.Text = if rem > 0.5 then string.format("%.0f", rem) else ""
                end
            else
                ico.Visible = false
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. TARGET RETICLE  (animated ground circle under the selected target)
-- ═══════════════════════════════════════════════════════════════════════════
local reticleBB = Instance.new("BillboardGui")
reticleBB.Name = "TargetReticle"
reticleBB.AlwaysOnTop = false
reticleBB.Size = UDim2.fromOffset(90, 90)
reticleBB.StudsOffset = Vector3.new(0, 0.05, 0)
reticleBB.Enabled = false
reticleBB.Parent = workspace

-- Outer ring (thin stroke circle)
local reticleOuter = Instance.new("Frame")
reticleOuter.Name = "Outer"
reticleOuter.AnchorPoint = Vector2.new(0.5, 0.5)
reticleOuter.Position = UDim2.fromScale(0.5, 0.5)
reticleOuter.Size = UDim2.fromOffset(80, 80)
reticleOuter.BackgroundTransparency = 1
reticleOuter.BorderSizePixel = 0
reticleOuter.Parent = reticleBB
do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = reticleOuter
end
local reticleOuterStroke = Instance.new("UIStroke")
reticleOuterStroke.Color = Color3.fromRGB(255, 50, 50)
reticleOuterStroke.Thickness = 1.5
reticleOuterStroke.Transparency = 0.15
reticleOuterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
reticleOuterStroke.Parent = reticleOuter

-- Inner fill circle (semi-transparent)
local reticleInner = Instance.new("Frame")
reticleInner.Name = "Inner"
reticleInner.AnchorPoint = Vector2.new(0.5, 0.5)
reticleInner.Position = UDim2.fromScale(0.5, 0.5)
reticleInner.Size = UDim2.fromOffset(64, 64)
reticleInner.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
reticleInner.BackgroundTransparency = 0.72
reticleInner.BorderSizePixel = 0
reticleInner.Parent = reticleBB
do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = reticleInner
end

-- Rotation ring (thin outer ring that rotates slowly)
local reticleRotator = Instance.new("Frame")
reticleRotator.Name = "Rotator"
reticleRotator.AnchorPoint = Vector2.new(0.5, 0.5)
reticleRotator.Position = UDim2.fromScale(0.5, 0.5)
reticleRotator.Size = UDim2.fromOffset(88, 88)
reticleRotator.BackgroundTransparency = 1
reticleRotator.BorderSizePixel = 0
reticleRotator.Parent = reticleBB
do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = reticleRotator

    -- Dashed effect: a small neon dot
    local dot = Instance.new("Frame")
    dot.AnchorPoint = Vector2.new(0.5, 0)
    dot.Position = UDim2.new(0.5, -2, 0, 0)
    dot.Size = UDim2.fromOffset(4, 4)
    dot.BackgroundColor3 = Color3.fromRGB(255, 220, 80)
    dot.BackgroundTransparency = 0
    dot.BorderSizePixel = 0
    dot.Parent = reticleRotator
    do
        local dc = Instance.new("UICorner")
        dc.CornerRadius = UDim.new(1, 0)
        dc.Parent = dot
    end
end

-- Pulse animation coroutine
local reticlePulseRunning = false
local function startReticlePulse(color: Color3)
    reticleOuterStroke.Color = color
    reticleInner.BackgroundColor3 = color
    if reticlePulseRunning then
        return
    end
    reticlePulseRunning = true
    task.spawn(function()
        while reticleBB.Enabled and reticlePulseRunning do
            TweenService:Create(
                reticleOuter,
                TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { Size = UDim2.fromOffset(84, 84) }
            ):Play()
            TweenService:Create(
                reticleInner,
                TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { Size = UDim2.fromOffset(67, 67), BackgroundTransparency = 0.62 }
            ):Play()
            task.wait(0.5)
            TweenService:Create(
                reticleOuter,
                TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { Size = UDim2.fromOffset(80, 80) }
            ):Play()
            TweenService:Create(
                reticleInner,
                TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { Size = UDim2.fromOffset(64, 64), BackgroundTransparency = 0.72 }
            ):Play()
            task.wait(0.5)
        end
        reticlePulseRunning = false
    end)
end

-- Slow rotation of the outer dot ring (RunService)
RunService.Heartbeat:Connect(function(dt)
    if reticleBB.Enabled then
        reticleRotator.Rotation = reticleRotator.Rotation + dt * 45 -- 45°/s
    end
end)

local function setReticle(
    char: Model?,
    fighter: { [string]: any },
    localFighter: { [string]: any }?
)
    if not char then
        reticleBB.Enabled = false
        reticlePulseRunning = false
        return
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        reticleBB.Enabled = false
        reticlePulseRunning = false
        return
    end
    reticleBB.Adornee = hrp :: BasePart
    reticleBB.Enabled = true

    -- Colour by relation (spec §1.1)
    local color: Color3
    if localFighter and fighter.team == localFighter.team then
        color = Color3.fromRGB(0, 255, 100) -- friendly: green
    else
        color = Color3.fromRGB(255, 50, 50) -- hostile:  red
    end
    startReticlePulse(color)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. UPDATE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════
local function localFighterFromState(): { [string]: any }?
    if not currentState or currentState.kind ~= "Match" then
        return nil
    end
    for _, f in currentState.fighters or {} do
        if f.id == localFighterId then
            return f
        end
    end
    return nil
end

local function updateVignette()
    local lf = localFighterFromState()
    if not lf then
        setVignette(false)
        return
    end
    local pct =
        math.clamp((tonumber(lf.health) or 0) / math.max(tonumber(lf.maxHealth) or 1, 1), 0, 1)
    setVignette(pct < 0.30)
end

local function updateCC()
    local lf = localFighterFromState()
    if not lf then
        ccFrame.Visible = false
        return
    end
    local ccEff: { [string]: any }? = nil
    for _, eff in lf.effects or {} do
        local n = tostring(eff.name or "")
        if n == "Stun" or n == "Fear" or n == "Root" then
            ccEff = eff
            break
        end
    end
    if not ccEff then
        ccFrame.Visible = false
        return
    end
    ccFrame.Visible = true
    ccLabel.Text = CC_LABEL[ccEff.name] or "KONTROLLVERLUST"
    local rem = math.max(0, tonumber(ccEff.remaining) or 0)
    local full = math.max(tonumber(ccEff.duration) or rem, 0.01)
    local pct = math.clamp(rem / full, 0, 1)
    TweenService:Create(ccBar, TweenInfo.new(0.08, Enum.EasingStyle.Linear), {
        Size = UDim2.new(pct, -10, 0, 5),
    }):Play()
end

local function updateNameplatesAll()
    if not currentState or currentState.kind ~= "Match" then
        for _, bb in nameplates do
            bb.Enabled = false
        end
        reticleBB.Enabled = false
        reticlePulseRunning = false
        return
    end

    local fighters = currentState.fighters or {}
    local seen: { [string]: true } = {}

    local localFighter: { [string]: any }? = nil
    for _, f in fighters do
        if f.id == localFighterId then
            localFighter = f
            break
        end
    end

    local targetReticleSet = false
    for _, fighter in fighters do
        seen[fighter.id] = true
        local char = characterForFighter(fighter)
        if not char then
            continue
        end

        -- Attach nameplate to Head if available, otherwise HumanoidRootPart
        local anchor = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
        if not anchor then
            continue
        end

        local isTarget = (selectedTargetId == fighter.id)
        local isLocal = (fighter.id == localFighterId)

        local bb = getOrBuildNameplate(fighter.id)
        if bb.Parent ~= anchor then
            bb.Parent = anchor
        end
        -- Hide nameplate for the local player (we see ourselves in the unit frame)
        bb.Enabled = not isLocal

        if not isLocal then
            updateNameplate(bb, fighter, isTarget)
        end

        -- Reticle
        if isTarget then
            setReticle(char, fighter, localFighter)
            targetReticleSet = true
        end
    end

    if not targetReticleSet then
        reticleBB.Enabled = false
        reticlePulseRunning = false
    end

    -- Clean up stale plates
    for id in nameplates do
        if not seen[id] then
            destroyNameplate(id)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. EVENT WIRING
-- ═══════════════════════════════════════════════════════════════════════════
stateUpdateEvent.OnClientEvent:Connect(function(state)
    currentState = state
    stateReceivedAt = os.clock()

    if state.kind == "Match" then
        localFighterId = state.localFighterId
        -- Sync target from server state
        for _, f in state.fighters or {} do
            if f.id == localFighterId then
                if f.targetId then
                    selectedTargetId = f.targetId
                end
                break
            end
        end
    else
        localFighterId = nil
        selectedTargetId = nil
    end

    updateVignette()
    updateCC()
    updateNameplatesAll()
end)

-- Continuous polling loop for cast-bar progress & reticle rotation
task.spawn(function()
    while screenGui.Parent do
        updateNameplatesAll()
        updateVignette()
        updateCC()
        task.wait(0.08)
    end
end)
