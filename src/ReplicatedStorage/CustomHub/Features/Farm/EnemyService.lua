local EnemyService = {}
EnemyService.__index = EnemyService

local HIDDEN_SPAWN_REFRESH_INTERVAL = 1
local HIDDEN_SPAWN_RETRY_INTERVAL = 5

local function normalizeEnemyName(name)
    return (name:gsub(" %p?Lv%.? %d+%p?", ""))
end

local function matchesSpawnName(spawnName, targetName, normalizedTarget)
    return spawnName == targetName or normalizeEnemyName(spawnName) == normalizedTarget
end

function EnemyService.new(compatibility)
    return setmetatable({
        Compatibility = compatibility,
        Workspace = compatibility.Workspace,
        CollisionOriginals = {},
        IgnoredSpawns = {},
        HiddenSpawnCache = nil,
    }, EnemyService)
end

function EnemyService:_GetEnemySpawnsFolder()
    local worldOrigin = self.Workspace:FindFirstChild("_WorldOrigin")
    if not worldOrigin or worldOrigin.Parent ~= self.Workspace then
        return nil
    end

    local enemySpawns = worldOrigin:FindFirstChild("EnemySpawns")
    if not enemySpawns
        or not enemySpawns:IsA("Folder")
        or enemySpawns.Parent ~= worldOrigin
    then
        return nil
    end
    return enemySpawns
end

function EnemyService:_RefreshHiddenSpawnCache()
    local now = os.clock()
    local current = self.HiddenSpawnCache
    if current and now < current.ExpiresAt then
        return current
    end

    local cache = {
        Parts = {},
        Available = false,
        ExpiresAt = now + HIDDEN_SPAWN_RETRY_INTERVAL,
    }
    local getter = self.Compatibility and self.Compatibility.GetUnparentedInstances
    if type(getter) == "function" then
        local callOk, instances = pcall(getter, self.Compatibility)
        if callOk and type(instances) == "table" then
            cache.Available = true
            cache.ExpiresAt = now + HIDDEN_SPAWN_REFRESH_INTERVAL
            local scanOk = pcall(function()
                for _, instance in pairs(instances) do
                    local readOk, isBasePart, name, parent = pcall(function()
                        return instance:IsA("BasePart"), instance.Name, instance.Parent
                    end)
                    if readOk and isBasePart and parent == nil and type(name) == "string" then
                        cache.Parts[instance] = name
                    end
                end
            end)
            if not scanOk then
                cache.Parts = {}
                cache.Available = false
                cache.ExpiresAt = now + HIDDEN_SPAWN_RETRY_INTERVAL
            end
        end
    end

    self.HiddenSpawnCache = cache
    return cache
end

function EnemyService:_PruneIgnoredSpawns(enemySpawns, hiddenCache, targetName)
    local normalizedTarget = normalizeEnemyName(targetName)
    for spawnPart in pairs(self.IgnoredSpawns) do
        local readOk, isBasePart, name, parent = pcall(function()
            return spawnPart:IsA("BasePart"), spawnPart.Name, spawnPart.Parent
        end)
        local matchingName = readOk
            and isBasePart
            and type(name) == "string"
            and matchesSpawnName(name, targetName, normalizedTarget)
        local replicated = matchingName
            and enemySpawns ~= nil
            and parent == enemySpawns
        local hidden = matchingName
            and parent == nil
            and hiddenCache.Available
            and hiddenCache.Parts[spawnPart] == name
        if not replicated and not hidden then
            self.IgnoredSpawns[spawnPart] = nil
        end
    end
end

function EnemyService:IsAlive(model)
    if not model or not model.Parent then
        return false
    end
    local root = model:FindFirstChild("HumanoidRootPart")
    local humanoid = model:FindFirstChildWhichIsA("Humanoid")
    return root ~= nil and humanoid ~= nil and humanoid.Health > 0
end

function EnemyService:FindNearest(targetName, origin)
    local enemies = self.Workspace:FindFirstChild("Enemies")
    if not enemies or not targetName or not origin then
        return nil
    end

    local nearest, nearestDistance = nil, math.huge
    for _, enemy in ipairs(enemies:GetChildren()) do
        local matches = type(targetName) == "table"
            and table.find(targetName, enemy.Name) ~= nil
            or enemy.Name == targetName
        if matches and self:IsAlive(enemy) then
            local distance = (enemy.HumanoidRootPart.Position - origin).Magnitude
            if distance < nearestDistance then
                nearest, nearestDistance = enemy, distance
            end
        end
    end
    return nearest, nearestDistance
end

