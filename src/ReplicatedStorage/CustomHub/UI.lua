local UI = {}
UI.__index = UI

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local MINIMIZE_BUTTON_WIDTH = 28
local HEADER_BUTTON_GAP = 6
local RESTORE_BUTTON_SIZE = Vector2.new(56, 56)
local RESTORE_DRAG_THRESHOLD = 8
local WINDOW_VISIBLE_GRIP_WIDTH = 128
local WINDOW_VISIBLE_GRIP_HEIGHT = 24
local HEADER_HEIGHT = 40
local FOOTER_HEIGHT = 30

local function create(className, properties, parent)
    local instance = Instance.new(className)
    for property, value in pairs(properties) do
        instance[property] = value
    end
    if className == "TextLabel" or className == "TextButton" or className == "TextBox" then
        instance.AutoLocalize = false
    end
    instance.Parent = parent
    return instance
end

local function addCorner(parent, radius)
    create("UICorner", {
        CornerRadius = UDim.new(0, radius or 4),
    }, parent)
end

local function displayTabName(tabName)
    return tabName == "Farm" and "Farming" or tabName
end

local function normalizeSearchText(text)
    return string.lower((tostring(text or ""):match("^%s*(.-)%s*$") or ""))
end

local function clampDragPosition(origin, delta, viewport, size)
    local halfX = math.min(size.X / 2, viewport.X / 2)
    local halfY = math.min(size.Y / 2, viewport.Y / 2)
    local startCenterX = viewport.X * origin.X.Scale + origin.X.Offset
    local startCenterY = viewport.Y * origin.Y.Scale + origin.Y.Offset
    local centerX = math.clamp(
        startCenterX + delta.X,
        halfX,
        math.max(halfX, viewport.X - halfX)
    )
    local centerY = math.clamp(
        startCenterY + delta.Y,
        halfY,
        math.max(halfY, viewport.Y - halfY)
    )
    return UDim2.new(
        origin.X.Scale,
        centerX - viewport.X * origin.X.Scale,
        origin.Y.Scale,
        centerY - viewport.Y * origin.Y.Scale
    )
end

local function clampWindowDragPosition(origin, delta, viewport, size)
    local visibleGripWidth = math.min(
        WINDOW_VISIBLE_GRIP_WIDTH,
        size.X,
        viewport.X / 2
    )
    local visibleHeaderHeight = math.min(
        WINDOW_VISIBLE_GRIP_HEIGHT,
        HEADER_HEIGHT,
        viewport.Y / 2
    )
    local halfX = size.X / 2
    local halfY = size.Y / 2
    local startCenterX = viewport.X * origin.X.Scale + origin.X.Offset
    local startCenterY = viewport.Y * origin.Y.Scale + origin.Y.Offset
    local centerX = math.clamp(
        startCenterX + delta.X,
        visibleGripWidth - halfX,
        viewport.X - visibleGripWidth + halfX
    )
    local minCenterY = visibleHeaderHeight - HEADER_HEIGHT + halfY
    local centerY = math.clamp(
        startCenterY + delta.Y,
        minCenterY,
        math.max(minCenterY, viewport.Y - visibleHeaderHeight + halfY)
    )

    return UDim2.new(
        origin.X.Scale,
        centerX - viewport.X * origin.X.Scale,
        origin.Y.Scale,
        centerY - viewport.Y * origin.Y.Scale
    )
end

local function disconnectAll(connections)
    for index = #connections, 1, -1 do
        local connection = connections[index]
        if connection and connection.Connected then
            connection:Disconnect()
        end
        connections[index] = nil
    end
end

function UI.new(playerGui, state, compatibility, config, dispatch, onClose)
    return setmetatable({
        PlayerGui = playerGui,
        State = state,
        Compatibility = compatibility,
        Config = config,
        Dispatch = dispatch,
        OnClose = onClose,
        Gui = nil,
        Root = nil,
        Header = nil,
        Sidebar = nil,
        SearchBox = nil,
        NavScroll = nil,
        MainPane = nil,
        PageHeader = nil,
        PageTitle = nil,
        MinimizeButton = nil,
        RestoreButton = nil,
        RestoreHalo = nil,
        RestorePing = nil,
        SizeConstraint = nil,
        IsMinimized = false,
        RestoreDrag = nil,
        RestoreDragMoved = false,
        WindowDrag = nil,
        StatusLabel = nil,
        StatusDot = nil,
        TabButtons = {},
        TabMarkers = {},
        ToggleLabels = {},
        SelectorEntries = {},
        ActiveTweens = {},
        TweenCompletedConnections = {},
        PressedButtonScale = nil,
        PressedButtonInput = nil,
        PersistentConnections = {},
        PageConnections = {},
        StateConnection = nil,
        Scroll = nil,
        Content = nil,
        ContentLayout = nil,
        ControlsContainer = nil,
        ControlGridLayout = nil,
        ActiveControls = nil,
        ActiveTab = nil,
        SearchQuery = "",
        _contentSizeConnection = nil,
        ViewportConnection = nil,
    }, UI)
end

function UI:_WatchViewport(camera)
    if self.ViewportConnection and self.ViewportConnection.Connected then
        self.ViewportConnection:Disconnect()
    end
    self.ViewportConnection = nil
    if not camera then
        return
    end
    self.ViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        self:_ApplySize(self.State:GetSnapshot())
        self:_UpdateControlGridLayout()
        self:_ClampRestoreButton()
    end)
end

function UI:_Connect(bucket, signal, callback)
    local connection = signal:Connect(callback)
    table.insert(bucket, connection)
    return connection
end

function UI:_CancelTween(instance)
    if not instance then
        return
    end
    local tween = self.ActiveTweens[instance]
    if not tween then
        return
    end
    self.ActiveTweens[instance] = nil
    local connection = self.TweenCompletedConnections[instance]
    self.TweenCompletedConnections[instance] = nil
    if connection and connection.Connected then
        connection:Disconnect()
    end
    tween:Cancel()
