local TeleportFeature = {
    Context = nil,
    MovementService = nil,
    ActiveTravel = nil,
    Generation = 0,
    CharacterRemovingConnection = nil,
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

function TeleportFeature:_SetStatus(message, kind)
    if self.Context and self.Context.State then
        self.Context.State:SetStatus(message, kind or "info")
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
    local npcFolder = workspace and workspace:FindFirstChild("NPCs")
    if not npcFolder then
        return nil, "Workspace.NPCs is unavailable"
    end

    local _, _, playerRoot = compatibility:GetCharacterParts()
    local nearestRoot
    local nearestDistance = math.huge
    for _, npc in ipairs(npcFolder:GetChildren()) do
        if npc:IsA("Model") and npc.Name == name then
            local root = npc:FindFirstChild("HumanoidRootPart")
            local humanoid = npc:FindFirstChildOfClass("Humanoid")
            if root and root:IsA("BasePart") and (not humanoid or humanoid.Health > 0) then
                local distance = playerRoot and (root.Position - playerRoot.Position).Magnitude or 0
                if distance < nearestDistance then
                    nearestRoot = root
                    nearestDistance = distance
                end
            end
        end
    end
    if not nearestRoot then
        return nil, "The selected NPC is not currently loaded in Workspace.NPCs"
    end
    return nearestRoot
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
    return CFrame.new(root.Position + Vector3.new(0, 5, 0))
end

function TeleportFeature:_ResolveIslandCFrame(destination)
    if destination.Position then
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
    if message then
        self:_SetStatus(message, "warning")
    else
        self:_SetStatus("Travel cancelled.", "info")
    end
    return true
end

function TeleportFeature:_StartTravel(destination, destinationLabel)
    local context = self.Context
    local compatibility = context and context.Compatibility
    local mainFarm = context and context.MainFarm
    if mainFarm and mainFarm.Running then
        self:_SetStatus("Turn off Start Farm before manual travel.", "warning")
        return false, "Auto Farm is running"
    end
    local character, humanoid, root = compatibility:GetCharacterParts()
    if not character or not humanoid or not root then
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
    }
    self.ActiveTravel = request
    local moveCallOk, moved, moveResult = pcall(function()
        return self.MovementService:MoveTo(destination, {
            Speed = 190,
            Threshold = 8,
            IsCurrent = function()
                return self.ActiveTravel == request
                    and self.Generation == request.Generation
                    and compatibility.Player.Character == character
                    and not (mainFarm and mainFarm.Running)
            end,
        })
    end)
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
                    self:_FinishTravel(
                        request,
                        "Travel stalled; copy the status report for movement details.",
                        "warning"
                    )
                else
                    self:_FinishTravel(request, "Arrived at " .. request.Label .. ".", "success")
                end
                return
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
        return self:_SelectSetting("Island", payload, options)
    elseif actionId == "teleport.npc.select" then
        local workspace = self.Context.Compatibility.Workspace
        local npcFolder = workspace and workspace:FindFirstChild("NPCs")
        local options = {}
        if currentSeaIndex(self.Context.Compatibility) and npcFolder then
            local names = {}
            for _, npc in ipairs(npcFolder:GetChildren()) do
                local root = npc:IsA("Model") and npc:FindFirstChild("HumanoidRootPart")
                local humanoid = npc:IsA("Model") and npc:FindFirstChildOfClass("Humanoid")
                if npc:IsA("Model")
                    and root
                    and root:IsA("BasePart")
                    and (not humanoid or humanoid.Health > 0)
                    and not string.find(npc.Name, "Boat", 1, true)
                    and not string.find(npc.Name, "Set Home", 1, true)
                then
                    names[npc.Name] = true
                end
            end
            for name in pairs(names) do
                table.insert(options, name)
            end
            table.sort(options)
        end
        return self:_SelectSetting("Npc", payload, options)
    elseif actionId == "teleport.island.go" then
        local destination, destinationError = self:_GetSelectedIsland()
        if not destination then
            self:_SetStatus(destinationError .. ".", "warning")
            return false, destinationError
        end
        local cframe, resolveError = self:_ResolveIslandCFrame(destination)
        if not cframe then
            self:_SetStatus(resolveError .. ".", "warning")
            return false, resolveError
        end
        return self:_StartTravel(cframe, destination.Name)
    elseif actionId == "teleport.npc.go" then
        local destination, destinationError = self:_GetNpcDestination()
        if not destination then
            self:_SetStatus(destinationError .. ".", "warning")
            return false, destinationError
        end
        return self:_StartTravel(destination, "NPC " .. tostring(config.TravelSettings.Npc))
    elseif actionId == "teleport.cancel" then
        if not self:Cancel() then
            self:_SetStatus("There is no active travel to cancel.", "info")
        end
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
