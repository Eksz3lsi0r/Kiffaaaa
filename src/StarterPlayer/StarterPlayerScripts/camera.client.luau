local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("ArenaDuelConfig"))
local remotesFolder = ReplicatedStorage:WaitForChild(Config.RemoteFolderName)

local queueRequestEvent = remotesFolder:WaitForChild(Config.Remotes.QueueRequest) :: RemoteEvent
local classSelectEvent = remotesFolder:WaitForChild(Config.Remotes.ClassSelect) :: RemoteEvent
local targetSelectEvent = remotesFolder:WaitForChild(Config.Remotes.TargetSelect) :: RemoteEvent
local abilityCastEvent = remotesFolder:WaitForChild(Config.Remotes.AbilityCast) :: RemoteEvent
local stateUpdateEvent = remotesFolder:WaitForChild(Config.Remotes.StateUpdate) :: RemoteEvent
local systemMessageEvent = remotesFolder:WaitForChild(Config.Remotes.SystemMessage) :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local currentState = nil
local selectedClass = "Warrior"
local selectedTargetId: string? = nil
local abilityButtons: { TextButton } = {}
local abilityVisuals = {}
local classButtons: { [string]: TextButton } = {}
local targetButtons: { [string]: TextButton } = {}
local seenCombatEvents: { [number]: boolean } = {}
local stateReceivedAt = os.clock()
local messageExpiresAt = 0
local messageFading = false
local messageTween: Tween? = nil
local studioAutoQueueRequested = false
local cameraShakeIntensity = 0
local cameraShakeSeed = 0
local portraitCache = {}
local applyPanelChrome: (Frame, Color3) -> ()
local applyButtonChrome: (TextButton, Color3) -> ()

local theme = {
    shadow = Color3.fromRGB(10, 8, 8),
    panelTop = Color3.fromRGB(69, 50, 33),
    panelMid = Color3.fromRGB(34, 25, 21),
    panelBottom = Color3.fromRGB(18, 14, 12),
    raised = Color3.fromRGB(63, 42, 29),
    trim = Color3.fromRGB(164, 118, 64),
    trimBright = Color3.fromRGB(233, 200, 140),
    health = Color3.fromRGB(188, 66, 60),
    healthLow = Color3.fromRGB(222, 84, 72),
    mana = Color3.fromRGB(86, 133, 224),
    focus = Color3.fromRGB(232, 182, 72),
    ready = Color3.fromRGB(126, 188, 92),
    locked = Color3.fromRGB(121, 69, 83),
    cast = Color3.fromRGB(222, 176, 88),
    panelText = Color3.fromRGB(239, 227, 204),
    mutedText = Color3.fromRGB(186, 172, 154),
}

local classTints = {
    Warrior = Color3.fromRGB(199, 148, 92),
    Priest = Color3.fromRGB(221, 229, 241),
    Mage = Color3.fromRGB(111, 163, 255),
    Rogue = Color3.fromRGB(245, 214, 82),
}

local abilityVisualAssets = {
    Mage = {
        Ability1 = {
            image = "rbxassetid://229313524",
            glyph = "FB",
            rune = "Feuer",
            iconColor = Color3.fromRGB(246, 126, 58),
            panelColor = Color3.fromRGB(66, 34, 24),
        },
        Ability2 = {
            image = "rbxassetid://3131549391",
            glyph = "FR",
            rune = "Frost",
            iconColor = Color3.fromRGB(112, 205, 255),
            panelColor = Color3.fromRGB(24, 43, 64),
        },
        Ability3 = {
            image = "rbxassetid://91049678",
            glyph = "NV",
            rune = "Nova",
            iconColor = Color3.fromRGB(168, 236, 255),
            panelColor = Color3.fromRGB(29, 54, 78),
        },
        Ability4 = {
            image = "rbxassetid://23534055",
            glyph = "EX",
            rune = "Element",
            iconColor = Color3.fromRGB(198, 126, 255),
            panelColor = Color3.fromRGB(54, 34, 80),
        },
    },
}

local function getAbilityVisualAsset(classId: string, abilityId: string, displayName: string)
    local classAssets = abilityVisualAssets[classId]
    local asset = if classAssets then classAssets[abilityId] else nil
    if asset then
        return asset
    end

    return {
        image = "",
        glyph = string.upper(string.sub(displayName, 1, 2)),
        rune = classId,
        iconColor = classTints[classId] or theme.trimBright,
        panelColor = theme.panelBottom,
    }
end

local function resolveAbilityImage(image: string): string
    local assetId = string.match(image, "^rbxassetid://(%d+)$")
    if assetId then
        -- Using rbxthumb makes non-image asset IDs still render as visible thumbnails.
        return string.format("rbxthumb://type=Asset&id=%s&w=150&h=150", assetId)
    end

    return image
end

local function getStudioAutoQueueMode(): string?
    if not RunService:IsStudio() then
        return nil
    end

    local mode = ReplicatedStorage:GetAttribute(Config.StudioAutomation.AutoQueueModeAttribute)
    if typeof(mode) ~= "string" or not Config.MatchModes[mode] then
        return nil
    end

    return mode
end

local studioAutoQueueMode = getStudioAutoQueueMode()

local function requestStudioAutoQueue()
    if studioAutoQueueRequested or not studioAutoQueueMode then
        return
    end

    studioAutoQueueRequested = true
    -- In automated playtests there is no human at the keyboard.
    -- Force Mage so the player fighter can attack from range (70 studs)
    -- instead of defaulting to Warrior and never reaching melee range.
    if studioAutoQueueMode == "Bot" then
        classSelectEvent:FireServer("Mage")
    end
    queueRequestEvent:FireServer(studioAutoQueueMode)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ArenaDuelGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 8
screenGui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = screenGui

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.AnchorPoint = Vector2.new(0.5, 0)
topBar.Position = UDim2.fromScale(0.5, 0.02)
topBar.Size = UDim2.fromOffset(280, 36)
topBar.BackgroundColor3 = theme.panelMid
topBar.BackgroundTransparency = 0.04
topBar.BorderSizePixel = 0
topBar.Parent = root

local topCorner = Instance.new("UICorner")
topCorner.CornerRadius = UDim.new(0, 8)
topCorner.Parent = topBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.fromOffset(10, 5)
titleLabel.Size = UDim2.new(1, -20, 0, 13)
titleLabel.Font = Enum.Font.Garamond
titleLabel.TextColor3 = theme.trimBright
titleLabel.TextScaled = false
titleLabel.TextSize = 10
titleLabel.Text = "Vor Lobby Matchmaking"
titleLabel.Parent = topBar

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "Timer"
timerLabel.BackgroundTransparency = 1
timerLabel.Position = UDim2.fromOffset(10, 20)
timerLabel.Size = UDim2.new(1, -20, 0, 10)
timerLabel.Font = Enum.Font.Garamond
timerLabel.TextColor3 = theme.panelText
timerLabel.TextScaled = false
timerLabel.TextSize = 8
timerLabel.Text = "Waehle Klasse und Matchmodus"
timerLabel.Parent = topBar

local leftPanel = Instance.new("Frame")
leftPanel.Name = "LobbyPanel"
leftPanel.Position = UDim2.fromOffset(11, 55)
leftPanel.Size = UDim2.fromOffset(120, 155)
leftPanel.BackgroundColor3 = theme.panelMid
leftPanel.BackgroundTransparency = 0.04
leftPanel.BorderSizePixel = 0
leftPanel.Parent = root

local leftCorner = Instance.new("UICorner")
leftCorner.CornerRadius = UDim.new(0, 8)
leftCorner.Parent = leftPanel

local leftLayout = Instance.new("UIListLayout")
leftLayout.Padding = UDim.new(0, 3)
leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
leftLayout.Parent = leftPanel

local leftPadding = Instance.new("UIPadding")
leftPadding.PaddingTop = UDim.new(0, 5)
leftPadding.PaddingLeft = UDim.new(0, 5)
leftPadding.PaddingRight = UDim.new(0, 5)
leftPadding.Parent = leftPanel

local function createPanelLabel(text: string, parent: Instance, height: number): TextLabel
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 0, height)
    label.Font = Enum.Font.Garamond
    label.TextColor3 = theme.trimBright
    label.TextSize = 9
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = text
    label.Parent = parent
    return label
end

local function createButton(text: string, parent: Instance, height: number): TextButton
    local button = Instance.new("TextButton")
    button.AutoButtonColor = false
    button.Size = UDim2.new(1, 0, 0, height)
    button.BackgroundColor3 = theme.raised
    button.BorderSizePixel = 0
    button.Font = Enum.Font.Garamond
    button.TextColor3 = theme.panelText
    button.TextSize = 8
    button.TextWrapped = true
    button.Text = text
    button.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    applyButtonChrome(button, theme.trim)

    return button
end

local function animateButtonPress(button: TextButton)
    local scaleInstance = button:FindFirstChild("PressScale")
    local scale: UIScale
    if scaleInstance and scaleInstance:IsA("UIScale") then
        scale = scaleInstance
    else
        scale = Instance.new("UIScale")
        scale.Name = "PressScale"
        scale.Parent = button
    end

    scale.Scale = 1

    task.spawn(function()
        local shrink = TweenService:Create(
            scale,
            TweenInfo.new(0.055, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Scale = 0.96 }
        )
        local expand = TweenService:Create(
            scale,
            TweenInfo.new(0.11, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Scale = 1 }
        )

        shrink:Play()
        shrink.Completed:Wait()
        expand:Play()
    end)
end

local function getClassTint(classId: string?): Color3
    return classTints[classId or ""] or theme.trimBright
end

local function addStroke(
    guiObject: GuiObject,
    color: Color3,
    thickness: number,
    transparency: number
): UIStroke
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = color
    stroke.Thickness = thickness
    stroke.Transparency = transparency
    stroke.Parent = guiObject
    return stroke
end

local function addPanelGem(parent: GuiObject, xOffset: number, yOffset: number, accentColor: Color3)
    local gem = Instance.new("Frame")
    gem.Name = "Gem"
    gem.BackgroundColor3 = accentColor
    gem.BackgroundTransparency = 0.12
    gem.BorderSizePixel = 0
    gem.Position = UDim2.fromOffset(xOffset, yOffset)
    gem.Size = UDim2.fromOffset(10, 10)
    gem.Rotation = 45
    gem.ZIndex = 5
    gem.Parent = parent

    local stroke = addStroke(gem, theme.trimBright, 1, 0.2)
    stroke.LineJoinMode = Enum.LineJoinMode.Round
end

applyPanelChrome = function(frame: Frame, accentColor: Color3)
    frame.BackgroundColor3 = theme.panelMid
    frame.BackgroundTransparency = 0.04
    frame.ClipsDescendants = false

    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, accentColor:Lerp(theme.panelTop, 0.75)),
        ColorSequenceKeypoint.new(0.18, theme.panelTop),
        ColorSequenceKeypoint.new(0.5, theme.panelMid),
        ColorSequenceKeypoint.new(1, theme.panelBottom),
    })
    gradient.Rotation = 90
    gradient.Parent = frame

    local stroke = addStroke(frame, accentColor:Lerp(theme.trimBright, 0.45), 2, 0.12)
    stroke.LineJoinMode = Enum.LineJoinMode.Round

    local inset = Instance.new("Frame")
    inset.Name = "Inset"
    inset.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    inset.BackgroundTransparency = 0.95
    inset.BorderSizePixel = 0
    inset.Position = UDim2.fromOffset(6, 6)
    inset.Size = UDim2.new(1, -12, 1, -12)
    inset.ZIndex = 0
    inset.Parent = frame

    local insetCorner = Instance.new("UICorner")
    insetCorner.CornerRadius = UDim.new(0, 8)
    insetCorner.Parent = inset

    local topTrim = Instance.new("Frame")
    topTrim.Name = "TopTrim"
    topTrim.BackgroundColor3 = accentColor:Lerp(theme.trimBright, 0.4)
    topTrim.BorderSizePixel = 0
    topTrim.Position = UDim2.fromOffset(18, 10)
    topTrim.Size = UDim2.new(1, -36, 0, 2)
    topTrim.Parent = frame

    local bottomTrim = Instance.new("Frame")
    bottomTrim.Name = "BottomTrim"
    bottomTrim.BackgroundColor3 = accentColor:Lerp(theme.panelBottom, 0.35)
    bottomTrim.BorderSizePixel = 0
    bottomTrim.AnchorPoint = Vector2.new(0, 1)
    bottomTrim.Position = UDim2.new(0, 18, 1, -10)
    bottomTrim.Size = UDim2.new(1, -36, 0, 2)
    bottomTrim.Parent = frame

    local topLeft = Instance.new("Frame")
    topLeft.BackgroundTransparency = 1
    topLeft.Size = UDim2.fromOffset(0, 0)
    topLeft.Parent = frame
    addPanelGem(frame, 16, 6, accentColor)
    addPanelGem(frame, 16, 0, accentColor)
