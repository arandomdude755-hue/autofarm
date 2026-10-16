local StackTaskQueue = {}
StackTaskQueue.__index = StackTaskQueue

local TASK_KIND = {
    CakePrince = true,
    EliteHunter = true,
    RipIndra = true,
    SoulReaper = true,
    DoughKing = true,
    Darkbeard = true,
    Saw = true,
    Greybeard = true,
    CursedCaptain = true,
    FactoryRaid = true,
    CastleRaid = true,
    Fruit = true,
    Berry = true,
    HopEliteHunter = true,
    HopBerry = true,
    SeaUnlock2 = true,
    SeaUnlock3 = true,
}

local MANUAL_TASK_KIND = {
    SeaUnlock2 = true,
    SeaUnlock3 = true,
}

local SPAWNED_BOSS_KINDS = {
    ["rip_indra True Form"] = "RipIndra",
    ["Soul Reaper"] = "SoulReaper",
    ["Dough King"] = "DoughKing",
    ["Darkbeard"] = "Darkbeard",
    ["The Saw"] = "Saw",
    ["Greybeard"] = "Greybeard",
    ["Cursed Captain"] = "CursedCaptain",
    ["Core"] = "FactoryRaid",
}

local CASTLE_RAID_CENTER = Vector3.new(-5543, 313, -2964)
local CASTLE_RAID_RADIUS = 1000

local ELITE_HUNTER_NAMES = {
    Deandre = true,
    Urban = true,
    Diablo = true,
}

local function isAliveEliteHunter(instance)
    if not instance or not instance:IsA("Model") or not ELITE_HUNTER_NAMES[instance.Name] then
        return false
    end
    local root = instance:FindFirstChild("HumanoidRootPart")
    local humanoid = instance:FindFirstChildWhichIsA("Humanoid")
    return root ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function isSpawnedStackBoss(instance)
    return instance ~= nil
        and instance:IsA("Model")
        and SPAWNED_BOSS_KINDS[instance.Name] ~= nil
end

local function isSpawnedBossKind(kind)
    return kind == "RipIndra"
        or kind == "SoulReaper"
        or kind == "DoughKing"
        or kind == "Darkbeard"
        or kind == "Saw"
        or kind == "Greybeard"
        or kind == "CursedCaptain"
        or kind == "FactoryRaid"
end

local function isCastleRaidCandidate(instance)
    if not instance or not instance:IsA("Model") then
        return false
    end

    local name = string.lower(instance.Name)
    if name == "oni2"
        or string.find(name, "boss", 1, true)
        or string.find(name, "friend", 1, true)
        or string.find(name, "wraith", 1, true)
        or name == "rip_indra true form"
    then
        return false
    end

    local root = instance:FindFirstChild("HumanoidRootPart")
    local humanoid = instance:FindFirstChildWhichIsA("Humanoid")
    return root ~= nil
        and humanoid ~= nil
        and humanoid.Health > 0
        and (root.Position - CASTLE_RAID_CENTER).Magnitude <= CASTLE_RAID_RADIUS
end

local function isFruitCandidate(instance)
    return instance ~= nil
        and (instance:IsA("Tool") or instance:IsA("Model"))
        and string.find(string.lower(instance.Name), "fruit", 1, true) ~= nil
end

local function findFruitHandle(instance)
    local handle = instance and instance:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then
        return handle
    end
    return instance and instance:FindFirstChildWhichIsA("BasePart", true) or nil
end

local function isCakePrinceCandidate(instance)
    return instance ~= nil
        and instance:IsA("Model")
        and instance.Name == "Cake Prince"
end

local function hasBerrySpawnData(bush)
    if not bush then
        return false
    end
    for _, value in pairs(bush:GetAttributes()) do
        if value ~= nil and value ~= false and value ~= "" then
            return true
        end
    end
    return false
end

