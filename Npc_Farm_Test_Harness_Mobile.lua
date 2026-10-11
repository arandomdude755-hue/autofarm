-- NPC Farm Test Harness — Mobile Edition
-- For testing in your own Roblox experience / private test place.
-- Uses the BNN-referenced CombatUtil attack flow and remote request sequence.
-- Combat dependencies are resolved at runtime and attack requests are session/target guarded.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local PLAYER_GUI = player:WaitForChild("PlayerGui")

-- Tuning
local HOVER_HEIGHT = 7
local MOVE_SPEED = 55 -- studs/second
local ARRIVAL_DISTANCE = 9 -- Existing harness threshold; actual per-style reach is not in this repo.
local MELEE_APPROACH_STANDOFF = ARRIVAL_DISTANCE - 2
local MELEE_APPROACH_TOLERANCE = 1.5
local FIGHTING_STYLE_TOOLTIP = "Melee" -- BNN reference categorizes melee tools by ToolTip.
local BNN_M1_HIT_SCAN_RANGE = 30 -- ClickM1's normal AttackFunction argument in the BNN source.
local QUEST_ACCEPT_RANGE = 8
local QUEST_ACCEPT_DELAY = 2
local RESCAN_INTERVAL = 2
local MAX_CONSECUTIVE_ERRORS = 3
local QUEST_EXCLUSIONS = {
    BartiloQuest = true,
    Trainees = true,
    MarineQuest = true,
    CitizenQuest = true,
}

local running = false
local selectedNpcName = nil
local questModeEnabled = false
local currentTarget = nil
local currentQuestName = nil
local currentQuestGiver = nil
local currentQuestTarget = nil
local questStatus = "Manual NPC mode"
local questSelectorTestStatus = "not run"
local combatTestStatus = "not run"
local currentFightingStyleTool = nil
local currentFightingStyleName = nil
local fightingStyleStatus = "Not checked"
local attackActionStatus = "No M1 request attempted"
local questReadyKey = nil
local questReadyAt = 0
local movementToken = 0
local farmSession = 0
local activeTween = nil
local farmState = "Stopped"
local lastScan = 0
local lastReport = "Not tested yet."
local errors = {}
local attacksAttempted = 0
local targetHealthDropsObserved = 0
local lastAttackTarget = nil
local lastAttackHealth = nil
local basicComboIndex = 0
local bnnCombatDependencies = nil
local bnnCombatDependencyStatus = "Combat dependencies not checked"
local targetCount = 0
local spawnMarkerCount = 0
local questCatalogCache = nil
local guideModuleCache = nil

local function getCharacter()
    local character = player.Character
    if not character then return nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then return nil end
    return character, humanoid, root
end

local function isAliveNpc(model)
    if not model or not model:IsA("Model") or model == player.Character or not model:IsDescendantOf(Workspace) then
        return false
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
    return humanoid ~= nil and humanoid.Health > 0
        and root ~= nil and root:IsA("BasePart") and root:IsDescendantOf(model)
end

local function findNpcModels()
    local found, seen = {}, {}
    local enemiesFolder = Workspace:FindFirstChild("Enemies")
    if enemiesFolder then
        for _, item in ipairs(enemiesFolder:GetDescendants()) do
            if item:IsA("Model") and isAliveNpc(item) and not seen[item] then
                seen[item] = true
                table.insert(found, item)
            end
        end
        for _, item in ipairs(enemiesFolder:GetChildren()) do
            if item:IsA("Model") and isAliveNpc(item) and not seen[item] then
                seen[item] = true
                table.insert(found, item)
            end
        end
    else
        -- Fallback for test places without Workspace.Enemies: inspect direct Workspace models only.
        for _, item in ipairs(Workspace:GetChildren()) do
            if item:IsA("Model") and isAliveNpc(item) and not seen[item] then
                seen[item] = true
                table.insert(found, item)
            end
        end
    end
    table.sort(found, function(a, b)
        return a.Name:lower() < b.Name:lower()
    end)
    return found
end

local function getSpawnMarkers(npcName)
    local markers, seen = {}, {}
    local origin = Workspace:FindFirstChild("_WorldOrigin")
    local folder = origin and origin:FindFirstChild("EnemySpawns")
    if folder then
        local wanted = (npcName or ""):lower()
        for _, item in ipairs(folder:GetDescendants()) do
            if item:IsA("BasePart") and not seen[item] then
                local name = item.Name:lower()
                if wanted == "" or name:find(wanted, 1, true) then
                    seen[item] = true
                    table.insert(markers, item)
                end
            end
        end
    end
    return markers
end

local function isFightingStyleTool(item)
    return item ~= nil and item:IsA("Tool") and item.ToolTip == FIGHTING_STYLE_TOOLTIP
end

local BNN_M1_BODY_PARTS = {
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    UpperTorso = true, LowerTorso = true, Head = true,
}

local function resolveBNNCombatDependencies()
    if bnnCombatDependencies then
        return bnnCombatDependencies
    end
    local modules = ReplicatedStorage:FindFirstChild("Modules")
    local combatUtilModule = modules and modules:FindFirstChild("CombatUtil")
    local netModule = modules and modules:FindFirstChild("Net")
    local registerAttack = netModule and netModule:FindFirstChild("RE/RegisterAttack")
    if not combatUtilModule or not combatUtilModule:IsA("ModuleScript")
        or not netModule or not netModule:IsA("ModuleScript")
        or not registerAttack or not registerAttack:IsA("RemoteEvent")
    then
        bnnCombatDependencyStatus = "Missing BNN CombatUtil, Net, or RE/RegisterAttack"
        return nil, bnnCombatDependencyStatus
    end

    local okCombat, combatUtil = pcall(require, combatUtilModule)
    if not okCombat or type(combatUtil) ~= "table" then
        bnnCombatDependencyStatus = "Could not load CombatUtil: " .. tostring(combatUtil)
        return nil, bnnCombatDependencyStatus
    end
    local okNet, net = pcall(require, netModule)
    if not okNet or type(net) ~= "table" or type(net.RemoteEvent) ~= "function" then
        bnnCombatDependencyStatus = "Could not load Net.RemoteEvent: " .. tostring(net)
        return nil, bnnCombatDependencyStatus
    end
    local okHit, registerHit = pcall(function()
        return net:RemoteEvent("RegisterHit", true)
    end)
    if not okHit or not registerHit then
        bnnCombatDependencyStatus = "Could not resolve Net:RemoteEvent(RegisterHit, true): " .. tostring(registerHit)
        return nil, bnnCombatDependencyStatus
    end

    bnnCombatDependencies = {
        CombatUtil = combatUtil,
        RegisterAttack = registerAttack,
        RegisterHit = registerHit,
    }
    bnnCombatDependencyStatus = "BNN CombatUtil and attack remotes ready"
    return bnnCombatDependencies
