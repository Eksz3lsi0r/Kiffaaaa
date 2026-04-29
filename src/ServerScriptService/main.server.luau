--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

type EnemyState = {
    Model: Model,
    Root: BasePart,
    Head: BasePart,
    HomePosition: Vector3,
    WalkRadius: number,
    WalkSpeed: number,
    Phase: number,
    Health: number,
    MaxHealth: number,
    Alive: boolean,
    HealthFill: Frame,
    HealthLabel: TextLabel,
}

type DragonState = {
    Model: Model,
    Saddle: BasePart,
    Muzzle: BasePart,
    RestPosition: Vector3,
    FlightCenter: Vector3,
    FlightRadius: number,
    FlightDuration: number,
}

local baseplateTopY = 0.5
local scenarioRunning = true
local combatRunning = false
local enemies: { EnemyState } = {}
local riderWeld: WeldConstraint? = nil
local riderHumanoid: Humanoid? = nil
local riderRootPart: BasePart? = nil

local function clearWorkspace()
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Terrain") then
            child:Clear()
        elseif child.Name ~= "Baseplate" then
            child:Destroy()
        end
    end
end

local function ensureBaseplate()
    local baseplate = Workspace:FindFirstChild("Baseplate")
    if baseplate ~= nil and not baseplate:IsA("BasePart") then
        baseplate:Destroy()
        baseplate = nil
    end

    if baseplate == nil then
        local created = Instance.new("Part")
        created.Name = "Baseplate"
        created.Parent = Workspace
        baseplate = created
    end

    local part = baseplate :: BasePart
    part.Anchored = true
    part.Size = Vector3.new(512, 1, 512)
    part.Position = Vector3.new(0, 0, 0)
    part.Material = Enum.Material.Grass
    part.Color = Color3.fromRGB(102, 170, 92)
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
end

local function createPart(
    parent: Instance,
    name: string,
    size: Vector3,
    cframe: CFrame,
    color: Color3,
    material: Enum.Material,
    shape: Enum.PartType?
): BasePart
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Massless = true
    part.Size = size
    part.CFrame = cframe
    part.Color = color
    part.Material = material
    if shape ~= nil then
        part.Shape = shape
    end
    part.Parent = parent
    return part
end

local function createEnemyHealthGui(adornee: BasePart, title: string): (Frame, TextLabel)
    local gui = Instance.new("BillboardGui")
    gui.Name = title .. "HealthBar"
    gui.Adornee = adornee
    gui.AlwaysOnTop = true
    gui.LightInfluence = 0
    gui.Size = UDim2.fromOffset(120, 28)
    gui.StudsOffset = Vector3.new(0, 4.8, 0)
    gui.Parent = adornee

    local root = Instance.new("Frame")
    root.Name = "Root"
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromScale(1, 1)
    root.Parent = gui

    local barBackground = Instance.new("Frame")
    barBackground.Name = "Background"
    barBackground.AnchorPoint = Vector2.new(0.5, 0)
    barBackground.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    barBackground.BorderSizePixel = 0
    barBackground.Position = UDim2.fromScale(0.5, 0.18)
    barBackground.Size = UDim2.fromOffset(104, 8)
    barBackground.Parent = root

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 1
    stroke.Parent = barBackground

    local barFill = Instance.new("Frame")
    barFill.Name = "Fill"
    barFill.BackgroundColor3 = Color3.fromRGB(70, 255, 90)
    barFill.BorderSizePixel = 0
    barFill.Size = UDim2.fromScale(1, 1)
    barFill.Parent = barBackground

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0.45
    label.TextScaled = true
    label.Position = UDim2.fromScale(0, 0.5)
    label.Size = UDim2.fromOffset(120, 14)
    label.Parent = root

    return barFill, label
end

local function updateEnemyBar(enemy: EnemyState)
    local percent = math.clamp(enemy.Health / enemy.MaxHealth, 0, 1)
    local red = math.floor(255 * (1 - percent))
    local green = math.floor(255 * percent)
    enemy.HealthFill.Size = UDim2.fromScale(percent, 1)
    enemy.HealthFill.BackgroundColor3 = Color3.fromRGB(red, green, 70)
    enemy.HealthLabel.Text =
        string.format("%s %d/%d", enemy.Model.Name, enemy.Health, enemy.MaxHealth)
end

