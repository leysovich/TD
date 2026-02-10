local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Workspace = game:GetService('Workspace')
local Debris = game:GetService('Debris')
local PhysicsService = game:GetService('PhysicsService')

local TD = ReplicatedStorage:WaitForChild('TD')
local Config = require(TD:WaitForChild('Config'))
local Remotes = TD:WaitForChild('Remotes')
local PlaceTowerRemote = Remotes:WaitForChild('PlaceTower')
local StateUpdateRemote = Remotes:WaitForChild('StateUpdate')
local TowerActionRemote = Remotes:WaitForChild('TowerAction')

local Assets = TD:WaitForChild('Assets')
local TowerModels = Assets:WaitForChild('TowerModels')
local EnemyModels = Assets:WaitForChild('EnemyModels')

local Map = Workspace:WaitForChild('TD_Map')
local WaypointsFolder = Map:WaitForChild('Waypoints')
local TowersFolder = Workspace:WaitForChild('TD_Towers')
local EnemiesFolder = Workspace:WaitForChild('TD_Enemies')

local playerState = {}
local towers = {}
local towerById = {}
local enemies = {}

local nextTowerId = 1
local currentWave = 0
local waveName = 'Preparing'
local lives = Config.BaseLives
local gameStatus = 'Intermission'
local intermissionEndsAt = 0
local matchStartAt = os.clock()

local DEFAULT_WALK_ANIMS = {
    [Enum.HumanoidRigType.R6] = 'rbxassetid://180426354',
    [Enum.HumanoidRigType.R15] = 'rbxassetid://507777826',
}

local TARGET_MODES = {'First', 'Last', 'Strongest', 'Closest'}
local TARGET_MODE_INDEX = {
    First = 1,
    Last = 2,
    Strongest = 3,
    Closest = 4,
}

local KILL_REWARD_MULT = 1.25

local ENEMY_COLLISION_GROUP = 'TDEnemyGhost'

local function ensureEnemyCollisionGroup()
    local exists = false
    for _, group in ipairs(PhysicsService:GetCollisionGroups()) do
        if group.name == ENEMY_COLLISION_GROUP then
            exists = true
            break
        end
    end

    if not exists then
        pcall(function()
            PhysicsService:CreateCollisionGroup(ENEMY_COLLISION_GROUP)
        end)
    end

    for _, group in ipairs(PhysicsService:GetCollisionGroups()) do
        pcall(function()
            PhysicsService:CollisionGroupSetCollidable(ENEMY_COLLISION_GROUP, group.name, false)
        end)
    end

    pcall(function()
        PhysicsService:CollisionGroupSetCollidable(ENEMY_COLLISION_GROUP, ENEMY_COLLISION_GROUP, false)
    end)
end

ensureEnemyCollisionGroup()

local SOUND_IDS = {
    Place = 'rbxasset://sounds/clickfast.wav',
    Upgrade = 'rbxasset://sounds/button.wav',
    Sell = 'rbxasset://sounds/electronicpingshort.wav',
    Hit = 'rbxasset://sounds/clickfast.wav',
    Death = 'rbxasset://sounds/uuhhh.wav',
    FireLaser = 'rbxasset://sounds/electronicpingshort.wav',
    FireMissile = 'rbxasset://sounds/button.wav',
    FireFrost = 'rbxasset://sounds/electronicpingshort.wav',
    BaseHit = 'rbxasset://sounds/uuhhh.wav',
}

local function flattenXZ(v)
    return Vector3.new(v.X, 0, v.Z)
end

local function signedAngleXZ(fromV, toV)
    local a = flattenXZ(fromV)
    local b = flattenXZ(toV)
    if a.Magnitude < 0.001 or b.Magnitude < 0.001 then
        return 0
    end
    a = a.Unit
    b = b.Unit
    return math.atan2(a:Cross(b).Y, a:Dot(b))
end

local function wrapAngleRad(angle)
    return math.atan2(math.sin(angle), math.cos(angle))
end

local function yawFromFlatDir(dir)
    if dir.Magnitude < 0.001 then
        return 0
    end
    return math.atan2(-dir.X, -dir.Z)
end

local function playSoundAt(position, soundId, volume, pitch)
    local holder = Instance.new('Part')
    holder.Name = 'SFX'
    holder.Anchored = true
    holder.CanCollide = false
    holder.Transparency = 1
    holder.Size = Vector3.new(0.2, 0.2, 0.2)
    holder.Position = position
    holder.Parent = Workspace

    local sound = Instance.new('Sound')
    sound.SoundId = soundId
    sound.Volume = volume or 0.6
    sound.PlaybackSpeed = pitch or 1
    sound.RollOffMaxDistance = 110
    sound.RollOffMinDistance = 8
    sound.Parent = holder

    pcall(function()
        sound:Play()
    end)

    Debris:AddItem(holder, 1.2)
end

local function createImpactVFX(position, color)
    local glow = Instance.new('Part')
    glow.Anchored = true
    glow.CanCollide = false
    glow.Shape = Enum.PartType.Ball
    glow.Material = Enum.Material.Neon
    glow.Color = color
    glow.Transparency = 0.15
    glow.Size = Vector3.new(0.8, 0.8, 0.8)
    glow.Position = position
    glow.Parent = Workspace

    local ring = Instance.new('Part')
    ring.Anchored = true
    ring.CanCollide = false
    ring.Material = Enum.Material.Neon
    ring.Color = color:Lerp(Color3.new(1, 1, 1), 0.2)
    ring.Transparency = 0.2
    ring.Size = Vector3.new(0.2, 1.2, 1.2)
    ring.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0)
    ring.Parent = Workspace

    task.spawn(function()
        local t = 0
        local duration = 0.16
        while t < duration and glow.Parent and ring.Parent do
            local dt = RunService.Heartbeat:Wait()
            t += dt
            local a = math.clamp(t / duration, 0, 1)

            local s1 = 0.8 + a * 2.0
            glow.Size = Vector3.new(s1, s1, s1)
            glow.Transparency = 0.15 + a * 0.8

            ring.Size = Vector3.new(0.2, 1.2 + a * 2.0, 1.2 + a * 2.0)
            ring.Transparency = 0.2 + a * 0.75
        end

        if glow.Parent then glow:Destroy() end
        if ring.Parent then ring:Destroy() end
    end)
