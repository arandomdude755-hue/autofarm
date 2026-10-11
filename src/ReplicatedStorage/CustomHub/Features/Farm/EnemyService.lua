local EnemyService = {}
EnemyService.__index = EnemyService

local function normalizeEnemyName(name)
    return (name:gsub(" %p?Lv%.? %d+%p?", ""))
end

function EnemyService.new(compatibility)
    return setmetatable({
        Compatibility = compatibility,
        Workspace = compatibility.Workspace,
        CollisionOriginals = {},
    }, EnemyService)
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

function EnemyService:FindSpawn(targetName)
    local worldOrigin = self.Workspace:FindFirstChild("_WorldOrigin")
    local enemySpawns = worldOrigin and worldOrigin:FindFirstChild("EnemySpawns")
    if not enemySpawns or type(targetName) ~= "string" then
        return nil
    end

    local normalizedTarget = normalizeEnemyName(targetName)
    for _, spawnPart in ipairs(enemySpawns:GetChildren()) do
        if spawnPart:IsA("BasePart") then
            local normalizedSpawn = normalizeEnemyName(spawnPart.Name)
            if spawnPart.Name == targetName or normalizedSpawn == normalizedTarget then
                return spawnPart
            end
        end
    end
    return nil
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
