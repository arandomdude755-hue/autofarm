local ServerHopService = {}
ServerHopService.__index = ServerHopService

local INITIAL_SCAN_DELAY = 6
local ARRIVAL_SCAN_DELAY = 8
local RETRY_DELAY = 3
local PAGE_DELAY = 0.5
local TELEPORT_TIMEOUT = 25
local SESSION_LIFETIME = 3600
local MAX_VISITED_SERVERS = 300
local MAX_PERSISTED_VISITED_SERVERS = 40

local function shortError(value)
    local message = tostring(value or "unknown error"):gsub("[%c]", " ")
    if #message > 180 then
        message = message:sub(1, 177) .. "..."
    end
    return message
end

local function validJobId(value)
    return type(value) == "string"
        and #value > 0
        and #value <= 128
        and not value:find("[%c]")
end

function ServerHopService.new(compatibility, settingsPersistence, setStatus, coordinator)
    return setmetatable({
        Compatibility = compatibility,
        SettingsPersistence = settingsPersistence,
        SetStatus = setStatus,
        Coordinator = coordinator,
        CoordinatorLease = nil,
        Settings = nil,
        Session = nil,
        ResumePending = false,
        Fetching = false,
        InFlight = false,
        PendingJobId = nil,
        PendingDeadline = 0,
        NextAttemptAt = 0,
        PageCount = 0,
        Generation = 0,
        Destroyed = false,
        TeleportFailureConnection = nil,
        LastErrorStatus = nil,
    }, ServerHopService)
end

function ServerHopService:_SetStatus(message, kind)
    if type(self.SetStatus) == "function" then
        pcall(self.SetStatus, message, kind or "info")
    end
end

function ServerHopService:_ReleaseCoordinatorLease()
    if self.Coordinator and self.CoordinatorLease then
        self.Coordinator:Release(self.CoordinatorLease)
    end
    self.CoordinatorLease = nil
end

function ServerHopService:OwnsLease(lease)
    return lease ~= nil and self.CoordinatorLease == lease
end

function ServerHopService:_ReadModes()
    local settings = self.Settings or {}
    return {
        EliteHunter = settings.HopForEliteHunter == true,
        Berry = settings.HopForBerries == true,
    }
end

function ServerHopService:_HasEnabledMode()
    local modes = self:_ReadModes()
    return modes.EliteHunter or modes.Berry
end

function ServerHopService:_ModeLabel()
    local modes = self:_ReadModes()
    if modes.EliteHunter and modes.Berry then
        return "Elite Hunters and berries"
    elseif modes.EliteHunter then
        return "Elite Hunters"
    elseif modes.Berry then
        return "berries"
    end
    return "targets"
end

function ServerHopService:_IsThirdSea()
    local compatibility = self.Compatibility
    if not compatibility or type(compatibility.IsThirdSea) ~= "function" then
        return false
    end
    local ok, result = pcall(compatibility.IsThirdSea, compatibility)
    return ok and result == true
end

