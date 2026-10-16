local MapGatewayService = require(script.Parent.MapGatewayService)

local TeleportFeature = {
    Context = nil,
    MovementService = nil,
    GatewayService = nil,
    ActiveTravel = nil,
    ActiveFarmTravel = nil,
    Generation = 0,
    FarmTravelGeneration = 0,
    LastFarmGatewayPlanCheck = nil,
    CharacterRemovingConnection = nil,
}

local MAX_STALL_RETRIES = 2
local STALL_RETRY_DELAY = 1.1
local MAX_TRAVEL_TIMEOUT = 150
local MAX_GATEWAY_ATTEMPTS = 4
local TITLE_ACCESS_RECHECK_WINDOW = 6
local NPC_DIAGNOSTIC_TARGETS = {
    { Label = "Titles Specialist", Names = { "Titles Specialist" } },
    { Label = "Awakenings Expert", Names = { "Awakenings Expert", "Awakening Expert" } },
    { Label = "Blox Fruits Gacha", Names = { "Blox Fruit Gacha", "Blox Fruits Gacha" } },
}

local function disconnect(connection)
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
    end
end

local function currentSeaIndex(compatibility)
    local checks = {
        { Index = 1, Method = "IsFirstSea" },
        { Index = 2, Method = "IsSecondSea" },
        { Index = 3, Method = "IsThirdSea" },
    }
    local found
    local count = 0
    for _, sea in ipairs(checks) do
        local check = compatibility and compatibility[sea.Method]
        if type(check) == "function" then
            local ok, result = pcall(check, compatibility)
            if ok and result == true then
                found = sea.Index
                count += 1
            end
        end
    end
    return count == 1 and found or nil
end

function TeleportFeature:_SetStatus(message, kind, playerMessage)
    if self.Context and self.Context.State then
        self.Context.State:SetStatus(message, kind or "info", playerMessage)
    end
end

function TeleportFeature:_SetFeatureEnabled(actionId, enabled)
    local state = self.Context and self.Context.State
    if state and actionId then
        state:SetFeatureEnabled(actionId, enabled)
    end
end

function TeleportFeature:IsTraveling()
    return self.ActiveTravel ~= nil
end

function TeleportFeature:_GetSelectedIsland()
    local compatibility = self.Context and self.Context.Compatibility
    local config = self.Context and self.Context.Config
    local seaIndex = currentSeaIndex(compatibility)
    if not seaIndex then
        return nil, "Could not identify the current sea"
    end

    local selected = config and config.TravelSettings and config.TravelSettings.Island
    if type(selected) ~= "string" then
        return nil, "Select an island first"
    end
    for _, destination in ipairs((config.TravelDestinations or {})[seaIndex] or {}) do
        if destination.Name == selected then
            return destination
        end
    end
    return nil, "That island is unavailable in this sea"
end

function TeleportFeature:_FindNpcRoot(name)
    local compatibility = self.Context and self.Context.Compatibility
    local workspace = compatibility and compatibility.Workspace
    local replicatedStorage = compatibility and compatibility.ReplicatedStorage
    local sources = {
        {
            Folder = workspace and workspace:FindFirstChild("NPCs"),
            IsLive = true,
            Priority = 0,
        },
        {
            Folder = replicatedStorage and replicatedStorage:FindFirstChild("NPCs"),
            IsLive = false,
            Priority = 1,
        },
    }

    local _, _, playerRoot = compatibility:GetCharacterParts()
    local selectedRoot
    local selectedPriority = math.huge
    local nearestDistance = math.huge
    for _, source in ipairs(sources) do
        for _, npc in ipairs(source.Folder and source.Folder:GetChildren() or {}) do
            if npc:IsA("Model") and npc.Name == name then
                local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
                local humanoid = source.IsLive and npc:FindFirstChildOfClass("Humanoid")
                local templateInSea = source.IsLive
                    or self.Context.Config.IsTravelNpcPositionInCurrentSea(
                        compatibility,
                        root and root.Position
                    )
                if root and root:IsA("BasePart")
                    and (not humanoid or humanoid.Health > 0)
                    and templateInSea
                then
                    local distance = playerRoot and (root.Position - playerRoot.Position).Magnitude or 0
                    if source.Priority < selectedPriority
                        or source.Priority == selectedPriority and distance < nearestDistance
                    then
                        selectedRoot = root
                        selectedPriority = source.Priority
                        nearestDistance = distance
                    end
                end
            end
        end
    end
    if not selectedRoot and type(compatibility.GetNpcModelsByName) == "function" then
        local models = compatibility:GetNpcModelsByName(name)
        for _, npc in ipairs(type(models) == "table" and models or {}) do
            local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
            local humanoid = npc:IsDescendantOf(workspace)
                and npc:FindFirstChildOfClass("Humanoid")
            local safePosition = root
                and root:IsA("BasePart")
                and self.Context.Config.IsTravelNpcPositionInCurrentSea(
                    compatibility,
                    root.Position
                )
            if safePosition and (not humanoid or humanoid.Health > 0) then
                local distance = playerRoot and (root.Position - playerRoot.Position).Magnitude or 0
                if distance < nearestDistance then
                    selectedRoot = root
                    nearestDistance = distance
                end
            end
        end
    end
    if not selectedRoot then
        return nil, "The selected NPC has no usable live or template position"
    end
    return selectedRoot
end

function TeleportFeature:_GetNpcDestination()
    local compatibility = self.Context and self.Context.Compatibility
    if not currentSeaIndex(compatibility) then
        return nil, "Could not identify the current sea"
    end
    local selected = self.Context.Config.TravelSettings.Npc
    if type(selected) ~= "string" then
        return nil, "Select an NPC first"
    end
    local root, rootError = self:_FindNpcRoot(selected)
    if not root then
        return nil, rootError
    end
    return root.CFrame * CFrame.new(0, 0, -4)
end

function TeleportFeature:_ResolveIslandCFrame(destination)
    if destination.Position then
        if destination.ExactPosition == true then
            return CFrame.new(destination.Position)
        end
        return CFrame.new(destination.Position + Vector3.new(0, 18, 0))
    end
    if destination.LocationName then
        local workspace = self.Context.Compatibility.Workspace
        local worldOrigin = workspace:FindFirstChild("_WorldOrigin")
        local locations = worldOrigin and worldOrigin:FindFirstChild("Locations")
        local location = locations and locations:FindFirstChild(destination.LocationName)
        if location and location:IsA("BasePart") then
            return location.CFrame + Vector3.new(0, 18, 0)
        elseif location and location:IsA("Model") then
            return location:GetPivot() + Vector3.new(0, 18, 0)
        end
        return nil, "The selected location is not currently available"
    end
    return nil, "The selected island has no usable destination"
