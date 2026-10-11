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
    Background = Color3.fromRGB(18, 21, 28),
    Header = Color3.fromRGB(23, 27, 36),
    TabBar = Color3.fromRGB(20, 24, 32),
    Panel = Color3.fromRGB(22, 26, 34),
    Control = Color3.fromRGB(27, 32, 42),
    Selected = Color3.fromRGB(30, 36, 48),
    Border = Color3.fromRGB(43, 49, 62),
    AccentBorder = Color3.fromRGB(69, 117, 190),
    Text = Color3.fromRGB(237, 239, 243),
    MutedText = Color3.fromRGB(157, 165, 177),
    Accent = Color3.fromRGB(79, 139, 224),
    Success = Color3.fromRGB(106, 190, 145),
    Warning = Color3.fromRGB(222, 184, 105),
    Error = Color3.fromRGB(224, 116, 108),
    Font = Enum.Font.Gotham,
    StrongFont = Enum.Font.GothamSemibold,
    MonoFont = Enum.Font.Code,
}

local Tabs = { "Main", "Farm", "Player", "Teleport", "Settings" }
local Pages = {
    Main = {
        Section = "Hub Overview",
        Meta = "LOCAL UI",
        Description = "Hub status and safe UI checks.",
        Controls = {
            {
                Kind = "button",
                Label = "Run UI self-check",
                Detail = "Checks this shell only; no gameplay action.",
                Action = "main.selfCheck",
                Badge = "CHECK",
            },
        },
    },
    Farm = {
        Section = "Farm Preview",
        Meta = "DISCONNECTED",
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
        Section = "Player Tools",
        Meta = "PLACEHOLDER",
        Description = "Player utilities are not connected.",
        Controls = {
            {
                Kind = "button",
                Label = "Character status",
                Detail = "Placeholder; no character data is read or changed.",
                Action = "player.status",
                Badge = "INFO",
            },
        },
    },
    Teleport = {
        Section = "Travel",
        Meta = "PLACEHOLDER",
        Description = "Travel actions are not connected.",
        Controls = {
            {
                Kind = "button",
                Label = "Travel status",
                Detail = "Placeholder; no movement or remote is invoked.",
                Action = "teleport.status",
                Badge = "INFO",
            },
        },
    },
    Settings = {
        Section = "Interface & Display",
        Meta = "LOCAL",
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
                Badge = "RESET",
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
local titlebar
local statusLabel
local tabButtons = {}
local toggleEntries = {}
local closeRegistry
local isCleaned = true
local selfTestRunning = true
local selfTestCancelled = false
local dragging = false
local dragInput
local dragStart
local dragOrigin

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
        local dot = statusLabel.Parent and statusLabel.Parent:FindFirstChild("StatusDot")
        if dot then
            dot.BackgroundColor3 = statusLabel.TextColor3
        end
    end
end

local function updateSize()
    if not root then
        return
    end

    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(390, 844)
    local landscape = viewport.X > viewport.Y
    local widthScale = state.compact and (touchEnabled and 0.92 or 0.72) or 0.96
    local heightScale = state.compact and (landscape and 0.84 or 0.78) or 0.9
    local maxWidth = landscape and 760 or 500
    local maxHeight = landscape and 360 or 740
    local width = math.min(viewport.X * widthScale, maxWidth, math.max(280, viewport.X - 16))
    local height = math.min(viewport.Y * heightScale, maxHeight, math.max(320, viewport.Y - 32))
    root.Size = UDim2.fromOffset(math.floor(width), math.floor(height))
end

local function updateIndicators()
    for tabName, button in pairs(tabButtons) do
        local selected = tabName == state.selectedTab
        button.BackgroundColor3 = selected and Theme.Selected or Theme.TabBar
        button.TextColor3 = selected and Theme.Text or Theme.MutedText
        local stroke = button:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = selected and Theme.AccentBorder or Theme.Border
            stroke.Transparency = selected and 0.18 or 0.72
        end
        local marker = button:FindFirstChild("ActiveMarker")
        if marker then
            marker.Visible = selected
        end
    end

    for _, entry in ipairs(toggleEntries) do
        if entry.Action == "preview.farm" then
            entry.Value.Text = state.farmPreview and "ON" or "OFF"
            entry.Value.BackgroundColor3 = state.farmPreview and Theme.Accent or Theme.TabBar
            entry.Value.TextColor3 = state.farmPreview and Theme.Text or Theme.MutedText
        elseif entry.Action == "settings.compact" then
            entry.Value.Text = state.compact and "ON" or "OFF"
            entry.Value.BackgroundColor3 = state.compact and Theme.Accent or Theme.TabBar
            entry.Value.TextColor3 = state.compact and Theme.Text or Theme.MutedText
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
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
        Font = Theme.Font,
        Text = page.Description,
        TextColor3 = Theme.MutedText,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        LayoutOrder = 1,
    }, content)

    local section = create("Frame", {
        Name = "SectionHeader",
        Size = UDim2.new(1, -2, 0, 26),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        LayoutOrder = 2,
    }, content)
    addCorner(section, 3)
    create("Frame", {
        Name = "AccentBar",
        Position = UDim2.fromOffset(7, 6),
        Size = UDim2.new(0, 3, 1, -12),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
    }, section)
    create("TextLabel", {
        Name = "SectionName",
        Position = UDim2.fromOffset(17, 0),
        Size = UDim2.new(1, -124, 1, 0),
        BackgroundTransparency = 1,
        Font = Theme.MonoFont,
        Text = string.upper(page.Section),
        TextColor3 = Theme.Text,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, section)
    create("TextLabel", {
        Name = "SectionMeta",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 0),
        Size = UDim2.fromOffset(92, 26),
        BackgroundTransparency = 1,
        Font = Theme.MonoFont,
        Text = page.Meta,
        TextColor3 = Theme.MutedText,
        TextSize = 8,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, section)

    for index, control in ipairs(page.Controls) do
        local hasValue = control.Kind == "previewToggle" or control.Kind == "settingToggle"
        local reserved = 78
        local row = create("TextButton", {
            Name = "Action_" .. control.Action:gsub("[^%w]", "_"),
            Size = UDim2.new(1, -2, 0, 68),
            BackgroundColor3 = Theme.Control,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            LayoutOrder = index + 2,
        }, content)
        addCorner(row, 3)
        addStroke(row)

        create("TextLabel", {
            Name = "Title",
            Position = UDim2.fromOffset(10, 8),
            Size = UDim2.new(1, -20 - reserved, 0, 22),
            BackgroundTransparency = 1,
            Font = Theme.StrongFont,
            Text = control.Label,
            TextColor3 = Theme.Text,
            TextSize = 13,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)

        create("TextLabel", {
            Name = "Detail",
            Position = UDim2.fromOffset(10, 32),
            Size = UDim2.new(1, -20, 0, 32),
            BackgroundTransparency = 1,
            Font = Theme.Font,
            Text = control.Detail,
            TextColor3 = Theme.MutedText,
            TextSize = 10,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
        }, row)

        if hasValue then
            local valueLabel = create("TextLabel", {
                Name = "Value",
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -10, 0, 10),
                Size = UDim2.fromOffset(58, 22),
                BackgroundColor3 = Theme.TabBar,
                BorderSizePixel = 0,
                Font = Theme.StrongFont,
                Text = "OFF",
                TextColor3 = Theme.MutedText,
                TextSize = 9,
                TextXAlignment = Enum.TextXAlignment.Center,
            }, row)
            addCorner(valueLabel, 3)
            addStroke(valueLabel)
            table.insert(toggleEntries, { Action = control.Action, Value = valueLabel })
        else
            local badge = create("TextLabel", {
                Name = "ActionBadge",
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -10, 0, 10),
                Size = UDim2.fromOffset(58, 22),
                BackgroundColor3 = Theme.TabBar,
                BorderSizePixel = 0,
                Font = Theme.MonoFont,
                Text = control.Badge or "OPEN",
                TextColor3 = Theme.Accent,
                TextSize = 8,
                TextXAlignment = Enum.TextXAlignment.Center,
            }, row)
            addCorner(badge, 3)
            addStroke(badge)
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
    titlebar = nil
    statusLabel = nil
    tabButtons = {}
    toggleEntries = {}
    dragging = false
    dragInput = nil
    dragStart = nil
    dragOrigin = nil

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
        Size = UDim2.fromOffset(350, 600),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
    }, screenGui)
    addCorner(root, 4)
    addStroke(root)
    create("UISizeConstraint", {
        MinSize = Vector2.new(280, 320),
        MaxSize = Vector2.new(760, 740),
    }, root)

    titlebar = create("Frame", {
        Name = "Titlebar",
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Theme.Header,
        BorderSizePixel = 0,
        Active = true,
    }, root)
    create("Frame", {
        Name = "LogoMark",
        Position = UDim2.fromOffset(10, 13),
        Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
    }, titlebar)
    create("Frame", {
        Name = "LogoCenter",
        Position = UDim2.fromOffset(5, 5),
        Size = UDim2.fromOffset(4, 4),
        BackgroundColor3 = Theme.Text,
        BorderSizePixel = 0,
    }, titlebar.LogoMark)
    create("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(0, 72, 1, 0),
        BackgroundTransparency = 1,
        Font = Theme.MonoFont,
        Text = "APEX HUB",
        TextColor3 = Theme.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, titlebar)
    local versionBadge = create("TextLabel", {
        Name = "VersionBadge",
        Position = UDim2.fromOffset(110, 11),
        Size = UDim2.fromOffset(50, 18),
        BackgroundColor3 = Theme.Selected,
        BorderSizePixel = 0,
        Font = Theme.MonoFont,
        Text = "UI TEST",
        TextColor3 = Theme.Accent,
        TextSize = 8,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, titlebar)
    addCorner(versionBadge, 2)
    addStroke(versionBadge)

    local closeButton = create("TextButton", {
        Name = "Close",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 7),
        Size = UDim2.fromOffset(28, 26),
        BackgroundColor3 = Theme.Control,
        BorderSizePixel = 0,
        Font = Theme.StrongFont,
        Text = "×",
        TextColor3 = Theme.MutedText,
        TextSize = 17,
    }, titlebar)
    addCorner(closeButton, 3)
    addStroke(closeButton)
    connect(persistentConnections, closeButton.Activated, function()
        cleanup()
    end)

    connect(persistentConnections, titlebar.InputBegan, function(input)
        if input.Position.X >= closeButton.AbsolutePosition.X then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragInput = input.UserInputType == Enum.UserInputType.Touch and input or nil
            dragStart = input.Position
            dragOrigin = root.AbsolutePosition
        end
    end)
    connect(persistentConnections, UserInputService.InputChanged, function(input)
        if not dragging or not dragStart or not dragOrigin then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= dragInput then
            return
        end

        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(390, 844)
        local delta = input.Position - dragStart
        local size = root.AbsoluteSize
        local x = math.clamp(dragOrigin.X + delta.X, 0, math.max(0, viewport.X - size.X))
        local y = math.clamp(dragOrigin.Y + delta.Y, 0, math.max(0, viewport.Y - size.Y))
        root.Position = UDim2.fromOffset(x + size.X / 2, y + size.Y / 2)
    end)
    connect(persistentConnections, UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input == dragInput then
            dragging = false
            dragInput = nil
            dragStart = nil
            dragOrigin = nil
        end
    end)

    local tabBar = create("Frame", {
        Name = "TabBar",
        Position = UDim2.fromOffset(0, 40),
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = Theme.TabBar,
        BorderSizePixel = 0,
    }, root)
    local tabWidth = 1 / #Tabs
    for index, tabName in ipairs(Tabs) do
        local button = create("TextButton", {
            Name = "Tab_" .. tabName,
            Position = UDim2.new((index - 1) * tabWidth, 2, 0, 4),
            Size = UDim2.new(tabWidth, -4, 0, 28),
            BackgroundColor3 = Theme.TabBar,
            BorderSizePixel = 0,
            Font = Theme.Font,
            Text = tabName,
            TextColor3 = Theme.MutedText,
            TextSize = 10,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, tabBar)
        addCorner(button, 3)
        addStroke(button)
        create("Frame", {
            Name = "ActiveMarker",
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, -2),
            Size = UDim2.fromOffset(12, 2),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Visible = false,
        }, button)
        connect(persistentConnections, button.Activated, function()
            selectTab(tabName)
        end)
        tabButtons[tabName] = button
    end

    scroll = create("ScrollingFrame", {
        Name = "Page",
        Position = UDim2.fromOffset(0, 76),
        Size = UDim2.new(1, 0, 1, -106),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.Accent,
        AutomaticCanvasSize = Enum.AutomaticSize.None,
    }, root)
    content = create("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(9, 7),
        Size = UDim2.new(1, -18, 0, 0),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
    }, scroll)
    contentLayout = create("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, content)

    local statusFrame = create("Frame", {
        Name = "Status",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Theme.TabBar,
        BorderSizePixel = 0,
    }, root)
    create("Frame", {
        Name = "StatusDot",
        Position = UDim2.fromOffset(10, 12),
        Size = UDim2.fromOffset(6, 6),
        BackgroundColor3 = Theme.Success,
        BorderSizePixel = 0,
    }, statusFrame)
    statusLabel = create("TextLabel", {
        Name = "Message",
        Position = UDim2.fromOffset(24, 0),
        Size = UDim2.new(1, -100, 1, 0),
        BackgroundTransparency = 1,
        Font = Theme.MonoFont,
        Text = state.status,
        TextColor3 = Theme.Success,
        TextSize = 9,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, statusFrame)
    local footerTag = create("TextLabel", {
        Name = "FooterTag",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 0),
        Size = UDim2.fromOffset(60, 30),
        BackgroundTransparency = 1,
        Font = Theme.MonoFont,
        Text = "UI ONLY",
        TextColor3 = Theme.MutedText,
        TextSize = 8,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, statusFrame)

    connect(persistentConnections, contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        if scroll then
            scroll.CanvasSize = UDim2.new(0, 0, 0, contentLayout.AbsoluteContentSize.Y)
        end
    end)
    local camera = workspace.CurrentCamera
    if camera then
        connect(persistentConnections, camera:GetPropertyChangedSignal("ViewportSize"), updateSize)
    end

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

    test("native window, section, and scrolling surfaces exist", function()
        selectTab("Main")
        local section = content:FindFirstChild("SectionHeader")
        return titlebar ~= nil and titlebar:IsA("Frame")
            and scroll ~= nil and scroll:IsA("ScrollingFrame")
            and section ~= nil and section:FindFirstChild("AccentBar") ~= nil
            and screenGui:FindFirstChild("Window"):FindFirstChild("Status") ~= nil
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
        local enabled = state.farmPreview and toggleEntries[1].Value.Text == "ON"
        activateControl(control)
        local disabled = not state.farmPreview and toggleEntries[1].Value.Text == "OFF"
        selectTab("Main")
        return enabled and disabled
    end)

    test("compact setting updates and restores window size", function()
        selectTab("Settings")
        local control = Pages.Settings.Controls[1]
        activateControl(control)
        local expandedWidth = root.Size.X.Offset
        local expandedHeight = root.Size.Y.Offset
        local expanded = not state.compact
        activateControl(control)
        local compactWidth = root.Size.X.Offset
        local compactHeight = root.Size.Y.Offset
        local compact = state.compact
        selectTab("Main")
        return expanded and compact and expandedWidth >= compactWidth and expandedHeight > compactHeight
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
    print("[CustomHub UI Test] MANUAL: tap all tabs and Close; also drag the titlebar and inspect text fit, contrast, and scroll feel on your phone.")
    setStatus(summary .. " MANUAL: inspect touch, drag, text, and scroll.", failed == 0 and "success" or "error")
    selfTestRunning = false
end)
