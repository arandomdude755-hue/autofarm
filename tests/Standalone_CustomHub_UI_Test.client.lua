-- Standalone UI-only client test. No module imports, remotes, gameplay state, or executor APIs.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

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
local BUBBLE_HINT_SEEN_ATTRIBUTE = "CustomHubMobileUiTestBubbleHintSeen"

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
local activeTweens = {}
local tweenCompletedConnections = {}
local screenGui
local root
local windowScale
local scroll
local content
local contentLayout
local controlsContainer
local controlGridLayout
local currentControlCount = 0
local titlebar
local sizeConstraint
local minimizeButton
local bubbleContainer
local bubbleButton
local bubbleScale
local bubbleHalo
local bubbleRing
local bubblePing
local bubbleDot
local bubbleHint
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
local isMinimized = false
local bubbleDragging = false
local bubbleDragInput
local bubbleDragStart
local bubbleDragOrigin
local bubbleDragMoved = false
local pressedButtonScale
local pressedButtonInput
local transitionGeneration = 0
local hintAnimationGeneration = 0

local function create(className, properties, parent)
    local object = Instance.new(className)
    for property, value in pairs(properties) do
        object[property] = value
    end
    if className == "TextLabel" or className == "TextButton" or className == "TextBox" then
        object.AutoLocalize = false
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

local function cancelTween(instance)
    local tween = activeTweens[instance]
    if not tween then
        return
    end
    activeTweens[instance] = nil
    local connection = tweenCompletedConnections[instance]
    tweenCompletedConnections[instance] = nil
    if connection and connection.Connected then
        connection:Disconnect()
    end
    tween:Cancel()
end

local function playTween(instance, duration, goals, onComplete, delayTime, repeatCount, reverses)
    if not instance then
        return
    end
    cancelTween(instance)
    local tween = TweenService:Create(
        instance,
        TweenInfo.new(
            duration,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out,
            repeatCount or 0,
            reverses == true,
            delayTime or 0
        ),
        goals
    )
    activeTweens[instance] = tween
    local connection
    connection = tween.Completed:Connect(function(playbackState)
        if activeTweens[instance] == tween then
            activeTweens[instance] = nil
        end
        if tweenCompletedConnections[instance] == connection then
            tweenCompletedConnections[instance] = nil
        end
        if connection.Connected then
            connection:Disconnect()
        end
        if playbackState == Enum.PlaybackState.Completed and onComplete then
            onComplete()
        end
    end)
    tweenCompletedConnections[instance] = connection
    tween:Play()
    return tween
end

local function cancelAllTweens()
    local instances = {}
    for instance in pairs(activeTweens) do
        table.insert(instances, instance)
    end
    for _, instance in ipairs(instances) do
        cancelTween(instance)
    end
    table.clear(activeTweens)
    table.clear(tweenCompletedConnections)
end

local function attachButtonFeedback(button, connectionBucket, pressedScale)
    local scale = create("UIScale", { Scale = 1 }, button)
    connect(connectionBucket, button.MouseEnter, function()
        if not touchEnabled then
            playTween(scale, 0.1, { Scale = 1.025 })
        end
    end)
    connect(connectionBucket, button.MouseLeave, function()
        if pressedButtonScale ~= scale then
            playTween(scale, 0.1, { Scale = 1 })
        end
    end)
    connect(connectionBucket, button.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if pressedButtonScale and pressedButtonScale ~= scale and pressedButtonScale.Parent then
            playTween(pressedButtonScale, 0.1, { Scale = 1 })
        end
        pressedButtonScale = scale
        pressedButtonInput = input.UserInputType == Enum.UserInputType.Touch and input or nil
        playTween(scale, 0.07, { Scale = pressedScale or 0.96 })
    end)
    connect(connectionBucket, button.Activated, function()
        if pressedButtonScale == scale then
            pressedButtonScale = nil
            pressedButtonInput = nil
        end
        playTween(scale, 0.12, { Scale = 1 })
    end)
    return scale
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