end

function UI:_PlayTween(instance, duration, goals, onComplete, repeatCount, reverses)
    if not instance or not instance.Parent then
        return
    end
    self:_CancelTween(instance)
    local tween = TweenService:Create(
        instance,
        TweenInfo.new(
            duration,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out,
            repeatCount or 0,
            reverses == true
        ),
        goals
    )
    self.ActiveTweens[instance] = tween
    local connection
    connection = tween.Completed:Connect(function(playbackState)
        if self.ActiveTweens[instance] == tween then
            self.ActiveTweens[instance] = nil
        end
        if self.TweenCompletedConnections[instance] == connection then
            self.TweenCompletedConnections[instance] = nil
        end
        if connection.Connected then
            connection:Disconnect()
        end
        if playbackState == Enum.PlaybackState.Completed and onComplete then
            onComplete()
        end
    end)
    self.TweenCompletedConnections[instance] = connection
    tween:Play()
end

function UI:_CancelTweensIn(instance)
    self:_CancelTween(instance)
    for _, descendant in ipairs(instance:GetDescendants()) do
        self:_CancelTween(descendant)
    end
end

function UI:_CancelAllTweens()
    local instances = {}
    for instance in pairs(self.ActiveTweens) do
        table.insert(instances, instance)
    end
    for _, instance in ipairs(instances) do
        self:_CancelTween(instance)
    end
    table.clear(self.ActiveTweens)
    table.clear(self.TweenCompletedConnections)
end

function UI:_AttachButtonFeedback(button, bucket, pressedScale)
    local scale = create("UIScale", { Scale = 1 }, button)
    self:_Connect(bucket, button.MouseEnter, function()
        if not self.Compatibility:IsTouchEnabled() then
            self:_PlayTween(scale, 0.1, { Scale = 1.025 })
        end
    end)
    self:_Connect(bucket, button.MouseLeave, function()
        if self.PressedButtonScale ~= scale then
            self:_PlayTween(scale, 0.1, { Scale = 1 })
        end
    end)
    self:_Connect(bucket, button.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if self.PressedButtonScale and self.PressedButtonScale ~= scale
            and self.PressedButtonScale.Parent then
            self:_PlayTween(self.PressedButtonScale, 0.1, { Scale = 1 })
        end
        self.PressedButtonScale = scale
        self.PressedButtonInput = input.UserInputType == Enum.UserInputType.Touch and input or nil
        self:_PlayTween(scale, 0.07, { Scale = pressedScale or 0.96 })
    end)
    self:_Connect(bucket, button.Activated, function()
        if self.PressedButtonScale == scale then
            self.PressedButtonScale = nil
            self.PressedButtonInput = nil
        end
        self:_PlayTween(scale, 0.12, { Scale = 1 })
    end)
    return scale
end

function UI:_ApplySize(snapshot)
    if not self.Root then
        return
    end
    local touch = self.Compatibility:IsTouchEnabled()
    local viewport = self.Compatibility:GetViewportSize()
    if typeof(viewport) ~= "Vector2" then
        viewport = Vector2.new(390, 844)
    end
    local landscape = viewport.X > viewport.Y
    local layout = self.Config.Layout
    local widthScale = snapshot.compact and (touch and 0.92 or 0.72) or 0.96
    local maxWidth = landscape and 760 or 500
    local maxHeight = math.min(landscape and 420 or 740, math.max(1, viewport.Y - 32))
    local minHeight = math.min(landscape and 300 or 320, maxHeight)
    local pageHeight = self.ContentLayout and self.ContentLayout.AbsoluteContentSize.Y or 0
    local desiredHeight = HEADER_HEIGHT + layout.PageHeaderHeight + pageHeight + FOOTER_HEIGHT + 14
    local width = math.min(viewport.X * widthScale, maxWidth, math.max(1, viewport.X - 16))
    local height = math.clamp(desiredHeight, minHeight, maxHeight)
    if self.SizeConstraint then
        self.SizeConstraint.MinSize = Vector2.new(math.min(280, width), minHeight)
        self.SizeConstraint.MaxSize = Vector2.new(maxWidth, maxHeight)
    end
    self.Root.Size = UDim2.fromOffset(math.floor(width), math.floor(height))
    self:_UpdateShellLayout()
    self:_ClampWindow()
end

function UI:_SetMinimized(minimized)
    if not self.Root or not self.RestoreButton or self.IsMinimized == minimized then
        return false
    end

    self.IsMinimized = minimized
    self.Root.Visible = not minimized
    self.RestoreButton.Visible = minimized
    if not minimized then
        self.RestoreDrag = nil
        self.RestoreDragMoved = false
        self:_CancelTween(self.RestoreHalo)
        self:_CancelTween(self.RestorePing)
        if self.RestoreHalo then
            self.RestoreHalo.Size = UDim2.fromOffset(70, 70)
            self.RestoreHalo.BackgroundTransparency = 0.86
        end
        if self.RestorePing then
            self.RestorePing.Size = UDim2.fromOffset(7, 7)
            self.RestorePing.BackgroundTransparency = 1
        end
    else
        if self.RestoreHalo then
            self.RestoreHalo.Size = UDim2.fromOffset(70, 70)
            self.RestoreHalo.BackgroundTransparency = 0.84
            self:_PlayTween(self.RestoreHalo, 1.05, {
                Size = UDim2.fromOffset(78, 78),
                BackgroundTransparency = 0.97,
            }, nil, -1, true)
        end
        if self.RestorePing then
            self.RestorePing.Size = UDim2.fromOffset(7, 7)
            self.RestorePing.BackgroundTransparency = 0.25
            self:_PlayTween(self.RestorePing, 0.9, {
                Size = UDim2.fromOffset(20, 20),
                BackgroundTransparency = 1,
            }, nil, -1, false)
        end
    end
    return true
end