end

applyButtonChrome = function(button: TextButton, accentColor: Color3)
    button.AutoButtonColor = false
    button.BackgroundColor3 = theme.raised
    button.BackgroundTransparency = 0.02
    button.Font = Enum.Font.Garamond
    button.TextSize = 9
    button.TextColor3 = theme.panelText

    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, accentColor:Lerp(theme.panelTop, 0.7)),
        ColorSequenceKeypoint.new(0.34, theme.raised),
        ColorSequenceKeypoint.new(1, theme.panelBottom),
    })
    gradient.Rotation = 90
    gradient.Parent = button

    local stroke = addStroke(button, accentColor:Lerp(theme.trimBright, 0.4), 1.5, 0.14)
    stroke.LineJoinMode = Enum.LineJoinMode.Round
end

applyPanelChrome(topBar, theme.trim)
applyPanelChrome(leftPanel, Color3.fromRGB(118, 148, 196))

local function createPortrait(
    parent: Instance,
    position: UDim2,
    accentColor: Color3
): (Frame, ImageLabel, TextLabel)
    local portraitFrame = Instance.new("Frame")
    portraitFrame.Name = "Portrait"
    portraitFrame.Position = position
    portraitFrame.Size = UDim2.fromOffset(32, 32)
    portraitFrame.BackgroundColor3 = theme.panelBottom
    portraitFrame.BorderSizePixel = 0
    portraitFrame.Parent = parent

    local portraitCorner = Instance.new("UICorner")
    portraitCorner.CornerRadius = UDim.new(0, 12)
    portraitCorner.Parent = portraitFrame

    local portraitStroke =
        addStroke(portraitFrame, accentColor:Lerp(theme.trimBright, 0.35), 2, 0.08)
    portraitStroke.LineJoinMode = Enum.LineJoinMode.Round

    local portraitGradient = Instance.new("UIGradient")
    portraitGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, accentColor:Lerp(theme.panelTop, 0.8)),
        ColorSequenceKeypoint.new(1, theme.panelBottom),
    })
    portraitGradient.Rotation = 90
    portraitGradient.Parent = portraitFrame

    local image = Instance.new("ImageLabel")
    image.Name = "PortraitImage"
    image.BackgroundTransparency = 1
    image.Position = UDim2.fromOffset(2, 2)
    image.Size = UDim2.fromOffset(28, 28)
    image.ScaleType = Enum.ScaleType.Crop
    image.Parent = portraitFrame

    local imageCorner = Instance.new("UICorner")
    imageCorner.CornerRadius = UDim.new(0, 10)
    imageCorner.Parent = image

    local fallback = Instance.new("TextLabel")
    fallback.Name = "Fallback"
    fallback.BackgroundTransparency = 1
    fallback.Size = UDim2.fromScale(1, 1)
    fallback.Font = Enum.Font.Garamond
    fallback.TextColor3 = accentColor:Lerp(theme.trimBright, 0.2)
    fallback.TextSize = 11
    fallback.TextStrokeTransparency = 0.3
    fallback.Text = "--"
    fallback.Parent = image

    return portraitFrame, image, fallback
end

local function setPortraitImage(
    imageLabel: ImageLabel,
    fallbackLabel: TextLabel,
    fighterId: string?,
    classId: string?
)
    local userId = if fighterId then tonumber(fighterId) else nil
    if userId then
        local cached = portraitCache[userId]
        if cached == nil then
            local ok, content = pcall(function()
                local thumbnail, _ = Players:GetUserThumbnailAsync(
                    userId,
                    Enum.ThumbnailType.HeadShot,
                    Enum.ThumbnailSize.Size150x150
                )
                return thumbnail
            end)
            cached = if ok and typeof(content) == "string" then content else ""
            portraitCache[userId] = cached
        end

        if cached ~= "" then
            imageLabel.Image = cached
            fallbackLabel.Visible = false
            return
        end
    end

    imageLabel.Image = ""
    fallbackLabel.Visible = true
    fallbackLabel.Text = string.upper(string.sub(classId or "?", 1, 2))
    fallbackLabel.TextColor3 = getClassTint(classId)
end

local function getPowerBarInfo(fighter: any)
    local maxHealth = math.max(tonumber(fighter.maxHealth) or 1, 1)
    local classColor = getClassTint(fighter.classId)
    local shieldValue = tonumber(fighter.shield) or 0

    if fighter.classId == "Rogue" then
        local focusValue = math.clamp(tonumber(fighter.focus) or 0, 0, Config.MaxFocus)
        return "Fokus",
            focusValue / math.max(Config.MaxFocus, 1),
            theme.focus,
            string.format("%d / %d Fokus", focusValue, Config.MaxFocus)
    end

    if shieldValue > 0.05 then
        return "Schild",
            math.clamp(shieldValue / maxHealth, 0, 1),
            Color3.fromRGB(92, 156, 255),
            string.format("Schild %d", math.floor(shieldValue))
    end

    if fighter.casting then
        local duration =
            math.max(fighter.casting.duration or fighter.casting.remaining or 0.01, 0.01)
        local remaining =
            math.max(0, (fighter.casting.remaining or 0) - (os.clock() - stateReceivedAt))
        return "Zauber",
            math.clamp(1 - remaining / duration, 0, 1),
            theme.cast,
            string.format(
                "%s %.1fs",
                fighter.casting.displayName or fighter.casting.abilityId,
                remaining
            )
    end

    if fighter.castLockedRemaining and fighter.castLockedRemaining > 0.05 then
        local remaining = tonumber(fighter.castLockedRemaining) or 0
        return "Sperre",
            math.clamp(remaining / 6, 0, 1),
            theme.locked,
            string.format("Gesperrt %.1fs", remaining)
    end

    return "Ressource",
        1,
        classColor,
        string.format(
            "%s bereit",
            tostring(
                (Config.Classes[fighter.classId] and Config.Classes[fighter.classId].displayName)
                    or fighter.classId
            )
        )
end

createPanelLabel("Klassenwahl", leftPanel, 12)

for _, classId in Config.ClassOrder do
    local classConfig = Config.Classes[classId]
    local button = createButton(classConfig.displayName, leftPanel, 15)
    classButtons[classId] = button
    button.Activated:Connect(function()
        animateButtonPress(button)
        selectedClass = classId
        classSelectEvent:FireServer(classId)
    end)
end

createPanelLabel("Matchmaking", leftPanel, 12)

local queueOneButton = createButton("1vs1 suchen", leftPanel, 16)
queueOneButton.Activated:Connect(function()
    animateButtonPress(queueOneButton)
    queueRequestEvent:FireServer("Duel1v1")
end)

local queueTwoButton = createButton("2vs2 suchen", leftPanel, 16)
queueTwoButton.Activated:Connect(function()
    animateButtonPress(queueTwoButton)
    queueRequestEvent:FireServer("Duel2v2")
end)

local botButton = createButton("1vsCOM Test", leftPanel, 16)
botButton.BackgroundColor3 = Color3.fromRGB(87, 61, 126)
botButton.Activated:Connect(function()
    animateButtonPress(botButton)
    queueRequestEvent:FireServer("Bot")
end)

-- ── GLADIUS-STYLE ARENA PANEL  (spec §5.1: enemies right side) ───────────────
local rightPanel = Instance.new("Frame")
rightPanel.Name = "TargetPanel"
rightPanel.AnchorPoint = Vector2.new(1, 0)
rightPanel.Position = UDim2.new(1, -8, 0, 124)
rightPanel.Size = UDim2.fromOffset(210, 320)
rightPanel.BackgroundColor3 = theme.panelMid
rightPanel.BackgroundTransparency = 0.04
rightPanel.BorderSizePixel = 0
rightPanel.Parent = root

local rightCorner = Instance.new("UICorner")
rightCorner.CornerRadius = UDim.new(0, 8)
rightCorner.Parent = rightPanel

applyPanelChrome(rightPanel, Color3.fromRGB(200, 60, 60))

local rightPadding = Instance.new("UIPadding")
rightPadding.PaddingTop = UDim.new(0, 6)
rightPadding.PaddingLeft = UDim.new(0, 5)
rightPadding.PaddingRight = UDim.new(0, 5)
rightPadding.Parent = rightPanel

local rightLayout = Instance.new("UIListLayout")
rightLayout.Padding = UDim.new(0, 4)
rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
rightLayout.Parent = rightPanel

createPanelLabel("Arena", rightPanel, 12)

local targetList = Instance.new("Frame")
targetList.Name = "TargetList"
targetList.BackgroundTransparency = 1
targetList.Size = UDim2.new(1, 0, 1, -16)
targetList.Parent = rightPanel

local targetLayout = Instance.new("UIListLayout")
targetLayout.Padding = UDim.new(0, 4)
targetLayout.SortOrder = Enum.SortOrder.LayoutOrder
targetLayout.Parent = targetList

local bottomBar = Instance.new("Frame")
bottomBar.Name = "AbilityBar"
bottomBar.AnchorPoint = Vector2.new(0.5, 1)
bottomBar.Position = UDim2.new(0.5, 0, 1, -6)
bottomBar.Size = UDim2.fromOffset(350, 47)
bottomBar.BackgroundColor3 = theme.panelMid
bottomBar.BackgroundTransparency = 0.03
bottomBar.BorderSizePixel = 0
bottomBar.Parent = root

local bottomCorner = Instance.new("UICorner")
bottomCorner.CornerRadius = UDim.new(0, 8)
bottomCorner.Parent = bottomBar

applyPanelChrome(bottomBar, theme.trim)

-- Wrap buttons in a nested frame so the UIListLayout only lays out ability
-- buttons and is not confused by the chrome decoration frames (Inset,
-- TopTrim, BottomTrim, Gem) that applyPanelChrome added to bottomBar.
local buttonRow = Instance.new("Frame")
buttonRow.Name = "ButtonRow"
buttonRow.BackgroundTransparency = 1
buttonRow.Size = UDim2.fromScale(1, 1)
buttonRow.ZIndex = 10
buttonRow.Parent = bottomBar

local bottomPadding = Instance.new("UIPadding")
bottomPadding.PaddingTop = UDim.new(0, 5)
bottomPadding.PaddingBottom = UDim.new(0, 5)
bottomPadding.PaddingLeft = UDim.new(0, 7)
bottomPadding.PaddingRight = UDim.new(0, 7)
bottomPadding.Parent = buttonRow

local abilityLayout = Instance.new("UIListLayout")
abilityLayout.FillDirection = Enum.FillDirection.Horizontal
abilityLayout.Padding = UDim.new(0, 5)
abilityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
abilityLayout.VerticalAlignment = Enum.VerticalAlignment.Center
abilityLayout.SortOrder = Enum.SortOrder.LayoutOrder
abilityLayout.Parent = buttonRow