local function findBerryPickup(bush)
    if not bush then
        return nil, nil
    end
    for _, child in ipairs(bush:GetChildren()) do
        local prompt
        if child:IsA("ProximityPrompt") then
            prompt = child
        else
            prompt = child:FindFirstChildWhichIsA("ProximityPrompt", true)
        end
        if prompt then
            return child:IsA("ProximityPrompt") and child.Parent or child, prompt
        end
    end
    return nil, nil
end

local function instancePivot(instance)
    if not instance then
        return nil
    end
    if instance:IsA("BasePart") then
        return instance.CFrame
    elseif instance:IsA("Model") then
        return instance:GetPivot()
    end
    local cframe = instance:GetAttribute("CFrame")
    if typeof(cframe) == "CFrame" then
        return cframe
    elseif typeof(cframe) == "Vector3" then
        return CFrame.new(cframe)
    end
    return nil
end

function StackTaskQueue.new(workspaceService, collectionService, replicatedStorage)
    return setmetatable({
        Workspace = workspaceService,
        CollectionService = collectionService,
        ReplicatedStorage = replicatedStorage,
        Enabled = {
            CakePrince = false,
            EliteHunter = false,
            RipIndra = false,
            SoulReaper = false,
            DoughKing = false,
            Darkbeard = false,
            Saw = false,
            Greybeard = false,
            CursedCaptain = false,
            FactoryRaid = false,
            CastleRaid = false,
            Fruit = false,
            Berry = false,
            HopEliteHunter = false,
            HopBerry = false,
            SeaUnlock2 = false,
            SeaUnlock3 = false,
        },
        Pending = {},
        PendingByInstance = setmetatable({}, { __mode = "k" }),
        ActiveByInstance = setmetatable({}, { __mode = "k" }),
        CompletedByInstance = setmetatable({}, { __mode = "k" }),
        KindByInstance = setmetatable({}, { __mode = "k" }),
        SpawnOrderByInstance = setmetatable({}, { __mode = "k" }),
        FruitWatchers = setmetatable({}, { __mode = "k" }),
        BerryWatchers = setmetatable({}, { __mode = "k" }),
        BerryActiveByBush = setmetatable({}, { __mode = "k" }),
        BerryPickupByBush = setmetatable({}, { __mode = "k" }),
        EliteByName = {},
        Sequence = 0,
        Connections = {},
        EnemiesConnection = nil,
        EnemiesFolder = nil,
    }, StackTaskQueue)
end

function StackTaskQueue:_DisconnectFruitWatcher(instance)
    local connections = self.FruitWatchers[instance]
    if not connections then
        return
    end
    self.FruitWatchers[instance] = nil
    for _, connection in ipairs(connections) do
        if connection.Connected then
            connection:Disconnect()
        end
    end
end

function StackTaskQueue:_DisconnectBerryWatcher(instance)
    local connections = self.BerryWatchers[instance]
    if not connections then
        return
    end
    self.BerryWatchers[instance] = nil
    for _, connection in ipairs(connections) do
        if connection.Connected then
            connection:Disconnect()
        end
    end
end

function StackTaskQueue:_RememberSpawn(kind, instance)
    if self.SpawnOrderByInstance[instance] == nil then
        self.Sequence += 1
        self.SpawnOrderByInstance[instance] = self.Sequence
        self.KindByInstance[instance] = kind
    end
    return self.SpawnOrderByInstance[instance]
end

function StackTaskQueue:_Queue(kind, instance)
    if not self.Enabled[kind]
        or self.PendingByInstance[instance]
        or self.ActiveByInstance[instance]
        or self.CompletedByInstance[instance]
    then
        return
    end

    local spawnSequence = self:_RememberSpawn(kind, instance)
    local entry = {
        Kind = kind,
        Instance = instance,
        Sequence = spawnSequence,
        QueueSequence = spawnSequence,
        QueuedAt = os.clock(),
        HadHandle = kind == "Fruit",
    }
    self.PendingByInstance[instance] = entry
    table.insert(self.Pending, entry)
end

