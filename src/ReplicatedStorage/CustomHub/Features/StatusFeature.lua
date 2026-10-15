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
    if ok then
        return value
    end
    return nil
end

local function formatDuration(totalSeconds)
    local seconds = math.max(0, math.floor(tonumber(totalSeconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    local remainder = seconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, remainder)
end

local function formatCompactDuration(totalSeconds)
    local seconds = math.max(0, math.floor(tonumber(totalSeconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    elseif minutes > 0 then
        return tostring(minutes) .. "m"
    end
    return tostring(seconds % 60) .. "s"
end

local function formatServerAge(totalSeconds)
    local seconds = math.max(0, math.floor(tonumber(totalSeconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    local remainder = seconds % 60
    return string.format("%dh %dm %ds", hours, minutes, remainder)
end

local function getOldestLocationTime(workspace)
    local worldOrigin = findChild(workspace, "_WorldOrigin")
    local locations = findChild(worldOrigin, "Locations")
    if not locations then
        return nil
    end

    local oldestTimeIn
    local oldestLocation
    local childrenOk, children = pcall(function()
        return locations:GetChildren()
    end)
    if not childrenOk or type(children) ~= "table" then
        return nil
    end
    for _, location in ipairs(children) do
        local value
        pcall(function()
            value = location:GetAttribute("TimeIn")
        end)
        value = tonumber(value)
        if value and (not oldestTimeIn or value < oldestTimeIn) then
            oldestTimeIn = value
            oldestLocation = location
        end
    end
    return oldestTimeIn, oldestLocation
end

local function readServerElapsed(workspace)
    local oldestTimeIn = getOldestLocationTime(workspace)
    if not oldestTimeIn then
        return nil, "No TimeIn markers"
    end
    if oldestTimeIn < 1000000000 then
        return nil, "Unrecognized TimeIn data"
    end

    local function validElapsed(now)
        local elapsed = tonumber(now) and (tonumber(now) - oldestTimeIn) or nil
        if elapsed and elapsed >= 0 and elapsed <= 30 * 24 * 60 * 60 then
            return elapsed
        end
        return nil
    end

    -- Prefer Roblox's synchronized server clock for the same TimeIn marker BNN uses.
    local serverClockOk, serverNow = pcall(function()
        return workspace:GetServerTimeNow()
    end)
    if serverClockOk then
        local elapsed = validElapsed(serverNow)
        if elapsed then
            return elapsed
        end
    end

    -- Older runtimes may need BNN's tick() clock correction.
    local tickOk, correctedTick = pcall(function()
        return tick() - 25200
    end)
    if tickOk then
        local elapsed = validElapsed(correctedTick)
        if elapsed then
            return elapsed
        end
    end
    return nil, "TimeIn clock mismatch"
end

local LEGENDARY_ITEM_NAMES = {
    "God's Chalice",
    "Sweet Chalice",
    "Fist of Darkness",
}

local function findActiveLegendaryBoss(workspace)
    local enemies = findChild(workspace, "Enemies")
    local childrenOk, children = pcall(function()
        return enemies and enemies:GetChildren()
    end)
    if not childrenOk or type(children) ~= "table" then
        return nil
    end
    for _, enemy in ipairs(children) do
        local name = string.lower(tostring(enemy.Name))
        if string.find(name, "indra", 1, true)
            or string.find(name, "dough king", 1, true)
            or string.find(name, "darkbeard", 1, true)
        then
            local humanoid = enemy:FindFirstChildWhichIsA("Humanoid")
            if humanoid and humanoid.Health > 0 then
                return enemy.Name
            end
        end
    end
    return nil
end

local function collectHeldLegendaryItems(playersService, maxItems)
    local foundItems = {}
    if not playersService then
        return foundItems
    end
    local playersOk, players = pcall(function()
        return playersService:GetPlayers()
    end)
    if not playersOk or type(players) ~= "table" then
        return foundItems
    end

    for _, player in ipairs(players) do
        local containers = {}
        local character = readProperty(player, "Character")
        local backpack = findChild(player, "Backpack")
        if character then
            table.insert(containers, character)
        end
        if backpack then
            table.insert(containers, backpack)
        end
        for _, container in ipairs(containers) do
            for _, itemName in ipairs(LEGENDARY_ITEM_NAMES) do
                if findChild(container, itemName) then
                    local displayName = readProperty(player, "DisplayName")
                        or readProperty(player, "Name")
                        or "player"
                    local containerName = container == character and "Character" or "Backpack"
                    table.insert(foundItems, {
                        Item = itemName,
                        Holder = tostring(displayName),
                        Container = containerName,
                    })
                    if maxItems and #foundItems >= maxItems then
                        return foundItems
                    end
                end
            end
        end
    end
    return foundItems
end

local function findHeldLegendaryItem(playersService)
    local foundItems = collectHeldLegendaryItems(playersService, 1)
    local first = foundItems[1]
    if first then
        return first.Item, first.Holder, first.Container
    end
    return nil
end

local function readLegendaryItemStatus(context, workspace, elapsed)
    local bossName = findActiveLegendaryBoss(workspace)
    local playersService = context and context.Compatibility
        and context.Compatibility.Players
    local heldItem = findHeldLegendaryItem(playersService)
    local timerText
    if elapsed then
        local cycleSeconds = 4 * 60 * 60
        local untilNextCycle = cycleSeconds - (elapsed % cycleSeconds)
        timerText = "~" .. formatCompactDuration(untilNextCycle)
    end

    if bossName then
        return timerText
                and ("Next: " .. timerText .. "; summon active")
            or "Summon active"
    elseif heldItem then
        local shortName = heldItem == "God's Chalice" and "Chalice"
            or heldItem == "Fist of Darkness" and "Fist"
            or heldItem
        return timerText
                and ("Next: " .. timerText .. "; " .. shortName .. " held")
            or ("Held " .. shortName)
    elseif timerText then
        return "Next: " .. timerText
    end
    return "Timer unavailable"
end

local function formatNumber(value)
    local number = tonumber(value)
    if not number then
        return displayValue(value)
    end
    local integer = math.floor(number)
    local sign = integer < 0 and "-" or ""
    local digits = tostring(math.abs(integer))
    local reversed = digits:reverse():gsub("(%d%d%d)", "%1,")
    local formatted = reversed:reverse():gsub("^,", "")
    return sign .. formatted
end

local function updateMoonClockRate(statusFeature, clockTime)
    local now = os.clock()
    local sample = statusFeature._moonClockSample
    if not sample then
        statusFeature._moonClockSample = {
            clockTime = clockTime,
            sampledAt = now,
        }
    else
        local elapsed = now - sample.sampledAt
        if elapsed > 45 then
            statusFeature._moonSecondsPerGameHour = nil
            statusFeature._moonRateUpdatedAt = nil
            statusFeature._moonClockSample = {
                clockTime = clockTime,
                sampledAt = now,
            }
        elseif elapsed >= 3 then
            local clockHours = (clockTime - sample.clockTime) % 24
            if clockHours > 0.001 and clockHours < 6 then
                local measuredRate = elapsed / clockHours
                if measuredRate >= 1 and measuredRate <= 7200 then
                    local previousRate = statusFeature._moonSecondsPerGameHour
                    statusFeature._moonSecondsPerGameHour = previousRate
                        and previousRate * 0.7 + measuredRate * 0.3
                        or measuredRate
                    statusFeature._moonRateUpdatedAt = now
                end
            end
            statusFeature._moonClockSample = {
                clockTime = clockTime,
                sampledAt = now,
            }
        end
    end

    local rate = statusFeature._moonSecondsPerGameHour
    if not rate or now - (statusFeature._moonRateUpdatedAt or -math.huge) > 120 then
        return nil
    end
    return rate
end

local function sampleMoonClockRate(statusFeature)
    local lighting
    pcall(function()
        lighting = game:GetService("Lighting")
    end)
    local clockTime = tonumber(readProperty(lighting, "ClockTime"))
    if clockTime then
        updateMoonClockRate(statusFeature, clockTime)
    end
end

-- Keep BNN/Vxeze's phase boundaries, but convert them with measured clock speed.
local function moonForecast(phaseText, clockTime, phaseNumber)
    if phaseText == "Full Moon" then
        if clockTime <= 5 then
            return "Full Moon ends in", 5 - clockTime
        elseif clockTime < 12 then
            return "Fake Moon", nil
        elseif clockTime < 18 then
            return "Full Moon starts in", 18 - clockTime
        end
        return "Full Moon ends in", 30 - clockTime
    elseif phaseText == "Next Night" then
        local targetClock = clockTime <= 12 and 18 or 30
        return "Next Full Moon in", targetClock - clockTime
    end
    if phaseNumber ~= nil and phaseNumber ~= 5 then
        local nightsUntilFullMoon = (5 - phaseNumber) % 8
        if nightsUntilFullMoon > 0 then
            -- Use the same next-night boundary as BNN/Vxeze, then add one
            -- in-game day for each remaining moon phase.
            local targetClock = clockTime <= 12 and 18 or 30
            local hoursRemaining = targetClock - clockTime
                + math.max(0, nightsUntilFullMoon - 1) * 24
            return "Next Full Moon in", hoursRemaining
        end
    end
    return nil, nil
end

local function formatMoonEstimate(realSeconds)
    local seconds = math.max(0, math.floor((tonumber(realSeconds) or 0) + 0.5))
    if seconds < 60 then
        return "<1m"
    end
    local minutes = math.floor(seconds / 60)
    local hours = math.floor(minutes / 60)
    local remainingMinutes = minutes % 60
    if hours >= 24 then
        return string.format("~%dd %02dh", math.floor(hours / 24), hours % 24)
    end
    if hours > 0 then
        return string.format("~%dh %02dm", hours, remainingMinutes)
    end
    return string.format("~%dm", minutes)
end

local function readMoonStatus(statusFeature)
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
    local blueMoon = false
    pcall(function()
        blueMoon = lighting:GetAttribute("IsBlueMoon") == true
    end)
    if blueMoon then
        phaseText = "Blue Moon"
    elseif phaseNumber == 5 then
        phaseText = "Full Moon"
    elseif phaseNumber == 4 then
        phaseText = "Phase 4 (next night is Full Moon)"
    elseif phaseNumber ~= nil and phaseNumber >= 0 then
        local nightsUntilFullMoon = (5 - phaseNumber) % 8
        phaseText = string.format(
            "Phase %d (%d nights until Full Moon)",
            phaseNumber,
            nightsUntilFullMoon
        )
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
            phaseText = "Phase 4 (next night is Full Moon)"
        else
            phaseText = "Unknown phase"
        end
    end

    local clockTime = tonumber(readProperty(lighting, "ClockTime"))
    local displayPhase = phaseText:match("^(Phase %d+)") or phaseText
    if not clockTime then
        return displayPhase .. " · Calculating"
    end

    if phaseText == "Blue Moon" then
        return "Blue Moon"
    end

    local forecastPhase = phaseNumber
    if phaseText == "Phase 4 (next night is Full Moon)" then
        forecastPhase = 4
    elseif phaseText == "Full Moon" then
        forecastPhase = 5
    end
    local label, hoursRemaining = moonForecast(phaseText, clockTime, forecastPhase)
    if label == "Fake Moon" then
        return "Full Moon · Fake Moon"
    end
    if not label or not hoursRemaining then
        return displayPhase .. " · Calculating"
    end

    local rate = updateMoonClockRate(statusFeature, clockTime)
    if not rate then
        return displayPhase .. " · Calculating"
    end
    local forecastLabel = label
    if label == "Next Full Moon in" then
        forecastLabel = "Full Moon in"
    elseif label == "Full Moon ends in" then
        forecastLabel = "Ends in"
    elseif label == "Full Moon starts in" then
        forecastLabel = "Starts in"
    end
    return displayPhase .. " · " .. forecastLabel .. " "
        .. formatMoonEstimate(hoursRemaining * rate)
end

local function readTikiEyes(map, statusFeature)
    local serverId
    pcall(function()
        serverId = tostring(game.JobId)
    end)
    if serverId == "" then
        serverId = nil
    end

    local cached = statusFeature and statusFeature._tikiEyesCache
    if cached and serverId and cached.ServerId ~= serverId then
        statusFeature._tikiEyesCache = nil
        cached = nil
    end
    local cachedValue = cached
            and serverId
            and cached.ServerId == serverId
            and cached.Value
        or nil

    local tiki = findChild(map, "TikiOutpost")
    local islandModel = findChild(tiki, "IslandModel", true)
    if not islandModel then
        return cachedValue or "Not loaded"
    end
    local cleared = 0
    local found = 0
    for index = 1, 4 do
        local eye = findChild(islandModel, "Eye" .. tostring(index), true)
        if eye then
            found += 1
            local transparency = tonumber(readProperty(eye, "Transparency"))
            if transparency == 1 then
                cleared += 1
            end
        end
    end
    if found == 0 then
        return cachedValue or "Not loaded"
    end

    if cached and cached.ServerId == serverId then
        cleared = math.max(cleared, cached.Cleared)
        found = math.max(found, cached.Found)
    end
    local value = tostring(cleared) .. " / 4 cleared"
    if found < 4 then
        value ..= " (Partial)"
    end
    if statusFeature and serverId then
        statusFeature._tikiEyesCache = {
            ServerId = serverId,
            Cleared = cleared,
            Found = found,
            Value = value,
        }
    end
    return value
end

local ELITE_TARGET_NAMES = {
    "Deandre",
    "Urban",
    "Diablo",
}

local function isThirdSea(compatibility)
    local method = compatibility and compatibility.IsThirdSea
    if type(method) ~= "function" then
        return false
    end
    local ok, value = pcall(method, compatibility)
    return ok and value == true
end

local function findAliveElite(container)
    if not container then
        return nil
    end
    local childrenOk, children = pcall(function()
        return container:GetChildren()
    end)
    if not childrenOk or type(children) ~= "table" then
        return nil
    end
    for _, enemy in ipairs(children) do
        if enemy:IsA("Model") and table.find(ELITE_TARGET_NAMES, enemy.Name) then
            local humanoid = enemy:FindFirstChildWhichIsA("Humanoid")
            if enemy:FindFirstChild("HumanoidRootPart")
                and humanoid
                and humanoid.Health > 0
            then
                return enemy
            end
        end
    end
    return nil
end

local function readEliteHunterStatus(workspace, replicatedStorage, compatibility)
    if not isThirdSea(compatibility) then
        return "Third Sea only"
    end
    local storedElite = findAliveElite(replicatedStorage)
    if storedElite then
        return "Spawned: " .. storedElite.Name
    end

    local enemies = findChild(workspace, "Enemies")
    local liveElite = findAliveElite(enemies)
    if liveElite then
        return "Spawned: " .. liveElite.Name
    end
    return "Not spawned"
end

local function readEventPresence(marker)
    return marker and "Spawned" or "Not spawned"
end

local function readWorldEventValues(context, statusFeature)
    local compatibility = context and context.Compatibility
    local workspace = compatibility and compatibility.Workspace
    local replicatedStorage = compatibility and compatibility.ReplicatedStorage
    local map = findChild(workspace, "Map")
    local worldOrigin = findChild(workspace, "_WorldOrigin")
    local locations = findChild(worldOrigin, "Locations")
    local thirdSea = isThirdSea(compatibility)
    local serverElapsed = readServerElapsed(workspace)
    local mirage = findChild(map, "MysticIsland")
    local prehistoric = findChild(map, "PrehistoricIsland")
    local frozenDimension = findChild(locations, "Frozen Dimension")
    return {
        serverAge = serverElapsed and formatServerAge(serverElapsed) or "Unavailable",
        legendaryItemTimer = readLegendaryItemStatus(context, workspace, serverElapsed),
        moon = readMoonStatus(statusFeature),
        eliteHunter = readEliteHunterStatus(workspace, replicatedStorage, compatibility),
        mirageIsland = thirdSea
                and readEventPresence(mirage)
            or "Third Sea only",
        prehistoricIsland = thirdSea
                and readEventPresence(prehistoric)
            or "Third Sea only",
        frozenDimension = thirdSea
                and readEventPresence(frozenDimension)
            or "Third Sea only",
        tikiEyes = thirdSea and readTikiEyes(map, statusFeature) or "Third Sea only",
    }
end

local function safeFullName(instance)
    if not instance then
        return "missing"
    end
    local ok, name = pcall(function()
        return instance:GetFullName()
    end)
    return ok and tostring(name) or tostring(readProperty(instance, "Name") or "unknown")
end

local function readAttribute(instance, attributeName)
    if not instance then
        return nil
    end
    local ok, value = pcall(function()
        return instance:GetAttribute(attributeName)
    end)
    if ok then
        return value
    end
    return nil
end

local function rawNumber(value)
    local number = tonumber(value)
    return number and string.format("%.3f", number) or "unavailable"
end

local function stateText(value)
    if value == true then
        return "true"
    elseif value == false then
        return "false"
    end
    return "unavailable"
end

local function formatCycleRemaining(elapsed)
    local seconds = tonumber(elapsed)
    if not seconds or seconds < 0 then
        return "invalid"
    end
    local cycleSeconds = 4 * 60 * 60
    return formatDuration(cycleSeconds - (seconds % cycleSeconds))
end

local function appendClockDiagnostics(lines, workspace)
    table.insert(lines, "")
    table.insert(lines, "===== [Clock / Legendary Item Evidence] =====")
    local timeIn, oldestLocation = getOldestLocationTime(workspace)
    local worldOrigin = findChild(workspace, "_WorldOrigin")
    local locations = findChild(worldOrigin, "Locations")
    local timeInCount = 0
    local listedTimeIn = 0
    local childrenOk, children = pcall(function()
        return locations and locations:GetChildren()
    end)
    if childrenOk and type(children) == "table" then
        for _, location in ipairs(children) do
            local markerTime = tonumber(readAttribute(location, "TimeIn"))
            if markerTime then
                timeInCount += 1
                if listedTimeIn < 16 then
                    listedTimeIn += 1
                    table.insert(
                        lines,
                        "TimeIn marker: "
                            .. tostring(readProperty(location, "Name") or "unknown")
                            .. "; value="
                            .. rawNumber(markerTime)
                    )
                end
            end
        end
    end

    local serverClockOk, serverNow = pcall(function()
        return workspace:GetServerTimeNow()
    end)
    if not serverClockOk then
        serverNow = nil
    end
    local correctedTickOk, correctedTick = pcall(function()
        return tick() - 25200
    end)
    if not correctedTickOk then
        correctedTick = nil
    end
    local serverElapsed = timeIn and serverNow and (serverNow - timeIn) or nil
    local bnnElapsed = timeIn and correctedTick and (correctedTick - timeIn) or nil
    local serverElapsedValid = serverElapsed
        and serverElapsed >= 0
        and serverElapsed <= 30 * 24 * 60 * 60
    local bnnElapsedValid = bnnElapsed
        and bnnElapsed >= 0
        and bnnElapsed <= 30 * 24 * 60 * 60
    local selectedClock = serverElapsedValid
            and "Workspace:GetServerTimeNow()"
        or bnnElapsedValid
            and "tick() - 25200"
        or "none (clock mismatch)"

    table.insert(
        lines,
        "Oldest TimeIn marker: "
            .. safeFullName(oldestLocation)
            .. "; TimeIn="
            .. rawNumber(timeIn)
            .. "; total markers="
            .. tostring(timeInCount)
    )
    table.insert(lines, "GetServerTimeNow: " .. rawNumber(serverNow))
    table.insert(lines, "tick() - 25200: " .. rawNumber(correctedTick))
    table.insert(lines, "Selected elapsed-time clock: " .. selectedClock)
    table.insert(lines, "Server-clock elapsed seconds: " .. rawNumber(serverElapsed))
    table.insert(lines, "BNN-clock elapsed seconds: " .. rawNumber(bnnElapsed))
    table.insert(
        lines,
        "Server-clock next 4-hour boundary: "
            .. (serverElapsedValid and formatCycleRemaining(serverElapsed) or "unavailable")
    )
    table.insert(
        lines,
        "BNN-clock next 4-hour boundary: "
            .. (bnnElapsedValid and formatCycleRemaining(bnnElapsed) or "unavailable")
    )
    table.insert(
        lines,
        "Workspace.DistributedGameTime: "
            .. rawNumber(readProperty(workspace, "DistributedGameTime"))
    )
    if timeInCount > listedTimeIn then
        table.insert(lines, "TimeIn marker list truncated after " .. tostring(listedTimeIn))
    end
end

local function appendLegendaryItemDiagnostics(lines, context, workspace)
    local compatibility = context and context.Compatibility
    local playersService = compatibility and compatibility.Players
    local heldItems = collectHeldLegendaryItems(playersService)
    local activeBoss = findActiveLegendaryBoss(workspace)

    table.insert(lines, "")
    table.insert(lines, "===== [Legendary Item Observation] =====")
    if activeBoss then
        table.insert(lines, "Live summon observed in Workspace.Enemies: " .. tostring(activeBoss))
    else
        table.insert(lines, "Live summon observed in Workspace.Enemies: none")
    end
    if #heldItems == 0 then
        table.insert(
            lines,
            "Held Chalice/Fist scan: none found in visible player Character/Backpack containers"
        )
    else
        for _, item in ipairs(heldItems) do
            table.insert(
                lines,
                "Held item observed: "
                    .. item.Item
                    .. "; holder="
                    .. item.Holder
                    .. "; container="
                    .. item.Container
                    .. "; acquisition source=unknown"
            )
        end
    end
    table.insert(
        lines,
        "Possession does not establish chest origin; it may come from a chest, Elite Hunter, or another source."
    )
    table.insert(
        lines,
        "The four-hour countdown is a TimeIn-based estimate; it is not evidence that an item is absent or available."
    )
end

local function instancePresence(instance)
    if not instance then
        return "not present in this client view"
    end
    return "present; class="
        .. tostring(readProperty(instance, "ClassName") or "unknown")
        .. "; path="
        .. safeFullName(instance)
end

local function appendNamedDescendantMatches(lines, root, label)
    if not root then
        table.insert(lines, label .. " name scan: root unavailable")
        return
    end
    local descendantsOk, descendants = pcall(function()
        return root:GetDescendants()
    end)
    if not descendantsOk or type(descendants) ~= "table" then
        table.insert(lines, label .. " name scan: failed")
        return
    end

    local scanLimit = math.min(#descendants, 5000)
    local matches = 0
    local listed = 0
    local needles = {
        "tiki",
        "eye",
        "prehistoric",
        "mystic",
        "mirage",
        "frozen",
        "island",
    }
    for index = 1, scanLimit do
        local instance = descendants[index]
        local lowerName = string.lower(tostring(readProperty(instance, "Name") or ""))
        local matched = false
        for _, needle in ipairs(needles) do
            if string.find(lowerName, needle, 1, true) then
                matched = true
                break
            end
        end
        if matched then
            matches += 1
            if listed < 24 then
                listed += 1
                table.insert(
                    lines,
                    label
                        .. " matching node: "
                        .. tostring(readProperty(instance, "Name") or "unknown")
                        .. "; class="
                        .. tostring(readProperty(instance, "ClassName") or "unknown")
                        .. "; path="
                        .. safeFullName(instance)
                )
            end
        end
    end
    table.insert(
        lines,
        label
            .. " descendants scanned="
            .. tostring(scanLimit)
            .. "/"
            .. tostring(#descendants)
            .. "; relevant name matches="
            .. tostring(matches)
            .. (matches > listed and " (list capped at " .. tostring(listed) .. ")" or "")
    )
end

local function appendIslandDiagnostics(lines, context, remoteEvents)
    local compatibility = context and context.Compatibility
    local workspace = compatibility and compatibility.Workspace
    local map = findChild(workspace, "Map")
    local worldOrigin = findChild(workspace, "_WorldOrigin")
    local locations = findChild(worldOrigin, "Locations")
    local playerGui
    if compatibility and type(compatibility.GetPlayerGui) == "function" then
        local guiOk, gui = pcall(compatibility.GetPlayerGui, compatibility)
        if guiOk then
            playerGui = gui
        end
    end
    local mainGui = findChild(playerGui, "Main")
    local topHud = findChild(mainGui, "TopHUDList")

    table.insert(lines, "")
    table.insert(lines, "===== [Island / Event Detection Evidence] =====")
    table.insert(lines, "Workspace.Map: " .. instancePresence(map))
    table.insert(lines, "Workspace._WorldOrigin.Locations: " .. instancePresence(locations))
    appendNamedDescendantMatches(lines, map, "Workspace.Map")

    local locationsOk, locationChildren = pcall(function()
        return locations and locations:GetChildren()
    end)
    if locationsOk and type(locationChildren) == "table" then
        local listLimit = math.min(#locationChildren, 60)
        table.insert(
            lines,
            "World-origin location names (up to "
                .. tostring(listLimit)
                .. " of "
                .. tostring(#locationChildren)
                .. "):"
        )
        for index = 1, listLimit do
            local location = locationChildren[index]
            table.insert(
                lines,
                "Location: "
                    .. tostring(readProperty(location, "Name") or "unknown")
                    .. "; TimeIn="
                    .. rawNumber(readAttribute(location, "TimeIn"))
                    .. "; CFrame attribute="
                    .. (readAttribute(location, "CFrame") ~= nil and "present" or "absent")
            )
        end
        if #locationChildren > listLimit then
            table.insert(lines, "Location-name list truncated after " .. tostring(listLimit))
        end
    else
        table.insert(lines, "World-origin location names: unavailable")
    end

    local islandChecks = {
        { Label = "Tiki Outpost", MapName = "TikiOutpost", LocationNames = { "Tiki Outpost", "Tiki" } },
        { Label = "Prehistoric Island", MapName = "PrehistoricIsland", LocationNames = { "Prehistoric Island" } },
        { Label = "Mirage Island", MapName = "MysticIsland", LocationNames = { "Mirage Island", "Mystic Island" } },
        { Label = "Frozen Dimension", MapName = "Frozen Dimension", LocationNames = { "Frozen Dimension" } },
    }

    for _, check in ipairs(islandChecks) do
        local mapInstance = findChild(map, check.MapName)
        table.insert(
            lines,
            check.Label .. " Workspace.Map marker: " .. instancePresence(mapInstance)
        )
        for _, locationName in ipairs(check.LocationNames) do
            local location = findChild(locations, locationName)
            if location then
                table.insert(
                    lines,
                    check.Label
                        .. " world-origin marker: "
                        .. safeFullName(location)
                        .. "; TimeIn="
                        .. rawNumber(readAttribute(location, "TimeIn"))
                        .. "; CFrame attribute="
                        .. (readAttribute(location, "CFrame") ~= nil and "present" or "absent")
                )
            end
        end
    end
    remoteEvents = remoteEvents or {}
    table.insert(
        lines,
        "Realm tag HasMirageIsland: "
            .. (type(remoteEvents.mirageRealmTag) == "boolean"
                and tostring(remoteEvents.mirageRealmTag)
                or "unknown (" .. tostring(remoteEvents.mirageRealmTagReason or "not checked") .. ")")
    )
    table.insert(
        lines,
        "Mirage spawn status follows Workspace.Map.MysticIsland; the Realm tag is diagnostic only."
    )
    table.insert(
        lines,
        "Tiki Outpost location entry is a travel-location marker; it does not prove eye-event state."
    )

    local tiki = findChild(map, "TikiOutpost")
    local islandModel = findChild(tiki, "IslandModel", true)
    table.insert(lines, "Tiki IslandModel: " .. instancePresence(islandModel))
    for index = 1, 4 do
        local eye = findChild(islandModel, "Eye" .. tostring(index), true)
        table.insert(
            lines,
            "Tiki Eye"
                .. tostring(index)
                .. ": "
                .. (eye
                        and ("present; Transparency=" .. rawNumber(readProperty(eye, "Transparency"))
                            .. "; path=" .. safeFullName(eye))
                    or "not present in this client view")
        )
    end

    local prehistoricTimer = findChild(topHud, "PrehistoricRaidTimer")
    local raidTimer = findChild(topHud, "RaidTimer")
    table.insert(
        lines,
        "PlayerGui.Main.TopHUDList.PrehistoricRaidTimer.Visible: "
            .. stateText(readProperty(prehistoricTimer, "Visible"))
    )
    table.insert(
        lines,
        "PlayerGui.Main.TopHUDList.RaidTimer.Visible: "
            .. stateText(readProperty(raidTimer, "Visible"))
    )

    local player = compatibility and compatibility.Player
    table.insert(
        lines,
        "LocalPlayer CurrentLocation: " .. tostring(readAttribute(player, "CurrentLocation") or "unavailable")
    )
    table.insert(
        lines,
        "LocalPlayer LastSpawnPoint: "
            .. tostring(getChildValue(findChild(player, "Data"), "LastSpawnPoint") or "unavailable")
    )

    local guiDescendantsOk, guiDescendants = pcall(function()
        return topHud and topHud:GetDescendants()
    end)
    local guiTimersListed = 0
    if guiDescendantsOk and type(guiDescendants) == "table" then
        for _, node in ipairs(guiDescendants) do
            if guiTimersListed >= 20 then
                break
            end
            local nodeName = string.lower(tostring(readProperty(node, "Name") or ""))
            local visible = readProperty(node, "Visible")
            if visible ~= nil
                and (string.find(nodeName, "tiki", 1, true)
                    or string.find(nodeName, "prehistoric", 1, true)
                    or string.find(nodeName, "mirage", 1, true)
                    or string.find(nodeName, "frozen", 1, true)
                    or string.find(nodeName, "island", 1, true))
            then
                guiTimersListed += 1
                table.insert(
                    lines,
                    "Event HUD element: "
                        .. tostring(readProperty(node, "Name"))
                        .. "; Visible="
                        .. tostring(visible)
                        .. "; path="
                        .. safeFullName(node)
                )
            end
        end
    end
    if guiTimersListed == 0 then
        table.insert(lines, "Event HUD elements: no matching visible controls found")
    end
end

local function appendUnparentedIslandDiagnostics(lines, compatibility)
    table.insert(lines, "")
    table.insert(lines, "===== [Unparented Instance Check — Manual Report Only] =====")
    local getter = compatibility and compatibility.GetUnparentedInstances
    if type(getter) ~= "function" then
        table.insert(lines, "Unparented-instance API: unavailable")
        return
    end
    local ok, instances = pcall(getter, compatibility)
    if not ok or type(instances) ~= "table" then
        table.insert(lines, "Unparented-instance API: unavailable or failed")
        return
    end

    local scanLimit = math.min(#instances, 5000)
    local matchCount = 0
    local listed = 0
    local summaryIndex = #lines + 1
    table.insert(lines, "Unparented instances scanned: pending")
    local needles = {
        "tiki",
        "prehistoric",
        "mystic",
        "mirage",
        "frozen",
        "eye1",
        "eye2",
        "eye3",
        "eye4",
    }
    for index = 1, scanLimit do
        local instance = instances[index]
        local name = string.lower(tostring(readProperty(instance, "Name") or ""))
        local matched = false
        for _, needle in ipairs(needles) do
            if string.find(name, needle, 1, true) then
                matched = true
                break
            end
        end
        if matched then
            matchCount += 1
            if listed < 20 then
                listed += 1
                table.insert(
                    lines,
                    "Unparented match: "
                        .. tostring(readProperty(instance, "Name") or "unknown")
                        .. "; class="
                        .. tostring(readProperty(instance, "ClassName") or "unknown")
                )
            end
        end
    end
    lines[summaryIndex] =
        "Unparented instances scanned: "
        .. tostring(scanLimit)
        .. " / "
        .. tostring(#instances)
        .. "; relevant name matches="
        .. tostring(matchCount)
    if #instances > scanLimit then
        table.insert(
            lines,
            summaryIndex + 1,
            "Unparented-instance scan was capped at " .. tostring(scanLimit)
        )
    end
    if listed == 0 then
        table.insert(lines, "No matching unparented island/eye names found")
    elseif matchCount > listed then
        table.insert(lines, "Unparented match list truncated after " .. tostring(listed))
    end
end

local function readRemoteFunction(context)
    local compatibility = context and context.Compatibility
    local replicatedStorage = compatibility and compatibility.ReplicatedStorage
    local remotes = findChild(replicatedStorage, "Remotes")
    local remote = findChild(remotes, "CommF_")
    if remote and remote:IsA("RemoteFunction") then
        return remote
    end
    return nil
end

local function readLeviathanSpyStatus(context, remote)
    if not isThirdSea(context and context.Compatibility) then
        return "Third Sea only"
    end
    if not remote then
        return "Unavailable (status remote not loaded)"
    end
    local ok, result = pcall(function()
        return remote:InvokeServer("InfoLeviathan", "1")
    end)
    if not ok then
        return "Unavailable (server check failed)"
    end
    local status = tonumber(result)
    if status == 5 then
        return "Leviathan is out"
    elseif status == -1 or status == nil then
        return "I DONT KNOW"
    end
    return "Bribe the Spy"
end

local function readCakePrinceMobs(context, remote)
    if not isThirdSea(context and context.Compatibility) then
        return "Third Sea only"
    end
    if not remote then
        return "Unavailable (status remote not loaded)"
    end
    local ok, result = pcall(function()
        return remote:InvokeServer("CakePrinceSpawner", true)
    end)
    if not ok then
        return "Unavailable (server check failed)"
    end
    if type(result) == "number" then
        return tostring(math.max(0, math.floor(result))) .. " enemies left"
    end
    if type(result) ~= "string" or result == "" then
        return "Unknown"
    end

    local plainText = result:gsub("<[^>]+>", "")
    local normalized = string.lower(plainText)
    if string.find(normalized, "open the portal", 1, true) then
        return "Portal ready"
    elseif string.find(normalized, "already spawned", 1, true)
        or string.find(normalized, "cake prince has spawned", 1, true)
    then
        return "Cake Prince spawned"
    end
    local count = plainText:match("(%d+)%s*[Ee]nemies?")
        or plainText:match("(%d+)")
    if count then
        return tostring(count) .. " enemies left"
    end
    return "Unknown"
end

local function readRealmEventTags(context)
    local compatibility = context and context.Compatibility
    local replicatedStorage = compatibility and compatibility.ReplicatedStorage
    local util = findChild(replicatedStorage, "Util")
    local realmScript = findChild(util, "Realm")
    if not realmScript then
        return {
            mirageRealmTagReason = "ReplicatedStorage.Util.Realm is not loaded",
        }
    end

    local requireOk, realm = pcall(require, realmScript)
    if not requireOk or type(realm) ~= "table" then
        return {
            mirageRealmTagReason = "Realm module could not be read",
        }
    end
    local readTag = realm.getIfCurrentRealmHasTagAsync
    if type(readTag) ~= "function" then
        return {
            mirageRealmTagReason = "Realm tag check is unavailable",
        }
    end

    local tags = {}
    local definitions = {
        { Key = "mirageRealmTag", ReasonKey = "mirageRealmTagReason", Tag = "HasMirageIsland" },
    }
    for _, definition in ipairs(definitions) do
        local callOk, value = pcall(readTag, definition.Tag)
        if callOk and type(value) == "boolean" then
            tags[definition.Key] = value
        else
            tags[definition.ReasonKey] = callOk
                    and "Realm returned a non-boolean result"
                or "Realm tag check failed"
        end
    end
    return tags
end

local function readRemoteEventValues(context)
    local remote = readRemoteFunction(context)
    local realmTags = readRealmEventTags(context)
    return {
        leviathanSpy = readLeviathanSpyStatus(context, remote),
        cakePrinceMobs = readCakePrinceMobs(context, remote),
        mirageRealmTag = realmTags.mirageRealmTag,
        mirageRealmTagReason = realmTags.mirageRealmTagReason,
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

function StatusFeature:_ReadValues()
    local context = self.Context
    local compatibility = context and context.Compatibility
    local player = compatibility and compatibility.Player
    local playerData = player and player:FindFirstChild("Data")
    local level = getChildValue(playerData, "Level")
    local race = getChildValue(playerData, "Race")
    local fragments = getChildValue(playerData, "Fragments")
    local money = getChildValue(playerData, "Beli") or getChildValue(playerData, "Money")

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
    local remoteEvents = self.RemoteEventStatus or {}
    local worldEvents = readWorldEventValues(context, self)

    return {
        sea = getSea(compatibility),
        level = displayValue(level),
        race = displayValue(race),
        fragments = formatNumber(fragments),
        money = money ~= nil and ("$" .. formatNumber(money)) or "Unavailable",
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
        serverAge = worldEvents.serverAge,
        legendaryItemTimer = worldEvents.legendaryItemTimer,
        moon = worldEvents.moon,
        leviathanSpy = remoteEvents.leviathanSpy or "Waiting for status check",
        cakePrinceMobs = remoteEvents.cakePrinceMobs or "Waiting for status check",
        eliteHunter = worldEvents.eliteHunter,
        mirageIsland = worldEvents.mirageIsland,
        prehistoricIsland = worldEvents.prehistoricIsland,
        frozenDimension = worldEvents.frozenDimension,
        tikiEyes = worldEvents.tikiEyes,
        mirageRealmTag = remoteEvents.mirageRealmTag,
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
        "Fragments: " .. values.fragments,
        "Money: " .. values.money,
        "Auto Farm: " .. values.autoFarm,
        "Farm Mastery: " .. values.farmMastery,
        "Farm Materials: " .. values.farmMaterials,
        "Quest: " .. values.questState,
        "Quest title: " .. values.questTitle,
        "Quest target: " .. values.questTarget,
        "Quest progress: " .. values.questProgress,
        "Quest reader: " .. values.questReader,
        "Quest dialogue: " .. values.questDialogue,
        "Server age: " .. values.serverAge,
        "Chalice / Fist status: " .. values.legendaryItemTimer,
        "Moon: " .. values.moon,
        "Leviathan Spy: " .. values.leviathanSpy,
        "Cake Prince mobs: " .. values.cakePrinceMobs,
        "Elite Hunter: " .. values.eliteHunter,
        "Mirage Island: " .. values.mirageIsland,
        "Prehistoric Island: " .. values.prehistoricIsland,
        "Frozen Dimension: " .. values.frozenDimension,
        "Tiki eyes: " .. values.tikiEyes,
        "Players: " .. values.players,
        "Place ID: " .. values.placeId,
        "Server Job ID: " .. values.fullJobId,
    }
    local compatibility = self.Context and self.Context.Compatibility
    local workspace = compatibility and compatibility.Workspace
    appendClockDiagnostics(lines, workspace)
    appendLegendaryItemDiagnostics(lines, self.Context, workspace)
    appendIslandDiagnostics(lines, self.Context, self.RemoteEventStatus)
    appendUnparentedIslandDiagnostics(lines, compatibility)
    table.insert(lines, "===== [StatusReport] REPORT END =====")
    return table.concat(lines, "\n")
end

function StatusFeature:_RequestEventStatusRefresh(context, generation)
    if self._remoteRefreshBusy == generation then
        return
    end
    local now = os.clock()
    if now - (self._lastRemoteRefreshAt or -math.huge) < 15 then
        return
    end
    self._lastRemoteRefreshAt = now
    self._remoteRefreshBusy = generation
    task.spawn(function()
        local ok, values = pcall(readRemoteEventValues, context)
        if self._remoteRefreshBusy == generation then
            self._remoteRefreshBusy = nil
        end
        if not ok or type(values) ~= "table"
            or self.Context ~= context
            or self._generation ~= generation
        then
            return
        end
        self.RemoteEventStatus = values
        context.State:SetStatusValues(self:_ReadValues())
    end)
end

function StatusFeature:Initialize(context)
    self.Context = context
    self._generation = (self._generation or 0) + 1
    local generation = self._generation
    self._remoteRefreshBusy = nil
    self._lastRemoteRefreshAt = -math.huge
    self._moonClockSample = nil
    self._moonSecondsPerGameHour = nil
    self._moonRateUpdatedAt = nil
    self.RemoteEventStatus = {
        leviathanSpy = "Waiting for status check",
        cakePrinceMobs = "Waiting for status check",
        mirageRealmTagReason = "not checked",
    }
    context.State:SetStatusValues(self:_ReadValues())
    task.spawn(function()
        while self.Context == context and self._generation == generation do
            task.wait(1)
            if self.Context == context and self._generation == generation then
                sampleMoonClockRate(self)
                local snapshot = context.State:GetSnapshot()
                if snapshot.selectedTab == "StatusServer"
                    or snapshot.selectedTab == "EventStatus"
                then
                    context.State:SetStatusValues(self:_ReadValues())
                end
                if snapshot.selectedTab == "EventStatus" then
                    self:_RequestEventStatusRefresh(context, generation)
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
    local snapshot = self.Context.State:GetSnapshot()
    if snapshot.selectedTab == "EventStatus" then
        self:_RequestEventStatusRefresh(self.Context, self._generation)
    end
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
    self._remoteRefreshBusy = nil
    self._moonClockSample = nil
    self._moonSecondsPerGameHour = nil
    self._moonRateUpdatedAt = nil
    self.RemoteEventStatus = nil
    self.Context = nil
end

return StatusFeature