for slot = 1, 4 do
    local button = createButton("", buttonRow, 92)
    button.Size = UDim2.fromOffset(82, 37)
    button.LayoutOrder = slot
    button.Text = ""
    abilityButtons[slot] = button

    local buttonStroke = button:FindFirstChildOfClass("UIStroke")

    local iconPanel = Instance.new("Frame")
    iconPanel.Name = "IconPanel"
    iconPanel.BackgroundColor3 = Color3.fromRGB(28, 21, 18)
    iconPanel.BorderSizePixel = 0
    iconPanel.Position = UDim2.fromOffset(3, 3)
    iconPanel.Size = UDim2.fromOffset(22, 22)
    iconPanel.ZIndex = 12
    iconPanel.Parent = button

    local iconCorner = Instance.new("UICorner")
    iconCorner.CornerRadius = UDim.new(0, 8)
    iconCorner.Parent = iconPanel

    addStroke(iconPanel, theme.trim, 1.5, 0.2)

    local iconLabel = Instance.new("TextLabel")
    iconLabel.Name = "IconLabel"
    iconLabel.BackgroundTransparency = 1
    iconLabel.Size = UDim2.fromScale(1, 1)
    iconLabel.Font = Enum.Font.Garamond
    iconLabel.TextColor3 = theme.trimBright
    iconLabel.TextSize = 10
    iconLabel.TextStrokeTransparency = 0.25
    iconLabel.Text = tostring(slot)
    iconLabel.ZIndex = 14
    iconLabel.Parent = iconPanel

    local iconImage = Instance.new("ImageLabel")
    iconImage.Name = "IconImage"
    iconImage.BackgroundTransparency = 1
    iconImage.Position = UDim2.fromOffset(2, 2)
    iconImage.Size = UDim2.fromOffset(19, 19)
    iconImage.ScaleType = Enum.ScaleType.Fit
    iconImage.ImageTransparency = 0
    iconImage.Visible = false
    iconImage.ZIndex = 13
    iconImage.Parent = iconPanel

    local keyCap = Instance.new("TextLabel")
    keyCap.Name = "KeyCap"
    keyCap.AnchorPoint = Vector2.new(1, 0)
    keyCap.Position = UDim2.new(1, -4, 0, 3)
    keyCap.Size = UDim2.fromOffset(13, 9)
    keyCap.BackgroundColor3 = theme.panelBottom
    keyCap.BorderSizePixel = 0
    keyCap.Font = Enum.Font.Garamond
    keyCap.TextColor3 = theme.panelText
    keyCap.TextSize = 7
    keyCap.Text = tostring(slot)
    keyCap.ZIndex = 12
    keyCap.Parent = button

    local keyCorner = Instance.new("UICorner")
    keyCorner.CornerRadius = UDim.new(0, 6)
    keyCorner.Parent = keyCap

    addStroke(keyCap, theme.trim, 1, 0.18)

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.BackgroundTransparency = 1
    nameLabel.Position = UDim2.fromOffset(29, 3)
    nameLabel.Size = UDim2.new(1, -48, 0, 11)
    nameLabel.Font = Enum.Font.Garamond
    nameLabel.TextColor3 = theme.trimBright
    nameLabel.TextSize = 9
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Text = "Fertigkeit"
    nameLabel.ZIndex = 12
    nameLabel.Parent = button

    local stateLabel = Instance.new("TextLabel")
    stateLabel.Name = "StateLabel"
    stateLabel.BackgroundTransparency = 1
    stateLabel.Position = UDim2.fromOffset(29, 15)
    stateLabel.Size = UDim2.new(1, -48, 0, 8)
    stateLabel.Font = Enum.Font.Garamond
    stateLabel.TextColor3 = theme.mutedText
    stateLabel.TextSize = 6
    stateLabel.TextXAlignment = Enum.TextXAlignment.Left
    stateLabel.Text = "Bereit"
    stateLabel.ZIndex = 12
    stateLabel.Parent = button

    local runeLabel = Instance.new("TextLabel")
    runeLabel.Name = "RuneLabel"
    runeLabel.BackgroundTransparency = 1
    runeLabel.Position = UDim2.new(1, -48, 0, 24)
    runeLabel.Size = UDim2.fromOffset(30, 8)
    runeLabel.Font = Enum.Font.Garamond
    runeLabel.TextColor3 = theme.trimBright
    runeLabel.TextSize = 6
    runeLabel.TextXAlignment = Enum.TextXAlignment.Right
    runeLabel.Text = ""
    runeLabel.ZIndex = 12
    runeLabel.Parent = button

    local cooldownOverlay = Instance.new("Frame")
    cooldownOverlay.Name = "CooldownOverlay"
    cooldownOverlay.BackgroundColor3 = Color3.fromRGB(8, 9, 12)
    cooldownOverlay.BackgroundTransparency = 0.24
    cooldownOverlay.BorderSizePixel = 0
    cooldownOverlay.Position = UDim2.fromOffset(0, 0)
    cooldownOverlay.Size = UDim2.fromScale(1, 0)
    cooldownOverlay.Visible = false
    cooldownOverlay.ZIndex = 15
    cooldownOverlay.Parent = button

    local cooldownOverlayCorner = Instance.new("UICorner")
    cooldownOverlayCorner.CornerRadius = UDim.new(0, 8)
    cooldownOverlayCorner.Parent = cooldownOverlay

    local cooldownText = Instance.new("TextLabel")
    cooldownText.Name = "CooldownText"
    cooldownText.BackgroundTransparency = 1
    cooldownText.Position = UDim2.fromOffset(0, 0)
    cooldownText.Size = UDim2.fromScale(1, 1)
    cooldownText.Font = Enum.Font.Garamond
    cooldownText.TextColor3 = Color3.fromRGB(255, 245, 214)
    cooldownText.TextSize = 12
    cooldownText.TextStrokeTransparency = 0.2
    cooldownText.Text = ""
    cooldownText.ZIndex = 16
    cooldownText.Parent = cooldownOverlay

    abilityVisuals[slot] = {
        nameLabel = nameLabel,
        stateLabel = stateLabel,
        runeLabel = runeLabel,
        cooldownOverlay = cooldownOverlay,
        cooldownText = cooldownText,
        iconLabel = iconLabel,
        iconImage = iconImage,
        iconPanel = iconPanel,
        keyCap = keyCap,
        stroke = buttonStroke,
    }

    button.Activated:Connect(function()
        animateButtonPress(button)
        local abilityId = Config.AbilityOrder[slot]
        if abilityId then
            abilityCastEvent:FireServer(abilityId)
        end
    end)
end

local castBar = Instance.new("Frame")
castBar.Name = "CastBar"
castBar.AnchorPoint = Vector2.new(0.5, 1)
castBar.Position = UDim2.new(0.5, 0, 1, -59)
castBar.Size = UDim2.fromOffset(200, 13)
castBar.BackgroundColor3 = theme.panelBottom
castBar.BackgroundTransparency = 0.05
castBar.BorderSizePixel = 0
castBar.Visible = false
castBar.Parent = root

local castCorner = Instance.new("UICorner")
castCorner.CornerRadius = UDim.new(0, 6)
castCorner.Parent = castBar

applyPanelChrome(castBar, theme.cast)

local castFill = Instance.new("Frame")
castFill.Name = "Fill"
castFill.BackgroundColor3 = Color3.fromRGB(214, 172, 72)
castFill.BorderSizePixel = 0
castFill.Size = UDim2.fromScale(0, 1)
castFill.Parent = castBar

local castFillCorner = Instance.new("UICorner")
castFillCorner.CornerRadius = UDim.new(0, 6)
castFillCorner.Parent = castFill

local castText = Instance.new("TextLabel")
castText.Name = "Label"
castText.BackgroundTransparency = 1
castText.Size = UDim2.fromScale(1, 1)
castText.Font = Enum.Font.GothamBold
castText.TextColor3 = Color3.fromRGB(255, 255, 255)
castText.TextSize = 7
castText.TextStrokeTransparency = 0.45
castText.Parent = castBar

local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "SystemMessage"
messageLabel.AnchorPoint = Vector2.new(0.5, 1)
messageLabel.Position = UDim2.new(0.5, 0, 1, -77)
messageLabel.Size = UDim2.fromOffset(280, 14)
messageLabel.BackgroundTransparency = 1
messageLabel.Font = Enum.Font.Garamond
messageLabel.TextColor3 = theme.trimBright
messageLabel.TextScaled = true
messageLabel.TextStrokeTransparency = 0.35
messageLabel.Text = ""
messageLabel.Parent = root

-- ── PHASE ANNOUNCEMENT BANNER  (WoW-style centre-screen overlay) ─────────────
local phaseAnnouncement = Instance.new("TextLabel")
phaseAnnouncement.Name = "PhaseAnnouncement"
phaseAnnouncement.AnchorPoint = Vector2.new(0.5, 0.5)
phaseAnnouncement.Position = UDim2.fromScale(0.5, 0.36)
phaseAnnouncement.Size = UDim2.fromOffset(380, 60)
phaseAnnouncement.BackgroundTransparency = 1
phaseAnnouncement.Font = Enum.Font.Garamond
phaseAnnouncement.TextColor3 = Color3.fromRGB(255, 220, 55)
phaseAnnouncement.TextSize = 44
phaseAnnouncement.TextStrokeTransparency = 0.05
phaseAnnouncement.TextStrokeColor3 = Color3.fromRGB(60, 28, 0)
phaseAnnouncement.Text = ""
phaseAnnouncement.TextTransparency = 1
phaseAnnouncement.ZIndex = 12
phaseAnnouncement.Parent = root

local phaseAnnouncementSub = Instance.new("TextLabel")
phaseAnnouncementSub.Name = "PhaseAnnouncementSub"
phaseAnnouncementSub.AnchorPoint = Vector2.new(0.5, 0.5)
phaseAnnouncementSub.Position = UDim2.fromScale(0.5, 0.45)
phaseAnnouncementSub.Size = UDim2.fromOffset(260, 23)
phaseAnnouncementSub.BackgroundTransparency = 1
phaseAnnouncementSub.Font = Enum.Font.Garamond
phaseAnnouncementSub.TextColor3 = Color3.fromRGB(240, 240, 240)
phaseAnnouncementSub.TextSize = 14
phaseAnnouncementSub.TextStrokeTransparency = 0.3
phaseAnnouncementSub.Text = ""
phaseAnnouncementSub.TextTransparency = 1
phaseAnnouncementSub.ZIndex = 12
phaseAnnouncementSub.Parent = root

-- ── SELF UNIT FRAME  (PvP spec §2.1: 220×68 player health frame) ─────────────
local selfFrame = Instance.new("Frame")
selfFrame.Name = "SelfFrame"
selfFrame.Position = UDim2.fromOffset(9, 8)
selfFrame.Size = UDim2.fromOffset(220, 68)
selfFrame.BackgroundColor3 = theme.panelMid
selfFrame.BackgroundTransparency = 0.04
selfFrame.BorderSizePixel = 0
selfFrame.Visible = false
selfFrame.Parent = root

local selfFrameCorner = Instance.new("UICorner")
selfFrameCorner.CornerRadius = UDim.new(0, 8)
selfFrameCorner.Parent = selfFrame

applyPanelChrome(selfFrame, theme.ready)

-- Left class-colour accent stripe
local selfAccentStripe = Instance.new("Frame")
selfAccentStripe.Name = "AccentStripe"
selfAccentStripe.BackgroundColor3 = theme.ready
selfAccentStripe.BackgroundTransparency = 0.18
selfAccentStripe.BorderSizePixel = 0
selfAccentStripe.Size = UDim2.fromOffset(3, 68)
selfAccentStripe.Parent = selfFrame

-- Circular portrait (48 × 48)
local selfPortraitFrame, selfPortraitImage, selfPortraitFallback =
    createPortrait(selfFrame, UDim2.fromOffset(5, 8), theme.ready)
selfPortraitFrame.Size = UDim2.fromOffset(48, 48)
selfPortraitImage.Size = UDim2.fromOffset(42, 42)

-- Player name (class colour, 11 px bold)
local selfNameLabel = Instance.new("TextLabel")
selfNameLabel.Name = "NameLabel"
selfNameLabel.BackgroundTransparency = 1
selfNameLabel.Position = UDim2.fromOffset(59, 4)
selfNameLabel.Size = UDim2.new(1, -68, 0, 13)
selfNameLabel.Font = Enum.Font.GothamBold
selfNameLabel.TextColor3 = theme.trimBright
selfNameLabel.TextSize = 11
selfNameLabel.TextStrokeTransparency = 0.2
selfNameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
selfNameLabel.TextXAlignment = Enum.TextXAlignment.Left
selfNameLabel.Text = "Spieler"
selfNameLabel.Parent = selfFrame

