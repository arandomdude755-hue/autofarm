local MovementService = {}
MovementService.__index = MovementService

local SUBMERGED_REFERENCE = Vector3.new(11538.599609375, -2154.7021484375, 9827.3125)
local TIKI_OUTPOST_REFERENCE = Vector3.new(-16204, 10, 479)
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
local function disconnect(connection)
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
    end
end

local function formatPosition(position)
    return string.format("(%.1f, %.1f, %.1f)", position.X, position.Y, position.Z)
end

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
        FarmCollisionActive = false,
        FarmCollisionCharacter = nil,
        FarmCollisionCharacterAddedConnection = nil,
        FarmCollisionCharacterRemovingConnection = nil,
        FarmCollisionDescendantAddedConnection = nil,
        FarmCollisionSteppedConnection = nil,
        FarmCollisionOriginals = {},
        FarmCollisionPartConnections = {},
        FarmCollisionErrorReported = false,
        FarmCollisionMaintenanceGeneration = 0,
        HoldForce = nil,
        LastStallDiagnostic = nil,
    }, MovementService)
end

function MovementService:_GetRoute(destination, currentPosition)
    if not self.Compatibility:IsThirdSea() then
        return nil
    end

    local destinationDistance = (destination.Position - SUBMERGED_REFERENCE).Magnitude
    local currentDistance = (currentPosition - SUBMERGED_REFERENCE).Magnitude
    if destinationDistance <= 3000 and currentDistance > 3000 then
        return {
            Name = "Submerged",
            Stage = SUBMERGED_STAGING,
            ArrivalReference = SUBMERGED_REFERENCE,
            ArrivalRadius = 3000,
        }
    end
    if destinationDistance > 3000 and currentDistance <= 3000 then
        return {
            Name = "Tiki",
            Stage = TIKI_STAGING,
            ArrivalReference = TIKI_OUTPOST_REFERENCE,
            ArrivalRadius = 3000,
        }
    end
    return nil
end

function MovementService:GetSpecialTravelRoute(destination, currentPosition)
    return self:_GetRoute(destination, currentPosition)
end

function MovementService:RequestSpecialTravelRoute(route, isCurrent)
    if type(route) ~= "table" or (route.Name ~= "Submerged" and route.Name ~= "Tiki") then
        return false, "Unsupported special travel route"
    end
    if type(isCurrent) ~= "function" then
        isCurrent = function()
            return true
        end
    end
    return self:_RequestRoute(route, isCurrent, self.RouteGeneration)
end

function MovementService:_RestoreCollision(active)
    for part, canCollide in pairs(active.CollisionOriginals) do
        if part and part.Parent then
            part.CanCollide = canCollide
        end
        active.CollisionOriginals[part] = nil
    end
end

function MovementService:_RestoreFarmCollision()
    disconnect(self.FarmCollisionDescendantAddedConnection)
    self.FarmCollisionDescendantAddedConnection = nil
    for part, canCollide in pairs(self.FarmCollisionOriginals) do
        disconnect(self.FarmCollisionPartConnections[part])
        self.FarmCollisionPartConnections[part] = nil
        pcall(function()
            if part.Parent then
                part.CanCollide = canCollide
            end
        end)
    end
    table.clear(self.FarmCollisionOriginals)
    self.FarmCollisionCharacter = nil
end

function MovementService:_ReportFarmCollisionError(err)
    if self.FarmCollisionErrorReported or not self.Report then
        return
    end
    self.FarmCollisionErrorReported = true
    self.Report("Character collision maintenance error: " .. tostring(err), "warning")
end

