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

    return {
        sea = getSea(compatibility),
        level = displayValue(level),
        race = displayValue(race),
        character = getCharacterStatus(character),
        health = health,
        autoFarm = snapshot.featureEnabled["farm.main"] and "On" or "Off",
        farmMastery = farmSettings.FarmMastery == true and "On" or "Off",
        farmMaterials = farmSettings.FarmMaterialsEnabled == true and "On" or "Off",
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
        "Players: " .. values.players,
        "Place ID: " .. values.placeId,
        "Server Job ID: " .. values.fullJobId,
        "===== [StatusReport] REPORT END =====",
    }
    return table.concat(lines, "\n")
end

function StatusFeature:Initialize(context)
    self.Context = context
    context.State:SetStatusValues(self:_ReadValues())
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
    self.Context = nil
end

return StatusFeature
