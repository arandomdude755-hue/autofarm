local UI = {}
UI.__index = UI

local UserInputService = game:GetService("UserInputService")
local MINIMIZE_BUTTON_WIDTH = 42
local HEADER_BUTTON_GAP = 6
local RESTORE_BUTTON_SIZE = Vector2.new(60, 32)
local RESTORE_DRAG_THRESHOLD = 8

local function create(className, properties, parent)
    local instance = Instance.new(className)
    for property, value in pairs(properties) do
        instance[property] = value
    end
    instance.Parent = parent
    return instance
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
        MinimizeButton = nil,
        RestoreButton = nil,
        IsMinimized = false,
        RestoreDrag = nil,
        RestoreDragMoved = false,
        StatusLabel = nil,
        TabButtons = {},
        ToggleLabels = {},
        PersistentConnections = {},
        PageConnections = {},
        StateConnection = nil,
        Scroll = nil,
        Content = nil,
        ContentLayout = nil,
        ActiveTab = nil,
        _contentSizeConnection = nil,
    }, UI)
end

function UI:_Connect(bucket, signal, callback)
    local connection = signal:Connect(callback)
    table.insert(bucket, connection)
    return connection
end

function UI:_ApplySize(snapshot)
    if not self.Root then
        return
    end
    local layout = self.Config.Layout
    local touch = self.Compatibility:IsTouchEnabled()
    local width
    local height
    if snapshot.compact then
        width = touch and layout.MobileWidth or layout.DesktopWidth
        height = touch and layout.MobileHeight or layout.DesktopHeight
    else
        width = layout.ExpandedWidth
        height = layout.ExpandedHeight
    end
    self.Root.Size = UDim2.fromScale(width, height)
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
    end
    return true
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

    for tabName, button in pairs(self.TabButtons) do
        button.BackgroundColor3 = tabName == snapshot.selectedTab and theme.Selected or theme.Control
        button.TextColor3 = tabName == snapshot.selectedTab and theme.Text or theme.MutedText
    end

    for _, entry in ipairs(self.ToggleLabels) do
        local enabled
        if entry.Control.Kind == "featureToggle" then
            enabled = snapshot.featureEnabled[entry.Control.Action] == true
            entry.Label.Text = enabled and "ON" or "OFF"
        elseif entry.Control.Kind == "settingToggle" then
            enabled = snapshot.compact
            entry.Label.Text = enabled and "On" or "Off"
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
    for _, child in ipairs(self.Content:GetChildren()) do
        if child ~= self.ContentLayout then
            child:Destroy()
        end
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
    local hasToggle = control.Kind == "featureToggle" or control.Kind == "settingToggle"
    local reservedTitleSpace = hasToggle and (layout.ToggleValueWidth + layout.ToggleGap) or 0
    local row = create("TextButton", {
        Name = "Action_" .. control.Action:gsub("[^%w]", "_"),
        Size = UDim2.new(1, 0, 0, layout.RowHeight),
        BackgroundColor3 = theme.Control,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        Font = theme.Font,
        TextSize = theme.TextSizes.Control,
        TextColor3 = theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = #self.Content:GetChildren(),
    }, self.Content)

    create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, row)

    create("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(layout.RowInset, layout.RowTitleTop),
        Size = UDim2.new(1, -layout.RowInset * 2 - reservedTitleSpace, 0, layout.RowTitleHeight),
        BackgroundTransparency = 1,
        Font = theme.StrongFont,
        Text = control.Label,
        TextColor3 = theme.Text,
        TextSize = theme.TextSizes.Control,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)

    create("TextLabel", {
        Name = "Detail",
        Position = UDim2.fromOffset(layout.RowInset, layout.RowDetailTop),
        Size = UDim2.new(1, -layout.RowInset * 2, 0, layout.RowDetailHeight),
        BackgroundTransparency = 1,
        Font = theme.Font,
        Text = control.Detail,
        TextColor3 = theme.MutedText,
        TextSize = theme.TextSizes.Detail,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, row)

    local toggleLabel
    if control.Kind == "featureToggle" or control.Kind == "settingToggle" then
        toggleLabel = create("TextLabel", {
            Name = "Value",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -layout.RowInset, 0, layout.ToggleValueTop),
            Size = UDim2.fromOffset(layout.ToggleValueWidth, layout.ToggleValueHeight),
            BackgroundTransparency = 1,
            Font = theme.StrongFont,
            Text = "Off",
            TextColor3 = theme.Accent,
            TextSize = theme.TextSizes.Detail,
            TextXAlignment = Enum.TextXAlignment.Right,
        }, row)
        table.insert(self.ToggleLabels, { Control = control, Label = toggleLabel })
    end

    self:_Connect(self.PageConnections, row.Activated, function()
        self:_ActivateControl(control)
    end)