end

local function collectFightingStyleTools(container)
    local tools = {}
    if not container then return tools end
    for _, item in ipairs(container:GetChildren()) do
        if isFightingStyleTool(item) then
            table.insert(tools, item)
        end
    end
    return tools
end

local function chooseFightingStyleTool(equippedTools, backpackTools)
    if #equippedTools == 1 then
        return equippedTools[1], "equipped"
    end
    if #equippedTools > 1 then
        return nil, "Multiple fighting-style tools are equipped; selection is ambiguous"
    end
    if #backpackTools == 1 then
        return backpackTools[1], "needs-equip"
    end
    if #backpackTools == 0 then
        return nil, "No owned Tool with ToolTip 'Melee' was found"
    end
    return nil, "Multiple owned fighting styles found; selection is ambiguous, equip the intended style manually"
end

local function resolveFightingStyleTool(allowInitialEquip)
    local character, humanoid = getCharacter()
    if not character then
        return nil, "Character is unavailable"
    end
    local backpack = player:FindFirstChildOfClass("Backpack") or player:FindFirstChild("Backpack")
    local styleTool, selectionStatus = chooseFightingStyleTool(
        collectFightingStyleTools(character),
        collectFightingStyleTools(backpack)
    )
    if not styleTool then
        return nil, selectionStatus
    end
    if selectionStatus == "equipped" then
        return styleTool, "equipped"
    end
    if not allowInitialEquip then
        return nil, "Fighting style was unequipped; equip the intended style manually"
    end

    local ok, err = pcall(function()
        humanoid:EquipTool(styleTool)
    end)
    if not ok then
        return nil, "Could not equip " .. tostring(styleTool.Name) .. ": " .. tostring(err)
    end
    if styleTool.Parent ~= character or not isFightingStyleTool(styleTool) then
        return nil, "Waiting for fighting style " .. tostring(styleTool.Name) .. " to equip"
    end
    return styleTool, "equipped"
end

local function attackContextIsCurrent(active, session, currentSession, target, activeTarget, targetAlive)
    return active and session == currentSession and target ~= nil
        and target == activeTarget and targetAlive
end

local function setCurrentTarget(target)
    if currentTarget ~= target then
        currentTarget = target
        lastAttackTarget = nil
        lastAttackHealth = nil
    end
end

local function setCurrentFightingStyle(tool, status)
    if currentFightingStyleTool ~= tool then
        lastAttackTarget = nil
        lastAttackHealth = nil
        basicComboIndex = 0
    end
    currentFightingStyleTool = tool
    currentFightingStyleName = tool and tool.Name or nil
    fightingStyleStatus = status
end

local function runCombatMockTests()
    local function mockTool(name, toolTip)
        return {
            Name = name,
            ToolTip = toolTip,
            IsA = function(_, className) return className == "Tool" end,
        }
    end
    local equipped = mockTool("CurrentStyle", FIGHTING_STYLE_TOOLTIP)
    local owned = mockTool("OtherStyle", FIGHTING_STYLE_TOOLTIP)
    local chosenEquipped, equippedState = chooseFightingStyleTool({equipped}, {owned})
    local chosenOwned, ownedState = chooseFightingStyleTool({}, {owned})
    local ambiguous, ambiguousState = chooseFightingStyleTool({}, {owned, mockTool("SecondStyle", FIGHTING_STYLE_TOOLTIP)})
    local swordOnly, swordState = chooseFightingStyleTool({}, {mockTool("Sword", "Sword")})
    local targetA, targetB = {}, {}
    local attackTestsPassed = attackContextIsCurrent(true, 3, 3, targetA, targetA, true)
        and not attackContextIsCurrent(false, 3, 3, targetA, targetA, true)
        and not attackContextIsCurrent(true, 2, 3, targetA, targetA, true)
        and not attackContextIsCurrent(true, 3, 3, targetA, targetB, true)
        and not attackContextIsCurrent(true, 3, 3, targetA, targetA, false)
    local styleTestsPassed = chosenEquipped == equipped and equippedState == "equipped"
        and chosenOwned == owned and ownedState == "needs-equip"
        and ambiguous == nil and string.find(ambiguousState, "ambiguous", 1, true) ~= nil
        and swordOnly == nil and swordState ~= nil
    return styleTestsPassed and attackTestsPassed,
        styleTestsPassed and attackTestsPassed
            and "style choice, ambiguity, stop/session/target/death cancellation passed"
            or "combat mock assertion failed"
end

local function normalizePosition(value)
    if typeof(value) == "CFrame" then
        return value.Position
    end
    if typeof(value) == "Vector3" then
        return value
    end
    return nil
end

local function requireReplicatedModule(name)
    local module = ReplicatedStorage:FindFirstChild(name)
    if not module or not module:IsA("ModuleScript") then
        return nil, name .. " ModuleScript is unavailable"
    end
    local ok, value = pcall(require, module)
    if not ok then
        return nil, name .. " failed to load: " .. tostring(value)
    end
    if type(value) ~= "table" then
        return nil, name .. " did not return a table"
    end
    return value
end

-- Read-only BNN-shaped data adapter.
-- Expected: ReplicatedStorage.Quests[InternalQuestName][questId].Task;
-- GuideModule.Data.NPCList records with InternalQuestName, Levels, NPCName, Position;
-- GuideModule.Data.QuestData for active tasks; and player.Data.Level.Value.
-- Returns a validated context or nil plus a diagnostic string; it does not mutate game state.
local function getQuestContext()
    if not questCatalogCache then
        local value, reason = requireReplicatedModule("Quests")
        if not value then return nil, reason end
        questCatalogCache = value
    end
    if not guideModuleCache then
        local value, reason = requireReplicatedModule("GuideModule")
        if not value then return nil, reason end
        guideModuleCache = value
    end

    local guideData = guideModuleCache.Data
    local playerData = player:FindFirstChild("Data")
    local levelValue = playerData and playerData:FindFirstChild("Level")
    if type(guideData) ~= "table" or type(guideData.NPCList) ~= "table" then
        return nil, "GuideModule.Data.NPCList is unavailable"
    end
    if not levelValue or type(levelValue.Value) ~= "number" then
        return nil, "player Data.Level is unavailable"
    end

    return {
        quests = questCatalogCache,
        guideData = guideData,
        npcList = guideData.NPCList,
        activeQuestData = guideData.QuestData,
        level = levelValue.Value,
    }
end