function UI:_ClampRestoreButton()
    if not self.RestoreButton then
        return
    end
    local viewport = self.Compatibility:GetViewportSize()
    if typeof(viewport) ~= "Vector2" then
        viewport = Vector2.new(390, 844)
    end
    self.RestoreButton.Position = clampDragPosition(
        self.RestoreButton.Position,
        Vector2.zero,
        viewport,
        self.RestoreButton.AbsoluteSize
    )
end

function UI:_ClampWindow()
    if not self.Root then
        return
    end
    local viewport = self.Compatibility:GetViewportSize()
    if typeof(viewport) ~= "Vector2" then
        viewport = Vector2.new(390, 844)
    end
    self.Root.Position = clampWindowDragPosition(
        self.Root.Position,
        Vector2.zero,
        viewport,
        self.Root.AbsoluteSize
    )
end

function UI:_UpdateShellLayout()
    if not self.Root or not self.Sidebar or not self.MainPane then
        return
    end

    local layout = self.Config.Layout
    local rootWidth = self.Root.AbsoluteSize.X
    local maxSidebarWidth = math.max(
        72,
        math.min(layout.SidebarMaxWidth, rootWidth - layout.MainPaneMinWidth)
    )
    local minSidebarWidth = math.min(layout.SidebarMinWidth, maxSidebarWidth)
    local sidebarWidth = math.clamp(
        rootWidth * layout.SidebarWidthRatio,
        minSidebarWidth,
        maxSidebarWidth
    )

    self.Sidebar.Position = UDim2.new(0, 0, 0, HEADER_HEIGHT)
    self.Sidebar.Size = UDim2.new(0, sidebarWidth, 1, -HEADER_HEIGHT - FOOTER_HEIGHT)
    self.MainPane.Position = UDim2.new(0, sidebarWidth, 0, HEADER_HEIGHT)
    self.MainPane.Size = UDim2.new(1, -sidebarWidth, 1, -HEADER_HEIGHT - FOOTER_HEIGHT)

    if self.PageHeader then
        self.PageHeader.Size = UDim2.new(1, 0, 0, layout.PageHeaderHeight)
    end
    if self.SearchBox then
        self.SearchBox.PlaceholderText = sidebarWidth < 148
            and "Search..."
            or "Search section or function"
    end
    if self.Scroll then
        self.Scroll.Position = UDim2.new(0, 0, 0, layout.PageHeaderHeight)
        self.Scroll.Size = UDim2.new(1, 0, 1, -layout.PageHeaderHeight)
    end
end

function UI:_Refresh(snapshot)
    if not self.Gui then
        return
    end

    local theme = self.Config.Theme
    self.StatusLabel.Text = snapshot.status
    if snapshot.statusKind == "error" then
        self.StatusLabel.TextColor3 = theme.Error
    elseif snapshot.statusKind == "success" then
        self.StatusLabel.TextColor3 = theme.Success
    elseif snapshot.statusKind == "warning" then
        self.StatusLabel.TextColor3 = theme.Warning
    else
        self.StatusLabel.TextColor3 = theme.MutedText
    end
    if self.StatusDot then
        self.StatusDot.BackgroundColor3 = self.StatusLabel.TextColor3
    end
    if self.RestorePing then
        self.RestorePing.BackgroundColor3 = self.StatusLabel.TextColor3
    end

    for tabName, button in pairs(self.TabButtons) do
        local selected = tabName == snapshot.selectedTab
        button.BackgroundColor3 = theme.Selected
        button.BackgroundTransparency = selected and 0 or 1
        button.TextColor3 = selected and theme.Accent or theme.MutedText
        local stroke = button:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = selected and theme.AccentBorder or theme.Border
            stroke.Transparency = selected and 0.18 or 1
        end
        local marker = self.TabMarkers[tabName]
        if marker then
            marker.Visible = true
            marker.BackgroundColor3 = selected and theme.Accent or theme.MutedText
            marker.Size = selected and UDim2.fromOffset(3, 17) or UDim2.fromOffset(5, 5)
        end
    end

    for _, entry in ipairs(self.ToggleLabels) do
        local enabled
        if entry.Control.Kind == "featureToggle" then
            enabled = snapshot.featureEnabled[entry.Control.Action] == true
            entry.Label.Text = enabled and "ON" or "OFF"
            entry.Label.BackgroundColor3 = enabled and theme.Accent or theme.TabBar
            entry.Label.TextColor3 = enabled and theme.Text or theme.MutedText
        elseif entry.Control.Kind == "settingToggle" then
            enabled = snapshot.compact
            entry.Label.Text = enabled and "On" or "Off"
            entry.Label.BackgroundColor3 = enabled and theme.Accent or theme.TabBar
            entry.Label.TextColor3 = enabled and theme.Text or theme.MutedText
        end
    end

    for _, entry in ipairs(self.SelectorEntries) do
        local farmSettings = self.Config.FarmSettings or {}
        local selectedValue = farmSettings[entry.Setting]
        for _, option in ipairs(entry.Options) do
            local selected = option.Value == selectedValue
            option.Button.BackgroundColor3 = selected and theme.Accent or theme.TabBar
            option.Button.TextColor3 = selected and theme.Text or theme.MutedText
            local stroke = option.Button:FindFirstChildOfClass("UIStroke")
            if stroke then
                stroke.Color = selected and theme.AccentBorder or theme.Border
                stroke.Transparency = selected and 0.12 or 0.65
            end
        end
    end

    self:_ApplySize(snapshot)
    if self.ActiveTab ~= snapshot.selectedTab then
        if self.Config.Pages[snapshot.selectedTab] then
            self:_RenderTab(snapshot.selectedTab)
        else
            self.StatusLabel.Text = "Unknown tab: " .. tostring(snapshot.selectedTab)
            self.StatusLabel.TextColor3 = theme.Error
        end
    end
end

function UI:_ClearPage()
    disconnectAll(self.PageConnections)
    self.ToggleLabels = {}
    self.SelectorEntries = {}
    self.ControlsContainer = nil
    self.ControlGridLayout = nil
    self.ActiveControls = nil
    for _, child in ipairs(self.Content:GetChildren()) do
        if child ~= self.ContentLayout then
            self:_CancelTweensIn(child)
            child:Destroy()
        end
    end