end

local function createDeathEffect(position, color)
    createImpactVFX(position, color)

    local shock = Instance.new('Part')
    shock.Anchored = true
    shock.CanCollide = false
    shock.Material = Enum.Material.Neon
    shock.Color = color
    shock.Transparency = 0.25
    shock.Size = Vector3.new(0.2, 2, 2)
    shock.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(90), 0, 0)
    shock.Parent = Workspace

    task.spawn(function()
        local t = 0
        local duration = 0.24
        while t < duration and shock.Parent do
            local dt = RunService.Heartbeat:Wait()
            t += dt
            local a = math.clamp(t / duration, 0, 1)
            shock.Size = Vector3.new(0.2, 2 + a * 6, 2 + a * 6)
            shock.Transparency = 0.25 + a * 0.7
        end
        if shock.Parent then shock:Destroy() end
    end)

    playSoundAt(position, SOUND_IDS.Death, 0.55, 1)
end

local function flashEnemy(enemy)
    if not enemy or not enemy.model or not enemy.model.Parent then
        return
    end

    local now = os.clock()
    if enemy.flashUntil and enemy.flashUntil > now then
        return
    end
    enemy.flashUntil = now + 0.08

    local h = Instance.new('Highlight')
    h.FillColor = Color3.fromRGB(255, 90, 90)
    h.FillTransparency = 0.35
    h.OutlineColor = Color3.fromRGB(255, 170, 120)
    h.OutlineTransparency = 0.2
    h.DepthMode = Enum.HighlightDepthMode.Occluded
    h.Adornee = enemy.model
    h.Parent = enemy.model
    Debris:AddItem(h, 0.09)
end

local function getWaypoints()
    local list = WaypointsFolder:GetChildren()
    table.sort(list, function(a, b)
        local an = tonumber(string.match(a.Name, '%d+')) or 0
        local bn = tonumber(string.match(b.Name, '%d+')) or 0
        return an < bn
    end)
    return list
end

local waypoints = getWaypoints()

local function getIntermissionRemaining()
    if gameStatus ~= 'Intermission' then
        return 0
    end
    return math.max(0, math.ceil(intermissionEndsAt - os.clock()))
end

local function getElapsedSeconds()
    return math.max(0, math.floor(os.clock() - matchStartAt))
end

local function getModelRoot(model)
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

local function findDescendantByName(model, lowerName)
    for _, d in ipairs(model:GetDescendants()) do
        if string.lower(d.Name) == lowerName then
            return d
        end
    end
    return nil
end

local function findDescendantContaining(model, tokenLower)
    for _, d in ipairs(model:GetDescendants()) do
        if string.find(string.lower(d.Name), tokenLower, 1, true) then
            return d
        end
    end
    return nil
end

local function getNodePivot(node)
    if node:IsA('Model') then
        return node:GetPivot()
    elseif node:IsA('BasePart') then
        return node.CFrame
    end
    return nil
end

local function setNodePivot(node, cf)
    if node:IsA('Model') then
        node:PivotTo(cf)
    elseif node:IsA('BasePart') then
        node.CFrame = cf
    end
end

local function getMuzzlePosition(tower)
    local muzzle = tower.muzzle
    if muzzle and muzzle.Parent then
        if muzzle:IsA('Attachment') then
            return muzzle.WorldPosition
        elseif muzzle:IsA('BasePart') then
            return muzzle.Position
        end
    end

    return tower.root.Position + tower.root.CFrame.LookVector * math.max(2, tower.root.Size.Z * 0.5)
end

local function setTowerModelStatic(model)
    local root = getModelRoot(model)
    if not root then
        return nil
    end

    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA('BasePart') then
            d.Anchored = true
            d.CanCollide = false
            d.Massless = true
        end
    end

    root.CanCollide = true
    return root
end

local function chooseTopPrimaryPart(topModel, rootPosition)
    if topModel.PrimaryPart then
        return topModel.PrimaryPart
    end

    local bestPart = nil
    local bestScore = math.huge

    for _, d in ipairs(topModel:GetDescendants()) do
        if d:IsA('BasePart') then
            local dist = (d.Position - rootPosition).Magnitude
            local upBias = math.max(0, d.Position.Y - rootPosition.Y)
            local score = dist + upBias * 0.45

            local lname = string.lower(d.Name)
            if string.find(lname, 'pivot', 1, true) or string.find(lname, 'hinge', 1, true) then
                score -= 100
            end

            if score < bestScore then
                bestScore = score
                bestPart = d
            end
        end
    end

    if bestPart then
        topModel.PrimaryPart = bestPart
    end

    return bestPart
end

