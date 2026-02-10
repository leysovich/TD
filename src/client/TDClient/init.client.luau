local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local UserInputService = game:GetService('UserInputService')
local RunService = game:GetService('RunService')
local Workspace = game:GetService('Workspace')

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local TD = ReplicatedStorage:WaitForChild('TD')
local Config = require(TD:WaitForChild('Config'))
local Remotes = TD:WaitForChild('Remotes')
local PlaceTowerRemote = Remotes:WaitForChild('PlaceTower')
local StateUpdateRemote = Remotes:WaitForChild('StateUpdate')
local TowerActionRemote = Remotes:WaitForChild('TowerAction')
local Assets = TD:WaitForChild('Assets')
local TowerModels = Assets:WaitForChild('TowerModels')

local hotbarSlots = {
    {slotId = 'none', keyCode = Enum.KeyCode.Zero, keyText = '0', towerKey = nil, label = 'Empty Hands'},
    {slotId = 'laser', keyCode = Enum.KeyCode.One, keyText = '1', towerKey = 'LaserTurret', label = 'Laser Turret'},
    {slotId = 'frost', keyCode = Enum.KeyCode.Two, keyText = '2', towerKey = 'FrostBeam', label = 'Frost Beam'},
    {slotId = 'missile', keyCode = Enum.KeyCode.Three, keyText = '3', towerKey = 'MissilePod', label = 'Missile Pod'},
}

local selectedTowerKey = nil
local selectedPlacedTower = nil
local showUpgradePreview = false

local currentState = {
    status = 'Loading',
    wave = 0,
    maxWave = 0,
    waveName = 'Preparing',
    lives = Config.BaseLives,
    money = Config.StartMoney,
    towers = 0,
    intermissionRemaining = 0,
    elapsedSeconds = 0,
}

local previewModel = nil
local previewIsValid = false
local previewPos = Vector3.new(0, 0, 0)
local previewGroundAnchor = nil
local previewAnchorPart = nil
local previewVisualPos = nil
local PREVIEW_SMOOTH_SPEED = 22

local currentRangePart = nil
local nextRangePart = nil

local actionMessageUntil = 0
local actionMessageText = ''

local slotButtons = {}
local statusLabel
local waveLabel
local creditsLabel
local livesLabel
local intermissionLabel
local totalTimeLabel
local placementLabel
local actionMessageLabel
local livesFill

local hoverEnemyPanel
local hoverEnemyName
local hoverEnemyHpText
local hoverEnemyHpFill

local towerPanel
local towerPanelTitle
local towerPanelStats
local towerPanelUpgradeBtn
local towerPanelSellBtn
local towerPanelTargetBtn

local colors = {
    panel = Color3.fromRGB(14, 20, 30),
    panelAlt = Color3.fromRGB(20, 28, 40),
    slot = Color3.fromRGB(22, 32, 48),
    slotSelected = Color3.fromRGB(14, 44, 54),
    text = Color3.fromRGB(232, 241, 255),
    subtext = Color3.fromRGB(162, 184, 210),
    accent = Color3.fromRGB(0, 228, 185),
    bad = Color3.fromRGB(255, 96, 108),
    good = Color3.fromRGB(94, 245, 132),
    rangeCurrent = Color3.fromRGB(80, 220, 255),
    rangeNext = Color3.fromRGB(255, 204, 95),
}

local function flattenXZ(v)
    return Vector3.new(v.X, 0, v.Z)
end

local function formatTime(total)
    local t = math.max(0, math.floor(total or 0))
    local m = math.floor(t / 60)
    local s = t % 60
    return string.format('%02d:%02d', m, s)
end

local function sortedWaypoints()
    local map = Workspace:FindFirstChild('TD_Map')
    local wpFolder = map and map:FindFirstChild('Waypoints')
    if not wpFolder then
        return {}
    end

    local list = wpFolder:GetChildren()
    table.sort(list, function(a, b)
        local an = tonumber(string.match(a.Name, '%d+')) or 0
        local bn = tonumber(string.match(b.Name, '%d+')) or 0
        return an < bn
    end)
    return list
end

local function getGroundYAt(pos)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local ignore = {}
    local towers = Workspace:FindFirstChild('TD_Towers')
    local enemies = Workspace:FindFirstChild('TD_Enemies')
    if towers then table.insert(ignore, towers) end
    if enemies then table.insert(ignore, enemies) end
    if previewModel then table.insert(ignore, previewModel) end
    if currentRangePart then table.insert(ignore, currentRangePart) end
    if nextRangePart then table.insert(ignore, nextRangePart) end
    rayParams.FilterDescendantsInstances = ignore

    local origin = Vector3.new(pos.X, pos.Y + 256, pos.Z)
    local result = Workspace:Raycast(origin, Vector3.new(0, -1024, 0), rayParams)
    if result then
        return result.Position.Y
    end

    return 2
end

local function getCursorGroundPlacement()
    local camera = Workspace.CurrentCamera
    if not camera then
        return nil
    end

    local mousePos = UserInputService:GetMouseLocation()
    local unitRay = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local ignore = {}
    local towers = Workspace:FindFirstChild('TD_Towers')
    local enemies = Workspace:FindFirstChild('TD_Enemies')
    if towers then table.insert(ignore, towers) end
    if enemies then table.insert(ignore, enemies) end
    if previewModel then table.insert(ignore, previewModel) end
    if currentRangePart then table.insert(ignore, currentRangePart) end
    if nextRangePart then table.insert(ignore, nextRangePart) end
    if player.Character then table.insert(ignore, player.Character) end
    rayParams.FilterDescendantsInstances = ignore

    local hit = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 3000, rayParams)
    local hitPos
    if hit then
        hitPos = hit.Position
    else
        local dirY = unitRay.Direction.Y
        if math.abs(dirY) > 1e-4 then
            local t = -unitRay.Origin.Y / dirY
            if t > 0 then
                hitPos = unitRay.Origin + unitRay.Direction * t
            end
        end
    end

    if not hitPos then
        return nil
    end

    local groundY = getGroundYAt(hitPos)
    return Vector3.new(hitPos.X, groundY, hitPos.Z)
