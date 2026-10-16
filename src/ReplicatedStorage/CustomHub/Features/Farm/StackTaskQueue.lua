local StackTaskQueue = {}
StackTaskQueue.__index = StackTaskQueue

local TASK_KIND = {
    CakePrince = true,
    Fruit = true,
}

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

function StackTaskQueue.new(workspaceService)
    return setmetatable({
        Workspace = workspaceService,
        Enabled = {
            CakePrince = false,
            Fruit = false,
        },
        Pending = {},
        PendingByInstance = setmetatable({}, { __mode = "k" }),
        ActiveByInstance = setmetatable({}, { __mode = "k" }),
        CompletedByInstance = setmetatable({}, { __mode = "k" }),
        KindByInstance = setmetatable({}, { __mode = "k" }),
        SpawnOrderByInstance = setmetatable({}, { __mode = "k" }),
        FruitWatchers = setmetatable({}, { __mode = "k" }),
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
    end)
    for _, instance in ipairs(folder:GetChildren()) do
        self:_ObserveCakePrince(instance)
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

    self:_WatchEnemies(workspaceService:FindFirstChild("Enemies"))
    for _, instance in ipairs(workspaceService:GetChildren()) do
        self:_ObserveFruit(instance)
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
    if self.Enabled[kind] == enabled then
        return true
    end
    self.Enabled[kind] = enabled

    if enabled then
        self:_QueueExisting(kind)
    else
        self:_RemovePending(kind)
        if kind == "Fruit" then
            for instance in pairs(self.FruitWatchers) do
                self:_DisconnectFruitWatcher(instance)
            end
        end
        for instance, observedKind in pairs(self.KindByInstance) do
            if observedKind == kind then
                self.CompletedByInstance[instance] = nil
            end
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
    return self.Enabled.CakePrince == true or self.Enabled.Fruit == true
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
                    or entry.Kind ~= "Fruit"
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
    table.clear(self.Connections)
    table.clear(self.Pending)
    self.PendingByInstance = setmetatable({}, { __mode = "k" })
    self.ActiveByInstance = setmetatable({}, { __mode = "k" })
    self.CompletedByInstance = setmetatable({}, { __mode = "k" })
    self.KindByInstance = setmetatable({}, { __mode = "k" })
    self.SpawnOrderByInstance = setmetatable({}, { __mode = "k" })
    self.FruitWatchers = setmetatable({}, { __mode = "k" })
    self.EnemiesFolder = nil
    self.Workspace = nil
end

return StackTaskQueue