end

function UI:_RenderTab(tabName)
    local page = self.Config.Pages[tabName]
    if not page then
        return false
    end

    self.ActiveTab = tabName
    self:_ClearPage()
    local theme = self.Config.Theme
    create("TextLabel", {
        Name = "PageDescription",
        Size = UDim2.new(1, 0, 0, self.Config.Layout.PageDescriptionHeight),
        BackgroundTransparency = 1,
        Font = theme.Font,
        Text = page.Description,
        TextColor3 = theme.MutedText,
        TextSize = theme.TextSizes.Body,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 0,
    }, self.Content)

    for _, control in ipairs(page.Controls) do
        self:_AddControl(control)
    end
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
        IgnoreGuiInset = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 10,
    }, self.PlayerGui)

    self.Root = create("Frame", {
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(layout.MobileWidth, layout.MobileHeight),
        BackgroundColor3 = theme.Background,
        BorderSizePixel = 0,
    }, self.Gui)
    create("UISizeConstraint", {
        MinSize = layout.MinSize,
        MaxSize = layout.MaxSize,
    }, self.Root)
    create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, self.Root)

    local title = create("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(layout.Padding, layout.HeaderTop),
        Size = UDim2.new(
            1,
            -math.max(
                layout.TitleRightInset,
                layout.Padding * 2 + layout.CloseWidth + HEADER_BUTTON_GAP + MINIMIZE_BUTTON_WIDTH
            ),
            0,
            layout.HeaderHeight
        ),
        BackgroundTransparency = 1,
        Font = theme.StrongFont,
        Text = self.Config.Name,
        TextColor3 = theme.Text,
        TextSize = theme.TextSizes.Title,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, self.Root)

    local closeButton = create("TextButton", {
        Name = "Close",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -layout.Padding, 0, layout.HeaderTop),
        Size = UDim2.fromOffset(layout.CloseWidth, layout.CloseHeight),
        BackgroundColor3 = theme.Control,
        BorderSizePixel = 0,
        AutoButtonColor = true,
        Font = theme.Font,
        Text = "Close",
        TextColor3 = theme.MutedText,
        TextSize = theme.TextSizes.Detail,
    }, self.Root)
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
            -(layout.Padding + layout.CloseWidth + HEADER_BUTTON_GAP),
            0,
            layout.HeaderTop
        ),
        Size = UDim2.fromOffset(MINIMIZE_BUTTON_WIDTH, layout.CloseHeight),
        BackgroundColor3 = theme.Control,
        BorderSizePixel = 0,
        AutoButtonColor = true,
        Font = theme.Font,
        Text = "Min",
        TextColor3 = theme.MutedText,
        TextSize = theme.TextSizes.Detail,
    }, self.Root)
    self:_Connect(self.PersistentConnections, self.MinimizeButton.Activated, function()
        self:_SetMinimized(true)
    end)

    self.RestoreButton = create("TextButton", {
        Name = "Restore",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, -38, 0.68, 0),
        Size = UDim2.fromOffset(RESTORE_BUTTON_SIZE.X, RESTORE_BUTTON_SIZE.Y),
        BackgroundColor3 = theme.Control,
        BorderSizePixel = 0,
        AutoButtonColor = true,
        Font = theme.StrongFont,
        Text = "Restore",
        TextColor3 = theme.Text,
        TextSize = theme.TextSizes.Detail,
        Visible = false,
        ZIndex = 20,
    }, self.Gui)
    create("UICorner", {
        CornerRadius = UDim.new(0, RESTORE_BUTTON_SIZE.Y / 2),
    }, self.RestoreButton)
    create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, self.RestoreButton)
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
    self:_Connect(self.PersistentConnections, UserInputService.InputChanged, function(input)
        local drag = self.RestoreDrag
        if not drag or not self.RestoreButton or not self.RestoreButton.Parent then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= drag.Input then
            return
        end

        local delta = input.Position - drag.Start
        if delta.Magnitude >= RESTORE_DRAG_THRESHOLD then
            self.RestoreDragMoved = true
        end
        if not self.RestoreDragMoved then
            return
        end

        local viewport = self.Compatibility:GetViewportSize()
        if typeof(viewport) ~= "Vector2" then
            viewport = Vector2.new(390, 844)
        end
        self.RestoreButton.Position = clampDragPosition(
            drag.Origin,
            delta,
            viewport,
            self.RestoreButton.AbsoluteSize
        )
    end)
    self:_Connect(self.PersistentConnections, UserInputService.InputEnded, function(input)
        local drag = self.RestoreDrag
        if drag and (
            input.UserInputType == Enum.UserInputType.MouseButton1
                or input == drag.Input
        ) then
            self.RestoreDrag = nil
        end
    end)

    local tabWidth = 1 / #self.Config.Tabs
    for index, tabName in ipairs(self.Config.Tabs) do
        local button = create("TextButton", {
            Name = "Tab_" .. tabName,
            Position = UDim2.new((index - 1) * tabWidth, 0, 0, layout.TabsTop),
            Size = UDim2.new(tabWidth, -2, 0, layout.TabHeight),
            BackgroundColor3 = theme.Control,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = theme.StrongFont,
            Text = tabName,
            TextColor3 = theme.MutedText,
            TextSize = theme.TextSizes.Tab,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, self.Root)
        self.TabButtons[tabName] = button
        self:_Connect(self.PersistentConnections, button.Activated, function()
            self:_SelectTab(tabName)
        end)
    end

    local statusFrame = create("Frame", {
        Name = "Status",
        Position = UDim2.new(0, 0, 0, layout.StatusTop),
        Size = UDim2.new(1, 0, 0, layout.StatusHeight),
        BackgroundColor3 = theme.Panel,
        BorderSizePixel = 0,
    }, self.Root)
    create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, statusFrame)
    self.StatusLabel = create("TextLabel", {
        Name = "Message",
        Position = UDim2.fromOffset(layout.StatusInset, layout.StatusTextTop),
        Size = UDim2.new(1, -layout.StatusInset * 2, 1, -layout.StatusTextTop * 2),
        BackgroundTransparency = 1,
        Font = theme.Font,
        Text = "",
        TextColor3 = theme.MutedText,
        TextSize = theme.TextSizes.Status,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, statusFrame)

    self.Scroll = create("ScrollingFrame", {
        Name = "Page",
        Position = UDim2.new(0, 0, 0, layout.ContentTop),
        Size = UDim2.new(1, 0, 1, -layout.ContentTop - 10),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = layout.ScrollBarThickness,
        ScrollBarImageColor3 = theme.Border,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.None,
    }, self.Root)
    self.Content = create("Frame", {
        Name = "Content",
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
    end)
    table.insert(self.PersistentConnections, self._contentSizeConnection)

    self.StateConnection = self.State:Subscribe(function(snapshot)
        self:_Refresh(snapshot)
    end)
    self:_ApplySize(self.State:GetSnapshot())
    self:_RenderTab(self.State:GetSnapshot().selectedTab)
    return true
end

function UI:Destroy()
    if self.StateConnection then
        self.StateConnection:Disconnect()
        self.StateConnection = nil
    end
    disconnectAll(self.PageConnections)
    disconnectAll(self.PersistentConnections)
    if self.Gui then
        self.Gui:Destroy()
        self.Gui = nil
        self.Root = nil
    end
    self.MinimizeButton = nil
    self.RestoreButton = nil
    self.IsMinimized = false
    self.RestoreDrag = nil
    self.RestoreDragMoved = false
end

return UI