end

function TeleportFeature:_IsTravelCurrent(request, character)
    local context = self.Context
    local compatibility = context and context.Compatibility
    local mainFarm = context and context.MainFarm
    if request.IsFarmTask == true then
        local isCurrentOk, taskIsCurrent = pcall(request.IsCurrent)
        return self.ActiveFarmTravel == request
            and self.FarmTravelGeneration == request.Generation
            and compatibility
            and compatibility.Player
            and compatibility.Player.Character == character
            and mainFarm
            and mainFarm.Running
            and isCurrentOk
            and taskIsCurrent == true
    end
    return self.ActiveTravel == request
        and self.Generation == request.Generation
        and compatibility
        and compatibility.Player
        and compatibility.Player.Character == character
        and not (mainFarm and mainFarm.Running)
end

function TeleportFeature:_StopMovementSession()
    local movement = self.MovementService
    if movement and type(movement._StopMovement) == "function" then
        movement:_StopMovement()
    end
end

function TeleportFeature:_MoveAndWait(request, character, destination, shouldAbort)
    local compatibility = self.Context.Compatibility
    local _, _, startRoot = compatibility:GetCharacterParts()
    if not startRoot then
        return false, "Character is unavailable"
    end

    local lastStallAt = self.MovementService.LastStallAt
    local routeRequestsBefore = table.clone(self.MovementService.LastRouteRequest or {})
    local startDistance = (destination.Position - startRoot.Position).Magnitude
    local function startMovement()
        return pcall(function()
            return self.MovementService:MoveTo(destination, {
                Speed = 190,
                Threshold = 8,
                IsCurrent = function()
                    return self:_IsTravelCurrent(request, character)
                end,
            })
        end)
    end
    local moveCallOk, moved, moveResult = startMovement()
    if not moveCallOk then
        self:_StopMovementSession()
        return false, tostring(moved)
    end
    if not moved then
        return false, tostring(moveResult)
    end
    if moveResult == "arrived" then
        return true
    end

    local deadline = os.clock()
        + math.max(20, math.min(MAX_TRAVEL_TIMEOUT, startDistance / 120 + 15))
    local stallRetries = 0
    while self:_IsTravelCurrent(request, character) do
        if not self:_IsTravelCurrent(request, character) then
            return false, "Travel was interrupted"
        end
        if type(shouldAbort) == "function" then
            local abortCheckOk, shouldStop, abortReason = pcall(shouldAbort)
            if abortCheckOk and shouldStop == true then
                self:_StopMovementSession()
                return false,
                    tostring(abortReason or "Route access could not be confirmed"),
                    "title_access"
            end
        end
        local currentCharacter, _, currentRoot = compatibility:GetCharacterParts()
        if currentCharacter ~= character or not currentRoot then
            return false, "Character changed during travel"
        end
        local remaining = (destination.Position - currentRoot.Position).Magnitude
        if not self.MovementService.Active then
            if remaining <= 14 then
                return true
            end
            if self.MovementService.LastStallAt ~= lastStallAt then
                stallRetries += 1
                if stallRetries > MAX_STALL_RETRIES then
                    return false,
                        "Movement stalled after "
                            .. tostring(MAX_STALL_RETRIES)
                            .. " waypoint recovery attempts"
                end

                lastStallAt = self.MovementService.LastStallAt
                self:_SetStatus(
                    "Movement stalled; retrying the same waypoint ("
                        .. tostring(stallRetries)
                        .. "/"
                        .. tostring(MAX_STALL_RETRIES)
                        .. ").",
                    "warning"
                )
                task.wait(STALL_RETRY_DELAY)
                if not self:_IsTravelCurrent(request, character) then
                    return false, "Travel was interrupted"
                end

                local retryCallOk, retryMoved, retryResult = startMovement()
                if not retryCallOk then
                    self:_StopMovementSession()
                    return false, tostring(retryMoved)
                end
                if not retryMoved then
                    return false, tostring(retryResult)
                end
                if retryResult == "arrived" then
                    return true
                end
                continue
            end

            local routeTransitionStarted = false
            for routeName, requestedAt in pairs(self.MovementService.LastRouteRequest or {}) do
                if requestedAt > (routeRequestsBefore[routeName] or 0) then
                    routeTransitionStarted = true
                    break
                end
            end
            if routeTransitionStarted then
                local transitionDeadline = os.clock() + 8
                while self:_IsTravelCurrent(request, character)
                    and os.clock() < transitionDeadline
                do
                    local transitionCharacter, _, transitionRoot =
                        compatibility:GetCharacterParts()
                    if transitionCharacter ~= character or not transitionRoot then
                        return false, "Character changed during map transition"
                    end
                    if (destination.Position - transitionRoot.Position).Magnitude <= 14 then
                        return true
                    end
                    if (transitionRoot.Position - startRoot.Position).Magnitude >= 200 then
                        return false, "Map transition completed; continue toward the destination"
                    end
                    task.wait(0.1)
                end
                if not self:_IsTravelCurrent(request, character) then
                    return false, "Travel was interrupted"
                end
                return false, "Map transition did not reach the destination"
            end
            self:_StopMovementSession()
            return false, "Movement stopped before reaching the waypoint"
        end
        if os.clock() >= deadline then
            self:_StopMovementSession()
            return false, "Movement timed out before reaching the waypoint"
        end
        task.wait(0.1)
    end
    return false, "Travel was cancelled"
end