local function ensureModelCenterPivot(modelNode, rootPosition)
    if not modelNode or not modelNode:IsA('Model') then
        return nil
    end

    local pivot = modelNode:FindFirstChild('__AimCenterPivot')
    if pivot and not pivot:IsA('BasePart') then
        pivot:Destroy()
        pivot = nil
    end

    if not pivot then
        pivot = Instance.new('Part')
        pivot.Name = '__AimCenterPivot'
        pivot.Size = Vector3.new(0.2, 0.2, 0.2)
        pivot.Transparency = 1
        pivot.Anchored = true
        pivot.CanCollide = false
        pivot.CanQuery = false
        pivot.CanTouch = false
        pivot.Massless = true
        pivot.Parent = modelNode
    end

    local candidates = {}
    for _, d in ipairs(modelNode:GetDescendants()) do
        if d:IsA('BasePart') and d ~= pivot then
            table.insert(candidates, d)
        end
    end

    local pivotPos
    if rootPosition and #candidates > 0 then
        table.sort(candidates, function(p0, p1)
            return (p0.Position - rootPosition).Magnitude < (p1.Position - rootPosition).Magnitude
        end)

        local count = math.min(4, #candidates)
        local weighted = Vector3.zero
        local totalW = 0
        for i = 1, count do
            local part = candidates[i]
            local dist = (part.Position - rootPosition).Magnitude
            local w = 1 / math.max(0.25, dist)
            weighted += part.Position * w
            totalW += w
        end

        if totalW > 0 then
            pivotPos = weighted / totalW
        end
    end

    if not pivotPos then
        local boxCF = modelNode:GetBoundingBox()
        pivotPos = boxCF.Position
    end

    local modelPivot = modelNode:GetPivot()
    pivot.CFrame = CFrame.new(pivotPos) * modelPivot.Rotation

    modelNode.PrimaryPart = pivot
    return pivot
end

local function findAimNode(model, root)
    local explicit = findDescendantByName(model, 'aimpivot')
        or findDescendantByName(model, 'turretpivot')
        or findDescendantContaining(model, 'aimpivot')
        or findDescendantContaining(model, 'turretpivot')

    if explicit and explicit:IsA('BasePart') then
        return explicit
    end

    local top = model:FindFirstChild('Top', true)
    if top and top:IsA('Model') then
        chooseTopPrimaryPart(top, root.Position)
        if top.PrimaryPart then
            return top
        end
    elseif top and top:IsA('BasePart') then
        return top
    end

    local turret = model:FindFirstChild('Turret', true)
    if turret and turret:IsA('Model') then
        chooseTopPrimaryPart(turret, root.Position)
        if turret.PrimaryPart then
            return turret
        end
    elseif turret and turret:IsA('BasePart') then
        return turret
    end

    return model
end

local function prepareEnemyModel(model)
    local root = getModelRoot(model)
    if not root then
        return nil, false
    end

    local humanoid = model:FindFirstChildOfClass('Humanoid')
    local hasHumanoid = humanoid ~= nil

    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA('BasePart') then
            d.CanCollide = false
            d.CanTouch = false
            d.CanQuery = false
            d.Massless = true
            d.CollisionGroup = ENEMY_COLLISION_GROUP
        end
    end

    if hasHumanoid then
        humanoid.AutoRotate = false
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA('BasePart') then
                d.Anchored = (d == root)
            end
        end
    else
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA('BasePart') then
                d.Anchored = true
            end
        end
    end

    return root, hasHumanoid
end

local function startEnemyWalkAnimation(model)
    local humanoid = model:FindFirstChildOfClass('Humanoid')
    if not humanoid then
        return nil
    end

    local animator = humanoid:FindFirstChildOfClass('Animator')
    if not animator then
        animator = Instance.new('Animator')
        animator.Parent = humanoid
    end

    local anim
    for _, name in ipairs({'WalkAnimation', 'Walk', 'walk', 'Run', 'run'}) do
        local found = findDescendantByName(model, string.lower(name))
        if found and found:IsA('Animation') and found.AnimationId ~= '' then
            anim = found
            break
        end
    end

    if not anim then
        local defaultId = DEFAULT_WALK_ANIMS[humanoid.RigType]
        if defaultId then
            anim = Instance.new('Animation')
            anim.Name = 'GeneratedWalkAnimation'
            anim.AnimationId = defaultId
            anim.Parent = model
        end
    end

    if not anim then
        return nil
    end

    local track
    local ok = pcall(function()
        track = animator:LoadAnimation(anim)
    end)

    if not ok or not track then
        return nil
    end

    track.Looped = true
    track.Priority = Enum.AnimationPriority.Movement
    track:Play(0.15, 1, 1)
    return track
end

local function updateEnemyAttributes(enemy)
    if not enemy or not enemy.model or not enemy.model.Parent then
        return
    end

    enemy.model:SetAttribute('EnemyName', enemy.enemyName or enemy.model.Name)
    enemy.model:SetAttribute('HP', math.max(0, math.floor(enemy.hp + 0.5)))
    enemy.model:SetAttribute('MaxHP', math.max(1, math.floor(enemy.maxHp + 0.5)))
end

local function getNextUpgradeSpec(tower)
    local def = Config.Towers[tower.towerKey]
    if not def then
        return nil
    end

    local upgrades = def.Upgrades or {}
    return upgrades[tower.level + 1]
end

local function getTowerSellValue(tower)
    return math.floor((tower.spent or 0) * (Config.SellRefundRate or 0.65))
end

local function updateTowerAttributes(tower)
    if not tower.model or not tower.model.Parent then
        return
    end

    local nextUpgrade = getNextUpgradeSpec(tower)

    tower.model:SetAttribute('TowerId', tower.id)
    tower.model:SetAttribute('OwnerUserId', tower.owner and tower.owner.UserId or 0)
    tower.model:SetAttribute('TowerKey', tower.towerKey)
    tower.model:SetAttribute('Level', tower.level)
    tower.model:SetAttribute('Damage', math.floor(tower.damage * 100 + 0.5) / 100)
    tower.model:SetAttribute('Range', math.floor(tower.range * 100 + 0.5) / 100)
    tower.model:SetAttribute('FireRate', math.floor(tower.fireRate * 100 + 0.5) / 100)
    tower.model:SetAttribute('SellValue', getTowerSellValue(tower))
    tower.model:SetAttribute('NextUpgradeCost', nextUpgrade and nextUpgrade.Cost or 0)
    tower.model:SetAttribute('TargetMode', tower.targetMode or 'First')
end

local function clearUpgradeVisuals(tower)
    if not tower or not tower.model then
        return
    end

    local v = tower.model:FindFirstChild('_UpgradeVisuals')
    if v then
        v:Destroy()
    end
end

local function makeVisualPart(parent, name, size, cf, color, material, transparency, shape)
    local p = Instance.new('Part')
    p.Name = name
    p.Size = size
    p.CFrame = cf
    p.Color = color
    p.Material = material or Enum.Material.Metal
    p.Transparency = transparency or 0
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.Massless = true
    if shape then
        p.Shape = shape
    end
    p.Parent = parent
    return p
end

local function applyTowerUpgradeVisuals(tower)
    if not tower or not tower.model or not tower.model.Parent or not tower.root then
        return
    end

    clearUpgradeVisuals(tower)

    local level = tonumber(tower.level) or 0
    if level <= 0 then
        return
    end

    local root = tower.root
    local accent = root.Color
    local towerKey = tower.towerKey

    local folder = Instance.new('Folder')
    folder.Name = '_UpgradeVisuals'
    folder.Parent = tower.model

    if towerKey == 'LaserTurret' then
        if level >= 1 then
            makeVisualPart(folder, 'L1_RingA', Vector3.new(root.Size.X * 1.35, 0.1, root.Size.Z * 1.35), CFrame.new(root.Position.X, root.Position.Y - root.Size.Y * 0.45, root.Position.Z), accent, Enum.Material.Neon, 0.2)
        end
        if level >= 2 then
            local y = root.Position.Y + root.Size.Y * 0.26
            local x = root.Size.X * 0.55
            makeVisualPart(folder, 'L2_LeftFin', Vector3.new(0.2, 0.35, 1.05), CFrame.new(root.Position + root.CFrame.RightVector * -x + Vector3.new(0, y - root.Position.Y, 0)), accent:Lerp(Color3.new(1,1,1),0.18), Enum.Material.Metal, 0)
            makeVisualPart(folder, 'L2_RightFin', Vector3.new(0.2, 0.35, 1.05), CFrame.new(root.Position + root.CFrame.RightVector * x + Vector3.new(0, y - root.Position.Y, 0)), accent:Lerp(Color3.new(1,1,1),0.18), Enum.Material.Metal, 0)
        end
        if level >= 3 then
            local corePos = root.Position + root.CFrame.LookVector * (root.Size.Z * 0.22) + Vector3.new(0, root.Size.Y * 0.45, 0)
            makeVisualPart(folder, 'L3_Core', Vector3.new(0.42, 0.42, 0.42), CFrame.new(corePos), accent:Lerp(Color3.new(1,1,1),0.28), Enum.Material.Neon, 0.07, Enum.PartType.Ball)
            makeVisualPart(folder, 'L3_Halo', Vector3.new(1.1, 0.08, 1.1), CFrame.new(corePos - Vector3.new(0, 0.15, 0)), accent, Enum.Material.Neon, 0.16)
        end

    elseif towerKey == 'FrostBeam' then
        local frost = Color3.fromRGB(145, 215, 255)
        if level >= 1 then
            makeVisualPart(folder, 'L1_FrostRing', Vector3.new(root.Size.X * 1.28, 0.09, root.Size.Z * 1.28), CFrame.new(root.Position.X, root.Position.Y - root.Size.Y * 0.45, root.Position.Z), frost, Enum.Material.Neon, 0.18)
        end
        if level >= 2 then
            local p1 = makeVisualPart(folder, 'L2_CrystalA', Vector3.new(0.22, 0.55, 0.22), CFrame.new(root.Position + root.CFrame.RightVector * -0.35 + Vector3.new(0, root.Size.Y * 0.48, 0)) * CFrame.Angles(math.rad(18),0,math.rad(12)), frost, Enum.Material.Glass, 0)
            local p2 = makeVisualPart(folder, 'L2_CrystalB', Vector3.new(0.22, 0.55, 0.22), CFrame.new(root.Position + root.CFrame.RightVector * 0.35 + Vector3.new(0, root.Size.Y * 0.48, 0)) * CFrame.Angles(math.rad(-16),0,math.rad(-10)), frost, Enum.Material.Glass, 0)
            p1.Color = frost
            p2.Color = frost
        end
        if level >= 3 then
            local emitterCore = makeVisualPart(folder, 'L3_EmitterCore', Vector3.new(0.26, 0.26, 0.26), CFrame.new(root.Position + Vector3.new(0, root.Size.Y * 0.55, 0)), frost, Enum.Material.Neon, 0.05, Enum.PartType.Ball)
            local att = Instance.new('Attachment')
            att.Parent = emitterCore
            local pe = Instance.new('ParticleEmitter')
            pe.Color = ColorSequence.new(frost, Color3.new(1,1,1))
            pe.LightEmission = 0.9
            pe.Lifetime = NumberRange.new(0.25, 0.45)
            pe.Rate = 14
            pe.Speed = NumberRange.new(0.2, 0.55)
            pe.SpreadAngle = Vector2.new(180, 180)
            pe.Texture = 'rbxasset://textures/particles/smoke_main.dds'
            pe.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.55),
                NumberSequenceKeypoint.new(1, 1),
            })
            pe.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.2),
                NumberSequenceKeypoint.new(1, 0.7),
            })
            pe.Parent = att
        end

    elseif towerKey == 'MissilePod' then
        local warn = Color3.fromRGB(255, 170, 80)
        if level >= 1 then
            makeVisualPart(folder, 'L1_Stabilizer', Vector3.new(root.Size.X * 1.18, 0.12, root.Size.Z * 1.18), CFrame.new(root.Position.X, root.Position.Y - root.Size.Y * 0.45, root.Position.Z), warn, Enum.Material.Metal, 0)
        end
        if level >= 2 then
            local back = root.Position - root.CFrame.LookVector * (root.Size.Z * 0.32) + Vector3.new(0, root.Size.Y * 0.35, 0)
            makeVisualPart(folder, 'L2_PodLeft', Vector3.new(0.35, 0.35, 0.85), CFrame.new(back + root.CFrame.RightVector * -0.45), warn:Lerp(Color3.new(1,1,1),0.1), Enum.Material.Metal, 0)
            makeVisualPart(folder, 'L2_PodRight', Vector3.new(0.35, 0.35, 0.85), CFrame.new(back + root.CFrame.RightVector * 0.45), warn:Lerp(Color3.new(1,1,1),0.1), Enum.Material.Metal, 0)
        end
        if level >= 3 then
            local led = makeVisualPart(folder, 'L3_WarnLight', Vector3.new(0.24, 0.24, 0.24), CFrame.new(root.Position + Vector3.new(0, root.Size.Y * 0.6, 0)), Color3.fromRGB(255, 70, 70), Enum.Material.Neon, 0.05, Enum.PartType.Ball)
            local att = Instance.new('Attachment')
            att.Parent = led
            local pe = Instance.new('ParticleEmitter')
            pe.Color = ColorSequence.new(Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 200, 120))
            pe.LightEmission = 1
            pe.Lifetime = NumberRange.new(0.18, 0.28)
            pe.Rate = 10
            pe.Speed = NumberRange.new(0.1, 0.3)
            pe.SpreadAngle = Vector2.new(360, 360)
            pe.Texture = 'rbxasset://textures/particles/sparkles_main.dds'
            pe.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.2),
                NumberSequenceKeypoint.new(1, 1),
            })
            pe.Size = NumberSequence.new(0.18)
            pe.Parent = att
        end
    end