local function getActiveQuestTarget(context)
    local questData = context and context.activeQuestData
    local tasks = type(questData) == "table" and questData.Task or nil
    if type(tasks) ~= "table" then
        return nil, nil
    end
    local targetName = next(tasks)
    if type(targetName) ~= "string" then
        return nil, nil
    end
    return questData, targetName
end

-- Input: validated getQuestContext() result. Output: highest eligible non-excluded
-- NPCList quest record and one task enemy name, or nil if no candidate is usable.
local function selectQuestForLevel(context)
    local best, bestLevel = nil, -math.huge
    for _, npcInfo in pairs(context.npcList) do
        if type(npcInfo) == "table"
            and type(npcInfo.InternalQuestName) == "string"
            and not QUEST_EXCLUSIONS[npcInfo.InternalQuestName]
            and type(npcInfo.Levels) == "table"
        then
            local questsForGiver = context.quests[npcInfo.InternalQuestName]
            if type(questsForGiver) == "table" then
                for rawQuestId, rawRequiredLevel in pairs(npcInfo.Levels) do
                    local questId = tonumber(rawQuestId)
                    local requiredLevel = tonumber(rawRequiredLevel)
                    local questDefinition = questsForGiver[rawQuestId]
                        or (questId and questsForGiver[questId])
                    if questId and requiredLevel and requiredLevel <= context.level
                        and requiredLevel >= bestLevel
                        and type(questDefinition) == "table"
                        and type(questDefinition.Task) == "table"
                    then
                        local mobName
                        for name, count in pairs(questDefinition.Task) do
                            if type(name) == "string" and tonumber(count) and tonumber(count) > 1 then
                                mobName = name
                                break
                            end
                        end
                        if mobName then
                            bestLevel = requiredLevel
                            best = {
                                Level = requiredLevel,
                                QuestName = npcInfo.InternalQuestName,
                                Id = questId,
                                GiverName = npcInfo.NPCName,
                                Position = npcInfo.Position,
                                Mob = mobName,
                            }
                        end
                    end
                end
            end
        end
    end
    return best
end

local function runQuestSelectorMockTest()
    local mockContext = {
        level = 25,
        quests = {
            MockQuest = {
                [1] = {Task = {["Low Level Mob"] = 5}},
                [2] = {Task = {["High Level Mob"] = 5}},
            },
            BartiloQuest = {
                [1] = {Task = {["Excluded Mob"] = 5}},
            },
        },
        npcList = {
            {
                NPCName = "Mock Quest Giver",
                InternalQuestName = "MockQuest",
                Position = Vector3.new(0, 0, 0),
                Levels = {[1] = 5, [2] = 20},
            },
            {
                NPCName = "Excluded Giver",
                InternalQuestName = "BartiloQuest",
                Position = Vector3.new(0, 0, 0),
                Levels = {[1] = 24},
            },
        },
    }
    local highLevel = selectQuestForLevel(mockContext)
    mockContext.level = 10
    local lowerLevel = selectQuestForLevel(mockContext)
    local activeQuest, activeTarget = getActiveQuestTarget({
        activeQuestData = {Task = {["Mock Active Mob"] = 2}},
    })
    local passed = highLevel ~= nil
        and highLevel.QuestName == "MockQuest"
        and highLevel.Id == 2
        and highLevel.Mob == "High Level Mob"
        and lowerLevel ~= nil
        and lowerLevel.Id == 1
        and lowerLevel.Mob == "Low Level Mob"
        and activeQuest ~= nil
        and activeTarget == "Mock Active Mob"
    return passed, passed and "level choice, exclusion, and active target passed" or "mock selector assertion failed"
end

-- BNN-compatible integration point; this repo does not contain the game's quest server.
-- Inputs: selected quest record {QuestName: string, Id: number}.
-- Output: request-sent boolean and diagnostic text; this does not confirm server acceptance.
-- Assumption from the BNN reference: ReplicatedStorage.Remotes.CommF_ accepts
-- InvokeServer("StartQuest", questName, questId). Replace this adapter if the replica differs.
local function requestQuestStart(selection)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local remote = remotes and remotes:FindFirstChild("CommF_")
    if not remote or not remote:IsA("RemoteFunction") then
        return false, "BNN-compatible Remotes.CommF_ RemoteFunction is unavailable"
    end
    local ok, err = pcall(function()
        remote:InvokeServer("StartQuest", tostring(selection.QuestName), selection.Id)
    end)
    if not ok then
        return false, "StartQuest request failed: " .. tostring(err)
    end
    return true, "StartQuest request sent; awaiting GuideModule quest state"
end

local function setReport()
    local character, humanoid, root = getCharacter()
    local lines = {
        "NPC Farm Test Harness",
        "Player: " .. player.Name,
        "Character ready: " .. tostring(character ~= nil),
        "Farm mode: " .. (questModeEnabled and "level-based quest" or "manual NPC"),
        "Selected NPC: " .. tostring(selectedNpcName or "(none)"),
        "Quest: " .. tostring(currentQuestName or "(none)"),
        "Quest giver: " .. tostring(currentQuestGiver or "(none)"),
        "Quest target: " .. tostring(currentQuestTarget or "(none)"),
        "Quest integration: " .. tostring(questStatus),
        "Quest selector mock: " .. tostring(questSelectorTestStatus),
        "Combat mock: " .. tostring(combatTestStatus),
        "Target alive: " .. tostring(currentTarget ~= nil and isAliveNpc(currentTarget)),
        "Fighting style: " .. tostring(currentFightingStyleName or "(unidentified)"),
        "Fighting style status: " .. tostring(fightingStyleStatus),
        "Engage threshold: " .. tostring(ARRIVAL_DISTANCE) .. " studs (harness setting, not style-verified)",
        "BNN combat dependencies: " .. tostring(bnnCombatDependencyStatus),
        "NPCs detected: " .. tostring(targetCount),
        "Spawn markers detected: " .. tostring(spawnMarkerCount),
        "BNN-style M1 sequence attempts: " .. tostring(attacksAttempted),
        "Target health drops observed after M1 request: " .. tostring(targetHealthDropsObserved),
        "Attack action status: " .. tostring(attackActionStatus),
        "Farm state: " .. tostring(farmState),
        "Farm running: " .. tostring(running),
        "Errors: " .. (#errors == 0 and "none" or table.concat(errors, " | ")),
    }
    lastReport = table.concat(lines, "\n")
    return lastReport
end

local statusLabel

local function setFarmState(state, message)
    farmState = state
    if statusLabel and message then
        statusLabel.Text = message
    end
end

local function recordError(err)
    table.insert(errors, tostring(err))
    if #errors > 5 then table.remove(errors, 1) end
end

local function safeCopy()
    local report = setReport()
    if typeof(setclipboard) ~= "function" then
        statusLabel.Text = "Clipboard unavailable — report shown in output"
        print(report)
        return
    end
    local ok = pcall(setclipboard, report)
    statusLabel.Text = ok and "Report copied" or "Copy failed — see output"
    if not ok then print(report) end
end

-- UI
local old = PLAYER_GUI:FindFirstChild("NpcFarmTestHarness")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "NpcFarmTestHarness"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = PLAYER_GUI

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(280, 300)
frame.Position = UDim2.new(0, 18, 0.32, 0)
frame.BackgroundColor3 = Color3.fromRGB(28, 29, 32)
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(82, 85, 91)
stroke.Thickness = 1
stroke.Parent = frame

local function makeLabel(name, text, pos, size, parent)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Text = text
    label.Position = pos
    label.Size = size
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(240, 240, 240)
    label.TextSize = 14
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end

local title = makeLabel("Title", "NPC FARM • TEST HARNESS", UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 25), frame)
title.Font = Enum.Font.GothamBold
title.TextSize = 15