-- Class / role label (muted, 8 px)
local selfClassLabel = Instance.new("TextLabel")
selfClassLabel.Name = "ClassLabel"
selfClassLabel.BackgroundTransparency = 1
selfClassLabel.Position = UDim2.fromOffset(59, 18)
selfClassLabel.Size = UDim2.new(1, -68, 0, 9)
selfClassLabel.Font = Enum.Font.Gotham
selfClassLabel.TextColor3 = theme.mutedText
selfClassLabel.TextSize = 8
selfClassLabel.TextXAlignment = Enum.TextXAlignment.Left
selfClassLabel.Text = "Klasse"
selfClassLabel.Parent = selfFrame

-- HP bar (gradient-filled, 18 px tall)
local selfHealthBack = Instance.new("Frame")
selfHealthBack.Name = "HealthBack"
selfHealthBack.Position = UDim2.fromOffset(59, 29)
selfHealthBack.Size = UDim2.new(1, -68, 0, 18)
selfHealthBack.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
selfHealthBack.BackgroundTransparency = 0.40
selfHealthBack.BorderSizePixel = 0
selfHealthBack.Parent = selfFrame

do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 3)
    c.Parent = selfHealthBack
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(50, 50, 50)
    s.Thickness = 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = selfHealthBack
end

local selfHealthFill = Instance.new("Frame")
selfHealthFill.Name = "Fill"
selfHealthFill.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
selfHealthFill.BorderSizePixel = 0
selfHealthFill.Size = UDim2.fromScale(1, 1)
selfHealthFill.Parent = selfHealthBack

do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 3)
    c.Parent = selfHealthFill
end

local selfHPLabel = Instance.new("TextLabel")
selfHPLabel.Name = "HPLabel"
selfHPLabel.BackgroundTransparency = 1
selfHPLabel.Size = UDim2.fromScale(1, 1)
selfHPLabel.Font = Enum.Font.GothamBold
selfHPLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
selfHPLabel.TextStrokeTransparency = 0
selfHPLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
selfHPLabel.TextSize = 9
selfHPLabel.Text = ""
selfHPLabel.Parent = selfHealthBack

-- Resource bar (class-coloured, 5 px)
local selfResourceBack = Instance.new("Frame")
selfResourceBack.Name = "ResourceBack"
selfResourceBack.Position = UDim2.fromOffset(59, 49)
selfResourceBack.Size = UDim2.new(1, -68, 0, 5)
selfResourceBack.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
selfResourceBack.BackgroundTransparency = 0.40
selfResourceBack.BorderSizePixel = 0
selfResourceBack.Parent = selfFrame

do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 2)
    c.Parent = selfResourceBack
end

local selfResourceFill = Instance.new("Frame")
selfResourceFill.Name = "Fill"
selfResourceFill.BackgroundColor3 = theme.focus
selfResourceFill.BorderSizePixel = 0
selfResourceFill.Size = UDim2.fromScale(1, 1)
selfResourceFill.Parent = selfResourceBack

do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 2)
    c.Parent = selfResourceFill
end

local selfResourceLabel = Instance.new("TextLabel")
selfResourceLabel.Name = "ResourceLabel"
selfResourceLabel.BackgroundTransparency = 1
selfResourceLabel.Size = UDim2.fromScale(1, 1)
selfResourceLabel.Font = Enum.Font.Gotham
selfResourceLabel.TextColor3 = theme.panelText
selfResourceLabel.TextSize = 7
selfResourceLabel.TextStrokeTransparency = 0.35
selfResourceLabel.Text = ""
selfResourceLabel.Parent = selfResourceBack

-- Debuff icon row (3 × 12 px icons, bottom of frame)
local selfDebuffRow = Instance.new("Frame")
selfDebuffRow.Name = "DebuffRow"
selfDebuffRow.BackgroundTransparency = 1
selfDebuffRow.Position = UDim2.fromOffset(59, 57)
selfDebuffRow.Size = UDim2.new(1, -68, 0, 10)
selfDebuffRow.Parent = selfFrame
do
    local l = Instance.new("UIListLayout")
    l.FillDirection = Enum.FillDirection.Horizontal
    l.Padding = UDim.new(0, 2)
    l.VerticalAlignment = Enum.VerticalAlignment.Center
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = selfDebuffRow
end

local selfDebuffIcons: { Frame } = {}
for di = 1, 3 do
    local ico = Instance.new("Frame")
    ico.Name = "SelfDebuff" .. di
    ico.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    ico.BackgroundTransparency = 0.25
    ico.BorderSizePixel = 0
    ico.Size = UDim2.fromOffset(10, 10)
    ico.Visible = false
    ico.LayoutOrder = di
    ico.Parent = selfDebuffRow
    do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 2)
        c.Parent = ico
        local s = Instance.new("UIStroke")
        s.Color = Color3.fromRGB(80, 140, 255)
        s.Thickness = 1
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = ico
        local t = Instance.new("TextLabel")
        t.BackgroundTransparency = 1
        t.Size = UDim2.fromScale(1, 1)
        t.Font = Enum.Font.GothamBold
        t.TextColor3 = Color3.fromRGB(255, 255, 255)
        t.TextSize = 6
        t.Text = ""
        t.Parent = ico
    end
    selfDebuffIcons[di] = ico
end

-- Hidden compatibility label (kept so existing references don't error)
local selfEffectsLabel = Instance.new("TextLabel")
selfEffectsLabel.Name = "Effects"
selfEffectsLabel.BackgroundTransparency = 1
selfEffectsLabel.Position = UDim2.fromOffset(59, 58)
selfEffectsLabel.Size = UDim2.new(1, -68, 0, 7)
selfEffectsLabel.Font = Enum.Font.Garamond
selfEffectsLabel.TextColor3 = theme.mutedText
selfEffectsLabel.TextSize = 6
selfEffectsLabel.TextXAlignment = Enum.TextXAlignment.Left
selfEffectsLabel.Visible = false
selfEffectsLabel.Text = ""
selfEffectsLabel.Parent = selfFrame

-- ── TARGET UNIT FRAME  (PvP spec §2.2: 240×68, mirrored layout) ─────────────
local targetUnitFrame = Instance.new("Frame")
targetUnitFrame.Name = "TargetUnitFrame"
targetUnitFrame.AnchorPoint = Vector2.new(1, 0)
targetUnitFrame.Position = UDim2.new(1, -9, 0, 8)
targetUnitFrame.Size = UDim2.fromOffset(240, 68)
targetUnitFrame.BackgroundColor3 = theme.panelMid
targetUnitFrame.BackgroundTransparency = 0.04
targetUnitFrame.BorderSizePixel = 0
targetUnitFrame.Visible = false
targetUnitFrame.Parent = root

local targetFrameCorner = Instance.new("UICorner")
targetFrameCorner.CornerRadius = UDim.new(0, 8)
targetFrameCorner.Parent = targetUnitFrame

applyPanelChrome(targetUnitFrame, theme.health)

-- Right accent stripe (class-coloured)
local targetAccentStripe = Instance.new("Frame")
targetAccentStripe.Name = "AccentStripe"
targetAccentStripe.BackgroundColor3 = theme.health
targetAccentStripe.BackgroundTransparency = 0.2
targetAccentStripe.BorderSizePixel = 0
targetAccentStripe.Position = UDim2.fromOffset(237, 0)
targetAccentStripe.Size = UDim2.fromOffset(3, 68)
targetAccentStripe.Parent = targetUnitFrame

local targetAccentCorner = Instance.new("UICorner")
targetAccentCorner.CornerRadius = UDim.new(0, 8)
targetAccentCorner.Parent = targetAccentStripe

-- Circular portrait (48×48) on right side
local targetPortraitFrame, targetPortraitImage, targetPortraitFallback =
    createPortrait(targetUnitFrame, UDim2.fromOffset(183, 8), theme.health)
targetPortraitFrame.Size = UDim2.fromOffset(48, 48)
targetPortraitImage.Size = UDim2.fromOffset(42, 42)

-- Target name (class colour, 11 px bold)
local targetNameLabel = Instance.new("TextLabel")
targetNameLabel.Name = "NameLabel"
targetNameLabel.BackgroundTransparency = 1
targetNameLabel.Position = UDim2.fromOffset(9, 4)
targetNameLabel.Size = UDim2.new(1, -68, 0, 13)
targetNameLabel.Font = Enum.Font.GothamBold
targetNameLabel.TextColor3 = theme.trimBright
targetNameLabel.TextSize = 11
targetNameLabel.TextStrokeTransparency = 0.2
targetNameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
targetNameLabel.TextXAlignment = Enum.TextXAlignment.Left
targetNameLabel.Text = "Ziel"
targetNameLabel.Parent = targetUnitFrame

local targetClassLabel = Instance.new("TextLabel")
targetClassLabel.Name = "ClassLabel"
targetClassLabel.BackgroundTransparency = 1
targetClassLabel.Position = UDim2.fromOffset(9, 18)
targetClassLabel.Size = UDim2.new(1, -68, 0, 9)
targetClassLabel.Font = Enum.Font.Gotham
targetClassLabel.TextColor3 = theme.mutedText
targetClassLabel.TextSize = 8
targetClassLabel.TextXAlignment = Enum.TextXAlignment.Left
targetClassLabel.Text = "Klasse"
targetClassLabel.Parent = targetUnitFrame

-- HP bar (gradient fill, 18 px)
local targetHealthBack = Instance.new("Frame")
targetHealthBack.Name = "HealthBack"
targetHealthBack.Position = UDim2.fromOffset(9, 29)
targetHealthBack.Size = UDim2.new(1, -68, 0, 18)
targetHealthBack.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
targetHealthBack.BackgroundTransparency = 0.40
targetHealthBack.BorderSizePixel = 0
targetHealthBack.Parent = targetUnitFrame

do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 3)
    c.Parent = targetHealthBack
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(50, 50, 50)
    s.Thickness = 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = targetHealthBack
end

local targetHealthFill = Instance.new("Frame")
targetHealthFill.Name = "Fill"
targetHealthFill.BackgroundColor3 = theme.health
targetHealthFill.BorderSizePixel = 0
targetHealthFill.Size = UDim2.fromScale(1, 1)
targetHealthFill.Parent = targetHealthBack

do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 3)
    c.Parent = targetHealthFill
end

local targetHPLabel = Instance.new("TextLabel")
targetHPLabel.Name = "HPLabel"
targetHPLabel.BackgroundTransparency = 1
targetHPLabel.Size = UDim2.fromScale(1, 1)
targetHPLabel.Font = Enum.Font.GothamBold
targetHPLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
targetHPLabel.TextStrokeTransparency = 0
targetHPLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
targetHPLabel.TextSize = 9
targetHPLabel.Text = ""
targetHPLabel.Parent = targetHealthBack

-- Resource bar (5 px)
local targetResourceBack = Instance.new("Frame")
targetResourceBack.Name = "ResourceBack"
targetResourceBack.Position = UDim2.fromOffset(9, 49)
targetResourceBack.Size = UDim2.new(1, -68, 0, 5)
targetResourceBack.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
targetResourceBack.BackgroundTransparency = 0.40
targetResourceBack.BorderSizePixel = 0
targetResourceBack.Parent = targetUnitFrame

do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 2)
    c.Parent = targetResourceBack
end

local targetResourceFill = Instance.new("Frame")
targetResourceFill.Name = "Fill"
targetResourceFill.BackgroundColor3 = theme.mana
targetResourceFill.BorderSizePixel = 0
targetResourceFill.Size = UDim2.fromScale(1, 1)
targetResourceFill.Parent = targetResourceBack

do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 2)
    c.Parent = targetResourceFill
end

local targetResourceLabel = Instance.new("TextLabel")
targetResourceLabel.Name = "ResourceLabel"
targetResourceLabel.BackgroundTransparency = 1
targetResourceLabel.Size = UDim2.fromScale(1, 1)
targetResourceLabel.Font = Enum.Font.Gotham
targetResourceLabel.TextColor3 = theme.panelText
targetResourceLabel.TextSize = 7
targetResourceLabel.TextStrokeTransparency = 0.35
targetResourceLabel.Text = ""
targetResourceLabel.Parent = targetResourceBack