end

function UI:_SyncControlGridHeight()
    if self.ControlsContainer and self.ControlGridLayout then
        self.ControlsContainer.Size = UDim2.new(
            1,
            -2,
            0,
            self.ControlGridLayout.AbsoluteContentSize.Y
        )
    end
end

function UI:_UpdateControlGridLayout()
    if not self.ControlsContainer or not self.ControlGridLayout then
        return
    end

    local viewport = self.Compatibility:GetViewportSize()
    if typeof(viewport) ~= "Vector2" then
        viewport = Vector2.new(390, 844)
    end
    local landscape = viewport.X > viewport.Y
    local columnCount = landscape
        and self.ControlsContainer.AbsoluteSize.X >= 620
        and self.ActiveControls
        and #self.ActiveControls > 1
        and 2
        or 1
    local rowHeight = self.Config.Layout.RowHeight
    self.ControlGridLayout.FillDirectionMaxCells = columnCount
    self.ControlGridLayout.CellSize = columnCount == 2
        and UDim2.new(0.5, -4, 0, rowHeight)
        or UDim2.new(1, 0, 0, rowHeight)
end

function UI:_TabMatchesSearch(tabName, query)
    if query == "" then
        return true
    end
    if string.find(normalizeSearchText(displayTabName(tabName)), query, 1, true) then
        return true
    end

    local page = self.Config.Pages[tabName]
    for _, control in ipairs(page and page.Controls or {}) do
        if string.find(normalizeSearchText(control.Label), query, 1, true) then
            return true
        end
    end
    return false
end

function UI:_ApplyControlSearchHighlight()
    if not self.ControlsContainer or not self.ActiveControls then
        return
    end

    local theme = self.Config.Theme
    local query = self.SearchQuery
    for _, control in ipairs(self.ActiveControls) do
        local row = self.ControlsContainer:FindFirstChild(
            "Action_" .. control.Action:gsub("[^%w]", "_")
        )
        if row then
            local matched = query ~= ""
                and string.find(normalizeSearchText(control.Label), query, 1, true) ~= nil
            row.BackgroundColor3 = matched and theme.Selected or theme.Control
            local stroke = row:FindFirstChildOfClass("UIStroke")
            if stroke then
                stroke.Color = matched and theme.AccentBorder or theme.Border
                stroke.Transparency = matched and 0.12 or 0.4
            end
        end
    end
end

function UI:_ApplySearchFilter()
    if not self.SearchBox or not self.NavScroll then
        return
    end

    local layout = self.Config.Layout
    local query = normalizeSearchText(self.SearchBox.Text)
    self.SearchQuery = query
    local top = 0
    local firstMatch
    for _, tabName in ipairs(self.Config.Tabs) do
        local button = self.TabButtons[tabName]
        local matches = self:_TabMatchesSearch(tabName, query)
        if button then
            button.Visible = matches
            if matches then
                button.Position = UDim2.fromOffset(0, top)
                top = top + layout.SidebarRowHeight + layout.SidebarRowGap
                firstMatch = firstMatch or tabName
            end
        end
    end
    self.NavScroll.CanvasSize = UDim2.new(0, 0, 0, math.max(0, top - layout.SidebarRowGap))

    local selectedTab = self.State:GetSnapshot().selectedTab
    if query ~= "" and firstMatch and not self:_TabMatchesSearch(selectedTab, query) then
        self:_SelectTab(firstMatch)
    else
        self:_ApplyControlSearchHighlight()
    end
end

function UI:_SelectTab(tabName)
    if not self.Config.Pages[tabName] then
        self.State:SetStatus("Unknown tab: " .. tostring(tabName), "error")
        return false
    end
    self.State:SetSelectedTab(tabName)
    return true
end

function UI:_ActivateControl(control)
    local snapshot = self.State:GetSnapshot()
    if control.Kind == "featureToggle" then
        return self.Dispatch(control.Action, snapshot.featureEnabled[control.Action] ~= true)
    elseif control.Kind == "settingToggle" then
        return self.Dispatch(control.Action, not snapshot.compact)
    end
    return self.Dispatch(control.Action, true)
end