statusLabel = makeLabel("Status", "Status: stopped", UDim2.fromOffset(12, 35), UDim2.new(1, -24, 0, 22), frame)
statusLabel.TextColor3 = Color3.fromRGB(255, 211, 115)

local selectedLabel = makeLabel("Selected", "NPC: (none)", UDim2.fromOffset(12, 60), UDim2.new(1, -24, 0, 22), frame)

local npcButton = Instance.new("TextButton")
npcButton.Name = "SelectNpc"
npcButton.Text = "SELECT NPC  ▼"
npcButton.Position = UDim2.fromOffset(12, 88)
npcButton.Size = UDim2.new(1, -24, 0, 34)
npcButton.BackgroundColor3 = Color3.fromRGB(53, 56, 62)
npcButton.TextColor3 = Color3.new(1, 1, 1)
npcButton.TextSize = 14
npcButton.Font = Enum.Font.GothamSemibold
npcButton.Parent = frame
Instance.new("UICorner", npcButton).CornerRadius = UDim.new(0, 5)

local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "NpcList"
listFrame.Position = UDim2.fromOffset(12, 126)
listFrame.Size = UDim2.new(1, -24, 0, 90)
listFrame.BackgroundColor3 = Color3.fromRGB(39, 41, 46)
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 5
listFrame.Visible = false
listFrame.CanvasSize = UDim2.fromOffset(0, 0)
listFrame.Parent = frame
Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 5)

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 3)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    listFrame.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 4)
end)

local function clearNpcList()
    for _, item in ipairs(listFrame:GetChildren()) do
        if item:IsA("TextButton") then item:Destroy() end
    end
end

local function refreshNpcList()
    clearNpcList()
    local questOption = Instance.new("TextButton")
    questOption.Name = "AutoQuestByLevel"
    questOption.Text = "AUTO QUEST • PLAYER LEVEL"
    questOption.LayoutOrder = 0
    questOption.Size = UDim2.new(1, -6, 0, 29)
    questOption.BackgroundColor3 = Color3.fromRGB(67, 87, 123)
    questOption.TextColor3 = Color3.new(1, 1, 1)
    questOption.TextSize = 13
    questOption.Font = Enum.Font.GothamSemibold
    questOption.Parent = listFrame
    Instance.new("UICorner", questOption).CornerRadius = UDim.new(0, 4)
    questOption.Activated:Connect(function()
        if running then
            statusLabel.Text = "Stop farming before changing target mode"
            return
        end
        questModeEnabled = true
        selectedNpcName = nil
        currentQuestName = nil
        currentQuestGiver = nil
        currentQuestTarget = nil
        questStatus = "Level-based quest mode selected"
        questReadyKey = nil
        questReadyAt = 0
        selectedLabel.Text = "Mode: Auto quest (level)"
        listFrame.Visible = false
        npcButton.Text = "SELECT NPC  ▼"
        statusLabel.Text = "Auto quest mode selected"
        setReport()
    end)

    local npcs = findNpcModels()
    targetCount = #npcs
    for index, npc in ipairs(npcs) do
        local button = Instance.new("TextButton")
        button.Name = "Npc_" .. npc.Name
        button.Text = npc.Name
        button.LayoutOrder = index
        button.Size = UDim2.new(1, -6, 0, 29)
        button.BackgroundColor3 = Color3.fromRGB(58, 61, 68)
        button.TextColor3 = Color3.new(1, 1, 1)
        button.TextSize = 13
        button.Font = Enum.Font.Gotham
        button.Parent = listFrame
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 4)
        button.Activated:Connect(function()
            if running then
                statusLabel.Text = "Stop farming before changing target mode"
                return
            end
            questModeEnabled = false
            selectedNpcName = npc.Name
            currentQuestName = nil
            currentQuestGiver = nil
            currentQuestTarget = nil
            questStatus = "Manual NPC mode"
            questReadyKey = nil
            questReadyAt = 0
            selectedLabel.Text = "NPC: " .. selectedNpcName
            listFrame.Visible = false
            npcButton.Text = "SELECT NPC  ▼"
            statusLabel.Text = "Selected " .. selectedNpcName
            setReport()
        end)
    end
    if #npcs == 0 then
        local empty = makeLabel("Empty", "No living NPCs found", UDim2.fromOffset(6, 3), UDim2.new(1, -12, 0, 24), listFrame)
        empty.LayoutOrder = 1
        empty.TextSize = 12
    end
end

npcButton.Activated:Connect(function()
    refreshNpcList()
    listFrame.Visible = not listFrame.Visible
    npcButton.Text = listFrame.Visible and "SELECT NPC  ▲" or "SELECT NPC  ▼"
end)

local function makeButton(name, text, pos, color)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Text = text
    button.Position = pos
    button.Size = UDim2.new(1, -24, 0, 32)
    button.BackgroundColor3 = color
    button.TextColor3 = Color3.new(1, 1, 1)
    button.TextSize = 14
    button.Font = Enum.Font.GothamBold
    button.Parent = frame
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 5)
    return button
end

local startButton = makeButton("Start", "START FARM", UDim2.fromOffset(12, 224), Color3.fromRGB(52, 125, 83))
local stopButton = makeButton("Stop", "STOP / RESTORE", UDim2.fromOffset(12, 260), Color3.fromRGB(164, 77, 66))

-- Mobile-friendly dragging by touch or mouse.
local dragging, dragInput, dragStart, frameStart
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        frameStart = frame.Position
        dragInput = input
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
title.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput and dragStart and frameStart then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(frameStart.X.Scale, frameStart.X.Offset + delta.X, frameStart.Y.Scale, frameStart.Y.Offset + delta.Y)
    end