-- Debuff icon row (3 × 10 px icons, bottom)
local targetDebuffRow = Instance.new("Frame")
targetDebuffRow.Name = "DebuffRow"
targetDebuffRow.BackgroundTransparency = 1
targetDebuffRow.Position = UDim2.fromOffset(9, 57)
targetDebuffRow.Size = UDim2.new(1, -68, 0, 10)
targetDebuffRow.Parent = targetUnitFrame
do
    local l = Instance.new("UIListLayout")
    l.FillDirection = Enum.FillDirection.Horizontal
    l.Padding = UDim.new(0, 2)
    l.VerticalAlignment = Enum.VerticalAlignment.Center
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = targetDebuffRow
end

local targetDebuffIcons: { Frame } = {}
for di = 1, 3 do
    local ico = Instance.new("Frame")
    ico.Name = "TgtDebuff" .. di
    ico.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    ico.BackgroundTransparency = 0.25
    ico.BorderSizePixel = 0
    ico.Size = UDim2.fromOffset(10, 10)
    ico.Visible = false
    ico.LayoutOrder = di
    ico.Parent = targetDebuffRow
    do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 2)
        c.Parent = ico
        local s = Instance.new("UIStroke")
        s.Color = Color3.fromRGB(80, 140, 255)
        s.Thickness = 1
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = ico
        local t = Instance.new("TextLabel")
        t.BackgroundTransparency = 1
        t.Size = UDim2.fromScale(1, 1)
        t.Font = Enum.Font.GothamBold
        t.TextColor3 = Color3.fromRGB(255, 255, 255)
        t.TextSize = 6
        t.Text = ""
        t.Parent = ico
    end
    targetDebuffIcons[di] = ico
end

-- Target effects text (hidden, kept for compatibility)
local targetEffectsLabel = Instance.new("TextLabel")
targetEffectsLabel.Name = "Effects"
targetEffectsLabel.BackgroundTransparency = 1
targetEffectsLabel.Position = UDim2.fromOffset(9, 57)
targetEffectsLabel.Size = UDim2.new(1, -48, 0, 7)
targetEffectsLabel.Font = Enum.Font.Garamond
targetEffectsLabel.TextColor3 = theme.mutedText
targetEffectsLabel.TextSize = 6
targetEffectsLabel.TextXAlignment = Enum.TextXAlignment.Left
targetEffectsLabel.Visible = false
targetEffectsLabel.Text = ""
targetEffectsLabel.Parent = targetUnitFrame

-- Target cast bar (appears over resource bar when target is casting)
local targetCastBack = Instance.new("Frame")
targetCastBack.Name = "CastBack"
targetCastBack.Position = UDim2.fromOffset(9, 49)
targetCastBack.Size = UDim2.new(1, -68, 0, 14)
targetCastBack.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
targetCastBack.BackgroundTransparency = 0.28
targetCastBack.BorderSizePixel = 0
targetCastBack.Visible = false
targetCastBack.Parent = targetUnitFrame

do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 3)
    c.Parent = targetCastBack
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(80, 65, 15)
    s.Thickness = 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = targetCastBack
end

local targetCastFill = Instance.new("Frame")
targetCastFill.Name = "Fill"
targetCastFill.BackgroundColor3 = theme.cast
targetCastFill.BorderSizePixel = 0
targetCastFill.Size = UDim2.fromScale(0, 1)
targetCastFill.Parent = targetCastBack

do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 3)
    c.Parent = targetCastFill
end

local targetCastText = Instance.new("TextLabel")
targetCastText.Name = "CastText"
targetCastText.BackgroundTransparency = 1
targetCastText.Size = UDim2.fromScale(1, 1)
targetCastText.Font = Enum.Font.GothamBold
targetCastText.TextColor3 = Color3.fromRGB(255, 245, 200)
targetCastText.TextStrokeTransparency = 0.2
targetCastText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
targetCastText.TextSize = 8
targetCastText.Text = ""
targetCastText.Parent = targetCastBack

-- ── TARGET-OF-TARGET FRAME  (spec §2.2, 120×36 below target frame) ───────────
local totFrame = Instance.new("Frame")
totFrame.Name = "TotFrame"
totFrame.AnchorPoint = Vector2.new(1, 0)
totFrame.Position = UDim2.new(1, -9, 0, 82)
totFrame.Size = UDim2.fromOffset(130, 36)
totFrame.BackgroundColor3 = theme.panelMid
totFrame.BackgroundTransparency = 0.08
totFrame.BorderSizePixel = 0
totFrame.Visible = false
totFrame.Parent = root

do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = totFrame
    local s = Instance.new("UIStroke")
    s.Color = Color3.fromRGB(100, 70, 20)
    s.Thickness = 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = totFrame
end

-- Small arrow label pointing left
local totArrow = Instance.new("TextLabel")
totArrow.BackgroundTransparency = 1
totArrow.Position = UDim2.fromOffset(3, 0)
totArrow.Size = UDim2.fromOffset(10, 36)
totArrow.Font = Enum.Font.Gotham
totArrow.TextColor3 = theme.mutedText
totArrow.TextSize = 10
totArrow.Text = "▶"
totArrow.Parent = totFrame

local totNameLabel = Instance.new("TextLabel")
totNameLabel.Name = "TotName"
totNameLabel.BackgroundTransparency = 1
totNameLabel.Position = UDim2.fromOffset(16, 3)
totNameLabel.Size = UDim2.new(1, -20, 0, 12)
totNameLabel.Font = Enum.Font.GothamBold
totNameLabel.TextColor3 = theme.trimBright
totNameLabel.TextSize = 10
totNameLabel.TextXAlignment = Enum.TextXAlignment.Left
totNameLabel.Text = ""
totNameLabel.Parent = totFrame

local totHPBack = Instance.new("Frame")
totHPBack.Name = "TotHP"
totHPBack.Position = UDim2.fromOffset(16, 18)
totHPBack.Size = UDim2.new(1, -22, 0, 10)
totHPBack.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
totHPBack.BackgroundTransparency = 0.4
totHPBack.BorderSizePixel = 0
totHPBack.Parent = totFrame

do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 2)
    c.Parent = totHPBack
end

local totHPFill = Instance.new("Frame")
totHPFill.Name = "Fill"
totHPFill.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
totHPFill.BorderSizePixel = 0
totHPFill.Size = UDim2.fromScale(1, 1)
totHPFill.Parent = totHPBack

do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 2)
    c.Parent = totHPFill
end

local function tweenGuiTree(container: GuiObject, visible: boolean)
    local descendants = container:GetDescendants()
    table.insert(descendants, 1, container)

    if visible then
        container.Visible = true
    end

    for _, descendant in descendants do
        if descendant:IsA("GuiObject") then
            if descendant:GetAttribute("BaseBackgroundTransparency") == nil then
                descendant:SetAttribute(
                    "BaseBackgroundTransparency",
                    descendant.BackgroundTransparency
                )
            end

            local backgroundTarget = if visible
                then descendant:GetAttribute("BaseBackgroundTransparency") :: number
                else 1
            TweenService:Create(
                descendant,
                TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { BackgroundTransparency = backgroundTarget }
            ):Play()
        end

        if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
            if descendant:GetAttribute("BaseTextTransparency") == nil then
                descendant:SetAttribute("BaseTextTransparency", descendant.TextTransparency)
            end

            local textTarget = if visible
                then descendant:GetAttribute("BaseTextTransparency") :: number
                else 1
            TweenService:Create(
                descendant,
                TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { TextTransparency = textTarget }
            ):Play()
        end
    end

    if not visible then
        task.delay(0.24, function()
            if screenGui.Parent and container.BackgroundTransparency >= 0.98 then
                container.Visible = false
            end
        end)
    end
end

local function showSystemMessage(text: string)
    if messageTween then
        messageTween:Cancel()
        messageTween = nil
    end

    messageLabel.Text = text
    messageLabel.TextTransparency = 0
    messageLabel.TextStrokeTransparency = 0.35
    messageExpiresAt = os.clock() + 2.8
    messageFading = false
end

local function fadeSystemMessage()
    if messageLabel.Text == "" or messageFading then
        return
    end

    messageFading = true
    local tween = TweenService:Create(
        messageLabel,
        TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { TextTransparency = 1, TextStrokeTransparency = 1 }
    )
    messageTween = tween
    tween:Play()
    tween.Completed:Connect(function()
        if os.clock() >= messageExpiresAt then
            messageLabel.Text = ""
        end
    end)
end

local phaseAnnouncementTween: Tween? = nil
local function showPhaseAnnouncement(mainText: string, subText: string, holdDuration: number)
    if phaseAnnouncementTween then
        phaseAnnouncementTween:Cancel()
        phaseAnnouncementTween = nil
    end

    phaseAnnouncement.Text = mainText
    phaseAnnouncement.TextTransparency = 0
    phaseAnnouncement.TextStrokeTransparency = 0.05
    phaseAnnouncementSub.Text = subText
    phaseAnnouncementSub.TextTransparency = if subText ~= "" then 0 else 1
    phaseAnnouncementSub.TextStrokeTransparency = if subText ~= "" then 0.3 else 1

    task.delay(holdDuration, function()
        local t = TweenService:Create(
            phaseAnnouncement,
            TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 1, TextStrokeTransparency = 1 }
        )
        phaseAnnouncementTween = t
        t:Play()
        TweenService:Create(
            phaseAnnouncementSub,
            TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { TextTransparency = 1, TextStrokeTransparency = 1 }
        ):Play()
    end)
end

local function vectorFromPayload(position): Vector3?
    if typeof(position) ~= "table" then
        return nil
    end

    if
        typeof(position.x) ~= "number"
        or typeof(position.y) ~= "number"
        or typeof(position.z) ~= "number"
    then
        return nil
    end

    return Vector3.new(position.x, position.y, position.z)
end

local function getCombatTextColor(kind: string): Color3
    if kind == "Heal" then
        return Color3.fromRGB(96, 255, 148)
    elseif kind == "Absorb" or kind == "Shield" then
        return Color3.fromRGB(116, 211, 255)
    elseif kind == "Control" or kind == "Interrupt" then
        return Color3.fromRGB(214, 172, 255)
    elseif kind == "Cast" then
        return Color3.fromRGB(244, 205, 92)
    elseif kind == "Resist" then
        return Color3.fromRGB(210, 210, 218)
    end

    return Color3.fromRGB(255, 96, 88)
end

local function spawnCombatText(event)
    local position = vectorFromPayload(event.position)
    if not position then
        return
    end

    local anchor = Instance.new("Part")
    anchor.Name = "CombatTextAnchor"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.2, 0.2, 0.2)
    anchor.Position = position
        + Vector3.new(math.random(-18, 18) / 10, 3.8, math.random(-8, 8) / 10)
    anchor.Parent = workspace

    local billboard = Instance.new("BillboardGui")
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.fromOffset(180, 48)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
    billboard.Parent = anchor

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamBlack
    label.Text = tostring(event.text or event.kind)
    label.TextColor3 = getCombatTextColor(tostring(event.kind))
    label.TextScaled = true
    label.TextStrokeTransparency = 0.15
    label.Parent = billboard

    TweenService:Create(
        anchor,
        TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = anchor.Position + Vector3.new(0, 3.5, 0) }
    ):Play()
    TweenService:Create(
        label,
        TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { TextTransparency = 1, TextStrokeTransparency = 1 }
    ):Play()

    task.delay(1, function()
        anchor:Destroy()
    end)
end

local function getLocalFighter(state)
    if not state or state.kind ~= "Match" then
        return nil
    end

    for _, fighter in state.fighters do
        if fighter.id == state.localFighterId then
            return fighter
        end
    end

    return nil
end

local function updateClassButtons()
    for classId, button in classButtons do
        if classId == selectedClass then
            button.BackgroundColor3 = Color3.fromRGB(78, 112, 76)
        else
            button.BackgroundColor3 = Color3.fromRGB(48, 55, 66)
        end
    end