function TeleportFeature:_RunDirectTravel(request, character, waitBeforeRetry, destination, finishRequestOnArrival)
    destination = destination or request.Destination
    local retries = 0
    while self:_IsTravelCurrent(request, character) do
        if waitBeforeRetry or retries > 0 then
            task.wait(STALL_RETRY_DELAY)
            waitBeforeRetry = false
            if not self:_IsTravelCurrent(request, character) then
                return false, "Travel was interrupted"
            end
        end

        local arrived, reason = self:_MoveAndWait(request, character, destination)
        if arrived then
            if self.GatewayService then
                self.GatewayService:RecordTravelPhase(
                    finishRequestOnArrival == false
                        and "special transport staging reached"
                        or "destination reached"
                )
            end
            if finishRequestOnArrival ~= false then
                self:_FinishTravel(request, "Arrived at " .. request.Label .. ".", "success")
            end
            return true
        end
        if not self:_IsTravelCurrent(request, character) then
            return false, reason
        end

        if reason == "Map transition completed; continue toward the destination" then
            request.RouteTransitionRetries = (request.RouteTransitionRetries or 0) + 1
            if request.RouteTransitionRetries > 2 then
                if finishRequestOnArrival == false then
                    return false, "Map gateway transitions did not reach staging"
                end
                self:_FinishTravel(
                    request,
                    "Map gateway transitions did not reach the selected destination.",
                    "warning"
                )
                return false, reason
            end
            self:_SetStatus(
                "Map transition complete; continuing to " .. request.Label .. ".",
                "info"
            )
        else
            retries += 1
            request.StallRetries = retries
            if retries > MAX_STALL_RETRIES then
                if self.GatewayService then
                    self.GatewayService:RecordTravelPhase(
                        "normal travel stopped after gateway fallback",
                        nil,
                        { Failure = reason }
                    )
                end
                if finishRequestOnArrival == false then
                    return false, reason
                end
                self:_FinishTravel(
                    request,
                    "Travel stalled after "
                        .. tostring(MAX_STALL_RETRIES)
                        .. " retries; copy the status report for movement details, then try again.",
                    "warning"
                )
                return false, reason
            end
            self:_SetStatus(
                "Travel stalled; retrying ("
                    .. tostring(retries)
                    .. "/"
                    .. tostring(MAX_STALL_RETRIES)
                    .. ").",
                "warning"
            )
        end
    end
    return false, "Travel was cancelled"
end

function TeleportFeature:_RequestSpecialTransport(request, character, route)
    if not self:_IsTravelCurrent(request, character) then
        return false, "Travel was interrupted"
    end

    local compatibility = self.Context.Compatibility
    local requestOk, requestError = self.MovementService:RequestSpecialTravelRoute(
        route,
        function()
            return self:_IsTravelCurrent(request, character)
        end
    )
    if not requestOk then
        return false, requestError or "Submarine Worker transport could not start"
    end

    local arrivalReference = route and route.ArrivalReference
    local arrivalRadius = tonumber(route and route.ArrivalRadius) or 3000
    local arrivalName = route and route.Name == "Tiki" and "Tiki Outpost" or "Submerged"
    if typeof(arrivalReference) ~= "Vector3" then
        return false, arrivalName .. " arrival reference is unavailable"
    end

    local deadline = os.clock() + 10
    repeat
        if not self:_IsTravelCurrent(request, character) then
            return false, "Travel was interrupted"
        end
        local currentCharacter, _, currentRoot = compatibility:GetCharacterParts()
        if currentCharacter ~= character or not currentRoot then
            return false, "Character changed during Submerged transport"
        end
        if (currentRoot.Position - arrivalReference).Magnitude <= arrivalRadius then
            return true
        end
        task.wait(0.1)
    until os.clock() >= deadline
    return false, arrivalName .. " transport did not confirm arrival"
end

function TeleportFeature:_ApproachGatewayStand(request, character, route)
    local compatibility = self.Context.Compatibility
    local _, _, approachRoot = compatibility:GetCharacterParts()
    self.GatewayService:RecordTravelPhase("approaching gateway stand", route, {
        PositionBeforeApproach = approachRoot and approachRoot.Position or nil,
        DistanceToStand = approachRoot
                and (approachRoot.Position - route.Stand).Magnitude
            or nil,
    })
    self:_SetStatus("Travelling to map gateway: " .. route.Name .. ".", "info")

    local abortIfTitleUnknown
    if route.ProvisionalTitleAccess == true or route.PlanTitleAccessRoute then
        abortIfTitleUnknown = function()
            return self.GatewayService:ShouldAbortForUnconfirmedTitle(route)
        end
    end
    local reached, movementError, movementStage = self:_MoveAndWait(
        request,
        character,
        CFrame.new(route.Stand),
        abortIfTitleUnknown
    )
    if not reached then
        if movementStage == "title_access" then
            return false, movementError, "title_access"
        end
        if not self:_IsTravelCurrent(request, character) then
            return false, movementError
        end
        self.GatewayService:MarkApproachFailed(route, movementError)
        local _, _, failedRoot = compatibility:GetCharacterParts()
        self.GatewayService:RecordTravelPhase(
            "could not reach gateway stand; trying another gateway",
            route,
            {
                PositionAfterApproach = failedRoot and failedRoot.Position or nil,
                Failure = movementError,
            }
        )
        self:_SetStatus(
            "Could not reach " .. route.Name .. "; checking another route.",
            "warning"
        )
        return false, movementError
    end

    self:_StopMovementSession()
    local _, _, gatewayRoot = compatibility:GetCharacterParts()
    local standDistance = gatewayRoot
            and (gatewayRoot.Position - route.Stand).Magnitude
        or math.huge
    if not gatewayRoot or standDistance > 25 then
        local standError = "Could not reach the gateway pad closely enough"
        self.GatewayService:MarkApproachFailed(route, standError)
        self.GatewayService:RecordTravelPhase(
            "gateway stand not reached; checking another gateway",
            route,
            {
                PositionAtStand = gatewayRoot and gatewayRoot.Position or nil,
                DistanceAtStand = standDistance,
                Failure = standError,
            }
        )
        self:_SetStatus(
            route.Name .. " pad was not reached; checking another route.",
            "warning"
        )
        return false, standError
    end

    local positionBeforeAlignment = gatewayRoot.Position
    local aligned, alignmentError = pcall(function()
        gatewayRoot.CFrame = CFrame.new(route.Stand)
        gatewayRoot.AssemblyLinearVelocity = Vector3.zero
        gatewayRoot.AssemblyAngularVelocity = Vector3.zero
    end)
    if not aligned then
        local standError = "Could not align at the gateway pad: "
            .. tostring(alignmentError)
        self.GatewayService:MarkApproachFailed(route, standError)
        self.GatewayService:RecordTravelPhase(
            "gateway stand alignment failed; checking another gateway",
            route,
            {
                PositionAtStand = positionBeforeAlignment,
                DistanceAtStand = standDistance,
                Failure = standError,
            }
        )
        self:_SetStatus(
            route.Name .. " pad alignment failed; checking another route.",
            "warning"
        )
        return false, standError
    end

    self.GatewayService:RecordTravelPhase("at gateway stand; activating", route, {
        PositionAtStand = positionBeforeAlignment,
        DistanceAtStand = (gatewayRoot.Position - route.Stand).Magnitude,
        PositionBeforeAlignment = positionBeforeAlignment,
        DistanceBeforeAlignment = standDistance,
    })
    return true
end

