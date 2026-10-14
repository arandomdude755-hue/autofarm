local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Compatibility = {}
Compatibility.__index = Compatibility

function Compatibility.new()
    return setmetatable({
        Player = Players.LocalPlayer,
        Players = Players,
        ReplicatedStorage = ReplicatedStorage,
        Workspace = Workspace,
        RunService = RunService,
        CollectionService = CollectionService,
    }, Compatibility)
end

function Compatibility:GetPlayerGui()
    if not self.Player then
        return nil, "LocalPlayer is unavailable"
    end
    local playerGui = self.Player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return nil, "PlayerGui is unavailable"
    end
    return playerGui
end

function Compatibility:GetUnparentedInstances()
    local getterOk, getter = pcall(function()
        return getnilinstances
    end)
    if not getterOk or type(getter) ~= "function" then
        return nil
    end

    local callOk, instances = pcall(getter)
    if not callOk or type(instances) ~= "table" then
        return nil
    end
    return instances
end

function Compatibility:GetGunShootFunction()
    if type(self.GunShootFunction) == "function"
        and type(self.GunShootTargetAssist) == "table"
        and type(self.GunShootTargetAssist.getTargetInfo) == "function"
    then
        return self.GunShootFunction, self.GunShootTargetAssist
    end

    local now = os.clock()
    if now < (self.GunShootNextScanAt or 0) then
        return nil, nil, self.GunShootResolveError or "Gun shoot function scan is cooling down"
    end
    self.GunShootNextScanAt = now + 2

    local getterOk, getGc = pcall(function()
        return getgc
    end)
    if not getterOk or type(getGc) ~= "function" then
        self.GunShootResolveError = "Executor getgc is unavailable"
        return nil, nil, self.GunShootResolveError
    end

    local debugOk, debugLibrary = pcall(function()
        return debug
    end)
    local getInfo = debugOk and debugLibrary and debugLibrary.getinfo
    local getConstants = debugOk and debugLibrary and debugLibrary.getconstants
    if type(getInfo) ~= "function" or type(getConstants) ~= "function" then
        self.GunShootResolveError = "Gun shoot function inspection is unavailable"
        return nil, nil, self.GunShootResolveError
    end

    local getGcOk, objects = pcall(getGc, false)
    if not getGcOk or type(objects) ~= "table" then
        self.GunShootResolveError = "Executor could not enumerate client functions"
        return nil, nil, self.GunShootResolveError
    end

    local isLuaClosure
    pcall(function()
        isLuaClosure = islclosure
    end)
    local getUpvalues
    pcall(function()
        getUpvalues = getupvalues
    end)

    local function hasRequiredConstants(constants)
        if type(constants) ~= "table" then
            return false
        end
        local foundShotsLeft = false
        local foundTotalShots = false
        for _, value in pairs(constants) do
            if value == "LocalShotsLeft" then
                foundShotsLeft = true
            elseif value == "LocalTotalShots" then
                foundTotalShots = true
            end
            if foundShotsLeft and foundTotalShots then
                return true
            end
        end
        return false
    end

    local function findTargetAssist(candidate)
        local values
        if type(getUpvalues) == "function" then
            local valuesOk, result = pcall(getUpvalues, candidate)
            if valuesOk and type(result) == "table" then
                values = result
            end
        end
        if not values and type(debugLibrary.getupvalue) == "function" then
            values = {}
            for index = 1, 40 do
                local valueOk, first, second =
                    pcall(debugLibrary.getupvalue, candidate, index)
                if not valueOk or first == nil then
                    break
                end
                table.insert(values, second ~= nil and second or first)
            end
        end
        for _, value in pairs(values or {}) do
            if type(value) == "table" then
                local targetInfo
                local readOk, result = pcall(rawget, value, "getTargetInfo")
                if readOk then
                    targetInfo = result
                end
                if type(targetInfo) == "function" then
                    return value
                end
            end
        end
        return nil
    end

    for _, candidate in pairs(objects) do
        if type(candidate) == "function" then
            local closureAllowed = true
            if type(isLuaClosure) == "function" then
                local closureOk, isClosure = pcall(isLuaClosure, candidate)
                closureAllowed = closureOk and isClosure == true
            end
            if closureAllowed then
                local infoOk, info = pcall(getInfo, candidate)
                local parameterCount = info
                    and (info.numparams or info.nparams)
                if infoOk and parameterCount == 2 then
                    local constantsOk, constants = pcall(getConstants, candidate)
                    if constantsOk and hasRequiredConstants(constants) then
                        local targetAssist = findTargetAssist(candidate)
                        if targetAssist then
                            self.GunShootFunction = candidate
                            self.GunShootTargetAssist = targetAssist
                            self.GunShootResolveError = nil
                            return candidate, targetAssist
                        end
                    end
                end
            end
        end
    end

    self.GunShootResolveError =
        "Could not find the client gun handler with a target lookup"
    return nil, nil, self.GunShootResolveError