end

local function firstBasePart(model)
    if model.PrimaryPart then
        return model.PrimaryPart
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA('BasePart') then
            model.PrimaryPart = d
            return d
        end
    end
    return nil
end

local function buildFallbackPreview(name)
    local model = Instance.new('Model')
    model.Name = name

    local base = Instance.new('Part')
    base.Name = 'Base'
    base.Size = Vector3.new(4, 6, 4)
    base.Anchored = true
    base.CanCollide = false
    base.Material = Enum.Material.Neon
    base.Parent = model

    model.PrimaryPart = base
    return model
end

local function getTowerTemplateModel(templateName)
    local chosen = nil
    for _, child in ipairs(TowerModels:GetChildren()) do
        if child:IsA('Model') and child.Name == templateName then
            chosen = child
        end
    end

    if chosen then
        return chosen
    end

    local fallback = TowerModels:FindFirstChild(templateName)
    if fallback and fallback:IsA('Model') then
        return fallback
    end

    return nil
end

local TOWER_TOP_Y_OFFSET = {
    LaserTurret = -0.65,
}

local function applyTowerModelFixups(model, towerKey)
    local offsetY = TOWER_TOP_Y_OFFSET[towerKey]
    if not offsetY or math.abs(offsetY) < 0.001 then
        return
    end

    local top = model:FindFirstChild('Top', true)
    if not top then
        return
    end

    local delta = Vector3.new(0, offsetY, 0)
    if top:IsA('Model') then
        top:PivotTo(top:GetPivot() + delta)
    elseif top:IsA('BasePart') then
        top.CFrame = top.CFrame + delta
    end
end

local function getTemplateForTower(towerKey)
    if not towerKey then
        return nil
    end

    local towerDef = Config.Towers[towerKey]
    if not towerDef then
        return nil
    end

    local templateName = towerDef.TemplateName or towerKey
    local template = getTowerTemplateModel(templateName)
    if template and template:IsA('Model') then
        return template
    end

    return nil
end

local function setPreviewTint(model, valid)
    local color = valid and colors.good or colors.bad
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA('BasePart') then
            d.Color = color
            d.Transparency = 0.5
        end
    end
end

local function getPlacementAnchorPart(model)
    local explicitBase = model:FindFirstChild('Base', true)
    if explicitBase and explicitBase:IsA('BasePart') then
        return explicitBase
    end

    if explicitBase and explicitBase:IsA('Model') then
        local lowest = nil
        local lowestY = math.huge
        for _, d in ipairs(explicitBase:GetDescendants()) do
            if d:IsA('BasePart') then
                local y = d.Position.Y - d.Size.Y * 0.5
                if y < lowestY then
                    lowest = d
                    lowestY = y
                end
            end
        end
        if lowest then
            return lowest
        end
    end

    local best = nil
    local bestScore = -math.huge

    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA('BasePart') then
            local lname = string.lower(d.Name)
            local score = 0

            if lname == 'base' then
                score = 100
            elseif string.find(lname, 'base', 1, true) then
                score = 80
            elseif string.find(lname, 'plate', 1, true) or string.find(lname, 'stand', 1, true) or string.find(lname, 'foot', 1, true) or string.find(lname, 'pedestal', 1, true) then
                score = 60
            elseif d == model.PrimaryPart then
                score = 40
            end

            if not best or score > bestScore or (score == bestScore and d.Position.Y < best.Position.Y) then
                best = d
                bestScore = score
            end
        end
    end

    return best
end

local function getGroundAnchorAttachment(model)
    local a = model:FindFirstChild('GroundAnchor', true)
    if a and a:IsA('Attachment') then
        return a
    end
    return nil
end

local function getModelGroundPoint(model, groundAnchor, anchor)
    if groundAnchor and groundAnchor.Parent then
        return groundAnchor.WorldPosition
    end

    if anchor and anchor.Parent then
        return anchor.CFrame:PointToWorldSpace(Vector3.new(0, -anchor.Size.Y * 0.5, 0))
    end

    local boxCF, boxSize = model:GetBoundingBox()
    return Vector3.new(boxCF.Position.X, boxCF.Position.Y - boxSize.Y * 0.5, boxCF.Position.Z)
end

local function placeModelOnGround(model, targetPos, groundAnchor, anchor)
    local refPoint = getModelGroundPoint(model, groundAnchor, anchor)
    local delta = targetPos - refPoint
    if delta.Magnitude < 1e-5 then
        return
    end
    model:PivotTo(model:GetPivot() + delta)
end

local function isPlacementValidClient(pos)
    local mapMin = Vector3.new(-180, 0, -120)
    local mapMax = Vector3.new(180, 0, 120)
    if pos.X < mapMin.X or pos.X > mapMax.X or pos.Z < mapMin.Z or pos.Z > mapMax.Z then
        return false
    end

    local waypoints = sortedWaypoints()
    if #waypoints >= 2 then
        local minPathDist = 9
        for i = 1, #waypoints - 1 do
            local a = waypoints[i].Position
            local b = waypoints[i + 1].Position
            local ab = b - a
            local denom = ab:Dot(ab)
            if denom > 0 then
                local ap = pos - a
                local t = math.clamp(ap:Dot(ab) / denom, 0, 1)
                local closest = a + ab * t
                local dist = (Vector3.new(closest.X, pos.Y, closest.Z) - pos).Magnitude
                if dist < minPathDist then
                    return false
                end
            end
        end
    end

    local towerFolder = Workspace:FindFirstChild('TD_Towers')
    if towerFolder then
        for _, child in ipairs(towerFolder:GetChildren()) do
            local towerPos
            if child:IsA('Model') then
                towerPos = child:GetPivot().Position
            elseif child:IsA('BasePart') then
                towerPos = child.Position
            end

            if towerPos and (flattenXZ(towerPos - pos)).Magnitude < 6 then
                return false
            end
        end
    end

    return true
end

