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

function MovementService.new(compatibility, report, lowHealthSettings)
    local self = setmetatable({
        Compatibility = compatibility,
        Report = report,
        LowHealthRetreatSettings = lowHealthSettings or {},
        Destroyed = false,
        LowHealthRetreatLatched = false,
        LowHealthRetreatPending = false,
        LowHealthRetreatInProgress = false,
        LowHealthRetreatDeferralGeneration = 0,
        LowHealthRetreatDeferrals = {},
        LowHealthRetreatCharacter = nil,
        LowHealthRetreatHumanoidConnection = nil,
        LowHealthRetreatChildAddedConnection = nil,
        LowHealthRetreatCharacterAddedConnection = nil,
        LowHealthRetreatCharacterRemovingConnection = nil,
        LowHealthRetreat = nil,
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
    self:_InitializeLowHealthRetreat()
    return self
end

function MovementService:_InitializeLowHealthRetreat()
    local player = self.Compatibility and self.Compatibility.Player
    if not player then
        return
    end
    self.LowHealthRetreatCharacterAddedConnection = player.CharacterAdded:Connect(function(character)
        self:_BindLowHealthRetreatCharacter(character)
    end)
    self.LowHealthRetreatCharacterRemovingConnection = player.CharacterRemoving:Connect(function(character)
        if self.LowHealthRetreatCharacter == character then
            self:_BindLowHealthRetreatCharacter(nil)
        end
    end)
    self:_BindLowHealthRetreatCharacter(player.Character)
end

function MovementService:_BindLowHealthRetreatCharacter(character)
    disconnect(self.LowHealthRetreatHumanoidConnection)
    disconnect(self.LowHealthRetreatChildAddedConnection)
    self.LowHealthRetreatHumanoidConnection = nil
    self.LowHealthRetreatChildAddedConnection = nil

    if self.LowHealthRetreat then
        self:_FinishLowHealthRetreat()
    end
    self.LowHealthRetreatCharacter = character
    self.LowHealthRetreatLatched = false
    self.LowHealthRetreatPending = false
    if not character then
        return
    end

    local function bindHumanoid(humanoid)
        if self.LowHealthRetreatCharacter ~= character or not humanoid then
            return
        end
        disconnect(self.LowHealthRetreatHumanoidConnection)
        self.LowHealthRetreatHumanoidConnection = humanoid.HealthChanged:Connect(function()
            self:RefreshLowHealthRetreat()
        end)
        self:RefreshLowHealthRetreat()
    end

    bindHumanoid(character:FindFirstChildOfClass("Humanoid"))
    self.LowHealthRetreatChildAddedConnection = character.ChildAdded:Connect(function(child)
        if child:IsA("Humanoid") then
            bindHumanoid(child)
        end
    end)
end

function MovementService:SetLowHealthRetreatSettings(settings)
    if self.Destroyed then
        return
    end
    self.LowHealthRetreatSettings = type(settings) == "table" and settings or {}
    self:RefreshLowHealthRetreat()
end

function MovementService:BeginLowHealthRetreatDeferral()
    if self.Destroyed then
        return nil
    end
    self.LowHealthRetreatDeferralGeneration += 1
    local token = self.LowHealthRetreatDeferralGeneration
    self.LowHealthRetreatDeferrals[token] = true
    task.delay(20, function()
        self:EndLowHealthRetreatDeferral(token)
    end)
    return token
end

function MovementService:EndLowHealthRetreatDeferral(token)
    if token == nil or not self.LowHealthRetreatDeferrals[token] then
        return false
    end
    self.LowHealthRetreatDeferrals[token] = nil
    if next(self.LowHealthRetreatDeferrals) == nil then
        self:RefreshLowHealthRetreat()
    end
    return true
end

function MovementService:_TrackLowHealthRetreatCollisionPart(retreat, part)
    if not part:IsA("BasePart") or retreat.CollisionOriginals[part] ~= nil then
        return
    end

    local original = part.CanCollide
    local farmOriginal = self.FarmCollisionActive
        and self.FarmCollisionOriginals[part]
    local movementOriginal = self.Active
        and self.Active.CollisionOriginals
        and self.Active.CollisionOriginals[part]
    if farmOriginal ~= nil then
        original = farmOriginal
    elseif movementOriginal ~= nil then
        original = movementOriginal
    end
    retreat.CollisionOriginals[part] = original
    retreat.PartConnections[part] = part:GetPropertyChangedSignal("CanCollide"):Connect(function()
        if self.LowHealthRetreat == retreat
            and not retreat.Restoring
            and part.Parent
            and part.CanCollide
        then
            part.CanCollide = false
        end
    end)
    part.CanCollide = false
end

function MovementService:_RestoreLowHealthRetreatCollision(retreat)
    retreat.Restoring = true
    disconnect(retreat.DescendantAddedConnection)
    retreat.DescendantAddedConnection = nil
    for part, original in pairs(retreat.CollisionOriginals) do
        disconnect(retreat.PartConnections[part])
        if part.Parent then
            local keepSuppressed = self.FarmCollisionActive == true
            local active = self.Active
            if not keepSuppressed and active and active.CollisionOriginals
                and active.CollisionOriginals[part] ~= nil
            then
                keepSuppressed = true
            end
            if keepSuppressed then
                part.CanCollide = false
            else
                part.CanCollide = original
            end
        end
    end
    table.clear(retreat.CollisionOriginals)
    table.clear(retreat.PartConnections)
end

function MovementService:_FinishLowHealthRetreat()
    local retreat = self.LowHealthRetreat
    if not retreat then
        self.LowHealthRetreatInProgress = false
        return
    end

    disconnect(retreat.Connection)
    retreat.Connection = nil
    self:_RestoreLowHealthRetreatCollision(retreat)
    self.LowHealthRetreat = nil
    self.LowHealthRetreatInProgress = false

    local _, humanoid = self.Compatibility:GetCharacterParts()
    local recovered = humanoid
        and humanoid.MaxHealth > 0
        and humanoid.Health / humanoid.MaxHealth * 100 >= 80
    if recovered then
        self.LowHealthRetreatLatched = false
        self.LowHealthRetreatPending = false
    end
    if self.Report then
        self.Report(
            recovered
                and "Health recovered; resuming the current task."
                or "Low-health retreat ended; resuming the current task.",
            "info"
        )
    end
end

function MovementService:_StartLowHealthRetreat(character, humanoid, root)
    if self.LowHealthRetreatInProgress or not character or not humanoid or not root then
        return false
    end

    local settings = self.LowHealthRetreatSettings or {}
    local height = math.clamp(
        tonumber(settings.LowHealthRiseHeight) or 800,
        tonumber(settings.LowHealthRiseHeightMin) or 100,
        tonumber(settings.LowHealthRiseHeightMax) or 2000
    )
    local retreat = {
        Character = character,
        Humanoid = humanoid,
        Root = root,
        GoalY = root.Position.Y + height,
        HoldX = root.Position.X,
        HoldZ = root.Position.Z,
        Ascending = true,
        CollisionOriginals = {},
        PartConnections = {},
    }
    self.LowHealthRetreat = retreat
    self.LowHealthRetreatInProgress = true

    for _, descendant in ipairs(character:GetDescendants()) do
        self:_TrackLowHealthRetreatCollisionPart(retreat, descendant)
    end
    retreat.DescendantAddedConnection = character.DescendantAdded:Connect(function(descendant)
        if self.LowHealthRetreat == retreat then
            self:_TrackLowHealthRetreatCollisionPart(retreat, descendant)
        end
    end)
    retreat.Connection = self.Compatibility.RunService.Heartbeat:Connect(function(deltaTime)
        local ok, err = pcall(self._StepLowHealthRetreat, self, retreat, deltaTime)
        if not ok then
            if self.Report then
                self.Report("Low-health lift stopped safely: " .. tostring(err), "warning")
            end
            self:_FinishLowHealthRetreat()
        end
    end)
    if self.Report then
        self.Report(
            "Health is low; rising quickly and holding position until recovery.",
            "warning"
        )
    end
    return true
end

function MovementService:_StepLowHealthRetreat(retreat, deltaTime)
    if self.LowHealthRetreat ~= retreat then
        return
    end
    local character, humanoid, root = self.Compatibility:GetCharacterParts()
    if character ~= retreat.Character or humanoid ~= retreat.Humanoid or root ~= retreat.Root then
        self.LowHealthRetreatLatched = false
        self.LowHealthRetreatPending = false
        self:_FinishLowHealthRetreat()
        return
    end
    if humanoid.Health <= 0 then
        self.LowHealthRetreatLatched = false
        self.LowHealthRetreatPending = false
        self:_FinishLowHealthRetreat()
        return
    end
    if humanoid.MaxHealth > 0
        and humanoid.Health / humanoid.MaxHealth * 100 >= 80
    then
        self.LowHealthRetreatLatched = false
        self.LowHealthRetreatPending = false
        self:_FinishLowHealthRetreat()
        return
    end
    if root.Anchored then
        return
    end

    if retreat.Ascending then
        local remainingY = retreat.GoalY - root.Position.Y
        local frameTime = math.clamp(tonumber(deltaTime) or 0, 0, 0.1)
        local step = math.min(300 * frameTime, 30, math.max(remainingY, 0))
        local nextY = root.Position.Y + step
        if remainingY <= 1 or nextY >= retreat.GoalY then
            nextY = retreat.GoalY
            retreat.Ascending = false
        end
        local risePosition = Vector3.new(retreat.HoldX, nextY, retreat.HoldZ)
        root.CFrame = root.CFrame + (risePosition - root.Position)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return
    end

    local holdPosition = Vector3.new(retreat.HoldX, retreat.GoalY, retreat.HoldZ)
    root.CFrame = root.CFrame + (holdPosition - root.Position)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
end

function MovementService:RefreshLowHealthRetreat()
    if self.Destroyed then
        return false
    end
    local settings = self.LowHealthRetreatSettings or {}
    if settings.LowHealthRiseEnabled ~= true then
        self.LowHealthRetreatLatched = false
        self.LowHealthRetreatPending = false
        self:_FinishLowHealthRetreat()
        return false
    end

    local character, humanoid, root = self.Compatibility:GetCharacterParts()
    if not character or not humanoid or not root or humanoid.MaxHealth <= 0 then
        return false
    end
    local healthPercent = humanoid.Health / humanoid.MaxHealth * 100
    if healthPercent >= 80 then
        self.LowHealthRetreatPending = false
        self.LowHealthRetreatLatched = false
        if self.LowHealthRetreatInProgress then
            self:_FinishLowHealthRetreat()
        end
        return false
    end

    if self.LowHealthRetreatPending and next(self.LowHealthRetreatDeferrals) == nil then
        self.LowHealthRetreatPending = false
        return self:_StartLowHealthRetreat(character, humanoid, root)
    end
    if healthPercent > (tonumber(settings.LowHealthRiseThreshold) or 40)
        or self.LowHealthRetreatLatched
    then
        return false
    end

    self.LowHealthRetreatLatched = true
    if next(self.LowHealthRetreatDeferrals) ~= nil then
        self.LowHealthRetreatPending = true
        return true
    end
    return self:_StartLowHealthRetreat(character, humanoid, root)
end

function MovementService:Destroy()
    self.Destroyed = true
    self.LowHealthRetreatLatched = false
    self.LowHealthRetreatPending = false
    table.clear(self.LowHealthRetreatDeferrals)
    self:_FinishLowHealthRetreat()
    disconnect(self.LowHealthRetreatHumanoidConnection)
    disconnect(self.LowHealthRetreatChildAddedConnection)
    disconnect(self.LowHealthRetreatCharacterAddedConnection)
    disconnect(self.LowHealthRetreatCharacterRemovingConnection)
    self.LowHealthRetreatHumanoidConnection = nil
    self.LowHealthRetreatChildAddedConnection = nil
    self.LowHealthRetreatCharacterAddedConnection = nil
    self.LowHealthRetreatCharacterRemovingConnection = nil
    self:Cancel()
    self:SetFarmCollisionSuppression(false)
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
    if self.LowHealthRetreatInProgress then
        return true, "low-health lift is temporarily overriding movement"
    end
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

        local deferral = self:BeginLowHealthRetreatDeferral()
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
        self:EndLowHealthRetreatDeferral(deferral)
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
    if self.LowHealthRetreatInProgress then
        return true, "low-health retreat is holding position"
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
            local retreatOriginals = self.LowHealthRetreat
                and self.LowHealthRetreat.CollisionOriginals
            local retreatOriginal = retreatOriginals
                and retreatOriginals[descendant]
            if retreatOriginal ~= nil then
                collisionOriginals[descendant] = retreatOriginal
            else
                collisionOriginals[descendant] = descendant.CanCollide
            end
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
        then
            self.LastStallAt = os.clock()
            self:_Finish(active, true)
            self.Report("Movement interrupted by character replacement", "warning")
            return
        end

        if self.LowHealthRetreatInProgress
            and self.LowHealthRetreat
            and self.LowHealthRetreat.Character == character
        then
            active.BestDistance = (active.Goal.Position - root.Position).Magnitude
            active.LastProgressAt = os.clock()
            return
        end

        if root.Anchored then
            self.LastStallAt = os.clock()
            self:_Finish(active, true)
            self.Report("Movement interrupted because the character root is anchored", "warning")
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