end

local function broadcastState()
    local shared = {
        lives = lives,
        wave = currentWave,
        maxWave = #Config.Waves,
        waveName = waveName,
        status = gameStatus,
        intermissionRemaining = getIntermissionRemaining(),
        elapsedSeconds = getElapsedSeconds(),
    }

    for _, player in ipairs(Players:GetPlayers()) do
        local pState = playerState[player]
        if pState then
            StateUpdateRemote:FireClient(player, {
                money = pState.money,
                lives = shared.lives,
                wave = shared.wave,
                maxWave = shared.maxWave,
                waveName = shared.waveName,
                status = shared.status,
                intermissionRemaining = shared.intermissionRemaining,
                elapsedSeconds = shared.elapsedSeconds,
                towers = pState.towerCount,
            })
        end
    end
end

local function setStatus(status)
    gameStatus = status
    if status ~= 'Intermission' then
        intermissionEndsAt = 0
    end
    broadcastState()
end

local function beginIntermission(seconds)
    intermissionEndsAt = os.clock() + seconds
    setStatus('Intermission')
end

local function runIntermission(seconds)
    beginIntermission(seconds)
    while getIntermissionRemaining() > 0 do
        task.wait(0.2)
    end
end

local function addMoneyToAll(amount)
    for _, p in ipairs(Players:GetPlayers()) do
        local pState = playerState[p]
        if pState then
            pState.money += amount
        end
    end