local function clearPreview()
    if previewModel then
        previewModel:Destroy()
        previewModel = nil
    end

    previewGroundAnchor = nil
    previewAnchorPart = nil
    previewVisualPos = nil
end

local function rebuildPreview()
    clearPreview()

    if not selectedTowerKey then
        previewIsValid = false
        previewGroundAnchor = nil
        previewAnchorPart = nil
        previewVisualPos = nil
        return
    end

    local template = getTemplateForTower(selectedTowerKey)
    if template then
        previewModel = template:Clone()
    else
        previewModel = buildFallbackPreview(selectedTowerKey)
    end

    applyTowerModelFixups(previewModel, selectedTowerKey)

    previewModel.Name = 'TD_Preview_' .. selectedTowerKey
    previewModel.Parent = Workspace

    for _, d in ipairs(previewModel:GetDescendants()) do
        if d:IsA('BasePart') then
            d.Anchored = true
            d.CanCollide = false
            d.CastShadow = false
        end
    end

    if not firstBasePart(previewModel) then
        previewModel:Destroy()
        previewModel = nil
        previewIsValid = false
        previewGroundAnchor = nil
        previewAnchorPart = nil
        previewVisualPos = nil
        return
    end

    previewGroundAnchor = getGroundAnchorAttachment(previewModel)
    previewAnchorPart = getPlacementAnchorPart(previewModel)
    previewVisualPos = nil

    setPreviewTint(previewModel, false)
    previewIsValid = false
end

local RANGE_SEGMENTS = 72

local function createRangePart(color)
    local ring = Instance.new('Model')
    ring.Name = 'RangePreviewRing'
    ring:SetAttribute('Segments', RANGE_SEGMENTS)

    for i = 1, RANGE_SEGMENTS do
        local seg = Instance.new('Part')
        seg.Name = 'S' .. i
        seg.Anchored = true
        seg.CanCollide = false
        seg.CanQuery = false
        seg.CanTouch = false
        seg.Material = Enum.Material.Neon
        seg.Color = color
        seg.Transparency = 0.25
        seg.CastShadow = false
        seg.Size = Vector3.new(0.3, 0.08, 0.8)
        seg.Parent = ring
    end

    ring.Parent = Workspace
    return ring
end

local function setRangePart(ring, center, radius, color, transparency)
    if not ring then
        return
    end

    local r = math.max(1, radius)
    local y = getGroundYAt(center) + 0.06
    local count = ring:GetAttribute('Segments') or RANGE_SEGMENTS

    local segLen = math.max(0.35, (2 * math.pi * r / count) * 0.96)
    local segThick = math.clamp(r * 0.022, 0.22, 0.72)

    for i = 1, count do
        local seg = ring:FindFirstChild('S' .. i)
        if seg and seg:IsA('BasePart') then
            local t = (i - 1) / count
            local a0 = t * math.pi * 2
            local x = center.X + math.cos(a0) * r
            local z = center.Z + math.sin(a0) * r

            local tangent = Vector3.new(-math.sin(a0), 0, math.cos(a0))
            seg.CFrame = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x, y, z) + tangent, Vector3.new(0, 1, 0))
            seg.Size = Vector3.new(segThick, 0.08, segLen)
            seg.Color = color
            seg.Transparency = transparency
        end
    end
end

local function clearRangeParts()
    if currentRangePart then
        currentRangePart:Destroy()
        currentRangePart = nil
    end
    if nextRangePart then
        nextRangePart:Destroy()
        nextRangePart = nil
    end
end

local function makeCorner(parent, radius)
    local c = Instance.new('UICorner')
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
end

local function makeStroke(parent, color, thickness, transparency)
    local s = Instance.new('UIStroke')
    s.Color = color
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.Parent = parent
end

local function setLivesBar(lives)
    local pct = math.clamp((lives or 0) / math.max(1, Config.BaseLives), 0, 1)
    livesFill.Size = UDim2.fromScale(pct, 1)
    livesFill.BackgroundColor3 = Color3.fromRGB(
        math.floor(240 - 160 * pct),
        math.floor(80 + 140 * pct),
        102
    )
    livesLabel.Text = string.format('Base HP  %d / %d', lives or 0, Config.BaseLives)
end

local function setSlotVisual(slot, selected, affordable)
    slot.Button.BackgroundColor3 = selected and colors.slotSelected or colors.slot
    slot.Border.Color = selected and colors.accent or Color3.fromRGB(54, 76, 98)
    slot.KeyLabel.TextColor3 = selected and colors.accent or colors.subtext

    if slot.TowerKey == nil then
        slot.NameLabel.TextColor3 = selected and colors.accent or colors.text
        slot.CostLabel.TextColor3 = colors.subtext
    else
        slot.NameLabel.TextColor3 = affordable and (selected and colors.accent or colors.text) or Color3.fromRGB(130, 142, 160)
        slot.CostLabel.TextColor3 = affordable and Color3.fromRGB(167, 224, 246) or colors.bad
    end
end

local function updateSlotVisuals()
    for _, slot in pairs(slotButtons) do
        local selected = (slot.TowerKey == selectedTowerKey)

        local affordable = true
        if slot.TowerKey then
            local cost = (Config.Towers[slot.TowerKey] and Config.Towers[slot.TowerKey].Cost) or 0
            affordable = (currentState.money or 0) >= cost
        end

        setSlotVisual(slot, selected, affordable)
    end
end

local function setActionMessage(text, duration)
    actionMessageText = text or ''
    actionMessageUntil = os.clock() + (duration or 1.5)
    actionMessageLabel.Text = actionMessageText
end

