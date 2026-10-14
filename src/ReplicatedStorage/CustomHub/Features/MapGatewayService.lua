local MapGatewayService = {}
MapGatewayService.__index = MapGatewayService

local MINIMUM_DISTANCE_SAVED = 1500
local MAX_ROUTE_HOPS = 4
local FAILED_ROUTE_COOLDOWN = 120

local ROUTES_BY_SEA = {
    [1] = {
        {
            Name = "Enter Underwater City",
            Stand = Vector3.new(4050, 6, -1815),
            Destination = Vector3.new(61163.85, 11.6797, 1819.78),
        },
        {
            Name = "Leave Underwater City",
            Stand = Vector3.new(61170, 1, 1952),
            Destination = Vector3.new(3864.69, 6.74, -1926.21),
        },
    },
    [2] = {
        {
            Name = "Enter Ghost Ship",
            Stand = Vector3.new(-6499, 91, -127),
            Destination = Vector3.new(923, 126, 32852),
        },
        {
            Name = "Leave Ghost Ship",
            Stand = Vector3.new(920, 155, 32838),
            Destination = Vector3.new(-6509, 89, -133),
        },
    },
    [3] = {
        {
            Name = "Castle to Mansion",
            Stand = Vector3.new(-5060.41, 318.5, -3193.22),
            Destination = Vector3.new(-12463.60, 378.33, -7566.08),
            Requires = "Valkyrie Helm",
        },
        {
            Name = "Mansion to Castle",
            Stand = Vector3.new(-12463.60, 378.33, -7566.08),
            Destination = Vector3.new(-5060.41, 318.5, -3193.22),
            Requires = "Valkyrie Helm",
        },
        {
            Name = "Castle to Hydra",
            Stand = Vector3.new(-5027.03, 318.5, -3206.70),
            Destination = Vector3.new(5650.95, 1017.27, -350.38),
            Requires = "Valkyrie Helm",
        },
        {
            Name = "Hydra to Castle",
            Stand = Vector3.new(5650.95, 1017.27, -350.38),
            Destination = Vector3.new(-5027.03, 318.5, -3206.70),
            Requires = "Valkyrie Helm",
        },
        {
            Name = "Castle to Tiki",
            Stand = Vector3.new(-5097.13, 318.5, -3178.40),
            Destination = Vector3.new(-16814, 58, 304),
            Map = "Boat Castle",
            Touch = "MapTeleportC",
            Requires = "Feathered Visage",
        },
        {
            Name = "Tiki to Castle",
            Stand = Vector3.new(-16799.09, 84.32, 291.07),
            Destination = Vector3.new(-5084.73, 318.5, -3155.86),
            Map = "TikiOutpost",
            Touch = "MapTeleportC",
            Requires = "Feathered Visage",
        },
        {
            Name = "Enter Beautiful Pirate Domain",
            Part = "WaterfallBossHitbox",
            Argument = "WaterfallBossHitbox",
        },
        {
            Name = "Leave Beautiful Pirate Domain",
            Part = "TurtleEntranceBoss",
            Argument = "TurtleEntranceBoss",
        },
    },
}

local function distance(first, second)
    return (first - second).Magnitude
end

function MapGatewayService.new(compatibility)
    return setmetatable({
        Compatibility = compatibility,
        FailedUntil = {},
    }, MapGatewayService)
end

function MapGatewayService:_CurrentSeaIndex()
    local compatibility = self.Compatibility
    local found
    local count = 0
    for index, method in ipairs({ "IsFirstSea", "IsSecondSea", "IsThirdSea" }) do
        local check = compatibility and compatibility[method]
        if type(check) == "function" then
            local ok, result = pcall(check, compatibility)
            if ok and result == true then
                found = index
                count += 1
            end
        end
    end
    return count == 1 and found or nil
end

function MapGatewayService:_ResolveStand(route)
    if route.Stand then
        return route.Stand
    end
    if not route.Part then
        return nil
    end

    local workspace = self.Compatibility and self.Compatibility.Workspace
    local instance = workspace and workspace:FindFirstChild(route.Part, true)
    if not instance then
        return nil
    end
    if instance:IsA("BasePart") then
        return instance.Position
    elseif instance:IsA("Model") then
        return instance:GetPivot().Position
    end
    return nil
end

function MapGatewayService:_ResolveTouchTarget(route)
    local compatibility = self.Compatibility
    if not compatibility or not compatibility.CanSimulateTouch
        or not compatibility:CanSimulateTouch()
    then
        return nil
    end
    local workspace = compatibility.Workspace
    local mapRoot = workspace and workspace:FindFirstChild("Map")
    local map = mapRoot and mapRoot:FindFirstChild(route.Map or "Boat Castle")
    local trigger = map and map:FindFirstChild(route.Touch)
    local collectionService = compatibility.CollectionService
    if not trigger or not collectionService then
        return nil
    end
    local tagOk, tagged = pcall(collectionService.HasTag, collectionService, trigger, "BoatCastleTeleporter")
    if not tagOk or tagged ~= true then
        return nil
    end
    local hitbox = trigger:FindFirstChild("Hitbox")
    return hitbox and hitbox:IsA("BasePart") and hitbox or nil