end

local function addWaveBonus(waveIndex)
    local bonus = math.floor((Config.WaveClearBonusBase or 0) + waveIndex * (Config.WaveClearBonusScale or 0))
    if bonus > 0 then
        addMoneyToAll(bonus)
    end
end

local function removeEnemy(index)
    local enemy = enemies[index]
    if not enemy then
        return
    end

    if enemy.walkTrack then
        pcall(function()
            enemy.walkTrack:Stop(0.1)
            enemy.walkTrack:Destroy()
        end)
    end

    if enemy.model and enemy.model.Parent then
        enemy.model:Destroy()
    end

    table.remove(enemies, index)
end

local function damageEnemy(targetEnemy, damage)
    if not targetEnemy or targetEnemy.dead then
        return false
    end

    targetEnemy.hp -= damage
    updateEnemyAttributes(targetEnemy)
    flashEnemy(targetEnemy)

    if targetEnemy.hp <= 0 then
        targetEnemy.dead = true
        local killReward = math.max(1, math.floor((targetEnemy.reward or 0) * KILL_REWARD_MULT + 0.5))
        addMoneyToAll(killReward)
        createDeathEffect(targetEnemy.pathPos or targetEnemy.model:GetPivot().Position, Color3.fromRGB(255, 105, 105))
        return true
    end

    return false
end

local function buildEnemyModel(enemyType)
    local template = EnemyModels:FindFirstChild(enemyType or '')
    if template and template:IsA('Model') then
        return template:Clone()
    end

    local fallback = Instance.new('Model')
    fallback.Name = enemyType or 'Enemy'

    local part = Instance.new('Part')
    part.Name = 'Body'
    part.Size = Vector3.new(3, 3, 3)
    part.Shape = Enum.PartType.Ball
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(255, 90, 90)
    part.Anchored = true
    part.CanCollide = false
    part.Parent = fallback

    fallback.PrimaryPart = part
    return fallback
end

local function spawnEnemy(wave)
    if #waypoints < 2 then
        warn('Need at least 2 waypoints to run TD pathing')
        return
    end

    local model = buildEnemyModel(wave.EnemyType)
    model.Parent = EnemiesFolder

    local root, hasHumanoid = prepareEnemyModel(model)
    if not root then
        model:Destroy()
        return
    end

    local startPos = waypoints[1].Position + Vector3.new(0, 2, 0)
    local initialTarget = waypoints[2].Position + Vector3.new(0, 2, 0)
    local initialDir = flattenXZ(initialTarget - startPos)
    local initialYaw = yawFromFlatDir(initialDir)
    model:PivotTo(CFrame.new(startPos) * CFrame.Angles(0, initialYaw, 0))

    local walkTrack = startEnemyWalkAnimation(model)

    local enemy = {
        model = model,
        root = root,
        hp = wave.HP,
        maxHp = wave.HP,
        speed = wave.Speed,
        reward = wave.Reward,
        waypointIndex = 1,
        dead = false,
        slowUntil = 0,
        slowFactor = 1,
        pathPos = startPos,
        yaw = initialYaw,
        turnRate = math.rad(wave.TurnRate or 110),
        walkTrack = walkTrack,
        useBobbing = (walkTrack == nil),
        bobSeed = math.random() * math.pi * 2,
        hasHumanoid = hasHumanoid,
        enemyName = wave.EnemyType or model.Name,
    }

    updateEnemyAttributes(enemy)
    table.insert(enemies, enemy)
end

local function getEnemyPathProgress(enemy)
    if not enemy then
        return 0
    end

    local index = enemy.waypointIndex or 1
    local progress = index
    local nextWaypoint = waypoints[index + 1]

    if nextWaypoint then
        local fromPos = waypoints[index] and waypoints[index].Position or (enemy.pathPos or nextWaypoint.Position)
        local toPos = nextWaypoint.Position
        local segmentLength = (toPos - fromPos).Magnitude
        if segmentLength > 0.001 then
            local along = (enemy.pathPos or fromPos) - fromPos
            local frac = math.clamp(along:Dot((toPos - fromPos).Unit) / segmentLength, 0, 1)
            progress += frac
        end
    end

    return progress
end

local function enemyPriorityMetric(tower, enemy, enemyPos)
    local mode = tower.targetMode or 'First'

    if mode == 'Closest' then
        return (enemyPos - tower.root.Position).Magnitude
    end

    if mode == 'Strongest' then
        return -(enemy.hp or 0)
    end

    local pathProgress = getEnemyPathProgress(enemy)
    if mode == 'Last' then
        return pathProgress
    end

    return -pathProgress
end

local function chooseTargetInRange(tower)
    if not tower or not tower.root then
        return nil
    end

    local rangeFrom = tower.root.Position
    local bestEnemy = nil
    local bestMetric = nil
    local bestDistance = math.huge

    for _, enemy in ipairs(enemies) do
        if enemy.model and enemy.model.Parent and not enemy.dead then
            local enemyPos = enemy.pathPos or enemy.model:GetPivot().Position
            local dist = (enemyPos - rangeFrom).Magnitude
            if dist <= tower.range then
                local metric = enemyPriorityMetric(tower, enemy, enemyPos)
                if bestEnemy == nil or metric < bestMetric or (metric == bestMetric and dist < bestDistance) then
                    bestEnemy = enemy
                    bestMetric = metric
                    bestDistance = dist
                end
            end
        end
    end

    return bestEnemy