local function getNearestLivingEnemy(position: Vector3): EnemyState?
    local nearestEnemy: EnemyState? = nil
    local nearestDistance = math.huge

    for _, enemy in ipairs(enemies) do
        if enemy.Alive and enemy.Model.Parent ~= nil then
            local distance = (enemy.Root.Position - position).Magnitude
            if distance < nearestDistance then
                nearestDistance = distance
                nearestEnemy = enemy
            end
        end
    end

    return nearestEnemy
end

local function spawnImpactFlash(position: Vector3, color: Color3)
    local flash = Instance.new("Part")
    flash.Name = "ImpactFlash"
    flash.Anchored = true
    flash.CanCollide = false
    flash.CanTouch = false
    flash.CanQuery = false
    flash.Shape = Enum.PartType.Ball
    flash.Size = Vector3.new(1.2, 1.2, 1.2)
    flash.Material = Enum.Material.Neon
    flash.Color = color
    flash.Transparency = 0.2
    flash.CFrame = CFrame.new(position)
    flash.Parent = Workspace

    local light = Instance.new("PointLight")
    light.Color = color
    light.Brightness = 4
    light.Range = 14
    light.Parent = flash

    local tween = TweenService:Create(
        flash,
        TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = Vector3.new(5, 5, 5), Transparency = 1 }
    )
    tween:Play()
    task.delay(0.3, function()
        if flash.Parent ~= nil then
            flash:Destroy()
        end
    end)
end

local function damageEnemy(enemy: EnemyState, amount: number)
    if not enemy.Alive then
        return
    end

    enemy.Health = math.max(0, enemy.Health - amount)
    updateEnemyBar(enemy)
    print(
        ("[server] %s took %d damage (%d/%d)"):format(
            enemy.Model.Name,
            amount,
            enemy.Health,
            enemy.MaxHealth
        )
    )

    if enemy.Health <= 0 then
        enemy.Alive = false
        print(("[server] %s defeated"):format(enemy.Model.Name))
        spawnImpactFlash(enemy.Root.Position, Color3.fromRGB(255, 120, 70))
        task.delay(0.35, function()
            if enemy.Model.Parent ~= nil then
                enemy.Model:Destroy()
            end
        end)
    end
end

local function launchFireball(startPosition: Vector3, targetEnemy: EnemyState)
    if not targetEnemy.Alive or targetEnemy.Model.Parent == nil then
        return
    end

    local fireball = Instance.new("Part")
    fireball.Name = "Fireball"
    fireball.Anchored = true
    fireball.CanCollide = false
    fireball.CanTouch = false
    fireball.CanQuery = false
    fireball.Shape = Enum.PartType.Ball
    fireball.Size = Vector3.new(1.6, 1.6, 1.6)
    fireball.Material = Enum.Material.Neon
    fireball.Color = Color3.fromRGB(255, 117, 33)
    fireball.CFrame = CFrame.new(startPosition)
    fireball.Parent = Workspace

    local backAttachment = Instance.new("Attachment")
    backAttachment.Position = Vector3.new(0, 0, 0.8)
    backAttachment.Parent = fireball

    local frontAttachment = Instance.new("Attachment")
    frontAttachment.Position = Vector3.new(0, 0, -0.8)
    frontAttachment.Parent = fireball

    local trail = Instance.new("Trail")
    trail.Attachment0 = backAttachment
    trail.Attachment1 = frontAttachment
    trail.Color = ColorSequence.new(Color3.fromRGB(255, 198, 86), Color3.fromRGB(255, 92, 22))
    trail.Lifetime = 0.16
    trail.MinLength = 0.05
    trail.LightEmission = 1
    trail.Parent = fireball

    local light = Instance.new("PointLight")
    light.Color = fireball.Color
    light.Brightness = 2.5
    light.Range = 10
    light.Parent = fireball

    print(("[server] fireball launched at %s"):format(targetEnemy.Model.Name))

    local targetPosition = targetEnemy.Root.Position + Vector3.new(0, 1.6, 0)
    local distance = (targetPosition - startPosition).Magnitude
    local travelTime = math.clamp(distance / 130, 0.25, 0.95)
    local startTime = os.clock()

    while fireball.Parent ~= nil do
        local elapsed = os.clock() - startTime
        local alpha = math.clamp(elapsed / travelTime, 0, 1)
        local liveTargetPosition = targetEnemy.Alive
                and targetEnemy.Model.Parent ~= nil
                and (targetEnemy.Root.Position + Vector3.new(0, 1.6, 0))
            or targetPosition
        local position = startPosition:Lerp(liveTargetPosition, alpha)
        fireball.CFrame = CFrame.new(position)
        if alpha >= 1 then
            break
        end
        RunService.Heartbeat:Wait()
    end

    if fireball.Parent ~= nil then
        local hitPosition = fireball.Position
        fireball:Destroy()
        spawnImpactFlash(hitPosition, Color3.fromRGB(255, 161, 52))
        if targetEnemy.Alive and targetEnemy.Model.Parent ~= nil then
            damageEnemy(targetEnemy, 10)
        end
    end
