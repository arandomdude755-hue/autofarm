local MovementService = {}
MovementService.__index = MovementService

local SUBMERGED_REFERENCE = Vector3.new(11538.599609375, -2154.7021484375, 9827.3125)
local SUBMERGED_STAGING = CFrame.new(
    -16269.4082,
    23.9799957,
    1371.66235,
    -0.999388933,
    0,
    -0.0349550731,
    0,
    1,
    0,
    0.0349550731,
    0,
    -0.999388933
)
local TIKI_STAGING = CFrame.new(
    11427.9189,
    -2156.36401,
    9726.24023,
    -0.929097056,
    -7.17796156E-34,
    0.369835705,
    -7.17796156E-34,
    1,
    1.37611875E-34,
    -0.369835705,
    -1.37611875E-34,
    -0.929097056
)

function MovementService.new(compatibility, report)
    return setmetatable({
        Compatibility = compatibility,
        Report = report,
        Active = nil,
        Generation = 0,
        RouteGeneration = 0,
        TagGeneration = 0,
        OwnsTeleportTag = false,
        LastRouteRequest = {},
    }, MovementService)
end

function MovementService:_GetRoute(destination, currentPosition)
    if not self.Compatibility:IsThirdSea() then
        return nil
    end

    local destinationDistance = (destination.Position - SUBMERGED_REFERENCE).Magnitude
    local currentDistance = (currentPosition - SUBMERGED_REFERENCE).Magnitude
    if destinationDistance <= 3000 and currentDistance > 3000 then
        return { Name = "Submerged", Stage = SUBMERGED_STAGING }
    end
    if destinationDistance > 3000 and currentDistance <= 3000 then
        return { Name = "Tiki", Stage = TIKI_STAGING }
    end
    return nil
end

function MovementService:_RestoreCollision(active)
    for part, canCollide in pairs(active.CollisionOriginals) do
        if part and part.Parent then
            part.CanCollide = canCollide
        end
        active.CollisionOriginals[part] = nil
    end
end

function MovementService:_Finish(active, delayTagRemoval)
    if self.Active ~= active then
        return
    end
    self.Active = nil
    if active.Connection and active.Connection.Connected then
        active.Connection:Disconnect()
    end
    self:_RestoreCollision(active)

    if active.FloatForce and active.FloatForce.Parent then
        active.FloatForce:Destroy()
    end
    if active.Humanoid and active.Humanoid.Parent then
        active.Humanoid.PlatformStand = false
    end

    if active.HasTeleportTag then
        local tagGeneration = self.TagGeneration
        local function removeTag()
            if self.Active == nil
                and self.TagGeneration == tagGeneration
                and self.Compatibility.CollectionService:HasTag(self.Compatibility.Player, "Teleporting")
            then
                self.Compatibility.CollectionService:RemoveTag(self.Compatibility.Player, "Teleporting")
                self.OwnsTeleportTag = false
            end
        end
        if delayTagRemoval then
            task.delay(1.5, removeTag)
        else
            removeTag()
        end
    end
end

function MovementService:_StopMovement()
    self.Generation += 1
    local active = self.Active
    if active then
        self:_Finish(active, true)
    end
end

function MovementService:Cancel()
    self.RouteGeneration += 1
    self:_StopMovement()
end

function MovementService:_RequestRoute(route, isCurrent, routeGeneration)
    local now = os.clock()
    if now - (self.LastRouteRequest[route.Name] or 0) < 5 then
        return false, "Travel request is cooling down"
    end
    self.LastRouteRequest[route.Name] = now

    task.spawn(function()
        if not isCurrent() or self.RouteGeneration ~= routeGeneration then
            return
        end
        local replication = self.Compatibility.ReplicatedStorage
        local modules = replication:FindFirstChild("Modules")
        local netContainer = modules and modules:FindFirstChild("Net")
        local commF, commFError = self.Compatibility:GetCommF()
        if not netContainer or not commF then
            self.Report("Travel dependencies are unavailable", "error")
            return
        end

        local ok, err = pcall(function()
            if route.Name == "Submerged" then
                local remote = netContainer:FindFirstChild("RF/SubmarineWorkerSpeak")
                if not remote then
                    error("Modules.Net.RF/SubmarineWorkerSpeak is unavailable")
                end
                remote:InvokeServer("TravelToSubmergedIsland")
                if isCurrent() and self.RouteGeneration == routeGeneration then
                    commF:InvokeServer("SetLastSpawnPoint", "SubmergedIsland")
                end
            else
                local remote = netContainer:FindFirstChild("RF/SubmarineTransportation")
                if not remote then
                    error("Modules.Net.RF/SubmarineTransportation is unavailable")
                end
                remote:InvokeServer("GetAvailableLocations")
                if isCurrent() and self.RouteGeneration == routeGeneration then
                    remote:InvokeServer("InitiateTeleport", "Tiki Outpost")
                end
            end
        end)
        if not isCurrent() or self.RouteGeneration ~= routeGeneration then
            return
        end
        if ok then
            self.Report(route.Name .. " travel request submitted", "info")
        else
            self.Report("Travel request error: " .. tostring(err), "error")
        end
    end)
    return true