end)

local function stopFarm()
    running = false
    farmSession += 1
    movementToken += 1
    questReadyKey = nil
    questReadyAt = 0
    local tween = activeTween
    activeTween = nil
    if tween then
        pcall(function() tween:Cancel() end)
    end
    setCurrentTarget(nil)
    setCurrentFightingStyle(nil, "Not checked (farm stopped)")
    attackActionStatus = "No attack loop active"
    startButton.Text = "START FARM"
    setFarmState("Stopped", "Status: stopped")
    setReport()
end

local function moveToPoint(positionProvider, validityProvider, session, arrivalDistance, verticalOffset)
    local character, humanoid, root = getCharacter()
    if not character then return false, "character-unavailable" end
    verticalOffset = verticalOffset == nil and HOVER_HEIGHT or verticalOffset
    local heightOffset = Vector3.new(0, verticalOffset, 0)
    local function getTargetPosition()
        if not validityProvider() then return nil end
        return normalizePosition(positionProvider())
    end
    local targetPosition = getTargetPosition()
    if not targetPosition then return false, "target-position-unavailable" end

    movementToken += 1
    local token = movementToken
    local destination = targetPosition + heightOffset
    local tween

    local function cancelTween()
        local previous = tween
        tween = nil
        if activeTween == previous then
            activeTween = nil
        end
        if previous then
            pcall(function() previous:Cancel() end)
        end
    end

    local function startTween(movingRoot, goal)
        local distance = (movingRoot.Position - goal).Magnitude
        local duration = math.max(0.1, distance / MOVE_SPEED)
        tween = TweenService:Create(
            movingRoot,
            TweenInfo.new(duration, Enum.EasingStyle.Linear),
            {CFrame = CFrame.new(goal)}
        )
        activeTween = tween
        tween:Play()
    end

    startTween(root, destination)

    local startTime = os.clock()
    while running and session == farmSession and token == movementToken do
        targetPosition = getTargetPosition()
        if not targetPosition then
            cancelTween()
            return false, "target-invalid"
        end
        local currentCharacter, currentHumanoid, currentRoot = getCharacter()
        if currentCharacter ~= character or not currentRoot or currentRoot ~= root or not currentHumanoid then
            cancelTween()
            return false, "character-changed"
        end
        local newDestination = targetPosition + heightOffset
        if (newDestination - destination).Magnitude > 4 then
            cancelTween()
            destination = newDestination
            startTween(currentRoot, destination)
        end
        if (currentRoot.Position - targetPosition).Magnitude <= arrivalDistance then
            cancelTween()
            return true, "arrived"
        end
        if os.clock() - startTime > 12 then
            cancelTween()
            return false, "movement-timeout"
        end
        RunService.Heartbeat:Wait()
    end
    cancelTween()
    if not running or session ~= farmSession or token ~= movementToken then
        return false, "cancelled"
    end
    return false, "movement-interrupted"
end

local function moveNearTarget(target, session)
    if not target or not isAliveNpc(target) then return false, "target-invalid" end
    local _, _, playerRoot = getCharacter()
    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    if not playerRoot or not targetRoot or not targetRoot:IsA("BasePart") then
        return false, "target-position-unavailable"
    end
    if (playerRoot.Position - targetRoot.Position).Magnitude <= ARRIVAL_DISTANCE then
        return true, "within-engage-threshold"
    end

    local awayFromTarget = Vector3.new(
        playerRoot.Position.X - targetRoot.Position.X,
        0,
        playerRoot.Position.Z - targetRoot.Position.Z
    )
    if awayFromTarget.Magnitude < 0.001 then
        local facing = targetRoot.CFrame.LookVector
        awayFromTarget = Vector3.new(-facing.X, 0, -facing.Z)
    end
    if awayFromTarget.Magnitude < 0.001 then
        return false, "approach-direction-unavailable"
    end
    local approachDirection = awayFromTarget.Unit
    return moveToPoint(
        function()
            local root = target:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") then
                return root.Position + approachDirection * MELEE_APPROACH_STANDOFF
            end
            return nil
        end,
        function() return currentTarget == target and isAliveNpc(target) end,
        session,
        MELEE_APPROACH_TOLERANCE,
        0
    )
end

local function moveToQuestGiver(position, session)
    local targetPosition = normalizePosition(position)
    if not targetPosition then return false, "quest-giver-position-unavailable" end
    return moveToPoint(
        function() return targetPosition end,
        function() return true end,
        session,
        QUEST_ACCEPT_RANGE
    )
end

local function collectBNNTargetHitParts(target, character, attackerRoot, combatUtil)
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies or not target:IsDescendantOf(enemies) then
        return nil, "Target is not under Workspace.Enemies"
    end
    local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    if not targetHumanoid or targetHumanoid.Health <= 0 or not targetRoot or not targetRoot:IsA("BasePart") then
        return nil, "Target rig is incomplete"
    end

    local characterSummoner = character:FindFirstChild("Summoner")
    local characterSummonerPlayer = characterSummoner and characterSummoner.Value
    if characterSummonerPlayer and characterSummonerPlayer:IsA("Player")
        and characterSummonerPlayer.Character == target
    then
        return nil, "Target is the player's summoned character"
    end
    local targetSummoner = target:FindFirstChild("Summoner")
    if targetSummoner and targetSummoner.Value == player then
        return nil, "Target is summoned by the player"
    end

    local vulnerableOk, vulnerable = pcall(function()
        return combatUtil:IsVulnerable(target)
    end)
    if not vulnerableOk then
        return nil, "CombatUtil:IsVulnerable failed: " .. tostring(vulnerable)
    end
    if not vulnerable then
        return nil, "Target is not vulnerable"
    end

    -- BNN's getBladeHits uses 10 + the passed range + half the target root width
    -- as a rig gate, then gathers body parts within range + half-width of the player root.
    local halfWidth = targetRoot.Size.X / 2
    if (targetRoot.Position - attackerRoot.Position).Magnitude > 10 + BNN_M1_HIT_SCAN_RANGE + halfWidth then
        return nil, "Target is outside BNN hit-scan range"
    end
    local hits = {}
    for _, part in ipairs(target:GetChildren()) do
        if part:IsA("BasePart") and BNN_M1_BODY_PARTS[part.Name]
            and (part.Position - attackerRoot.Position).Magnitude <= BNN_M1_HIT_SCAN_RANGE + halfWidth
        then
            local rigOk, rig = pcall(function()
                return combatUtil:GetRigOfHitPart(part)
            end)
            if rigOk and rig == target then
                -- BNN's AttackAOE keeps only the first valid hit part per rig.
                table.insert(hits, part)
                break
            end
        end
    end
    if #hits == 0 then
        return nil, "No valid BNN body-part hits found"
    end
    return hits
