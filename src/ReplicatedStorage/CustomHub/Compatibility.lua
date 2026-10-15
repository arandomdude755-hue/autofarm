local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Compatibility = {}
Compatibility.__index = Compatibility

local TITLE_MENU_PROBE_TIMEOUT = 0.35
local TITLE_MENU_PROBE_INTERVAL = 0.05
local TITLE_STATE_CACHE_TTL = 30
local TITLE_STATE_UNKNOWN_CACHE_TTL = 1

function Compatibility.new()
    return setmetatable({
        Player = Players.LocalPlayer,
        Players = Players,
        ReplicatedStorage = ReplicatedStorage,
        Workspace = Workspace,
        RunService = RunService,
        CollectionService = CollectionService,
        NpcManager = nil,
        NpcCatalogNames = nil,
    }, Compatibility)
end

function Compatibility:GetNpcManager()
    if self.NpcManager then
        return self.NpcManager
    end
    local managerModule = self.ReplicatedStorage
        and self.ReplicatedStorage:FindFirstChild("NPCManager")
    if not managerModule or not managerModule:IsA("ModuleScript") then
        return nil, "NPCManager module is unavailable"
    end
    local ok, manager = pcall(require, managerModule)
    if not ok or type(manager) ~= "table"
        or type(manager.getNPCsByName) ~= "function"
    then
        return nil, "NPCManager lookup is unavailable: " .. tostring(manager)
    end
    self.NpcManager = manager
    return manager
end

function Compatibility:GetNpcCatalogNames()
    if self.NpcCatalogNames then
        return table.clone(self.NpcCatalogNames)
    end
    local managerModule = self.ReplicatedStorage
        and self.ReplicatedStorage:FindFirstChild("NPCManager")
    local npcListModule = managerModule
        and managerModule:FindFirstChild("NPCList")
    if not npcListModule or not npcListModule:IsA("ModuleScript") then
        return nil, "NPCManager.NPCList module is unavailable"
    end
    local ok, npcList = pcall(require, npcListModule)
    local list = ok and type(npcList) == "table" and npcList.List
    if type(list) ~= "table" then
        return nil, "NPCManager NPC list is unavailable: " .. tostring(npcList)
    end
    local names = {}
    for name in pairs(list) do
        if type(name) == "string" and name ~= "" then
            table.insert(names, name)
        end
    end
    table.sort(names)
    self.NpcCatalogNames = names
    return table.clone(names)
end

function Compatibility:GetNpcModelsByName(name)
    if type(name) ~= "string" or name == "" then
        return {}, "NPC name is invalid"
    end
    local manager, managerError = self:GetNpcManager()
    if not manager then
        return {}, managerError
    end
    local ok, entries = pcall(manager.getNPCsByName, name)
    if not ok or type(entries) ~= "table" then
        return {}, ok and "NPCManager returned no entry list" or tostring(entries)
    end
    local models = {}
    local seen = {}
    for _, entry in ipairs(entries) do
        local stateOk, model = pcall(function()
            local modelState = entry and entry._modelState
            return modelState and modelState._instance
        end)
        if stateOk and model and typeof(model) == "Instance"
            and model:IsA("Model") and not seen[model]
        then
            seen[model] = true
            table.insert(models, model)
        end
    end
    return models
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