function StackTaskQueue:_ObserveFruit(instance)
    if not isFruitCandidate(instance) then
        return
    end
    self:_RememberSpawn("Fruit", instance)
    if not self.Enabled.Fruit or instance.Parent ~= self.Workspace then
        return
    end

    if findFruitHandle(instance) then
        self:_DisconnectFruitWatcher(instance)
        self:_Queue("Fruit", instance)
        return
    end
    if self.FruitWatchers[instance] then
        return
    end

    local connections = {}
    self.FruitWatchers[instance] = connections
    local function checkReady()
        if not self.Workspace or instance.Parent ~= self.Workspace then
            self:_DisconnectFruitWatcher(instance)
            return
        end
        if findFruitHandle(instance) then
            self:_DisconnectFruitWatcher(instance)
            self:_Queue("Fruit", instance)
        end
    end
    table.insert(connections, instance.DescendantAdded:Connect(checkReady))
    table.insert(connections, instance.AncestryChanged:Connect(function(_, parent)
        if parent ~= self.Workspace then
            self:_DisconnectFruitWatcher(instance)
        end
    end))
    checkReady()
end

function StackTaskQueue:_ObserveCakePrince(instance)
    if not isCakePrinceCandidate(instance) then
        return
    end
    self:_RememberSpawn("CakePrince", instance)
    self:_Queue("CakePrince", instance)
end

function StackTaskQueue:_ObserveEliteHunter(instance)
    if not isAliveEliteHunter(instance) then
        return
    end

    self:_RememberSpawn("EliteHunter", instance)
    if not self.Enabled.EliteHunter then
        return
    end

    local existing = self.EliteByName[instance.Name]
    if existing then
        local existingInstance = existing.Instance
        if existingInstance == instance then
            return
        end

        local oldIsAlive = isAliveEliteHunter(existingInstance)
        if not oldIsAlive then
            self:_RemovePendingInstance("EliteHunter", existingInstance)
            self.ActiveByInstance[existingInstance] = nil
            self.EliteByName[instance.Name] = nil
            existing = nil
        end
    end

    if existing then
        local existingInstance = existing.Instance
        local wasActive = existingInstance and self.ActiveByInstance[existingInstance] == true
        local oldIsInWorkspace = existingInstance
            and existingInstance:IsDescendantOf(self.Workspace)
        local newIsInWorkspace = instance:IsDescendantOf(self.Workspace)
        if newIsInWorkspace and not oldIsInWorkspace then
            self.PendingByInstance[existingInstance] = nil
            self.ActiveByInstance[existingInstance] = nil
            existing.Instance = instance
            self.PendingByInstance[instance] = existing
            if wasActive then
                self.ActiveByInstance[instance] = true
            end
        end
        return
    end

    self:_Queue("EliteHunter", instance)
    local entry = self.PendingByInstance[instance]
    if entry then
        self.EliteByName[instance.Name] = entry
    end
end

function StackTaskQueue:_ObserveSpawnedBoss(instance)
    if not isSpawnedStackBoss(instance) then
        return
    end
    local kind = SPAWNED_BOSS_KINDS[instance.Name]
    self:_RememberSpawn(kind, instance)
    self:_Queue(kind, instance)
end

function StackTaskQueue:_ObserveCastleRaid(instance)
    if not isCastleRaidCandidate(instance) then
        return
    end
    self:_RememberSpawn("CastleRaid", instance)
    self:_Queue("CastleRaid", instance)
end

function StackTaskQueue:BindLiveEliteTarget(entry, target)
    if not entry
        or entry.Kind ~= "EliteHunter"
        or not isAliveEliteHunter(target)
        or not self.EnemiesFolder
        or target.Parent ~= self.EnemiesFolder
    then
        return false
    end

    local previous = entry.Instance
    if previous ~= target then
        self.PendingByInstance[previous] = nil
        self.ActiveByInstance[previous] = nil
        entry.Instance = target
        self.PendingByInstance[target] = nil
        self.ActiveByInstance[target] = true
        self.CompletedByInstance[target] = nil
        self.KindByInstance[target] = "EliteHunter"
        self.SpawnOrderByInstance[target] = entry.QueueSequence
        self.EliteByName[target.Name] = entry
    end
    return true
