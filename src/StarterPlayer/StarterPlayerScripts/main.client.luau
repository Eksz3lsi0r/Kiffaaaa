--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = require(ReplicatedStorage.Shared)
local MatchConfig = Shared.MatchConfig
local Elements = Shared.Elements

type ElementName = "Earth" | "Air" | "Fire" | "Water"

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

type ArenaState = {
    Status: string,
    ArenaReady: boolean,
    QueueCount: number,
    Mode: string?,
    BestOf: number,
    RoundsToWin: number,
    Countdown: number,
    Message: string,
    Viewer: any,
    Cooldowns: {
        Primary: number,
        Secondary: number,
        Ultimate: number,
    },
    Match: any,
}

local remoteFolder = ReplicatedStorage:WaitForChild(MatchConfig.RemoteFolderName, 20)
if remoteFolder == nil then
    warn("[client] arena remotes missing")
    return
end

local stateEvent = remoteFolder:WaitForChild(MatchConfig.StateEventName) :: RemoteEvent
local chooseElementEvent =
    remoteFolder:WaitForChild(MatchConfig.ChooseElementEventName) :: RemoteEvent
local chooseLoadoutEvent =
    remoteFolder:WaitForChild(MatchConfig.ChooseLoadoutEventName) :: RemoteEvent
local castAbilityEvent = remoteFolder:WaitForChild(MatchConfig.CastAbilityEventName) :: RemoteEvent
local requestStateFunction =
    remoteFolder:WaitForChild(MatchConfig.RequestStateFunctionName) :: RemoteFunction

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ElementalArenaHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

local function stylePanel(frame: Frame, topColor: Color3, bottomColor: Color3)
    frame.BackgroundColor3 = topColor
    frame.BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 18)
    corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Transparency = 0.8
    stroke.Thickness = 1
    stroke.Parent = frame
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, topColor),
        ColorSequenceKeypoint.new(1, bottomColor),
    })
    gradient.Rotation = 115
    gradient.Parent = frame
end

local function createLabel(
    parent: Instance,
    name: string,
    text: string,
    size: UDim2,
    position: UDim2,
    textSize: number,
    transparency: number?
): TextLabel
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = transparency or 1
    label.Size = size
    label.Position = position
    label.Font = Enum.Font.GothamBold
    label.Text = text
    label.TextColor3 = Color3.fromRGB(246, 239, 228)
    label.TextSize = textSize
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.Parent = parent
    return label
end

local function createButton(parent: Instance, name: string, size: UDim2): TextButton
    local button = Instance.new("TextButton")
    button.Name = name
    button.Size = size
    button.AutoButtonColor = false
    button.BackgroundColor3 = Color3.fromRGB(44, 47, 53)
    button.Text = ""
    button.BorderSizePixel = 0
    button.Parent = parent
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 16)
    corner.Parent = button
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Transparency = 0.84
    stroke.Parent = button
    return button
end

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = screenGui

local uiScale = Instance.new("UIScale")
uiScale.Scale = 0.78
uiScale.Parent = root

local titlePanel = Instance.new("Frame")
titlePanel.Name = "TitlePanel"
titlePanel.Size = UDim2.fromOffset(360, 88)
titlePanel.Position = UDim2.fromOffset(28, 24)
stylePanel(titlePanel, Color3.fromRGB(29, 32, 37), Color3.fromRGB(68, 52, 43))
titlePanel.Parent = root

createLabel(
    titlePanel,
    "Title",
    "Elemental Arena",
    UDim2.fromOffset(320, 30),
    UDim2.fromOffset(20, 16),
    28
)
local subtitle = createLabel(
    titlePanel,
    "Subtitle",
    "Erde, Luft, Feuer und Wasser im serverautoritativen Best of 5.",
    UDim2.fromOffset(320, 40),
    UDim2.fromOffset(20, 48),
    13
)
subtitle.Font = Enum.Font.Gotham
subtitle.TextTransparency = 0.08