function Compatibility:HasUnlockedTitle(titleName)
    if type(titleName) ~= "string" or titleName == "" then
        return nil, "title name is unavailable"
    end

    local now = os.clock()
    self.TitleOwnershipCache = self.TitleOwnershipCache or {}
    local targetLower = string.lower(titleName)

    local function getMenuParts()
        local playerGui = self.Player and self.Player:FindFirstChildOfClass("PlayerGui")
        local titlesMenu = playerGui and playerGui:FindFirstChild("TitlesMenu")
        local root = titlesMenu and titlesMenu:FindFirstChild("ROOT")
        local frame = root and root:FindFirstChild("Frame")
        local content = frame and frame:FindFirstChild("content")
        local list = content and content:FindFirstChild("scrollingFrame")
        return titlesMenu, frame, list
    end

    local function readTitleState()
        local titlesMenu, frame, list = getMenuParts()
        if not titlesMenu then
            return nil, "TitlesMenu is unavailable", titlesMenu, frame, list
        end
        if not list then
            return nil, "title list is not populated", titlesMenu, frame, list
        end

        local row = list:FindFirstChild(titleName)
        if not row then
            for _, child in ipairs(list:GetChildren()) do
                if string.lower(tostring(child.Name)) == targetLower then
                    row = child
                    break
                end
            end
        end
        if not row or not row:IsA("GuiObject") then
            return nil, "title row is not present in the loaded list", titlesMenu, frame, list
        end
        if not row.Visible then
            return nil, "title row is hidden in the loaded list", titlesMenu, frame, list
        end

        local titleLabel = row:FindFirstChild("titleName", true)
        local titleText = titleLabel and titleLabel:IsA("TextLabel")
                and tostring(titleLabel.Text)
            or ""
        local titleTextLower = string.lower(titleText)
        local lockedImage = row:FindFirstChild("lockedImage", true)
        local isLocked = string.find(titleTextLower, "(locked)", 1, true) ~= nil
        if lockedImage and lockedImage:IsA("GuiObject") and lockedImage.Visible then
            isLocked = true
        end
        if isLocked then
            return false, "title row is marked locked", titlesMenu, frame, list
        end
        if titleTextLower ~= ""
            and string.find(titleTextLower, targetLower, 1, true)
        then
            return true, "unlocked title row is visible", titlesMenu, frame, list
        end
        return nil, "title row has no readable unlocked/locked marker", titlesMenu, frame, list
    end

    local function safeReadTitleState()
        local readOk, state, reason, titlesMenu, frame, list = pcall(readTitleState)
        if not readOk then
            return nil, "title UI scan failed: " .. tostring(state), nil, nil, nil
        end
        return state, reason, titlesMenu, frame, list
    end

    local state, reason, titlesMenu, frame = safeReadTitleState()
    if state ~= nil then
        self.TitleOwnershipCache[titleName] = {
            Value = state,
            Reason = reason,
            At = now,
            ExpiresAt = state == true
                    and math.huge
                or state == false
                    and now + TITLE_STATE_CACHE_TTL
                or now + TITLE_STATE_UNKNOWN_CACHE_TTL,
        }
        return state, reason
    end

    local cache = self.TitleOwnershipCache[titleName]
    if cache and now < cache.ExpiresAt then
        return cache.Value, cache.Reason
    end

    local menuIsVisible = false
    pcall(function()
        menuIsVisible = titlesMenu.Enabled == true and frame and frame.Visible == true
    end)
    local openedForProbe = false
    local originalFrame = frame
    local originalFrameVisible = frame and frame.Visible
    local originalEnabled
    if titlesMenu and titlesMenu:IsA("LayerCollector") then
        originalEnabled = titlesMenu.Enabled
    end

    local visibilityConnections = {}
    local function suppressProbeMenu()
        pcall(function()
            local _, activeFrame = getMenuParts()
            if activeFrame and activeFrame:IsA("GuiObject") then
                activeFrame.Visible = false
            end
            if titlesMenu and titlesMenu:IsA("LayerCollector") then
                titlesMenu.Enabled = false
            end
        end)
    end
    local function watchFrame(activeFrame)
        if not activeFrame or not activeFrame:IsA("GuiObject") then
            return
        end
        local connectOk, connection = pcall(function()
            return activeFrame:GetPropertyChangedSignal("Visible"):Connect(function()
                pcall(function()
                    if openedForProbe and activeFrame.Visible then
                        activeFrame.Visible = false
                    end
                end)
            end)
        end)
        if connectOk and connection then
            table.insert(visibilityConnections, connection)
        end
        if openedForProbe and activeFrame.Visible then
            activeFrame.Visible = false
        end
    end

    if not menuIsVisible then
        local openEvent = titlesMenu and titlesMenu:FindFirstChild("Open")
        if not openEvent or not openEvent:IsA("BindableEvent") then
            reason = "TitlesMenu.Open is unavailable"
        else
            if frame then
                watchFrame(frame)
            end
            if titlesMenu and titlesMenu:IsA("LayerCollector") then
                local enabledConnection = titlesMenu:GetPropertyChangedSignal("Enabled"):Connect(
                    function()
                        pcall(function()
                            if openedForProbe and titlesMenu.Enabled then
                                titlesMenu.Enabled = false
                            end
                        end)
                    end
                )
                table.insert(visibilityConnections, enabledConnection)
            end
            local descendantConnection
            if titlesMenu then
                descendantConnection = titlesMenu.DescendantAdded:Connect(function(instance)
                    if instance.Name == "Frame"
                        and instance.Parent
                        and instance.Parent.Name == "ROOT"
                    then
                            pcall(watchFrame, instance)
                    end
                end)
            end
            openedForProbe = true
            local fired, fireError = pcall(function()
                openEvent:Fire()
            end)
            if fired then
                suppressProbeMenu()
            else
                openedForProbe = false
                reason = "TitlesMenu.Open failed: " .. tostring(fireError)
            end
            if descendantConnection then
                table.insert(visibilityConnections, descendantConnection)
            end
        end
    end

    local function waitForTitleState()
        local deadline = os.clock() + TITLE_MENU_PROBE_TIMEOUT
        repeat
            state, reason = safeReadTitleState()
            if state ~= nil or (not openedForProbe and not menuIsVisible) then
                break
            end
            if openedForProbe then
                suppressProbeMenu()
            end
            if os.clock() >= deadline then
                reason = "title list did not populate within "
                    .. tostring(TITLE_MENU_PROBE_TIMEOUT)
                    .. " seconds"
                break
            end
            task.wait(TITLE_MENU_PROBE_INTERVAL)
        until false
        return state, reason
    end
    local probeOk, probeState, probeReason = pcall(waitForTitleState)
    if probeOk then
        state, reason = probeState, probeReason
    else
        state = nil
        reason = "title menu probe failed: " .. tostring(probeState)
    end

    for _, connection in ipairs(visibilityConnections) do
        pcall(function()
            if connection and connection.Connected then
                connection:Disconnect()
            end
        end)
    end
    if openedForProbe then
        openedForProbe = false
        pcall(function()
            local _, activeFrame = getMenuParts()
            if activeFrame and activeFrame:IsA("GuiObject") then
                activeFrame.Visible = originalFrame and originalFrameVisible == true or false
            end
            if titlesMenu and originalEnabled ~= nil then
                titlesMenu.Enabled = originalEnabled
            end
        end)
    end

    now = os.clock()
    self.TitleOwnershipCache[titleName] = {
        Value = state,
        Reason = reason,
        At = now,
        ExpiresAt = state == true
                and math.huge
            or state == false
                and now + TITLE_STATE_CACHE_TTL
            or now + TITLE_STATE_UNKNOWN_CACHE_TTL,
    }
    return state, reason
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