end

function StackTaskQueue:_ForgetBerryBush(bush)
    self:_DisconnectBerryWatcher(bush)
    self:_RemovePendingInstance("Berry", bush)
    self.BerryActiveByBush[bush] = nil
    self.BerryPickupByBush[bush] = nil
    self.PendingByInstance[bush] = nil
    self.CompletedByInstance[bush] = nil
    self.KindByInstance[bush] = nil
    self.SpawnOrderByInstance[bush] = nil
end

function StackTaskQueue:_ObserveBerry(bush)
    if not self.CollectionService
        or not bush
        or not self.CollectionService:HasTag(bush, "BerryBush")
    then
        return
    end

    local parent = bush.Parent
    if not parent then
        return
    end
    if parent:FindFirstChild("IgnoredBerry") or parent:FindFirstChild("Ignored") then
        self:_RemovePendingInstance("Berry", bush)
        self.CompletedByInstance[bush] = nil
        self.BerryActiveByBush[bush] = false
        self.KindByInstance[bush] = nil
        self.SpawnOrderByInstance[bush] = nil
        return
    end

    local berryModel = findBerryPickup(bush)
    local active = hasBerrySpawnData(bush) or berryModel ~= nil
    if not active then
        if self.BerryActiveByBush[bush] ~= false then
            self:_RemovePendingInstance("Berry", bush)
            self.CompletedByInstance[bush] = nil
            self.KindByInstance[bush] = nil
            self.SpawnOrderByInstance[bush] = nil
        end
        self.BerryActiveByBush[bush] = false
        return
    end

    if self.BerryActiveByBush[bush] == false then
        self.CompletedByInstance[bush] = nil
        self.KindByInstance[bush] = nil
        self.SpawnOrderByInstance[bush] = nil
    end
    self.BerryActiveByBush[bush] = true
    local previousPickup = self.BerryPickupByBush[bush]
    if berryModel and berryModel ~= previousPickup then
        self.BerryPickupByBush[bush] = berryModel
        self.CompletedByInstance[bush] = nil
    elseif previousPickup and not previousPickup:IsDescendantOf(bush) then
        self.BerryPickupByBush[bush] = nil
    end
    if not self.Enabled.Berry then
        return
    end

    self:_RememberSpawn("Berry", bush)
    if not self.BerryWatchers[bush] then
        local connections = {}
        self.BerryWatchers[bush] = connections
        table.insert(connections, bush.AttributeChanged:Connect(function()
            self:_ObserveBerry(bush)
        end))
        table.insert(connections, bush.DescendantAdded:Connect(function()
            self:_ObserveBerry(bush)
        end))
        table.insert(connections, bush.DescendantRemoving:Connect(function()
            task.defer(function()
                if self.BerryWatchers[bush] then
                    self:_ObserveBerry(bush)
                end
            end)
        end))
        table.insert(connections, bush.AncestryChanged:Connect(function(_, newParent)
            if not newParent then
                self:_ForgetBerryBush(bush)
            end
        end))
    end
    self:_Queue("Berry", bush)
end

function StackTaskQueue:_RemovePendingInstance(kind, instance)
    for index = #self.Pending, 1, -1 do
        local entry = self.Pending[index]
        if entry.Kind == kind and entry.Instance == instance then
            self.PendingByInstance[instance] = nil
            table.remove(self.Pending, index)
        end
    end
end

function StackTaskQueue:IsBerryBush(bush)
    return self.CollectionService ~= nil
        and bush ~= nil
        and self.CollectionService:HasTag(bush, "BerryBush")
end

function StackTaskQueue:IsBerryActive(bush)
    if not self:IsBerryBush(bush) then
        return false
    end
    local parent = bush.Parent
    if not parent or parent:FindFirstChild("IgnoredBerry") or parent:FindFirstChild("Ignored") then
        return false
    end
    local model = findBerryPickup(bush)
    return hasBerrySpawnData(bush) or model ~= nil
end

