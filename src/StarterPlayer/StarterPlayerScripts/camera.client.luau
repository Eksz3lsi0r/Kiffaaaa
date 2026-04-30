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
    queueRequestEvent:FireServer(studioAutoQueueMode)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ArenaDuelGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)
root.Parent = screenGui

local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.AnchorPoint = Vector2.new(0.5, 0)
topBar.Position = UDim2.fromScale(0.5, 0.03)
topBar.Size = UDim2.fromOffset(620, 86)
topBar.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
topBar.BackgroundTransparency = 0.08
topBar.BorderSizePixel = 0
topBar.Parent = root

local topCorner = Instance.new("UICorner")
topCorner.CornerRadius = UDim.new(0, 8)
topCorner.Parent = topBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.fromOffset(16, 8)
titleLabel.Size = UDim2.new(1, -32, 0, 28)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextScaled = true
titleLabel.Text = "Vor Lobby Matchmaking"
titleLabel.Parent = topBar

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "Timer"
timerLabel.BackgroundTransparency = 1
timerLabel.Position = UDim2.fromOffset(16, 42)
timerLabel.Size = UDim2.new(1, -32, 0, 30)
timerLabel.Font = Enum.Font.GothamBold
timerLabel.TextColor3 = Color3.fromRGB(244, 205, 92)
timerLabel.TextScaled = true
timerLabel.Text = "Waehle Klasse und Matchmodus"
timerLabel.Parent = topBar

local leftPanel = Instance.new("Frame")
leftPanel.Name = "LobbyPanel"
leftPanel.Position = UDim2.fromOffset(18, 130)
leftPanel.Size = UDim2.fromOffset(280, 360)
leftPanel.BackgroundColor3 = Color3.fromRGB(20, 23, 28)
leftPanel.BackgroundTransparency = 0.08
leftPanel.BorderSizePixel = 0
leftPanel.Parent = root

local leftCorner = Instance.new("UICorner")
leftCorner.CornerRadius = UDim.new(0, 8)
leftCorner.Parent = leftPanel

local leftLayout = Instance.new("UIListLayout")
leftLayout.Padding = UDim.new(0, 8)
leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
leftLayout.Parent = leftPanel

local leftPadding = Instance.new("UIPadding")
leftPadding.PaddingTop = UDim.new(0, 12)
leftPadding.PaddingLeft = UDim.new(0, 12)
leftPadding.PaddingRight = UDim.new(0, 12)
leftPadding.Parent = leftPanel

local function createPanelLabel(text: string, parent: Instance, height: number): TextLabel
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 0, height)
    label.Font = Enum.Font.GothamBold
    label.TextColor3 = Color3.fromRGB(235, 238, 245)
    label.TextSize = 18
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = text
    label.Parent = parent
    return label
end

local function createButton(text: string, parent: Instance, height: number): TextButton
    local button = Instance.new("TextButton")
    button.AutoButtonColor = true
    button.Size = UDim2.new(1, 0, 0, height)
    button.BackgroundColor3 = Color3.fromRGB(48, 55, 66)
    button.BorderSizePixel = 0
    button.Font = Enum.Font.GothamBold
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextSize = 15
    button.TextWrapped = true
    button.Text = text
    button.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = button

    return button
end

createPanelLabel("Klassenwahl", leftPanel, 24)

for _, classId in Config.ClassOrder do
    local classConfig = Config.Classes[classId]
    local button = createButton(classConfig.displayName, leftPanel, 38)
    classButtons[classId] = button
    button.Activated:Connect(function()
        selectedClass = classId
        classSelectEvent:FireServer(classId)
    end)
end

createPanelLabel("Matchmaking", leftPanel, 24)

local queueOneButton = createButton("1vs1 suchen", leftPanel, 42)
queueOneButton.Activated:Connect(function()
    queueRequestEvent:FireServer("Duel1v1")
end)

local queueTwoButton = createButton("2vs2 suchen", leftPanel, 42)
queueTwoButton.Activated:Connect(function()
    queueRequestEvent:FireServer("Duel2v2")
end)

local botButton = createButton("1vsCOM Test", leftPanel, 42)
botButton.BackgroundColor3 = Color3.fromRGB(87, 61, 126)
botButton.Activated:Connect(function()
    queueRequestEvent:FireServer("Bot")
end)

