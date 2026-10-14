local MapGatewayService = {}
MapGatewayService.__index = MapGatewayService

local MINIMUM_DISTANCE_SAVED = 1500
local MAX_ROUTE_HOPS = 4
local FAILED_ROUTE_COOLDOWN = 120
local GATEWAY_ACTIVATION_TIMEOUT = 8
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
    local map = mapRoot and mapRoot:FindFirstChild(route.Map or "Boat Castle")
    local trigger = map and map:FindFirstChild(route.Touch)
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
    local hitbox = trigger:FindFirstChild("Hitbox")
    if not hitbox or not hitbox:IsA("BasePart") then
        return nil, "gateway trigger Hitbox is missing or not a BasePart"
    end
    return hitbox, nil
end

function MapGatewayService:_GetAvailableRoutes(seaIndex)
    local compatibility = self.Compatibility
    local now = os.clock()
    local routes = {}
    local candidates = {}
    local diagnostic = self.LastDiagnostic
    if diagnostic then
        diagnostic.Candidates = candidates
    end
    for _, source in ipairs(ROUTES_BY_SEA[seaIndex] or {}) do
        local candidate = {
            Name = source.Name,
            Requirement = source.Requires,
            Activation = source.Touch and "touch" or "requestEntrance",
            Eligible = false,
        }
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
                candidate.RequirementOwned = available
                if not available then
                    candidate.Reason = checkOk
                            and (inventoryError or "required item not found in inventory")
                        or ("inventory check failed: " .. formatScalar(owned))
                end
            end

            local stand = available and self:_ResolveStand(source) or nil
            if available and typeof(stand) ~= "Vector3" then
                available = false
                candidate.Reason = "gateway stand position is not loaded"
            end
            local touchTarget
            if available and source.Touch then
                local touchReason
                touchTarget, touchReason = self:_ResolveTouchTarget(source)
                available = touchTarget ~= nil
                if not available then
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
                table.insert(routes, route)
            end
        end
        table.insert(candidates, candidate)
    end
    return routes
end

function MapGatewayService:FindPlan(destination, currentPosition, destinationLabel)
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
    diagnostic.DirectDistance = directDistance
    diagnostic.PlannedDistance = plannedCost
    diagnostic.DistanceSaved = directDistance - plannedCost
    diagnostic.MinimumDistanceSaved = MINIMUM_DISTANCE_SAVED
    if #plan == 0 or directDistance - plannedCost < MINIMUM_DISTANCE_SAVED then
        diagnostic.Phase = "direct travel: no qualifying gateway route"
        diagnostic.Reason = #plan == 0
                and "No available route produced a shorter path"
            or "Best gateway route saves less than the required distance"
        return {}, nil
    end
    diagnostic.SelectedRoutes = {}
    for _, route in ipairs(plan) do
        table.insert(diagnostic.SelectedRoutes, route.Name)
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
        diagnostic.Activation = route.TouchTarget and "touch" or "requestEntrance"
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

function MapGatewayService:MarkFailed(route)
    if route and route.Name then
        self.FailedUntil[route.Name] = os.clock() + FAILED_ROUTE_COOLDOWN
    end
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
    local function invokeEntrance()
        if remoteCallPending or not isCurrent() then
            return
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

    if route.TouchTarget then
        local touchOk, touchError = compatibility:TouchPart(
            root,
            route.TouchTarget,
            isCurrent
        )
        if diagnostic and diagnostic.LastAttempt then
            diagnostic.LastAttempt.RemoteCallStatus = touchOk
                    and "touch event completed"
                or "touch event failed"
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
            diagnostic.LastAttempt.Displacement = distance(
                diagnostic.LastAttempt.PositionBeforeActivation or root.Position,
                currentRoot.Position
            )
        end
        if distance(currentRoot.Position, route.Destination) <= 200 then
            self.FailedUntil[route.Name] = nil
            self:RecordTravelPhase("gateway arrival confirmed", route, {
                PositionAfterActivation = currentRoot.Position,
                DistanceAfterActivation = distance(currentRoot.Position, route.Destination),
            })
            return true
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
    self:MarkFailed(route)
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
                .. "; reason="
                .. formatScalar(candidate.Reason or "available")
                .. (type(candidate.StandDistance) == "number"
                    and ("; start_to_pad=" .. string.format("%.1f", candidate.StandDistance))
                    or "")
                .. (type(candidate.CooldownRemaining) == "number"
                    and ("; cooldown=" .. string.format("%.1f", candidate.CooldownRemaining))
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