function StackTaskQueue:GetBerryPickup(bush)
    local model, prompt = findBerryPickup(bush)
    local destination = instancePivot(model)
    if not destination then
        destination = instancePivot(bush and bush.Parent)
    end
    if not destination then
        destination = instancePivot(bush)
    end
    return model, prompt, destination
end

function StackTaskQueue:_WatchEnemies(folder)
    if not folder or folder == self.EnemiesFolder then
        return
    end
    if self.EnemiesConnection then
        self.EnemiesConnection:Disconnect()
        self.EnemiesConnection = nil
    end
    self.EnemiesFolder = folder
    self.EnemiesConnection = folder.ChildAdded:Connect(function(instance)
        self:_ObserveCakePrince(instance)
        self:_ObserveEliteHunter(instance)
        self:_ObserveSpawnedBoss(instance)
        self:_ObserveCastleRaid(instance)
    end)
    for _, instance in ipairs(folder:GetChildren()) do
        self:_ObserveCakePrince(instance)
        self:_ObserveEliteHunter(instance)
        self:_ObserveSpawnedBoss(instance)
        self:_ObserveCastleRaid(instance)
    end
end

function StackTaskQueue:Initialize()
    local workspaceService = self.Workspace
    if not workspaceService then
        return false, "Workspace is unavailable"
    end

    table.insert(self.Connections, workspaceService.ChildAdded:Connect(function(instance)
        if instance.Name == "Enemies" then
            self:_WatchEnemies(instance)
        end
        self:_ObserveFruit(instance)
    end))

    local replicatedStorage = self.ReplicatedStorage
    if replicatedStorage then
        table.insert(
            self.Connections,
            replicatedStorage.ChildAdded:Connect(function(instance)
                self:_ObserveEliteHunter(instance)
            end)
        )
    end

    self:_WatchEnemies(workspaceService:FindFirstChild("Enemies"))
    for _, instance in ipairs(workspaceService:GetChildren()) do
        self:_ObserveFruit(instance)
    end
    if replicatedStorage then
        for _, instance in ipairs(replicatedStorage:GetChildren()) do
            self:_ObserveEliteHunter(instance)
        end
    end

    local collectionService = self.CollectionService
    if collectionService then
        table.insert(
            self.Connections,
            collectionService:GetInstanceAddedSignal("BerryBush"):Connect(function(bush)
                self:_ObserveBerry(bush)
            end)
        )
        table.insert(
            self.Connections,
            collectionService:GetInstanceRemovedSignal("BerryBush"):Connect(function(bush)
                self:_ForgetBerryBush(bush)
            end)
        )
    end
    return true
end

function StackTaskQueue:_QueueExisting(kind)
    local workspaceService = self.Workspace
    if not workspaceService then
        return
    end

    if kind == "Fruit" then
        for _, instance in ipairs(workspaceService:GetChildren()) do
            self:_ObserveFruit(instance)
        end
    elseif kind == "CakePrince" then
        local enemies = workspaceService:FindFirstChild("Enemies")
        if enemies then
            self:_WatchEnemies(enemies)
            for _, instance in ipairs(enemies:GetChildren()) do
                self:_ObserveCakePrince(instance)
            end
        end
    elseif kind == "EliteHunter" then
        local replicatedStorage = self.ReplicatedStorage
        if replicatedStorage then
            for _, instance in ipairs(replicatedStorage:GetChildren()) do
                self:_ObserveEliteHunter(instance)
            end
        end
        local enemies = workspaceService:FindFirstChild("Enemies")
        if enemies then
            self:_WatchEnemies(enemies)
            for _, instance in ipairs(enemies:GetChildren()) do
                self:_ObserveEliteHunter(instance)
            end
        end
    elseif isSpawnedBossKind(kind) then
        local enemies = self.Workspace:FindFirstChild("Enemies")
        if enemies then
            self:_WatchEnemies(enemies)
            for _, instance in ipairs(enemies:GetChildren()) do
                self:_ObserveSpawnedBoss(instance)
            end
        end
    elseif kind == "CastleRaid" then
        local enemies = self.Workspace:FindFirstChild("Enemies")
        if enemies then
            self:_WatchEnemies(enemies)
            for _, instance in ipairs(enemies:GetChildren()) do
                self:_ObserveCastleRaid(instance)
            end
        end
    elseif kind == "Berry" then
        local collectionService = self.CollectionService
        if collectionService then
            for _, bush in ipairs(collectionService:GetTagged("BerryBush")) do
                self:_ObserveBerry(bush)
            end
        end
    end