local rightPanel = Instance.new("Frame")
rightPanel.Name = "TargetPanel"
rightPanel.AnchorPoint = Vector2.new(1, 0)
rightPanel.Position = UDim2.new(1, -18, 0, 130)
rightPanel.Size = UDim2.fromOffset(330, 380)
rightPanel.BackgroundColor3 = Color3.fromRGB(20, 23, 28)
rightPanel.BackgroundTransparency = 0.08
rightPanel.BorderSizePixel = 0
rightPanel.Parent = root

local rightCorner = Instance.new("UICorner")
rightCorner.CornerRadius = UDim.new(0, 8)
rightCorner.Parent = rightPanel

local rightPadding = Instance.new("UIPadding")
rightPadding.PaddingTop = UDim.new(0, 12)
rightPadding.PaddingLeft = UDim.new(0, 12)
rightPadding.PaddingRight = UDim.new(0, 12)
rightPadding.Parent = rightPanel

local rightLayout = Instance.new("UIListLayout")
rightLayout.Padding = UDim.new(0, 8)
rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
rightLayout.Parent = rightPanel

createPanelLabel("Ziele", rightPanel, 24)

local targetList = Instance.new("Frame")
targetList.Name = "TargetList"
targetList.BackgroundTransparency = 1
targetList.Size = UDim2.new(1, 0, 1, -36)
targetList.Parent = rightPanel

local targetLayout = Instance.new("UIListLayout")
targetLayout.Padding = UDim.new(0, 6)
targetLayout.SortOrder = Enum.SortOrder.LayoutOrder
targetLayout.Parent = targetList

local bottomBar = Instance.new("Frame")
bottomBar.Name = "AbilityBar"
bottomBar.AnchorPoint = Vector2.new(0.5, 1)
bottomBar.Position = UDim2.new(0.5, 0, 1, -24)
bottomBar.Size = UDim2.fromOffset(680, 96)
bottomBar.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
bottomBar.BackgroundTransparency = 0.08
bottomBar.BorderSizePixel = 0
bottomBar.Parent = root

local bottomCorner = Instance.new("UICorner")
bottomCorner.CornerRadius = UDim.new(0, 8)
bottomCorner.Parent = bottomBar

local abilityLayout = Instance.new("UIListLayout")
abilityLayout.FillDirection = Enum.FillDirection.Horizontal
abilityLayout.Padding = UDim.new(0, 10)
abilityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
abilityLayout.VerticalAlignment = Enum.VerticalAlignment.Center
abilityLayout.SortOrder = Enum.SortOrder.LayoutOrder
abilityLayout.Parent = bottomBar

for slot = 1, 4 do
    local button = createButton(tostring(slot), bottomBar, 72)
    button.Size = UDim2.fromOffset(150, 72)
    button.LayoutOrder = slot
    abilityButtons[slot] = button
    button.Activated:Connect(function()
        local abilityId = Config.AbilityOrder[slot]
        if abilityId then
            abilityCastEvent:FireServer(abilityId)
        end
    end)
end

local castBar = Instance.new("Frame")
castBar.Name = "CastBar"
castBar.AnchorPoint = Vector2.new(0.5, 1)
castBar.Position = UDim2.new(0.5, 0, 1, -128)
castBar.Size = UDim2.fromOffset(420, 30)
castBar.BackgroundColor3 = Color3.fromRGB(13, 15, 18)
castBar.BackgroundTransparency = 0.12
castBar.BorderSizePixel = 0
castBar.Visible = false
castBar.Parent = root

local castCorner = Instance.new("UICorner")
castCorner.CornerRadius = UDim.new(0, 6)
castCorner.Parent = castBar

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
castText.TextSize = 15
castText.TextStrokeTransparency = 0.45
castText.Parent = castBar