function UI:_AddControl(control)
    local theme = self.Config.Theme
    local layout = self.Config.Layout
    local hasToggle = control.Kind == "featureToggle"
        or control.Kind == "settingToggle"
    local isSelector = control.Kind == "settingSelect"
    local reservedTitleSpace = hasToggle and (layout.ToggleValueWidth + layout.ToggleGap) or 0
    local row = create(isSelector and "Frame" or "TextButton", {
        Name = "Action_" .. control.Action:gsub("[^%w]", "_"),
        Size = UDim2.new(1, 0, 0, layout.RowHeight),
        BackgroundColor3 = theme.Control,
        BorderSizePixel = 0,
        LayoutOrder = #self.ControlsContainer:GetChildren(),
    }, self.ControlsContainer)
    if row:IsA("TextButton") then
        row.AutoButtonColor = false
        row.Text = ""
        row.Font = theme.Font
        row.TextSize = theme.TextSizes.Control
        row.TextColor3 = theme.Text
        row.TextXAlignment = Enum.TextXAlignment.Left
        self:_AttachButtonFeedback(row, self.PageConnections)
    end
    addCorner(row, 4)

    local rowStroke = create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, row)

    local titleTop = isSelector and layout.SelectorTitleTop or layout.RowTitleTop
    local titleHeight = isSelector and layout.SelectorTitleHeight or layout.RowTitleHeight
    local titleSize = isSelector
        and UDim2.new(0, layout.SelectorTitleWidth, 0, titleHeight)
        or UDim2.new(1, -layout.RowInset * 2 - reservedTitleSpace, 0, titleHeight)
    create("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(layout.RowInset, titleTop),
        Size = titleSize,
        BackgroundTransparency = 1,
        Font = theme.StrongFont,
        Text = control.Label,
        TextColor3 = theme.Text,
        TextSize = theme.TextSizes.Control,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)

    if hasToggle then
        local toggleLabel = create("TextLabel", {
            Name = "Value",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -layout.RowInset, 0, layout.ToggleValueTop),
            Size = UDim2.fromOffset(layout.ToggleValueWidth, layout.ToggleValueHeight),
            BackgroundColor3 = theme.TabBar,
            Font = theme.StrongFont,
            Text = "OFF",
            TextColor3 = theme.MutedText,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Center,
        }, row)
        addCorner(toggleLabel, 3)
        create("UIStroke", {
            Color = theme.Border,
            Thickness = layout.BorderThickness,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, toggleLabel)
        table.insert(self.ToggleLabels, { Control = control, Label = toggleLabel })
    end

    if isSelector then
        row.Size = UDim2.new(1, 0, 0, layout.RowHeight)
        rowStroke.Transparency = 0.15
        local options = control.Options or {}
        local optionsFrame = create("Frame", {
            Name = "Options",
            Position = UDim2.new(
                0,
                layout.RowInset + layout.SelectorTitleWidth + layout.SelectorTitleGap,
                0,
                layout.SelectorOptionsTop
            ),
            Size = UDim2.new(
                1,
                -(layout.RowInset * 2 + layout.SelectorTitleWidth + layout.SelectorTitleGap),
                0,
                layout.SelectorOptionsHeight
            ),
            BackgroundTransparency = 1,
        }, row)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
        }, optionsFrame)
        local optionEntries = {}
        local optionCount = #options
        if optionCount > 0 then
            for index, value in ipairs(options) do
                local optionButton = create("TextButton", {
                    Name = "Option_" .. tostring(value):gsub("[^%w]", "_"),
                    Size = UDim2.new(
                        1 / optionCount,
                        -(6 * (optionCount - 1) / optionCount),
                        1,
                        0
                    ),
                    BackgroundColor3 = theme.TabBar,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Font = theme.StrongFont,
                    Text = tostring(value),
                    TextColor3 = theme.MutedText,
                    TextSize = 10,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    LayoutOrder = index,
                }, optionsFrame)
                addCorner(optionButton, 3)
                create("UIStroke", {
                    Color = theme.Border,
                    Thickness = layout.BorderThickness,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                }, optionButton)
                self:_AttachButtonFeedback(optionButton, self.PageConnections, 0.96)
                self:_Connect(self.PageConnections, optionButton.Activated, function()
                    local ok, result, actionError = pcall(
                        self.Dispatch,
                        control.Action,
                        value
                    )
                    if not ok then
                        self.State:SetStatus("UI action error: " .. tostring(result), "error")
                    elseif result == false and actionError then
                        self.State:SetStatus(tostring(actionError), "error")
                    end
                end)
                table.insert(optionEntries, {
                    Value = value,
                    Button = optionButton,
                })
            end
        end
        table.insert(self.SelectorEntries, {
            Setting = control.Setting,
            Options = optionEntries,
        })
    else
        self:_Connect(self.PageConnections, row.Activated, function()
            local ok, actionError = pcall(self._ActivateControl, self, control)
            if not ok then
                self.State:SetStatus("UI action error: " .. tostring(actionError), "error")
            end
        end)
    end
end