end

function MapGatewayService:_GetAvailableRoutes(seaIndex)
    local compatibility = self.Compatibility
    local now = os.clock()
    local routes = {}
    for _, source in ipairs(ROUTES_BY_SEA[seaIndex] or {}) do
        if now >= (self.FailedUntil[source.Name] or 0) then
            local available = true
            if source.Requires then
                local checkOk, owned = pcall(
                    compatibility.HasOwnedInventoryItem,
                    compatibility,
                    source.Requires
                )
                available = checkOk and owned == true
            end

            local stand = available and self:_ResolveStand(source) or nil
            available = available and typeof(stand) == "Vector3"
            local touchTarget
            if available and source.Touch then
                touchTarget = self:_ResolveTouchTarget(source)
                available = touchTarget ~= nil
            end

            if available then
                local route = table.clone(source)
                route.Stand = stand
                route.TouchTarget = touchTarget
                table.insert(routes, route)
            end
        end
    end
    return routes
end

function MapGatewayService:FindPlan(destination, currentPosition)
    if typeof(destination) ~= "Vector3" or typeof(currentPosition) ~= "Vector3" then
        return {}, "Travel positions are unavailable"
    end
    local seaIndex = self:_CurrentSeaIndex()
    if not seaIndex then
        return {}, "Current sea is unavailable"
    end

    local routes = self:_GetAvailableRoutes(seaIndex)
    local function findBest(position, remainingHops, used)
        local bestCost = distance(position, destination)
        local bestPath = {}
        if remainingHops <= 0 then
            return bestCost, bestPath
        end

        for _, route in ipairs(routes) do
            if not used[route.Name] then
                used[route.Name] = true
                local remainingCost, remainingPath =
                    findBest(route.Destination, remainingHops - 1, used)
                used[route.Name] = nil
                local routeCost = distance(position, route.Stand) + remainingCost
                if routeCost < bestCost then
                    bestCost = routeCost
                    bestPath = { route }
                    for _, nextRoute in ipairs(remainingPath) do
                        table.insert(bestPath, nextRoute)
                    end
                end
            end
        end
        return bestCost, bestPath
    end

    local directDistance = distance(currentPosition, destination)
    local plannedCost, plan = findBest(currentPosition, MAX_ROUTE_HOPS, {})
    if #plan == 0 or directDistance - plannedCost < MINIMUM_DISTANCE_SAVED then
        return {}, nil
    end
    return plan, nil
end

function MapGatewayService:MarkFailed(route)
    if route and route.Name then
        self.FailedUntil[route.Name] = os.clock() + FAILED_ROUTE_COOLDOWN
    end
end

function MapGatewayService:Use(route, isCurrent)
    local compatibility = self.Compatibility
    isCurrent = isCurrent or function()
        return true
    end
    if not route or not isCurrent() then
        return false, "Travel was cancelled"
    end

    local character, _, root = compatibility:GetCharacterParts()
    if not character or not root then
        return false, "Character is unavailable"
    end

    local requestResult
    if route.TouchTarget then
        local touchOk, touchError = compatibility:TouchPart(
            root,
            route.TouchTarget,
            isCurrent
        )
        if not touchOk then
            return false, touchError
        end
    else
        local remote, remoteError = compatibility:GetCommF()
        if not remote then
            return false, remoteError
        end
        task.spawn(function()
            if not isCurrent() then
                requestResult = { Ok = false, Result = "Travel was cancelled" }
                return
            end
            local ok, result = pcall(function()
                return remote:InvokeServer(
                    "requestEntrance",
                    route.Argument or route.Destination
                )
            end)
            requestResult = { Ok = ok, Result = result }
        end)
    end

    local deadline = os.clock() + 8
    while isCurrent() and os.clock() < deadline do
        local currentCharacter, _, currentRoot = compatibility:GetCharacterParts()
        if currentCharacter ~= character or not currentRoot then
            return false, "Character changed during gateway travel"
        end
        if distance(currentRoot.Position, route.Destination) <= 200 then
            self.FailedUntil[route.Name] = nil
            return true
        end
        if requestResult and not requestResult.Ok then
            self:MarkFailed(route)
            return false, "Gateway request failed: " .. tostring(requestResult.Result)
        end
        task.wait(0.1)
    end
    if not isCurrent() then
        return false, "Travel was cancelled"
    end
    self:MarkFailed(route)
    return false, "Gateway did not confirm arrival"
end

return MapGatewayService