function TeleportFeature:_RunTravel(request, character)
    local compatibility = self.Context.Compatibility
    local gatewayDestination = request.GatewayDestination or request.Destination
    local attemptedRoutes = {}
    local visitedGatewayPositions = {}
    local gatewayAttempts = 0
    local gatewayFailed = false

    local function findPlanFromCurrentPosition()
        if not self.GatewayService then
            return {}
        end
        local _, _, currentRoot = compatibility:GetCharacterParts()
        if not currentRoot then
            return {}
        end

        if not request.RoutePlanConsumed
            and type(request.RoutePlan) == "table"
            and #request.RoutePlan > 0
            and typeof(request.RoutePlanDestination) == "Vector3"
            and typeof(request.RouteStartPosition) == "Vector3"
            and (request.RoutePlanDestination - gatewayDestination.Position).Magnitude <= 200
            and (request.RouteStartPosition - currentRoot.Position).Magnitude <= 200
        then
            request.RoutePlanConsumed = true
            return request.RoutePlan
        end
        request.RoutePlanConsumed = true

        local planOk, resolvedPlan = pcall(
            self.GatewayService.FindPlan,
            self.GatewayService,
            gatewayDestination.Position,
            currentRoot.Position,
            request.GatewayPlanLabel or request.Label,
            attemptedRoutes,
            visitedGatewayPositions
        )
        if not planOk or type(resolvedPlan) ~= "table" then
            self.GatewayService:RecordTravelPhase(
                "gateway planning failed; using normal travel",
                nil,
                { Failure = resolvedPlan }
            )
            return {}
        end

        if #resolvedPlan == 0
            and self.GatewayService:HasPendingTitleChecks()
        then
            local deadline = os.clock() + TITLE_ACCESS_RECHECK_WINDOW
            while os.clock() < deadline do
                task.wait(0.1)
                if not self:_IsTravelCurrent(request, character) then
                    return {}
                end
                local _, _, retryRoot = compatibility:GetCharacterParts()
                if not retryRoot then
                    break
                end
                planOk, resolvedPlan = pcall(
                    self.GatewayService.FindPlan,
                    self.GatewayService,
                    gatewayDestination.Position,
                    retryRoot.Position,
                    request.GatewayPlanLabel or request.Label,
                    attemptedRoutes,
                    visitedGatewayPositions
                )
                if not planOk or type(resolvedPlan) ~= "table"
                    or #resolvedPlan > 0
                    or not self.GatewayService:HasPendingTitleChecks()
                then
                    break
                end
            end
            if not planOk or type(resolvedPlan) ~= "table" then
                return {}
            end
        end
        return resolvedPlan
    end

    if request.SpecialTravelRoute
        and request.SpecialTravelRoute.Name == "Tiki"
    then
        local route = request.SpecialTravelRoute
        local stagingReached, stagingError = self:_RunDirectTravel(
            request,
            character,
            false,
            route.Stage,
            false
        )
        if not stagingReached then
            if self:_IsTravelCurrent(request, character) then
                self:_FinishTravel(
                    request,
                    "Could not reach Submerged exit staging: " .. tostring(stagingError),
                    "warning"
                )
            end
            return
        end

        self:_SetStatus("Leaving Submerged for Tiki Outpost.", "info")
        self.GatewayService:RecordTravelPhase(
            "at Submerged exit staging; requesting Tiki transport"
        )
        local transported, transportError =
            self:_RequestSpecialTransport(request, character, route)
        if not transported then
            if self:_IsTravelCurrent(request, character) then
                self:_FinishTravel(
                    request,
                    "Could not leave Submerged: " .. tostring(transportError),
                    "warning"
                )
            end
            return
        end

        self.GatewayService:RecordTravelPhase(
            "Tiki arrival confirmed; planning gateway route"
        )
        self:_SetStatus("At Tiki Outpost; planning the next route.", "info")
        request.SpecialTravelRoute = nil
        request.GatewayDestination = request.Destination
        request.GatewayPlanLabel = request.Label
        request.RoutePlan = nil
        request.RoutePlanConsumed = true
        gatewayDestination = request.Destination
    end

    -- Take one leg at a time. A second leg planned before teleporting can be
    -- stale by the time the first transition finishes or fails.
    while gatewayAttempts < MAX_GATEWAY_ATTEMPTS do
        if not self:_IsTravelCurrent(request, character) then
            return
        end
        local plan = findPlanFromCurrentPosition()
        local route = plan[1]
        if not route then
            break
        end
        if attemptedRoutes[route.Name] then
            break
        end
        attemptedRoutes[route.Name] = true
        gatewayAttempts += 1

        self:_SetStatus("Using map gateway: " .. route.Name .. ".", "info")
        local reached, approachError, approachStage =
            self:_ApproachGatewayStand(request, character, route)
        if not reached then
            if not self:_IsTravelCurrent(request, character) then
                return
            end
            if approachStage == "title_access" then
                self.GatewayService:RecordTravelPhase(
                    "Tiki title access was not confirmed; using normal travel",
                    route,
                    { Failure = approachError }
                )
                self:_SetStatus(
                    "Tiki access could not be confirmed; continuing without that gateway.",
                    "info"
                )
                request.RoutePlan = nil
                continue
            end
            gatewayFailed = true
            request.RoutePlan = nil
            continue
        end

        local titleAccessOk, titleAccessError =
            self.GatewayService:WaitForTitleAccess(
                route,
                TITLE_ACCESS_RECHECK_WINDOW,
                function()
                    return self:_IsTravelCurrent(request, character)
                end
            )
        if not titleAccessOk then
            if not self:_IsTravelCurrent(request, character) then
                return
            end
            self.GatewayService:RecordTravelPhase(
                "Tiki title access was not confirmed; using normal travel",
                route,
                { Failure = titleAccessError }
            )
            self:_SetStatus(
                "Tiki access could not be confirmed; continuing without that gateway.",
                "info"
            )
            request.RoutePlan = nil
            continue
        end

        self:_SetStatus("Activating map gateway: " .. route.Name .. ".", "info")
        local used, gatewayError, failureStage = self.GatewayService:Use(route, function()
            return self:_IsTravelCurrent(request, character)
        end)
        if not used then
            if not self:_IsTravelCurrent(request, character) then
                return
            end
            if failureStage == "approach" then
                self.GatewayService:MarkApproachFailed(route, gatewayError)
                self.GatewayService:RecordTravelPhase(
                    "gateway stand not reached; checking another gateway",
                    route,
                    { Failure = gatewayError }
                )
                self:_SetStatus(
                    route.Name .. " pad was not reached; checking another route.",
                    "warning"
                )
            else
                self.GatewayService:MarkFailed(route, gatewayError)
                self.GatewayService:RecordTravelPhase(
                    "gateway activation failed; trying another gateway",
                    route,
                    { Failure = gatewayError }
                )
                self:_SetStatus(
                    route.Name .. " did not confirm arrival; checking another route.",
                    "warning"
                )
            end
            gatewayFailed = true
            if gatewayError then
                request.LastGatewayError = tostring(gatewayError)
            end
            request.RoutePlan = nil
            continue
        end
        request.RoutePlan = nil
        self.GatewayService:RecordTravelPhase(
            "gateway arrival confirmed; continuing to destination",
            route
        )
        self:_SetStatus(
            route.Name .. " arrival confirmed; checking the next leg.",
            "info"
        )
        table.insert(visitedGatewayPositions, route.Destination)
    end

    if self:_IsTravelCurrent(request, character) then
        if gatewayAttempts >= MAX_GATEWAY_ATTEMPTS then
            self.GatewayService:RecordTravelPhase(
                "gateway attempt limit reached; continuing by normal travel",
                nil,
                { GatewayAttempts = gatewayAttempts }
            )
        elseif gatewayFailed then
            self.GatewayService:RecordTravelPhase(
                "no more usable gateway routes; continuing by normal travel",
                nil,
                { GatewayAttempts = gatewayAttempts }
            )
        end
        if request.SpecialTravelRoute
            and request.SpecialTravelRoute.Name == "Submerged"
        then
            local stagingReached, stagingError = self:_RunDirectTravel(
                request,
                character,
                false,
                request.GatewayDestination,
                false
            )
            if not stagingReached then
                if self:_IsTravelCurrent(request, character) then
                    self:_FinishTravel(
                        request,
                        "Could not reach Tiki staging for Submerged travel: "
                            .. tostring(stagingError),
                        "warning"
                    )
                end
                return
            end

            self:_SetStatus("At Tiki; entering Submerged.", "info")
            self.GatewayService:RecordTravelPhase(
                "at Tiki staging; requesting Submerged transport"
            )
            local transported, transportError = self:_RequestSpecialTransport(
                request,
                character,
                request.SpecialTravelRoute
            )
            if not transported then
                if self:_IsTravelCurrent(request, character) then
                    self:_FinishTravel(
                        request,
                        "Could not enter Submerged: " .. tostring(transportError),
                        "warning"
                    )
                end
                return
            end
            self.GatewayService:RecordTravelPhase(
                "Submerged arrival confirmed; continuing to destination"
            )
        end
        self:_RunDirectTravel(request, character, false, request.Destination, true)
    end