end

-- Mirrors ClickM1 -> AttackFunction(30) -> animated attackMelee. The BNN
-- no-animation setting branch is intentionally not used; CombatUtil:CanAttack
-- and the style's basic animation remain part of this request path.
local function attackTarget(target, session, styleTool)
    local character, playerHumanoid, root = getCharacter()
    local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")
    local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
    local targetAlive = isAliveNpc(target)
    if not attackContextIsCurrent(running, session, farmSession, target, currentTarget, targetAlive) then
        return false, "target-invalid"
    end
    if not character or not root or not styleTool or styleTool.Parent ~= character
        or not isFightingStyleTool(styleTool) or currentFightingStyleTool ~= styleTool
    then
        return false, "style-changed"
    end
    if not targetHumanoid or not targetRoot or not targetRoot:IsA("BasePart") then
        return false, "target-invalid"
    end
    if (root.Position - targetRoot.Position).Magnitude > ARRIVAL_DISTANCE then
        return false, "out-of-range"
    end
    if lastAttackTarget == target and lastAttackHealth and targetHumanoid.Health < lastAttackHealth then
        targetHealthDropsObserved += 1
        lastAttackHealth = targetHumanoid.Health
        attackActionStatus = "Target health decrease observed after M1 request; cause is not attributed"
    end
    local dependencies, dependencyError = resolveBNNCombatDependencies()
    if not dependencies then
        attackActionStatus = dependencyError
        return false, "combat-dependency-unavailable"
    end
    local stun = character:FindFirstChild("Stun")
    if not stun or typeof(stun.Value) ~= "number" then
        attackActionStatus = "BNN Stun.Value is unavailable; M1 suppressed"
        return false, "stun-state-unavailable"
    end
    if stun.Value ~= 0 then
        attackActionStatus = "M1 suppressed while stunned"
        return false, "stunned"
    end

    local hits, hitError = collectBNNTargetHitParts(target, character, root, dependencies.CombatUtil)
    if not hits then
        attackActionStatus = hitError
        return false, "no-valid-hits"
    end
    local movesetCacheOk, movesetCache = pcall(function()
        return dependencies.CombatUtil:GetMovesetAnimCache(character:FindFirstChildOfClass("Humanoid"))
    end)
    if not movesetCacheOk or type(movesetCache) ~= "table" then
        attackActionStatus = "CombatUtil moveset animation cache unavailable"
        return false, "moveset-unavailable"
    end
    local weaponNameOk, weaponName = pcall(function()
        return dependencies.CombatUtil:GetWeaponName(styleTool)
    end)
    if not weaponNameOk or not weaponName then
        attackActionStatus = "CombatUtil could not identify the equipped fighting style"
        return false, "weapon-data-unavailable"
    end
    local weaponDataOk, weaponData = pcall(function()
        return dependencies.CombatUtil:GetWeaponData(weaponName)
    end)
    if not weaponDataOk or type(weaponData) ~= "table"
        or type(weaponData.Moveset) ~= "table" or type(weaponData.Moveset.Basic) ~= "table"
        or #weaponData.Moveset.Basic == 0
    then
        attackActionStatus = "CombatUtil fighting-style moveset is unavailable"
        return false, "weapon-data-unavailable"
    end

    local canAttackOk, canAttack = pcall(function()
        return dependencies.CombatUtil:CanAttack(target, weaponData.WeaponType)
    end)
    if not canAttackOk then
        attackActionStatus = "CombatUtil:CanAttack failed: " .. tostring(canAttack)
        return false, "combat-check-error"
    end
    if not canAttack then
        attackActionStatus = "CombatUtil currently rejects this M1"
        return false, "combat-cooldown"
    end

    basicComboIndex += 1
    if basicComboIndex > #weaponData.Moveset.Basic then
        basicComboIndex = 1
    end
    local pureWeaponNameOk, pureWeaponName = pcall(function()
        return dependencies.CombatUtil:GetPureWeaponName(weaponName)
    end)
    if not pureWeaponNameOk or not pureWeaponName then
        attackActionStatus = "CombatUtil could not resolve the basic animation key"
        return false, "animation-unavailable"
    end
    local animationTrack = movesetCache[pureWeaponName .. "-basic" .. basicComboIndex]
    if not animationTrack then
        attackActionStatus = "Basic animation track is missing for the equipped style"
        return false, "animation-unavailable"
    end
    local speedMultiplier = animationTrack:GetAttribute("SpeedMult") or 1
    if typeof(speedMultiplier) ~= "number" or speedMultiplier <= 0 or animationTrack.Length <= 0 then
        attackActionStatus = "Basic animation duration or SpeedMult is invalid"
        return false, "animation-unavailable"
    end
    local latestCharacter, latestHumanoid, latestRoot = getCharacter()
    local latestTargetRoot = target:FindFirstChild("HumanoidRootPart")
    if not attackContextIsCurrent(running, session, farmSession, target, currentTarget, isAliveNpc(target))
        or latestCharacter ~= character or latestHumanoid ~= playerHumanoid or latestRoot ~= root
        or not latestTargetRoot or not latestTargetRoot:IsA("BasePart")
        or styleTool.Parent ~= character or currentFightingStyleTool ~= styleTool
        or (latestRoot.Position - latestTargetRoot.Position).Magnitude > ARRIVAL_DISTANCE
    then
        return false, "target-invalid"
    end

    local attackDuration = animationTrack.Length / speedMultiplier
    local primaryHit = hits[1]
    local additionalHits = {}
    for index = 2, #hits do
        table.insert(additionalHits, hits[index])
    end
    lastAttackTarget = target
    lastAttackHealth = targetHumanoid.Health
    attacksAttempted += 1
    local ok, err = pcall(function()
        dependencies.RegisterAttack:FireServer(attackDuration)
        dependencies.RegisterHit:FireServer(primaryHit, additionalHits)
        animationTrack:Play(0.1, 1, speedMultiplier)
    end)
    if not ok then
        attackActionStatus = "BNN M1 sequence failed; a partial remote request may have been sent"
        recordError(err)
        return false, "m1-error"
    end
    attackActionStatus = "BNN RegisterAttack/RegisterHit M1 request sent; server damage is not confirmed"
    return true, "m1-requested"
end