local function getTowerNextUpgradePreview(towerModel)
    if not towerModel then
        return nil
    end

    local towerKey = towerModel:GetAttribute('TowerKey')
    local level = tonumber(towerModel:GetAttribute('Level')) or 0
    local def = towerKey and Config.Towers[towerKey]
    if not def then
        return nil
    end

    local up = def.Upgrades and def.Upgrades[level + 1]
    if not up then
        return nil
    end

    local curDamage = tonumber(towerModel:GetAttribute('Damage')) or 0
    local curRange = tonumber(towerModel:GetAttribute('Range')) or 0
    local curRate = tonumber(towerModel:GetAttribute('FireRate')) or 0

    return {
        cost = up.Cost or 0,
        nextDamage = curDamage * (up.DamageMult or 1),
        nextRange = curRange + (up.RangeAdd or 0),
        nextRate = curRate * (up.FireRateMult or 1),
    }
end

local function updateHUD()
    waveLabel.Text = string.format('Wave  %d / %d  |  %s', currentState.wave or 0, currentState.maxWave or 0, tostring(currentState.waveName))
    creditsLabel.Text = string.format('Credits: %d', currentState.money or 0)
    statusLabel.Text = string.format('Status: %s', tostring(currentState.status))
    totalTimeLabel.Text = 'Time: ' .. formatTime(currentState.elapsedSeconds or 0)

    local intermission = tonumber(currentState.intermissionRemaining) or 0
    if tostring(currentState.status) == 'Intermission' then
        intermissionLabel.Text = string.format('Next Wave In: %ds', intermission)
        intermissionLabel.TextColor3 = Color3.fromRGB(255, 220, 130)
    else
        intermissionLabel.Text = ''
    end

    if selectedTowerKey then
        placementLabel.Text = previewIsValid and 'Placement Valid' or 'Placement Invalid'
        placementLabel.TextColor3 = previewIsValid and colors.good or colors.bad
    else
        placementLabel.Text = 'Hands Equipped (No Placement)'
        placementLabel.TextColor3 = colors.subtext
    end

    setLivesBar(currentState.lives or 0)
    updateSlotVisuals()
end

local function getEnemyModelFromTarget(target)
    local enemiesFolder = Workspace:FindFirstChild('TD_Enemies')
    if not enemiesFolder then
        return nil
    end

    local node = target
    while node and node ~= Workspace do
        if node:IsA('Model') and node.Parent == enemiesFolder then
            return node
        end
        node = node.Parent
    end

    return nil
end

local function getTowerModelFromTarget(target)
    local towersFolder = Workspace:FindFirstChild('TD_Towers')
    if not towersFolder then
        return nil
    end

    local node = target
    while node and node ~= Workspace do
        if node:IsA('Model') and node.Parent == towersFolder then
            return node
        end
        node = node.Parent
    end

    return nil
end

local function updateHoverEnemyPanel()
    if selectedTowerKey then
        hoverEnemyPanel.Visible = false
        return
    end

    local target = mouse.Target
    local enemyModel = getEnemyModelFromTarget(target)

    if not enemyModel then
        hoverEnemyPanel.Visible = false
        return
    end

    local hp = enemyModel:GetAttribute('HP')
    local maxHp = enemyModel:GetAttribute('MaxHP')
    if type(hp) ~= 'number' or type(maxHp) ~= 'number' then
        hoverEnemyPanel.Visible = false
        return
    end

    local enemyName = enemyModel:GetAttribute('EnemyName')
    if type(enemyName) ~= 'string' or enemyName == '' then
        enemyName = enemyModel.Name
    end

    local pct = math.clamp(hp / math.max(1, maxHp), 0, 1)
    hoverEnemyName.Text = enemyName
    hoverEnemyHpText.Text = string.format('%d / %d', math.floor(hp + 0.5), math.floor(maxHp + 0.5))
    hoverEnemyHpFill.Size = UDim2.fromScale(pct, 1)
    hoverEnemyHpFill.BackgroundColor3 = Color3.fromRGB(
        math.floor(240 - 160 * pct),
        math.floor(80 + 140 * pct),
        102
    )

    local mousePos = UserInputService:GetMouseLocation()
    hoverEnemyPanel.Position = UDim2.fromOffset(mousePos.X + 20, mousePos.Y - 12)
    hoverEnemyPanel.Visible = true
end

local function updateTowerPanel()
    if selectedTowerKey then
        showUpgradePreview = false
        towerPanel.Visible = false
        return
    end

    if not selectedPlacedTower or not selectedPlacedTower.Parent then
        showUpgradePreview = false
        towerPanel.Visible = false
        return
    end

    local owner = selectedPlacedTower:GetAttribute('OwnerUserId')
    if owner ~= player.UserId then
        showUpgradePreview = false
        towerPanel.Visible = false
        return
    end

    local towerKey = selectedPlacedTower:GetAttribute('TowerKey')
    local towerDef = towerKey and Config.Towers[towerKey]

    local displayName = (towerDef and towerDef.DisplayName) or tostring(towerKey or 'Tower')
    local level = selectedPlacedTower:GetAttribute('Level') or 0
    local damage = selectedPlacedTower:GetAttribute('Damage') or 0
    local range = selectedPlacedTower:GetAttribute('Range') or 0
    local fireRate = selectedPlacedTower:GetAttribute('FireRate') or 0
    local targetMode = selectedPlacedTower:GetAttribute('TargetMode') or 'First'
    local nextUpgradeCost = selectedPlacedTower:GetAttribute('NextUpgradeCost') or 0
    local sellValue = selectedPlacedTower:GetAttribute('SellValue') or 0

    towerPanelTitle.Text = string.format('%s  (Lv.%d)', displayName, level)

    local lines = {
        string.format('DMG: %.2f', damage),
        string.format('Range: %.2f', range),
        string.format('Rate: %.2fs', fireRate),
        string.format('Target: %s', tostring(targetMode)),
        string.format('Sell: %d', sellValue),
    }

    local nextPreview = getTowerNextUpgradePreview(selectedPlacedTower)
    if showUpgradePreview and nextPreview then
        table.insert(lines, '--- Next Upgrade ---')
        table.insert(lines, string.format('Cost: %d', nextPreview.cost))
        table.insert(lines, string.format('Next DMG: %.2f', nextPreview.nextDamage))
        table.insert(lines, string.format('Next Range: %.2f', nextPreview.nextRange))
        table.insert(lines, string.format('Next Rate: %.2fs', nextPreview.nextRate))
    end

    towerPanelStats.Text = table.concat(lines, '\n')

    if nextUpgradeCost > 0 then
        towerPanelUpgradeBtn.Text = string.format('Upgrade  (%d)', nextUpgradeCost)
        local canAfford = (currentState.money or 0) >= nextUpgradeCost
        towerPanelUpgradeBtn.AutoButtonColor = canAfford
        towerPanelUpgradeBtn.Active = canAfford
        towerPanelUpgradeBtn.BackgroundColor3 = canAfford and Color3.fromRGB(28, 82, 64) or Color3.fromRGB(58, 58, 68)
        towerPanelUpgradeBtn.TextColor3 = canAfford and colors.text or colors.subtext
    else
        towerPanelUpgradeBtn.Text = 'MAX LEVEL'
        towerPanelUpgradeBtn.AutoButtonColor = false
        towerPanelUpgradeBtn.Active = false
        towerPanelUpgradeBtn.BackgroundColor3 = Color3.fromRGB(58, 58, 68)
        towerPanelUpgradeBtn.TextColor3 = colors.subtext
    end

    towerPanelSellBtn.Text = string.format('Sell  (+%d)', sellValue)
    if towerPanelTargetBtn then
        towerPanelTargetBtn.Text = string.format('Target: %s  (R)', tostring(targetMode))
    end
    towerPanel.Visible = true