end



local function damageEnemiesInRadius(origin, radius, damage)
    for _, enemy in ipairs(enemies) do
        if enemy.model and enemy.model.Parent and not enemy.dead then
            local enemyPos = enemy.pathPos or enemy.model:GetPivot().Position
            if (enemyPos - origin).Magnitude <= radius then
                damageEnemy(enemy, damage)
            end
        end
    end
end

local function updateEnemies(dt)
    local now = os.clock()

    for i = #enemies, 1, -1 do
        local enemy = enemies[i]
        if enemy.dead or not enemy.model or not enemy.model.Parent then
            removeEnemy(i)
        else
            local currentPos = enemy.pathPos or enemy.model:GetPivot().Position
            local nextWaypoint = waypoints[enemy.waypointIndex + 1]

            if not nextWaypoint then
                lives -= 1
                playSoundAt(currentPos, SOUND_IDS.BaseHit, 0.5, 1)
                removeEnemy(i)
                if lives <= 0 then
                    setStatus('Defeat')
                end
            else
                local speed = enemy.speed
                if now < enemy.slowUntil then
                    speed *= enemy.slowFactor
                end

                if enemy.walkTrack then
                    enemy.walkTrack:AdjustSpeed(math.clamp(speed / 10, 0.45, 2.2))
                end

                local targetPos = nextWaypoint.Position + Vector3.new(0, 2, 0)
                local toTarget = targetPos - currentPos
                local distance = toTarget.Magnitude
                local step = speed * dt

                local newPathPos = currentPos
                if distance <= step then
                    newPathPos = targetPos
                    enemy.waypointIndex += 1
                elseif distance > 0 then
                    newPathPos = currentPos + toTarget.Unit * step
                end

                enemy.pathPos = newPathPos

                local renderPos = newPathPos
                if enemy.useBobbing then
                    renderPos += Vector3.new(0, math.sin(now * 8 + enemy.bobSeed) * 0.28, 0)
                end

                local desiredDir = flattenXZ(targetPos - newPathPos)
                if desiredDir.Magnitude > 0.001 then
                    local desiredYaw = yawFromFlatDir(desiredDir)
                    local currentYaw = enemy.yaw or desiredYaw
                    local maxTurnStep = (enemy.turnRate or math.rad(110)) * dt
                    local deltaYaw = wrapAngleRad(desiredYaw - currentYaw)

                    if math.abs(deltaYaw) > maxTurnStep then
                        currentYaw += (deltaYaw >= 0 and 1 or -1) * maxTurnStep
                    else
                        currentYaw = desiredYaw
                    end

                    enemy.yaw = wrapAngleRad(currentYaw)
                end

                local facingYaw = enemy.yaw or 0
                enemy.model:PivotTo(CFrame.new(renderPos) * CFrame.Angles(0, facingYaw, 0))
            end
        end
    end
end

local function rotateTowerToward(tower, targetPos)
    local aimNode = tower.aimNode or tower.model
    local nodeCF = getNodePivot(aimNode)
    if not nodeCF then
        return
    end

    local nodePos = nodeCF.Position
    local desiredDir = flattenXZ(targetPos - nodePos)
    if desiredDir.Magnitude < 0.01 then
        return
    end

    desiredDir = desiredDir.Unit

    local baseDir = tower.aimBaseDir
    if not baseDir or baseDir.Magnitude < 0.01 then
        local baseCF = CFrame.new(nodePos) * (tower.aimBaseRotation or nodeCF.Rotation)
        baseDir = flattenXZ(baseCF.LookVector)
        if baseDir.Magnitude < 0.01 then
            baseDir = flattenXZ(nodeCF.LookVector)
        end
    end

    baseDir = baseDir.Unit
    local yawDelta = signedAngleXZ(baseDir, desiredDir)

    local desiredCF = CFrame.new(nodePos) * CFrame.Angles(0, yawDelta, 0) * (tower.aimBaseRotation or nodeCF.Rotation)
    setNodePivot(aimNode, desiredCF)
end

local function updateTowers(dt)
    local now = os.clock()

    for _, tower in ipairs(towers) do
        if tower.model and tower.model.Parent and tower.root then
            tower.cooldown -= dt

            if tower.cooldown <= 0 then
                local target = chooseTargetInRange(tower)

                if target then
                    local targetPos = target.pathPos or target.model:GetPivot().Position
                    rotateTowerToward(tower, targetPos)

                    local origin = getMuzzlePosition(tower)

                    local fireSound = SOUND_IDS.FireLaser
                    if tower.towerKey == 'MissilePod' then
                        fireSound = SOUND_IDS.FireMissile
                    elseif tower.towerKey == 'FrostBeam' then
                        fireSound = SOUND_IDS.FireFrost
                    end
                    playSoundAt(origin, fireSound, 0.35, 1)

                    local beamDistance = (targetPos - origin).Magnitude
                    local fx = Instance.new('Part')
                    fx.Anchored = true
                    fx.CanCollide = false
                    fx.Material = Enum.Material.Neon
                    fx.Color = tower.root.Color
                    fx.Size = Vector3.new(0.22, 0.22, beamDistance)
                    fx.CFrame = CFrame.lookAt((origin + targetPos) / 2, targetPos)
                    fx.Transparency = 0.1
                    fx.Parent = Workspace
                    Debris:AddItem(fx, 0.08)

                    createImpactVFX(targetPos, tower.root.Color)
                    playSoundAt(targetPos, SOUND_IDS.Hit, 0.22, 1)

                    if tower.splashRadius then
                        damageEnemiesInRadius(targetPos, tower.splashRadius, tower.damage)
                    else
                        damageEnemy(target, tower.damage)
                    end

                    if tower.slowFactor and not target.dead then
                        target.slowFactor = tower.slowFactor
                        target.slowUntil = now + (tower.slowDuration or 1)
                    end

                    tower.cooldown = tower.fireRate
                end
            end
        end
    end
end

