local TeleportFeature = {
    Context = nil,
    MovementService = nil,
    ActiveTravel = nil,
    Generation = 0,
    CharacterRemovingConnection = nil,
}

local MAX_STALL_RETRIES = 2
local STALL_RETRY_DELAY = 1.1

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

function TeleportFeature:_SetStatus(message, kind)
    if self.Context and self.Context.State then
        self.Context.State:SetStatus(message, kind or "info")
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
        if destination.SurfaceSnap == true then
            local compatibility = self.Context and self.Context.Compatibility
            local workspace = compatibility and compatibility.Workspace
            if not workspace then
                return nil, "Workspace is unavailable for surface lookup"
            end
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {
                compatibility.Player and compatibility.Player.Character,
            }
            pcall(function()
                params.RespectCanCollide = true
            end)
            local origin = destination.Position + Vector3.new(0, 1200, 0)
            local hit = workspace:Raycast(origin, Vector3.new(0, -2400, 0), params)
            if not hit then
                return nil, "Could not find a safe surface at " .. destination.Name
            end
            return CFrame.new(hit.Position + Vector3.new(0, 5, 0))
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

function TeleportFeature:_FinishTravel(request, message, kind)
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

function TeleportFeature:Cancel(message)
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
    self:_SetFeatureEnabled(request.Action, false)
    if message then
        self:_SetStatus(message, "warning")
    else
        self:_SetStatus("Travel cancelled.", "info")
    end
    return true
end

