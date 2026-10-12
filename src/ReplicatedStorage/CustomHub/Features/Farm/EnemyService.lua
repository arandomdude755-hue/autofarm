local EnemyService = {}
EnemyService.__index = EnemyService

local HIDDEN_SPAWN_REFRESH_INTERVAL = 5
local HIDDEN_SPAWN_RETRY_INTERVAL = 10
local HIDDEN_SPAWN_SCAN_CHUNK_SIZE = 64

local function disconnect(connection)
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
    end
end

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

local function addNameIndexEntry(index, namesByInstance, instance)
    local normalizedName = normalizeEnemyName(instance.Name)
    if not normalizedName then
        namesByInstance[instance] = nil
        return
    end

    local bucket = index[normalizedName]
    if not bucket then
        bucket = setmetatable({}, { __mode = "k" })
        index[normalizedName] = bucket
    end
    bucket[instance] = true
    namesByInstance[instance] = normalizedName
end

local function removeNameIndexEntry(index, namesByInstance, instance)
    local normalizedName = namesByInstance[instance]
    local bucket = normalizedName and index[normalizedName]
    if bucket then
        bucket[instance] = nil
        if next(bucket) == nil then
            index[normalizedName] = nil
        end
    end
    namesByInstance[instance] = nil
end

function EnemyService.new(compatibility)
    return setmetatable({
        Compatibility = compatibility,
        Workspace = compatibility.Workspace,
        CollisionPartsByTarget = setmetatable({}, { __mode = "k" }),
        IgnoredSpawns = {},
        HiddenSpawnCache = nil,
        PreparedTargets = setmetatable({}, { __mode = "k" }),
        EnemyModels = setmetatable({}, { __mode = "k" }),
        EnemyModelsByName = {},
        EnemyModelNames = setmetatable({}, { __mode = "k" }),
        EnemyNameConnections = setmetatable({}, { __mode = "k" }),
        SpawnMarkers = setmetatable({}, { __mode = "k" }),
        SpawnMarkersByName = {},
        SpawnMarkerNames = setmetatable({}, { __mode = "k" }),
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

function EnemyService:_GetEnemyModelIndex()
    local enemies = self.Workspace:FindFirstChild("Enemies")
    if not enemies then
        enemies = self.Workspace:FindFirstChild("Enemies", true)
    end
    if enemies == self.EnemyContainer then
        return self.EnemyModels, enemies
    end

    disconnect(self.EnemyAddedConnection)
    disconnect(self.EnemyRemovingConnection)
    for _, connection in pairs(self.EnemyNameConnections) do
        disconnect(connection)
    end
    self.EnemyAddedConnection = nil
    self.EnemyRemovingConnection = nil
    self.EnemyContainer = enemies
    self.EnemyModels = setmetatable({}, { __mode = "k" })
    self.EnemyModelsByName = {}
    self.EnemyModelNames = setmetatable({}, { __mode = "k" })
    self.EnemyNameConnections = setmetatable({}, { __mode = "k" })
    if not enemies then
        return self.EnemyModels, nil
    end

    for _, instance in ipairs(enemies:GetDescendants()) do
        self:_IndexEnemyModel(instance)
    end
    self.EnemyAddedConnection = enemies.DescendantAdded:Connect(function(instance)
        self:_IndexEnemyModel(instance)
    end)
    self.EnemyRemovingConnection = enemies.DescendantRemoving:Connect(function(instance)
        self:_UnindexEnemyModel(instance)
    end)
    return self.EnemyModels, enemies
end

function EnemyService:_IndexEnemyModel(model)
    if not model:IsA("Model") then
        return
    end

    self.EnemyModels[model] = true
    removeNameIndexEntry(self.EnemyModelsByName, self.EnemyModelNames, model)
    addNameIndexEntry(self.EnemyModelsByName, self.EnemyModelNames, model)
    if self.EnemyNameConnections[model] then
        return
    end

    self.EnemyNameConnections[model] = model:GetPropertyChangedSignal("Name"):Connect(function()
        if not self.EnemyModels[model] then
            return
        end
        removeNameIndexEntry(self.EnemyModelsByName, self.EnemyModelNames, model)
        addNameIndexEntry(self.EnemyModelsByName, self.EnemyModelNames, model)
    end)
end

function EnemyService:_UnindexEnemyModel(model)
    if not model:IsA("Model") then
        return
    end
    self.EnemyModels[model] = nil
    removeNameIndexEntry(self.EnemyModelsByName, self.EnemyModelNames, model)
    disconnect(self.EnemyNameConnections[model])
    self.EnemyNameConnections[model] = nil
end

function EnemyService:_GetSpawnMarkerIndex()
    local enemySpawns = self:_GetEnemySpawnsFolder()
    if enemySpawns == self.SpawnContainer then
        return self.SpawnMarkers, enemySpawns
    end

    disconnect(self.SpawnAddedConnection)
    disconnect(self.SpawnRemovingConnection)
    self.SpawnAddedConnection = nil
    self.SpawnRemovingConnection = nil
    self.SpawnContainer = enemySpawns
    self.SpawnMarkers = setmetatable({}, { __mode = "k" })
    self.SpawnMarkersByName = {}
    self.SpawnMarkerNames = setmetatable({}, { __mode = "k" })
    if not enemySpawns then
        return self.SpawnMarkers, nil
    end

    for _, instance in ipairs(enemySpawns:GetDescendants()) do
        self:_IndexSpawnMarker(instance)
    end
    self.SpawnAddedConnection = enemySpawns.DescendantAdded:Connect(function(instance)
        self:_IndexSpawnMarker(instance)
    end)
    self.SpawnRemovingConnection = enemySpawns.DescendantRemoving:Connect(function(instance)
        self:_UnindexSpawnMarker(instance)
    end)
    return self.SpawnMarkers, enemySpawns
end

function EnemyService:_IndexSpawnMarker(spawnPart)
    if not spawnPart:IsA("BasePart") then
        return
    end
    self.SpawnMarkers[spawnPart] = true
    removeNameIndexEntry(self.SpawnMarkersByName, self.SpawnMarkerNames, spawnPart)
    addNameIndexEntry(self.SpawnMarkersByName, self.SpawnMarkerNames, spawnPart)
end

function EnemyService:_UnindexSpawnMarker(spawnPart)
    if not spawnPart:IsA("BasePart") then
        return
    end
    self.SpawnMarkers[spawnPart] = nil
    removeNameIndexEntry(self.SpawnMarkersByName, self.SpawnMarkerNames, spawnPart)
end

function EnemyService:_RefreshHiddenSpawnCache()
    local now = os.clock()
    local current = self.HiddenSpawnCache
    if current and (current.Loading or now < current.ExpiresAt) then
        return current
    end

    local cache = {
        Parts = {},
        ByName = {},
        Available = false,
        Loading = true,
        ExpiresAt = math.huge,
    }
    self.HiddenSpawnCache = cache

    local function markUnavailable()
        if self.HiddenSpawnCache == cache then
            cache.Available = false
            cache.Loading = false
            cache.ExpiresAt = os.clock() + HIDDEN_SPAWN_RETRY_INTERVAL
        end
    end

    task.defer(function()
        local getter = self.Compatibility and self.Compatibility.GetUnparentedInstances
        if type(getter) ~= "function" then
            markUnavailable()
            return
        end

        local callOk, instances = pcall(getter, self.Compatibility)
        if not callOk or type(instances) ~= "table" or self.HiddenSpawnCache ~= cache then
            markUnavailable()
            return
        end

        cache.Available = true
        local scanned = 0
        for _, instance in pairs(instances) do
            if self.HiddenSpawnCache ~= cache then
                return
            end

            local readOk, isBasePart, name, parent = pcall(function()
                return instance:IsA("BasePart"), instance.Name, instance.Parent
            end)
            if readOk and isBasePart and parent == nil and type(name) == "string" then
                cache.Parts[instance] = name
                local normalizedName = normalizeEnemyName(name)
                if normalizedName then
                    local matches = cache.ByName[normalizedName]
                    if not matches then
                        matches = {}
                        cache.ByName[normalizedName] = matches
                    end
                    table.insert(matches, instance)
                end
            end

            scanned += 1
            if scanned % HIDDEN_SPAWN_SCAN_CHUNK_SIZE == 0 then
                task.wait()
            end
        end

        if self.HiddenSpawnCache == cache then
            cache.Loading = false
            cache.ExpiresAt = os.clock() + HIDDEN_SPAWN_REFRESH_INTERVAL
        end
    end)

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
    local enemyModels, enemies = self:_GetEnemyModelIndex()
    local normalizedTargets = normalizeTargetNames(targetName)
    if not enemies or #normalizedTargets == 0 or not origin then
        return nil
    end

    local nearest, nearestDistance = nil, math.huge
    local seen = {}
    for _, normalizedName in ipairs(normalizedTargets) do
        for enemy in pairs(self.EnemyModelsByName[normalizedName] or {}) do
            if not seen[enemy] then
                seen[enemy] = true
                if enemyModels[enemy] and isDescendantOf(enemy, enemies) then
                    local root = enemy:FindFirstChild("HumanoidRootPart")
                    local humanoid = enemy:FindFirstChildWhichIsA("Humanoid")
                    if root and humanoid and humanoid.Health > 0 then
                        local distance = (root.Position - origin).Magnitude
                        if distance < nearestDistance then
                            nearest, nearestDistance = enemy, distance
                        end
                    end
                end
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

    local enemyModels, enemies = self:_GetEnemyModelIndex()
    if not enemies then
        return nil
    end

    local nearest, nearestDistance = nil, radius
    for enemy in pairs(enemyModels) do
        if isDescendantOf(enemy, enemies) and self:IsAlive(enemy) then
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
        HiddenDiscoveryChecked = false,
        SelectedSource = "none",
        SelectedName = nil,
        MatchedTarget = nil,
        SelectedDistance = nil,
    }
    local normalizedTarget = normalizeTargetNames(targetName)
    if #normalizedTarget == 0 then
        return nil, false, diagnostic
    end

    local _, enemySpawns = self:_GetSpawnMarkerIndex()
    local now = os.clock()
    local hiddenCache = self.HiddenSpawnCache
    if hiddenCache and not hiddenCache.Loading and now >= hiddenCache.ExpiresAt then
        hiddenCache = nil
    end
    diagnostic.EnemySpawnsContainerFound = enemySpawns ~= nil
    diagnostic.HiddenDiscoveryChecked = hiddenCache ~= nil
    diagnostic.HiddenDiscoveryAvailable = hiddenCache ~= nil
        and hiddenCache.Available == true
    diagnostic.HiddenDiscoveryLoading = hiddenCache ~= nil
        and hiddenCache.Loading == true
    self:_PruneIgnoredSpawns(
        enemySpawns,
        hiddenCache or { Available = false, Parts = {} },
        targetName
    )

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
        local seenNormal = {}
        for _, normalizedName in ipairs(normalizedTarget) do
            for spawnPart in pairs(self.SpawnMarkersByName[normalizedName] or {}) do
                if not seenNormal[spawnPart] then
                    seenNormal[spawnPart] = true
                    considerSpawn(spawnPart, enemySpawns, nil, "EnemySpawns")
                end
            end
        end
    end

    -- Only enumerate all unparented runtime instances if the normal marker index
    -- cannot provide a candidate. A valid cached fallback remains usable meanwhile.
    if not hiddenCache and not nearest then
        hiddenCache = self:_RefreshHiddenSpawnCache()
        diagnostic.HiddenDiscoveryChecked = true
        diagnostic.HiddenDiscoveryAvailable = hiddenCache.Available == true
        diagnostic.HiddenDiscoveryLoading = hiddenCache.Loading == true
    end

    if hiddenCache
        and hiddenCache.Available
        and not hiddenCache.Loading
        and os.clock() < hiddenCache.ExpiresAt
    then
        local seenHidden = {}
        for _, normalizedName in ipairs(normalizedTarget) do
            for _, spawnPart in ipairs(hiddenCache.ByName[normalizedName] or {}) do
                local cachedName = hiddenCache.Parts[spawnPart]
                if cachedName and not seenHidden[spawnPart] then
                    seenHidden[spawnPart] = true
                    considerSpawn(spawnPart, nil, cachedName, "unparented-cache")
                end
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

function EnemyService:ClearTracking()
    disconnect(self.EnemyAddedConnection)
    disconnect(self.EnemyRemovingConnection)
    disconnect(self.SpawnAddedConnection)
    disconnect(self.SpawnRemovingConnection)
    for _, connection in pairs(self.EnemyNameConnections) do
        disconnect(connection)
    end
    self.EnemyAddedConnection = nil
    self.EnemyRemovingConnection = nil
    self.SpawnAddedConnection = nil
    self.SpawnRemovingConnection = nil
    self.EnemyContainer = nil
    self.SpawnContainer = nil
    self.EnemyModels = setmetatable({}, { __mode = "k" })
    self.EnemyModelsByName = {}
    self.EnemyModelNames = setmetatable({}, { __mode = "k" })
    self.EnemyNameConnections = setmetatable({}, { __mode = "k" })
    self.SpawnMarkers = setmetatable({}, { __mode = "k" })
    self.SpawnMarkersByName = {}
    self.SpawnMarkerNames = setmetatable({}, { __mode = "k" })
    self.HiddenSpawnCache = nil
    table.clear(self.PreparedTargets)
end

function EnemyService:PrepareTarget(model, playerRoot)
    if not self:IsAlive(model) or not playerRoot then
        return
    end
    if (model.HumanoidRootPart.Position - playerRoot.Position).Magnitude > 50 then
        return
    end

    if self.PreparedTargets[model] then
        return
    end
    local targetParts = {}
    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            targetParts[part] = part.CanCollide
            part.CanCollide = false
        end
    end
    self.CollisionPartsByTarget[model] = targetParts
    self.PreparedTargets[model] = true
end

function EnemyService:RestoreTargetCollision(target)
    if target then
        local targetParts = self.CollisionPartsByTarget[target]
        if targetParts then
            local shouldRestore = target.Parent ~= nil
            if shouldRestore then
                local humanoid = target:FindFirstChildWhichIsA("Humanoid")
                if humanoid and humanoid.Health <= 0 then
                    shouldRestore = false
                end
            end

            if shouldRestore then
                for part, originalCanCollide in pairs(targetParts) do
                    if part.Parent and part.CanCollide ~= originalCanCollide then
                        part.CanCollide = originalCanCollide
                    end
                end
            end
        end
        self.CollisionPartsByTarget[target] = nil
        self.PreparedTargets[target] = nil
        return
    end

    for targetModel, targetParts in pairs(self.CollisionPartsByTarget) do
        for part, originalCanCollide in pairs(targetParts) do
            if part.Parent and part.CanCollide ~= originalCanCollide then
                part.CanCollide = originalCanCollide
            end
        end
        self.CollisionPartsByTarget[targetModel] = nil
    end
    table.clear(self.PreparedTargets)
    table.clear(self.CollisionPartsByTarget)
end

return EnemyService