local function processQuestMode(session)
    local context, contextError = getQuestContext()
    if not context then
        currentQuestName = nil
        currentQuestGiver = nil
        currentQuestTarget = nil
        questStatus = contextError
        setFarmState("QuestUnavailable", "Quest data unavailable: " .. tostring(contextError))
        task.wait(RESCAN_INTERVAL)
        return nil
    end
    if not running or session ~= farmSession then return nil end

    local activeQuest, activeTarget = getActiveQuestTarget(context)
    if activeQuest and activeTarget then
        currentQuestName = tostring(activeQuest.QuestName or activeQuest.Name or "Active quest")
        currentQuestGiver = tostring(activeQuest.NPCName or "(unknown)")
        currentQuestTarget = activeTarget
        questStatus = "Active task read from GuideModule.Data.QuestData"
        questReadyKey = nil
        questReadyAt = 0
        setFarmState("QuestActive", "Active quest: farming " .. activeTarget)
        return activeTarget
    end

    local selection = selectQuestForLevel(context)
    if not selection then
        currentQuestName = nil
        currentQuestGiver = nil
        currentQuestTarget = nil
        questStatus = "No eligible BNN-shaped quest entry found"
        setFarmState("NoEligibleQuest", "No eligible quest found for level " .. tostring(context.level))
        task.wait(RESCAN_INTERVAL)
        return nil
    end

    currentQuestName = selection.QuestName
    currentQuestGiver = selection.GiverName
    currentQuestTarget = selection.Mob
    questStatus = string.format("Level %d selected quest %s (%s)", context.level, selection.QuestName, selection.Mob)

    local giverPosition = normalizePosition(selection.Position)
    if not giverPosition then
        questStatus = "Selected quest has no supported NPCList.Position"
        setFarmState("QuestPositionUnavailable", questStatus)
        task.wait(RESCAN_INTERVAL)
        return nil
    end

    local requestKey = tostring(selection.QuestName) .. ":" .. tostring(selection.Id)
    if questReadyKey ~= requestKey then
        questReadyKey = requestKey
        questReadyAt = 0
    end

    local _, _, root = getCharacter()
    if not root then
        setFarmState("WaitingForCharacter", "Waiting for a living character")
        task.wait(0.25)
        return nil
    end

    local distance = (root.Position - giverPosition).Magnitude
    if distance > QUEST_ACCEPT_RANGE then
        questReadyAt = 0
        setFarmState("MovingToQuestGiver", "Moving to " .. tostring(selection.GiverName or selection.QuestName))
        local arrived, moveReason = moveToQuestGiver(giverPosition, session)
        if not arrived and running and session == farmSession then
            questStatus = "Quest giver approach: " .. tostring(moveReason)
            setFarmState("QuestGiverMoveFailed", "Quest giver movement interrupted")
            task.wait(0.1)
        end
        return nil
    end

    if questReadyAt == 0 then
        questReadyAt = os.clock() + QUEST_ACCEPT_DELAY
        setFarmState("QuestReady", "At quest giver; waiting before request")
        return nil
    end
    if os.clock() < questReadyAt then
        setFarmState("QuestReady", "Waiting for quest state update")
        task.wait(0.2)
        return nil
    end

    questReadyAt = os.clock() + QUEST_ACCEPT_DELAY
    setFarmState("RequestingQuest", "Requesting " .. selection.QuestName)
    local sent, detail = requestQuestStart(selection)
    if not running or session ~= farmSession then return nil end
    questStatus = detail
    if not sent then
        recordError(detail)
        setFarmState("QuestRequestFailed", "Quest request unavailable; see report")
    else
        setFarmState("AwaitingQuest", "Request sent; awaiting active quest state")
    end
    return nil
end

startButton.Activated:Connect(function()
    if running then return end
    if not questModeEnabled and not selectedNpcName then
        statusLabel.Text = "Choose AUTO QUEST or select an NPC"
        return
    end
    local character, humanoid = getCharacter()
    if not character then
        statusLabel.Text = "Character not ready"
        return
    end
    running = true
    farmSession += 1
    local session = farmSession
    startButton.Text = "RUNNING..."
    setFarmState(
        "Acquiring",
        questModeEnabled and "Status: auto quest farming" or ("Status: farming " .. selectedNpcName)
    )
    local diedConnection = humanoid.Died:Connect(function()
        if running and session == farmSession then
            stopFarm()
        end
    end)
    task.spawn(function()
        local consecutiveErrors = 0
        local allowInitialStyleEquip = true
        while running and session == farmSession do
            local ok, err = pcall(function()
                local _, _, root = getCharacter()
                if not root then
                    setCurrentTarget(nil)
                    setFarmState("WaitingForCharacter", "Waiting for a living character")
                    task.wait(0.25)
                    return
                end

                local targetName = selectedNpcName
                if questModeEnabled then
                    targetName = processQuestMode(session)
                else
                    currentQuestName = nil
                    currentQuestGiver = nil
                    currentQuestTarget = nil
                    questStatus = "Manual NPC mode"
                end

                if targetName and running and session == farmSession then
                    local styleTool, styleReason = resolveFightingStyleTool(allowInitialStyleEquip)
                    if not styleTool then
                        setCurrentFightingStyle(nil, styleReason)
                        setCurrentTarget(nil)
                        attackActionStatus = "No attack attempted: fighting style is unidentified"
                        setFarmState("FightingStyleUnavailable", styleReason)
                        task.wait(0.5)
                    else
                        allowInitialStyleEquip = false
                        setCurrentFightingStyle(styleTool, "Equipped: " .. styleTool.Name)
                        setFarmState("Acquiring", "Searching for " .. targetName)
                        local candidates = findNpcModels()
                        targetCount = #candidates
                        local best, bestDistance
                        for _, npc in ipairs(candidates) do
                            if npc.Name == targetName and isAliveNpc(npc) then
                                local npcRoot = npc:FindFirstChild("HumanoidRootPart")
                                if npcRoot and root then
                                    local distance = (root.Position - npcRoot.Position).Magnitude
                                    if not bestDistance or distance < bestDistance then
                                        best, bestDistance = npc, distance
                                    end
                                end
                            end
                        end

                        if best then
                            setCurrentTarget(best)
                            setFarmState("Moving", "Moving to " .. best.Name)
                            local arrived, moveReason = moveNearTarget(best, session)
                            if running and session == farmSession and arrived and isAliveNpc(best) then
                                setFarmState("AttackAttempt", "BNN-style M1 attempt on " .. best.Name)
                                local attacked, attackReason = attackTarget(best, session, styleTool)
                                if attackReason == "m1-error" then
                                    setFarmState("M1Error", attackActionStatus)
                                    task.wait(0.25)
                                elseif attackReason == "combat-dependency-unavailable"
                                    or attackReason == "moveset-unavailable"
                                    or attackReason == "weapon-data-unavailable"
                                    or attackReason == "animation-unavailable"
                                then
                                    setFarmState("CombatUnavailable", attackActionStatus)
                                    task.wait(0.5)
                                elseif attackReason == "stun-state-unavailable" then
                                    setFarmState("CombatStateUnavailable", attackActionStatus)
                                    task.wait(0.5)
                                elseif attackReason == "stunned" then
                                    setFarmState("Stunned", attackActionStatus)
                                    task.wait(0.12)
                                elseif attackReason == "combat-cooldown" or attackReason == "cooldown" then
                                    setFarmState("AttackCooldown", attackActionStatus)
                                    task.wait(0.12)
                                elseif attackReason == "no-valid-hits" or attackReason == "combat-check-error" then
                                    setFarmState("NoValidM1Hits", attackActionStatus)
                                    task.wait(0.12)
                                elseif attackReason == "style-changed" then
                                    setFarmState("FightingStyleChanged", "Fighting style changed; rechecking")
                                    task.wait(0.1)
                                elseif attackReason == "out-of-range" then
                                    setFarmState("Repositioning", "Target moved out of range; repositioning")
                                    task.wait(0.1)
                                elseif not attacked and attackReason == "target-invalid" then
                                    setCurrentTarget(nil)
                                else
                                    task.wait(0.12)
                                end
                            elseif running and session == farmSession then
                                setCurrentTarget(nil)
                                if moveReason == "movement-timeout" then
                                    setFarmState("Reacquiring", "Movement timed out; reacquiring target")
                                else
                                    setFarmState("Reacquiring", "Target or movement changed; reacquiring")
                                end
                                task.wait(0.1)
                            end
                        else
                            setCurrentTarget(nil)
                            setFarmState("WaitingForTarget", "Waiting for " .. targetName .. " to spawn")
                            local markers = getSpawnMarkers(targetName)
                            spawnMarkerCount = #markers
                            task.wait(RESCAN_INTERVAL)
                        end
                    end
                elseif not questModeEnabled then
                    setCurrentTarget(nil)
                    setFarmState("WaitingForTarget", "Select an NPC or enable auto quest")
                    task.wait(RESCAN_INTERVAL)
                else
                    setCurrentTarget(nil)
                end
                setReport()
                task.wait(0.05)
            end)
            if not ok then
                if session == farmSession then
                    recordError(err)
                    consecutiveErrors += 1
                    if consecutiveErrors >= MAX_CONSECUTIVE_ERRORS then
                        stopFarm()
                        setFarmState("Error", "Stopped after repeated runtime errors")
                        setReport()
                    else
                        setFarmState(
                            "Retrying",
                            string.format("Temporary error; retry %d/%d", consecutiveErrors, MAX_CONSECUTIVE_ERRORS)
                        )
                        setReport()
                        task.wait(1)
                    end
                end
            else
                consecutiveErrors = 0
            end
            if not running or session ~= farmSession then
                break
            end
        end
        if diedConnection.Connected then
            diedConnection:Disconnect()
        end
    end)
end)