function TeleportFeature:_StartTravel(destination, destinationLabel, actionId)
    local context = self.Context
    local compatibility = context and context.Compatibility
    local mainFarm = context and context.MainFarm
    if mainFarm and mainFarm.Running then
        self:_SetFeatureEnabled(actionId, false)
        self:_SetStatus("Turn off Start Farm before manual travel.", "warning")
        return false, "Auto Farm is running"
    end
    local character, humanoid, root = compatibility:GetCharacterParts()
    if not character or not humanoid or not root then
        self:_SetFeatureEnabled(actionId, false)
        self:_SetStatus("Travel unavailable: character is not ready.", "error")
        return false, "Character is unavailable"
    end

    if self.ActiveTravel then
        self:Cancel("Previous travel request cancelled.")
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
        LastStallAt = self.MovementService.LastStallAt,
        Label = destinationLabel,
        Action = actionId,
        Destination = destination,
        StallRetries = 0,
    }
    self.ActiveTravel = request
    self:_SetFeatureEnabled(actionId, true)

    local function issueMovement()
        return self.MovementService:MoveTo(request.Destination, {
            Speed = 190,
            Threshold = 8,
            IsCurrent = function()
                return self.ActiveTravel == request
                    and self.Generation == request.Generation
                    and compatibility.Player.Character == character
                    and not (mainFarm and mainFarm.Running)
            end,
        })
    end
    local moveCallOk, moved, moveResult = pcall(issueMovement)
    if not moveCallOk then
        moveResult = moved
        moved = false
    end
    if not moved then
        self:_FinishTravel(
            request,
            "Travel could not start: " .. tostring(moveResult),
            "error"
        )
        return false, moveResult
    end
    if moveResult == "arrived" then
        self:_FinishTravel(request, "Arrived at " .. destinationLabel .. ".", "success")
        return true
    end

    self:_SetStatus("Travelling to " .. destinationLabel .. ".", "info")
    task.spawn(function()
        while self.ActiveTravel == request do
            if compatibility.Player.Character ~= character then
                self:_FinishTravel(request, "Travel cancelled because the character changed.", "warning")
                return
            end
            if mainFarm and mainFarm.Running then
                self:_FinishTravel(request, "Travel cancelled because Auto Farm started.", "warning")
                return
            end

            if not self.MovementService.Active then
                if self.MovementService.LastStallAt ~= request.LastStallAt then
                    request.LastStallAt = self.MovementService.LastStallAt
                    if request.StallRetries >= MAX_STALL_RETRIES then
                        self:_FinishTravel(
                            request,
                            "Travel stalled after "
                                .. tostring(request.StallRetries)
                                .. " retries; copy the status report for movement details, then try again.",
                            "warning"
                        )
                        return
                    end

                    request.StallRetries += 1
                    self:_SetStatus(
                        "Travel stalled; retrying ("
                            .. tostring(request.StallRetries)
                            .. "/"
                            .. tostring(MAX_STALL_RETRIES)
                            .. ").",
                        "warning"
                    )
                    task.wait(STALL_RETRY_DELAY)
                    if self.ActiveTravel ~= request then
                        return
                    end

                    local retryCallOk, retryMoved, retryResult = pcall(issueMovement)
                    if not retryCallOk then
                        retryResult = retryMoved
                        retryMoved = false
                    end
                    if not retryMoved then
                        self:_FinishTravel(
                            request,
                            "Travel retry could not start: " .. tostring(retryResult),
                            "error"
                        )
                        return
                    end
                    if retryResult == "arrived" then
                        self:_FinishTravel(
                            request,
                            "Arrived at " .. request.Label .. ".",
                            "success"
                        )
                        return
                    end
                else
                    self:_FinishTravel(request, "Arrived at " .. request.Label .. ".", "success")
                    return
                end
            end
            task.wait(0.1)
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

function TeleportFeature:Handle(actionId, payload)
    local config = self.Context and self.Context.Config
    if actionId == "teleport.island.select" then
        local compatibility = self.Context.Compatibility
        local seaIndex = currentSeaIndex(compatibility)
        local options = {}
        for _, destination in ipairs(
            seaIndex and (config.TravelDestinations[seaIndex] or {}) or {}
        ) do
            table.insert(options, destination.Name)
        end
        self:_SelectSetting("Island", payload, options)
        return true
    elseif actionId == "teleport.npc.select" then
        local compatibility = self.Context.Compatibility
        local workspace = compatibility.Workspace
        local replicatedStorage = compatibility.ReplicatedStorage
        local npcSources = {}
        local liveNpcFolder = workspace and workspace:FindFirstChild("NPCs")
        local templateNpcFolder = replicatedStorage and replicatedStorage:FindFirstChild("NPCs")
        if liveNpcFolder then
            table.insert(npcSources, { Folder = liveNpcFolder, IsLive = true })
        end
        if templateNpcFolder then
            table.insert(npcSources, { Folder = templateNpcFolder, IsLive = false })
        end
        local options = {}
        if currentSeaIndex(compatibility) then
            local names = {}
            for _, source in ipairs(npcSources) do
                for _, npc in ipairs(source.Folder:GetChildren()) do
                    local isLive = source.IsLive
                    local root = npc:IsA("Model")
                        and (npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart)
                    local humanoid = isLive and npc:IsA("Model")
                        and npc:FindFirstChildOfClass("Humanoid")
                    if npc:IsA("Model")
                        and root
                        and root:IsA("BasePart")
                        and (not humanoid or humanoid.Health > 0)
                        and (isLive or config.IsTravelNpcPositionInCurrentSea(compatibility, root.Position))
                        and not string.find(npc.Name, "Boat", 1, true)
                        and not string.find(npc.Name, "Set Home", 1, true)
                    then
                        names[npc.Name] = true
                    end
                end
            end
            for name in pairs(names) do
                table.insert(options, name)
            end
            table.sort(options)
        end
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
    self.ActiveTravel = nil
    self.MovementService = context.MovementService

    local player = context.Compatibility.Player
    if player then
        self.CharacterRemovingConnection = player.CharacterRemoving:Connect(function()
            self:Cancel("Travel cancelled because the character is resetting.")
        end)
    end
    return true
end

function TeleportFeature:Cleanup()
    self:Cancel("Travel cancelled during hub cleanup.")
    disconnect(self.CharacterRemovingConnection)
    self.CharacterRemovingConnection = nil
    self.Context = nil
    self.MovementService = nil
end

return TeleportFeature