end

function StackTaskQueue:_RemovePending(kind)
    for index = #self.Pending, 1, -1 do
        local entry = self.Pending[index]
        if entry.Kind == kind then
            self.PendingByInstance[entry.Instance] = nil
            table.remove(self.Pending, index)
        end
    end
end

function StackTaskQueue:SetEnabled(kind, enabled)
    if not TASK_KIND[kind] then
        return false, "Unsupported stack task"
    end

    enabled = enabled == true
    if enabled and kind == "Berry" and not self.CollectionService then
        return false, "Berry detection is unavailable"
    end
    if self.Enabled[kind] == enabled then
        return true
    end
    self.Enabled[kind] = enabled

    if enabled then
        if kind ~= "HopEliteHunter"
            and kind ~= "HopBerry"
            and not MANUAL_TASK_KIND[kind]
        then
            self:_QueueExisting(kind)
        end
    else
        self:_RemovePending(kind)
        if kind == "Fruit" then
            for instance in pairs(self.FruitWatchers) do
                self:_DisconnectFruitWatcher(instance)
            end
        elseif kind == "Berry" then
            for bush in pairs(self.BerryWatchers) do
                self:_DisconnectBerryWatcher(bush)
            end
        end
        for instance, observedKind in pairs(self.KindByInstance) do
            if observedKind == kind then
                self.CompletedByInstance[instance] = nil
            end
        end
        if kind == "EliteHunter" then
            table.clear(self.EliteByName)
        end
    end
    return true
end

function StackTaskQueue:QueueManual(kind, token)
    if not MANUAL_TASK_KIND[kind] then
        return false, "Unsupported manual stack task"
    end
    if type(token) ~= "table" then
        return false, "Manual stack task token is invalid"
    end
    if not self.Enabled[kind] then
        return false, "Manual stack task is disabled"
    end
    self:_Queue(kind, token)
    return self.PendingByInstance[token] ~= nil
        or self.ActiveByInstance[token] ~= nil
end

function StackTaskQueue:RemoveManual(kind, token)
    if not MANUAL_TASK_KIND[kind] or type(token) ~= "table" then
        return false
    end
    local entry = self.PendingByInstance[token]
    if not entry or entry.Kind ~= kind then
        return false
    end
    self.PendingByInstance[token] = nil
    for index = #self.Pending, 1, -1 do
        if self.Pending[index] == entry then
            table.remove(self.Pending, index)
            break
        end
    end
    return true
end

function StackTaskQueue:IsEnabled(entry)
    return entry ~= nil and self.Enabled[entry.Kind] == true
end