function EnemyService:FindSpawn(targetName, origin)
    local diagnostic = {
        TargetName = targetName,
        NormalMarkerFound = false,
        HiddenMarkerFound = false,
        HiddenDiscoveryAvailable = false,
        SelectedSource = "none",
        SelectedName = nil,
        SelectedDistance = nil,
    }
    if type(targetName) ~= "string" then
        return nil, false, diagnostic
    end

    local enemySpawns = self:_GetEnemySpawnsFolder()
    local hiddenCache = self:_RefreshHiddenSpawnCache()
    diagnostic.HiddenDiscoveryAvailable = hiddenCache.Available == true
    local normalizedTarget = normalizeEnemyName(targetName)
    self:_PruneIgnoredSpawns(enemySpawns, hiddenCache, targetName)

    local hasMatchingSpawn = false
    local nearest, nearestDistance = nil, math.huge
    local function considerSpawn(spawnPart, expectedParent, expectedName, source)
        local readOk, isBasePart, name, parent, position = pcall(function()
            return spawnPart:IsA("BasePart"), spawnPart.Name, spawnPart.Parent, spawnPart.Position
        end)
        if not readOk
            or not isBasePart
            or parent ~= expectedParent
            or type(name) ~= "string"
            or (expectedName and name ~= expectedName)
            or not matchesSpawnName(name, targetName, normalizedTarget)
        then
            return
        end

        hasMatchingSpawn = true
        if source == "EnemySpawns" then
            diagnostic.NormalMarkerFound = true
        elseif source == "unparented-cache" then
            diagnostic.HiddenMarkerFound = true
        end
        if self.IgnoredSpawns[spawnPart] then
            return
        end
        local distance = typeof(origin) == "Vector3"
            and (position - origin).Magnitude
            or 0
        if distance < nearestDistance then
            nearest, nearestDistance = spawnPart, distance
            diagnostic.SelectedSource = source
            diagnostic.SelectedName = name
            diagnostic.SelectedDistance = distance
        end
    end

    if enemySpawns then
        local childrenOk, children = pcall(function()
            return enemySpawns:GetChildren()
        end)
        if childrenOk then
            for _, spawnPart in ipairs(children) do
                considerSpawn(spawnPart, enemySpawns, nil, "EnemySpawns")
            end
        end
    end

    -- Include cached unparented candidates in nearest selection, but refresh the
    -- potentially expensive runtime enumeration no more than once per cache interval.
    if hiddenCache.Available and os.clock() < hiddenCache.ExpiresAt then
        for spawnPart, cachedName in pairs(hiddenCache.Parts) do
            if matchesSpawnName(cachedName, targetName, normalizedTarget) then
                considerSpawn(spawnPart, nil, cachedName, "unparented-cache")
            end
        end
    end

    if nearest then
        return nearest, false, diagnostic
    end
    return nil, hasMatchingSpawn, diagnostic
end

function EnemyService:IsSpawnAvailable(spawnPart, targetName)
    if not spawnPart or type(targetName) ~= "string" then
        return false
    end
    local readOk, isBasePart, name, parent = pcall(function()
        return spawnPart:IsA("BasePart"), spawnPart.Name, spawnPart.Parent
    end)
    if not readOk
        or not isBasePart
        or type(name) ~= "string"
        or self.IgnoredSpawns[spawnPart]
    then
        return false
    end

    local normalizedTarget = normalizeEnemyName(targetName)
    if not matchesSpawnName(name, targetName, normalizedTarget) then
        return false
    end

    local enemySpawns = self:_GetEnemySpawnsFolder()
    if enemySpawns ~= nil and parent == enemySpawns then
        return true
    end

    local hiddenCache = self.HiddenSpawnCache
    return parent == nil
        and hiddenCache ~= nil
        and hiddenCache.Available
        and os.clock() < hiddenCache.ExpiresAt
        and hiddenCache.Parts[spawnPart] == name
end

function EnemyService:MarkSpawnIgnored(spawnPart, targetName)
    if self:IsSpawnAvailable(spawnPart, targetName) then
        self.IgnoredSpawns[spawnPart] = true
    end
end

function EnemyService:ClearIgnoredSpawns()
    table.clear(self.IgnoredSpawns)
end

function EnemyService:PrepareTarget(model, playerRoot)
    if not self:IsAlive(model) or not playerRoot then
        return
    end
    if (model.HumanoidRootPart.Position - playerRoot.Position).Magnitude > 50 then
        return
    end

    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            self.CollisionOriginals[part] = true
            part.CanCollide = false
        end
    end
end

function EnemyService:RestoreTargetCollision()
    for part, originalCanCollide in pairs(self.CollisionOriginals) do
        if part and part.Parent then
            part.CanCollide = originalCanCollide
        end
        self.CollisionOriginals[part] = nil
    end
end

return EnemyService