function UI:_RenderTab(tabName)
    local page = self.Config.Pages[tabName]
    if not page then
        return false
    end

    self.ActiveTab = tabName
    if self.PageTitle then
        self.PageTitle.Text = displayTabName(tabName)
    end
    self:_ClearPage()
    local theme = self.Config.Theme
    local layout = self.Config.Layout
    self.ActiveControls = page.Controls
    self.ControlsContainer = create("Frame", {
        Name = "ControlGrid",
        Size = UDim2.new(1, -2, 0, 0),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
    }, self.Content)
    self.ControlGridLayout = create("UIGridLayout", {
        CellSize = UDim2.new(1, 0, 0, layout.RowHeight),
        CellPadding = UDim2.fromOffset(6, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        FillDirectionMaxCells = 1,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, self.ControlsContainer)
    self:_Connect(
        self.PageConnections,
        self.ControlGridLayout:GetPropertyChangedSignal("AbsoluteContentSize"),
        function()
            self:_SyncControlGridHeight()
        end
    )
    self:_Connect(
        self.PageConnections,
        self.ControlsContainer:GetPropertyChangedSignal("AbsoluteSize"),
        function()
            self:_UpdateControlGridLayout()
        end
    )
    for index, control in ipairs(page.Controls) do
        self:_AddControl(control)
        local row = self.ControlsContainer:FindFirstChild(
            "Action_" .. control.Action:gsub("[^%w]", "_")
        )
        if row then
            row.LayoutOrder = index
        end
    end
    self:_UpdateControlGridLayout()
    self:_SyncControlGridHeight()
    self:_ApplyControlSearchHighlight()
    self.Scroll.CanvasPosition = Vector2.zero
    self:_Refresh(self.State:GetSnapshot())
    return true
end

function UI:Mount()
    local previous = self.PlayerGui:FindFirstChild("CustomHubShell")
    if previous then
        previous:Destroy()
    end

    local theme = self.Config.Theme
    local layout = self.Config.Layout
    self.Gui = create("ScreenGui", {
        Name = "CustomHubShell",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 100,
    }, self.PlayerGui)

    self.Root = create("Frame", {
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(350, 360),
        BackgroundColor3 = theme.Background,
        BorderSizePixel = 0,
    }, self.Gui)
    addCorner(self.Root, 4)
    self.SizeConstraint = create("UISizeConstraint", {
        MinSize = layout.MinSize,
        MaxSize = layout.MaxSize,
    }, self.Root)
    create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, self.Root)

    self.Header = create("Frame", {
        Name = "Titlebar",
        Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
        BackgroundColor3 = theme.Header,
        BorderSizePixel = 0,
        Active = true,
    }, self.Root)
    addCorner(self.Header, 4)
    create("Frame", {
        Name = "LogoMark",
        Position = UDim2.fromOffset(10, 13),
        Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = theme.Accent,
        BorderSizePixel = 0,
    }, self.Header)
    create("Frame", {
        Name = "LogoCenter",
        Position = UDim2.fromOffset(5, 5),
        Size = UDim2.fromOffset(4, 4),
        BackgroundColor3 = theme.Text,
        BorderSizePixel = 0,
    }, self.Header.LogoMark)
    local title = create("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(1, -112, 0, HEADER_HEIGHT),
        BackgroundTransparency = 1,
        Font = theme.MonoFont,
        Text = string.upper(self.Config.Name),
        TextColor3 = theme.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, self.Header)
    local versionBadge = create("TextLabel", {
        Name = "VersionBadge",
        Position = UDim2.fromOffset(122, 11),
        Size = UDim2.fromOffset(44, 18),
        BackgroundColor3 = theme.Selected,
        BorderSizePixel = 0,
        Font = theme.MonoFont,
        Text = "DEV",
        TextColor3 = theme.Accent,
        TextSize = 8,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, self.Header)
    addCorner(versionBadge, 2)
    create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, versionBadge)

    local closeButton = create("TextButton", {
        Name = "Close",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 7),
        Size = UDim2.fromOffset(layout.CloseWidth, layout.CloseHeight),
        BackgroundColor3 = theme.Control,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = theme.StrongFont,
        Text = "×",
        TextColor3 = theme.MutedText,
        TextSize = 17,
    }, self.Header)
    addCorner(closeButton, 3)
    create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, closeButton)
    self:_AttachButtonFeedback(closeButton, self.PersistentConnections)
    self:_Connect(self.PersistentConnections, closeButton.Activated, function()
        if self.OnClose then
            self.OnClose()
        end
    end)

    self.MinimizeButton = create("TextButton", {
        Name = "Minimize",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(
            1,
            -(8 + layout.CloseWidth + HEADER_BUTTON_GAP),
            0,
            7
        ),
        Size = UDim2.fromOffset(MINIMIZE_BUTTON_WIDTH, layout.CloseHeight),
        BackgroundColor3 = theme.Control,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = theme.StrongFont,
        Text = "−",
        TextColor3 = theme.MutedText,
        TextSize = 17,
    }, self.Header)
    addCorner(self.MinimizeButton, 3)
    create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, self.MinimizeButton)
    self:_AttachButtonFeedback(self.MinimizeButton, self.PersistentConnections)
    self:_Connect(self.PersistentConnections, self.MinimizeButton.Activated, function()
        self:_SetMinimized(true)
    end)

    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(390, 844)
    self.RestoreButton = create("TextButton", {
        Name = "Restore",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(viewport.X - 42, viewport.Y / 2),
        Size = UDim2.fromOffset(RESTORE_BUTTON_SIZE.X, RESTORE_BUTTON_SIZE.Y),
        BackgroundColor3 = theme.Header,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        Visible = false,
        ZIndex = 20,
    }, self.Gui)
    addCorner(self.RestoreButton, 32)
    create("UIStroke", {
        Color = theme.AccentBorder,
        Thickness = 2,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, self.RestoreButton)
    self.RestoreHalo = create("Frame", {
        Name = "PulseHalo",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(70, 70),
        BackgroundColor3 = theme.Accent,
        BackgroundTransparency = 0.84,
        BorderSizePixel = 0,
        ZIndex = 20,
    }, self.RestoreButton)
    addCorner(self.RestoreHalo, 40)
    create("TextLabel", {
        Name = "Glyph",
        Position = UDim2.fromOffset(18, 5),
        Size = UDim2.fromOffset(20, 22),
        BackgroundTransparency = 1,
        Font = theme.StrongFont,
        Text = "⌂",
        TextColor3 = theme.Accent,
        TextSize = 19,
        ZIndex = 22,
    }, self.RestoreButton)
    create("TextLabel", {
        Name = "Brand",
        Position = UDim2.fromOffset(0, 29),
        Size = UDim2.new(1, 0, 0, 12),
        BackgroundTransparency = 1,
        Font = theme.MonoFont,
        Text = "HUB",
        TextColor3 = theme.Text,
        TextSize = 8,
        ZIndex = 22,
    }, self.RestoreButton)
    self.RestorePing = create("Frame", {
        Name = "StatusPing",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 8),
        Size = UDim2.fromOffset(7, 7),
        BackgroundColor3 = theme.Success,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 23,
    }, self.RestoreButton)
    addCorner(self.RestorePing, 8)
    self:_AttachButtonFeedback(self.RestoreButton, self.PersistentConnections, 0.9)
    self:_Connect(self.PersistentConnections, self.RestoreButton.Activated, function()
        if self.RestoreDragMoved then
            self.RestoreDragMoved = false
            return
        end
        self:_SetMinimized(false)
    end)
    self:_Connect(self.PersistentConnections, self.RestoreButton.InputBegan, function(input)
        if not self.IsMinimized
            or (input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch)
        then
            return
        end

        self.RestoreDragMoved = false
        self.RestoreDrag = {
            Input = input.UserInputType == Enum.UserInputType.Touch and input or nil,
            Start = input.Position,
            Origin = self.RestoreButton.Position,
        }
    end)
    self:_Connect(self.PersistentConnections, self.Header.InputBegan, function(input)
        if self.MinimizeButton
            and input.Position.X >= self.MinimizeButton.AbsolutePosition.X then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            self.WindowDrag = {
                Input = input.UserInputType == Enum.UserInputType.Touch and input or nil,
                Start = input.Position,
                Origin = self.Root.Position,
            }
        end
    end)
    self:_Connect(self.PersistentConnections, UserInputService.InputChanged, function(input)
        local drag = self.RestoreDrag
        if drag and self.RestoreButton and self.RestoreButton.Parent
            and (input.UserInputType == Enum.UserInputType.MouseMovement or input == drag.Input) then
            local delta = input.Position - drag.Start
            if delta.Magnitude >= RESTORE_DRAG_THRESHOLD then
                self.RestoreDragMoved = true
            end
            if self.RestoreDragMoved then
                local viewportSize = self.Compatibility:GetViewportSize()
                if typeof(viewportSize) ~= "Vector2" then
                    viewportSize = Vector2.new(390, 844)
                end
                self.RestoreButton.Position = clampDragPosition(
                    drag.Origin,
                    delta,
                    viewportSize,
                    self.RestoreButton.AbsoluteSize
                )
            end
        end

        local windowDrag = self.WindowDrag
        if windowDrag and self.Root
            and (input.UserInputType == Enum.UserInputType.MouseMovement or input == windowDrag.Input) then
            local viewportSize = self.Compatibility:GetViewportSize()
            if typeof(viewportSize) ~= "Vector2" then
                viewportSize = Vector2.new(390, 844)
            end
            self.Root.Position = clampWindowDragPosition(
                windowDrag.Origin,
                input.Position - windowDrag.Start,
                viewportSize,
                self.Root.AbsoluteSize
            )
        end
    end)
    self:_Connect(self.PersistentConnections, UserInputService.InputEnded, function(input)
        local drag = self.RestoreDrag
        if drag and (
            input.UserInputType == Enum.UserInputType.MouseButton1
                or input == drag.Input
        ) then
            self.RestoreDrag = nil
        end
        if self.WindowDrag and (
            input.UserInputType == Enum.UserInputType.MouseButton1
                or input == self.WindowDrag.Input
        ) then
            self.WindowDrag = nil
        end
        if self.PressedButtonScale and (
            input.UserInputType == Enum.UserInputType.MouseButton1
                or input == self.PressedButtonInput
        ) then
            local scale = self.PressedButtonScale
            self.PressedButtonScale = nil
            self.PressedButtonInput = nil
            if scale.Parent then
                self:_PlayTween(scale, 0.12, { Scale = 1 })
            end
        end
    end)

    self.Sidebar = create("Frame", {
        Name = "Sidebar",
        Position = UDim2.new(0, 0, 0, HEADER_HEIGHT),
        Size = UDim2.new(0, layout.SidebarMinWidth, 1, -HEADER_HEIGHT - FOOTER_HEIGHT),
        BackgroundColor3 = theme.Sidebar,
        BorderSizePixel = 0,
    }, self.Root)
    create("Frame", {
        Name = "Divider",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = theme.Border,
        BorderSizePixel = 0,
    }, self.Sidebar)

    local searchFrame = create("Frame", {
        Name = "Search",
        Position = UDim2.new(0, layout.SidebarSearchInset, 0, 8),
        Size = UDim2.new(1, -layout.SidebarSearchInset * 2, 0, layout.SidebarSearchHeight),
        BackgroundColor3 = theme.Control,
        BorderSizePixel = 0,
    }, self.Sidebar)
    addCorner(searchFrame, 4)
    create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, searchFrame)
    create("TextLabel", {
        Name = "SearchIcon",
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.fromOffset(16, layout.SidebarSearchHeight),
        BackgroundTransparency = 1,
        Font = theme.StrongFont,
        Text = "⌕",
        TextColor3 = theme.MutedText,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, searchFrame)
    self.SearchBox = create("TextBox", {
        Name = "SearchInput",
        Position = UDim2.fromOffset(27, 0),
        Size = UDim2.new(1, -32, 1, 0),
        BackgroundTransparency = 1,
        ClearTextOnFocus = false,
        Font = theme.MonoFont,
        PlaceholderText = "Search section or function",
        PlaceholderColor3 = theme.MutedText,
        Text = "",
        TextColor3 = theme.Text,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, searchFrame)
    self:_Connect(
        self.PersistentConnections,
        self.SearchBox:GetPropertyChangedSignal("Text"),
        function()
            self:_ApplySearchFilter()
        end
    )

    self.NavScroll = create("ScrollingFrame", {
        Name = "Navigation",
        Position = UDim2.new(0, 6, 0, layout.SidebarNavTop),
        Size = UDim2.new(1, -12, 1, -layout.SidebarNavTop - 6),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = layout.ScrollBarThickness,
        ScrollBarImageColor3 = theme.Accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.None,
    }, self.Sidebar)

    self.MainPane = create("Frame", {
        Name = "MainPane",
        Position = UDim2.new(0, layout.SidebarMinWidth, 0, HEADER_HEIGHT),
        Size = UDim2.new(1, -layout.SidebarMinWidth, 1, -HEADER_HEIGHT - FOOTER_HEIGHT),
        BackgroundColor3 = theme.Panel,
        BorderSizePixel = 0,
    }, self.Root)
    self.PageHeader = create("Frame", {
        Name = "PageHeader",
        Size = UDim2.new(1, 0, 0, layout.PageHeaderHeight),
        BackgroundColor3 = theme.Header,
        BorderSizePixel = 0,
    }, self.MainPane)
    create("Frame", {
        Name = "PageAccent",
        Position = UDim2.fromOffset(12, 9),
        Size = UDim2.fromOffset(3, 14),
        BackgroundColor3 = theme.Accent,
        BorderSizePixel = 0,
    }, self.PageHeader)
    self.PageTitle = create("TextLabel", {
        Name = "PageTitle",
        Position = UDim2.fromOffset(24, 0),
        Size = UDim2.new(1, -36, 1, 0),
        BackgroundTransparency = 1,
        Font = theme.StrongFont,
        Text = "",
        TextColor3 = theme.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, self.PageHeader)
    create("Frame", {
        Name = "BottomBorder",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = theme.Border,
        BorderSizePixel = 0,
    }, self.PageHeader)

    local navTop = 0
    for _, tabName in ipairs(self.Config.Tabs) do
        local button = create("TextButton", {
            Name = "Tab_" .. tabName,
            Position = UDim2.fromOffset(0, navTop),
            Size = UDim2.new(1, -2, 0, layout.SidebarRowHeight),
            BackgroundColor3 = theme.Selected,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = theme.StrongFont,
            Text = displayTabName(tabName),
            TextColor3 = theme.MutedText,
            TextSize = theme.TextSizes.Tab,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, self.NavScroll)
        addCorner(button, 4)
        create("UIPadding", {
            PaddingLeft = UDim.new(0, 23),
            PaddingRight = UDim.new(0, 8),
        }, button)
        create("UIStroke", {
            Color = theme.Border,
            Thickness = layout.BorderThickness,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Transparency = 1,
        }, button)
        self:_AttachButtonFeedback(button, self.PersistentConnections)
        local marker = create("Frame", {
            Name = "ActiveMarker",
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 8, 0.5, 0),
            Size = UDim2.fromOffset(5, 5),
            BackgroundColor3 = theme.MutedText,
            BorderSizePixel = 0,
        }, button)
        addCorner(marker, 4)
        self.TabButtons[tabName] = button
        self.TabMarkers[tabName] = marker
        self:_Connect(self.PersistentConnections, button.Activated, function()
            self:_SelectTab(tabName)
        end)
        navTop = navTop + layout.SidebarRowHeight + layout.SidebarRowGap
    end
    self.NavScroll.CanvasSize = UDim2.new(
        0,
        0,
        0,
        math.max(0, navTop - layout.SidebarRowGap)
    )

    local statusFrame = create("Frame", {
        Name = "Status",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT),
        BackgroundColor3 = theme.TabBar,
        BorderSizePixel = 0,
    }, self.Root)
    create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, statusFrame)
    self.StatusLabel = create("TextLabel", {
        Name = "Message",
        Position = UDim2.fromOffset(24, 0),
        Size = UDim2.new(1, -100, 1, 0),
        BackgroundTransparency = 1,
        Font = theme.MonoFont,
        Text = "",
        TextColor3 = theme.MutedText,
        TextSize = 9,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, statusFrame)
    self.StatusDot = create("Frame", {
        Name = "StatusDot",
        Position = UDim2.fromOffset(10, 12),
        Size = UDim2.fromOffset(6, 6),
        BackgroundColor3 = theme.Success,
        BorderSizePixel = 0,
    }, statusFrame)
    addCorner(self.StatusDot, 4)
    local footerTag = create("TextLabel", {
        Name = "FooterTag",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 0),
        Size = UDim2.fromOffset(60, FOOTER_HEIGHT),
        BackgroundTransparency = 1,
        Font = theme.MonoFont,
        Text = "CUSTOM",
        TextColor3 = theme.MutedText,
        TextSize = 8,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, statusFrame)

    self.Scroll = create("ScrollingFrame", {
        Name = "Page",
        Position = UDim2.new(0, 0, 0, layout.PageHeaderHeight),
        Size = UDim2.new(1, 0, 1, -layout.PageHeaderHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = layout.ScrollBarThickness,
        ScrollBarImageColor3 = theme.Accent,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.None,
    }, self.MainPane)
    self.Content = create("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(9, 7),
        Size = UDim2.new(1, -layout.ScrollContentInset, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
    }, self.Scroll)
    self.ContentLayout = create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, layout.Spacing),
    }, self.Content)
    self._contentSizeConnection = self.ContentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        if self.Scroll and self.ContentLayout then
            self.Scroll.CanvasSize = UDim2.new(0, 0, 0, self.ContentLayout.AbsoluteContentSize.Y + 4)
        end
        self:_ApplySize(self.State:GetSnapshot())
    end)
    table.insert(self.PersistentConnections, self._contentSizeConnection)

    self:_WatchViewport(camera)
    self:_Connect(
        self.PersistentConnections,
        workspace:GetPropertyChangedSignal("CurrentCamera"),
        function()
            self:_WatchViewport(workspace.CurrentCamera)
        end
    )
    self:_Connect(
        self.PersistentConnections,
        self.Root:GetPropertyChangedSignal("AbsoluteSize"),
        function()
            self:_UpdateShellLayout()
            self:_UpdateControlGridLayout()
        end
    )

    self.StateConnection = self.State:Subscribe(function(snapshot)
        self:_Refresh(snapshot)
    end)
    self:_ApplySize(self.State:GetSnapshot())
    self:_RenderTab(self.State:GetSnapshot().selectedTab)
    self:_ClampRestoreButton()
    return true