local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "SystemMessage"
messageLabel.AnchorPoint = Vector2.new(0.5, 1)
messageLabel.Position = UDim2.new(0.5, 0, 1, -164)
messageLabel.Size = UDim2.fromOffset(680, 32)
messageLabel.BackgroundTransparency = 1
messageLabel.Font = Enum.Font.GothamBold
messageLabel.TextColor3 = Color3.fromRGB(255, 242, 188)
messageLabel.TextScaled = true
messageLabel.TextStrokeTransparency = 0.35
messageLabel.Text = ""
messageLabel.Parent = root

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
    messageTween = TweenService:Create(
        messageLabel,
        TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { TextTransparency = 1, TextStrokeTransparency = 1 }
    )
    messageTween:Play()
    messageTween.Completed:Connect(function()
        if os.clock() >= messageExpiresAt then
            messageLabel.Text = ""
        end
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
        local ability = classConfig.abilities[abilityId]
        local cooldownRemaining = 0
        if localFighter and localFighter.cooldowns and localFighter.cooldowns[abilityId] then
            cooldownRemaining = localFighter.cooldowns[abilityId]
        end

        if
            localFighter
            and localFighter.casting
            and localFighter.casting.abilityId == abilityId
        then
            button.BackgroundColor3 = Color3.fromRGB(135, 103, 45)
            button.Text = string.format("%d\n%s\nCASTING", slot, ability.displayName)
        elseif
            localFighter
            and localFighter.castLockedRemaining
            and localFighter.castLockedRemaining > 0.05
        then
            button.BackgroundColor3 = Color3.fromRGB(92, 48, 54)
            button.Text = string.format(
                "%d\n%s\nLock %.1fs",
                slot,
                ability.displayName,
                localFighter.castLockedRemaining
            )
        elseif cooldownRemaining > 0.05 then
            button.BackgroundColor3 = Color3.fromRGB(74, 74, 82)
            button.Text =
                string.format("%d\n%s\n%.1fs", slot, ability.displayName, cooldownRemaining)
        else
            button.BackgroundColor3 = Color3.fromRGB(57, 82, 121)
            local focusText = if ability.consumeFocus and localFighter
                then string.format("\n%d Focus", localFighter.focus or 0)
                else ""
            button.Text = string.format("%d\n%s%s", slot, ability.displayName, focusText)
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

local function makeTargetButton(fighter, localFighter)
    local button = targetButtons[fighter.id]
    if not button then
        button = createButton("", targetList, 78)
        button.TextXAlignment = Enum.TextXAlignment.Left
        button.TextYAlignment = Enum.TextYAlignment.Top
        button.TextSize = 14
        targetButtons[fighter.id] = button
        button.Activated:Connect(function()
            selectedTargetId = fighter.id
            targetSelectEvent:FireServer(fighter.id)
        end)

        local padding = Instance.new("UIPadding")
        padding.PaddingTop = UDim.new(0, 7)
        padding.PaddingLeft = UDim.new(0, 10)
        padding.PaddingRight = UDim.new(0, 10)
        padding.Parent = button

        local healthBack = Instance.new("Frame")
        healthBack.Name = "HealthBack"
        healthBack.AnchorPoint = Vector2.new(0.5, 1)
        healthBack.Position = UDim2.new(0.5, 0, 1, -8)
        healthBack.Size = UDim2.new(1, -20, 0, 8)
        healthBack.BackgroundColor3 = Color3.fromRGB(36, 38, 44)
        healthBack.BorderSizePixel = 0
        healthBack.Parent = button

        local healthFill = Instance.new("Frame")
        healthFill.Name = "Fill"
        healthFill.BackgroundColor3 = Color3.fromRGB(91, 202, 118)
        healthFill.BorderSizePixel = 0
        healthFill.Size = UDim2.fromScale(1, 1)
        healthFill.Parent = healthBack

        local effectsLabel = Instance.new("TextLabel")
        effectsLabel.Name = "Effects"
        effectsLabel.BackgroundTransparency = 1
        effectsLabel.Position = UDim2.fromOffset(10, 39)
        effectsLabel.Size = UDim2.new(1, -20, 0, 16)
        effectsLabel.Font = Enum.Font.GothamBold
        effectsLabel.TextColor3 = Color3.fromRGB(190, 210, 255)
        effectsLabel.TextSize = 11
        effectsLabel.TextXAlignment = Enum.TextXAlignment.Left
        effectsLabel.Text = ""
        effectsLabel.Parent = button

        local castBack = Instance.new("Frame")
        castBack.Name = "CastBack"
        castBack.AnchorPoint = Vector2.new(0.5, 1)
        castBack.Position = UDim2.new(0.5, 0, 1, -19)
        castBack.Size = UDim2.new(1, -20, 0, 5)
        castBack.BackgroundColor3 = Color3.fromRGB(36, 38, 44)
        castBack.BorderSizePixel = 0
        castBack.Visible = false
        castBack.Parent = button

        local castProgress = Instance.new("Frame")
        castProgress.Name = "Fill"
        castProgress.BackgroundColor3 = Color3.fromRGB(244, 205, 92)
        castProgress.BorderSizePixel = 0
        castProgress.Size = UDim2.fromScale(0, 1)
        castProgress.Parent = castBack
    end

    local healthPercent = if fighter.maxHealth > 0 then fighter.health / fighter.maxHealth else 0
    local relation = if localFighter and fighter.team == localFighter.team then "Team" else "Gegner"
    local targetMarker = if selectedTargetId == fighter.id then " >" else ""
    button.Text = string.format(
        "%s%s\n%s | %d/%d HP",
        fighter.name,
        targetMarker,
        relation,
        fighter.health,
        fighter.maxHealth
    )

    local healthBack = button:FindFirstChild("HealthBack")
    local healthFill = if healthBack then healthBack:FindFirstChild("Fill") else nil
    if healthFill and healthFill:IsA("Frame") then
        local fillColor = if healthPercent <= 0.35
            then Color3.fromRGB(230, 76, 68)
            else Color3.fromRGB(91, 202, 118)
        healthFill.BackgroundColor3 = fillColor
        TweenService:Create(
            healthFill,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Size = UDim2.fromScale(math.clamp(healthPercent, 0, 1), 1) }
        ):Play()
    end

    local effectsLabel = button:FindFirstChild("Effects")
    if effectsLabel and effectsLabel:IsA("TextLabel") then
        local effectTexts = {}
        for _, effect in fighter.effects or {} do
            table.insert(effectTexts, string.format("%s %.0fs", effect.name, effect.remaining or 0))
        end
        effectsLabel.Text = table.concat(effectTexts, "  ")
    end

    local castBack = button:FindFirstChild("CastBack")
    local castProgress = if castBack then castBack:FindFirstChild("Fill") else nil
    if castBack and castBack:IsA("Frame") and castProgress and castProgress:IsA("Frame") then
        if fighter.casting then
            local duration =
                math.max(fighter.casting.duration or fighter.casting.remaining or 0.01, 0.01)
            local remaining =
                math.max(0, (fighter.casting.remaining or 0) - (os.clock() - stateReceivedAt))
            castBack.Visible = true
            castProgress.Size = UDim2.fromScale(math.clamp(1 - remaining / duration, 0, 1), 1)
        else
            castBack.Visible = false
        end
    end

    if selectedTargetId == fighter.id then
        button.BackgroundColor3 = Color3.fromRGB(126, 83, 58)
    elseif relation == "Team" then
        button.BackgroundColor3 = Color3.fromRGB(54, 86, 72)
    elseif healthPercent <= 0 then
        button.BackgroundColor3 = Color3.fromRGB(45, 45, 48)
    else
        button.BackgroundColor3 = Color3.fromRGB(92, 54, 54)
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
    tweenGuiTree(bottomBar, inMatch)
    tweenGuiTree(castBar, inMatch and castBar.Visible)
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

local function render()
    updateClassButtons()
    updateAbilityButtons()
    updateCastBar()
    updateTargets()
    updateTimer()
    updatePanelVisibility()
    processCombatEvents()
end

stateUpdateEvent.OnClientEvent:Connect(function(state)
    currentState = state
    stateReceivedAt = os.clock()
    if state.kind == "Lobby" then
        selectedClass = state.selectedClass or selectedClass
        requestStudioAutoQueue()
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
        abilityCastEvent:FireServer("Ability1")
    elseif input.KeyCode == Enum.KeyCode.Two then
        abilityCastEvent:FireServer("Ability2")
    elseif input.KeyCode == Enum.KeyCode.Three then
        abilityCastEvent:FireServer("Ability3")
    elseif input.KeyCode == Enum.KeyCode.Four then
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