local statusPanel = Instance.new("Frame")
statusPanel.Name = "StatusPanel"
statusPanel.Size = UDim2.fromOffset(360, 200)
statusPanel.Position = UDim2.fromOffset(28, 130)
stylePanel(statusPanel, Color3.fromRGB(36, 40, 48), Color3.fromRGB(20, 23, 29))
statusPanel.Parent = root

local statusTitle = createLabel(
    statusPanel,
    "StatusTitle",
    "Status",
    UDim2.fromOffset(320, 24),
    UDim2.fromOffset(20, 18),
    22
)
local statusBody = createLabel(
    statusPanel,
    "StatusBody",
    "Warte auf Serverzustand...",
    UDim2.fromOffset(320, 78),
    UDim2.fromOffset(20, 54),
    18
)
statusBody.Font = Enum.Font.GothamMedium
local viewerStats = createLabel(
    statusPanel,
    "ViewerStats",
    "",
    UDim2.fromOffset(320, 72),
    UDim2.fromOffset(20, 130),
    14
)
viewerStats.Font = Enum.Font.Gotham

local scoreboardPanel = Instance.new("Frame")
scoreboardPanel.Name = "ScoreboardPanel"
scoreboardPanel.Size = UDim2.fromOffset(420, 252)
scoreboardPanel.Position = UDim2.new(1, -448, 0, 24)
stylePanel(scoreboardPanel, Color3.fromRGB(31, 35, 42), Color3.fromRGB(17, 20, 24))
scoreboardPanel.Parent = root

local scoreboardTitle = createLabel(
    scoreboardPanel,
    "ScoreboardTitle",
    "Duellstand",
    UDim2.fromOffset(380, 26),
    UDim2.fromOffset(20, 18),
    22
)
local countdownLabel = createLabel(
    scoreboardPanel,
    "Countdown",
    "",
    UDim2.fromOffset(380, 22),
    UDim2.fromOffset(20, 50),
    14
)
countdownLabel.Font = Enum.Font.Gotham

local cardContainer = Instance.new("Frame")
cardContainer.Name = "CardContainer"
cardContainer.BackgroundTransparency = 1
cardContainer.Size = UDim2.fromOffset(380, 154)
cardContainer.Position = UDim2.fromOffset(20, 82)
cardContainer.Parent = scoreboardPanel

local cardLayout = Instance.new("UIListLayout")
cardLayout.FillDirection = Enum.FillDirection.Vertical
cardLayout.Padding = UDim.new(0, 12)
cardLayout.Parent = cardContainer

local playerCards = {} :: { any }
for index = 1, 2 do
    local card = Instance.new("Frame")
    card.Name = "PlayerCard" .. index
    card.Size = UDim2.fromOffset(380, 70)
    stylePanel(card, Color3.fromRGB(55, 60, 69), Color3.fromRGB(29, 34, 43))
    card.Parent = cardContainer

    local nameLabel = createLabel(
        card,
        "Name",
        "Warte auf Spieler",
        UDim2.fromOffset(230, 22),
        UDim2.fromOffset(16, 12),
        18
    )
    local scoreLabel = createLabel(
        card,
        "Score",
        "0 Siege",
        UDim2.fromOffset(100, 22),
        UDim2.fromOffset(260, 12),
        18
    )
    local detailLabel = createLabel(
        card,
        "Detail",
        "Noch kein aktives Duell.",
        UDim2.fromOffset(348, 30),
        UDim2.fromOffset(16, 38),
        13
    )
    detailLabel.Font = Enum.Font.Gotham
    playerCards[index] = {
        Frame = card,
        NameLabel = nameLabel,
        ScoreLabel = scoreLabel,
        DetailLabel = detailLabel,
    }
end

local controlsPanel = Instance.new("Frame")
controlsPanel.Name = "ControlsPanel"
controlsPanel.Size = UDim2.fromOffset(420, 136)
controlsPanel.Position = UDim2.new(1, -448, 1, -164)
stylePanel(controlsPanel, Color3.fromRGB(34, 39, 47), Color3.fromRGB(18, 20, 24))
controlsPanel.Parent = root