local function getGroundYAt(pos)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {TowersFolder, EnemiesFolder}

    local origin = Vector3.new(pos.X, pos.Y + 256, pos.Z)
    local result = Workspace:Raycast(origin, Vector3.new(0, -1024, 0), rayParams)
    if result then
        return result.Position.Y
    end

    return 2
end

local function clampToGround(pos)
    return Vector3.new(pos.X, getGroundYAt(pos), pos.Z)
end

local function isPlacementValid(pos)
    if #waypoints < 2 then
        return false
    end

    local mapMin = Vector3.new(-180, 0, -120)
    local mapMax = Vector3.new(180, 0, 120)
    if pos.X < mapMin.X or pos.X > mapMax.X or pos.Z < mapMin.Z or pos.Z > mapMax.Z then
        return false
    end

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

    for _, tower in ipairs(towers) do
        if tower.model and tower.model.Parent then
            local towerPos = tower.model:GetPivot().Position
            if (towerPos - pos).Magnitude < 6 then
                return false
            end
        end
    end

    return true
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

local function buildTowerModel(towerKey, stats)
    local template = getTowerTemplateModel(stats.TemplateName or towerKey)
    local model

    if template and template:IsA('Model') then
        model = template:Clone()
    else
        model = Instance.new('Model')
        model.Name = towerKey

        local base = Instance.new('Part')
        base.Name = 'Base'
        base.Anchored = true
        base.CanCollide = true
        base.Material = Enum.Material.Metal
        base.Color = stats.Color or Color3.fromRGB(200, 200, 200)
        base.Size = Vector3.new(4, 6, 4)
        base.Parent = model

        local top = Instance.new('Part')
        top.Name = 'Top'
        top.Anchored = true
        top.CanCollide = false
        top.Material = Enum.Material.Neon
        top.Color = base.Color
        top.Size = Vector3.new(2.4, 1.2, 2.4)
        top.Position = base.Position + Vector3.new(0, 3.2, 0)
        top.Parent = model

        model.PrimaryPart = base
    end

    local root = setTowerModelStatic(model)
    if not root then
        return nil
    end

    model.PrimaryPart = root

    local muzzle = findDescendantByName(model, 'muzzle') or findDescendantContaining(model, 'muzzle')
    if muzzle and not (muzzle:IsA('BasePart') or muzzle:IsA('Attachment')) then
        muzzle = nil
    end

    local aimNode = findAimNode(model, root)
    if aimNode and aimNode:IsA('Model') then
        ensureModelCenterPivot(aimNode, root.Position)
    end

    return model, root, muzzle, aimNode
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

local function placeModelOnGround(model, targetXZ, groundY)
    local groundAnchor = getGroundAnchorAttachment(model)
    if groundAnchor then
        local ap = groundAnchor.WorldPosition
        local xzDelta = Vector3.new(targetXZ.X - ap.X, 0, targetXZ.Z - ap.Z)
        model:PivotTo(model:GetPivot() + xzDelta)

        local yDelta = groundY - groundAnchor.WorldPosition.Y
        model:PivotTo(model:GetPivot() + Vector3.new(0, yDelta, 0))
        return
    end

    local anchor = getPlacementAnchorPart(model)

    if anchor then
        local anchorPos = anchor.Position
        local xzDelta = Vector3.new(targetXZ.X - anchorPos.X, 0, targetXZ.Z - anchorPos.Z)
        model:PivotTo(model:GetPivot() + xzDelta)

        local bottomY = anchor.Position.Y - anchor.Size.Y * 0.5
        local yDelta = groundY - bottomY
        model:PivotTo(model:GetPivot() + Vector3.new(0, yDelta, 0))
        return
    end

    local startPivot = model:GetPivot()
    local xzDelta = Vector3.new(targetXZ.X - startPivot.Position.X, 0, targetXZ.Z - startPivot.Position.Z)
    model:PivotTo(startPivot + xzDelta)

    local boxCF, boxSize = model:GetBoundingBox()
    local currentBottomY = boxCF.Position.Y - boxSize.Y * 0.5
    local yDelta = groundY - currentBottomY
    model:PivotTo(model:GetPivot() + Vector3.new(0, yDelta, 0))
end

local function safeBaseAimDir(aimNode, muzzle)
    local nodeCF = getNodePivot(aimNode)
    if not nodeCF then
        return Vector3.new(0, 0, -1), CFrame.identity
    end

    local dir
    if muzzle then
        local muzzlePos = muzzle:IsA('Attachment') and muzzle.WorldPosition or muzzle.Position
        dir = flattenXZ(muzzlePos - nodeCF.Position)
    end

    if not dir or dir.Magnitude < 0.001 then
        dir = flattenXZ(nodeCF.LookVector)
    end

    if dir.Magnitude < 0.001 then
        dir = Vector3.new(0, 0, -1)
    else
        dir = dir.Unit
    end

    return dir, nodeCF.Rotation
end

local function createTower(player, towerKey, worldPos)
    local pState = playerState[player]
    if not pState then
        return
    end

    if gameStatus == 'Defeat' or gameStatus == 'Victory' then
        return
    end

    local def = Config.Towers[towerKey]
    if not def then
        return
    end

    if pState.towerCount >= Config.MaxTowersPerPlayer then
        return
    end

    if pState.money < def.Cost then
        return
    end

    local pos = clampToGround(worldPos)
    if not isPlacementValid(pos) then
        return
    end

    local model, root, muzzle, aimNode = buildTowerModel(towerKey, def)
    if not model or not root then
        return
    end

    pState.money -= def.Cost
    pState.towerCount += 1

    model.Parent = TowersFolder
    placeModelOnGround(model, pos, pos.Y)

    local aimBaseDir, aimBaseRotation = safeBaseAimDir(aimNode, muzzle)

    local tower = {
        id = nextTowerId,
        owner = player,
        model = model,
        root = root,
        muzzle = muzzle,
        aimNode = aimNode,
        aimBaseDir = aimBaseDir,
        aimBaseRotation = aimBaseRotation,
        towerKey = towerKey,
        level = 0,
        spent = def.Cost,
        damage = def.Damage,
        range = def.Range,
        fireRate = def.FireRate,
        slowFactor = def.SlowFactor,
        slowDuration = def.SlowDuration,
        splashRadius = def.SplashRadius,
        targetMode = 'First',
        cooldown = 0,
    }

    nextTowerId += 1

    table.insert(towers, tower)
    towerById[tower.id] = tower

    updateTowerAttributes(tower)
    applyTowerUpgradeVisuals(tower)
    playSoundAt(pos, SOUND_IDS.Place, 0.35, 1)
    broadcastState()