end

local function updateRangeShowcase()
    local showCurrent = false
    local currentCenter, currentRange
    local showNext = false
    local nextCenter, nextRange

    if selectedTowerKey then
        if previewModel and mouse.Hit then
            local def = Config.Towers[selectedTowerKey]
            if def then
                showCurrent = true
                currentCenter = previewPos
                currentRange = def.Range or 0
            end
        end
    elseif selectedPlacedTower and selectedPlacedTower.Parent then
        local owner = selectedPlacedTower:GetAttribute('OwnerUserId')
        if owner == player.UserId then
            showCurrent = true
            currentCenter = selectedPlacedTower:GetPivot().Position
            currentRange = tonumber(selectedPlacedTower:GetAttribute('Range')) or 0

            if showUpgradePreview then
                local nextPreview = getTowerNextUpgradePreview(selectedPlacedTower)
                if nextPreview then
                    showNext = true
                    nextCenter = currentCenter
                    nextRange = nextPreview.nextRange
                end
            end
        end
    end

    if showCurrent and currentRange and currentRange > 0 then
        if not currentRangePart then
            currentRangePart = createRangePart(colors.rangeCurrent)
        end
        setRangePart(currentRangePart, currentCenter, currentRange, colors.rangeCurrent, 0.72)
    elseif currentRangePart then
        currentRangePart:Destroy()
        currentRangePart = nil
    end

    if showNext and nextRange and nextRange > 0 then
        if not nextRangePart then
            nextRangePart = createRangePart(colors.rangeNext)
        end
        setRangePart(nextRangePart, nextCenter, nextRange, colors.rangeNext, 0.78)
    elseif nextRangePart then
        nextRangePart:Destroy()
        nextRangePart = nil
    end
end

local function setSelectedTower(key)
    if key ~= nil and not Config.Towers[key] then
        return
    end

    selectedTowerKey = key
    selectedPlacedTower = nil
    showUpgradePreview = false

    rebuildPreview()
    updateHUD()
    updateTowerPanel()
end

local function trySelectPlacedTowerFromMouse()
    local target = mouse.Target
    local towerModel = getTowerModelFromTarget(target)

    if towerModel and towerModel:GetAttribute('OwnerUserId') == player.UserId then
        selectedPlacedTower = towerModel
    else
        selectedPlacedTower = nil
    end

    showUpgradePreview = false
    updateTowerPanel()
end

local function invokeTowerAction(action)
    if not selectedPlacedTower or not selectedPlacedTower.Parent then
        return
    end

    local towerId = selectedPlacedTower:GetAttribute('TowerId')
    if type(towerId) ~= 'number' then
        return
    end

    local result
    local ok, err = pcall(function()
        result = TowerActionRemote:InvokeServer(action, towerId)
    end)

    if not ok then
        setActionMessage('Action failed: ' .. tostring(err), 2)
        return
    end

    if type(result) ~= 'table' then
        setActionMessage('Action failed', 1.6)
        return
    end

    if result.ok then
        setActionMessage(result.message or (action .. ' complete'), 1.2)
        if action == 'Sell' then
            selectedPlacedTower = nil
            showUpgradePreview = false
        end
    else
        setActionMessage(result.message or 'Action rejected', 1.8)
    end

    updateTowerPanel()
end

local gui = Instance.new('ScreenGui')
gui.Name = 'TDHud'
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild('PlayerGui')

local topPanel = Instance.new('Frame')
topPanel.Size = UDim2.new(0, 700, 0, 118)
topPanel.Position = UDim2.new(0.5, -350, 0, 18)
topPanel.BackgroundColor3 = colors.panel
topPanel.BorderSizePixel = 0
topPanel.Parent = gui
makeCorner(topPanel, 14)
makeStroke(topPanel, Color3.fromRGB(42, 70, 96), 1.2, 0)

local title = Instance.new('TextLabel')
title.Size = UDim2.new(0.62, -24, 0, 24)
title.Position = UDim2.fromOffset(12, 8)
title.BackgroundTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = colors.text
title.Text = 'Space Base Defense'
title.Parent = topPanel

totalTimeLabel = Instance.new('TextLabel')
totalTimeLabel.Size = UDim2.new(0.38, -12, 0, 22)
totalTimeLabel.Position = UDim2.new(0.62, 0, 0, 10)
totalTimeLabel.BackgroundTransparency = 1
totalTimeLabel.TextXAlignment = Enum.TextXAlignment.Right
totalTimeLabel.Font = Enum.Font.GothamSemibold
totalTimeLabel.TextSize = 14
totalTimeLabel.TextColor3 = Color3.fromRGB(255, 220, 130)
totalTimeLabel.Text = 'Time: 00:00'
totalTimeLabel.Parent = topPanel