createLabel(
    controlsPanel,
    "ControlsTitle",
    "Faehigkeiten",
    UDim2.fromOffset(380, 24),
    UDim2.fromOffset(20, 16),
    22
)
local controlsHint = createLabel(
    controlsPanel,
    "ControlsHint",
    "Q / E / R wirken deine freigeschalteten Skills.",
    UDim2.fromOffset(380, 18),
    UDim2.fromOffset(20, 46),
    13
)
controlsHint.Font = Enum.Font.Gotham

local cooldownRow = Instance.new("Frame")
cooldownRow.Name = "CooldownRow"
cooldownRow.BackgroundTransparency = 1
cooldownRow.Size = UDim2.fromOffset(380, 48)
cooldownRow.Position = UDim2.fromOffset(20, 76)
cooldownRow.Parent = controlsPanel

local cooldownLayout = Instance.new("UIListLayout")
cooldownLayout.FillDirection = Enum.FillDirection.Horizontal
cooldownLayout.Padding = UDim.new(0, 10)
cooldownLayout.Parent = cooldownRow

local cooldownLabels = {} :: { [string]: TextLabel }
for _, slotName in ipairs({ "Primary", "Secondary", "Ultimate" }) do
    local chip = Instance.new("Frame")
    chip.Name = slotName .. "Chip"
    chip.Size = UDim2.fromOffset(120, 48)
    stylePanel(chip, Color3.fromRGB(59, 67, 82), Color3.fromRGB(23, 28, 37))
    chip.Parent = cooldownRow

    local label =
        createLabel(chip, "Label", slotName, UDim2.fromOffset(98, 30), UDim2.fromOffset(14, 10), 15)
    label.Font = Enum.Font.GothamMedium
    cooldownLabels[slotName] = label
end

local selectionPanel = Instance.new("Frame")
selectionPanel.Name = "SelectionPanel"
selectionPanel.Size = UDim2.fromScale(0.62, 0.26)
selectionPanel.Position = UDim2.new(0.19, 0, 1, -216)
stylePanel(selectionPanel, Color3.fromRGB(26, 29, 33), Color3.fromRGB(49, 38, 30))
selectionPanel.Parent = root

createLabel(
    selectionPanel,
    "SelectionTitle",
    "Waehle dein Element",
    UDim2.new(1, -32, 0, 24),
    UDim2.fromOffset(16, 14),
    24
)
local selectionHint = createLabel(
    selectionPanel,
    "SelectionHint",
    "Jedes Element spielt sich sichtbar anders. Deine Wahl bleibt fuer kommende Matches gespeichert.",
    UDim2.new(1, -32, 0, 22),
    UDim2.fromOffset(16, 46),
    13
)
selectionHint.Font = Enum.Font.Gotham

local loadoutPanel = Instance.new("Frame")
loadoutPanel.Name = "LoadoutPanel"
loadoutPanel.Size = UDim2.fromOffset(360, 230)
loadoutPanel.Position = UDim2.fromOffset(28, 346)
stylePanel(loadoutPanel, Color3.fromRGB(30, 34, 40), Color3.fromRGB(16, 18, 22))
loadoutPanel.Parent = root

local loadoutTitle = createLabel(
    loadoutPanel,
    "LoadoutTitle",
    "Loadout",
    UDim2.fromOffset(320, 24),
    UDim2.fromOffset(20, 16),
    22
)
local loadoutHint = createLabel(
    loadoutPanel,
    "LoadoutHint",
    "Dein Build veraendert deine Kernwerte und den Kampfstil.",
    UDim2.fromOffset(320, 32),
    UDim2.fromOffset(20, 44),
    13
)
loadoutHint.Font = Enum.Font.Gotham

local loadoutDetails = createLabel(
    loadoutPanel,
    "LoadoutDetails",
    "Noch kein Loadout geladen.",
    UDim2.fromOffset(320, 56),
    UDim2.fromOffset(20, 78),
    13
)
loadoutDetails.Font = Enum.Font.Gotham

local loadoutButtonContainer = Instance.new("Frame")
loadoutButtonContainer.Name = "LoadoutButtonContainer"
loadoutButtonContainer.BackgroundTransparency = 1
loadoutButtonContainer.Size = UDim2.fromOffset(320, 88)
loadoutButtonContainer.Position = UDim2.fromOffset(20, 136)
loadoutButtonContainer.Parent = loadoutPanel