function ServerHopService:_CopySession(session)
    if type(session) ~= "table" then
        return nil
    end
    local copy = {
        PlaceId = session.PlaceId,
        ExpiresAt = session.ExpiresAt,
        Modes = {
            EliteHunter = session.Modes and session.Modes.EliteHunter == true,
            Berry = session.Modes and session.Modes.Berry == true,
        },
        Visited = {},
        Cursor = session.Cursor,
        PendingJobId = session.PendingJobId,
    }
    for _, jobId in ipairs(session.Visited or {}) do
        if validJobId(jobId) then
            copy.Visited[#copy.Visited + 1] = jobId
            if #copy.Visited >= MAX_VISITED_SERVERS then
                break
            end
        end
    end
    return copy
end

function ServerHopService:_SaveSession()
    local persistence = self.SettingsPersistence
    if not persistence or type(persistence.SetHopSession) ~= "function" then
        return false, "Settings storage is unavailable"
    end
    local copy = self:_CopySession(self.Session)
    if not copy then
        return false, "Hop session is unavailable"
    end
    if #copy.Visited > MAX_PERSISTED_VISITED_SERVERS then
        local recent = {}
        for index = #copy.Visited - MAX_PERSISTED_VISITED_SERVERS + 1, #copy.Visited do
            recent[#recent + 1] = copy.Visited[index]
        end
        copy.Visited = recent
    end
    copy.ExpiresAt = os.time() + SESSION_LIFETIME
    self.Session.ExpiresAt = copy.ExpiresAt
    local ok, saved, saveError = pcall(
        persistence.SetHopSession,
        persistence,
        copy
    )
    if not ok then
        return false, "Settings storage could not save the search session"
    end
    return saved, saveError
end

function ServerHopService:_ClearSavedSession()
    local persistence = self.SettingsPersistence
    if persistence and type(persistence.ClearHopSession) == "function" then
        pcall(persistence.ClearHopSession, persistence)
    end
    self.Session = nil
    self.PendingJobId = nil
    self.PendingDeadline = 0
    self.InFlight = false
    self:_ReleaseCoordinatorLease()
end

function ServerHopService:_EnsureSession()
    if self.Session then
        self.Session.Modes = self:_ReadModes()
        return self.Session
    end

    local modes = self:_ReadModes()
    if not modes.EliteHunter and not modes.Berry then
        return nil
    end

    local currentJobId = tostring(game.JobId or "")
    self.Session = {
        PlaceId = tonumber(game.PlaceId),
        ExpiresAt = os.time() + SESSION_LIFETIME,
        Modes = modes,
        Visited = {},
        Cursor = nil,
    }
    if validJobId(currentJobId) then
        self.Session.Visited[1] = currentJobId
    end
    return self.Session
end

function ServerHopService:_MarkVisited(jobId)
    if not self.Session or not validJobId(jobId) then
        return
    end
    for _, existing in ipairs(self.Session.Visited) do
        if existing == jobId then
            return
        end
    end
    table.insert(self.Session.Visited, jobId)
    while #self.Session.Visited > MAX_VISITED_SERVERS do
        table.remove(self.Session.Visited, 1)
    end
end

function ServerHopService:_IsVisited(jobId)
    for _, existing in ipairs((self.Session and self.Session.Visited) or {}) do
        if existing == jobId then
            return true
        end
    end
    return false
end

function ServerHopService:_SetModesOnSavedSession()
    if not self.Session then
        return
    end
    self.Session.Modes = self:_ReadModes()
    if not self.Session.Modes.EliteHunter and not self.Session.Modes.Berry then
        self:_ClearSavedSession()
        return
    end
    if self.Session.PendingJobId then
        local saved = self:_SaveSession()
        if not saved then
            self:_SetStatus(
                "Server search couldn't save its next hop; it will try again.",
                "warning"
            )
        end
    end
end

function ServerHopService:_FailPending(message)
    if not self.PendingJobId then
        return
    end
    self:_MarkVisited(self.PendingJobId)
    self.PendingJobId = nil
    self.PendingDeadline = 0
    self.InFlight = false
    if self.Session then
        self.Session.PendingJobId = nil
        self.Session.Modes = self:_ReadModes()
        self:_SaveSession()
    end
    self.NextAttemptAt = os.clock() + RETRY_DELAY
    self:_SetStatus(message or "That server could not be joined; trying another.", "warning")
    self:_ReleaseCoordinatorLease()
end

function ServerHopService:_OnTeleportInitFailed(player, teleportResult, errorMessage)
    if player ~= self.Compatibility.Player or not self.PendingJobId then
        return
    end
    local reason = errorMessage or teleportResult or "Roblox rejected the join"
    self:_FailPending(
        "Roblox rejected the server join (" .. shortError(reason) .. "); trying another."
    )
end

function ServerHopService:Initialize(settings)
    self.Settings = settings or {}
    self.Destroyed = false

    local teleportService
    pcall(function()
        teleportService = game:GetService("TeleportService")
    end)
    if teleportService and teleportService.TeleportInitFailed then
        local connectOk, connection = pcall(function()
            return teleportService.TeleportInitFailed:Connect(function(...)
                self:_OnTeleportInitFailed(...)
            end)
        end)
        if connectOk then
            self.TeleportFailureConnection = connection
        end
    end

    local persistence = self.SettingsPersistence
    local savedSession
    if persistence and type(persistence.GetHopSession) == "function" then
        local readOk, session = pcall(persistence.GetHopSession, persistence)
        if readOk then
            savedSession = session
        end
    end
    local currentJobId = tostring(game.JobId or "")
    local modes = self:_ReadModes()
    local shouldResume = savedSession ~= nil
        and tonumber(savedSession.PlaceId) == tonumber(game.PlaceId)
        and savedSession.PendingJobId == currentJobId
        and savedSession.ExpiresAt > os.time()
        and self:_IsThirdSea()
        and (modes.EliteHunter or modes.Berry)

    if shouldResume then
        self.Session = self:_CopySession(savedSession)
        self.Session.PendingJobId = nil
        self.ResumePending = true
        self.NextAttemptAt = os.clock() + ARRIVAL_SCAN_DELAY
        self:_MarkVisited(currentJobId)
        return true
    end

    if savedSession then
        self:_ClearSavedSession()
    end
    return true
end

function ServerHopService:ShouldResume()
    return self.ResumePending == true
end

function ServerHopService:ConsumeResume()
    if not self.ResumePending then
        return false
    end
    self.ResumePending = false
    if self.Session then
        self.Session.PendingJobId = nil
        self.Session.Modes = self:_ReadModes()
        self:_SaveSession()
    end
    self.NextAttemptAt = os.clock() + ARRIVAL_SCAN_DELAY
    self:_SetStatus("Checking this server for " .. self:_ModeLabel(), "info")
    return true
end

function ServerHopService:CancelResume()
    if not self.ResumePending then
        return false
    end
    self.ResumePending = false
    self:_ClearSavedSession()
    return true
end

function ServerHopService:SetEnabled(mode, enabled)
    if mode ~= "EliteHunter" and mode ~= "Berry" then
        return false, "Unsupported server search mode"
    end
    if type(enabled) ~= "boolean" then
        return false, "Server search setting is invalid"
    end
    if enabled then
        if not self:_IsThirdSea() then
            return false, "Elite Hunter and berry hopping is only available in Third Sea"
        end
        local persistence = self.SettingsPersistence
        if not persistence
            or type(persistence.CanPersistHopSession) ~= "function"
            or not persistence:CanPersistHopSession()
        then
            return false, "Server hopping needs local settings storage to resume after joining"
        end
    end

    self.NextAttemptAt = enabled
        and math.max(self.NextAttemptAt or 0, os.clock() + INITIAL_SCAN_DELAY)
        or self.NextAttemptAt
    self.Generation += 1
    self:_SetModesOnSavedSession()
    if not self:_HasEnabledMode() then
        self:_ClearSavedSession()
    elseif enabled then
        self:_SetStatus("Checking this server before searching for another", "info")
    end
    return true
end

function ServerHopService:HasEnabledModes()
    return self:_HasEnabledMode()
end

function ServerHopService:OnStackTaskStarted(kind)
    if (kind == "EliteHunter" and self:_ReadModes().EliteHunter)
        or (kind == "Berry" and self:_ReadModes().Berry)
    then
        self.NextAttemptAt = os.clock() + 2
    end
end

function ServerHopService:_BeginFetch()
    if self.Fetching or self.Destroyed then
        return
    end
    local session = self:_EnsureSession()
    if not session then
        return
    end
    if self.Coordinator and not self.CoordinatorLease then
        local lease = self.Coordinator:TryAcquire(
            "StackFarming",
            "Checking public servers",
            "StackFarm"
        )
        if not lease then
            return
        end
        self.CoordinatorLease = lease
    end
    self.Fetching = true
    local cursor = session.Cursor
    local generation = self.Generation
    self:_SetStatus("Checking public servers for " .. self:_ModeLabel(), "info")
    task.spawn(function()
        local callOk, result, fetchError = pcall(function()
            return self.Compatibility:GetPublicServers(cursor)
        end)
        if not callOk then
            fetchError = result
            result = nil
        end
        if self.Destroyed then
            self.Fetching = false
            self:_ReleaseCoordinatorLease()
            return
        end
        self.Fetching = false
        if generation ~= self.Generation then
            self:_ReleaseCoordinatorLease()
            return
        end
        if not self:_HasEnabledMode() then
            self:_ReleaseCoordinatorLease()
            return
        end
        if not result then
            if not self.LastErrorStatus then
                self.LastErrorStatus = true
                self:_SetStatus(
                    "Can't check public servers for place "
                        .. tostring(game.PlaceId)
                        .. " ("
                        .. shortError(fetchError)
                        .. "); retrying shortly.",
                    "warning"
                )
            end
            self.NextAttemptAt = os.clock() + 12
            self:_ReleaseCoordinatorLease()
            return
        end

        self.LastErrorStatus = nil
        local candidates = {}
        for _, server in ipairs(result.Servers or {}) do
            local jobId = type(server) == "table" and server.id
            local playing = type(server) == "table" and tonumber(server.playing)
            local maxPlayers = type(server) == "table" and tonumber(server.maxPlayers)
            if validJobId(jobId)
                and jobId ~= tostring(game.JobId)
                and not self:_IsVisited(jobId)
                and playing ~= nil
                and maxPlayers ~= nil
                and playing < maxPlayers
            then
                candidates[#candidates + 1] = jobId
            end
        end

        if #candidates == 0 then
            session.Cursor = result.NextCursor
            self.PageCount += 1
            if session.Cursor then
                local pause = PAGE_DELAY
                if self.PageCount >= 4 then
                    self.PageCount = 0
                    pause = 5
                    self:_SetStatus("Still checking public servers", "info")
                end
                self.NextAttemptAt = os.clock() + pause
                self:_ReleaseCoordinatorLease()
                return
            end

            session.Visited = {}
            self:_MarkVisited(tostring(game.JobId or ""))
            self.PageCount = 0
            self.NextAttemptAt = os.clock() + 8
            self:_SetStatus("No new public servers found; checking again shortly", "warning")
            self:_ReleaseCoordinatorLease()
            return
        end

        session.Cursor = result.NextCursor
        local jobId = candidates[math.random(1, #candidates)]
        self:_MarkVisited(jobId)
        session.PendingJobId = jobId
        session.Modes = self:_ReadModes()
        local saved, saveError = self:_SaveSession()
        if not saved then
            session.PendingJobId = nil
            self.NextAttemptAt = os.clock() + 12
            self:_SetStatus(
                "Server hopping can't continue because the search session couldn't be saved.",
                "error"
            )
            self:_ReleaseCoordinatorLease()
            return
        end

        self.PendingJobId = jobId
        self.PendingDeadline = os.clock() + TELEPORT_TIMEOUT
        self.InFlight = true
        self:_SetStatus("Joining another public server to check for targets", "info")
        local teleportCallOk, joined, joinError = pcall(function()
            return self.Compatibility:TeleportToPublicServer(jobId)
        end)
        if not teleportCallOk or not joined then
            if not teleportCallOk then
                joinError = joined
            end
            self:_FailPending(
                "Couldn't start the server hop ("
                    .. shortError(joinError)
                    .. "); trying another."
            )
        end
    end)
end

function ServerHopService:Step()
    if self.Destroyed or not self:_HasEnabledMode() then
        return false
    end
    if not self:_IsThirdSea() then
        self:_SetStatus("Server search is only available in Third Sea", "warning")
        self.NextAttemptAt = os.clock() + 30
        return false
    end

    if self.InFlight then
        if tostring(game.JobId or "") == self.PendingJobId then
            self.InFlight = false
            self.PendingJobId = nil
            self.PendingDeadline = 0
            self.NextAttemptAt = os.clock() + ARRIVAL_SCAN_DELAY
            self:_ReleaseCoordinatorLease()
            return false
        end
        if os.clock() >= self.PendingDeadline then
            self:_FailPending("The server join timed out; trying another server")
        else
            return true
        end
    end
    if self.Fetching or os.clock() < self.NextAttemptAt then
        return false
    end
    self:_BeginFetch()
    return false
end

function ServerHopService:Destroy()
    self.Destroyed = true
    self.Generation += 1
    self.Fetching = false
    self:_ReleaseCoordinatorLease()
    if self.TeleportFailureConnection then
        self.TeleportFailureConnection:Disconnect()
        self.TeleportFailureConnection = nil
    end
end

return ServerHopService