end

function Compatibility:IsTouchEnabled()
    return UserInputService.TouchEnabled
end

function Compatibility:GetViewportSize()
    local camera = Workspace.CurrentCamera
    if camera then
        return camera.ViewportSize
    end
    return Vector2.new(390, 844)
end

function Compatibility:GetCharacterParts()
    local character = self.Player and self.Player.Character
    if not character then
        return nil, nil, nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then
        return character, humanoid, nil
    end
    return character, humanoid, root
end

function Compatibility:GetQuestModules()
    local questsModule = self.ReplicatedStorage:WaitForChild("Quests", 10)
    local guideModule = self.ReplicatedStorage:WaitForChild("GuideModule", 10)
    if not questsModule or not guideModule then
        return nil, nil, "BNN quest modules are unavailable"
    end

    local ok, quests = pcall(require, questsModule)
    if not ok or type(quests) ~= "table" then
        return nil, nil, "ReplicatedStorage.Quests did not return a quest table"
    end

    local guideOk, guide = pcall(require, guideModule)
    if not guideOk or type(guide) ~= "table" then
        return nil, nil, "GuideModule did not return a data table"
    end
    return quests, guide
end

function Compatibility:GetCommF()
    local remotes = self.ReplicatedStorage:FindFirstChild("Remotes")
    local commF = remotes and remotes:FindFirstChild("CommF_")
    if not commF then
        return nil, "ReplicatedStorage.Remotes.CommF_ is unavailable"
    end
    return commF
end

function Compatibility:CanSimulateTouch()
    local ok, touchFunction = pcall(function()
        return firetouchinterest
    end)
    return ok and type(touchFunction) == "function"
end

function Compatibility:TouchPart(touchingPart, targetPart, isCurrent)
    if not touchingPart or not touchingPart.Parent or not targetPart or not targetPart.Parent then
        return false, "Gateway touch parts are unavailable"
    end
    if type(isCurrent) == "function" and not isCurrent() then
        return false, "Gateway touch was cancelled"
    end
    local ok, touchFunction = pcall(function()
        return firetouchinterest
    end)
    if not ok or type(touchFunction) ~= "function" then
        return false, "This client cannot activate the map gateway touch trigger"
    end

    local began, beginError = pcall(touchFunction, touchingPart, targetPart, 0)
    if not began then
        return false, "Gateway touch could not begin: " .. tostring(beginError)
    end
    task.wait(0.15)
    if type(isCurrent) == "function" and not isCurrent() then
        pcall(touchFunction, touchingPart, targetPart, 1)
        return false, "Gateway touch was cancelled"
    end
    local ended, endError = pcall(touchFunction, touchingPart, targetPart, 1)
    if not ended then
        return false, "Gateway touch could not finish: " .. tostring(endError)
    end
    return true
end