end

local function updateAbilityButtons()
    local classId = selectedClass
    local localFighter = getLocalFighter(currentState)
    if localFighter then
        classId = localFighter.classId
    end

    local classConfig = Config.Classes[classId]
    for slot, abilityId in Config.AbilityOrder do
        local button = abilityButtons[slot]
        local visuals = abilityVisuals[slot]
        local ability = classConfig.abilities[abilityId]
        local visualAsset = getAbilityVisualAsset(classId, abilityId, ability.displayName)
        local cooldownRemaining = 0
        if localFighter and localFighter.cooldowns and localFighter.cooldowns[abilityId] then
            cooldownRemaining = tonumber(localFighter.cooldowns[abilityId]) or 0
        end

        local iconText = visualAsset.glyph or string.upper(string.sub(ability.displayName, 1, 1))
        local baseAccent = getClassTint(classId)
        local stateText = if ability.castTime and ability.castTime > 0
            then string.format("Cast %.1fs", ability.castTime)
            elseif ability.radius then string.format("Radius %d", ability.radius)
            elseif ability.range then string.format("Reichweite %d", ability.range)
            else "Sofort"

        if visuals then
            visuals.nameLabel.Text = ability.displayName
            visuals.stateLabel.Text = stateText
            visuals.iconLabel.Text = iconText
            visuals.keyCap.Text = tostring(slot)
            visuals.runeLabel.Text = visualAsset.rune or ""

            local iconImage = visuals.iconImage
            if iconImage and iconImage:IsA("ImageLabel") then
                if typeof(visualAsset.image) == "string" and visualAsset.image ~= "" then
                    iconImage.Image = resolveAbilityImage(visualAsset.image)
                    iconImage.Visible = true
                    iconImage.ImageTransparency = 0.08
                    visuals.iconLabel.Visible = true
                    visuals.iconLabel.TextTransparency = 0.12
                    visuals.iconLabel.TextStrokeTransparency = 0.18
                else
                    iconImage.Image = ""
                    iconImage.Visible = false
                    visuals.iconLabel.Visible = true
                    visuals.iconLabel.TextTransparency = 0
                    visuals.iconLabel.TextStrokeTransparency = 0.25
                end
            end

            local iconPanel = visuals.iconPanel
            if iconPanel and iconPanel:IsA("Frame") then
                iconPanel.BackgroundColor3 = visualAsset.panelColor or theme.panelBottom
            end

            if visuals.iconLabel then
                visuals.iconLabel.TextColor3 = visualAsset.iconColor or theme.trimBright
            end
        end

        if
            localFighter
            and localFighter.casting
            and localFighter.casting.abilityId == abilityId
        then
            button.BackgroundColor3 = Color3.fromRGB(112, 82, 42)
            if visuals then
                visuals.stateLabel.Text = "Wirkt gerade"
                visuals.cooldownOverlay.Visible = false
                visuals.cooldownText.Text = ""
                if visuals.stroke then
                    visuals.stroke.Color = theme.cast
                end
            end
        elseif
            localFighter
            and localFighter.castLockedRemaining
            and localFighter.castLockedRemaining > 0.05
        then
            button.BackgroundColor3 = theme.locked
            if visuals then
                visuals.stateLabel.Text =
                    string.format("Gesperrt %.1fs", localFighter.castLockedRemaining)
                visuals.cooldownOverlay.Visible = false
                visuals.cooldownText.Text = ""
                if visuals.stroke then
                    visuals.stroke.Color = theme.locked:Lerp(theme.trimBright, 0.25)
                end
            end
        elseif cooldownRemaining > 0.05 then
            button.BackgroundColor3 = Color3.fromRGB(70, 56, 48)
            if visuals then
                local cooldownRatio =
                    math.clamp(cooldownRemaining / math.max(ability.cooldown, 0.05), 0, 1)
                visuals.stateLabel.Text = string.format("Bereit in %.1fs", cooldownRemaining)
                visuals.cooldownOverlay.Visible = true
                visuals.cooldownText.Text = string.format("%.1f", cooldownRemaining)
                TweenService
                    :Create(
                        visuals.cooldownOverlay,
                        TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                        { Size = UDim2.fromScale(1, cooldownRatio) }
                    )
                    :Play()
                if visuals.stroke then
                    visuals.stroke.Color = Color3.fromRGB(120, 108, 102)
                end
            end
        else
            button.BackgroundColor3 = Color3.fromRGB(67, 82, 58)
            if visuals then
                local detailText = if ability.consumeFocus and localFighter
                    then string.format("Fokus %d / %d", localFighter.focus or 0, Config.MaxFocus)
                    elseif ability.heal then string.format("Heilung %d", ability.heal)
                    elseif ability.damage then string.format("Schaden %d", ability.damage)
                    else stateText
                visuals.stateLabel.Text = detailText
                visuals.cooldownOverlay.Visible = false
                visuals.cooldownText.Text = ""
                visuals.cooldownOverlay.Size = UDim2.fromScale(1, 0)
                if visuals.stroke then
                    visuals.stroke.Color = baseAccent:Lerp(theme.trimBright, 0.2)
                end
            end
        end

        if visuals and not visuals.cooldownOverlay.Visible then
            visuals.cooldownOverlay.Size = UDim2.fromScale(1, 0)
        end
    end
end

local function updateCastBar()
    local localFighter = getLocalFighter(currentState)
    if not localFighter or not localFighter.casting then
        castBar.Visible = false
        return
    end

    local casting = localFighter.casting
    local duration = math.max(casting.duration or casting.remaining or 0.01, 0.01)
    local remaining = math.max(0, (casting.remaining or 0) - (os.clock() - stateReceivedAt))
    local progress = math.clamp(1 - remaining / duration, 0, 1)
    castBar.Visible = true
    castFill.Size = UDim2.fromScale(progress, 1)
    castText.Text = string.format("%s  %.1fs", casting.displayName or casting.abilityId, remaining)
end

