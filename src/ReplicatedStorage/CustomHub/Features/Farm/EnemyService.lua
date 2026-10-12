local EnemyService = {}
EnemyService.__index = EnemyService

local HIDDEN_SPAWN_REFRESH_INTERVAL = 1
local HIDDEN_SPAWN_RETRY_INTERVAL = 5

local function singularizeEnemyWord(word)
    if #word > 3 and word:sub(-3) == "ies" then
        local stem = word:sub(1, -4)
        local lastStemCharacter = stem:sub(-1)
        if lastStemCharacter ~= "" and not lastStemCharacter:match("[aeiou]") then
            return stem .. "y"
        end
    end

    if #word > 4 and word:sub(-2) == "es" then
        local stem = word:sub(1, -3)
        if stem:sub(-1) == "s" or stem:sub(-1) == "x" or stem:sub(-1) == "z"
            or stem:sub(-2) == "ch" or stem:sub(-2) == "sh"
        then
            return stem
        end
    end

    local ending = word:sub(-2)
    if #word > 2 and word:sub(-1) == "s"
        and ending ~= "ss" and ending ~= "us" and ending ~= "is"
    then
        return word:sub(1, -2)
    end
    return word
end

local function normalizeEnemyName(name)
    if type(name) ~= "string" or #name == 0 then
        return nil
    end

    local baseName = name:lower():gsub("%s+%p?lv%.?%s*%d+%p?%s*$", "")
    local words = {}
    for word in baseName:gmatch("[%w]+") do
        table.insert(words, word)
    end
    if #words == 0 then
        return nil
    end

    words[#words] = singularizeEnemyWord(words[#words])
    return table.concat(words, " ")
end

local function normalizeTargetNames(targetNames)
    local normalized = {}
    if type(targetNames) == "string" then
        local name = normalizeEnemyName(targetNames)
        if name then
            table.insert(normalized, name)
        end
    elseif type(targetNames) == "table" then
        for _, targetName in ipairs(targetNames) do
            local name = normalizeEnemyName(targetName)
            if name then
                table.insert(normalized, name)
            end
        end
    end
    return normalized
end

local function matchesEnemyName(enemyName, targetName)
    local normalizedEnemyName = normalizeEnemyName(enemyName)
    if not normalizedEnemyName then
        return false
    end

    if type(targetName) == "string" then
        return normalizedEnemyName == normalizeEnemyName(targetName)
    end
    if type(targetName) == "table" then
        for _, candidateName in ipairs(targetName) do
            if type(candidateName) == "string"
                and normalizedEnemyName == normalizeEnemyName(candidateName)
            then
                return true
            end
        end
    end
    return false
end

local function isDescendantOf(instance, container)
    if not instance or not container then
        return false
    end
    local ok, result = pcall(function()
        return instance:IsDescendantOf(container)
    end)
    return ok and result == true
end

local function matchesSpawnName(spawnName, normalizedTargets)
    local normalizedName = normalizeEnemyName(spawnName)
    if not normalizedName then
        return false
    end
    for _, normalizedTarget in ipairs(normalizedTargets or {}) do
        if normalizedName == normalizedTarget then
            return true
        end
    end
    return false
end

local function matchedTargetName(spawnName, targetNames, normalizedTargets)
    for index, normalizedTarget in ipairs(normalizedTargets) do
        if normalizeEnemyName(spawnName) == normalizedTarget then
            if type(targetNames) == "string" then
                return targetNames
            end
            return targetNames[index]
        end
    end
    return nil
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
    if not worldOrigin then
        worldOrigin = self.Workspace:FindFirstChild("_WorldOrigin", true)
    end
    if not worldOrigin then
        return self.Workspace:FindFirstChild("EnemySpawns", true)
    end

    local enemySpawns = worldOrigin:FindFirstChild("EnemySpawns")
    if not enemySpawns then
        enemySpawns = worldOrigin:FindFirstChild("EnemySpawns", true)
    end
    if not enemySpawns then
        enemySpawns = self.Workspace:FindFirstChild("EnemySpawns", true)
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
    local normalizedTarget = normalizeTargetNames(targetName)
    for spawnPart in pairs(self.IgnoredSpawns) do
        local readOk, isBasePart, name, parent = pcall(function()
            return spawnPart:IsA("BasePart"), spawnPart.Name, spawnPart.Parent
        end)
        local matchingName = readOk
            and isBasePart
            and type(name) == "string"
            and matchesSpawnName(name, normalizedTarget)
        local replicated = matchingName
            and enemySpawns ~= nil
            and parent ~= nil
            and isDescendantOf(spawnPart, enemySpawns)
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
    if not enemies then
        enemies = self.Workspace:FindFirstChild("Enemies", true)
    end
    if not enemies or not targetName or not origin then
        return nil
    end

    local nearest, nearestDistance = nil, math.huge
    for _, enemy in ipairs(enemies:GetDescendants()) do
        if enemy:IsA("Model")
            and matchesEnemyName(enemy.Name, targetName)
            and self:IsAlive(enemy)
        then
            local distance = (enemy.HumanoidRootPart.Position - origin).Magnitude
            if distance < nearestDistance then
                nearest, nearestDistance = enemy, distance
            end
        end
    end
    return nearest, nearestDistance
end

function EnemyService:FindNearestInRange(origin, maxDistance)
    if typeof(origin) ~= "Vector3" then
        return nil
    end
    local radius = tonumber(maxDistance)
    if not radius or radius < 0 or radius ~= radius or math.abs(radius) == math.huge then
        return nil
    end

    local enemies = self.Workspace:FindFirstChild("Enemies")
    if not enemies then
        enemies = self.Workspace:FindFirstChild("Enemies", true)
    end
    if not enemies then
        return nil
    end

    local nearest, nearestDistance = nil, radius
    for _, enemy in ipairs(enemies:GetDescendants()) do
        if enemy:IsA("Model") and self:IsAlive(enemy) then
            local distance = (enemy.HumanoidRootPart.Position - origin).Magnitude
            if distance <= nearestDistance then
                nearest, nearestDistance = enemy, distance
            end
        end
    end
    return nearest, nearestDistance
end

function EnemyService:FindSpawn(targetName, origin)
    local diagnostic = {
        TargetName = type(targetName) == "string" and targetName or "multiple quest targets",
        EnemySpawnsContainerFound = false,
        NormalMarkerFound = false,
        HiddenMarkerFound = false,
        HiddenDiscoveryAvailable = false,
        SelectedSource = "none",
        SelectedName = nil,
        MatchedTarget = nil,
        SelectedDistance = nil,
    }
    local normalizedTarget = normalizeTargetNames(targetName)
    if #normalizedTarget == 0 then
        return nil, false, diagnostic
    end

    local enemySpawns = self:_GetEnemySpawnsFolder()
    local hiddenCache = self:_RefreshHiddenSpawnCache()
    diagnostic.EnemySpawnsContainerFound = enemySpawns ~= nil
    diagnostic.HiddenDiscoveryAvailable = hiddenCache.Available == true
    self:_PruneIgnoredSpawns(enemySpawns, hiddenCache, targetName)

    local hasMatchingSpawn = false
    local nearest, nearestDistance = nil, math.huge
    local function considerSpawn(spawnPart, expectedParent, expectedName, source)
        local readOk, isBasePart, name, parent, position = pcall(function()
            return spawnPart:IsA("BasePart"), spawnPart.Name, spawnPart.Parent, spawnPart.Position
        end)
        local inExpectedContainer = source == "EnemySpawns"
            and isDescendantOf(spawnPart, expectedParent)
        local inHiddenCache = source == "unparented-cache" and parent == nil
        if not readOk
            or not isBasePart
            or (source == "EnemySpawns" and not inExpectedContainer)
            or (source == "unparented-cache" and not inHiddenCache)
            or type(name) ~= "string"
            or (expectedName and name ~= expectedName)
            or not matchesSpawnName(name, normalizedTarget)
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
            diagnostic.MatchedTarget = matchedTargetName(name, targetName, normalizedTarget)
            diagnostic.SelectedDistance = distance
        end
    end

    if enemySpawns then
        local childrenOk, children = pcall(function()
            return enemySpawns:GetDescendants()
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
            if matchesSpawnName(cachedName, normalizedTarget) then
                considerSpawn(spawnPart, nil, cachedName, "unparented-cache")
            end
        end
    end

    if nearest then
        return nearest, false, diagnostic, diagnostic.MatchedTarget
    end
    return nil, hasMatchingSpawn, diagnostic, nil
end

function EnemyService:IsSpawnAvailable(spawnPart, targetName)
    if not spawnPart then
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

    local normalizedTarget = normalizeTargetNames(targetName)
    if not matchesSpawnName(name, normalizedTarget) then
        return false
    end

    local enemySpawns = self:_GetEnemySpawnsFolder()
    if enemySpawns ~= nil and parent ~= nil and isDescendantOf(spawnPart, enemySpawns) then
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
