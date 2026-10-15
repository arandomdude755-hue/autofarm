local MapGatewayService = {}
MapGatewayService.__index = MapGatewayService

local MINIMUM_DISTANCE_SAVED = 1500
local MAX_ROUTE_HOPS = 4
local ROUTE_LOCATION_REPEAT_DISTANCE = 500
local FAILED_ROUTE_COOLDOWN = 10
local FAILED_APPROACH_COOLDOWN = 8
local GATEWAY_ACTIVATION_TIMEOUT = 5
local GATEWAY_TOUCH_LOAD_TIMEOUT = 2
local GATEWAY_STAND_ACCEPTANCE = 25
local GATEWAY_STAND_ALIGNMENT = 3
local GATEWAY_ARRIVAL_RADIUS = 500
local REMOTE_RETRY_INTERVAL = 0.3

local SEA_LABELS = {
    [1] = "First Sea",
    [2] = "Second Sea",
    [3] = "Third Sea",
}

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
            RequiresTitle = "Liberator of the Sky",
        },
        {
            Name = "Tiki to Castle",
            Stand = Vector3.new(-16799.09, 84.32, 291.07),
            Destination = Vector3.new(-5084.73, 318.5, -3155.86),
            Map = "TikiOutpost",
            Touch = "MapTeleportC",
            Requires = "Feathered Visage",
            RequiresTitle = "Liberator of the Sky",
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

local function repeatsGatewayArea(position, visitedPositions)
    for _, visitedPosition in ipairs(visitedPositions) do
        if typeof(visitedPosition) == "Vector3"
            and distance(position, visitedPosition) <= ROUTE_LOCATION_REPEAT_DISTANCE
        then
            return true
        end
    end
    return false
end

local function formatPosition(position)
    if typeof(position) ~= "Vector3" then
        return "n/a"
    end
    return string.format("(%.1f, %.1f, %.1f)", position.X, position.Y, position.Z)
end

local function formatScalar(value, limit)
    local text = tostring(value):gsub("[%c]", " ")
    limit = limit or 120
    if #text > limit then
        text = string.sub(text, 1, limit) .. "..."
    end
    return text
end

function MapGatewayService.new(compatibility)
    return setmetatable({
        Compatibility = compatibility,
        FailedUntil = {},
        LastFailures = {},
        LastDiagnostic = nil,
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
        return nil, "touch simulation is unavailable on this client"
    end
    local workspace = compatibility.Workspace
    local mapRoot = workspace and workspace:FindFirstChild("Map")
    local map = mapRoot and mapRoot:FindFirstChild(route.Map or "Boat Castle", true)
    local trigger = map and map:FindFirstChild(route.Touch, true)
    local collectionService = compatibility.CollectionService
    if not trigger then
        return nil, "gateway trigger is not loaded"
    end
    if not collectionService then
        return nil, "CollectionService is unavailable"
    end
    local tagOk, tagged = pcall(collectionService.HasTag, collectionService, trigger, "BoatCastleTeleporter")
    if not tagOk or tagged ~= true then
        return nil, "gateway trigger is not tagged BoatCastleTeleporter"
    end
    local hitbox = trigger:FindFirstChild("Hitbox", true)
    if not hitbox or not hitbox:IsA("BasePart") then
        return nil, "gateway trigger Hitbox is missing or not a BasePart"
    end
    return hitbox, nil
end

function MapGatewayService:_GetAvailableRoutes(seaIndex, currentPosition, destination)
    local compatibility = self.Compatibility
    local now = os.clock()
    local routes = {}
    local candidates = {}
    local diagnostic = self.LastDiagnostic
    if diagnostic then
        diagnostic.Candidates = candidates
    end

    local function estimateTitleRouteCost(source)
        local estimateRoutes = {}
        for _, route in ipairs(ROUTES_BY_SEA[seaIndex] or {}) do
            local includeRoute = route.Name == source.Name
            if not includeRoute and not route.RequiresTitle then
                includeRoute = true
                if route.Requires then
                    local checkOk, owned = pcall(
                        compatibility.HasOwnedInventoryItem,
                        compatibility,
                        route.Requires
                    )
                    includeRoute = checkOk and owned == true
                end
            end

            if includeRoute and typeof(route.Destination) == "Vector3" then
                local stand = route.Name == source.Name
                        and source.Stand
                    or self:_ResolveStand(route)
                if typeof(stand) == "Vector3" then
                    table.insert(estimateRoutes, {
                        Name = route.Name,
                        Stand = stand,
                        Destination = route.Destination,
                    })
                end
            end
        end

        local function findBestTitlePath(position, remainingHops, used, titleRouteUsed, visited)
            local bestCost = titleRouteUsed and distance(position, destination) or math.huge
            if remainingHops <= 0 then
                return bestCost
            end

            for _, route in ipairs(estimateRoutes) do
                if not used[route.Name]
                    and not repeatsGatewayArea(route.Destination, visited)
                then
                    used[route.Name] = true
                    table.insert(visited, route.Destination)
                    local includesTitleRoute =
                        titleRouteUsed or route.Name == source.Name
                    local remainingCost = findBestTitlePath(
                        route.Destination,
                        remainingHops - 1,
                        used,
                        includesTitleRoute,
                        visited
                    )
                    table.remove(visited)
                    used[route.Name] = nil
                    local routeCost = distance(position, route.Stand) + remainingCost
                    if routeCost < bestCost then
                        bestCost = routeCost
                    end
                end
            end
            return bestCost
        end

        return findBestTitlePath(
            currentPosition,
            MAX_ROUTE_HOPS,
            {},
            false,
            { currentPosition }
        )
    end

    for _, source in ipairs(ROUTES_BY_SEA[seaIndex] or {}) do
        local candidate = {
            Name = source.Name,
            Requirement = source.Requires,
            FallbackTitle = source.RequiresTitle,
            Activation = source.Touch and "touch" or "requestEntrance",
            Eligible = false,
        }
        local lastFailure = self.LastFailures[source.Name]
        if lastFailure then
            candidate.PreviousFailure = lastFailure.Reason
            candidate.PreviousFailureAge = math.max(0, now - lastFailure.At)
            local attempt = lastFailure.Attempt
            if attempt then
                candidate.PreviousFailurePhase = attempt.Phase
                candidate.PreviousFailureCallStatus = attempt.RemoteCallStatus
                candidate.PreviousFailureDetail = attempt.Failure
                candidate.PreviousFailureActivationFailure = attempt.ActivationFailure
                candidate.PreviousFailureDisplacement = attempt.Displacement
            end
        end
        local failedUntil = self.FailedUntil[source.Name] or 0
        if now < failedUntil then
            candidate.Reason = "temporarily skipped after a previous failure"
            candidate.CooldownRemaining = math.max(0, failedUntil - now)
        else
            local available = true
            if source.Requires then
                local checkOk, owned, inventoryError = pcall(
                    compatibility.HasOwnedInventoryItem,
                    compatibility,
                    source.Requires
                )
                available = checkOk and owned == true
                candidate.ItemRequirementOwned = available
                if available then
                    candidate.AccessBy = source.Requires
                elseif source.RequiresTitle then
                    local titleRouteCost = estimateTitleRouteCost(source)
                    local directCost = distance(currentPosition, destination)
                    local titleRouteSavings = directCost - titleRouteCost
                    candidate.TitleRouteCost = titleRouteCost
                    candidate.TitleRouteSavings = titleRouteSavings
                    if titleRouteSavings >= MINIMUM_DISTANCE_SAVED then
                        local titleCheckOk
                        local titleOwned
                        local titleError
                        local titlePending = false
                        local titleCheckIsAsync = false
                        if type(compatibility.BeginUnlockedTitleCheck) == "function" then
                            titleCheckIsAsync = true
                            local beginOk
                            beginOk, titleOwned, titleError, titlePending = pcall(
                                compatibility.BeginUnlockedTitleCheck,
                                compatibility,
                                source.RequiresTitle
                            )
                            titleCheckOk = beginOk
                        else
                            titleCheckOk, titleOwned, titleError = pcall(
                                compatibility.HasUnlockedTitle,
                                compatibility,
                                source.RequiresTitle
                            )
                        end
                        if titleCheckOk and type(titleOwned) == "boolean" then
                            candidate.TitleRequirementOwned = titleOwned
                        end
                        candidate.TitleCheckPending = titleCheckOk
                            and (
                                titleCheckIsAsync
                                    and titlePending == true
                                or not titleCheckIsAsync
                                    and titleOwned == nil
                            )
                        if titleCheckOk and titleOwned == true then
                            available = true
                            candidate.AccessBy = source.RequiresTitle
                        elseif candidate.TitleCheckPending then
                            available = true
                            candidate.ProvisionalTitleAccess = true
                            candidate.Reason = "title access is being checked"
                        else
                            local itemReason = checkOk
                                    and (inventoryError or "required item not found in inventory")
                                or ("inventory check failed: " .. formatScalar(owned))
                            local titleReason = titleCheckOk
                                    and (titleError
                                        or (titleOwned == false
                                            and "title is locked"
                                            or "title state is unknown"))
                                or ("title check failed: " .. formatScalar(titleOwned))
                            candidate.Reason = itemReason .. "; " .. titleReason
                        end
                    else
                        candidate.Reason =
                            "required item not found; title lookup skipped because this gateway is not shorter"
                    end
                else
                    candidate.Reason = checkOk
                            and (inventoryError or "required item not found in inventory")
                        or ("inventory check failed: " .. formatScalar(owned))
                end
            end
            candidate.RequirementOwned =
                available and candidate.ProvisionalTitleAccess ~= true

            local stand = available and self:_ResolveStand(source) or nil
            if available and typeof(stand) ~= "Vector3" then
                available = false
                candidate.Reason = "gateway stand position is not loaded"
            end
            local touchTarget
            if available and source.Touch then
                local touchReason
                touchTarget, touchReason = self:_ResolveTouchTarget(source)
                if touchTarget then
                    candidate.TouchTriggerLoaded = true
                elseif touchReason == "gateway trigger is not loaded" then
                    candidate.TouchTriggerLoaded = false
                    candidate.Reason = "trigger lookup deferred until gateway stand is reached"
                else
                    available = false
                    candidate.Reason = touchReason
                end
            end

            candidate.Eligible = available
            if available then
                candidate.Stand = stand
                candidate.Destination = source.Destination
                if diagnostic and typeof(diagnostic.CurrentPosition) == "Vector3" then
                    candidate.StandDistance = distance(diagnostic.CurrentPosition, stand)
                end
                local route = table.clone(source)
                route.Stand = stand
                route.TouchTarget = touchTarget
                route.ProvisionalTitleAccess =
                    candidate.ProvisionalTitleAccess == true
                table.insert(routes, route)
            end
        end
        table.insert(candidates, candidate)
    end
    return routes
end

function MapGatewayService:HasPendingTitleChecks()
    for _, candidate in ipairs(self.LastDiagnostic and self.LastDiagnostic.Candidates or {}) do
        if candidate.TitleCheckPending then
            return true
        end
    end
    return false
end

function MapGatewayService:GetTitleAccessState(route)
    local titleRoute = route and (
        route.ProvisionalTitleAccess == true and route
            or route.PlanTitleAccessRoute
    )
    if not titleRoute then
        return true, "route access is already confirmed", false
    end
    local compatibility = self.Compatibility
    if not compatibility or type(compatibility.GetUnlockedTitleCheck) ~= "function" then
        return nil, "title access status is unavailable", false
    end
    local ok, state, reason, pending = pcall(
        compatibility.GetUnlockedTitleCheck,
        compatibility,
        titleRoute.RequiresTitle
    )
    if not ok then
        return nil, tostring(state), false
    end
    return state, reason, pending == true
end

function MapGatewayService:ShouldAbortForUnconfirmedTitle(route)
    if not route
        or (route.ProvisionalTitleAccess ~= true and not route.PlanTitleAccessRoute)
    then
        return false
    end
    local state, reason, pending = self:GetTitleAccessState(route)
    if state == true or pending then
        return false
    end
    return true, reason or "title access could not be confirmed"
end

function MapGatewayService:WaitForTitleAccess(route, timeout, isCurrent)
    if not route
        or (route.ProvisionalTitleAccess ~= true and not route.PlanTitleAccessRoute)
    then
        return true
    end
    local deadline = os.clock() + math.max(0, tonumber(timeout) or 0)
    repeat
        if type(isCurrent) == "function" and not isCurrent() then
            return false, "Travel was cancelled"
        end
        local state, reason, pending = self:GetTitleAccessState(route)
        if state == true then
            return true
        end
        if state == false or not pending then
            return false, reason or "title access could not be confirmed"
        end
        if os.clock() >= deadline then
            break
        end
        task.wait(0.05)
    until false
    return false, "title access check timed out"
end

function MapGatewayService:FindPlan(
    destination,
    currentPosition,
    destinationLabel,
    excludedRoutes,
    visitedPositions
)
    excludedRoutes = type(excludedRoutes) == "table" and excludedRoutes or {}
    visitedPositions = type(visitedPositions) == "table" and visitedPositions or {}
    self.LastDiagnostic = {
        At = os.clock(),
        DestinationLabel = destinationLabel,
        Destination = destination,
        CurrentPosition = currentPosition,
        Phase = "checking available gateways",
    }
    local diagnostic = self.LastDiagnostic
    if typeof(destination) ~= "Vector3" or typeof(currentPosition) ~= "Vector3" then
        diagnostic.Phase = "direct travel: positions unavailable"
        diagnostic.Reason = "Travel positions are unavailable"
        return {}, "Travel positions are unavailable"
    end
    local seaIndex = self:_CurrentSeaIndex()
    if not seaIndex then
        diagnostic.Phase = "direct travel: current sea unavailable"
        diagnostic.Reason = "Current sea is unavailable"
        return {}, "Current sea is unavailable"
    end
    diagnostic.Sea = SEA_LABELS[seaIndex]

    local routes = self:_GetAvailableRoutes(seaIndex, currentPosition, destination)
    local function findBest(position, remainingHops, used, visited)
        local bestCost = distance(position, destination)
        local bestPath = {}
        if remainingHops <= 0 then
            return bestCost, bestPath
        end

        for _, route in ipairs(routes) do
            if not used[route.Name]
                and not repeatsGatewayArea(route.Destination, visited)
            then
                used[route.Name] = true
                table.insert(visited, route.Destination)
                local remainingCost, remainingPath =
                    findBest(route.Destination, remainingHops - 1, used, visited)
                table.remove(visited)
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
    local excluded = {}
    for routeName, isExcluded in pairs(excludedRoutes) do
        if isExcluded then
            excluded[routeName] = true
        end
    end
    local visited = { currentPosition }
    for _, position in ipairs(visitedPositions) do
        if typeof(position) == "Vector3" then
            table.insert(visited, position)
        end
    end
    local plannedCost, plan =
        findBest(currentPosition, MAX_ROUTE_HOPS, excluded, visited)
    diagnostic.DirectDistance = directDistance
    diagnostic.PlannedDistance = plannedCost
    diagnostic.DistanceSaved = directDistance - plannedCost
    diagnostic.MinimumDistanceSaved = MINIMUM_DISTANCE_SAVED
    if #plan == 0 or directDistance - plannedCost < MINIMUM_DISTANCE_SAVED then
        diagnostic.Phase = "direct travel: no qualifying gateway route"
        diagnostic.Reason = self:HasPendingTitleChecks()
                and "Title access is still being checked"
            or #plan == 0
                and "No available route produced a shorter path"
            or "Best gateway route saves less than the required distance"
        return {}, nil
    end
    diagnostic.SelectedRoutes = {}
    for _, route in ipairs(plan) do
        table.insert(diagnostic.SelectedRoutes, route.Name)
        if route.ProvisionalTitleAccess == true
            and not plan[1].PlanTitleAccessRoute
        then
            plan[1].PlanTitleAccessRoute = route
        end
    end
    diagnostic.Phase = "gateway route selected"
    return plan, nil
end

function MapGatewayService:RecordTravelPhase(phase, route, details)
    local diagnostic = self.LastDiagnostic
    if not diagnostic then
        return
    end
    diagnostic.Phase = phase
    diagnostic.UpdatedAt = os.clock()
    if route then
        diagnostic.CurrentRoute = route.Name
        diagnostic.Activation = route.Touch and "touch" or "requestEntrance"
        if not diagnostic.LastAttempt or diagnostic.LastAttempt.Route ~= route.Name then
            diagnostic.LastAttempt = {}
        end
        diagnostic.LastAttempt.Route = route.Name
        diagnostic.LastAttempt.Activation = diagnostic.Activation
        diagnostic.LastAttempt.Phase = phase
        diagnostic.LastAttempt.UpdatedAt = os.clock()
    elseif diagnostic.LastAttempt then
        diagnostic.LastAttempt.Phase = phase
        diagnostic.LastAttempt.UpdatedAt = os.clock()
    end
    if type(details) == "table" then
        for key, value in pairs(details) do
            diagnostic[key] = value
            if diagnostic.LastAttempt and key ~= "CurrentPosition" then
                diagnostic.LastAttempt[key] = value
            end
        end
    end
end

function MapGatewayService:MarkFailed(route, reason, cooldown)
    if route and route.Name then
        local now = os.clock()
        local diagnostic = self.LastDiagnostic
        local attempt
        if diagnostic and diagnostic.LastAttempt
            and diagnostic.LastAttempt.Route == route.Name
        then
            attempt = table.clone(diagnostic.LastAttempt)
        end
        self.FailedUntil[route.Name] = now
            + (tonumber(cooldown) or FAILED_ROUTE_COOLDOWN)
        self.LastFailures[route.Name] = {
            At = now,
            Reason = formatScalar(reason or "Gateway attempt failed"),
            Attempt = attempt,
        }
    end
end

function MapGatewayService:MarkApproachFailed(route, reason)
    self:MarkFailed(route, reason, FAILED_APPROACH_COOLDOWN)
end

function MapGatewayService:Use(route, isCurrent)
    local compatibility = self.Compatibility
    local diagnostic = self.LastDiagnostic
    isCurrent = isCurrent or function()
        return true
    end
    if not route or not isCurrent() then
        self:RecordTravelPhase("gateway activation cancelled", route, {
            Failure = "Travel was cancelled",
        })
        return false, "Travel was cancelled"
    end

    local character, _, root = compatibility:GetCharacterParts()
    if not character or not root then
        self:RecordTravelPhase("gateway activation failed", route, {
            Failure = "Character is unavailable",
        })
        return false, "Character is unavailable"
    end

    if typeof(route.Stand) ~= "Vector3" then
        local failure = "Gateway stand position is unavailable"
        self:RecordTravelPhase("gateway stand unavailable", route, {
            Failure = failure,
        })
        return false, failure, "approach"
    end
    local standDistance = distance(root.Position, route.Stand)
    if standDistance > GATEWAY_STAND_ACCEPTANCE then
        local failure = "Character is not close enough to the gateway pad"
        self:RecordTravelPhase("gateway stand not reached", route, {
            DistanceAtStand = standDistance,
            Failure = failure,
        })
        return false, failure, "approach"
    end
    pcall(function()
        if standDistance > GATEWAY_STAND_ALIGNMENT then
            root.CFrame = CFrame.new(route.Stand)
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)

    local activationStartPosition = root.Position
    self:RecordTravelPhase("activating gateway", route, {
        PositionBeforeActivation = root.Position,
        RemoteCallCount = 0,
        RemoteCallStatus = "not started",
        ActivationFailure = nil,
    })
    local remote
    local remoteCallPending = false
    local remoteCallCount = 0
    local lastRemoteCallAt = -math.huge
    local function alignAtStand(currentRoot)
        local offset = distance(currentRoot.Position, route.Stand)
        if offset > GATEWAY_STAND_ALIGNMENT
            and offset <= GATEWAY_ARRIVAL_RADIUS
        then
            currentRoot.CFrame = CFrame.new(route.Stand)
        end
        currentRoot.AssemblyLinearVelocity = Vector3.zero
        currentRoot.AssemblyAngularVelocity = Vector3.zero
    end
    local function invokeEntrance()
        if remoteCallPending or not isCurrent() then
            return
        end
        local currentCharacter, _, currentRoot = compatibility:GetCharacterParts()
        if currentCharacter ~= character or not currentRoot then
            return
        end
        if distance(currentRoot.Position, route.Stand) <= GATEWAY_ARRIVAL_RADIUS then
            pcall(alignAtStand, currentRoot)
        end
        remoteCallPending = true
        remoteCallCount += 1
        lastRemoteCallAt = os.clock()
        if diagnostic and diagnostic.LastAttempt
            and diagnostic.LastAttempt.Route == route.Name
        then
            diagnostic.LastAttempt.RemoteCallCount = remoteCallCount
            diagnostic.LastAttempt.RemoteCallStatus = "in progress"
        end
        task.spawn(function()
            if not isCurrent() then
                remoteCallPending = false
                return
            end
            local ok, result = pcall(function()
                return remote:InvokeServer(
                    "requestEntrance",
                    route.Argument or route.Destination
                )
            end)
            remoteCallPending = false
            if diagnostic and diagnostic.LastAttempt
                and diagnostic.LastAttempt.Route == route.Name
            then
                diagnostic.LastAttempt.RemoteCallStatus = ok
                        and "InvokeServer returned"
                    or "InvokeServer errored"
                diagnostic.LastAttempt.RemoteResultType = type(result)
                if type(result) == "string" or type(result) == "number"
                    or type(result) == "boolean"
                then
                    diagnostic.LastAttempt.RemoteResultSummary = formatScalar(result, 100)
                end
                if ok then
                    diagnostic.LastAttempt.ActivationFailure = nil
                else
                    diagnostic.LastAttempt.ActivationFailure = formatScalar(result)
                end
            end
        end)
    end

    if route.Touch then
        local touchTarget
        local touchResolveError
        local touchLoadAttempts = 0
        local deadline = os.clock() + GATEWAY_TOUCH_LOAD_TIMEOUT
        repeat
            touchLoadAttempts += 1
            touchTarget, touchResolveError = self:_ResolveTouchTarget(route)
            if touchTarget
                or touchResolveError ~= "gateway trigger is not loaded"
                or not isCurrent()
                or os.clock() >= deadline
            then
                break
            end
            task.wait(0.1)
        until false
        if not touchTarget then
            local failure = isCurrent()
                    and (touchResolveError or "gateway trigger did not load at the stand")
                or "Travel was cancelled"
            self:RecordTravelPhase("gateway touch trigger unavailable at stand", route, {
                Failure = failure,
                TouchTriggerStatus = "not loaded",
                TouchTriggerLoadAttempts = touchLoadAttempts,
            })
            return false, failure
        end

        route.TouchTarget = touchTarget
        self:RecordTravelPhase("gateway touch trigger loaded", route, {
            TouchTriggerStatus = "loaded at gateway stand",
            TouchTriggerLoadAttempts = touchLoadAttempts,
        })
        local touchOk, touchError = compatibility:TouchPart(root, touchTarget, isCurrent)
        if diagnostic and diagnostic.LastAttempt then
            diagnostic.LastAttempt.RemoteCallStatus = touchOk
                    and "touch event completed"
                or "touch event failed"
            diagnostic.LastAttempt.TouchTriggerStatus = "loaded at gateway stand"
            diagnostic.LastAttempt.TouchTriggerLoadAttempts = touchLoadAttempts
            if not touchOk then
                diagnostic.LastAttempt.ActivationFailure = touchError
            end
        end
        if not touchOk then
            self:RecordTravelPhase("gateway touch failed", route, {
                Failure = touchError,
            })
            return false, touchError
        end
    else
        local remoteError
        remote, remoteError = compatibility:GetCommF()
        if not remote then
            self:RecordTravelPhase("gateway remote unavailable", route, {
                Failure = remoteError,
                RemoteCallStatus = "not started",
            })
            return false, remoteError
        end
    end

    local deadline = os.clock() + GATEWAY_ACTIVATION_TIMEOUT
    if remote then
        invokeEntrance()
    end
    while isCurrent() and os.clock() < deadline do
        local currentCharacter, _, currentRoot = compatibility:GetCharacterParts()
        if currentCharacter ~= character or not currentRoot then
            self:RecordTravelPhase("character changed during gateway activation", route, {
                PositionAfterActivation = currentRoot and currentRoot.Position or nil,
                Failure = "Character changed during gateway travel",
            })
            return false, "Character changed during gateway travel"
        end
        if diagnostic and diagnostic.LastAttempt
            and diagnostic.LastAttempt.Route == route.Name
        then
            diagnostic.LastAttempt.PositionAfterActivation = currentRoot.Position
            diagnostic.LastAttempt.DistanceAfterActivation =
                distance(currentRoot.Position, route.Destination)
            diagnostic.LastAttempt.ActivationDisplacement = distance(
                activationStartPosition,
                currentRoot.Position
            )
            diagnostic.LastAttempt.Displacement = distance(
                diagnostic.LastAttempt.PositionBeforeActivation or root.Position,
                currentRoot.Position
            )
        end
        local destinationDistance = distance(currentRoot.Position, route.Destination)
        local activationDisplacement = distance(
            activationStartPosition,
            currentRoot.Position
        )
        if destinationDistance <= GATEWAY_ARRIVAL_RADIUS
            and activationDisplacement >= 200
        then
            self.FailedUntil[route.Name] = nil
            self.LastFailures[route.Name] = nil
            self:RecordTravelPhase("gateway arrival confirmed", route, {
                PositionAfterActivation = currentRoot.Position,
                DistanceAfterActivation = destinationDistance,
                ActivationDisplacement = activationDisplacement,
            })
            return true
        end
        if remote and distance(currentRoot.Position, route.Stand) <= GATEWAY_ARRIVAL_RADIUS then
            pcall(alignAtStand, currentRoot)
        end
        if remote and not remoteCallPending
            and os.clock() - lastRemoteCallAt >= REMOTE_RETRY_INTERVAL
        then
            invokeEntrance()
        end
        task.wait(0.1)
    end
    if not isCurrent() then
        self:RecordTravelPhase("gateway activation cancelled", route, {
            Failure = "Travel was cancelled",
        })
        return false, "Travel was cancelled"
    end
    local _, _, finalRoot = compatibility:GetCharacterParts()
    self:RecordTravelPhase("arrival was not confirmed before timeout", route, {
        PositionAfterActivation = finalRoot and finalRoot.Position or nil,
        DistanceAfterActivation = finalRoot
                and distance(finalRoot.Position, route.Destination)
            or nil,
        Failure = "Gateway did not confirm arrival within "
            .. tostring(GATEWAY_ACTIVATION_TIMEOUT)
            .. " seconds",
    })
    return false, "Gateway did not confirm arrival"
end

function MapGatewayService:BuildDiagnosticReport()
    local diagnostic = self.LastDiagnostic
    if type(diagnostic) ~= "table" then
        return nil
    end

    local age = math.max(0, os.clock() - (diagnostic.At or os.clock()))
    if age > 600 then
        return nil
    end
    local lines = {
        "===== [GatewayDiagnostic] REPORT BEGIN =====",
        "Age: " .. string.format("%.2f", age) .. " seconds",
        "Sea: " .. tostring(diagnostic.Sea or "unknown"),
        "Destination: " .. tostring(diagnostic.DestinationLabel or "unknown")
            .. " at " .. formatPosition(diagnostic.Destination),
        "Phase: " .. tostring(diagnostic.Phase or "unknown"),
    }
    if diagnostic.CurrentPosition then
        table.insert(lines, "Start position: " .. formatPosition(diagnostic.CurrentPosition))
    end
    if type(diagnostic.DirectDistance) == "number" then
        table.insert(
            lines,
            "Route distances: direct="
                .. string.format("%.1f", diagnostic.DirectDistance)
                .. "; planned="
                .. string.format("%.1f", diagnostic.PlannedDistance or 0)
                .. "; saved="
                .. string.format("%.1f", diagnostic.DistanceSaved or 0)
                .. "; minimum="
                .. tostring(diagnostic.MinimumDistanceSaved or MINIMUM_DISTANCE_SAVED)
        )
    end
    if diagnostic.Reason then
        table.insert(lines, "Planner reason: " .. formatScalar(diagnostic.Reason))
    end
    if type(diagnostic.SelectedRoutes) == "table" then
        table.insert(
            lines,
            "Selected route(s): "
                .. (#diagnostic.SelectedRoutes > 0
                    and table.concat(diagnostic.SelectedRoutes, " -> ")
                    or "none")
        )
    end

    for _, candidate in ipairs(diagnostic.Candidates or {}) do
        table.insert(
            lines,
            "Candidate "
                .. tostring(candidate.Name)
                .. ": eligible="
                .. tostring(candidate.Eligible)
        .. "; activation="
        .. tostring(candidate.Activation)
                .. "; requirement="
                .. tostring(candidate.Requirement or "none")
                .. "; owned="
                .. (candidate.RequirementOwned == nil
                    and "n/a"
                    or tostring(candidate.RequirementOwned))
                .. (candidate.ItemRequirementOwned ~= nil
                    and ("; item_owned=" .. tostring(candidate.ItemRequirementOwned))
                    or "")
                .. (candidate.FallbackTitle
                    and ("; fallback_title=" .. tostring(candidate.FallbackTitle))
                    or "")
                .. (candidate.TitleCheckPending and "; title_pending=true" or "")
                .. (candidate.FallbackTitle
                    and (
                        "; title_owned="
                            .. (candidate.TitleRequirementOwned == nil
                                and "unknown"
                                or tostring(candidate.TitleRequirementOwned))
                    )
                    or "")
                .. (candidate.AccessBy and ("; access_by=" .. tostring(candidate.AccessBy)) or "")
                .. (candidate.TouchTriggerLoaded ~= nil
                    and ("; trigger_loaded=" .. tostring(candidate.TouchTriggerLoaded))
                    or "")
                .. "; reason="
                .. formatScalar(candidate.Reason or "available")
                .. (type(candidate.StandDistance) == "number"
                    and ("; start_to_pad=" .. string.format("%.1f", candidate.StandDistance))
                    or "")
                .. (type(candidate.TitleRouteSavings) == "number"
                    and ("; title_route_saved="
                        .. string.format("%.1f", candidate.TitleRouteSavings))
                    or "")
                .. (type(candidate.CooldownRemaining) == "number"
                    and ("; cooldown=" .. string.format("%.1f", candidate.CooldownRemaining))
                    or "")
                .. (candidate.PreviousFailure
                    and ("; last_failure=" .. formatScalar(candidate.PreviousFailure))
                    or "")
                .. (candidate.PreviousFailurePhase
                    and ("; last_failure_phase="
                        .. formatScalar(candidate.PreviousFailurePhase))
                    or "")
                .. (candidate.PreviousFailureCallStatus
                    and ("; last_call_status="
                        .. formatScalar(candidate.PreviousFailureCallStatus))
                    or "")
                .. (candidate.PreviousFailureDetail
                    and ("; last_attempt_failure="
                        .. formatScalar(candidate.PreviousFailureDetail))
                    or "")
                .. (candidate.PreviousFailureActivationFailure
                    and ("; last_activation_error="
                        .. formatScalar(candidate.PreviousFailureActivationFailure))
                    or "")
                .. (type(candidate.PreviousFailureDisplacement) == "number"
                    and ("; last_displacement="
                        .. string.format("%.1f", candidate.PreviousFailureDisplacement))
                    or "")
                .. (type(candidate.PreviousFailureAge) == "number"
                    and ("; last_failure_age="
                        .. string.format("%.1f", candidate.PreviousFailureAge))
                    or "")
        )
    end

    local attempt = diagnostic.LastAttempt
    if attempt then
        table.insert(
            lines,
            "Last attempt: route="
                .. tostring(attempt.Route)
                .. "; type="
                .. tostring(attempt.Activation)
                .. "; phase="
                .. tostring(attempt.Phase)
                .. "; call_count="
                .. tostring(attempt.RemoteCallCount or 0)
                .. "; call_status="
                .. tostring(attempt.RemoteCallStatus or "n/a")
                .. (attempt.TouchTriggerStatus
                    and ("; touch_trigger=" .. tostring(attempt.TouchTriggerStatus))
                    or "")
                .. (type(attempt.TouchTriggerLoadAttempts) == "number"
                    and ("; touch_load_attempts=" .. tostring(attempt.TouchTriggerLoadAttempts))
                    or "")
        )
        if attempt.RemoteResultType then
            table.insert(
                lines,
                "Remote result: type="
                    .. tostring(attempt.RemoteResultType)
                    .. "; summary="
                    .. tostring(attempt.RemoteResultSummary or "<not scalar>")
            )
        end
        if attempt.PositionBeforeApproach or attempt.PositionAfterApproach
            or type(attempt.DistanceToStand) == "number"
            or type(attempt.DistanceAtStand) == "number"
        then
            table.insert(
                lines,
                "Approach positions: before="
                    .. formatPosition(attempt.PositionBeforeApproach)
                    .. "; after="
                    .. formatPosition(attempt.PositionAfterApproach)
                    .. "; start_to_pad="
                    .. (type(attempt.DistanceToStand) == "number"
                        and string.format("%.1f", attempt.DistanceToStand)
                        or "n/a")
                    .. "; at_pad_distance="
                    .. (type(attempt.DistanceAtStand) == "number"
                        and string.format("%.1f", attempt.DistanceAtStand)
                        or "n/a")
                    .. "; before_alignment="
                    .. (type(attempt.DistanceBeforeAlignment) == "number"
                        and string.format("%.1f", attempt.DistanceBeforeAlignment)
                        or "n/a")
            )
        end
        if attempt.PositionBeforeActivation then
            table.insert(
                lines,
                "Activation positions: before="
                    .. formatPosition(attempt.PositionBeforeActivation)
                    .. "; after="
                    .. formatPosition(attempt.PositionAfterActivation)
                    .. "; distance_after="
                    .. (type(attempt.DistanceAfterActivation) == "number"
                        and string.format("%.1f", attempt.DistanceAfterActivation)
                        or "n/a")
                    .. "; displacement="
                    .. (type(attempt.Displacement) == "number"
                        and string.format("%.1f", attempt.Displacement)
                        or "n/a")
                    .. "; activation_displacement="
                    .. (type(attempt.ActivationDisplacement) == "number"
                        and string.format("%.1f", attempt.ActivationDisplacement)
                        or "n/a")
            )
        end
        if attempt.Failure then
            table.insert(lines, "Attempt failure: " .. formatScalar(attempt.Failure))
        end
    end

    if diagnostic.Failure then
        table.insert(lines, "Travel note: " .. formatScalar(diagnostic.Failure))
    end
    table.insert(lines, "===== [GatewayDiagnostic] REPORT END =====")
    return table.concat(lines, "\n")
end

return MapGatewayService