local function setBubbleHintVisible(visible, immediate)
    if not bubbleHint then
        return
    end
    hintAnimationGeneration += 1
    local generation = hintAnimationGeneration
    local target = visible and 0 or 1

    if visible then
        bubbleHint.Visible = true
        if not immediate then
            bubbleHint.BackgroundTransparency = 1
            for _, descendant in ipairs(bubbleHint:GetDescendants()) do
                if descendant:IsA("TextLabel") then
                    descendant.TextTransparency = 1
                elseif descendant:IsA("UIStroke") then
                    descendant.Transparency = 1
                end
            end
        end
    end

    if immediate then
        bubbleHint.BackgroundTransparency = target
        for _, descendant in ipairs(bubbleHint:GetDescendants()) do
            if descendant:IsA("TextLabel") then
                descendant.TextTransparency = target
            elseif descendant:IsA("UIStroke") then
                descendant.Transparency = target
            end
        end
        bubbleHint.Visible = visible
        return
    end

    playTween(bubbleHint, 0.16, { BackgroundTransparency = target }, function()
        if generation == hintAnimationGeneration and not visible and bubbleHint then
            bubbleHint.Visible = false
        end
    end)
    for _, descendant in ipairs(bubbleHint:GetDescendants()) do
        if descendant:IsA("TextLabel") then
            playTween(descendant, 0.14, { TextTransparency = target })
        elseif descendant:IsA("UIStroke") then
            playTween(descendant, 0.14, { Transparency = target })
        end
    end
end

local function startBubbleAmbientAnimations()
    if not bubbleHalo or not bubblePing then
        return
    end

    cancelTween(bubbleHalo)
    cancelTween(bubblePing)
    bubbleHalo.Size = UDim2.fromOffset(70, 70)
    bubbleHalo.BackgroundTransparency = 0.84
    bubblePing.Size = UDim2.fromOffset(7, 7)
    bubblePing.BackgroundTransparency = 0.25

    -- A soft, slow halo pulse and an expanding status ping match the supplied HTML.
    playTween(bubbleHalo, 1.05, {
        Size = UDim2.fromOffset(78, 78),
        BackgroundTransparency = 0.97,
    }, nil, 0, -1, true)
    playTween(bubblePing, 0.9, {
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
    }, nil, 0, -1, false)
end

local function stopBubbleAmbientAnimations()
    if bubbleHalo then
        cancelTween(bubbleHalo)
        bubbleHalo.Size = UDim2.fromOffset(70, 70)
        bubbleHalo.BackgroundTransparency = 0.84
    end
    if bubblePing then
        cancelTween(bubblePing)
        bubblePing.Size = UDim2.fromOffset(7, 7)
        bubblePing.BackgroundTransparency = 1
    end
end

local function getClampedDragPosition(origin, delta, viewport, size)
    local halfX = math.min(size.X / 2, viewport.X / 2)
    local halfY = math.min(size.Y / 2, viewport.Y / 2)
    local startCenterX = viewport.X * origin.X.Scale + origin.X.Offset
    local startCenterY = viewport.Y * origin.Y.Scale + origin.Y.Offset
    local centerX = math.clamp(startCenterX + delta.X, halfX, math.max(halfX, viewport.X - halfX))
    local centerY = math.clamp(startCenterY + delta.Y, halfY, math.max(halfY, viewport.Y - halfY))
    return UDim2.new(
        origin.X.Scale,
        centerX - viewport.X * origin.X.Scale,
        origin.Y.Scale,
        centerY - viewport.Y * origin.Y.Scale
    )
end