function Compatibility:HasOwnedInventoryItem(itemName)
    local now = os.clock()
    self.OwnedInventoryCache = self.OwnedInventoryCache or {}
    if now - (self.OwnedInventoryCacheAt or 0) < 1
        and self.OwnedInventoryCache[itemName] ~= nil
    then
        return self.OwnedInventoryCache[itemName]
    end

    local itemServiceModule = self.ReplicatedStorage:FindFirstChild("ItemReplicationService")
    local itemConfigModule = self.ReplicatedStorage:FindFirstChild("ItemConfig")
    if not itemServiceModule or not itemConfigModule then
        return false, "Inventory lookup modules are unavailable"
    end

    local serviceOk, itemService = pcall(require, itemServiceModule)
    local configOk, itemConfig = pcall(require, itemConfigModule)
    if not serviceOk or type(itemService) ~= "table"
        or not configOk or type(itemConfig) ~= "table"
    then
        return false, "Inventory lookup modules could not be loaded"
    end

    local keys = itemService.KEYS
    local quantityKey = type(keys) == "table" and keys.QUANTITY
    if quantityKey == nil or type(itemService.GetItems) ~= "function"
        or type(itemConfig.match) ~= "function"
    then
        return false, "Inventory lookup APIs are unavailable"
    end

    local scanOk, found = pcall(function()
        for _, item in itemService:GetItems(quantityKey) do
            if item and item.Value and item.Value > 0 then
                local matchOk, itemDefinition = pcall(function()
                    return itemConfig.match(item.ItemId):unwrap()
                end)
                if matchOk and itemDefinition and itemDefinition.Display then
                    local display = itemDefinition.Display
                    local storageKey = itemDefinition.Index
                        and itemDefinition.Index.StorageKey
                    local resolvedName = display.Category == "Blox Fruit"
                            and (storageKey or display.Name)
                        or (display.Name or storageKey)
                    if resolvedName == itemName then
                        return true
                    end
                end
            end
        end
        return false
    end)
    if not scanOk then
        return false, "Inventory scan failed: " .. tostring(found)
    end

    self.OwnedInventoryCache[itemName] = found == true
    self.OwnedInventoryCacheAt = now
    return found == true
end