waveLabel = Instance.new('TextLabel')
waveLabel.Size = UDim2.new(1, -24, 0, 20)
waveLabel.Position = UDim2.fromOffset(12, 32)
waveLabel.BackgroundTransparency = 1
waveLabel.TextXAlignment = Enum.TextXAlignment.Left
waveLabel.Font = Enum.Font.GothamSemibold
waveLabel.TextSize = 14
waveLabel.TextColor3 = colors.subtext
waveLabel.Parent = topPanel

creditsLabel = Instance.new('TextLabel')
creditsLabel.Size = UDim2.new(0.34, -8, 0, 20)
creditsLabel.Position = UDim2.fromOffset(12, 54)
creditsLabel.BackgroundTransparency = 1
creditsLabel.TextXAlignment = Enum.TextXAlignment.Left
creditsLabel.Font = Enum.Font.Gotham
creditsLabel.TextSize = 14
creditsLabel.TextColor3 = colors.text
creditsLabel.Parent = topPanel

statusLabel = Instance.new('TextLabel')
statusLabel.Size = UDim2.new(0.34, -8, 0, 20)
statusLabel.Position = UDim2.new(0.34, 6, 0, 54)
statusLabel.BackgroundTransparency = 1
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 14
statusLabel.TextColor3 = colors.text
statusLabel.Parent = topPanel

intermissionLabel = Instance.new('TextLabel')
intermissionLabel.Size = UDim2.new(0.32, -8, 0, 20)
intermissionLabel.Position = UDim2.new(0.68, 4, 0, 54)
intermissionLabel.BackgroundTransparency = 1
intermissionLabel.TextXAlignment = Enum.TextXAlignment.Right
intermissionLabel.Font = Enum.Font.GothamSemibold
intermissionLabel.TextSize = 14
intermissionLabel.TextColor3 = Color3.fromRGB(255, 220, 130)
intermissionLabel.Parent = topPanel

livesLabel = Instance.new('TextLabel')
livesLabel.Size = UDim2.new(1, -24, 0, 18)
livesLabel.Position = UDim2.fromOffset(12, 75)
livesLabel.BackgroundTransparency = 1
livesLabel.TextXAlignment = Enum.TextXAlignment.Left
livesLabel.Font = Enum.Font.GothamSemibold
livesLabel.TextSize = 13
livesLabel.TextColor3 = colors.subtext
livesLabel.Parent = topPanel

local livesBarBG = Instance.new('Frame')
livesBarBG.Size = UDim2.new(1, -24, 0, 13)
livesBarBG.Position = UDim2.fromOffset(12, 94)
livesBarBG.BackgroundColor3 = Color3.fromRGB(36, 42, 55)
livesBarBG.BorderSizePixel = 0
livesBarBG.Parent = topPanel
makeCorner(livesBarBG, 7)

livesFill = Instance.new('Frame')
livesFill.Size = UDim2.fromScale(1, 1)
livesFill.BackgroundColor3 = colors.good
livesFill.BorderSizePixel = 0
livesFill.Parent = livesBarBG
makeCorner(livesFill, 7)

local hotbar = Instance.new('Frame')
hotbar.Size = UDim2.new(0, 980, 0, 122)
hotbar.Position = UDim2.new(0.5, -490, 1, -138)
hotbar.BackgroundColor3 = colors.panel
hotbar.BorderSizePixel = 0
hotbar.Parent = gui
makeCorner(hotbar, 16)
makeStroke(hotbar, Color3.fromRGB(42, 70, 96), 1.2, 0)

local hotbarTitle = Instance.new('TextLabel')
hotbarTitle.Size = UDim2.new(0.48, -12, 0, 22)
hotbarTitle.Position = UDim2.fromOffset(12, 8)
hotbarTitle.BackgroundTransparency = 1
hotbarTitle.TextXAlignment = Enum.TextXAlignment.Left
hotbarTitle.Font = Enum.Font.GothamBold
hotbarTitle.TextSize = 16
hotbarTitle.TextColor3 = colors.text
hotbarTitle.Text = 'Hotbar'
hotbarTitle.Parent = hotbar

placementLabel = Instance.new('TextLabel')
placementLabel.Size = UDim2.new(0.52, -12, 0, 22)
placementLabel.Position = UDim2.new(0.48, 0, 0, 8)
placementLabel.BackgroundTransparency = 1
placementLabel.TextXAlignment = Enum.TextXAlignment.Right
placementLabel.Font = Enum.Font.GothamSemibold
placementLabel.TextSize = 14
placementLabel.Parent = hotbar

actionMessageLabel = Instance.new('TextLabel')
actionMessageLabel.Size = UDim2.new(1, -24, 0, 18)
actionMessageLabel.Position = UDim2.fromOffset(12, 28)
actionMessageLabel.BackgroundTransparency = 1
actionMessageLabel.TextXAlignment = Enum.TextXAlignment.Left
actionMessageLabel.Font = Enum.Font.Gotham
actionMessageLabel.TextSize = 13
actionMessageLabel.TextColor3 = Color3.fromRGB(186, 214, 245)
actionMessageLabel.Text = ''
actionMessageLabel.Parent = hotbar

local slots = Instance.new('Frame')
slots.Size = UDim2.new(1, -20, 0, 72)
slots.Position = UDim2.fromOffset(10, 46)
slots.BackgroundTransparency = 1
slots.Parent = hotbar

local slotLayout = Instance.new('UIListLayout')
slotLayout.FillDirection = Enum.FillDirection.Horizontal
slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
slotLayout.Padding = UDim.new(0, 12)
slotLayout.Parent = slots