local function minimizeWindow(fromSelfTest)
    if isCleaned or not root or not bubbleContainer or isMinimized then
        return false
    end
    isMinimized = true
    setStatus("Hub minimized; tap the bubble to restore.", "info")

    if fromSelfTest then
        transitionGeneration += 1
        cancelTween(windowScale)
        cancelTween(bubbleScale)
        stopBubbleAmbientAnimations()
        root.Visible = false
        windowScale.Scale = 1
        root.BackgroundTransparency = 0
        bubbleContainer.Visible = true
        bubbleScale.Scale = 1
        setBubbleHintVisible(false, true)
        return true
    end

    transitionGeneration += 1
    local generation = transitionGeneration
    if not root.Visible then
        windowScale.Scale = 0.93
        root.BackgroundTransparency = 0.18
    end
    root.Visible = true
    local bubbleWasVisible = bubbleContainer.Visible
    bubbleContainer.Visible = true
    if not bubbleWasVisible then
        bubbleScale.Scale = 0.9
    end

    if player:GetAttribute(BUBBLE_HINT_SEEN_ATTRIBUTE) ~= true then
        player:SetAttribute(BUBBLE_HINT_SEEN_ATTRIBUTE, true)
        setBubbleHintVisible(true)
        local hintGeneration = hintAnimationGeneration
        task.delay(3.25, function()
            if not isCleaned and isMinimized and hintAnimationGeneration == hintGeneration then
                setBubbleHintVisible(false)
            end
        end)
    else
        setBubbleHintVisible(false, true)
    end

    playTween(bubbleScale, 0.15, { Scale = 1 })
    startBubbleAmbientAnimations()
    playTween(windowScale, 0.17, { Scale = 0.93 }, function()
        if generation == transitionGeneration and isMinimized and root then
            root.Visible = false
            windowScale.Scale = 1
            root.BackgroundTransparency = 0
        end
    end)
    playTween(root, 0.17, { BackgroundTransparency = 0.18 })
    return true
end

local function restoreWindow(fromSelfTest)
    if isCleaned or not root or not bubbleContainer or not isMinimized then
        return false
    end
    isMinimized = false
    setStatus("Hub restored; UI-only preview.", "info")

    if fromSelfTest then
        transitionGeneration += 1
        cancelTween(windowScale)
        cancelTween(bubbleScale)
        stopBubbleAmbientAnimations()
        root.Visible = true
        root.BackgroundTransparency = 0
        windowScale.Scale = 1
        bubbleContainer.Visible = false
        bubbleScale.Scale = 1
        setBubbleHintVisible(false, true)
        return true
    end

    transitionGeneration += 1
    local generation = transitionGeneration
    bubbleContainer.Visible = true
    setBubbleHintVisible(false)
    stopBubbleAmbientAnimations()

    -- Finish hiding the bubble before mounting the window again, so the two never overlap.
    playTween(bubbleScale, 0.14, { Scale = 0.88 }, function()
        if generation == transitionGeneration and not isMinimized and bubbleContainer and root then
            bubbleContainer.Visible = false
            bubbleScale.Scale = 1
            windowScale.Scale = 0.94
            root.BackgroundTransparency = 0.18
            root.Visible = true
            playTween(windowScale, 0.18, { Scale = 1 })
            playTween(root, 0.18, { BackgroundTransparency = 0 })
        end
    end)
    return true
end

local function getColumnCount(availableWidth, controlCount, landscape)
    if landscape and availableWidth >= 620 and controlCount > 1 then
        return 2
    end
    return 1
end

local function clampBubbleToViewport()
    if not bubbleContainer then
        return
    end
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(390, 844)
    local halfSize = bubbleContainer.AbsoluteSize / 2
    local halfX = math.min(halfSize.X, viewport.X / 2)
    local halfY = math.min(halfSize.Y, viewport.Y / 2)
    local position = bubbleContainer.Position
    local x = math.clamp(position.X.Offset, halfX, math.max(halfX, viewport.X - halfX))
    local y = math.clamp(position.Y.Offset, halfY, math.max(halfY, viewport.Y - halfY))
    bubbleContainer.Position = UDim2.fromOffset(x, y)
    if bubbleHint then
        local leftFits = x >= bubbleHint.AbsoluteSize.X + halfSize.X + 8
        bubbleHint.Position = leftFits and UDim2.new(0, -154, 0.5, -19) or UDim2.new(1, 14, 0.5, -19)
    end
