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
local TITLE_ACCESS_RECHECK_WINDOW = 1
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

function TeleportFeature:_MoveAndWait(request, character, destination)
    local compatibility = self.Context.Compatibility
    local _, _, startRoot = compatibility:GetCharacterParts()
    if not startRoot then
        return false, "Character is unavailable"
    end

    local lastStallAt = self.MovementService.LastStallAt
    local routeRequestsBefore = table.clone(self.MovementService.LastRouteRequest or {})
    local startDistance = (destination.Position - startRoot.Position).Magnitude
    local moveCallOk, moved, moveResult = pcall(function()
        return self.MovementService:MoveTo(destination, {
            Speed = 190,
            Threshold = 8,
            IsCurrent = function()
                return self:_IsTravelCurrent(request, character)
            end,
        })
    end)
    if not moveCallOk then
        self.MovementService:Cancel()
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
    while self:_IsTravelCurrent(request, character) do
        if not self:_IsTravelCurrent(request, character) then
            return false, "Travel was interrupted"
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
            if self.MovementService.LastStallAt ~= lastStallAt then
                return false, "Movement stalled before reaching the waypoint"
            end
            return false, "Movement stopped before reaching the waypoint"
        end
        if os.clock() >= deadline then
            self.MovementService:Cancel()
            return false, "Movement timed out before reaching the waypoint"
        end
        task.wait(0.1)
    end
    return false, "Travel was cancelled"
end

function TeleportFeature:_RunDirectTravel(request, character, waitBeforeRetry)
    local retries = 0
    while self:_IsTravelCurrent(request, character) do
        if waitBeforeRetry or retries > 0 then
            task.wait(STALL_RETRY_DELAY)
            waitBeforeRetry = false
            if not self:_IsTravelCurrent(request, character) then
                return
            end
        end

        local arrived, reason = self:_MoveAndWait(request, character, request.Destination)
        if arrived then
            if self.GatewayService then
                self.GatewayService:RecordTravelPhase("destination reached")
            end
            self:_FinishTravel(request, "Arrived at " .. request.Label .. ".", "success")
            return
        end
        if not self:_IsTravelCurrent(request, character) then
            return
        end

        if reason == "Map transition completed; continue toward the destination" then
            request.RouteTransitionRetries = (request.RouteTransitionRetries or 0) + 1
            if request.RouteTransitionRetries > 2 then
                self:_FinishTravel(
                    request,
                    "Map gateway transitions did not reach the selected destination.",
                    "warning"
                )
                return
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
                self:_FinishTravel(
                    request,
                    "Travel stalled after "
                        .. tostring(MAX_STALL_RETRIES)
                        .. " retries; copy the status report for movement details, then try again.",
                    "warning"
                )
                return
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
end