local loadoutLayout = Instance.new("UIListLayout")
loadoutLayout.FillDirection = Enum.FillDirection.Vertical
loadoutLayout.Padding = UDim.new(0, 8)
loadoutLayout.Parent = loadoutButtonContainer

local buttonRow = Instance.new("Frame")
buttonRow.Name = "ButtonRow"
buttonRow.BackgroundTransparency = 1
buttonRow.Size = UDim2.new(1, -32, 1, -88)
buttonRow.Position = UDim2.fromOffset(16, 76)
buttonRow.Parent = selectionPanel

local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.Padding = UDim.new(0, 10)
rowLayout.Parent = buttonRow

local elementButtons = {} :: { [string]: any }
for _, elementName in ipairs(Elements.ElementOrder) do
    local definition = (Elements.Elements :: any)[elementName]
    local button = createButton(buttonRow, elementName .. "Button", UDim2.new(0.25, -8, 1, 0))
    local titleLabel = createLabel(
        button,
        "Title",
        definition.DisplayName,
        UDim2.new(1, -20, 0, 22),
        UDim2.fromOffset(10, 10),
        18
    )
    local bodyLabel = createLabel(
        button,
        "Body",
        definition.Summary,
        UDim2.new(1, -20, 0, 40),
        UDim2.fromOffset(10, 38),
        12
    )
    bodyLabel.Font = Enum.Font.Gotham
    bodyLabel.TextColor3 = Color3.fromRGB(234, 236, 239)
    button.MouseButton1Click:Connect(function()
        chooseElementEvent:FireServer(elementName)
    end)
    elementButtons[elementName] = {
        Button = button,
        Title = titleLabel,
        Body = bodyLabel,
    }
end

local latestState: ArenaState? = nil
local countdownDeadline = 0

local function setButtonVisual(elementName: string, selected: boolean)
    local definition = (Elements.Elements :: any)[elementName]
    local buttonData = elementButtons[elementName]
    if buttonData == nil then
        return
    end
    buttonData.Button.BackgroundColor3 = if selected
        then definition.ThemeColor
        else Color3.fromRGB(44, 47, 53)
    local gradient = buttonData.Button:FindFirstChildOfClass("UIGradient")
    if gradient then
        gradient.Color = if selected
            then ColorSequence.new({
                ColorSequenceKeypoint.new(0, definition.ThemeColor),
                ColorSequenceKeypoint.new(1, definition.AccentColor),
            })
            else ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(57, 63, 74)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 28, 33)),
            })
    end
    buttonData.Title.TextColor3 = if selected
        then Color3.fromRGB(20, 24, 28)
        else Color3.fromRGB(246, 239, 228)
    buttonData.Body.TextColor3 = if selected
        then Color3.fromRGB(35, 38, 42)
        else Color3.fromRGB(234, 236, 239)
end

local function updateCountdownLabel()
    if countdownDeadline <= 0 then
        countdownLabel.Text = ""
        return
    end

    local remaining = math.max(0, math.ceil(countdownDeadline - os.clock()))
    if remaining <= 0 then
        countdownLabel.Text = ""
        countdownDeadline = 0
        return
    end
    countdownLabel.Text = ("Naechster Wechsel in %ds"):format(remaining)
end

local function formatPercentage(multiplier: number): string
    return string.format("%+d%%", math.floor((multiplier - 1) * 100 + 0.5))
end

local function clearLoadoutButtons()
    for _, child in ipairs(loadoutButtonContainer:GetChildren()) do
        if child ~= loadoutLayout then
            child:Destroy()
        end
    end
end