end

local function createEnemy(
    name: string,
    homePosition: Vector3,
    walkRadius: number,
    walkSpeed: number,
    phase: number
): EnemyState
    local model = Instance.new("Model")
    model.Name = name
    model.Parent = Workspace

    local root = createPart(
        model,
        "HumanoidRootPart",
        Vector3.new(2, 2, 1),
        CFrame.new(homePosition + Vector3.new(0, 2.5, 0)),
        Color3.fromRGB(35, 35, 35),
        Enum.Material.SmoothPlastic,
        nil
    )
    root.Transparency = 1

    createPart(
        model,
        "Torso",
        Vector3.new(2.8, 3.6, 1.6),
        CFrame.new(homePosition + Vector3.new(0, 4.1, 0)),
        Color3.fromRGB(86, 108, 75),
        Enum.Material.SmoothPlastic,
        nil
    )
    local head = createPart(
        model,
        "Head",
        Vector3.new(2.2, 2.1, 2.2),
        CFrame.new(homePosition + Vector3.new(0, 6.35, 0)),
        Color3.fromRGB(127, 164, 111),
        Enum.Material.SmoothPlastic,
        nil
    )
    createPart(
        model,
        "LeftArm",
        Vector3.new(0.8, 2.8, 0.8),
        CFrame.new(homePosition + Vector3.new(-2, 4.1, 0)),
        Color3.fromRGB(66, 86, 58),
        Enum.Material.SmoothPlastic,
        nil
    )
    createPart(
        model,
        "RightArm",
        Vector3.new(0.8, 2.8, 0.8),
        CFrame.new(homePosition + Vector3.new(2, 4.1, 0)),
        Color3.fromRGB(66, 86, 58),
        Enum.Material.SmoothPlastic,
        nil
    )
    createPart(
        model,
        "LeftLeg",
        Vector3.new(1, 2.9, 1),
        CFrame.new(homePosition + Vector3.new(-0.7, 1.05, 0)),
        Color3.fromRGB(50, 64, 44),
        Enum.Material.SmoothPlastic,
        nil
    )
    createPart(
        model,
        "RightLeg",
        Vector3.new(1, 2.9, 1),
        CFrame.new(homePosition + Vector3.new(0.7, 1.05, 0)),
        Color3.fromRGB(50, 64, 44),
        Enum.Material.SmoothPlastic,
        nil
    )

    model:PivotTo(CFrame.new(homePosition + Vector3.new(0, 2.5, 0)))

    local healthFill, healthLabel = createEnemyHealthGui(head, name)
    local enemy: EnemyState = {
        Model = model,
        Root = root,
        Head = head,
        HomePosition = homePosition,
        WalkRadius = walkRadius,
        WalkSpeed = walkSpeed,
        Phase = phase,
        Health = 30,
        MaxHealth = 30,
        Alive = true,
        HealthFill = healthFill,
        HealthLabel = healthLabel,
    }

    updateEnemyBar(enemy)
    table.insert(enemies, enemy)

    task.spawn(function()
        while scenarioRunning and enemy.Alive and enemy.Model.Parent ~= nil do
            local elapsed = os.clock()
            local angle = elapsed * enemy.WalkSpeed + enemy.Phase
            local x = enemy.HomePosition.X + math.cos(angle) * enemy.WalkRadius
            local z = enemy.HomePosition.Z + math.sin(angle * 0.75) * enemy.WalkRadius * 0.7
            local y = baseplateTopY + 2.5 + math.sin(elapsed * 8) * 0.08
            local position = Vector3.new(x, y, z)
            local direction = Vector3.new(-math.sin(angle), 0, math.cos(angle * 0.75))
            if direction.Magnitude < 0.001 then
                direction = Vector3.new(0, 0, -1)
            end
            enemy.Model:PivotTo(CFrame.lookAt(position, position + direction))
            RunService.Heartbeat:Wait()
        end
    end)

    return enemy