end

local function syncControlGridHeight()
    if controlsContainer and controlGridLayout then
        controlsContainer.Size = UDim2.new(1, -2, 0, controlGridLayout.AbsoluteContentSize.Y)
    end
end

local function updateControlGridLayout()
    if not controlsContainer or not controlGridLayout then
        return
    end

    local camera = workspace.CurrentCamera
    local landscape = camera ~= nil and camera.ViewportSize.X > camera.ViewportSize.Y
    local columnCount = getColumnCount(controlsContainer.AbsoluteSize.X, currentControlCount, landscape)
    local cellSize = columnCount == 2 and UDim2.new(0.5, -4, 0, 68) or UDim2.new(1, 0, 0, 68)
    if controlGridLayout.FillDirectionMaxCells ~= columnCount then
        controlGridLayout.FillDirectionMaxCells = columnCount
    end
    if controlGridLayout.CellSize ~= cellSize then
        controlGridLayout.CellSize = cellSize
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
    local maxWidth = landscape and 760 or 500
    local maxHeight = math.min(landscape and 420 or 740, math.max(1, viewport.Y - 32))
    local minHeight = math.min(landscape and 300 or 320, maxHeight)
    local availableWidth = math.max(1, viewport.X - 16)
    local width = math.min(viewport.X * widthScale, maxWidth, availableWidth)
    local pageHeight = contentLayout and contentLayout.AbsoluteContentSize.Y or 0
    local desiredHeight = 76 + 30 + pageHeight + 14
    local height = math.clamp(desiredHeight, minHeight, maxHeight)
    if sizeConstraint then
        sizeConstraint.MinSize = Vector2.new(math.min(280, width), minHeight)
        sizeConstraint.MaxSize = Vector2.new(maxWidth, maxHeight)
    end
    root.Size = UDim2.fromOffset(math.floor(width), math.floor(height))
    clampBubbleToViewport()
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
            if selected and not marker.Visible then
                marker.Size = UDim2.fromOffset(0, 2)
                marker.BackgroundTransparency = 0.2
                marker.Visible = true
                playTween(marker, 0.14, {
                    Size = UDim2.fromOffset(12, 2),
                    BackgroundTransparency = 0,
                })
            elseif not selected then
                cancelTween(marker)
                marker.Visible = false
                marker.Size = UDim2.fromOffset(0, 2)
                marker.BackgroundTransparency = 1
            end
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
    controlsContainer = nil
    controlGridLayout = nil
    currentControlCount = 0
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

    currentControlCount = #page.Controls
    controlsContainer = create("Frame", {
        Name = "ControlGrid",
        Size = UDim2.new(1, -2, 0, 0),
        BackgroundTransparency = 1,
        LayoutOrder = 3,
    }, content)
    controlGridLayout = create("UIGridLayout", {
        CellSize = UDim2.new(1, 0, 0, 68),
        CellPadding = UDim2.fromOffset(8, 6),
        FillDirection = Enum.FillDirection.Horizontal,
        FillDirectionMaxCells = 1,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, controlsContainer)
    connect(pageConnections, controlGridLayout:GetPropertyChangedSignal("AbsoluteContentSize"), syncControlGridHeight)
    connect(pageConnections, controlsContainer:GetPropertyChangedSignal("AbsoluteSize"), updateControlGridLayout)

    for index, control in ipairs(page.Controls) do
        local hasValue = control.Kind == "previewToggle" or control.Kind == "settingToggle"
        local reserved = 78
        local row = create("TextButton", {
            Name = "Action_" .. control.Action:gsub("[^%w]", "_"),
            Size = UDim2.new(1, 0, 0, 68),
            BackgroundColor3 = Theme.Control,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            LayoutOrder = index,
        }, controlsContainer)
        addCorner(row, 3)
        addStroke(row)
        attachButtonFeedback(row, pageConnections)

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

    updateControlGridLayout()
    syncControlGridHeight()
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
    transitionGeneration += 1
    hintAnimationGeneration += 1
    cancelAllTweens()

    if screenGui then
        screenGui:Destroy()
        screenGui = nil
    end
    root = nil
    windowScale = nil
    scroll = nil
    content = nil
    contentLayout = nil
    controlsContainer = nil
    controlGridLayout = nil
    currentControlCount = 0
    titlebar = nil
    sizeConstraint = nil
    minimizeButton = nil
    bubbleContainer = nil
    bubbleButton = nil
    bubbleScale = nil
    bubbleHalo = nil
    bubbleRing = nil
    bubblePing = nil
    bubbleDot = nil
    bubbleHint = nil
    statusLabel = nil
    tabButtons = {}
    toggleEntries = {}
    dragging = false
    dragInput = nil
    dragStart = nil
    dragOrigin = nil
    isMinimized = false
    bubbleDragging = false
    bubbleDragInput = nil
    bubbleDragStart = nil
    bubbleDragOrigin = nil
    bubbleDragMoved = false
    pressedButtonScale = nil
    pressedButtonInput = nil

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
        AutoLocalize = false,
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
    windowScale = create("UIScale", { Scale = 1 }, root)
    sizeConstraint = create("UISizeConstraint", {
        MinSize = Vector2.new(280, 280),
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

    minimizeButton = create("TextButton", {
        Name = "Minimize",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -42, 0, 7),
        Size = UDim2.fromOffset(26, 26),
        BackgroundColor3 = Theme.Control,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Theme.StrongFont,
        Text = "−",
        TextColor3 = Theme.MutedText,
        TextSize = 17,
    }, titlebar)
    addCorner(minimizeButton, 3)
    addStroke(minimizeButton)
    attachButtonFeedback(minimizeButton, persistentConnections)
    connect(persistentConnections, minimizeButton.Activated, minimizeWindow)

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
    attachButtonFeedback(closeButton, persistentConnections)
    connect(persistentConnections, closeButton.Activated, function()
        cleanup()
    end)

    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(390, 844)
    bubbleContainer = create("Frame", {
        Name = "FloatingBubble",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(viewport.X - 42, viewport.Y / 2),
        Size = UDim2.fromOffset(64, 64),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 20,
    }, screenGui)
    bubbleHalo = create("Frame", {
        Name = "PulseHalo",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(70, 70),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.84,
        BorderSizePixel = 0,
        ZIndex = 19,
    }, bubbleContainer)
    addCorner(bubbleHalo, 40)

    bubbleRing = create("Frame", {
        Name = "Ring",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(64, 64),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 20,
    }, bubbleContainer)
    for index = 1, 12 do
        local angle = (index - 1) * 30
        local radians = math.rad(angle)
        create("Frame", {
            Name = "Dash_" .. tostring(index),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, math.cos(radians) * 30, 0.5, math.sin(radians) * 30),
            Size = UDim2.fromOffset(3, 1),
            Rotation = angle + 90,
            BackgroundColor3 = Theme.AccentBorder,
            BackgroundTransparency = 0.28,
            BorderSizePixel = 0,
            ZIndex = 20,
        }, bubbleRing)
    end

    bubbleButton = create("TextButton", {
        Name = "Restore",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(56, 56),
        BackgroundColor3 = Theme.Header,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        ZIndex = 21,
    }, bubbleContainer)
    addCorner(bubbleButton, 28)
    bubbleScale = create("UIScale", { Scale = 1 }, bubbleButton)
    create("UIStroke", {
        Color = Theme.Border,
        Thickness = 2,
        Transparency = 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, bubbleButton)
    attachButtonFeedback(bubbleButton, persistentConnections, 0.9)
    local bubbleButtonStroke = bubbleButton:FindFirstChildOfClass("UIStroke")
    connect(persistentConnections, bubbleButton.MouseEnter, function()
        if not touchEnabled and bubbleButtonStroke then
            playTween(bubbleButtonStroke, 0.12, { Color = Theme.AccentBorder })
        end
    end)
    connect(persistentConnections, bubbleButton.MouseLeave, function()
        if bubbleButtonStroke then
            playTween(bubbleButtonStroke, 0.12, { Color = Theme.Border })
        end
    end)
    create("TextLabel", {
        Name = "Glyph",
        Position = UDim2.fromOffset(18, 5),
        Size = UDim2.fromOffset(20, 22),
        BackgroundTransparency = 1,
        TextTransparency = 1,
        Font = Theme.StrongFont,
        Text = "⌂",
        TextColor3 = Theme.Accent,
        TextSize = 19,
        ZIndex = 22,
    }, bubbleButton)
    create("TextLabel", {
        Name = "Brand",
        Position = UDim2.fromOffset(0, 29),
        Size = UDim2.new(1, 0, 0, 12),
        BackgroundTransparency = 1,
        TextTransparency = 1,
        Font = Theme.MonoFont,
        Text = "APEX",
        TextColor3 = Theme.Text,
        TextSize = 8,
        ZIndex = 22,
    }, bubbleButton)
    bubblePing = create("Frame", {
        Name = "UiStatusPing",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 8),
        Size = UDim2.fromOffset(7, 7),
        BackgroundColor3 = Theme.Success,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 22,
    }, bubbleButton)
    addCorner(bubblePing, 10)
    bubbleDot = create("Frame", {
        Name = "UiStatusDot",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 8),
        Size = UDim2.fromOffset(7, 7),
        BackgroundColor3 = Theme.Success,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ZIndex = 23,
    }, bubbleButton)
    addCorner(bubbleDot, 4)
    create("UIStroke", {
        Color = Theme.Header,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, bubbleDot)
    for index, width in ipairs({ 4, 8, 4 }) do
        create("Frame", {
            Name = "Grip_" .. tostring(index),
            Position = UDim2.new(0.5, (index - 2) * 6 - width / 2, 1, -7),
            Size = UDim2.fromOffset(width, 1),
            BackgroundColor3 = Theme.MutedText,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 22,
        }, bubbleButton)
    end
    bubbleHint = create("Frame", {
        Name = "Hint",
        Position = UDim2.new(0, -154, 0.5, -19),
        Size = UDim2.fromOffset(140, 38),
        BackgroundColor3 = Theme.Header,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 20,
    }, bubbleContainer)
    addCorner(bubbleHint, 3)
    addStroke(bubbleHint)
    local hintStroke = bubbleHint:FindFirstChildOfClass("UIStroke")
    if hintStroke then
        hintStroke.Transparency = 1
    end
    create("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(8, 4),
        Size = UDim2.new(1, -16, 0, 13),
        BackgroundTransparency = 1,
        TextTransparency = 1,
        Font = Theme.MonoFont,
        Text = "APEX  /  UI ONLY",
        TextColor3 = Theme.Accent,
        TextSize = 8,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 21,
    }, bubbleHint)
    create("TextLabel", {
        Name = "HintText",
        Position = UDim2.fromOffset(8, 19),
        Size = UDim2.new(1, -16, 0, 13),
        BackgroundTransparency = 1,
        TextTransparency = 1,
        Font = Theme.Font,
        Text = "Tap to restore • Drag to move",
        TextColor3 = Theme.MutedText,
        TextSize = 8,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 21,
    }, bubbleHint)
    connect(persistentConnections, bubbleButton.Activated, function()
        if not bubbleDragMoved then
            restoreWindow()
        end
        bubbleDragMoved = false
    end)
    connect(persistentConnections, bubbleButton.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            bubbleDragging = true
            bubbleDragInput = input.UserInputType == Enum.UserInputType.Touch and input or nil
            bubbleDragStart = input.Position
            bubbleDragOrigin = bubbleContainer.Position
            bubbleDragMoved = false
        end
    end)

    connect(persistentConnections, titlebar.InputBegan, function(input)
        if input.Position.X >= minimizeButton.AbsolutePosition.X then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragInput = input.UserInputType == Enum.UserInputType.Touch and input or nil
            dragStart = input.Position
            dragOrigin = root.Position
        end
    end)
    connect(persistentConnections, UserInputService.InputChanged, function(input)
        if bubbleDragging and bubbleDragStart and bubbleDragOrigin
            and (input.UserInputType == Enum.UserInputType.MouseMovement or input == bubbleDragInput) then
            local delta = input.Position - bubbleDragStart
            if delta.Magnitude >= 8 then
                bubbleDragMoved = true
            end
            if bubbleDragMoved and bubbleContainer then
                local camera = workspace.CurrentCamera
                local viewport = camera and camera.ViewportSize or Vector2.new(390, 844)
                bubbleContainer.Position = getClampedDragPosition(
                    bubbleDragOrigin,
                    delta,
                    viewport,
                    bubbleContainer.AbsoluteSize
                )
            end
        end

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
        root.Position = getClampedDragPosition(dragOrigin, delta, viewport, size)
    end)
    connect(persistentConnections, UserInputService.InputEnded, function(input)
        if pressedButtonScale
            and (input.UserInputType == Enum.UserInputType.MouseButton1 or input == pressedButtonInput) then
            local scale = pressedButtonScale
            pressedButtonScale = nil
            pressedButtonInput = nil
            if scale.Parent then
                playTween(scale, 0.12, { Scale = 1 })
            end
        end

        if bubbleDragging
            and (input.UserInputType == Enum.UserInputType.MouseButton1 or input == bubbleDragInput) then
            bubbleDragging = false
            bubbleDragInput = nil
            bubbleDragStart = nil
            bubbleDragOrigin = nil
        end

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
        attachButtonFeedback(button, persistentConnections)
        create("Frame", {
            Name = "ActiveMarker",
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, -2),
            Size = UDim2.fromOffset(0, 2),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 1,
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
        updateSize()
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
    updateSize()
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

    test("custom UI labels opt out of automatic translation", function()
        return screenGui.AutoLocalize == false
            and tabButtons.Teleport.AutoLocalize == false
            and tabButtons.Teleport.Text == "Teleport"
    end)

    test("responsive grid threshold avoids narrow two-column cards", function()
        return getColumnCount(619, 2, true) == 1
            and getColumnCount(620, 2, true) == 2
            and getColumnCount(800, 1, true) == 1
            and getColumnCount(800, 2, false) == 1
    end)

    test("window drag keeps its starting position before pointer movement", function()
        local initial = UDim2.fromScale(0.5, 0.5)
        local unchanged = getClampedDragPosition(
            initial,
            Vector2.new(0, 0),
            Vector2.new(844, 390),
            Vector2.new(700, 360)
        )
        local moved = getClampedDragPosition(
            initial,
            Vector2.new(18, 12),
            Vector2.new(844, 390),
            Vector2.new(700, 360)
        )
        local bubbleOrigin = UDim2.fromOffset(400, 195)
        local bubbleUnchanged = getClampedDragPosition(
            bubbleOrigin,
            Vector2.new(0, 0),
            Vector2.new(844, 390),
            Vector2.new(64, 64)
        )
        local bubbleMoved = getClampedDragPosition(
            bubbleOrigin,
            Vector2.new(18, 12),
            Vector2.new(844, 390),
            Vector2.new(64, 64)
        )
        return unchanged.X.Scale == initial.X.Scale
            and unchanged.X.Offset == initial.X.Offset
            and unchanged.Y.Scale == initial.Y.Scale
            and unchanged.Y.Offset == initial.Y.Offset
            and moved.X.Offset == 18
            and moved.Y.Offset == 12
            and bubbleUnchanged.X.Offset == bubbleOrigin.X.Offset
            and bubbleUnchanged.Y.Offset == bubbleOrigin.Y.Offset
            and bubbleMoved.X.Offset == bubbleOrigin.X.Offset + 18
            and bubbleMoved.Y.Offset == bubbleOrigin.Y.Offset + 12
    end)

    test("native window, section, and scrolling surfaces exist", function()
        selectTab("Main")
        local section = content:FindFirstChild("SectionHeader")
        return titlebar ~= nil and titlebar:IsA("Frame")
            and scroll ~= nil and scroll:IsA("ScrollingFrame")
            and controlsContainer ~= nil and controlGridLayout ~= nil
            and section ~= nil and section:FindFirstChild("AccentBar") ~= nil
            and screenGui:FindFirstChild("Window"):FindFirstChild("Status") ~= nil
    end)

    test("window, buttons, and bubble have tweenable animation scales", function()
        return windowScale ~= nil
            and bubbleScale ~= nil
            and bubbleHalo ~= nil
            and bubblePing ~= nil
            and bubbleRing:FindFirstChild("Dash_12") ~= nil
            and tabButtons.Main:FindFirstChildOfClass("UIScale") ~= nil
            and bubbleButton:FindFirstChildOfClass("UIScale") ~= nil
            and not bubbleHint.Visible
    end)

    test("bubble pulse and status ping stop cleanly", function()
        startBubbleAmbientAnimations()
        local started = activeTweens[bubbleHalo] ~= nil and activeTweens[bubblePing] ~= nil
        stopBubbleAmbientAnimations()
        return started
            and activeTweens[bubbleHalo] == nil
            and activeTweens[bubblePing] == nil
    end)

    test("tab selection and active indicators", function()
        for _, tabName in ipairs(Tabs) do
            if not selectTab(tabName) or state.selectedTab ~= tabName then
                return false
            end
            if tabButtons[tabName].BackgroundColor3 ~= Theme.Selected then
                return false
            end
            local marker = tabButtons[tabName]:FindFirstChild("ActiveMarker")
            if not marker or not marker.Visible then
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
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(390, 844)
        local landscape = viewport.X > viewport.Y
        local minHeight = landscape and 300 or 320
        local maxHeight = math.min(landscape and 420 or 740, math.max(1, viewport.Y - 32))
        selectTab("Main")
        return expanded and compact
            and expandedWidth >= compactWidth
            and expandedHeight >= minHeight
            and expandedHeight <= maxHeight
            and compactHeight >= minHeight
            and compactHeight <= maxHeight
    end)

    test("minimize and restore use the floating bubble without cleanup", function()
        if isMinimized or isCleaned then
            return false
        end
        local hintSeenBefore = player:GetAttribute(BUBBLE_HINT_SEEN_ATTRIBUTE)
        local minimized = minimizeWindow(true)
        local hidden = root ~= nil and not root.Visible
            and bubbleContainer ~= nil and bubbleContainer.Visible
            and isMinimized and not isCleaned
        local restored = restoreWindow(true)
        return minimized and hidden and restored
            and root.Visible and not bubbleContainer.Visible
            and not isMinimized and not isCleaned
            and player:GetAttribute(BUBBLE_HINT_SEEN_ATTRIBUTE) == hintSeenBefore
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
        local camera = workspace.CurrentCamera
        local landscape = camera ~= nil and camera.ViewportSize.X > camera.ViewportSize.Y
        local columnsFitWidth = controlGridLayout.FillDirectionMaxCells
            == getColumnCount(controlsContainer.AbsoluteSize.X, #Pages.Settings.Controls, landscape)
        local noOverlap = title.AbsolutePosition.X + title.AbsoluteSize.X <= value.AbsolutePosition.X
        selectTab("Main")
        return noOverlap and columnsFitWidth
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
        if next(activeTweens) ~= nil or next(tweenCompletedConnections) ~= nil then
            return false
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
    print("[CustomHub UI Test] MANUAL: tap all tabs and Close; also minimize, restore, and drag the bubble; drag the titlebar and inspect text, contrast, and scrolling.")
    setStatus(summary .. " MANUAL: inspect touch, drag, text, and scroll.", failed == 0 and "success" or "error")
    selfTestRunning = false
end)