end

function MovementService:MoveTo(destination, options)
    options = options or {}
    if typeof(destination) ~= "CFrame" then
        return false, "Movement destination must be a CFrame"
    end

    local character, humanoid, root = self.Compatibility:GetCharacterParts()
    if not character or not humanoid or not root then
        return false, "Character is unavailable"
    end
    if self.LastStallAt and os.clock() - self.LastStallAt < 1 then
        return false, "Movement retry cooldown after a stall"
    end

    local route = self:_GetRoute(destination, root.Position)
    local goal = route and route.Stage or destination
    local threshold = route and 8 or (tonumber(options.Threshold) or 2.5)
    local isCurrent = options.IsCurrent or function()
        return true
    end

    local active = self.Active
    if active
        and active.Character == character
        and active.RouteName == (route and route.Name)
        and (active.Goal.Position - goal.Position).Magnitude <= 12
    then
        return true, "already moving"
    end

    self:_StopMovement()
    if (goal.Position - root.Position).Magnitude <= threshold then
        if route then
            local requested, requestError = self:_RequestRoute(
                route,
                isCurrent,
                self.RouteGeneration
            )
            return requested, requestError or "at travel staging point"
        end
        root.CFrame = destination
        return true, "arrived"
    end

    self.Generation += 1
    self.TagGeneration += 1
    local generation = self.Generation
    local collisionOriginals = {}
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            collisionOriginals[descendant] = descendant.CanCollide
            descendant.CanCollide = false
        end
    end

    local floatForce = root:FindFirstChild("FloatForce")
    local ownsFloatForce = false
    if not floatForce then
        floatForce = Instance.new("BodyVelocity")
        floatForce.Name = "FloatForce"
        floatForce.Velocity = Vector3.zero
        floatForce.MaxForce = Vector3.new(100000, 100000, 100000)
        floatForce.P = 10000
        floatForce.Parent = root
        ownsFloatForce = true
    end

    local hasTag = self.Compatibility.CollectionService:HasTag(
        self.Compatibility.Player,
        "Teleporting"
    )
    if not hasTag then
        self.Compatibility.CollectionService:AddTag(self.Compatibility.Player, "Teleporting")
        self.OwnsTeleportTag = true
    end

    active = {
        Character = character,
        Humanoid = humanoid,
        Root = root,
        Goal = goal,
        RouteName = route and route.Name,
        Route = route,
        Threshold = threshold,
        Speed = route and 350 or (tonumber(options.Speed) or 300),
        IsCurrent = isCurrent,
        Generation = generation,
        CollisionOriginals = collisionOriginals,
        FloatForce = ownsFloatForce and floatForce or nil,
        HasTeleportTag = self.OwnsTeleportTag,
        BestDistance = (goal.Position - root.Position).Magnitude,
        LastProgressAt = os.clock(),
    }
    self.Active = active

    active.Connection = self.Compatibility.RunService.Heartbeat:Connect(function(deltaTime)
        if self.Active ~= active or self.Generation ~= generation or not isCurrent() then
            self:_Finish(active, true)
            return
        end

        local currentCharacter, currentHumanoid, currentRoot = self.Compatibility:GetCharacterParts()
        if currentCharacter ~= character
            or currentHumanoid ~= humanoid
            or currentRoot ~= root
            or root.Anchored
        then
            self.LastStallAt = os.clock()
            self:_Finish(active, true)
            self.Report("Movement interrupted by character replacement or an anchored root", "warning")
            return
        end

        local offset = goal.Position - root.Position
        local distance = offset.Magnitude
        if distance <= threshold then
            root.CFrame = goal
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            self:_Finish(active, true)
            if route then
                self:_RequestRoute(route, isCurrent, self.RouteGeneration)
            end
            return
        end
        if distance < active.BestDistance - 1 then
            active.BestDistance = distance
            active.LastProgressAt = os.clock()
        elseif os.clock() - active.LastProgressAt > 2.5 then
            self.LastStallAt = os.clock()
            self:_Finish(active, true)
            self.Report("Movement stalled; cancelling this attempt before retry", "warning")
            return
        end

        local step = math.min(active.Speed * deltaTime, 18)
        if step <= 0 then
            return
        end
        local nextPosition = root.Position + offset.Unit * math.min(step, distance)
        root.CFrame = CFrame.new(nextPosition)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)

    return true, route and ("moving to " .. route.Name .. " staging") or "moving"
end

return MovementService