stopButton.Activated:Connect(stopFarm)

local selfTestButton = Instance.new("TextButton")
selfTestButton.Name = "SelfTest"
selfTestButton.Text = "SELF-TEST / COPY REPORT"
selfTestButton.Position = UDim2.fromOffset(12, 296)
selfTestButton.Size = UDim2.new(1, -24, 0, 30)
selfTestButton.BackgroundColor3 = Color3.fromRGB(67, 87, 123)
selfTestButton.TextColor3 = Color3.new(1, 1, 1)
selfTestButton.TextSize = 12
selfTestButton.Font = Enum.Font.GothamBold
selfTestButton.Parent = frame
Instance.new("UICorner", selfTestButton).CornerRadius = UDim.new(0, 5)
selfTestButton.Activated:Connect(function()
    local npcs = findNpcModels()
    targetCount = #npcs
    local markers = getSpawnMarkers(currentQuestTarget or selectedNpcName)
    spawnMarkerCount = #markers
    local character = getCharacter()
    local backpack = player:FindFirstChildOfClass("Backpack") or player:FindFirstChild("Backpack")
    local styleCandidate, styleSelectionStatus = chooseFightingStyleTool(
        collectFightingStyleTools(character),
        collectFightingStyleTools(backpack)
    )
    setCurrentFightingStyle(styleCandidate, styleSelectionStatus)
    local summary = string.format("Test: %d NPCs • %d markers", targetCount, spawnMarkerCount)
    local selectorTestPassed, selectorTestDetail = runQuestSelectorMockTest()
    questSelectorTestStatus = selectorTestPassed and "PASS: " .. selectorTestDetail or "FAIL: " .. selectorTestDetail
    summary = summary .. (selectorTestPassed and " • quest mock PASS" or " • quest mock FAIL")
    if not selectorTestPassed then
        recordError(selectorTestDetail)
    end
    local combatTestPassed, combatTestDetail = runCombatMockTests()
    combatTestStatus = combatTestPassed and "PASS: " .. combatTestDetail or "FAIL: " .. combatTestDetail
    summary = summary .. (combatTestPassed and " • combat mock PASS" or " • combat mock FAIL")
    if not combatTestPassed then
        recordError(combatTestDetail)
    end
    if questModeEnabled then
        local context, contextError = getQuestContext()
        if context then
            local selection = selectQuestForLevel(context)
            if selection then
                currentQuestName = selection.QuestName
                currentQuestGiver = selection.GiverName
                currentQuestTarget = selection.Mob
                questStatus = string.format(
                    "Level %d candidate: %s / %s",
                    context.level,
                    tostring(selection.QuestName),
                    tostring(selection.Mob)
                )
                summary = summary .. " • quest candidate: " .. tostring(selection.Mob)
            else
                questStatus = "No eligible BNN-shaped quest entry found"
                summary = summary .. " • no eligible quest"
            end
        else
            questStatus = contextError
            summary = summary .. " • quest data unavailable"
        end
    end
    statusLabel.Text = summary
    setReport()
    print(lastReport)
    safeCopy()
end)

-- Expand frame to fit self-test button.
frame.Size = UDim2.fromOffset(280, 336)

player.CharacterAdded:Connect(function()
    stopFarm()
    task.wait(0.5)
    setReport()
end)

task.spawn(function()
    while gui.Parent do
        if os.clock() - lastScan >= RESCAN_INTERVAL then
            lastScan = os.clock()
            if listFrame.Visible then refreshNpcList() end
            local markers = getSpawnMarkers(selectedNpcName)
            spawnMarkerCount = #markers
            targetCount = #findNpcModels()
        end
        task.wait(0.5)
    end
end)

setReport()
print("NPC Farm Test Harness loaded. Select AUTO QUEST or an NPC, equip a tool, then press START FARM.")