for _, slotInfo in ipairs(hotbarSlots) do
    local btn = Instance.new('TextButton')
    btn.Size = UDim2.fromOffset(230, 70)
    btn.BackgroundColor3 = colors.slot
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Text = ''
    btn.Parent = slots
    makeCorner(btn, 10)

    local border = Instance.new('UIStroke')
    border.Thickness = 1.2
    border.Color = Color3.fromRGB(54, 76, 98)
    border.Parent = btn

    local key = Instance.new('TextLabel')
    key.Size = UDim2.fromOffset(24, 18)
    key.Position = UDim2.fromOffset(10, 8)
    key.BackgroundTransparency = 1
    key.Font = Enum.Font.GothamBold
    key.TextSize = 13
    key.TextXAlignment = Enum.TextXAlignment.Left
    key.TextColor3 = colors.subtext
    key.Text = slotInfo.keyText
    key.Parent = btn

    local name = Instance.new('TextLabel')
    name.Size = UDim2.new(1, -20, 0, 24)
    name.Position = UDim2.fromOffset(10, 22)
    name.BackgroundTransparency = 1
    name.Font = Enum.Font.GothamSemibold
    name.TextSize = 15
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.TextColor3 = colors.text
    name.Text = slotInfo.label
    name.Parent = btn

    local cost = Instance.new('TextLabel')
    cost.Size = UDim2.new(1, -20, 0, 16)
    cost.Position = UDim2.fromOffset(10, 50)
    cost.BackgroundTransparency = 1
    cost.Font = Enum.Font.Gotham
    cost.TextSize = 13
    cost.TextXAlignment = Enum.TextXAlignment.Left
    cost.TextColor3 = colors.subtext
    if slotInfo.towerKey then
        local c = (Config.Towers[slotInfo.towerKey] and Config.Towers[slotInfo.towerKey].Cost) or 0
        cost.Text = string.format('Cost: %d', c)
    else
        cost.Text = 'Inspect / Manage Towers'
    end
    cost.Parent = btn

    btn.MouseButton1Click:Connect(function()
        setSelectedTower(slotInfo.towerKey)
    end)

    slotButtons[slotInfo.slotId] = {
        SlotId = slotInfo.slotId,
        TowerKey = slotInfo.towerKey,
        Button = btn,
        Border = border,
        KeyLabel = key,
        NameLabel = name,
        CostLabel = cost,
    }
end

towerPanel = Instance.new('Frame')
towerPanel.Size = UDim2.fromOffset(280, 272)
towerPanel.Position = UDim2.new(1, -296, 0.5, -101)
towerPanel.BackgroundColor3 = colors.panelAlt
towerPanel.BorderSizePixel = 0
towerPanel.Visible = false
towerPanel.Parent = gui
makeCorner(towerPanel, 12)
makeStroke(towerPanel, Color3.fromRGB(62, 88, 114), 1.2, 0)

towerPanelTitle = Instance.new('TextLabel')
towerPanelTitle.Size = UDim2.new(1, -16, 0, 24)
towerPanelTitle.Position = UDim2.fromOffset(8, 8)
towerPanelTitle.BackgroundTransparency = 1
towerPanelTitle.TextXAlignment = Enum.TextXAlignment.Left
towerPanelTitle.Font = Enum.Font.GothamBold
towerPanelTitle.TextSize = 15
towerPanelTitle.TextColor3 = colors.text
towerPanelTitle.Text = 'Tower'
towerPanelTitle.Parent = towerPanel

towerPanelStats = Instance.new('TextLabel')
towerPanelStats.Size = UDim2.new(1, -16, 0, 124)
towerPanelStats.Position = UDim2.fromOffset(8, 36)
towerPanelStats.BackgroundTransparency = 1
towerPanelStats.TextXAlignment = Enum.TextXAlignment.Left
towerPanelStats.TextYAlignment = Enum.TextYAlignment.Top
towerPanelStats.Font = Enum.Font.Code
towerPanelStats.TextSize = 14
towerPanelStats.TextColor3 = colors.subtext
towerPanelStats.Text = ''
towerPanelStats.Parent = towerPanel

towerPanelUpgradeBtn = Instance.new('TextButton')
towerPanelUpgradeBtn.Size = UDim2.fromOffset(126, 34)
towerPanelUpgradeBtn.Position = UDim2.fromOffset(8, 220)
towerPanelUpgradeBtn.AutoButtonColor = true
towerPanelUpgradeBtn.BackgroundColor3 = Color3.fromRGB(28, 82, 64)
towerPanelUpgradeBtn.TextColor3 = colors.text
towerPanelUpgradeBtn.Font = Enum.Font.GothamBold
towerPanelUpgradeBtn.TextSize = 13
towerPanelUpgradeBtn.Text = 'Upgrade'
towerPanelUpgradeBtn.Parent = towerPanel
makeCorner(towerPanelUpgradeBtn, 8)

towerPanelSellBtn = Instance.new('TextButton')
towerPanelSellBtn.Size = UDim2.fromOffset(126, 34)
towerPanelSellBtn.Position = UDim2.fromOffset(146, 220)
towerPanelSellBtn.AutoButtonColor = true
towerPanelSellBtn.BackgroundColor3 = Color3.fromRGB(82, 44, 52)
towerPanelSellBtn.TextColor3 = colors.text
towerPanelSellBtn.Font = Enum.Font.GothamBold
towerPanelSellBtn.TextSize = 13
towerPanelSellBtn.Text = 'Sell'
towerPanelSellBtn.Parent = towerPanel
makeCorner(towerPanelSellBtn, 8)


towerPanelTargetBtn = Instance.new('TextButton')
towerPanelTargetBtn.Size = UDim2.fromOffset(264, 30)
towerPanelTargetBtn.Position = UDim2.fromOffset(8, 184)
towerPanelTargetBtn.AutoButtonColor = true
towerPanelTargetBtn.BackgroundColor3 = Color3.fromRGB(34, 62, 96)
towerPanelTargetBtn.TextColor3 = colors.text
towerPanelTargetBtn.Font = Enum.Font.GothamBold
towerPanelTargetBtn.TextSize = 13
towerPanelTargetBtn.Text = 'Target: First  (R)'
towerPanelTargetBtn.Parent = towerPanel
makeCorner(towerPanelTargetBtn, 8)
hoverEnemyPanel = Instance.new('Frame')
hoverEnemyPanel.Size = UDim2.fromOffset(190, 62)
hoverEnemyPanel.Position = UDim2.fromOffset(300, 300)
hoverEnemyPanel.BackgroundColor3 = colors.panelAlt
hoverEnemyPanel.BorderSizePixel = 0
hoverEnemyPanel.Visible = false
hoverEnemyPanel.Parent = gui
makeCorner(hoverEnemyPanel, 10)
makeStroke(hoverEnemyPanel, Color3.fromRGB(62, 88, 114), 1.2, 0)

