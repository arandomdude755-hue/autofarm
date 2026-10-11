-- NPC Farm Test Harness — Mobile Edition
-- For testing in your own Roblox experience / private test place.
-- Uses ordinary client-side character movement and Tool:Activate().
-- It does NOT fire undocumented combat remotes or attempt to bypass server validation.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local PLAYER_GUI = player:WaitForChild("PlayerGui")

-- Tuning
local HOVER_HEIGHT = 7
local MOVE_SPEED = 55 -- studs/second
local ARRIVAL_DISTANCE = 9
local ATTACK_INTERVAL = 0.35
local RESCAN_INTERVAL = 2

local running = false
local selectedNpcName = nil
local currentTarget = nil
local movementToken = 0
local lastAttack = 0
local lastScan = 0
local lastReport = "Not tested yet."
local errors = {}
local attacksAttempted = 0
local targetCount = 0
local spawnMarkerCount = 0

local function getCharacter()
    local character = player.Character
    if not character then return nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then return nil end
    return character, humanoid, root
end

local function isAliveNpc(model)
    if not model or not model:IsA("Model") or model == player.Character then return false end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
    return humanoid ~= nil and humanoid.Health > 0 and root ~= nil
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

local function getEquippedTool()
    local character = player.Character
    if not character then return nil end
    for _, item in ipairs(character:GetChildren()) do
        if item:IsA("Tool") then return item end
    end
    return nil
end

local function setReport()
    local character, humanoid, root = getCharacter()
    local tool = getEquippedTool()
    local lines = {
        "NPC Farm Test Harness",
        "Player: " .. player.Name,
        "Character ready: " .. tostring(character ~= nil),
        "Selected NPC: " .. tostring(selectedNpcName or "(none)"),
        "Target alive: " .. tostring(currentTarget ~= nil and isAliveNpc(currentTarget)),
        "Equipped tool: " .. tostring(tool and tool.Name or "(none)"),
        "NPCs detected: " .. tostring(targetCount),
        "Spawn markers detected: " .. tostring(spawnMarkerCount),
        "Tool activations attempted: " .. tostring(attacksAttempted),
        "Farm running: " .. tostring(running),
        "Errors: " .. (#errors == 0 and "none" or table.concat(errors, " | ")),
    }
    lastReport = table.concat(lines, "\n")
    return lastReport
end

local statusLabel

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
    local npcs = findNpcModels()
    targetCount = #npcs
    for _, npc in ipairs(npcs) do
        local button = Instance.new("TextButton")
        button.Name = "Npc_" .. npc.Name
        button.Text = npc.Name
        button.Size = UDim2.new(1, -6, 0, 29)
        button.BackgroundColor3 = Color3.fromRGB(58, 61, 68)
        button.TextColor3 = Color3.new(1, 1, 1)
        button.TextSize = 13
        button.Font = Enum.Font.Gotham
        button.Parent = listFrame
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 4)
        button.Activated:Connect(function()
            selectedNpcName = npc.Name
            selectedLabel.Text = "NPC: " .. selectedNpcName
            listFrame.Visible = false
            npcButton.Text = "SELECT NPC  ▼"
            statusLabel.Text = "Selected " .. selectedNpcName
            setReport()
        end)
    end
    if #npcs == 0 then
        local empty = makeLabel("Empty", "No living NPCs found", UDim2.fromOffset(6, 3), UDim2.new(1, -12, 0, 24), listFrame)
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
    movementToken += 1
    currentTarget = nil
    startButton.Text = "START FARM"
    statusLabel.Text = "Status: stopped"
    setReport()
end

local function moveNearTarget(target)
    local character, humanoid, root = getCharacter()
    if not character or not target or not isAliveNpc(target) then return false end
    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return false end

    movementToken += 1
    local token = movementToken
    local destination = targetRoot.Position + Vector3.new(0, HOVER_HEIGHT, 0)
    local distance = (root.Position - destination).Magnitude
    local duration = math.max(0.1, distance / MOVE_SPEED)
    local tween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = CFrame.new(destination)})
    tween:Play()

    local startTime = os.clock()
    while running and token == movementToken and isAliveNpc(target) do
        local _, currentHumanoid, currentRoot = getCharacter()
        if not currentRoot or not currentHumanoid then
            tween:Cancel()
            return false
        end
        targetRoot = target:FindFirstChild("HumanoidRootPart")
        if not targetRoot then tween:Cancel(); return false end
        local newDestination = targetRoot.Position + Vector3.new(0, HOVER_HEIGHT, 0)
        if (newDestination - destination).Magnitude > 4 then
            tween:Cancel()
            destination = newDestination
            local remaining = math.max(0.1, (currentRoot.Position - destination).Magnitude / MOVE_SPEED)
            tween = TweenService:Create(currentRoot, TweenInfo.new(remaining, Enum.EasingStyle.Linear), {CFrame = CFrame.new(destination)})
            tween:Play()
        end
        if (currentRoot.Position - targetRoot.Position).Magnitude <= ARRIVAL_DISTANCE then
            tween:Cancel()
            return true
        end
        if os.clock() - startTime > 12 then
            tween:Cancel()
            return false
        end
        RunService.Heartbeat:Wait()
    end
    tween:Cancel()
    return false
end

local function attackTarget(target)
    if not target or not isAliveNpc(target) then return end
    local tool = getEquippedTool()
    if not tool then
        statusLabel.Text = "Equip a weapon/tool first"
        return
    end
    if os.clock() - lastAttack < ATTACK_INTERVAL then return end
    lastAttack = os.clock()
    attacksAttempted += 1
    local ok, err = pcall(function()
        tool:Activate()
    end)
    if not ok then
        table.insert(errors, tostring(err))
        if #errors > 5 then table.remove(errors, 1) end
    end
end

startButton.Activated:Connect(function()
    if running then return end
    if not selectedNpcName then
        statusLabel.Text = "Choose an NPC first"
        return
    end
    local character = getCharacter()
    if not character then
        statusLabel.Text = "Character not ready"
        return
    end
    running = true
    startButton.Text = "RUNNING..."
    statusLabel.Text = "Status: farming " .. selectedNpcName
    task.spawn(function()
        while running do
            local candidates = findNpcModels()
            targetCount = #candidates
            local best, bestDistance
            local _, _, root = getCharacter()
            for _, npc in ipairs(candidates) do
                if npc.Name == selectedNpcName and isAliveNpc(npc) then
                    local npcRoot = npc:FindFirstChild("HumanoidRootPart")
                    if root and npcRoot then
                        local distance = (root.Position - npcRoot.Position).Magnitude
                        if not bestDistance or distance < bestDistance then
                            best, bestDistance = npc, distance
                        end
                    end
                end
            end

            if best then
                currentTarget = best
                local arrived = moveNearTarget(best)
                if running and arrived and isAliveNpc(best) then
                    attackTarget(best)
                    task.wait(0.12)
                end
            else
                currentTarget = nil
                statusLabel.Text = "Waiting for " .. selectedNpcName .. " to spawn"
                local markers = getSpawnMarkers(selectedNpcName)
                spawnMarkerCount = #markers
                task.wait(RESCAN_INTERVAL)
            end
            setReport()
            task.wait(0.05)
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
    local markers = getSpawnMarkers(selectedNpcName)
    spawnMarkerCount = #markers
    local character = getCharacter()
    local tool = getEquippedTool()
    statusLabel.Text = string.format("Test: %d NPCs • %d markers", targetCount, spawnMarkerCount)
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
print("NPC Farm Test Harness loaded. Select an NPC, equip a tool, then press START FARM.")