end

function UI:Destroy()
    if self.StateConnection then
        self.StateConnection:Disconnect()
        self.StateConnection = nil
    end
    if self.ViewportConnection and self.ViewportConnection.Connected then
        self.ViewportConnection:Disconnect()
    end
    self.ViewportConnection = nil
    disconnectAll(self.PageConnections)
    disconnectAll(self.PersistentConnections)
    self:_CancelAllTweens()
    if self.Gui then
        self.Gui:Destroy()
        self.Gui = nil
        self.Root = nil
    end
    self.Header = nil
    self.Sidebar = nil
    self.SearchBox = nil
    self.NavScroll = nil
    self.MainPane = nil
    self.PageHeader = nil
    self.PageTitle = nil
    self.MinimizeButton = nil
    self.RestoreButton = nil
    self.RestoreHalo = nil
    self.RestorePing = nil
    self.SizeConstraint = nil
    self.IsMinimized = false
    self.RestoreDrag = nil
    self.RestoreDragMoved = false
    self.WindowDrag = nil
    self.StatusLabel = nil
    self.StatusDot = nil
    self.TabButtons = {}
    self.TabMarkers = {}
    self.ToggleLabels = {}
    self.SelectorEntries = {}
    self.PressedButtonScale = nil
    self.PressedButtonInput = nil
    self.Scroll = nil
    self.Content = nil
    self.ContentLayout = nil
    self.ControlsContainer = nil
    self.ControlGridLayout = nil
    self.ActiveControls = nil
    self.ActiveTab = nil
    self.SearchQuery = ""
end

return UI
