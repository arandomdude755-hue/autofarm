local StatusFeature = {}

local function getChildValue(parent, name)
    if not parent then
        return nil
    end
    local ok, child = pcall(function()
        return parent:FindFirstChild(name)
    end)
    if not ok or not child then
        return nil
    end
    local valueOk, value = pcall(function()
        return child.Value
    end)
    return valueOk and value or nil
end

local function displayValue(value)
    if value == nil or tostring(value) == "" then
        return "Unavailable"
    end
    return tostring(value)
end

local function findChild(parent, name, recursive)
    if not parent then
        return nil
    end
    local ok, child = pcall(function()
        return parent:FindFirstChild(name, recursive == true)
    end)
    return ok and child or nil
end

local function readProperty(instance, name)
    if not instance then
        return nil
    end
    local ok, value = pcall(function()
        return instance[name]
    end)
    return ok and value or nil
end

local function formatDuration(totalSeconds)
    local seconds = math.max(0, math.floor(tonumber(totalSeconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    local remainder = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, remainder)
end

local function readGuiTimer(compatibility, timerName)
    local playerGui = compatibility and type(compatibility.GetPlayerGui) == "function"
        and compatibility:GetPlayerGui()
        or nil
    local main = findChild(playerGui, "Main")
    if not main then
        return "Unavailable"
    end
    if main:IsA("ScreenGui") and not main.Enabled then
        return "Unavailable (HUD hidden)"
    end

    local topHud = findChild(main, "TopHUDList")
    local timer = findChild(topHud, timerName)
    if not timer then
        return "Unavailable"
    end
    if readProperty(timer, "Visible") ~= true then
        return "Not active"
    end

    local function timeFromText(text)
        if type(text) ~= "string" then
            return nil
        end
        return text:match("(%d+:%d%d:%d%d)") or text:match("(%d+:%d%d)")
    end

    local timerText = timeFromText(readProperty(timer, "Text"))
    if timerText then
        return "Active: " .. timerText
    end

    local descendantsOk, descendants = pcall(function()
        return timer:GetDescendants()
    end)
    if descendantsOk and type(descendants) == "table" then
        for _, descendant in ipairs(descendants) do
            local isText = false
            pcall(function()
                isText = descendant:IsA("TextLabel")
                    or descendant:IsA("TextButton")
                    or descendant:IsA("TextBox")
            end)
            if isText and readProperty(descendant, "Visible") ~= false then
                timerText = timeFromText(readProperty(descendant, "Text"))
                if timerText then
                    return "Active: " .. timerText
                end
            end
        end
    end
    return "Active (countdown text unavailable)"
end

local function readLegendaryItemEstimate(workspace)
    local worldOrigin = findChild(workspace, "_WorldOrigin")
    local locations = findChild(worldOrigin, "Locations")
    if not locations then
        return "Unavailable"
    end

    local oldestTimeIn
    local childrenOk, children = pcall(function()
        return locations:GetChildren()
    end)
    if not childrenOk or type(children) ~= "table" then
        return "Unavailable"
    end
    for _, location in ipairs(children) do
        local value
        pcall(function()
            value = location:GetAttribute("TimeIn")
        end)
        value = tonumber(value)
        if value and (not oldestTimeIn or value < oldestTimeIn) then
            oldestTimeIn = value
        end
    end
    if not oldestTimeIn then
        return "Unavailable (no TimeIn markers)"
    end

    local nowOk, now = pcall(os.time)
    now = nowOk and tonumber(now) or nil
    if not now or oldestTimeIn < 1000000000 then
        return "Unavailable (unrecognized TimeIn data)"
    end
    local elapsed = now - oldestTimeIn
    if elapsed < 0 or elapsed > 30 * 24 * 60 * 60 then
        return "Unavailable (TimeIn data is stale)"
    end

    local cycleSeconds = 4 * 60 * 60
    local remaining = cycleSeconds - (elapsed % cycleSeconds)
    return formatDuration(remaining) .. " (estimate)"
end

local function readMoonStatus()
    local lighting
    pcall(function()
        lighting = game:GetService("Lighting")
    end)
    if not lighting then
        return "Unavailable"
    end

    local phase
    pcall(function()
        phase = lighting:GetAttribute("MoonPhase")
    end)
    local phaseNumber = tonumber(phase)
    local phaseText
    if phaseNumber == 5 then
        phaseText = "Full Moon"
    elseif phaseNumber == 4 then
        phaseText = "Next Night"
    elseif phaseNumber ~= nil then
        phaseText = "Other phase"
    else
        local sky
        pcall(function()
            sky = lighting:FindFirstChildOfClass("Sky")
        end)
        local textureId = readProperty(sky, "MoonTextureId")
        local textureNumber = type(textureId) == "string"
            and textureId:match("%d+$")
            or nil
        if textureNumber == "9709149431" then
            phaseText = "Full Moon"
        elseif textureNumber == "9709149052" then
            phaseText = "Next Night"
        else
            phaseText = "Unknown phase"
        end
    end

    local clockTime = tonumber(readProperty(lighting, "ClockTime"))
    if not clockTime then
        return phaseText
    end
    local hours = math.floor(clockTime) % 24
    local minutes = math.floor((clockTime - math.floor(clockTime)) * 60 + 0.5)
    if minutes >= 60 then
        hours = (hours + 1) % 24
        minutes = 0
    end
    return phaseText .. " | game clock " .. string.format("%02d:%02d", hours, minutes)
end

local function readTikiEyes(map)
    local tiki = findChild(map, "TikiOutpost")
    local islandModel = findChild(tiki, "IslandModel", true)
    if not islandModel then
        return "Unavailable (island not loaded)"
    end
    local cleared = 0
    for index = 1, 4 do
        local eye = findChild(islandModel, "Eye" .. tostring(index), true)
        if not eye then
            return "Unavailable (eye markers incomplete)"
        end
        local transparency = tonumber(readProperty(eye, "Transparency"))
        if transparency == nil then
            return "Unavailable"
        end
        if transparency == 1 then
            cleared += 1
        end
    end
    return tostring(cleared) .. " / 4 cleared"
end

local function readWorldEventValues(context)
    local compatibility = context and context.Compatibility
    local workspace = compatibility and compatibility.Workspace
    local map = findChild(workspace, "Map")
    local worldOrigin = findChild(workspace, "_WorldOrigin")
    local locations = findChild(worldOrigin, "Locations")
    local distributedTime = tonumber(readProperty(workspace, "DistributedGameTime"))
    local mirage = findChild(map, "MysticIsland")
    local prehistoric = findChild(map, "PrehistoricIsland")
    local frozenDimension = findChild(locations, "Frozen Dimension")

    local function presence(value, unavailable)
        if unavailable then
            return "Unavailable (map not loaded)"
        end
        return value and "Present" or "Not present"
    end

    return {
        serverUptime = distributedTime and formatDuration(distributedTime) or "Unavailable",
        legendaryItemTimer = readLegendaryItemEstimate(workspace),
        moon = readMoonStatus(),
        raidTimer = readGuiTimer(compatibility, "RaidTimer"),
        prehistoricTimer = readGuiTimer(compatibility, "PrehistoricRaidTimer"),
        mirageIsland = presence(mirage, not map),
        prehistoricIsland = presence(prehistoric, not map),
        frozenDimension = presence(frozenDimension, not locations),
        tikiEyes = readTikiEyes(map),
    }
end

local function getSea(compatibility)
    local checks = {
        { Name = "First Sea", Method = "IsFirstSea" },
        { Name = "Second Sea", Method = "IsSecondSea" },
        { Name = "Third Sea", Method = "IsThirdSea" },
    }
    local matched
    for _, check in ipairs(checks) do
        local method = compatibility and compatibility[check.Method]
        if type(method) == "function" then
            local ok, isSea = pcall(method, compatibility)
            if ok and isSea == true then
                if matched then
                    return "Unknown (multiple sea checks matched)"
                end
                matched = check.Name
            end
        end
    end
    return matched or "Unknown"
end

local function getCharacterStatus(character)
    if not character then
        return "Not spawned"
    end
    local humanoid = character:FindFirstChildWhichIsA("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then
        return "Loading"
    end
    if humanoid.Health <= 0 then
        return "Respawning"
    end
    return "Alive"
end

function StatusFeature:_ReadValues()
    local context = self.Context
    local compatibility = context and context.Compatibility
    local player = compatibility and compatibility.Player
    local playerData = player and player:FindFirstChild("Data")
    local level = getChildValue(playerData, "Level")
    local race = getChildValue(playerData, "Race")
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
    local health = "Unavailable"
    if humanoid then
        local currentHealth = tonumber(humanoid.Health)
        local maxHealth = tonumber(humanoid.MaxHealth)
        if currentHealth and maxHealth then
            health = string.format(
                "%d / %d",
                math.floor(currentHealth + 0.5),
                math.floor(maxHealth + 0.5)
            )
        end
    end

    local snapshot = context.State:GetSnapshot()
    local farmSettings = context.Config and context.Config.FarmSettings or {}
    local playersService = compatibility and compatibility.Players
    local playerCount = "Unavailable"
    local maxPlayers = "Unavailable"
    if playersService then
        local countOk, count = pcall(function()
            return #playersService:GetPlayers()
        end)
        if countOk then
            playerCount = tostring(count)
        end
        local maxOk, maximum = pcall(function()
            return playersService.MaxPlayers
        end)
        if maxOk and tonumber(maximum) then
            maxPlayers = tostring(maximum)
        end
    end

    local placeId = "Unavailable"
    local jobId = ""
    pcall(function()
        placeId = tostring(game.PlaceId)
        jobId = tostring(game.JobId)
    end)
    local shortJobId = jobId ~= "" and (jobId:sub(1, 12) .. "…") or "Unavailable"
    local questDetails = {
        State = "unknown",
        Target = nil,
        Title = "Unavailable",
        Progress = "Unavailable",
        Reader = "Quest service unavailable",
    }
    local questDialogue = "Unavailable"
    local questService = context.MainFarm and context.MainFarm.QuestService
    if questService then
        local detailsOk, details = pcall(questService.GetActiveQuestDetails, questService)
        if detailsOk and type(details) == "table" then
            questDetails = details
        else
            local stateOk, state, target, reader = pcall(
                questService.GetActiveQuestState,
                questService
            )
            if stateOk then
                questDetails.State = state or "unknown"
                questDetails.Target = target
                questDetails.Reader = reader or "Quest reader unavailable"
            end
        end
        local dialogueOk, dialogueOpen = pcall(
            questService.IsQuestGiverDialogueOpen,
            questService
        )
        if dialogueOk then
            questDialogue = dialogueOpen and "Open" or "Closed"
        end
    end
    local questStateLabels = {
        active = "Active",
        none = "No active quest",
        unknown = "Unknown",
        ["active-unknown"] = "Active (details unavailable)",
    }
    local worldEvents = readWorldEventValues(context)

    return {
        sea = getSea(compatibility),
        level = displayValue(level),
        race = displayValue(race),
        character = getCharacterStatus(character),
        health = health,
        autoFarm = snapshot.featureEnabled["farm.main"] and "On" or "Off",
        farmMastery = farmSettings.FarmMastery == true and "On" or "Off",
        farmMaterials = farmSettings.FarmMaterialsEnabled == true and "On" or "Off",
        questState = questStateLabels[questDetails.State] or "Unknown",
        questTitle = questDetails.Title or "Unavailable",
        questTarget = questDetails.Target
            or (questDetails.State == "none" and "None" or "Unavailable"),
        questProgress = questDetails.Progress or "Unavailable",
        questReader = questDetails.Reader or "Quest reader unavailable",
        questDialogue = questDialogue,
        serverUptime = worldEvents.serverUptime,
        legendaryItemTimer = worldEvents.legendaryItemTimer,
        moon = worldEvents.moon,
        raidTimer = worldEvents.raidTimer,
        prehistoricTimer = worldEvents.prehistoricTimer,
        mirageIsland = worldEvents.mirageIsland,
        prehistoricIsland = worldEvents.prehistoricIsland,
        frozenDimension = worldEvents.frozenDimension,
        tikiEyes = worldEvents.tikiEyes,
        players = playerCount .. " / " .. maxPlayers,
        placeId = placeId,
        jobId = shortJobId,
        fullJobId = jobId ~= "" and jobId or "Unavailable",
    }
end

function StatusFeature:_BuildReport(values)
    local lines = {
        "===== [StatusReport] REPORT BEGIN =====",
        "Sea: " .. values.sea,
        "Level: " .. values.level,
        "Race: " .. values.race,
        "Character: " .. values.character,
        "Health: " .. values.health,
        "Auto Farm: " .. values.autoFarm,
        "Farm Mastery: " .. values.farmMastery,
        "Farm Materials: " .. values.farmMaterials,
        "Quest: " .. values.questState,
        "Quest title: " .. values.questTitle,
        "Quest target: " .. values.questTarget,
        "Quest progress: " .. values.questProgress,
        "Quest reader: " .. values.questReader,
        "Quest dialogue: " .. values.questDialogue,
        "Server uptime: " .. values.serverUptime,
        "Next legendary item: " .. values.legendaryItemTimer,
        "Moon: " .. values.moon,
        "Raid timer: " .. values.raidTimer,
        "Prehistoric timer: " .. values.prehistoricTimer,
        "Mirage Island: " .. values.mirageIsland,
        "Prehistoric Island: " .. values.prehistoricIsland,
        "Frozen Dimension: " .. values.frozenDimension,
        "Tiki eyes: " .. values.tikiEyes,
        "Players: " .. values.players,
        "Place ID: " .. values.placeId,
        "Server Job ID: " .. values.fullJobId,
        "===== [StatusReport] REPORT END =====",
    }
    return table.concat(lines, "\n")
end

function StatusFeature:Initialize(context)
    self.Context = context
    self._generation = (self._generation or 0) + 1
    local generation = self._generation
    context.State:SetStatusValues(self:_ReadValues())
    task.spawn(function()
        while self.Context == context and self._generation == generation do
            task.wait(1)
            if self.Context == context and self._generation == generation then
                local snapshot = context.State:GetSnapshot()
                if snapshot.selectedTab == "StatusServer" then
                    context.State:SetStatusValues(self:_ReadValues())
                end
            end
        end
    end)
    return true
end

function StatusFeature:Handle(actionId)
    if actionId ~= "status.refresh" and actionId ~= "status.copy" then
        return false
    end
    local values = self:_ReadValues()
    self.Context.State:SetStatusValues(values)
    if actionId == "status.refresh" then
        self.Context.State:SetStatus("Status refreshed.", "success")
        return true
    end

    local report = self:_BuildReport(values)
    local copied = false
    local clipboardOk = pcall(function()
        if type(setclipboard) == "function" then
            setclipboard(report)
            copied = true
        end
    end)
    if clipboardOk and copied then
        self.Context.State:SetStatus("Status report copied to clipboard.", "success")
    else
        print(report)
        self.Context.State:SetStatus("Clipboard unavailable; status report printed to output.", "warning")
    end
    return true
end

function StatusFeature:Cleanup()
    self._generation = (self._generation or 0) + 1
    self.Context = nil
end

return StatusFeature