end

local function getFirstPlayer(): Player
    local players = Players:GetPlayers()
    if #players > 0 then
        return players[1]
    end

    return Players.PlayerAdded:Wait()
end

local function mountPlayerOnDragon(dragon: DragonState)
    local player = getFirstPlayer()
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

    rootPart.CFrame = dragon.Saddle.CFrame * CFrame.new(0, 2, 0)
    task.wait(0.25)

    if riderWeld ~= nil then
        riderWeld:Destroy()
        riderWeld = nil
    end

    local weld = Instance.new("WeldConstraint")
    weld.Name = "DragonRiderWeld"
    weld.Part0 = rootPart
    weld.Part1 = dragon.Saddle
    weld.Parent = rootPart

    riderWeld = weld
    riderHumanoid = humanoid
    riderRootPart = rootPart

    humanoid.Sit = true
    humanoid.PlatformStand = true
    humanoid.AutoRotate = false
    humanoid:ChangeState(Enum.HumanoidStateType.Seated)

    print(("[server] dragon rider mounted: %s"):format(player.Name))
end

local function unmountRider(restPosition: Vector3)
    if riderWeld ~= nil then
        riderWeld:Destroy()
        riderWeld = nil
    end

    if riderHumanoid ~= nil then
        riderHumanoid.Sit = false
        riderHumanoid.PlatformStand = false
        riderHumanoid.AutoRotate = true
        riderHumanoid:ChangeState(Enum.HumanoidStateType.Running)
    end

    if riderRootPart ~= nil then
        riderRootPart.CFrame = CFrame.new(restPosition + Vector3.new(0, 4, 8))
    end

    riderHumanoid = nil
    riderRootPart = nil
end

local function createDragon(): DragonState
    local model = Instance.new("Model")
    model.Name = "MCPDemoDragon"
    model.Parent = Workspace

    local restPosition = Vector3.new(0, 10, -44)
    local flightCenter = Vector3.new(0, 26, 0)
    local flightRadius = 46
    local flightDuration = 30
    local origin = CFrame.new(restPosition)

    local function addPart(
        name: string,
        size: Vector3,
        offset: CFrame,
        color: Color3,
        material: Enum.Material,
        shape: Enum.PartType?
    ): BasePart
        return createPart(model, name, size, origin * offset, color, material, shape)
    end

    addPart(
        "Body",
        Vector3.new(16, 5, 9),
        CFrame.new(0, 4, 0),
        Color3.fromRGB(62, 149, 86),
        Enum.Material.SmoothPlastic,
        nil
    )
    addPart(
        "Neck",
        Vector3.new(4, 4, 5),
        CFrame.new(0, 5, -6) * CFrame.Angles(math.rad(-20), 0, 0),
        Color3.fromRGB(70, 160, 94),
        Enum.Material.SmoothPlastic,
        nil
    )
    addPart(
        "Head",
        Vector3.new(5, 4, 5),
        CFrame.new(0, 6, -10),
        Color3.fromRGB(58, 136, 80),
        Enum.Material.SmoothPlastic,
        Enum.PartType.Ball
    )
    addPart(
        "Snout",
        Vector3.new(3, 2, 4),
        CFrame.new(0, 5.5, -13),
        Color3.fromRGB(47, 112, 66),
        Enum.Material.SmoothPlastic,
        nil
    )
    addPart(
        "HornLeft",
        Vector3.new(0.35, 2, 0.35),
        CFrame.new(-1.1, 8, -10.5) * CFrame.Angles(math.rad(-20), 0, math.rad(18)),
        Color3.fromRGB(235, 225, 188),
        Enum.Material.SmoothPlastic,
        nil
    )
    addPart(
        "HornRight",
        Vector3.new(0.35, 2, 0.35),
        CFrame.new(1.1, 8, -10.5) * CFrame.Angles(math.rad(-20), 0, math.rad(-18)),
        Color3.fromRGB(235, 225, 188),
        Enum.Material.SmoothPlastic,
        nil
    )
    addPart(
        "WingLeft",
        Vector3.new(10, 0.4, 8),
        CFrame.new(-8, 8, -1) * CFrame.Angles(0, 0, math.rad(-22)),
        Color3.fromRGB(52, 124, 72),
        Enum.Material.SmoothPlastic,
        nil
    )
    addPart(
        "WingRight",
        Vector3.new(10, 0.4, 8),
        CFrame.new(8, 8, -1) * CFrame.Angles(0, 0, math.rad(22)),
        Color3.fromRGB(52, 124, 72),
        Enum.Material.SmoothPlastic,
        nil
    )
    addPart(
        "TailBase",
        Vector3.new(3, 3, 7),
        CFrame.new(0, 4, 9) * CFrame.Angles(math.rad(18), 0, 0),
        Color3.fromRGB(58, 136, 80),
        Enum.Material.SmoothPlastic,
        nil
    )
    addPart(
        "TailTip",
        Vector3.new(2, 2, 6),
        CFrame.new(0, 3.6, 14) * CFrame.Angles(math.rad(28), 0, 0),
        Color3.fromRGB(47, 112, 66),
        Enum.Material.SmoothPlastic,
        nil
    )
    local saddle = addPart(
        "Saddle",
        Vector3.new(3, 1, 3),
        CFrame.new(0, 7, -1),
        Color3.fromRGB(114, 74, 45),
        Enum.Material.Leather,
        nil
    )
    local muzzle = addPart(
        "Muzzle",
        Vector3.new(1, 1, 1),
        CFrame.new(0, 5.6, -14),
        Color3.fromRGB(255, 255, 255),
        Enum.Material.SmoothPlastic,
        nil
    )
    muzzle.Transparency = 1

    model:PivotTo(CFrame.lookAt(restPosition, restPosition + Vector3.new(0, 0, -1)))

    local dragon = {
        Model = model,
        Saddle = saddle,
        Muzzle = muzzle,
        RestPosition = restPosition,
        FlightCenter = flightCenter,
        FlightRadius = flightRadius,
        FlightDuration = flightDuration,
    } :: DragonState
    return dragon