function MovementService:_CaptureStallDiagnostic(active, root, goal, distance)
    local collisionParts = {}
    local collidableParts = {}
    local collidableCount = 0
    local seenParts = {}
    local function inspectPart(part)
        if not part or seenParts[part] or not part.Parent then
            return
        end
        seenParts[part] = true
        collisionParts[#collisionParts + 1] = part
        if part.CanCollide then
            collidableCount += 1
            if #collidableParts < 5 then
                collidableParts[#collidableParts + 1] = part.Name
            end
        end
    end

    for part in pairs(self.FarmCollisionOriginals) do
        inspectPart(part)
    end
    for part in pairs(active.CollisionOriginals or {}) do
        inspectPart(part)
    end

    local obstacle = "no hit within 30 studs"
    local raycastOk, raycastResult = pcall(function()
        local offset = goal.Position - root.Position
        local castDistance = math.min(offset.Magnitude, 30)
        if castDistance <= 0 then
            return nil
        end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { active.Character }
        return self.Compatibility.Workspace:Raycast(
            root.Position,
            offset.Unit * castDistance,
            params
        )
    end)
    if not raycastOk then
        obstacle = "raycast unavailable: " .. tostring(raycastResult)
    elseif raycastResult then
        local instance = raycastResult.Instance
        local canCollide = "n/a"
        if instance:IsA("BasePart") then
            canCollide = tostring(instance.CanCollide)
        end
        obstacle = string.format(
            "hit=%s (%s); distance=%.1f; CanCollide=%s; material=%s",
            tostring(instance.Name),
            tostring(instance.ClassName),
            raycastResult.Distance,
            canCollide,
            tostring(raycastResult.Material)
        )
    end

    local correctionDistance = active.LastCommandError
        and string.format("%.1f studs", active.LastCommandError)
        or "not available"
    local collidableSummary = #collidableParts > 0
        and table.concat(collidableParts, ", ")
        or "none"
    local lines = {
        "===== [MovementStallDiagnostic] REPORT BEGIN =====",
        string.format("Stall duration: %.2f seconds", os.clock() - active.LastProgressAt),
        string.format("Root position: %s", formatPosition(root.Position)),
        string.format("Goal position: %s; current distance=%.1f studs", formatPosition(goal.Position), distance),
        "Tracked character parts: "
            .. tostring(#collisionParts)
            .. "; currently collidable: "
            .. tostring(collidableCount)
            .. "; examples: "
            .. collidableSummary,
        "Distance from last commanded position: " .. correctionDistance,
        "Forward obstacle check: " .. obstacle,
        "A clear ray only describes the corridor; it does not confirm the root accepted position commands.",
        "===== [MovementStallDiagnostic] REPORT END =====",
    }
    local text = table.concat(lines, "\n")
    self.LastStallDiagnostic = {
        At = os.clock(),
        Text = text,
    }
    return text
end

function MovementService:_MaintainFarmCollision()
    if not self.FarmCollisionActive then
        return
    end

    local player = self.Compatibility.Player
    if player and player.Character ~= self.FarmCollisionCharacter then
        self:_ApplyFarmCollision()
        return
    end

    for part in pairs(self.FarmCollisionOriginals) do
        if not part.Parent then
            disconnect(self.FarmCollisionPartConnections[part])
            self.FarmCollisionPartConnections[part] = nil
            self.FarmCollisionOriginals[part] = nil
        elseif part.CanCollide then
            self:_ApplyFarmCollisionPart(part)
        end
    end
end

function MovementService:_StartFarmCollisionMaintenance()
    self.FarmCollisionMaintenanceGeneration += 1
    local generation = self.FarmCollisionMaintenanceGeneration
    disconnect(self.FarmCollisionSteppedConnection)
    self.FarmCollisionSteppedConnection = self.Compatibility.RunService.Stepped:Connect(function()
        if not self.FarmCollisionActive
            or self.FarmCollisionMaintenanceGeneration ~= generation
        then
            return
        end

        -- Reassert collision suppression before each physics step, but only
        -- across the cached, event-maintained character parts. This prevents
        -- game scripts from restoring CanCollide between low-frequency checks
        -- without rescanning the character hierarchy every frame.
        do
            local ok, err = pcall(self._MaintainFarmCollision, self)
            if ok then
                self.FarmCollisionErrorReported = false
            else
                self:_ReportFarmCollisionError(err)
            end
        end
    end)
end

function MovementService:_ApplyFarmCollisionPart(part)
    if not self.FarmCollisionActive or not part:IsA("BasePart") then
        return
    end

    if self.FarmCollisionOriginals[part] == nil then
        self.FarmCollisionOriginals[part] = part.CanCollide
        self.FarmCollisionPartConnections[part] =
            part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                if self.FarmCollisionActive and part.Parent and part.CanCollide then
                    part.CanCollide = false
                end
            end)
    end
    if part.CanCollide then
        part.CanCollide = false
    end
end

function MovementService:_ApplyFarmCollision()
    if not self.FarmCollisionActive then
        return true
    end

    local player = self.Compatibility.Player
    local character = player and player.Character
    if character == self.FarmCollisionCharacter then
        return true
    end

    self:_RestoreFarmCollision()
    self.FarmCollisionCharacter = character
    if not character then
        return true
    end

    self.FarmCollisionDescendantAddedConnection = character.DescendantAdded:Connect(function(descendant)
        local ok, err = pcall(self._ApplyFarmCollisionPart, self, descendant)
        if ok then
            self.FarmCollisionErrorReported = false
        else
            self:_ReportFarmCollisionError(err)
        end
    end)
    for _, descendant in ipairs(character:GetDescendants()) do
        self:_ApplyFarmCollisionPart(descendant)
    end
    return true
end

function MovementService:SetFarmCollisionSuppression(enabled)
    enabled = enabled == true
    if not enabled then
        self.FarmCollisionActive = false
        self.FarmCollisionMaintenanceGeneration += 1
        disconnect(self.FarmCollisionSteppedConnection)
        self.FarmCollisionSteppedConnection = nil
        disconnect(self.FarmCollisionCharacterAddedConnection)
        disconnect(self.FarmCollisionCharacterRemovingConnection)
        self.FarmCollisionCharacterAddedConnection = nil
        self.FarmCollisionCharacterRemovingConnection = nil
        self:_RestoreFarmCollision()
        self.FarmCollisionErrorReported = false
        return true
    end

    if self.FarmCollisionActive then
        local ok, err = pcall(self._ApplyFarmCollision, self)
        if not ok then
            return false, tostring(err)
        end
        return true
    end

    self.FarmCollisionActive = true
    local ok, err = pcall(function()
        self:_ApplyFarmCollision()
        local player = self.Compatibility.Player
        if player then
            self.FarmCollisionCharacterAddedConnection = player.CharacterAdded:Connect(function()
                local applyOk, applyError = pcall(self._ApplyFarmCollision, self)
                if applyOk then
                    self.FarmCollisionErrorReported = false
                else
                    self:_ReportFarmCollisionError(applyError)
                end
            end)
            self.FarmCollisionCharacterRemovingConnection =
                player.CharacterRemoving:Connect(function(character)
                    if self.FarmCollisionCharacter == character then
                        self:_RestoreFarmCollision()
                    end
                end)
        end
    end)
    if not ok then
        self.FarmCollisionActive = false
        self.FarmCollisionMaintenanceGeneration += 1
        disconnect(self.FarmCollisionSteppedConnection)
        self.FarmCollisionSteppedConnection = nil
        disconnect(self.FarmCollisionCharacterAddedConnection)
        disconnect(self.FarmCollisionCharacterRemovingConnection)
        self.FarmCollisionCharacterAddedConnection = nil
        self.FarmCollisionCharacterRemovingConnection = nil
        self:_RestoreFarmCollision()
        return false, tostring(err)
    end

    self.FarmCollisionErrorReported = false
    self:_StartFarmCollisionMaintenance()
    return true
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

function MovementService:_DestroyHoldForce()
    if self.HoldForce and self.HoldForce.Parent then
        self.HoldForce:Destroy()
    end
    self.HoldForce = nil
end

function MovementService:Cancel()
    self.RouteGeneration += 1
    if type(self.OnCancel) == "function" then
        pcall(self.OnCancel)
    end
    self:_StopMovement()
    self:_DestroyHoldForce()
end

function MovementService:HoldPosition(isCurrent)
    local character, humanoid, root = self.Compatibility:GetCharacterParts()
    if not character or not humanoid or not root then
        return false, "Character is unavailable"
    end
    isCurrent = isCurrent or function()
        return true
    end
    if not isCurrent() then
        return false, "Farm session is no longer current"
    end

    local active = self.Active
    if active
        and active.Character == character
        and active.KeepSession
        and active.IsCurrent()
    then
        if active.HoldingForSearch then
            return true, "already holding"
        end
        active.Goal = root.CFrame
        active.Threshold = 1
        active.Speed = 0
        active.Holding = false
        active.HoldingForSearch = true
        active.BestDistance = 0
        active.LastProgressAt = os.clock()
        return true, "holding current position"
    end

    if active then
        self:_StopMovement()
    end
    if self.HoldForce and self.HoldForce.Parent ~= root then
        self:_DestroyHoldForce()
    end
    if not self.HoldForce then
        local holdForce = Instance.new("BodyVelocity")
        holdForce.Name = "CustomHubFarmHoldForce"
        holdForce.Velocity = Vector3.zero
        holdForce.MaxForce = Vector3.new(100000, 100000, 100000)
        holdForce.P = 10000
        holdForce.Parent = root
        self.HoldForce = holdForce
    end
    self.HoldForce.Velocity = Vector3.zero
    return true, "holding current position"
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
    -- A reached destination is not a reusable "already moving" goal: let the
    -- retained-session branch below refresh it, even for a small target shift.
    if active
        and active.Character == character
        and active.RouteName == (route and route.Name)
        and not active.Holding
        and not active.HoldingForSearch
        and (active.Goal.Position - goal.Position).Magnitude <= 12
    then
        return true, "already moving"
    end

    if active
        and active.Character == character
        and active.KeepSession
        and options.KeepSession == true
        and not active.Route
        and not route
        and active.IsCurrent()
    then
        local previousGoal = active.Goal.Position
        local destinationShift = (previousGoal - goal.Position).Magnitude
        local wasHolding = active.Holding or active.HoldingForSearch
        active.Goal = goal
        active.Threshold = threshold
        active.Speed = tonumber(options.Speed) or active.Speed
        active.IsCurrent = isCurrent
        active.Holding = false
        active.HoldingForSearch = false
        if wasHolding or destinationShift > 12 then
            active.BestDistance = (goal.Position - root.Position).Magnitude
            active.LastProgressAt = os.clock()
        end
        if active.BestDistance <= threshold then
            root.CFrame = destination
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            active.Holding = true
        end
        return true, active.Holding and "retargeted and holding" or "retargeted"
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

    self:_DestroyHoldForce()
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
        Speed = route and 190 or (tonumber(options.Speed) or 300),
        IsCurrent = isCurrent,
        Generation = generation,
        CollisionOriginals = collisionOriginals,
        FloatForce = ownsFloatForce and floatForce or nil,
        HasTeleportTag = self.OwnsTeleportTag,
        KeepSession = options.KeepSession == true and route == nil,
        Holding = false,
        HoldingForSearch = false,
        BestDistance = (goal.Position - root.Position).Magnitude,
        LastProgressAt = os.clock(),
    }
    self.Active = active

    active.Connection = self.Compatibility.RunService.Heartbeat:Connect(function(deltaTime)
        if self.Active ~= active or self.Generation ~= generation or not active.IsCurrent() then
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

        local goalNow = active.Goal
        local thresholdNow = active.Threshold
        if active.HoldingForSearch then
            root.CFrame = goalNow
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            active.LastCommandedPosition = goalNow.Position
            active.Holding = true
            active.BestDistance = 0
            active.LastProgressAt = os.clock()
            return
        end
        local offset = goalNow.Position - root.Position
        local distance = offset.Magnitude
        active.LastCommandError = active.LastCommandedPosition
            and (root.Position - active.LastCommandedPosition).Magnitude
            or nil
        if distance <= thresholdNow then
            root.CFrame = goalNow
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            active.LastCommandedPosition = goalNow.Position
            if active.KeepSession then
                active.Holding = true
                active.BestDistance = distance
                active.LastProgressAt = os.clock()
                return
            end
            self:_Finish(active, true)
            if active.Route then
                self:_RequestRoute(active.Route, active.IsCurrent, self.RouteGeneration)
            end
            return
        end
        active.Holding = false
        if distance < active.BestDistance - 1 then
            active.BestDistance = distance
            active.LastProgressAt = os.clock()
        elseif os.clock() - active.LastProgressAt > 2.5 then
            self.LastStallAt = os.clock()
            local diagnosticOk, diagnosticError = pcall(
                self._CaptureStallDiagnostic,
                self,
                active,
                root,
                goalNow,
                distance
            )
            if not diagnosticOk then
                self.LastStallDiagnostic = {
                    At = os.clock(),
                    Text = "===== [MovementStallDiagnostic] REPORT BEGIN =====\n"
                        .. "Snapshot failed: "
                        .. tostring(diagnosticError)
                        .. "\n===== [MovementStallDiagnostic] REPORT END =====",
                }
            end
            self:_Finish(active, true)
            self:HoldPosition(active.IsCurrent)
            self.Report(
                "Movement stalled; cancelling this attempt before retry. Copy the status report for details.",
                "warning"
            )
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
        active.LastCommandedPosition = nextPosition
    end)

    return true, route and ("moving to " .. route.Name .. " staging") or "moving"
end

return MovementService