hoverEnemyName = Instance.new('TextLabel')
hoverEnemyName.Size = UDim2.new(1, -12, 0, 22)
hoverEnemyName.Position = UDim2.fromOffset(8, 5)
hoverEnemyName.BackgroundTransparency = 1
hoverEnemyName.TextXAlignment = Enum.TextXAlignment.Left
hoverEnemyName.Font = Enum.Font.GothamSemibold
hoverEnemyName.TextSize = 14
hoverEnemyName.TextColor3 = colors.text
hoverEnemyName.Text = 'Enemy'
hoverEnemyName.Parent = hoverEnemyPanel

hoverEnemyHpText = Instance.new('TextLabel')
hoverEnemyHpText.Size = UDim2.new(1, -12, 0, 16)
hoverEnemyHpText.Position = UDim2.fromOffset(8, 24)
hoverEnemyHpText.BackgroundTransparency = 1
hoverEnemyHpText.TextXAlignment = Enum.TextXAlignment.Left
hoverEnemyHpText.Font = Enum.Font.Gotham
hoverEnemyHpText.TextSize = 12
hoverEnemyHpText.TextColor3 = colors.subtext
hoverEnemyHpText.Text = '0 / 0'
hoverEnemyHpText.Parent = hoverEnemyPanel

local hoverBarBg = Instance.new('Frame')
hoverBarBg.Size = UDim2.new(1, -12, 0, 12)
hoverBarBg.Position = UDim2.fromOffset(8, 45)
hoverBarBg.BackgroundColor3 = Color3.fromRGB(40, 46, 58)
hoverBarBg.BorderSizePixel = 0
hoverBarBg.Parent = hoverEnemyPanel
makeCorner(hoverBarBg, 6)

hoverEnemyHpFill = Instance.new('Frame')
hoverEnemyHpFill.Size = UDim2.fromScale(1, 1)
hoverEnemyHpFill.BackgroundColor3 = colors.good
hoverEnemyHpFill.BorderSizePixel = 0
hoverEnemyHpFill.Parent = hoverBarBg
makeCorner(hoverEnemyHpFill, 6)

local keyMap = {
    [Enum.KeyCode.Zero] = nil,
    [Enum.KeyCode.One] = 'LaserTurret',
    [Enum.KeyCode.Two] = 'FrostBeam',
    [Enum.KeyCode.Three] = 'MissilePod',
    [Enum.KeyCode.Q] = nil,
}

StateUpdateRemote.OnClientEvent:Connect(function(state)
    if type(state) == 'table' then
        currentState = state
        updateHUD()
        updateTowerPanel()
    end
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then
        return
    end

    if keyMap[input.KeyCode] ~= nil or input.KeyCode == Enum.KeyCode.Zero or input.KeyCode == Enum.KeyCode.Q then
        setSelectedTower(keyMap[input.KeyCode])
        return
    end

    if input.KeyCode == Enum.KeyCode.U or input.KeyCode == Enum.KeyCode.E then
        invokeTowerAction('Upgrade')
    elseif input.KeyCode == Enum.KeyCode.Delete then
        invokeTowerAction('Sell')
    elseif input.KeyCode == Enum.KeyCode.R then
        invokeTowerAction('CycleTargetMode')
    end
end)

mouse.Button1Down:Connect(function()
    if selectedTowerKey then
        if previewModel and previewIsValid then
            PlaceTowerRemote:FireServer(selectedTowerKey, previewPos)
        end
        return
    end

    trySelectPlacedTowerFromMouse()
end)

towerPanelUpgradeBtn.MouseButton1Click:Connect(function()
    invokeTowerAction('Upgrade')
end)

towerPanelSellBtn.MouseButton1Click:Connect(function()
    invokeTowerAction('Sell')
end)

towerPanelTargetBtn.MouseButton1Click:Connect(function()
    invokeTowerAction('CycleTargetMode')
end)

towerPanelUpgradeBtn.MouseEnter:Connect(function()
    showUpgradePreview = true
    updateTowerPanel()
end)

towerPanelUpgradeBtn.MouseLeave:Connect(function()
    showUpgradePreview = false
    updateTowerPanel()
end)

RunService.RenderStepped:Connect(function(dt)
    if selectedTowerKey and previewModel then
        local groundPos = getCursorGroundPlacement()
        if groundPos then
            previewPos = groundPos

            if not previewVisualPos then
                previewVisualPos = groundPos
            else
                local smoothAlpha = 1 - math.exp(-PREVIEW_SMOOTH_SPEED * math.max(0, dt or 0))
                previewVisualPos = previewVisualPos:Lerp(groundPos, math.clamp(smoothAlpha, 0, 1))
            end

            placeModelOnGround(previewModel, previewVisualPos, previewGroundAnchor, previewAnchorPart)

            local valid = isPlacementValidClient(previewPos)
            if valid ~= previewIsValid then
                previewIsValid = valid
                setPreviewTint(previewModel, previewIsValid)
                updateHUD()
            else
                previewIsValid = valid
            end
        end
    end

    updateRangeShowcase()
    updateHoverEnemyPanel()
    updateTowerPanel()

    if actionMessageUntil > 0 and os.clock() <= actionMessageUntil then
        actionMessageLabel.Text = actionMessageText
    else
        actionMessageLabel.Text = ''
    end
end)

setSelectedTower('LaserTurret')
updateHUD()

player.AncestryChanged:Connect(function(_, parent)
    if not parent then
        clearPreview()
        clearRangeParts()
    end
end)