end

local function runFireLoop(dragon: DragonState)
    combatRunning = true
    task.spawn(function()
        while scenarioRunning and combatRunning and dragon.Model.Parent ~= nil do
            task.wait(1)
            if not (scenarioRunning and combatRunning and dragon.Model.Parent ~= nil) then
                break
            end

            local target = getNearestLivingEnemy(dragon.Muzzle.Position)
            if target ~= nil then
                task.spawn(launchFireball, dragon.Muzzle.Position, target)
            end
        end
    end)
end

local function flyDragon(dragon: DragonState)
    print("[server] dragon flight started")
    runFireLoop(dragon)

    local startTime = os.clock()
    while os.clock() - startTime < dragon.FlightDuration do
        local elapsed = os.clock() - startTime
        local angle = elapsed * 0.55
        local radius = dragon.FlightRadius + math.sin(elapsed * 0.7) * 3
        local altitude = 26 + math.sin(elapsed * 1.3) * 3
        local position = dragon.FlightCenter
            + Vector3.new(math.cos(angle) * radius, altitude, math.sin(angle) * radius)
        local facing = position + Vector3.new(-math.sin(angle), 0, math.cos(angle))
        dragon.Model:PivotTo(CFrame.lookAt(position, facing))
        RunService.Heartbeat:Wait()
    end

    print("[server] dragon landing")
    combatRunning = false

    local landingStart = dragon.Model:GetPivot()
    local landingTarget = CFrame.new(dragon.RestPosition)
    for step = 1, 90 do
        dragon.Model:PivotTo(landingStart:Lerp(landingTarget, step / 90))
        RunService.Heartbeat:Wait()
    end

    unmountRider(dragon.RestPosition)
    scenarioRunning = false
    print("[server] dragon landed")
end

local function startDemo()
    clearWorkspace()
    ensureBaseplate()

    local dragon = createDragon()
    print(("[server] dragon ready at %s"):format(dragon.Model:GetFullName()))

    createEnemy("Zombie 1", Vector3.new(-52, baseplateTopY, -18), 10, 0.62, 0)
    createEnemy("Zombie 2", Vector3.new(0, baseplateTopY, 32), 10, 0.7, 2.1)
    createEnemy("Zombie 3", Vector3.new(52, baseplateTopY, -18), 10, 0.58, 4.2)

    print("[server] 3 enemies ready with 30 HP each")

    task.spawn(function()
        task.wait(2)
        mountPlayerOnDragon(dragon)
        flyDragon(dragon)
    end)
end

startDemo()
