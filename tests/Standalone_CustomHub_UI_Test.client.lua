-- Standalone UI-only client test. No module imports, remotes, gameplay state, or executor APIs.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
if not player then
    warn("[CustomHub UI Test] FAIL: this must run in a client LocalScript context")
    return
end

local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
if not playerGui then
    warn("[CustomHub UI Test] FAIL: PlayerGui was not available")
    return
end

local GUI_NAME = "CustomHubMobileUiTest"
local CLEANUP_NAME = "CustomHubMobileUiTestCleanup"

-- The local BindableFunction keeps the previous run's cleanup callback available
-- without globals, arbitrary require paths, or executor-specific APIs.
local previousCleanup = playerGui:FindFirstChild(CLEANUP_NAME)
if previousCleanup then
    if previousCleanup:IsA("BindableFunction") then
        local cleaned, cleanupError = pcall(function()
            previousCleanup:Invoke()
        end)
        if not cleaned then
            warn("[CustomHub UI Test] Previous cleanup reported: " .. tostring(cleanupError))
        end
    end
    if previousCleanup.Parent then
        previousCleanup:Destroy()
    end
end

local orphanedGui = playerGui:FindFirstChild(GUI_NAME)
if orphanedGui then
    orphanedGui:Destroy()
end

local Theme = {
    Background = Color3.fromRGB(24, 26, 30),
    Panel = Color3.fromRGB(32, 35, 40),
    Control = Color3.fromRGB(40, 44, 50),
    Selected = Color3.fromRGB(54, 81, 103),
    Border = Color3.fromRGB(62, 67, 75),
    Text = Color3.fromRGB(237, 239, 243),
    MutedText = Color3.fromRGB(165, 172, 181),
    Accent = Color3.fromRGB(111, 166, 204),
    Success = Color3.fromRGB(128, 190, 151),
    Warning = Color3.fromRGB(222, 184, 105),
    Error = Color3.fromRGB(224, 116, 108),
    Font = Enum.Font.Gotham,
    StrongFont = Enum.Font.GothamSemibold,
}

local Tabs = { "Main", "Farm", "Player", "Teleport", "Settings" }
local Pages = {
    Main = {
        Description = "Hub status and safe UI checks.",
        Controls = {
            {
                Kind = "button",
                Label = "Run UI self-check",
                Detail = "Checks this shell only; no gameplay action.",
                Action = "main.selfCheck",
            },
        },
    },
    Farm = {
        Description = "Farm controls are UI-only previews.",
        Controls = {
            {
                Kind = "previewToggle",
                Label = "Auto farm preview",
                Detail = "Local preview state only. Does not scan, move, or attack.",
                Action = "preview.farm",
            },
        },
    },
    Player = {
        Description = "Player utilities are not connected.",
        Controls = {
            {
                Kind = "button",
                Label = "Character status",
                Detail = "Placeholder; no character data is read or changed.",
                Action = "player.status",
            },
        },
    },
    Teleport = {
        Description = "Travel actions are not connected.",
        Controls = {
            {
                Kind = "button",
                Label = "Travel status",
                Detail = "Placeholder; no movement or remote is invoked.",
                Action = "teleport.status",
            },
        },
    },
    Settings = {
        Description = "These settings affect only this local UI.",
        Controls = {
            {
                Kind = "settingToggle",
                Label = "Compact layout",
                Detail = "Changes only the shell's on-screen size.",
                Action = "settings.compact",
            },
            {
                Kind = "button",
                Label = "Reset UI settings",
                Detail = "Restores local presentation defaults.",
                Action = "settings.reset",
            },
        },
    },
}

local touchEnabled = UserInputService.TouchEnabled
local compactDefault = true
local state = {
    selectedTab = "Main",
    compact = compactDefault,
    farmPreview = false,
    status = "UI shell ready; gameplay features are disconnected.",
    statusKind = "success",
}

local persistentConnections = {}
local pageConnections = {}
local screenGui
local root
local scroll
local content
local contentLayout
local statusLabel
local tabButtons = {}
local toggleEntries = {}
local closeRegistry
local isCleaned = true
local selfTestRunning = true
local selfTestCancelled = false