local function makeTargetButton(fighter: any, localFighter: any)
    local button: TextButton? = targetButtons[fighter.id]
    if not button then
        local createdButton = createButton("", targetList, 92)
        button = createdButton
        -- Gladius-style entry: 198 × 88 px
        createdButton.Size = UDim2.fromOffset(198, 88)
        createdButton.Text = ""
        createdButton.TextXAlignment = Enum.TextXAlignment.Left
        createdButton.TextYAlignment = Enum.TextYAlignment.Top
        targetButtons[fighter.id] = createdButton
        createdButton.Activated:Connect(function()
            animateButtonPress(createdButton)
            selectedTargetId = fighter.id
            targetSelectEvent:FireServer(fighter.id)
        end)

        -- Class-colour badge (top-left, 14 × 14)
        local classBadge = Instance.new("Frame")
        classBadge.Name = "ClassBadge"
        classBadge.Position = UDim2.fromOffset(5, 5)
        classBadge.Size = UDim2.fromOffset(14, 14)
        classBadge.BackgroundColor3 = theme.trim
        classBadge.BorderSizePixel = 0
        classBadge.ZIndex = 12
        classBadge.Parent = createdButton
        do
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 3)
            c.Parent = classBadge
        end

        -- Portrait (36 × 36)
        local portraitFrame, portraitImage, _portraitFallback =
            createPortrait(createdButton, UDim2.fromOffset(4, 20), theme.trim)
        portraitFrame.Size = UDim2.fromOffset(36, 36)
        portraitImage.Size = UDim2.fromOffset(30, 30)

        -- Name label (class colour, 11 px)
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "NameLabel"
        nameLabel.BackgroundTransparency = 1
        nameLabel.Position = UDim2.fromOffset(44, 4)
        nameLabel.Size = UDim2.new(1, -52, 0, 12)
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextColor3 = theme.trimBright
        nameLabel.TextSize = 10
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.ZIndex = 12
        nameLabel.Parent = createdButton

        -- HP bar (150 × 16)
        local healthBack = Instance.new("Frame")
        healthBack.Name = "HealthBack"
        healthBack.Position = UDim2.fromOffset(44, 18)
        healthBack.Size = UDim2.new(1, -52, 0, 16)
        healthBack.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        healthBack.BackgroundTransparency = 0.4
        healthBack.BorderSizePixel = 0
        healthBack.ZIndex = 12
        healthBack.Parent = createdButton
        do
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 3)
            c.Parent = healthBack
            local s = Instance.new("UIStroke")
            s.Color = Color3.fromRGB(50, 50, 50)
            s.Thickness = 1
            s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            s.Parent = healthBack
        end

        local healthFill = Instance.new("Frame")
        healthFill.Name = "Fill"
        healthFill.BackgroundColor3 = Color3.fromRGB(0, 190, 60)
        healthFill.BorderSizePixel = 0
        healthFill.Size = UDim2.fromScale(1, 1)
        healthFill.ZIndex = 13
        healthFill.Parent = healthBack
        do
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 3)
            c.Parent = healthFill
        end

        local hpTextLabel = Instance.new("TextLabel")
        hpTextLabel.Name = "HPText"
        hpTextLabel.BackgroundTransparency = 1
        hpTextLabel.Size = UDim2.fromScale(1, 1)
        hpTextLabel.Font = Enum.Font.GothamBold
        hpTextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        hpTextLabel.TextStrokeTransparency = 0
        hpTextLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        hpTextLabel.TextSize = 9
        hpTextLabel.Text = ""
        hpTextLabel.ZIndex = 14
        hpTextLabel.Parent = healthBack

        -- Resource bar (5 px)
        local resBack = Instance.new("Frame")
        resBack.Name = "ResBack"
        resBack.Position = UDim2.fromOffset(44, 36)
        resBack.Size = UDim2.new(1, -52, 0, 5)
        resBack.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        resBack.BackgroundTransparency = 0.4
        resBack.BorderSizePixel = 0
        resBack.ZIndex = 12
        resBack.Parent = createdButton
        do
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 2)
            c.Parent = resBack
        end

        local resFill = Instance.new("Frame")
        resFill.Name = "Fill"
        resFill.BackgroundColor3 = theme.mana
        resFill.BorderSizePixel = 0
        resFill.Size = UDim2.fromScale(1, 1)
        resFill.ZIndex = 13
        resFill.Parent = resBack
        do
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 2)
            c.Parent = resFill
        end

        -- DR Tracker  (3 × 20 px squares: Stun / Fear / Root)
        local drRow = Instance.new("Frame")
        drRow.Name = "DRRow"
        drRow.BackgroundTransparency = 1
        drRow.Position = UDim2.fromOffset(44, 44)
        drRow.Size = UDim2.new(1, -52, 0, 20)
        drRow.ZIndex = 12
        drRow.Parent = createdButton
        do
            local l = Instance.new("UIListLayout")
            l.FillDirection = Enum.FillDirection.Horizontal
            l.Padding = UDim.new(0, 3)
            l.VerticalAlignment = Enum.VerticalAlignment.Center
            l.SortOrder = Enum.SortOrder.LayoutOrder
            l.Parent = drRow
        end

        local drCategories = { "Stun", "Fear", "Root" }
        for di, catName in drCategories do
            local drIcon = Instance.new("Frame")
            drIcon.Name = "DR_" .. catName
            drIcon.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            drIcon.BackgroundTransparency = 0.3
            drIcon.BorderSizePixel = 0
            drIcon.Size = UDim2.fromOffset(20, 20)
            drIcon.LayoutOrder = di
            drIcon.ZIndex = 13
            drIcon.Parent = drRow
            do
                local c = Instance.new("UICorner")
                c.CornerRadius = UDim.new(0, 4)
                c.Parent = drIcon

                local s = Instance.new("UIStroke")
                s.Color = Color3.fromRGB(200, 200, 200) -- white = no DR
                s.Thickness = 1.5
                s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                s.Name = "DRStroke"
                s.Parent = drIcon

                local drLabel = Instance.new("TextLabel")
                drLabel.Name = "DRLabel"
                drLabel.BackgroundTransparency = 1
                drLabel.Size = UDim2.fromScale(1, 1)
                drLabel.Font = Enum.Font.GothamBold
                drLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
                drLabel.TextSize = 7
                drLabel.Text = string.sub(catName, 1, 2)
                drLabel.ZIndex = 14
                drLabel.Parent = drIcon
            end
        end

        -- Cast bar (above the frame)
        local castBack = Instance.new("Frame")
        castBack.Name = "CastBack"
        castBack.Position = UDim2.fromOffset(44, 67)
        castBack.Size = UDim2.new(1, -52, 0, 10)
        castBack.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        castBack.BackgroundTransparency = 0.35
        castBack.BorderSizePixel = 0
        castBack.Visible = false
        castBack.ZIndex = 12
        castBack.Parent = createdButton
        do
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 2)
            c.Parent = castBack
            local s = Instance.new("UIStroke")
            s.Color = Color3.fromRGB(80, 65, 15)
            s.Thickness = 1
            s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            s.Parent = castBack
        end

        local castProgress = Instance.new("Frame")
        castProgress.Name = "Fill"
        castProgress.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
        castProgress.BorderSizePixel = 0
        castProgress.Size = UDim2.fromScale(0, 1)
        castProgress.ZIndex = 13
        castProgress.Parent = castBack
        do
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 2)
            c.Parent = castProgress
        end

        local castLabel = Instance.new("TextLabel")
        castLabel.Name = "CastLabel"
        castLabel.BackgroundTransparency = 1
        castLabel.Position = UDim2.fromOffset(3, 0)
        castLabel.Size = UDim2.new(1, -6, 1, 0)
        castLabel.Font = Enum.Font.Gotham
        castLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        castLabel.TextStrokeTransparency = 0.2
        castLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        castLabel.TextSize = 8
        castLabel.TextXAlignment = Enum.TextXAlignment.Left
        castLabel.Text = ""
        castLabel.ZIndex = 14
        castLabel.Parent = castBack

        -- Debuff icons row (right side, 3 × 16 px)
        local debuffRow = Instance.new("Frame")
        debuffRow.Name = "DebuffIcons"
        debuffRow.BackgroundTransparency = 1
        debuffRow.AnchorPoint = Vector2.new(1, 0)
        debuffRow.Position = UDim2.new(1, -2, 0, 20)
        debuffRow.Size = UDim2.fromOffset(18, 60)
        debuffRow.ZIndex = 12
        debuffRow.Parent = createdButton
        do
            local l = Instance.new("UIListLayout")
            l.FillDirection = Enum.FillDirection.Vertical
            l.Padding = UDim.new(0, 2)
            l.HorizontalAlignment = Enum.HorizontalAlignment.Center
            l.SortOrder = Enum.SortOrder.LayoutOrder
            l.Parent = debuffRow
        end
        for ei = 1, 3 do
            local dico = Instance.new("Frame")
            dico.Name = "Debuff" .. ei
            dico.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
            dico.BackgroundTransparency = 0.2
            dico.BorderSizePixel = 0
            dico.Size = UDim2.fromOffset(16, 16)
            dico.Visible = false
            dico.LayoutOrder = ei
            dico.ZIndex = 13
            dico.Parent = debuffRow
            do
                local c = Instance.new("UICorner")
                c.CornerRadius = UDim.new(0, 3)
                c.Parent = dico
                local s = Instance.new("UIStroke")
                s.Color = Color3.fromRGB(80, 140, 255)
                s.Thickness = 1
                s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                s.Parent = dico
                local t = Instance.new("TextLabel")
                t.BackgroundTransparency = 1
                t.Size = UDim2.fromScale(1, 1)
                t.Font = Enum.Font.GothamBold
                t.TextColor3 = Color3.fromRGB(255, 255, 255)
                t.TextSize = 6
                t.Text = ""
                t.ZIndex = 14
                t.Parent = dico
            end
        end
    end

    local targetButton = button :: TextButton
    local healthPercent = if fighter.maxHealth > 0 then fighter.health / fighter.maxHealth else 0
    local relation = if localFighter and fighter.team == localFighter.team then "Team" else "Gegner"

    -- Class badge colour
    local classBadge = targetButton:FindFirstChild("ClassBadge") :: Frame?
    if classBadge then
        classBadge.BackgroundColor3 = getClassTint(fighter.classId)
    end

    -- Portrait
    local portraitFrame = targetButton:FindFirstChild("Portrait")
    local portraitImage = if portraitFrame then portraitFrame:FindFirstChild("PortraitImage") else nil
    local portraitFallback = if portraitImage then portraitImage:FindFirstChild("Fallback") else nil
    if portraitImage and portraitImage:IsA("ImageLabel") and portraitFallback and portraitFallback:IsA("TextLabel") then
        setPortraitImage(portraitImage, portraitFallback, fighter.id, fighter.classId)
    end

    -- Name (class colour)
    local nameLabel = targetButton:FindFirstChild("NameLabel") :: TextLabel?
    if nameLabel then
        nameLabel.Text = tostring(fighter.name or "?")
        nameLabel.TextColor3 = getClassTint(fighter.classId)
    end

    -- HP bar gradient fill
    local healthBack = targetButton:FindFirstChild("HealthBack")
    local healthFill = if healthBack then healthBack:FindFirstChild("Fill") else nil
    local hpText = if healthBack then healthBack:FindFirstChild("HPText") else nil
    if healthFill and healthFill:IsA("Frame") then
        local fillColor = if healthPercent > 0.5
            then Color3.fromRGB(math.floor(200 * (1 - healthPercent) * 2), 190, 0)
            elseif healthPercent > 0 then Color3.fromRGB(200, math.floor(200 * healthPercent * 2), 0)
            else Color3.fromRGB(80, 80, 80)
        TweenService:Create(
            healthFill,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Size = UDim2.fromScale(math.clamp(healthPercent, 0, 1), 1), BackgroundColor3 = fillColor }
        ):Play()
    end
    if hpText and hpText:IsA("TextLabel") then
        hpText.Text = string.format("%d / %d  %d%%", fighter.health, fighter.maxHealth, math.floor(healthPercent * 100))
    end

    -- Resource bar
    local resBack = targetButton:FindFirstChild("ResBack")
    local resFill = if resBack then resBack:FindFirstChild("Fill") else nil
    if resFill and resFill:IsA("Frame") then
        local _, resPct, resClr, _ = getPowerBarInfo(fighter)
        TweenService:Create(
            resFill,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Size = UDim2.fromScale(resPct, 1), BackgroundColor3 = resClr }
        ):Play()
    end

    -- DR tracker (Stun / Fear / Root)
    local drRow = targetButton:FindFirstChild("DRRow") :: Frame?
    if drRow and fighter.dr then
        local DR_COLORS = {
            none   = Color3.fromRGB(200, 200, 200),
            first  = Color3.fromRGB(255, 220, 0),
            second = Color3.fromRGB(255, 130, 0),
            immune = Color3.fromRGB(255, 60, 60),
        }
        for _, catName in { "Stun", "Fear", "Root" } do
            local drIcon = drRow:FindFirstChild("DR_" .. catName) :: Frame?
            if drIcon then
                local drData = fighter.dr and fighter.dr[catName]
                local stroke = drIcon:FindFirstChild("DRStroke") :: UIStroke?
                if stroke then
                    stroke.Color = DR_COLORS.none
                    if drData then
                        if drData.count >= 3 then
                            stroke.Color = DR_COLORS.immune
                        elseif drData.count == 2 then
                            stroke.Color = DR_COLORS.second
                        elseif drData.count == 1 then
                            stroke.Color = DR_COLORS.first
                        end
                    end
                end
            end
        end
    end

    -- Debuff icons
    local debuffRow = targetButton:FindFirstChild("DebuffIcons") :: Frame?
    if debuffRow then
        local effects = fighter.effects or {}
        for ei = 1, 3 do
            local dico = debuffRow:FindFirstChild("Debuff" .. ei) :: Frame?
            if not dico then continue end
            local eff = (effects :: { any })[ei]
            if eff then
                dico.Visible = true
                local t = dico:FindFirstChildOfClass("TextLabel")
                if t then
                    t.Text = string.upper(string.sub(tostring(eff.name or "?"), 1, 2))
                end
            else
                dico.Visible = false
            end
        end
    end

    -- Cast bar
    local castBack = targetButton:FindFirstChild("CastBack")
    local castProgress = if castBack then castBack:FindFirstChild("Fill") else nil
    local castLabel = if castBack then castBack:FindFirstChild("CastLabel") else nil
    if castBack and castBack:IsA("Frame") and castProgress and castProgress:IsA("Frame") then
        if fighter.casting then
            local dur = math.max(fighter.casting.duration or 0.01, 0.01)
            local rem = math.max(0, (fighter.casting.remaining or 0) - (os.clock() - stateReceivedAt))
            castBack.Visible = true
            castProgress.Size = UDim2.fromScale(math.clamp(1 - rem / dur, 0, 1), 1)
            if castLabel and castLabel:IsA("TextLabel") then
                castLabel.Text = string.format(
                    "%s  %.1fs",
                    tostring(fighter.casting.displayName or fighter.casting.abilityId or ""),
                    rem
                )
            end
        else
            castBack.Visible = false
            if castLabel and castLabel:IsA("TextLabel") then
                castLabel.Text = ""
            end
        end
    end

    -- Frame background colour by relation / selection / death
    if selectedTargetId == fighter.id then
        targetButton.BackgroundColor3 = Color3.fromRGB(110, 72, 30)
    elseif relation == "Team" then
        targetButton.BackgroundColor3 = Color3.fromRGB(34, 68, 56)
    elseif healthPercent <= 0 then
        targetButton.BackgroundColor3 = Color3.fromRGB(38, 38, 42)
    else
        targetButton.BackgroundColor3 = Color3.fromRGB(72, 34, 34)
    end
end

local function updateTargets()
    if not currentState or currentState.kind ~= "Match" then
        for _, button in targetButtons do
            button:Destroy()
        end
        table.clear(targetButtons)
        return
    end

    local localFighter = getLocalFighter(currentState)
    if localFighter and localFighter.targetId then
        selectedTargetId = localFighter.targetId
    end

    local seenTargets = {}
    for _, fighter in currentState.fighters do
        seenTargets[fighter.id] = true
        makeTargetButton(fighter, localFighter)
    end

    for fighterId, button in targetButtons do
        if not seenTargets[fighterId] then
            button:Destroy()
            targetButtons[fighterId] = nil
        end
    end
end

local function updateTimer()
    if not currentState then
        timerLabel.Text = "Waehle Klasse und Matchmodus"
        return
    end

    if currentState.kind == "Lobby" then
        local queuedMode = currentState.queuedMode
        if queuedMode then
            local modeConfig = Config.MatchModes[queuedMode]
            timerLabel.Text = string.format("Warteschlange: %s", modeConfig.displayName)
        elseif currentState.activeMatch then
            timerLabel.Text = "Arena besetzt"
        else
            timerLabel.Text = "Waehle Klasse und Matchmodus"
        end
    elseif currentState.phase == "Preparing" then
        timerLabel.Text = string.format("Tore oeffnen in %02d", currentState.countdown or 0)
    elseif currentState.phase == "Active" then
        timerLabel.Text = "Kampf aktiv"
    elseif currentState.phase == "Finished" then
        timerLabel.Text = string.format("Team %d gewinnt", currentState.winnerTeam or 0)
    end
end

local function updatePanelVisibility()
    local inMatch = currentState and currentState.kind == "Match"
    tweenGuiTree(leftPanel, not inMatch)
    tweenGuiTree(rightPanel, inMatch)
    tweenGuiTree(bottomBar, true)
    tweenGuiTree(castBar, inMatch and castBar.Visible)
    -- selfFrame and targetUnitFrame/totFrame are managed by their update functions
    if not inMatch then
        selfFrame.Visible = false
        targetUnitFrame.Visible = false
        totFrame.Visible = false
    end
end