local function renderLoadoutButtons(
    loadoutChoices: { any },
    selectedLoadoutId: string,
    canChangeLoadout: boolean
)
    clearLoadoutButtons()
    for _, loadout in ipairs(loadoutChoices) do
        local button =
            createButton(loadoutButtonContainer, loadout.Id .. "Button", UDim2.new(1, 0, 0, 40))
        local isSelected = loadout.Id == selectedLoadoutId or loadout.Selected
        button.Active = canChangeLoadout and loadout.Unlocked
        button.AutoButtonColor = button.Active
        button.BackgroundColor3 = if isSelected
            then Color3.fromRGB(70, 90, 110)
            else Color3.fromRGB(41, 45, 52)

        local nameLabel = createLabel(
            button,
            "Name",
            loadout.DisplayName,
            UDim2.new(1, -72, 0, 16),
            UDim2.fromOffset(12, 6),
            14
        )
        nameLabel.TextColor3 = if isSelected
            then Color3.fromRGB(18, 22, 28)
            else Color3.fromRGB(246, 239, 228)
        local summaryLabel = createLabel(
            button,
            "Summary",
            loadout.Summary,
            UDim2.new(1, -100, 0, 14),
            UDim2.fromOffset(12, 22),
            10
        )
        summaryLabel.Font = Enum.Font.Gotham
        summaryLabel.TextColor3 = if isSelected
            then Color3.fromRGB(28, 32, 38)
            else Color3.fromRGB(230, 232, 236)

        local statusLabel = createLabel(
            button,
            "Status",
            "",
            UDim2.fromOffset(60, 20),
            UDim2.new(1, -68, 0, 10),
            10
        )
        statusLabel.TextXAlignment = Enum.TextXAlignment.Right
        statusLabel.TextColor3 = if isSelected
            then Color3.fromRGB(18, 22, 28)
            else Color3.fromRGB(223, 226, 231)
        if loadout.Unlocked then
            statusLabel.Text = if isSelected then "Aktiv" else "Frei"
        else
            statusLabel.Text = string.format("Lv %d", loadout.UnlockProgress)
            button.BackgroundColor3 = Color3.fromRGB(32, 35, 40)
            nameLabel.TextColor3 = Color3.fromRGB(177, 182, 191)
            summaryLabel.TextColor3 = Color3.fromRGB(146, 151, 162)
            statusLabel.TextColor3 = Color3.fromRGB(146, 151, 162)
        end

        button.MouseButton1Click:Connect(function()
            if canChangeLoadout and loadout.Unlocked then
                chooseLoadoutEvent:FireServer(loadout.Id)
            end
        end)
    end

    if #loadoutChoices == 0 then
        local emptyLabel = createLabel(
            loadoutButtonContainer,
            "Empty",
            "Keine Loadouts verfuegbar.",
            UDim2.new(1, 0, 0, 20),
            UDim2.fromOffset(0, 0),
            12
        )
        emptyLabel.Font = Enum.Font.Gotham
        emptyLabel.TextColor3 = Color3.fromRGB(200, 204, 210)
    end
end