local function optimizeFruitRun(entries, currentPosition, estimateTravelCost)
    local count = #entries
    if count < 2 or typeof(currentPosition) ~= "Vector3" then
        return entries
    end

    local positions = {}
    for index, entry in ipairs(entries) do
        local handle = findFruitHandle(entry.Instance)
        if not handle then
            return entries
        end
        positions[index] = handle.Position
    end

    local costs = {}
    local function getCost(fromIndex, toIndex)
        costs[fromIndex] = costs[fromIndex] or {}
        local cached = costs[fromIndex][toIndex]
        if cached then
            return cached
        end

        local fromPosition = fromIndex == 0 and currentPosition or positions[fromIndex]
        local toPosition = positions[toIndex]
        local cost
        if type(estimateTravelCost) == "function" then
            local ok, result = pcall(estimateTravelCost, fromPosition, toPosition)
            if ok and type(result) == "number" and result == result and result < math.huge then
                cost = result
            end
        end
        if not cost then
            cost = (toPosition - fromPosition).Magnitude
        end
        costs[fromIndex][toIndex] = cost
        return cost
    end

    local order = {}
    if count <= 10 then
        -- Exact shortest visiting order for the small fruit batches normally seen in a server.
        local fullMask = 2 ^ count - 1
        local memo = {}
        local function solve(mask, lastIndex)
            if mask == fullMask then
                return 0
            end
            local memoKey = mask * (count + 1) + lastIndex
            local cached = memo[memoKey]
            if cached then
                return cached.Cost
            end

            local bestCost = math.huge
            local bestNext
            for nextIndex = 1, count do
                local bit = 2 ^ (nextIndex - 1)
                if math.floor(mask / bit) % 2 == 0 then
                    local nextMask = mask + bit
                    local total = getCost(lastIndex, nextIndex)
                        + solve(nextMask, nextIndex)
                    if total < bestCost then
                        bestCost = total
                        bestNext = nextIndex
                    end
                end
            end
            memo[memoKey] = { Cost = bestCost, Next = bestNext }
            return bestCost
        end

        solve(0, 0)
        local mask = 0
        local lastIndex = 0
        while mask ~= fullMask do
            local choice = memo[mask * (count + 1) + lastIndex]
            local nextIndex = choice and choice.Next
            if not nextIndex then
                return entries
            end
            table.insert(order, nextIndex)
            mask += 2 ^ (nextIndex - 1)
            lastIndex = nextIndex
        end
    else
        -- Keep unusually large batches responsive; use gateway-aware nearest-next selection.
        local remaining = {}
        for index = 1, count do
            remaining[index] = true
        end
        local lastIndex = 0
        for _ = 1, count do
            local bestIndex
            local bestCost = math.huge
            for index = 1, count do
                if remaining[index] then
                    local cost = getCost(lastIndex, index)
                    if cost < bestCost then
                        bestCost = cost
                        bestIndex = index
                    end
                end
            end
            if not bestIndex then
                return entries
            end
            table.insert(order, bestIndex)
            remaining[bestIndex] = nil
            lastIndex = bestIndex
        end
    end

    local ordered = {}
    for _, index in ipairs(order) do
        ordered[#ordered + 1] = entries[index]
    end
    return ordered
end

function StackTaskQueue:HasEnabledTasks()
    return self.Enabled.CakePrince == true
        or self.Enabled.EliteHunter == true
        or self.Enabled.RipIndra == true
        or self.Enabled.SoulReaper == true
        or self.Enabled.DoughKing == true
        or self.Enabled.Darkbeard == true
        or self.Enabled.Saw == true
        or self.Enabled.Greybeard == true
        or self.Enabled.CursedCaptain == true
        or self.Enabled.FactoryRaid == true
        or self.Enabled.CastleRaid == true
        or self.Enabled.Fruit == true
        or self.Enabled.Berry == true
        or self.Enabled.HopEliteHunter == true
        or self.Enabled.HopBerry == true
        or self.Enabled.SeaUnlock2 == true
        or self.Enabled.SeaUnlock3 == true
end

function StackTaskQueue:TakePendingKind(kind)
    for index, entry in ipairs(self.Pending) do
        if entry.Kind == kind then
            local instance = entry.Instance
            local isPresent = instance
                and instance.Parent == self.EnemiesFolder
                and isSpawnedStackBoss(instance)
            table.remove(self.Pending, index)
            self.PendingByInstance[instance] = nil
            if self:IsEnabled(entry) and isPresent then
                self.ActiveByInstance[instance] = true
                return entry
            end
            self.CompletedByInstance[instance] = true
            return nil, "The boss was defeated before it could be reached"
        end
    end
    return nil
end

function StackTaskQueue:PopNext(currentPosition, estimateTravelCost)
    table.sort(self.Pending, function(left, right)
        return left.QueueSequence < right.QueueSequence
    end)

    local validPending = {}
    for _, entry in ipairs(self.Pending) do
        local instance = entry.Instance
        local isPresent = instance
            and (
                entry.Kind == "Fruit"
                    and instance.Parent == self.Workspace
                    or entry.Kind == "EliteHunter"
                    and instance.Parent ~= nil
                    and isAliveEliteHunter(instance)
                    or isSpawnedBossKind(entry.Kind)
                    and instance.Parent == self.EnemiesFolder
                    and isSpawnedStackBoss(instance)
                    or MANUAL_TASK_KIND[entry.Kind]
                    and instance ~= nil
                    or entry.Kind ~= "Fruit"
                    and entry.Kind ~= "EliteHunter"
                    and not isSpawnedBossKind(entry.Kind)
                    and instance.Parent ~= nil
            )
        if self:IsEnabled(entry) and isPresent and not self.CompletedByInstance[instance] then
            validPending[#validPending + 1] = entry
        else
            self.PendingByInstance[instance] = nil
        end
    end
    self.Pending = validPending

    if self.Pending[1] and self.Pending[1].Kind == "Fruit" then
        local fruitRun = {}
        local index = 1
        while self.Pending[index] and self.Pending[index].Kind == "Fruit" do
            fruitRun[#fruitRun + 1] = self.Pending[index]
            index += 1
        end
        if #fruitRun > 1 then
            local ordered = optimizeFruitRun(fruitRun, currentPosition, estimateTravelCost)
            local queueSlots = {}
            for fruitIndex, entry in ipairs(fruitRun) do
                queueSlots[fruitIndex] = entry.QueueSequence
            end
            for fruitIndex, entry in ipairs(ordered) do
                entry.QueueSequence = queueSlots[fruitIndex]
                self.Pending[fruitIndex] = entry
            end
        end
    end

    while #self.Pending > 0 do
        local entry = table.remove(self.Pending, 1)
        self.PendingByInstance[entry.Instance] = nil
        if self:IsEnabled(entry) and entry.Instance then
            self.ActiveByInstance[entry.Instance] = true
            return entry
        end
    end
    return nil
end

function StackTaskQueue:Complete(entry, markCompleted)
    if not entry or not entry.Instance then
        return
    end
    self.PendingByInstance[entry.Instance] = nil
    self.ActiveByInstance[entry.Instance] = nil
    if markCompleted == false then
        self.CompletedByInstance[entry.Instance] = nil
    else
        self.CompletedByInstance[entry.Instance] = true
    end
    if entry.Kind == "EliteHunter"
        and self.EliteByName[entry.Instance.Name] == entry
    then
        self.EliteByName[entry.Instance.Name] = nil
    end
end

function StackTaskQueue:Cleanup()
    if self.EnemiesConnection then
        self.EnemiesConnection:Disconnect()
        self.EnemiesConnection = nil
    end
    for _, connection in ipairs(self.Connections) do
        connection:Disconnect()
    end
    for instance in pairs(self.FruitWatchers) do
        self:_DisconnectFruitWatcher(instance)
    end
    for bush in pairs(self.BerryWatchers) do
        self:_DisconnectBerryWatcher(bush)
    end
    table.clear(self.Connections)
    table.clear(self.Pending)
    self.PendingByInstance = setmetatable({}, { __mode = "k" })
    self.ActiveByInstance = setmetatable({}, { __mode = "k" })
    self.CompletedByInstance = setmetatable({}, { __mode = "k" })
    self.KindByInstance = setmetatable({}, { __mode = "k" })
    self.SpawnOrderByInstance = setmetatable({}, { __mode = "k" })
    self.FruitWatchers = setmetatable({}, { __mode = "k" })
    self.BerryWatchers = setmetatable({}, { __mode = "k" })
    self.BerryActiveByBush = setmetatable({}, { __mode = "k" })
    self.BerryPickupByBush = setmetatable({}, { __mode = "k" })
    table.clear(self.EliteByName)
    self.EnemiesFolder = nil
    self.CollectionService = nil
    self.Workspace = nil
    self.ReplicatedStorage = nil
end

return StackTaskQueue