function TeleportFeature:_RunTravel(request, character)
    local compatibility = self.Context.Compatibility
    local _, _, root = compatibility:GetCharacterParts()
    local plan = request.RoutePlan or {}
    if not request.RoutePlan and root and self.GatewayService then
        local planOk, resolvedPlan = pcall(
            self.GatewayService.FindPlan,
            self.GatewayService,
            request.Destination.Position,
            root.Position,
            request.Label
        )
        if planOk and type(resolvedPlan) == "table" then
            plan = resolvedPlan
        elseif not planOk then
            self.GatewayService:RecordTravelPhase(
                "gateway planning failed; using normal travel",
                nil,
                { Failure = resolvedPlan }
            )
        end
        if planOk and type(resolvedPlan) == "table"
            and #resolvedPlan == 0
            and self.GatewayService:HasPendingTitleChecks()
        then
            local deadline = os.clock() + TITLE_ACCESS_RECHECK_WINDOW
            while os.clock() < deadline do
                task.wait(0.1)
                if not self:_IsTravelCurrent(request, character) then
                    return
                end
                local _, _, retryRoot = compatibility:GetCharacterParts()
                if not retryRoot then
                    break
                end
                planOk, resolvedPlan = pcall(
                    self.GatewayService.FindPlan,
                    self.GatewayService,
                    request.Destination.Position,
                    retryRoot.Position,
                    request.Label
                )
                if not planOk or type(resolvedPlan) ~= "table"
                    or #resolvedPlan > 0
                    or not self.GatewayService:HasPendingTitleChecks()
                then
                    break
                end
            end
            if planOk and type(resolvedPlan) == "table" then
                plan = resolvedPlan
            end
        end
    end
    if #plan > 0 then
        local routeNames = {}
        for _, route in ipairs(plan) do
            table.insert(routeNames, route.Name)
        end
        self:_SetStatus(
            "Using map gateway route: " .. table.concat(routeNames, " → ") .. ".",
            "info"
        )
    elseif self.GatewayService then
        self.GatewayService:RecordTravelPhase(
            "using normal travel: no qualifying map gateway route"
        )
    end

    local gatewayFailed = false
    for _, route in ipairs(plan) do
        if not self:_IsTravelCurrent(request, character) then
            return
        end
        local _, _, approachRoot = compatibility:GetCharacterParts()
        self.GatewayService:RecordTravelPhase("approaching gateway stand", route, {
            PositionBeforeApproach = approachRoot and approachRoot.Position or nil,
            DistanceToStand = approachRoot
                    and (approachRoot.Position - route.Stand).Magnitude
                or nil,
        })
        self:_SetStatus("Travelling to map gateway: " .. route.Name .. ".", "info")
        local reached, movementError = self:_MoveAndWait(
            request,
            character,
            CFrame.new(route.Stand)
        )
        if not reached then
            if not self:_IsTravelCurrent(request, character) then
                return
            end
            self.GatewayService:MarkApproachFailed(route, movementError)
            local _, _, failedRoot = compatibility:GetCharacterParts()
            self.GatewayService:RecordTravelPhase(
                "could not reach gateway stand; falling back to normal travel",
                route,
                {
                    PositionAfterApproach = failedRoot and failedRoot.Position or nil,
                    Failure = movementError,
                }
            )
            self:_SetStatus(
                "Could not reach " .. route.Name .. "; continuing by normal travel.",
                "warning"
            )
            gatewayFailed = true
            break
        end

        local _, _, gatewayRoot = compatibility:GetCharacterParts()
        self.GatewayService:RecordTravelPhase("at gateway stand; activating", route, {
            PositionAtStand = gatewayRoot and gatewayRoot.Position or nil,
            DistanceAtStand = gatewayRoot
                    and (gatewayRoot.Position - route.Stand).Magnitude
                or nil,
        })
        self:_SetStatus("Activating map gateway: " .. route.Name .. ".", "info")
        local used, gatewayError = self.GatewayService:Use(route, function()
            return self:_IsTravelCurrent(request, character)
        end)
        if not used then
            if not self:_IsTravelCurrent(request, character) then
                return
            end
            self.GatewayService:MarkFailed(route, gatewayError)
            self.GatewayService:RecordTravelPhase(
                "gateway activation failed; falling back to normal travel",
                route,
                { Failure = gatewayError }
            )
            self:_SetStatus(
                route.Name .. " did not confirm arrival; continuing by normal travel.",
                "warning"
            )
            gatewayFailed = true
            if gatewayError then
                request.LastGatewayError = tostring(gatewayError)
            end
            break
        end
        self.GatewayService:RecordTravelPhase(
            "gateway arrival confirmed; continuing to destination",
            route
        )
        self:_SetStatus(
            route.Name .. " arrival confirmed; continuing to " .. request.Label .. ".",
            "info"
        )
    end

    if self:_IsTravelCurrent(request, character) then
        self:_RunDirectTravel(request, character, gatewayFailed)
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
        self:_SetStatus("Gateway route finished; farming will continue.", "info")
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

    local directDistance = (destination.Position - root.Position).Magnitude
    if directDistance <= 1500 then
        self.LastFarmGatewayPlanCheck = nil
        return false, "No long-distance gateway route needed"
    end

    local now = os.clock()
    local cached = self.LastFarmGatewayPlanCheck
    if cached
        and now - cached.At < 0.75
        and (cached.Destination - destination.Position).Magnitude <= 200
    then
        return false, cached.Error or "No qualifying gateway route"
    end

    local planOk, routePlan = pcall(
        self.GatewayService.FindPlan,
        self.GatewayService,
        destination.Position,
        root.Position,
        options.Label or "Farm target"
    )
    if not planOk or type(routePlan) ~= "table" or #routePlan == 0 then
        self.LastFarmGatewayPlanCheck = {
            At = now,
            Destination = destination.Position,
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
        RoutePlan = routePlan,
        IsCurrent = isCurrent,
        Speed = tonumber(options.Speed) or 190,
        Threshold = tonumber(options.Threshold) or 8,
        KeepSession = options.KeepSession == true,
        StallRetries = 0,
    }
    self.ActiveFarmTravel = request
    self.LastFarmGatewayPlanCheck = nil
    self:_SetStatus("Using a shorter gateway route to " .. request.Label .. ".", "info")
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

function TeleportFeature:_StartTravel(destination, destinationLabel, actionId)
    local context = self.Context
    local compatibility = context and context.Compatibility
    local mainFarm = context and context.MainFarm
    if mainFarm and mainFarm.Running then
        self:_SetFeatureEnabled(actionId, false)
        self:_SetStatus(
            "Travel unavailable while farming is active.",
            "error",
            "Turn off Start Farm first. Travel and farming can't run together."
        )
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

    self.Generation += 1
    local request = {
        Generation = self.Generation,
        Character = character,
        StartedAt = os.clock(),
        Label = destinationLabel,
        Action = actionId,
        Destination = destination,
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
