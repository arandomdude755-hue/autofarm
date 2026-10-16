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

    local entry = {
        Kind = kind,
        Instance = instance,
        Sequence = self:_RememberSpawn(kind, instance),
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

function StackTaskQueue:HasEnabledTasks()
    return self.Enabled.CakePrince == true or self.Enabled.Fruit == true
end

function StackTaskQueue:PopNext()
    table.sort(self.Pending, function(left, right)
        return left.Sequence < right.Sequence
    end)

    while #self.Pending > 0 do
        local entry = table.remove(self.Pending, 1)
        self.PendingByInstance[entry.Instance] = nil
        if self:IsEnabled(entry)
            and entry.Instance
            and (
                entry.Kind == "Fruit"
                    and entry.Instance.Parent == self.Workspace
                    or entry.Kind ~= "Fruit"
                    and entry.Instance.Parent ~= nil
            )
            and not self.CompletedByInstance[entry.Instance]
        then
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