end

function TeleportFeature:BuildGatewayDiagnosticReport()
    return self.GatewayService
        and self.GatewayService:BuildDiagnosticReport()
        or nil
end

function TeleportFeature:BuildNpcAvailabilityReport()
    local context = self.Context
    local compatibility = context and context.Compatibility
    local config = context and context.Config
    local workspace = compatibility and compatibility.Workspace
    local replicatedStorage = compatibility and compatibility.ReplicatedStorage
    if not compatibility or not workspace or not replicatedStorage then
        return "===== [TravelNpcDiagnostic] REPORT BEGIN =====\nNPC lookup services are unavailable.\n===== [TravelNpcDiagnostic] REPORT END ====="
    end

    local function normalizeName(name)
        local normalized = string.lower(tostring(name or "")):gsub("[^%w]", "")
        return normalized
    end

    local function targetForName(name)
        local normalized = normalizeName(name)
        for _, target in ipairs(NPC_DIAGNOSTIC_TARGETS) do
            for _, alias in ipairs(target.Names) do
                if normalized == normalizeName(alias) then
                    return target
                end
            end
        end
        return nil
    end

    local function pathOf(instance)
        local ok, path = pcall(function()
            return instance:GetFullName()
        end)
        return ok and path or tostring(instance.Name)
    end

    local function positionOf(root)
        if not root or not root:IsA("BasePart") then
            return "none"
        end
        local position = root.Position
        return string.format("(%.1f, %.1f, %.1f)", position.X, position.Y, position.Z)
    end

    local function isTemplatePositionCurrentSea(root)
        if not root or not root:IsA("BasePart")
            or not config
            or type(config.IsTravelNpcPositionInCurrentSea) ~= "function"
        then
            return false
        end
        local ok, result = pcall(
            config.IsTravelNpcPositionInCurrentSea,
            compatibility,
            root.Position
        )
        return ok and result == true
    end

    local function describeModel(model, sourceLabel, isLive, isDirectNpcSource, seenPaths, lines)
        local modelPath = pathOf(model)
        if seenPaths[modelPath] then
            return false
        end
        seenPaths[modelPath] = true
        local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        local validRoot = root and root:IsA("BasePart")
        local humanoid = isLive and model:FindFirstChildOfClass("Humanoid")
        local alive = not humanoid or humanoid.Health > 0
        local templatePositionCurrentSea = isLive or isTemplatePositionCurrentSea(root)
        local selectable = isDirectNpcSource and validRoot and alive and templatePositionCurrentSea
        local reason
        if not isDirectNpcSource then
            reason = "model is outside the direct NPC folders currently searched by travel"
        elseif not validRoot then
            reason = "no direct HumanoidRootPart or PrimaryPart"
        elseif not alive then
            reason = "live NPC is not alive"
        elseif not templatePositionCurrentSea then
            reason = "template root is outside the current-sea travel area"
        else
            reason = "available"
        end
        table.insert(
            lines,
            "  Model: "
                .. modelPath
                .. "; source="
                .. sourceLabel
                .. "; discoverable_by_current_dropdown="
                .. tostring(selectable == true)
                .. "; root="
                .. (validRoot and (root.Name .. " (" .. root.ClassName .. ")") or "none")
                .. "; position="
                .. positionOf(root)
                .. (isLive
                    and "; current_sea_source=live Workspace model"
                    or ("; template_current_sea=" .. tostring(templatePositionCurrentSea)))
                .. (humanoid and ("; health=" .. string.format("%.1f", humanoid.Health)) or "")
                .. "; reason="
                .. reason
        )
        return true
    end

    local liveFolder = workspace:FindFirstChild("NPCs")
    local templateFolder = replicatedStorage:FindFirstChild("NPCs")
    local sourceFolders = {
        { Folder = liveFolder, Label = "Workspace.NPCs", IsLive = true },
        { Folder = templateFolder, Label = "ReplicatedStorage.NPCs", IsLive = false },
    }
    local matches = {}
    local seenPaths = {}
    local lines = {
        "===== [TravelNpcDiagnostic] REPORT BEGIN =====",
        "Sea index: " .. tostring(currentSeaIndex(compatibility) or "unknown"),
        "Scan scope: direct NPC folders, targeted exact-name lookups in Workspace/ReplicatedStorage, and local NPCManager lookup; no remotes invoked",
    }

    for _, target in ipairs(NPC_DIAGNOSTIC_TARGETS) do
        matches[target] = 0
        table.insert(lines, "")
        table.insert(lines, "Target: " .. target.Label)
    end

    for _, source in ipairs(sourceFolders) do
        if source.Folder then
            for _, child in ipairs(source.Folder:GetChildren()) do
                if child:IsA("Model") then
                    local target = targetForName(child.Name)
                    if target then
                        local added = describeModel(
                            child,
                            source.Label,
                            source.IsLive,
                            true,
                            seenPaths,
                            lines
                        )
                        if added then
                            matches[target] += 1
                        end
                    end
                end
            end
        end
    end

    local scanRoots = {
        { Instance = workspace, Label = "Workspace" },
        { Instance = replicatedStorage, Label = "ReplicatedStorage" },
    }
    local seenNamedInstances = {}
    for _, target in ipairs(NPC_DIAGNOSTIC_TARGETS) do
        for _, lookupName in ipairs(target.Names) do
            for _, scanRoot in ipairs(scanRoots) do
                local instance = scanRoot.Instance:FindFirstChild(lookupName, true)
                if instance and not seenNamedInstances[instance] then
                    seenNamedInstances[instance] = true
                    if instance:IsA("Model") then
                        local added = describeModel(
                            instance,
                            scanRoot.Label .. " descendant (outside direct NPC listing unless stated)",
                            instance:IsDescendantOf(workspace),
                            false,
                            seenPaths,
                            lines
                        )
                        if added then
                            matches[target] += 1
                        end
                    else
                        table.insert(
                            lines,
                            scanRoot.Label
                                .. " exact-name instance "
                                .. pathOf(instance)
                                .. " is "
                                .. instance.ClassName
                                .. ", not an NPC Model"
                        )
                    end
                end
            end
        end
    end

    local managerFound = {}
    for _, target in ipairs(NPC_DIAGNOSTIC_TARGETS) do
        local foundManagerModel = false
        for _, lookupName in ipairs(target.Names) do
            local models, lookupError = compatibility:GetNpcModelsByName(lookupName)
            table.insert(
                lines,
                "NPCManager lookup "
                    .. lookupName
                    .. ": "
                    .. (lookupError and ("failed: " .. tostring(lookupError))
                        or (tostring(#models) .. " model(s)"))
            )
            for _, model in ipairs(models) do
                foundManagerModel = true
                local isLive = model:IsDescendantOf(workspace)
                local isDirectNpcSource = model.Parent == liveFolder
                    or model.Parent == templateFolder
                describeModel(
                    model,
                    "NPCManager.getNPCsByName",
                    isLive,
                    isDirectNpcSource,
                    seenPaths,
                    lines
                )
            end
        end
        if not compatibility.GetNpcModelsByName then
            table.insert(
                lines,
                "NPCManager lookup unavailable: Compatibility resolver is missing"
            )
        end
        managerFound[target] = foundManagerModel
    end

    for _, target in ipairs(NPC_DIAGNOSTIC_TARGETS) do
        if matches[target] == 0 and not managerFound[target] then
            table.insert(
                lines,
                "No exact-name model found for "
                    .. target.Label
                    .. " in the scanned folders, descendants, or NPCManager."
            )
        end
    end
    table.insert(lines, "")
    table.insert(lines, "A template position is only reported as evidence; travel still requires a validated current-sea root.")
    table.insert(lines, "===== [TravelNpcDiagnostic] REPORT END =====")
    return table.concat(lines, "\n")
end

function TeleportFeature:_FinishTravel(request, message, kind)
    if request.IsFarmTask == true then
        if self.ActiveFarmTravel ~= request then
            return
        end
        self.ActiveFarmTravel = nil
        self.FarmTravelGeneration += 1
        if self.MovementService then
            self.MovementService:Cancel()
        end
        local statusMessage = "Gateway route finished; farming will continue."
        local statusKind = "info"
        if kind == "warning" or kind == "error" then
            statusMessage = message or statusMessage
            statusKind = kind
        end
        self:_SetStatus(statusMessage, statusKind)
        return
    end
    if self.ActiveTravel ~= request then
        return
    end
    self.ActiveTravel = nil
    self.Generation += 1
    if self.MovementService then
        self.MovementService:Cancel()
        self.MovementService:SetFarmCollisionSuppression(false)
    end
    self:_SetFeatureEnabled(request.Action, false)
    self:_SetStatus(message, kind)
end

function TeleportFeature:Cancel(message, keepActionEnabled)
    local request = self.ActiveTravel
    if not request then
        return false
    end
    self.ActiveTravel = nil
    self.Generation += 1
    if self.MovementService then
        self.MovementService:Cancel()
        self.MovementService:SetFarmCollisionSuppression(false)
    end
    if not keepActionEnabled then
        self:_SetFeatureEnabled(request.Action, false)
    end
    if message then
        self:_SetStatus(message, "warning")
    elseif keepActionEnabled then
        self:_SetStatus("Updating travel destination.", "info")
    else
        self:_SetStatus("Travel cancelled.", "info")
    end
    return true
end

function TeleportFeature:CancelFarmTravel(skipMovementCancel)
    if not self.ActiveFarmTravel then
        return false
    end
    self.ActiveFarmTravel = nil
    self.FarmTravelGeneration += 1
    self.LastFarmGatewayPlanCheck = nil
    if self.MovementService and not skipMovementCancel then
        self.MovementService:Cancel()
    end
    return true
end

function TeleportFeature:MoveFarmTo(destination, options)
    options = options or {}
    if typeof(destination) ~= "CFrame"
        or not self.GatewayService
        or not self.MovementService
    then
        return false, "Gateway-aware farm travel is unavailable"
    end
    local isCurrent = options.IsCurrent or function()
        return true
    end
    if not isCurrent() then
        self:CancelFarmTravel()
        return false, "Farm movement is no longer current"
    end

    local character, _, root = self.Context.Compatibility:GetCharacterParts()
    if not character or not root then
        return false, "Character is unavailable"
    end

    local active = self.ActiveFarmTravel
    if active and self:_IsTravelCurrent(active, active.Character) then
        local shift = (active.Destination.Position - destination.Position).Magnitude
        if shift <= 500 then
            active.Destination = destination
            active.Label = options.Label or active.Label
            return true, "gateway route in progress"
        end
        self:CancelFarmTravel()
    elseif active then
        self:CancelFarmTravel()
    end

    local specialRoute = self.MovementService:GetSpecialTravelRoute(
        destination,
        root.Position
    )
    local gatewayDestination = destination
    local specialTravelRoute
    local outboundTiki = specialRoute and specialRoute.Name == "Tiki"
    if specialRoute
        and (specialRoute.Name == "Submerged" or specialRoute.Name == "Tiki")
    then
        gatewayDestination = specialRoute.Stage
        specialTravelRoute = specialRoute
    end
    local gatewayPlanLabel
    if specialTravelRoute and specialTravelRoute.Name == "Submerged" then
        gatewayPlanLabel = "Tiki staging for Submerged"
    elseif outboundTiki then
        gatewayPlanLabel = "Submerged exit staging"
    else
        gatewayPlanLabel = options.Label or "Farm target"
    end
    local directDistance = (gatewayDestination.Position - root.Position).Magnitude
    if directDistance <= 1500 and not outboundTiki then
        self.LastFarmGatewayPlanCheck = nil
        return false, "No long-distance gateway route needed"
    end

    local now = os.clock()
    local cached = self.LastFarmGatewayPlanCheck
    if not outboundTiki
        and cached
        and now - cached.At < 0.75
        and cached.RouteDestination
        and (cached.RouteDestination - gatewayDestination.Position).Magnitude <= 200
    then
        return false, cached.Error or "No qualifying gateway route"
    end

    local planOk, routePlan = true, {}
    if not outboundTiki then
        planOk, routePlan = pcall(
            self.GatewayService.FindPlan,
            self.GatewayService,
            gatewayDestination.Position,
            root.Position,
            gatewayPlanLabel
        )
    end
    if not planOk
        or type(routePlan) ~= "table"
        or (#routePlan == 0 and not outboundTiki)
    then
        self.LastFarmGatewayPlanCheck = {
            At = now,
            Destination = destination.Position,
            RouteDestination = gatewayDestination.Position,
            Error = planOk and "No qualifying gateway route" or tostring(routePlan),
        }
        return false, self.LastFarmGatewayPlanCheck.Error
    end

    self.FarmTravelGeneration += 1
    local request = {
        IsFarmTask = true,
        Generation = self.FarmTravelGeneration,
        Character = character,
        StartedAt = now,
        Label = options.Label or "Farm target",
        Destination = destination,
        GatewayDestination = gatewayDestination,
        GatewayPlanLabel = gatewayPlanLabel,
        SpecialTravelRoute = specialTravelRoute,
        RoutePlan = routePlan,
        RouteStartPosition = root.Position,
        RoutePlanDestination = gatewayDestination.Position,
        IsCurrent = isCurrent,
        Speed = tonumber(options.Speed) or 190,
        Threshold = tonumber(options.Threshold) or 8,
        KeepSession = options.KeepSession == true,
        StallRetries = 0,
    }
    self.ActiveFarmTravel = request
    self.LastFarmGatewayPlanCheck = nil
    if outboundTiki then
        self:_SetStatus(
            "Leaving Submerged through Tiki before continuing to " .. request.Label .. ".",
            "info"
        )
    else
        self:_SetStatus("Using a shorter gateway route to " .. request.Label .. ".", "info")
    end
    task.spawn(function()
        local runOk, runError = pcall(self._RunTravel, self, request, character)
        if not runOk and self.ActiveFarmTravel == request then
            self:_FinishTravel(
                request,
                "Gateway route failed; farming will retry normal travel: " .. tostring(runError),
                "warning"
            )
        end
    end)
    return true, "gateway route selected"
end

function TeleportFeature:EstimateFarmTravelDistance(currentPosition, destinationPosition)
    if typeof(currentPosition) ~= "Vector3"
        or typeof(destinationPosition) ~= "Vector3"
    then
        return nil, "Travel positions are unavailable"
    end

    local destination = CFrame.new(destinationPosition)
    local specialRoute = self.MovementService
        and self.MovementService:GetSpecialTravelRoute(destination, currentPosition)
    if specialRoute then
        local stagePosition = specialRoute.Stage and specialRoute.Stage.Position
        local arrivalReference = specialRoute.ArrivalReference
        if typeof(stagePosition) ~= "Vector3" then
            return (destinationPosition - currentPosition).Magnitude
        end

        local approachDistance
        if specialRoute.Name == "Tiki" then
            approachDistance = (stagePosition - currentPosition).Magnitude
        elseif self.GatewayService then
            approachDistance = self.GatewayService:EstimateTravelDistance(
                stagePosition,
                currentPosition
            )
        else
            approachDistance = (stagePosition - currentPosition).Magnitude
        end
        local finalDistance = typeof(arrivalReference) == "Vector3"
                and (destinationPosition - arrivalReference).Magnitude
            or 0
        return approachDistance + finalDistance
    end

    if self.GatewayService then
        return self.GatewayService:EstimateTravelDistance(
            destinationPosition,
            currentPosition
        )
    end
    return (destinationPosition - currentPosition).Magnitude
end

function TeleportFeature:_StartTravel(destination, destinationLabel, actionId)
    local context = self.Context
    local compatibility = context and context.Compatibility
    local mainFarm = context and context.MainFarm
    if mainFarm and mainFarm.Running then
        self:_SetFeatureEnabled(actionId, false)
        local stackSettings = context.Config and context.Config.StackFarmSettings or {}
        local stackActive = stackSettings.AutoAttackCakePrince == true
            or stackSettings.AutoEliteHunter == true
            or stackSettings.TeleportToFruit == true
            or stackSettings.AutoCollectBerries == true
        if mainFarm.MainFarmEnabled then
            self:_SetStatus(
                "Travel unavailable while Main Farming is active.",
                "error",
                "Turn off Start Farm first. Travel and farming can't run together."
            )
        elseif stackActive then
            self:_SetStatus(
                "Travel unavailable while Stack Farming is active.",
                "error",
                "Turn off the active Stack Farming task before starting Travel."
            )
        else
            self:_SetStatus(
                "Travel unavailable while farming is active.",
                "error",
                "Stop the active farming task before starting Travel."
            )
        end
        return false, "Auto Farm is running"
    end
    if self.ActiveTravel then
        if self.ActiveTravel.Action == actionId then
            return true
        end
        self:_SetFeatureEnabled(actionId, false)
        self:_SetStatus(
            "Travel unavailable: another trip is already active.",
            "error",
            "Turn off the current travel switch before starting a different trip."
        )
        return false, "Another trip is active"
    end
    local character, humanoid, root = compatibility:GetCharacterParts()
    if not character or not humanoid or not root then
        self:_SetFeatureEnabled(actionId, false)
        self:_SetStatus("Travel unavailable: character is not ready.", "error")
        return false, "Character is unavailable"
    end

    local collisionCallOk, collisionReady, collisionError = pcall(function()
        return self.MovementService:SetFarmCollisionSuppression(true)
    end)
    if not collisionCallOk then
        collisionError = collisionReady
        collisionReady = false
    end
    if not collisionReady then
        self:_SetFeatureEnabled(actionId, false)
        self:_SetStatus("Travel collision setup failed: " .. tostring(collisionError), "error")
        return false, collisionError
    end

    local specialRoute = self.MovementService:GetSpecialTravelRoute(
        destination,
        root.Position
    )
    local gatewayDestination = destination
    local gatewayPlanLabel = destinationLabel
    if specialRoute and specialRoute.Name == "Tiki" then
        gatewayDestination = specialRoute.Stage
        gatewayPlanLabel = "Submerged exit staging"
    else
        specialRoute = nil
    end

    self.Generation += 1
    local request = {
        Generation = self.Generation,
        Character = character,
        StartedAt = os.clock(),
        Label = destinationLabel,
        Action = actionId,
        Destination = destination,
        GatewayDestination = gatewayDestination,
        GatewayPlanLabel = gatewayPlanLabel,
        SpecialTravelRoute = specialRoute,
        StallRetries = 0,
    }
    self.ActiveTravel = request
    self:_SetFeatureEnabled(actionId, true)

    self:_SetStatus("Travelling to " .. destinationLabel .. ".", "info")
    task.spawn(function()
        local runOk, runError = pcall(self._RunTravel, self, request, character)
        if not runOk and self.ActiveTravel == request then
            self:_FinishTravel(
                request,
                "Travel could not continue: " .. tostring(runError),
                "error"
            )
        end
    end)
    return true
end

function TeleportFeature:_SelectSetting(setting, value, validOptions)
    if type(value) ~= "string" then
        self:_SetStatus("Travel selection must be a destination name.", "error")
        return false, "Invalid selection"
    end
    for _, option in ipairs(validOptions) do
        if option == value then
            self.Context.Config.TravelSettings[setting] = value
            self:_SetStatus("Selected " .. value .. ".", "success")
            return true
        end
    end
    self:_SetStatus("That destination is not available in the current sea.", "warning")
    return false, "Destination is unavailable"
end

function TeleportFeature:_RetargetActiveIslandTravel()
    local request = self.ActiveTravel
    if not request or request.Action ~= "teleport.island" then
        return false
    end

    local island, islandError = self:_GetSelectedIsland()
    if not island then
        self:Cancel(
            "Island travel stopped: "
                .. tostring(islandError or "the selected destination is unavailable")
                .. "."
        )
        return false
    end
    if request.Label == island.Name then
        return true
    end

    local destination, destinationError = self:_ResolveIslandCFrame(island)
    if not destination then
        self:Cancel(
            "Island travel stopped: "
                .. tostring(destinationError or "the selected destination is unavailable")
                .. "."
        )
        return false
    end

    self:Cancel(nil, true)
    return self:_StartTravel(destination, island.Name, request.Action)
end

function TeleportFeature:Handle(actionId, payload)
    local config = self.Context and self.Context.Config
    if actionId == "teleport.npc.report" then
        local report = self:BuildNpcAvailabilityReport()
        local copied = false
        local clipboardOk = pcall(function()
            if type(setclipboard) == "function" then
                setclipboard(report)
                copied = true
            end
        end)
        if clipboardOk and copied then
            self:_SetStatus("NPC availability report copied.", "success")
        else
            print(report)
            self:_SetStatus("Clipboard unavailable; NPC report printed to output.", "warning")
        end
        return true
    elseif actionId == "teleport.island.select" then
        local compatibility = self.Context.Compatibility
        local seaIndex = currentSeaIndex(compatibility)
        local options = {}
        for _, destination in ipairs(
            seaIndex and (config.TravelDestinations[seaIndex] or {}) or {}
        ) do
            table.insert(options, destination.Name)
        end
        local selected = self:_SelectSetting("Island", payload, options)
        if selected then
            self:_RetargetActiveIslandTravel()
        end
        return true
    elseif actionId == "teleport.npc.select" then
        local compatibility = self.Context.Compatibility
        local options = type(config.TravelNpcsForCurrentSea) == "function"
            and config.TravelNpcsForCurrentSea(compatibility)
            or {}
        self:_SelectSetting("Npc", payload, options)
        return true
    elseif actionId == "teleport.island" or actionId == "teleport.npc" then
        if payload ~= true then
            if self.ActiveTravel and self.ActiveTravel.Action == actionId then
                self:Cancel()
            else
                self:_SetFeatureEnabled(actionId, false)
            end
            return true
        end

        local destinationLabel
        local destination
        local destinationError
        if actionId == "teleport.island" then
            local island
            island, destinationError = self:_GetSelectedIsland()
            if island then
                destinationLabel = island.Name
                destination, destinationError = self:_ResolveIslandCFrame(island)
            end
        else
            destination, destinationError = self:_GetNpcDestination()
            destinationLabel = "NPC " .. tostring(config.TravelSettings.Npc)
        end
        if not destination then
            self:_SetFeatureEnabled(actionId, false)
            self:_SetStatus(tostring(destinationError or "Travel target is unavailable") .. ".", "warning")
            return true
        end
        self:_StartTravel(destination, destinationLabel, actionId)
        return true
    end
    return false
end

function TeleportFeature:Initialize(context)
    self:Cleanup()
    self.Context = context
    self.Generation = 0
    self.FarmTravelGeneration = 0
    self.ActiveTravel = nil
    self.ActiveFarmTravel = nil
    self.LastFarmGatewayPlanCheck = nil
    self.MovementService = context.MovementService
    self.GatewayService = MapGatewayService.new(context.Compatibility)
    if self.MovementService then
        self.MovementService.OnCancel = function()
            self:CancelFarmTravel(true)
        end
    end

    local player = context.Compatibility.Player
    if player then
        self.CharacterRemovingConnection = player.CharacterRemoving:Connect(function()
            self:CancelFarmTravel()
            self:Cancel("Travel cancelled because the character is resetting.")
        end)
    end
    return true
end

function TeleportFeature:Cleanup()
    self:CancelFarmTravel()
    self:Cancel("Travel cancelled during hub cleanup.")
    if self.MovementService then
        self.MovementService.OnCancel = nil
    end
    disconnect(self.CharacterRemovingConnection)
    self.CharacterRemovingConnection = nil
    self.Context = nil
    self.MovementService = nil
    self.GatewayService = nil
end

return TeleportFeature