local function renderState(state: ArenaState)
    latestState = state
    countdownDeadline = if state.Countdown > 0 then os.clock() + state.Countdown else 0
    local canChangeLoadout = state.Match == nil or state.Match.Phase ~= "Round"
    local matchMode = state.Mode or (state.Match and state.Match.Mode) or "PvP"

    statusTitle.Text = if state.ArenaReady then "Arena online" else "Arena im Aufbau"
    statusBody.Text = string.format("%s\nModus: %s", state.Message, matchMode)

    local viewer = state.Viewer
    local currentLoadout = viewer.CurrentLoadout
    viewerStats.Text = string.format(
        "Pfad: %s\nLoadout: %s\nLevel %.1f  |  Gear %d\nSchaden x%.1f  |  Cooldowns x%.1f\nWartende Spieler: %d\nModus: %s",
        viewer.Element,
        currentLoadout.DisplayName,
        viewer.Progress,
        viewer.GearTier,
        viewer.DamageMultiplier,
        viewer.CooldownMultiplier,
        state.QueueCount,
        matchMode
    )

    loadoutTitle.Text = string.format("Loadout | %s", currentLoadout.DisplayName)
    loadoutHint.Text = currentLoadout.Passive
    loadoutDetails.Text = string.format(
        "%s\n%s  |  Leben +%d  |  Cooldowns x%.2f",
        currentLoadout.Summary,
        formatPercentage(currentLoadout.DamageMultiplier),
        currentLoadout.HealthBonus,
        currentLoadout.CooldownMultiplier
    )
    renderLoadoutButtons(viewer.LoadoutChoices or {}, currentLoadout.Id, canChangeLoadout)

    for _, elementName in ipairs(Elements.ElementOrder) do
        setButtonVisual(elementName, viewer.Element == elementName)
    end

    if state.Match == nil then
        scoreboardTitle.Text = "Duellstand"
        for _, card in ipairs(playerCards) do
            card.NameLabel.Text = "Warte auf Spieler"
            card.ScoreLabel.Text = "0 Siege"
            card.DetailLabel.Text = "Noch kein aktives Duell."
            card.Frame.BackgroundColor3 = Color3.fromRGB(55, 60, 69)
        end
        selectionPanel.Visible = not viewer.HasSelectedElement
        loadoutPanel.Visible = canChangeLoadout
    else
        scoreboardTitle.Text = string.format(
            "Duellstand | %s | Runde %d",
            matchMode,
            math.max(state.Match.RoundNumber, 1)
        )
        selectionPanel.Visible = not viewer.HasSelectedElement
        loadoutPanel.Visible = canChangeLoadout
        for index, card in ipairs(playerCards) do
            local playerState = state.Match.Players[index]
            if playerState then
                local definition = (Elements.Elements :: any)[playerState.Element]
                card.NameLabel.Text = string.format(
                    "%s%s | %s",
                    playerState.IsBot and "Computer: " or "",
                    playerState.Name,
                    definition.DisplayName
                )
                card.ScoreLabel.Text = string.format("%d Siege", playerState.Score)
                card.DetailLabel.Text = string.format(
                    "HP %d/%d  |  Schild %d  |  Level %.1f  |  Gear %d  |  %s",
                    playerState.CurrentHealth,
                    playerState.MaxHealth,
                    playerState.Shield,
                    playerState.Progress,
                    playerState.GearTier,
                    playerState.CurrentLoadout.DisplayName
                )
                card.Frame.BackgroundColor3 = definition.ThemeColor
            else
                card.NameLabel.Text = "Warte auf Spieler"
                card.ScoreLabel.Text = "0 Siege"
                card.DetailLabel.Text = "Noch kein aktives Duell."
                card.Frame.BackgroundColor3 = Color3.fromRGB(55, 60, 69)
            end
        end
        if state.Match.Reward then
            statusBody.Text = string.format(
                "%s\nBelohnung: %s erhielt %s.",
                state.Message,
                state.Match.Reward.RecipientName,
                state.Match.Reward.Name
            )
        end
    end

    for slotName, keybind in pairs(MatchConfig.AbilityKeybinds) do
        local cooldown = state.Cooldowns[slotName]
        local slotDefinition = Elements.Elements[viewer.Element].Abilities[slotName]
        local unlocked = table.find(viewer.UnlockedSlots, slotName) ~= nil
        cooldownLabels[slotName].Text = string.format(
            "%s  %s\n%s",
            keybind,
            slotDefinition.Name,
            if unlocked then string.format("%.1fs", cooldown) else "gesperrt"
        )
    end

    updateCountdownLabel()
end

stateEvent.OnClientEvent:Connect(function(state: ArenaState)
    renderState(state)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or latestState == nil then
        return
    end
    if input.KeyCode == Enum.KeyCode.Q then
        castAbilityEvent:FireServer("Primary")
    elseif input.KeyCode == Enum.KeyCode.E then
        castAbilityEvent:FireServer("Secondary")
    elseif input.KeyCode == Enum.KeyCode.R then
        castAbilityEvent:FireServer("Ultimate")
    end
end)

task.spawn(function()
    while screenGui.Parent ~= nil do
        task.wait(0.2)
        updateCountdownLabel()
    end
end)

local ok, initialState = pcall(function()
    return requestStateFunction:InvokeServer()
end)

if ok and initialState ~= nil then
    renderState(initialState)
end

print(("[client] booted %s"):format(Shared.GameName))