local function processCombatEvents()
    if not currentState or currentState.kind ~= "Match" or not currentState.combatEvents then
        return
    end

    local localFighterId = currentState.localFighterId
    for _, event in currentState.combatEvents do
        if typeof(event.id) == "number" and not seenCombatEvents[event.id] then
            seenCombatEvents[event.id] = true
            spawnCombatText(event)

            if localFighterId and event.targetId == localFighterId and event.kind == "Damage" then
                local amount = tonumber(event.amount) or 0
                local impulse = math.clamp(0.35 + amount / 80, 0.4, 1.6)
                if impulse > cameraShakeIntensity then
                    cameraShakeIntensity = impulse
                    cameraShakeSeed = os.clock()
                end
            end
        end
    end
end

local function updateSelfFrame()
    local localFighter = getLocalFighter(currentState)
    if not localFighter then
        selfFrame.Visible = false
        return
    end

    selfFrame.Visible = true
    selfNameLabel.Text = tostring(localFighter.name or "Spieler")
    selfNameLabel.TextColor3 = getClassTint(localFighter.classId)
    selfClassLabel.Text = tostring(localFighter.className or localFighter.classId or "?")

    local hpNum: number = tonumber(localFighter.health) or 0
    local maxNum: number = tonumber(localFighter.maxHealth) or 1
    local hpPct = math.clamp(hpNum / math.max(maxNum, 1), 0, 1)
    local hpColor: Color3
    if hpPct > 0.5 then
        hpColor = Color3.fromRGB(math.floor(200 * (1 - hpPct) * 2), 200, 0)
    elseif hpPct > 0 then
        hpColor = Color3.fromRGB(200, math.floor(200 * hpPct * 2), 0)
    else
        hpColor = Color3.fromRGB(60, 60, 60)
    end
    TweenService:Create(
        selfHealthFill,
        TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = UDim2.fromScale(hpPct, 1), BackgroundColor3 = hpColor }
    ):Play()
    selfHPLabel.Text = string.format(
        "%d / %d  %d%%",
        math.floor(hpNum),
        math.floor(maxNum),
        math.floor(hpPct * 100)
    )
    setPortraitImage(selfPortraitImage, selfPortraitFallback, localFighter.id, localFighter.classId)
    selfPortraitFrame.BackgroundColor3 =
        getClassTint(localFighter.classId):Lerp(theme.panelBottom, 0.8)
    selfAccentStripe.BackgroundColor3 = getClassTint(localFighter.classId)

    local _, resourcePct, resourceColor, resourceText = getPowerBarInfo(localFighter)
    TweenService:Create(
        selfResourceFill,
        TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = UDim2.fromScale(resourcePct, 1), BackgroundColor3 = resourceColor }
    ):Play()
    selfResourceLabel.Text = resourceText

    -- Update debuff icon row
    local effects = localFighter.effects or {}
    for di = 1, 3 do
        local ico = selfDebuffIcons[di]
        if not ico then continue end
        local eff = (effects :: { any })[di]
        if eff then
            ico.Visible = true
            local t = ico:FindFirstChildOfClass("TextLabel")
            if t then
                t.Text = string.upper(string.sub(tostring(eff.name or "?"), 1, 2))
            end
        else
            ico.Visible = false
        end
    end
end

local function updateTargetUnitFrame()
    if not currentState or currentState.kind ~= "Match" or not selectedTargetId then
        targetUnitFrame.Visible = false
        totFrame.Visible = false
        return
    end

    local targetFighter = nil
    for _, fighter in currentState.fighters do
        if fighter.id == selectedTargetId then
            targetFighter = fighter
            break
        end
    end

    if not targetFighter then
        targetUnitFrame.Visible = false
        totFrame.Visible = false
        return
    end

    targetUnitFrame.Visible = true
    targetNameLabel.Text = tostring(targetFighter.name or "Ziel")
    targetNameLabel.TextColor3 = getClassTint(targetFighter.classId)
    targetClassLabel.Text = tostring(targetFighter.className or targetFighter.classId or "?")
    setPortraitImage(
        targetPortraitImage,
        targetPortraitFallback,
        targetFighter.id,
        targetFighter.classId
    )
    targetPortraitFrame.BackgroundColor3 =
        getClassTint(targetFighter.classId):Lerp(theme.panelBottom, 0.82)
    targetAccentStripe.BackgroundColor3 =
        getClassTint(targetFighter.classId):Lerp(theme.health, 0.55)

    local hpNum: number = tonumber(targetFighter.health) or 0
    local maxNum: number = tonumber(targetFighter.maxHealth) or 1
    local hpPct = math.clamp(hpNum / math.max(maxNum, 1), 0, 1)
    local hpColor: Color3
    if hpPct > 0.5 then
        hpColor = Color3.fromRGB(math.floor(200 * (1 - hpPct) * 2), 200, 0)
    elseif hpPct > 0 then
        hpColor = Color3.fromRGB(200, math.floor(200 * hpPct * 2), 0)
    else
        hpColor = Color3.fromRGB(60, 60, 60)
    end
    TweenService:Create(
        targetHealthFill,
        TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = UDim2.fromScale(hpPct, 1), BackgroundColor3 = hpColor }
    ):Play()
    targetHPLabel.Text = string.format(
        "%d / %d  %d%%",
        math.floor(hpNum),
        math.floor(maxNum),
        math.floor(hpPct * 100)
    )

    local _, resourcePct, resourceColor, resourceText = getPowerBarInfo(targetFighter)
    TweenService:Create(
        targetResourceFill,
        TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = UDim2.fromScale(resourcePct, 1), BackgroundColor3 = resourceColor }
    ):Play()
    targetResourceLabel.Text = resourceText

    -- Debuff icons
    local effects = targetFighter.effects or {}
    for di = 1, 3 do
        local ico = targetDebuffIcons[di]
        if not ico then continue end
        local eff = (effects :: { any })[di]
        if eff then
            ico.Visible = true
            local t = ico:FindFirstChildOfClass("TextLabel")
            if t then
                t.Text = string.upper(string.sub(tostring(eff.name or "?"), 1, 2))
            end
        else
            ico.Visible = false
        end
    end

    -- Cast bar
    if targetFighter.casting then
        local duration = math.max(targetFighter.casting.duration or 0.01, 0.01)
        local remaining =
            math.max(0, (targetFighter.casting.remaining or 0) - (os.clock() - stateReceivedAt))
        targetCastBack.Visible = true
        targetCastFill.Size = UDim2.fromScale(math.clamp(1 - remaining / duration, 0, 1), 1)
        targetCastText.Text = string.format(
            "Zaubert: %s  %.1fs",
            tostring(targetFighter.casting.displayName or targetFighter.casting.abilityId),
            remaining
        )
    else
        targetCastBack.Visible = false
        targetCastText.Text = ""
    end

    -- ── Target-of-Target frame ────────────────────────────────────────────
    local totTargetId = targetFighter.targetId
    local totFighter: any = nil
    if totTargetId then
        for _, f in currentState.fighters do
            if f.id == totTargetId then
                totFighter = f
                break
            end
        end
    end

    if totFighter then
        totFrame.Visible = true
        totNameLabel.Text = tostring(totFighter.name or "?")
        totNameLabel.TextColor3 = getClassTint(totFighter.classId)
        local totHpPct = math.clamp(
            (tonumber(totFighter.health) or 0) / math.max(tonumber(totFighter.maxHealth) or 1, 1),
            0, 1
        )
        local totColor: Color3
        if totHpPct > 0.5 then
            totColor = Color3.fromRGB(math.floor(200 * (1 - totHpPct) * 2), 200, 0)
        elseif totHpPct > 0 then
            totColor = Color3.fromRGB(200, math.floor(200 * totHpPct * 2), 0)
        else
            totColor = Color3.fromRGB(60, 60, 60)
        end
        TweenService:Create(
            totHPFill,
            TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Size = UDim2.fromScale(totHpPct, 1), BackgroundColor3 = totColor }
        ):Play()
    else
        totFrame.Visible = false
    end
end

local function render()
    updateClassButtons()
    updateAbilityButtons()
    updateCastBar()
    updateTargets()
    updateTimer()
    updatePanelVisibility()
    updateSelfFrame()
    updateTargetUnitFrame()
    processCombatEvents()
end

stateUpdateEvent.OnClientEvent:Connect(function(state)
    local previousKind = currentState and currentState.kind
    local previousPhase = currentState and currentState.phase
    currentState = state
    stateReceivedAt = os.clock()
    if state.kind == "Lobby" then
        selectedClass = state.selectedClass or selectedClass
        if previousKind == "Match" then
            studioAutoQueueRequested = false
        end
        requestStudioAutoQueue()
    elseif state.kind == "Match" then
        -- Phase transition announcements
        if previousPhase ~= "Active" and state.phase == "Active" then
            showPhaseAnnouncement("FIGHT!", "", 1.8)
        elseif state.phase == "Preparing" and previousKind ~= "Match" then
            showPhaseAnnouncement("VORBEREITUNGSPHASE", "Vorbereitung laeuft...", 2.6)
        elseif state.phase == "Finished" and previousPhase ~= "Finished" then
            local winTeam: number = state.winnerTeam or 0
            local winText = if winTeam == 1 then "TEAM 1 SIEGT!" else "TEAM 2 SIEGT!"
            showPhaseAnnouncement(winText, "Rueckkehr zur Lobby...", 4.0)
        end
    end
    render()
end)

systemMessageEvent.OnClientEvent:Connect(function(text: string)
    showSystemMessage(text)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end

    if input.KeyCode == Enum.KeyCode.One then
        animateButtonPress(abilityButtons[1])
        abilityCastEvent:FireServer("Ability1")
    elseif input.KeyCode == Enum.KeyCode.Two then
        animateButtonPress(abilityButtons[2])
        abilityCastEvent:FireServer("Ability2")
    elseif input.KeyCode == Enum.KeyCode.Three then
        animateButtonPress(abilityButtons[3])
        abilityCastEvent:FireServer("Ability3")
    elseif input.KeyCode == Enum.KeyCode.Four then
        animateButtonPress(abilityButtons[4])
        abilityCastEvent:FireServer("Ability4")
    elseif input.KeyCode == Enum.KeyCode.T and currentState and currentState.kind == "Match" then
        local localFighter = getLocalFighter(currentState)
        if not localFighter then
            return
        end

        local enemies = {}
        for _, fighter in currentState.fighters do
            if fighter.team ~= localFighter.team and fighter.health > 0 then
                table.insert(enemies, fighter)
            end
        end

        if #enemies > 0 then
            local nextIndex = 1
            for index, fighter in enemies do
                if fighter.id == selectedTargetId then
                    nextIndex = if index == #enemies then 1 else index + 1
                    break
                end
            end

            selectedTargetId = enemies[nextIndex].id
            targetSelectEvent:FireServer(selectedTargetId)
        end
    end
end)

task.spawn(function()
    while screenGui.Parent do
        if messageLabel.Text ~= "" and os.clock() > messageExpiresAt then
            fadeSystemMessage()
        end
        updateAbilityButtons()
        updateCastBar()
        updateTargetUnitFrame()
        updatePanelVisibility()
        task.wait(0.2)
    end
end)

local function getLocalHumanoid(): Humanoid?
    local character = player.Character
    if not character then
        return nil
    end

    return character:FindFirstChildOfClass("Humanoid")
end

RunService.Heartbeat:Connect(function(deltaTime)
    if cameraShakeIntensity <= 0.001 then
        cameraShakeIntensity = 0
        local humanoid = getLocalHumanoid()
        if humanoid and humanoid.CameraOffset.Magnitude > 0.001 then
            humanoid.CameraOffset = Vector3.zero
        end
        return
    end

    local humanoid = getLocalHumanoid()
    if not humanoid then
        cameraShakeIntensity = 0
        return
    end

    local t = (os.clock() - cameraShakeSeed) * 38
    local offset = Vector3.new(
        math.sin(t * 1.7) * cameraShakeIntensity,
        math.sin(t * 2.3 + 1.2) * cameraShakeIntensity * 0.6,
        math.sin(t * 1.1 + 2.4) * cameraShakeIntensity * 0.4
    )
    humanoid.CameraOffset = offset
    cameraShakeIntensity = math.max(0, cameraShakeIntensity - deltaTime * 4.5)
end)

render()
