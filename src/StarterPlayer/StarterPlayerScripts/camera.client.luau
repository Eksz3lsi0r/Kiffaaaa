local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local messageExpiresAt = 0
local studioAutoQueueRequested = false

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

local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "SystemMessage"
messageLabel.AnchorPoint = Vector2.new(0.5, 1)
messageLabel.Position = UDim2.new(0.5, 0, 1, -130)
messageLabel.Size = UDim2.fromOffset(680, 32)
messageLabel.BackgroundTransparency = 1
messageLabel.Font = Enum.Font.GothamBold
messageLabel.TextColor3 = Color3.fromRGB(255, 242, 188)
messageLabel.TextScaled = true
messageLabel.Text = ""
messageLabel.Parent = root

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

        if cooldownRemaining > 0.05 then
            button.BackgroundColor3 = Color3.fromRGB(74, 74, 82)
            button.Text =
                string.format("%d\n%s\n%.1fs", slot, ability.displayName, cooldownRemaining)
        else
            button.BackgroundColor3 = Color3.fromRGB(57, 82, 121)
            button.Text = string.format("%d\n%s", slot, ability.displayName)
        end
    end
end

local function makeTargetButton(fighter, localFighter)
    local button = targetButtons[fighter.id]
    if not button then
        button = createButton("", targetList, 54)
        targetButtons[fighter.id] = button
        button.Activated:Connect(function()
            selectedTargetId = fighter.id
            targetSelectEvent:FireServer(fighter.id)
        end)
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
    for _, button in targetButtons do
        button:Destroy()
    end
    table.clear(targetButtons)

    if not currentState or currentState.kind ~= "Match" then
        return
    end

    local localFighter = getLocalFighter(currentState)
    if localFighter and localFighter.targetId then
        selectedTargetId = localFighter.targetId
    end

    for _, fighter in currentState.fighters do
        makeTargetButton(fighter, localFighter)
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

local function render()
    updateClassButtons()
    updateAbilityButtons()
    updateTargets()
    updateTimer()
end

stateUpdateEvent.OnClientEvent:Connect(function(state)
    currentState = state
    if state.kind == "Lobby" then
        selectedClass = state.selectedClass or selectedClass
        requestStudioAutoQueue()
    end
    render()
end)

systemMessageEvent.OnClientEvent:Connect(function(text: string)
    messageLabel.Text = text
    messageExpiresAt = os.clock() + 4
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
            messageLabel.Text = ""
        end
        updateAbilityButtons()
        task.wait(0.2)
    end
end)

render()