function Compatibility:BuildTitleAccessDiagnosticReport()
    local targetTitle = "Liberator of the Sky"
    local targetLower = string.lower(targetTitle)
    local lines = {
        "===== [TitleAccessDiagnostic] REPORT BEGIN =====",
        "Target title: " .. targetTitle,
        "Purpose: locate title ownership data; no remotes are invoked",
    }
    local matchCount = 0
    local scanLimit = 3000
    local matchLimit = 30

    local function addMatch(sourceName, instance, valueDescription)
        if matchCount >= matchLimit then
            return
        end
        local path = "unknown path"
        pcall(function()
            path = instance:GetFullName()
        end)
        local className = "unknown class"
        pcall(function()
            className = instance.ClassName
        end)
        local visibility = ""
        pcall(function()
            if instance:IsA("GuiObject") then
                visibility = "; Visible=" .. tostring(instance.Visible)
            elseif instance:IsA("LayerCollector") then
                visibility = "; Enabled=" .. tostring(instance.Enabled)
            end
        end)
        lines[#lines + 1] = sourceName
            .. ": "
            .. path
            .. " ("
            .. className
            .. ")"
            .. (valueDescription and ("; value=" .. tostring(valueDescription)) or "")
            .. visibility
        matchCount += 1
    end

    local function scanRoot(sourceName, root, maxDescendants, includeTitleNames, includeAllText)
        if not root then
            lines[#lines + 1] = sourceName .. ": unavailable"
            return
        end
        local descendantsOk, descendants = pcall(root.GetDescendants, root)
        if not descendantsOk or type(descendants) ~= "table" then
            lines[#lines + 1] = sourceName .. ": descendants could not be read"
            return
        end
        local scanned = math.min(#descendants, tonumber(maxDescendants) or scanLimit)
        local relevantCount = 0
        for index = 1, scanned do
            local instance = descendants[index]
            local name = ""
            pcall(function()
                name = instance.Name
            end)
            local nameLower = string.lower(tostring(name))
            local valueText
            local isTextControl = false
            local valueOk = pcall(function()
                if instance:IsA("ValueBase") then
                    valueText = tostring(instance.Value)
                elseif instance:IsA("TextLabel")
                    or instance:IsA("TextButton")
                    or instance:IsA("TextBox")
                then
                    valueText = tostring(instance.Text)
                    isTextControl = true
                end
            end)
            if not valueOk then
                valueText = nil
            end
            local valueLower = type(valueText) == "string" and string.lower(valueText) or ""
            local exactTitleMatch = string.find(valueLower, targetLower, 1, true) ~= nil
            local exactTitleName = string.find(nameLower, targetLower, 1, true) ~= nil
            local titleNamed = includeTitleNames == true
                and string.find(nameLower, "title", 1, true) ~= nil
            local ownershipMarker = includeAllText == true
                and (
                    string.find(nameLower, "unlock", 1, true)
                    or string.find(nameLower, "owned", 1, true)
                    or string.find(nameLower, "claim", 1, true)
                    or string.find(nameLower, "equipped", 1, true)
                    or string.find(nameLower, "locked", 1, true)
                    or string.find(nameLower, "available", 1, true)
                )
            if titleNamed or exactTitleMatch or exactTitleName
                or (includeAllText == true and isTextControl)
                or ownershipMarker
            then
                relevantCount += 1
                addMatch(sourceName, instance, valueText)
            end

            local attributesOk, attributes = pcall(instance.GetAttributes, instance)
            if attributesOk and type(attributes) == "table" then
                for attributeName, attributeValue in pairs(attributes) do
                    local attributeNameLower = string.lower(tostring(attributeName))
                    local attributeText = tostring(attributeValue)
                    local attributeValueLower = string.lower(attributeText)
                    if (includeTitleNames == true
                            and string.find(attributeNameLower, "title", 1, true))
                        or string.find(attributeValueLower, targetLower, 1, true)
                    then
                        relevantCount += 1
                        addMatch(
                            sourceName .. " attribute " .. tostring(attributeName),
                            instance,
                            attributeText
                        )
                    end
                end
            end
        end
        lines[#lines + 1] = sourceName
            .. " scan: "
            .. tostring(scanned)
            .. " descendants; "
            .. tostring(relevantCount)
            .. " title-related matches"
            .. (#descendants > scanned and "; scan limit reached" or "")
    end

    local player = self.Player
    local playerData = player and player:FindFirstChild("Data")
    scanRoot("Player.Data", playerData, scanLimit, true, false)

    local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
    local titlesMenu = playerGui and playerGui:FindFirstChild("TitlesMenu")
    local mainTitles = playerGui
        and playerGui:FindFirstChild("Main")
        and playerGui.Main:FindFirstChild("Titles")
    scanRoot("PlayerGui exact-title scan", playerGui, 10000, false, false)
    scanRoot("TitlesMenu", titlesMenu, 10000, true, true)
    local function describeGuiRoot(instance)
        if not instance then
            return "missing"
        end
        local state = instance.ClassName .. "; present"
        pcall(function()
            if instance:IsA("LayerCollector") then
                state ..= "; Enabled=" .. tostring(instance.Enabled)
            elseif instance:IsA("GuiObject") then
                state ..= "; Visible=" .. tostring(instance.Visible)
            end
        end)
        return state
    end
    lines[#lines + 1] = "TitlesMenu root: "
        .. describeGuiRoot(titlesMenu)
    lines[#lines + 1] = "Main.Titles root: "
        .. describeGuiRoot(mainTitles)

    local replicatedStorage = self.ReplicatedStorage
    local remoteCandidates = {}
    local moduleCandidates = {}
    if replicatedStorage then
        local descendantsOk, descendants = pcall(replicatedStorage.GetDescendants, replicatedStorage)
        if descendantsOk and type(descendants) == "table" then
            for index = 1, math.min(#descendants, scanLimit) do
                local instance = descendants[index]
                local nameLower = string.lower(tostring(instance.Name))
                if instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction") then
                    if string.find(nameLower, "title", 1, true) then
                        remoteCandidates[#remoteCandidates + 1] = instance:GetFullName()
                    elseif instance.Name == "CommF_" then
                        remoteCandidates[#remoteCandidates + 1] =
                            instance:GetFullName() .. " (generic remote; not invoked)"
                    end
                elseif instance:IsA("ModuleScript")
                    and string.find(nameLower, "title", 1, true)
                then
                    moduleCandidates[#moduleCandidates + 1] = instance:GetFullName()
                end
            end
        end
    end
    lines[#lines + 1] = "Title-related remotes: "
        .. (#remoteCandidates > 0 and table.concat(remoteCandidates, ", ") or "none found")
    lines[#lines + 1] = "Title-related modules: "
        .. (#moduleCandidates > 0 and table.concat(moduleCandidates, ", ") or "none found")
    local remotesFolder = replicatedStorage and replicatedStorage:FindFirstChild("Remotes")
    local commF = remotesFolder and remotesFolder:FindFirstChild("CommF_")
    lines[#lines + 1] = "Generic CommF_ remote: "
        .. (commF and (commF.ClassName .. "; present; not invoked") or "missing")

    local npcFolder = self.Workspace and self.Workspace:FindFirstChild("NPCs")
    local titleNpcs = {}
    for _, npc in ipairs(npcFolder and npcFolder:GetChildren() or {}) do
        if string.find(string.lower(npc.Name), "title", 1, true) then
            titleNpcs[#titleNpcs + 1] = npc.Name
        end
    end
    lines[#lines + 1] = "Title-related Workspace.NPCs: "
        .. (#titleNpcs > 0 and table.concat(titleNpcs, ", ") or "none found")
    if matchCount == 0 then
        lines[#lines + 1] = "Exact title text not found in the scanned Player.Data or PlayerGui entries."
    end
    lines[#lines + 1] = "Note: name/value matches are evidence only; they do not prove unlocked status."
    lines[#lines + 1] = "===== [TitleAccessDiagnostic] REPORT END ====="
    return table.concat(lines, "\n")
end

function Compatibility:GetCombatDependencies()
    local modules = self.ReplicatedStorage:FindFirstChild("Modules")
    local netModule = modules and modules:FindFirstChild("Net")
    local mouseModule = self.ReplicatedStorage:FindFirstChild("Mouse")
    local combatUtilModule = modules and modules:FindFirstChild("CombatUtil")
    if not netModule or not mouseModule or not combatUtilModule then
        return nil, "BNN melee dependency modules are unavailable"
    end

    local registerAttack = netModule:WaitForChild("RE/RegisterAttack", 10)
    if not registerAttack then
        return nil, "Modules.Net.RE/RegisterAttack is unavailable"
    end

    local mouseOk, mouse = pcall(require, mouseModule)
    local combatOk, combatUtil = pcall(require, combatUtilModule)
    local netOk, net = pcall(require, netModule)
    if not mouseOk or not combatOk or not netOk then
        return nil, "BNN melee dependency modules failed to load"
    end

    local hitOk, registerHit = pcall(function()
        return net:RemoteEvent("RegisterHit", true)
    end)
    if not hitOk or not registerHit then
        return nil, "Modules.Net RegisterHit dependency is unavailable"
    end

    return {
        Mouse = mouse,
        CombatUtil = combatUtil,
        Net = net,
        RegisterAttack = registerAttack,
        RegisterHit = registerHit,
    }
end

function Compatibility:IsThirdSea()
    local mapName = self.Workspace:GetAttribute("MAP")
    return mapName == "Sea3"
        or game.PlaceId == 100117331123089
        or game.PlaceId == 7449423635
end

function Compatibility:IsFirstSea()
    local mapName = self.Workspace:GetAttribute("MAP")
    return mapName == "Sea1"
        or game.PlaceId == 2753915549
        or game.PlaceId == 85211729168715
end

function Compatibility:IsSecondSea()
    local mapName = self.Workspace:GetAttribute("MAP")
    return mapName == "Sea2"
        or game.PlaceId == 4442272183
        or game.PlaceId == 79091703265657
end

return Compatibility