end

local function removeTower(tower)
    if not tower then
        return
    end

    towerById[tower.id] = nil

    for i = #towers, 1, -1 do
        if towers[i] == tower then
            table.remove(towers, i)
            break
        end
    end

    if tower.model and tower.model.Parent then
        tower.model:Destroy()
    end
end

local function upgradeTower(player, tower)
    if not tower or tower.owner ~= player then
        return false, 'Not your tower'
    end

    local pState = playerState[player]
    if not pState then
        return false, 'No player state'
    end

    local upgrade = getNextUpgradeSpec(tower)
    if not upgrade then
        return false, 'Max level reached'
    end

    if pState.money < upgrade.Cost then
        return false, 'Not enough credits'
    end

    pState.money -= upgrade.Cost
    tower.spent += upgrade.Cost
    tower.level += 1

    tower.damage *= (upgrade.DamageMult or 1)
    tower.range += (upgrade.RangeAdd or 0)
    tower.fireRate *= (upgrade.FireRateMult or 1)

    if tower.slowFactor and upgrade.SlowFactorMult then
        tower.slowFactor *= upgrade.SlowFactorMult
    end

    if tower.slowDuration and upgrade.SlowDurationAdd then
        tower.slowDuration += upgrade.SlowDurationAdd
    end

    if tower.splashRadius and upgrade.SplashRadiusAdd then
        tower.splashRadius += upgrade.SplashRadiusAdd
    end

    tower.fireRate = math.max(0.08, tower.fireRate)
    tower.range = math.max(8, tower.range)

    updateTowerAttributes(tower)
    applyTowerUpgradeVisuals(tower)
    playSoundAt(tower.root.Position, SOUND_IDS.Upgrade, 0.45, 1)
    broadcastState()

    return true, 'Tower upgraded'
end

local function sellTower(player, tower)
    if not tower or tower.owner ~= player then
        return false, 'Not your tower'
    end

    local pState = playerState[player]
    if not pState then
        return false, 'No player state'
    end

    local refund = getTowerSellValue(tower)
    pState.money += refund
    pState.towerCount = math.max(0, pState.towerCount - 1)

    local pos = tower.root and tower.root.Position or tower.model:GetPivot().Position
    createImpactVFX(pos, Color3.fromRGB(130, 255, 170))
    playSoundAt(pos, SOUND_IDS.Sell, 0.5, 1)

    removeTower(tower)
    broadcastState()

    return true, 'Sold for ' .. refund
end

local function cycleTowerTargetMode(player, tower)
    if not tower or tower.owner ~= player then
        return false, 'Not your tower'
    end

    local currentMode = tower.targetMode or 'First'
    local idx = TARGET_MODE_INDEX[currentMode] or 1
    local nextMode = TARGET_MODES[(idx % #TARGET_MODES) + 1]
    tower.targetMode = nextMode

    updateTowerAttributes(tower)
    return true, 'Targeting: ' .. nextMode
end

TowerActionRemote.OnServerInvoke = function(player, action, towerId)
    if gameStatus == 'Defeat' or gameStatus == 'Victory' then
        return {ok = false, message = 'Game over'}
    end

    if type(towerId) ~= 'number' then
        return {ok = false, message = 'Invalid tower id'}
    end

    local tower = towerById[towerId]
    if not tower then
        return {ok = false, message = 'Tower not found'}
    end

    local ok, message
    if action == 'Upgrade' then
        ok, message = upgradeTower(player, tower)
    elseif action == 'Sell' then
        ok, message = sellTower(player, tower)
    elseif action == 'CycleTargetMode' then
        ok, message = cycleTowerTargetMode(player, tower)
    else
        ok, message = false, 'Unknown action'
    end

    local pState = playerState[player]
    return {
        ok = ok,
        message = message,
        money = pState and pState.money or 0,
    }
end

PlaceTowerRemote.OnServerEvent:Connect(function(player, towerKey, worldPos)
    if typeof(worldPos) ~= 'Vector3' then
        return
    end

    if typeof(towerKey) ~= 'string' then
        return
    end

    createTower(player, towerKey, worldPos)
end)

Players.PlayerAdded:Connect(function(player)
    playerState[player] = {
        money = Config.StartMoney,
        towerCount = 0,
    }

    task.defer(function()
        local pState = playerState[player]
        if pState then
            StateUpdateRemote:FireClient(player, {
                money = pState.money,
                lives = lives,
                wave = currentWave,
                maxWave = #Config.Waves,
                waveName = waveName,
                status = gameStatus,
                intermissionRemaining = getIntermissionRemaining(),
                elapsedSeconds = getElapsedSeconds(),
                towers = pState.towerCount,
            })
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    playerState[player] = nil

    for i = #towers, 1, -1 do
        local t = towers[i]
        if t.owner == player then
            removeTower(t)
        end
    end
end)

RunService.Heartbeat:Connect(function(dt)
    if gameStatus == 'Defeat' or gameStatus == 'Victory' then
        return
    end

    updateEnemies(dt)
    updateTowers(dt)
end)

task.spawn(function()
    while #Players:GetPlayers() == 0 do
        task.wait(0.5)
    end

    runIntermission(Config.Intermission)

    for waveIndex, wave in ipairs(Config.Waves) do
        if lives <= 0 then
            break
        end

        currentWave = waveIndex
        waveName = wave.Name or ('Wave ' .. waveIndex)
        setStatus('Wave')

        for _ = 1, wave.Count do
            if lives <= 0 then
                break
            end
            spawnEnemy(wave)
            task.wait(wave.SpawnDelay)
        end

        while #enemies > 0 and lives > 0 do
            task.wait(0.2)
        end

        if lives <= 0 then
            break
        end

        addWaveBonus(waveIndex)

        if waveIndex < #Config.Waves then
            runIntermission(Config.Intermission)
        end
    end

    if lives > 0 then
        waveName = 'Base Secured'
        setStatus('Victory')
    else
        waveName = 'Core Breached'
        setStatus('Defeat')
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        broadcastState()
    end
end)