local function create(className, properties, parent)
    local object = Instance.new(className)
    for property, value in pairs(properties) do
        object[property] = value
    end
    object.Parent = parent
    return object
end

local function addCorner(parent, radius)
    create("UICorner", { CornerRadius = UDim.new(0, radius or 6) }, parent)
end

local function addStroke(parent)
    create("UIStroke", {
        Color = Theme.Border,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

local function connect(bucket, signal, callback)
    local connection = signal:Connect(callback)
    table.insert(bucket, connection)
    return connection
end

local function disconnectAll(bucket)
    for index = #bucket, 1, -1 do
        local connection = bucket[index]
        if connection and connection.Connected then
            connection:Disconnect()
        end
        bucket[index] = nil
    end
end

local function setStatus(message, kind)
    local text = tostring(message)
    if #text > 88 then
        text = text:sub(1, 85) .. "..."
    end
    state.status = text
    state.statusKind = kind or "info"

    if statusLabel then
        statusLabel.Text = state.status
        if state.statusKind == "success" then
            statusLabel.TextColor3 = Theme.Success
        elseif state.statusKind == "warning" then
            statusLabel.TextColor3 = Theme.Warning
        elseif state.statusKind == "error" then
            statusLabel.TextColor3 = Theme.Error
        else
            statusLabel.TextColor3 = Theme.MutedText
        end
    end
end

local function updateSize()
    if not root then
        return
    end

    if state.compact then
        root.Size = touchEnabled and UDim2.fromScale(0.92, 0.78) or UDim2.fromScale(0.72, 0.78)
    else
        root.Size = UDim2.fromScale(0.96, 0.88)
    end
end

local function updateIndicators()
    for tabName, button in pairs(tabButtons) do
        local selected = tabName == state.selectedTab
        button.BackgroundColor3 = selected and Theme.Selected or Theme.Control
        button.TextColor3 = selected and Theme.Text or Theme.MutedText
    end

    for _, entry in ipairs(toggleEntries) do
        if entry.Action == "preview.farm" then
            entry.Value.Text = state.farmPreview and "Preview ON" or "Preview OFF"
        elseif entry.Action == "settings.compact" then
            entry.Value.Text = state.compact and "On" or "Off"
        end
    end
end

local renderTab

local function dispatch(action, value)
    if action == "main.selfCheck" then
        setStatus("UI action path is connected; no gameplay action was run.", "success")
    elseif action == "preview.farm" then
        state.farmPreview = value == true
        setStatus(state.farmPreview and "Farm preview ON; no farming code was started."
            or "Farm preview OFF; no farming code was started.", "info")
    elseif action == "player.status" then
        setStatus("Player tools are placeholders; no character data was read.", "info")
    elseif action == "teleport.status" then
        setStatus("Travel is a placeholder; no movement or remote was invoked.", "info")
    elseif action == "settings.compact" then
        state.compact = value == true
        updateSize()
        setStatus(state.compact and "Compact UI enabled." or "Expanded UI enabled.", "success")
    elseif action == "settings.reset" then
        state.selectedTab = "Main"
        state.compact = compactDefault
        state.farmPreview = false
        updateSize()
        setStatus("Local UI settings reset.", "success")
        renderTab("Main")
    else
        setStatus("Unknown UI action: " .. tostring(action), "error")
        return false
    end

    updateIndicators()
    return true
end

local function activateControl(control)
    if control.Kind == "previewToggle" then
        return dispatch(control.Action, not state.farmPreview)
    elseif control.Kind == "settingToggle" then
        return dispatch(control.Action, not state.compact)
    end
    return dispatch(control.Action, true)
end

local function clearPage()
    disconnectAll(pageConnections)
    toggleEntries = {}
    if not content then
        return
    end

    for _, child in ipairs(content:GetChildren()) do
        if child ~= contentLayout then
            child:Destroy()
        end
    end
end

renderTab = function(tabName)
    local page = Pages[tabName]
    if not page then
        setStatus("Unknown tab: " .. tostring(tabName), "error")
        return false
    end

    state.selectedTab = tabName
    clearPage()

    create("TextLabel", {
        Name = "PageDescription",
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundTransparency = 1,
        Font = Theme.Font,
        Text = page.Description,
        TextColor3 = Theme.MutedText,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 1,
    }, content)

    for index, control in ipairs(page.Controls) do
        local hasValue = control.Kind == "previewToggle" or control.Kind == "settingToggle"
        local reserved = hasValue and 98 or 0
        local row = create("TextButton", {
            Name = "Action_" .. control.Action:gsub("[^%w]", "_"),
            Size = UDim2.new(1, -4, 0, 72),
            BackgroundColor3 = Theme.Control,
            BorderSizePixel = 0,
            AutoButtonColor = true,
            Text = "",
            LayoutOrder = index + 1,
        }, content)
        addCorner(row, 5)
        addStroke(row)

        create("TextLabel", {
            Name = "Title",
            Position = UDim2.fromOffset(10, 7),
            Size = UDim2.new(1, -20 - reserved, 0, 22),
            BackgroundTransparency = 1,
            Font = Theme.StrongFont,
            Text = control.Label,
            TextColor3 = Theme.Text,
            TextSize = 14,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)

        create("TextLabel", {
            Name = "Detail",
            Position = UDim2.fromOffset(10, 31),
            Size = UDim2.new(1, -20, 0, 32),
            BackgroundTransparency = 1,
            Font = Theme.Font,
            Text = control.Detail,
            TextColor3 = Theme.MutedText,
            TextSize = 12,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
        }, row)

        if hasValue then
            local valueLabel = create("TextLabel", {
                Name = "Value",
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -10, 0, 8),
                Size = UDim2.fromOffset(90, 18),
                BackgroundTransparency = 1,
                Font = Theme.StrongFont,
                Text = "Off",
                TextColor3 = Theme.Accent,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Right,
            }, row)
            table.insert(toggleEntries, { Action = control.Action, Value = valueLabel })
        end

        connect(pageConnections, row.Activated, function()
            local ok, actionError = pcall(activateControl, control)
            if not ok then
                setStatus("UI action error: " .. tostring(actionError), "error")
            end
        end)
    end

    if scroll then
        scroll.CanvasPosition = Vector2.zero
    end
    updateIndicators()
    return true
end

local function selectTab(tabName)
    return renderTab(tabName)
end

local function cleanup(fromSelfTest)
    if isCleaned then
        return true
    end
    if not fromSelfTest and selfTestRunning then
        selfTestCancelled = true
    end
    isCleaned = true
    disconnectAll(pageConnections)
    disconnectAll(persistentConnections)

    if screenGui then
        screenGui:Destroy()
        screenGui = nil
    end
    root = nil
    scroll = nil
    content = nil
    contentLayout = nil
    statusLabel = nil
    tabButtons = {}
    toggleEntries = {}

    local registry = closeRegistry
    closeRegistry = nil
    if registry then
        registry.OnInvoke = nil
        if registry.Parent then
            registry:Destroy()
        end
    end
    return true
end

local function mount()
    isCleaned = false
    screenGui = create("ScreenGui", {
        Name = GUI_NAME,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 100,
    }, playerGui)

    root = create("Frame", {
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.92, 0.78),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
    }, screenGui)
    addCorner(root, 7)
    addStroke(root)
    create("UISizeConstraint", {
        MinSize = Vector2.new(270, 330),
        MaxSize = Vector2.new(500, 680),
    }, root)

    create("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(12, 7),
        Size = UDim2.new(1, -84, 0, 30),
        BackgroundTransparency = 1,
        Font = Theme.StrongFont,
        Text = "Custom Hub  ·  UI Test",
        TextColor3 = Theme.Text,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, root)

    local closeButton = create("TextButton", {
        Name = "Close",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 7),
        Size = UDim2.fromOffset(54, 28),
        BackgroundColor3 = Theme.Control,
        BorderSizePixel = 0,
        Font = Theme.Font,
        Text = "Close",
        TextColor3 = Theme.MutedText,
        TextSize = 12,
    }, root)
    addCorner(closeButton, 5)
    addStroke(closeButton)
    connect(persistentConnections, closeButton.Activated, function()
        cleanup()
    end)

    local tabWidth = 1 / #Tabs
    for index, tabName in ipairs(Tabs) do
        local button = create("TextButton", {
            Name = "Tab_" .. tabName,
            Position = UDim2.new((index - 1) * tabWidth, 0, 0, 42),
            Size = UDim2.new(tabWidth, -2, 0, 34),
            BackgroundColor3 = Theme.Control,
            BorderSizePixel = 0,
            Font = Theme.Font,
            Text = tabName,
            TextColor3 = Theme.MutedText,
            TextSize = 11,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, root)
        addCorner(button, 4)
        connect(persistentConnections, button.Activated, function()
            selectTab(tabName)
        end)
        tabButtons[tabName] = button
    end

    local statusFrame = create("Frame", {
        Name = "Status",
        Position = UDim2.fromOffset(0, 82),
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
    }, root)
    statusLabel = create("TextLabel", {
        Name = "Message",
        Position = UDim2.fromOffset(8, 4),
        Size = UDim2.new(1, -16, 1, -8),
        BackgroundTransparency = 1,
        Font = Theme.Font,
        Text = state.status,
        TextColor3 = Theme.Success,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, statusFrame)

    scroll = create("ScrollingFrame", {
        Name = "Page",
        Position = UDim2.new(0, 0, 0, 138),
        Size = UDim2.new(1, 0, 1, -148),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Theme.Accent,
        AutomaticCanvasSize = Enum.AutomaticSize.None,
    }, root)
    content = create("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, -8, 0, 0),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
    }, scroll)
    contentLayout = create("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, content)

    connect(persistentConnections, contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        if scroll then
            scroll.CanvasSize = UDim2.new(0, 0, 0, contentLayout.AbsoluteContentSize.Y)
        end
    end)

    closeRegistry = Instance.new("BindableFunction")
    closeRegistry.Name = CLEANUP_NAME
    closeRegistry.OnInvoke = function()
        return cleanup()
    end
    closeRegistry.Parent = playerGui

    updateSize()
    setStatus("UI shell ready; gameplay features are disconnected.", "success")
    renderTab(state.selectedTab)
end

local function recordTest(name, callback)
    local ok, result = pcall(callback)
    if ok and result ~= false then
        print("[CustomHub UI Test] PASS: " .. name)
        return true
    end
    local reason = ok and "check returned false" or tostring(result)
    warn("[CustomHub UI Test] FAIL: " .. name .. " — " .. reason)
    return false
end

local function countTestGuis()
    local count = 0
    for _, child in ipairs(playerGui:GetChildren()) do
        if child.Name == GUI_NAME and child:IsA("ScreenGui") then
            count += 1
        end
    end
    return count
end

mount()

if script and script:IsA("LocalScript") then
    connect(persistentConnections, script.Destroying, function()
        cleanup()
    end)
end

task.spawn(function()
    task.wait()
    if isCleaned or selfTestCancelled then
        return
    end

    local passed = 0
    local failed = 0
    local function test(name, callback)
        if recordTest(name, callback) then
            passed += 1
        else
            failed += 1
        end
    end

    test("single ScreenGui mounted", function()
        return screenGui ~= nil and screenGui.Parent == playerGui and countTestGuis() == 1
    end)

    test("all five tabs exist", function()
        for _, tabName in ipairs(Tabs) do
            if not tabButtons[tabName] or not tabButtons[tabName]:IsA("TextButton") then
                return false
            end
        end
        return true
    end)

    test("tab selection and active indicators", function()
        for _, tabName in ipairs(Tabs) do
            if not selectTab(tabName) or state.selectedTab ~= tabName then
                return false
            end
            if tabButtons[tabName].BackgroundColor3 ~= Theme.Selected then
                return false
            end
        end
        selectTab("Main")
        return true
    end)

    test("farm preview changes local state only", function()
        selectTab("Farm")
        local control = Pages.Farm.Controls[1]
        activateControl(control)
        local enabled = state.farmPreview and toggleEntries[1].Value.Text == "Preview ON"
        activateControl(control)
        local disabled = not state.farmPreview and toggleEntries[1].Value.Text == "Preview OFF"
        selectTab("Main")
        return enabled and disabled
    end)

    test("compact setting updates and restores window size", function()
        selectTab("Settings")
        local control = Pages.Settings.Controls[1]
        activateControl(control)
        local expanded = not state.compact and root.Size.X.Scale == 0.96 and root.Size.Y.Scale == 0.88
        activateControl(control)
        local compact = state.compact and root.Size.X.Scale == (touchEnabled and 0.92 or 0.72)
        selectTab("Main")
        return expanded and compact
    end)

    test("placeholder actions only update status", function()
        state.farmPreview = false
        selectTab("Main")
        activateControl(Pages.Main.Controls[1])
        local mainOk = string.find(state.status, "no gameplay action", 1, true) ~= nil
        selectTab("Player")
        activateControl(Pages.Player.Controls[1])
        local playerOk = string.find(state.status, "no character data was read", 1, true) ~= nil
        selectTab("Teleport")
        activateControl(Pages.Teleport.Controls[1])
        local travelOk = string.find(state.status, "no movement or remote was invoked", 1, true) ~= nil
        selectTab("Main")
        return mainOk and playerOk and travelOk and not state.farmPreview
    end)

    test("status error state is visible", function()
        setStatus("Self-test error display check.", "error")
        local visible = statusLabel.Text == state.status and statusLabel.TextColor3 == Theme.Error
        setStatus("UI self-test running.", "info")
        return visible
    end)

    selectTab("Settings")
    task.wait()
    if isCleaned or selfTestCancelled then
        return
    end
    test("tab text and toggle title fit current viewport", function()
        for _, tabName in ipairs(Tabs) do
            local button = tabButtons[tabName]
            if button.TextBounds.X > button.AbsoluteSize.X then
                return false
            end
        end

        local value
        for _, entry in ipairs(toggleEntries) do
            if entry.Action == "settings.compact" then
                value = entry.Value
                break
            end
        end
        local title = value and value.Parent:FindFirstChild("Title")
        if not title then
            return false
        end
        local noOverlap = title.AbsolutePosition.X + title.AbsoluteSize.X <= value.AbsolutePosition.X
        selectTab("Main")
        return noOverlap
    end)

    local settingsControls = Pages.Settings.Controls
    local scrollOverflow
    for index = 1, 8 do
        table.insert(settingsControls, {
            Kind = "button",
            Label = "Temporary scroll check " .. tostring(index),
            Detail = "Temporary UI test row; no game action.",
            Action = "main.selfCheck",
        })
    end
    selectTab("Settings")
    task.wait()
    task.wait()
    if isCleaned or selfTestCancelled then
        for index = 1, 8 do
            table.remove(settingsControls)
        end
        return
    end
    scrollOverflow = scroll and scroll.CanvasSize.Y.Offset > scroll.AbsoluteWindowSize.Y
    for index = 1, 8 do
        table.remove(settingsControls)
    end
    selectTab("Main")
    test("scroll view supports overflow", function()
        return scrollOverflow == true
    end)

    local oldGui = screenGui
    local oldConnections = {}
    for _, connection in ipairs(persistentConnections) do
        table.insert(oldConnections, connection)
    end
    for _, connection in ipairs(pageConnections) do
        table.insert(oldConnections, connection)
    end
    cleanup(true)

    test("cleanup removes UI and disconnects connections", function()
        if oldGui.Parent ~= nil or countTestGuis() ~= 0 then
            return false
        end
        for _, connection in ipairs(oldConnections) do
            if connection.Connected then
                return false
            end
        end
        return true
    end)

    if isCleaned and selfTestCancelled then
        selfTestRunning = false
        return
    end
    mount()
    test("replacement mount does not duplicate the interface", function()
        return screenGui ~= oldGui and screenGui.Parent == playerGui and countTestGuis() == 1
    end)

    local summary = string.format("Client self-test: %d PASS / %d FAIL.", passed, failed)
    print("[CustomHub UI Test] " .. summary)
    print("[CustomHub UI Test] MANUAL: tap all tabs and Close; inspect text fit, contrast, and scroll feel on your phone.")
    setStatus(summary .. " MANUAL: inspect touch, text fit, and scrolling.", failed == 0 and "success" or "error")
    selfTestRunning = false
end)
