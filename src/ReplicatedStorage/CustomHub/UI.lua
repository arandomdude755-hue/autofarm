local UI = {}
UI.__index = UI

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local MINIMIZE_BUTTON_WIDTH = 26
local HEADER_BUTTON_GAP = 5
local RESTORE_BUTTON_SIZE = Vector2.new(56, 56)
local RESTORE_DRAG_THRESHOLD = 8
local WINDOW_VISIBLE_GRIP_WIDTH = 128
local WINDOW_VISIBLE_GRIP_HEIGHT = 24
local HEADER_HEIGHT = 34
local FOOTER_HEIGHT = 24

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
    return tabName == "Farm" and "Farming"
        or tabName == "StatusServer" and "Server Status"
        or tabName
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

local function clampWindowDragPosition(origin, delta, viewport, size, headerHeight)
    local headerExtent = headerHeight or HEADER_HEIGHT
    local visibleGripWidth = math.min(
        WINDOW_VISIBLE_GRIP_WIDTH,
        size.X,
        viewport.X / 2
    )
    local visibleHeaderHeight = math.min(
        WINDOW_VISIBLE_GRIP_HEIGHT,
        headerExtent,
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
    local minCenterY = visibleHeaderHeight - headerExtent + halfY
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
    local self = setmetatable({
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
        RootScale = nil,
        SizeConstraint = nil,
        IsMinimized = false,
        RestoreDrag = nil,
        RestoreDragMoved = false,
        WindowDrag = nil,
        StatusLabel = nil,
        StatusDot = nil,
        NotificationFrame = nil,
        NotificationAccent = nil,
        NotificationStroke = nil,
        NotificationTitle = nil,
        NotificationMessage = nil,
        NotificationTween = nil,
        NotificationGeneration = 0,
        LastNotificationId = 0,
        CurrentNotificationPersistent = false,
        TabButtons = {},
        TabLabels = {},
        TabMarkers = {},
        TabArrows = {},
        TabSubsectionButtons = {},
        TabSubsectionLabels = {},
        ExpandedTabs = {},
        ActiveSubsectionTab = nil,
        ActiveSubsectionLabel = nil,
        ToggleLabels = {},
        SelectorEntries = {},
        StatusValueEntries = {},
        SliderEntries = {},
        ActiveSlider = nil,
        ActiveDropdown = nil,
        LastDropdownTap = nil,
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
        ControlRows = {},
        ControlGroups = {},
        SectionHeaderRecords = {},
        GroupArrows = {},
        CollapsedGroups = {},
        ActiveTab = nil,
        ActivePage = nil,
        SearchQuery = "",
        _contentSizeConnection = nil,
        ViewportConnection = nil,
    }, UI)
    for groupId, collapsed in pairs(config.CollapsibleDefaults or {}) do
        self.CollapsedGroups[groupId] = collapsed == true
    end
    return self
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
        self:_CloseDropdown()
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
    local widthScale = snapshot.compact
        and (touch and layout.MobileWidth or layout.DesktopWidth)
        or layout.ExpandedWidth
    local baseMaxWidth = landscape and layout.MaxSize.X or 500
    local verticalInset = landscape and 56 or 32
    local footprint = layout.UiSizeFootprints
        and layout.UiSizeFootprints[snapshot.uiSize]
    if type(footprint) ~= "number" or footprint <= 0 then
        return false, "Invalid UI size"
    end

    -- UI size changes the window footprint, not control/text scale. This keeps
    -- touch targets readable and lets smaller sizes use the normal scroll flow.
    if self.RootScale then
        self.RootScale.Scale = 1
    end
    local maxWidth = math.min(
        baseMaxWidth * footprint,
        math.max(1, viewport.X - 16)
    )
    local availableHeight = math.max(1, viewport.Y - verticalInset)
    local maxHeight = math.min(landscape and 420 or 740, availableHeight)
        * footprint
    local minWidth = math.min(
        math.max(
            layout.MinSize.X * footprint,
            layout.MinUsableWidth or layout.MinSize.X
        ),
        maxWidth
    )
    local minHeight = math.min(layout.MinSize.Y * footprint, maxHeight)
    local pageHeight = self.ContentLayout
        and self.ContentLayout.AbsoluteContentSize.Y
        or 0
    local desiredHeight = HEADER_HEIGHT + layout.PageHeaderHeight + pageHeight + FOOTER_HEIGHT + 14
    local width = math.max(
        minWidth,
        math.min(viewport.X * widthScale * footprint, maxWidth)
    )
    local height = math.clamp(desiredHeight * footprint, minHeight, maxHeight)
    if self.SizeConstraint then
        self.SizeConstraint.MinSize = Vector2.new(
            math.min(minWidth, width),
            minHeight
        )
        self.SizeConstraint.MaxSize = Vector2.new(maxWidth, maxHeight)
    end
    self.Root.Size = UDim2.fromOffset(math.floor(width), math.floor(height))
    self:_UpdateShellLayout()
    self:_UpdateControlGridLayout()
    self:_SyncControlGridHeight()
    self:_ClampWindow()
end

function UI:_SetMinimized(minimized)
    if not self.Root or not self.RestoreButton or self.IsMinimized == minimized then
        return false
    end

    if minimized then
        self:_CloseDropdown()
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
        self.Root.AbsoluteSize,
        HEADER_HEIGHT * (self.RootScale and self.RootScale.Scale or 1)
    )
end

function UI:_UpdateShellLayout()
    if not self.Root or not self.Sidebar or not self.MainPane then
        return
    end

    local layout = self.Config.Layout
    local rootWidth = self.Root.Size.X.Offset
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
        self.SearchBox.PlaceholderText = sidebarWidth < 214
            and "Search..."
            or "Search section or function"
    end
    if self.Scroll then
        self.Scroll.Position = UDim2.new(0, 0, 0, layout.PageHeaderHeight)
        self.Scroll.Size = UDim2.new(1, 0, 1, -layout.PageHeaderHeight)
    end
end

function UI:_GetSubsectionForPage(pageName)
    for tabName, subsections in pairs(self.Config.TabSubsections or {}) do
        for _, subsection in ipairs(subsections) do
            if (subsection.Page or tabName) == pageName then
                return tabName, subsection
            end
        end
    end
    return nil, nil
end

function UI:_PageMatchesSearch(pageName, query)
    if query == "" then
        return true
    end
    local page = self.Config.Pages[pageName]
    if not page then
        return false
    end
    local pageNameText = page.Title or displayTabName(pageName)
    if string.find(normalizeSearchText(pageNameText), query, 1, true) then
        return true
    end
    for _, control in ipairs(page.Controls or {}) do
        if string.find(normalizeSearchText(control.Label), query, 1, true) then
            return true
        end
    end
    return false
end

function UI:_FindMatchingPageForTab(tabName, query)
    for _, subsection in ipairs((self.Config.TabSubsections or {})[tabName] or {}) do
        local labelMatches = string.find(normalizeSearchText(subsection.Label), query, 1, true) ~= nil
        if labelMatches or self:_PageMatchesSearch(subsection.Page or tabName, query) then
            return subsection.Page or tabName
        end
    end
    if self:_PageMatchesSearch(tabName, query) then
        return tabName
    end
    return nil
end

function UI:_GetControlSettings(control)
    local settingsKey = control and control.SettingsKey or "FarmSettings"
    local settings = self.Config[settingsKey]
    return type(settings) == "table" and settings or {}
end

function UI:_GetControlOptions(control)
    if type(control.OptionsProvider) == "function" then
        local ok, options = pcall(
            control.OptionsProvider,
            self.Compatibility,
            self:_GetControlSettings(control)
        )
        if ok and type(options) == "table" then
            return options
        end
        return {}
    end
    return control.Options or {}
end

function UI:_RefreshDropdownOptions(entry, selectedValue)
    entry.Options = self:_GetControlOptions(entry.Control)
    entry.SelectedValue = selectedValue

    if type(entry.Control.OptionsProvider) ~= "function" then
        if entry.ValueLabel then
            entry.ValueLabel.Text = tostring(
                selectedValue or entry.Control.PlaceholderLabel or "Select"
            )
        end
        return
    end

    local selectedAvailable = false
    for _, option in ipairs(entry.Options) do
        if option == selectedValue then
            selectedAvailable = true
            break
        end
    end
    if not selectedAvailable then
        entry.SelectedValue = nil
        local emptyLabel = entry.Control.EmptyOptionsLabel
        local unavailableLabel = entry.Control.UnavailableSelectionLabel
        local label
        if not selectedValue then
            label = entry.Control.PlaceholderLabel or "Select"
        elseif #entry.Options == 0 then
            label = emptyLabel or "No options available"
        else
            label = unavailableLabel or "Select"
        end
        if entry.ValueLabel then
            entry.ValueLabel.Text = tostring(label)
        end
    elseif entry.ValueLabel then
        entry.ValueLabel.Text = tostring(selectedValue)
    end
end

function UI:_Refresh(snapshot)
    if not self.Gui then
        return
    end
    local selectedParent, selectedSubsection = self:_GetSubsectionForPage(snapshot.selectedTab)
    local navigationChanged = false
    for tabName in pairs(self.ExpandedTabs) do
        local shouldExpand = tabName == selectedParent
        if self.ExpandedTabs[tabName] ~= shouldExpand then
            self.ExpandedTabs[tabName] = shouldExpand
            navigationChanged = true
        end
    end
    if selectedParent and self.ExpandedTabs[selectedParent] ~= true then
        self.ExpandedTabs[selectedParent] = true
        navigationChanged = true
    end
    local nextSubsectionTab = selectedParent
    local nextSubsectionLabel = selectedSubsection and selectedSubsection.Label or nil
    if self.ActiveSubsectionTab ~= nextSubsectionTab
        or self.ActiveSubsectionLabel ~= nextSubsectionLabel
    then
        self.ActiveSubsectionTab = nextSubsectionTab
        self.ActiveSubsectionLabel = nextSubsectionLabel
    end
    if navigationChanged and self.NavScroll then
        self:_LayoutNavigation(true)
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
    for _, entry in ipairs(self.StatusValueEntries) do
        entry.ValueLabel.Text = tostring(snapshot.statusValues[entry.Key] or "—")
    end
    if snapshot.notification then
        self:_ShowNotification(snapshot.notification)
    elseif self.NotificationFrame and self.NotificationFrame.Visible then
        self:_HideNotification()
    end

    for tabName, button in pairs(self.TabButtons) do
        local selected = tabName == snapshot.selectedTab or tabName == selectedParent
        button.BackgroundColor3 = theme.Selected
        button.BackgroundTransparency = selected and 0 or 1
        local stroke = button:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = selected and theme.AccentBorder or theme.Border
            stroke.Transparency = selected and 0.18 or 1
        end
        local label = self.TabLabels[tabName]
        if label then
            label.TextColor3 = selected and theme.Accent or theme.MutedText
        end
        local marker = self.TabMarkers[tabName]
        if marker then
            marker.Visible = true
            marker.Position = UDim2.new(0, 10, 0.5, 0)
            marker.BackgroundColor3 = selected and theme.Accent or theme.MutedText
            marker.Size = selected and UDim2.fromOffset(3, 17) or UDim2.fromOffset(5, 5)
        end
    end
    for tabName, childButtons in pairs(self.TabSubsectionButtons) do
        for label, button in pairs(childButtons) do
            local selected = self.ActiveSubsectionTab == tabName
                and self.ActiveSubsectionLabel == label
            button.BackgroundColor3 = theme.Selected
            button.BackgroundTransparency = selected and 0 or 1
            local textLabel = self.TabSubsectionLabels[tabName]
                and self.TabSubsectionLabels[tabName][label]
            if textLabel then
                textLabel.TextColor3 = selected and theme.Accent or theme.MutedText
            end
            local marker = button:FindFirstChild("SubsectionMarker")
            if marker then
                marker.BackgroundColor3 = selected and theme.Accent or theme.MutedText
            end
        end
    end

    for _, entry in ipairs(self.ToggleLabels) do
        local enabled
        if entry.Control.Kind == "featureToggle" then
            enabled = snapshot.featureEnabled[entry.Control.Action] == true
            entry.Label.Text = enabled and "ON" or "OFF"
            entry.Label.TextColor3 = enabled and theme.Accent or theme.MutedText
        elseif entry.Control.Kind == "settingToggle" then
            local settingName = entry.Control.Setting
            if settingName then
                local settings = self:_GetControlSettings(entry.Control)
                enabled = settings[settingName] == true
            else
                enabled = snapshot.compact
            end
            entry.Label.Text = enabled and "On" or "Off"
            entry.Label.TextColor3 = enabled and theme.Accent or theme.MutedText
        end
        if entry.Track then
            entry.Track.BackgroundColor3 = enabled and theme.Accent or theme.TabBar
            if entry.TrackStroke then
                entry.TrackStroke.Color = enabled and theme.AccentBorder or theme.Border
                entry.TrackStroke.Transparency = enabled and 0.18 or 0.28
            end
        end
        if entry.Thumb then
            entry.Thumb.Position = UDim2.new(
                0,
                enabled and 17 or 3,
                0.5,
                0
            )
        end
    end

    for _, entry in ipairs(self.SelectorEntries) do
        local settings = self:_GetControlSettings(entry.Control)
        local selectedValue = entry.Setting == "UiSize"
            and snapshot.uiSize
            or settings[entry.Setting]
        if entry.Kind == "dropdown" then
            local lockSetting = entry.Control.LockedBySetting
            entry.IsLocked = lockSetting ~= nil and settings[lockSetting] == true
            if entry.IsLocked and self.ActiveDropdown and self.ActiveDropdown.Entry == entry then
                self:_CloseDropdown()
            end
            if entry.IsLocked then
                selectedValue = entry.Control.LockedValue or selectedValue
            end
            self:_RefreshDropdownOptions(entry, selectedValue)
            if entry.ValueLabel then
                entry.ValueLabel.TextColor3 = entry.IsLocked and theme.MutedText or theme.Text
            end
            self:_SetDropdownOpenVisual(
                entry,
                self.ActiveDropdown ~= nil and self.ActiveDropdown.Entry == entry
            )
        else
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
    end

    for _, entry in ipairs(self.SliderEntries) do
        if not self.ActiveSlider or self.ActiveSlider.Entry ~= entry then
            local farmSettings = self.Config.FarmSettings or {}
            local value = tonumber(farmSettings[entry.Setting]) or entry.Control.Min
            self:_UpdateSliderVisual(entry, value)
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

function UI:_ShowNotification(notification)
    local frame = self.NotificationFrame
    if not frame or not notification or notification.Id < self.LastNotificationId then
        return
    end
    if notification.Id == self.LastNotificationId then
        local wasPersistent = self.CurrentNotificationPersistent
        self.NotificationTitle.Text = notification.Title or "Action unavailable"
        self.NotificationMessage.Text = tostring(notification.Message or "")
        self.CurrentNotificationPersistent = notification.Persistent == true
        if self.CurrentNotificationPersistent and not wasPersistent then
            self.NotificationGeneration += 1
            if self.NotificationTween then
                self.NotificationTween:Cancel()
                self.NotificationTween = nil
            end
            frame.Position = UDim2.new(1, -16, 1, -16)
            frame.Visible = true
        end
        return
    end
    self.LastNotificationId = notification.Id
    self.NotificationGeneration += 1
    local generation = self.NotificationGeneration
    if self.NotificationTween then
        self.NotificationTween:Cancel()
        self.NotificationTween = nil
    end

    local theme = self.Config.Theme
    frame.Visible = true
    frame.Position = UDim2.new(1, -16, 1, 96)
    self.NotificationTitle.Text = notification.Title or "Action unavailable"
    self.NotificationMessage.Text = tostring(notification.Message or "")
    local accent = notification.Kind == "error" and theme.Error or theme.Warning
    self.NotificationAccent.BackgroundColor3 = accent
    self.NotificationStroke.Color = accent
    self.NotificationTitle.TextColor3 = accent
    self.CurrentNotificationPersistent = notification.Persistent == true

    local showTween = TweenService:Create(
        frame,
        TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        { Position = UDim2.new(1, -16, 1, -16) }
    )
    self.NotificationTween = showTween
    showTween:Play()

    if self.CurrentNotificationPersistent then
        return
    end
    task.delay(4.5, function()
        if self.NotificationGeneration ~= generation
            or not self.NotificationFrame
            or not self.NotificationFrame.Parent
        then
            return
        end
        if self.NotificationTween then
            self.NotificationTween:Cancel()
        end
        local hideTween = TweenService:Create(
            self.NotificationFrame,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Position = UDim2.new(1, -16, 1, 96) }
        )
        self.NotificationTween = hideTween
        hideTween:Play()
        task.delay(0.2, function()
            if self.NotificationGeneration == generation and self.NotificationFrame then
                self.NotificationFrame.Visible = false
                self.NotificationTween = nil
            end
        end)
    end)
end

function UI:_HideNotification()
    self.NotificationGeneration += 1
    if self.NotificationTween then
        self.NotificationTween:Cancel()
        self.NotificationTween = nil
    end
    if self.NotificationFrame then
        self.NotificationFrame.Visible = false
    end
    self.CurrentNotificationPersistent = false
end

function UI:_ClearPage()
    self:_CloseDropdown()
    if self.ActiveSlider then
        self:_CommitActiveSlider()
    end
    disconnectAll(self.PageConnections)
    self.ToggleLabels = {}
    self.SelectorEntries = {}
    self.StatusValueEntries = {}
    self.SliderEntries = {}
    self.ActiveSlider = nil
    self.ControlsContainer = nil
    self.ControlGridLayout = nil
    self.ActiveControls = nil
    self.ControlRows = {}
    self.ControlGroups = {}
    self.SectionHeaderRecords = {}
    self.GroupArrows = {}
    for _, child in ipairs(self.Content:GetChildren()) do
        if child ~= self.ContentLayout then
            self:_CancelTweensIn(child)
            child:Destroy()
        end
    end
end

function UI:_SyncControlGridHeight()
    if self.ControlsContainer and self.ControlGridLayout then
        local scale = self.RootScale and self.RootScale.Scale or 1
        self.ControlsContainer.Size = UDim2.new(
            1,
            -2,
            0,
            self.ControlGridLayout.AbsoluteContentSize.Y / scale
        )
    end
end

function UI:_SyncControlGroupHeight(group)
    if not group or not group.Card or not group.Card.Parent then
        return
    end
    local contentHeight = group.Layout.AbsoluteContentSize.Y
    local contentTop = group.HeaderHeight > 0
        and (group.HeaderHeight + 4)
        or group.Padding
    group.ControlsFrame.Position = UDim2.fromOffset(group.Padding, contentTop)
    group.ControlsFrame.Size = UDim2.new(
        1,
        -group.Padding * 2,
        0,
        contentHeight
    )
    group.Card.Size = UDim2.new(
        1,
        0,
        0,
        contentTop + contentHeight + group.Padding
    )
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
    for _, group in ipairs(self.ControlGroups) do
        local rowHeight = group.RowHeight or self.Config.Layout.RowHeight
        local columnCount = 1
        if not (self.ActivePage and self.ActivePage.SingleColumn)
            and landscape
            and group.ControlsFrame.AbsoluteSize.X >= 620
            and #group.Controls > 1
        then
            columnCount = 2
        end
        group.Layout.FillDirectionMaxCells = columnCount
        group.Layout.CellSize = columnCount == 2
            and UDim2.new(0.5, -3, 0, rowHeight)
            or UDim2.new(1, 0, 0, rowHeight)
        self:_SyncControlGroupHeight(group)
    end
end

function UI:_IsRequiredSeaAvailable(control)
    local requiredSea = tonumber(control and control.RequiredSea)
    if not requiredSea then
        return true
    end
    local method = requiredSea == 1 and "IsFirstSea"
        or requiredSea == 2 and "IsSecondSea"
        or requiredSea == 3 and "IsThirdSea"
    local check = method and self.Compatibility and self.Compatibility[method]
    if type(check) ~= "function" then
        return false
    end
    local ok, available = pcall(check, self.Compatibility)
    return ok and available == true
end

function UI:_TabMatchesSearch(tabName, query)
    if query == "" then
        return true
    end
    if string.find(normalizeSearchText(displayTabName(tabName)), query, 1, true) then
        return true
    end
    for _, subsection in ipairs((self.Config.TabSubsections or {})[tabName] or {}) do
        if string.find(normalizeSearchText(subsection.Label), query, 1, true)
            or self:_PageMatchesSearch(subsection.Page or tabName, query)
        then
            return true
        end
    end
    return self:_PageMatchesSearch(tabName, query)
end

function UI:_ControlNodeName(control)
    if control.Kind == "sectionHeader" then
        return "Subsection_" .. tostring(control.Label):gsub("[^%w]", "_")
    elseif control.Kind == "collapsibleHeader" then
        return "GroupHeader_" .. tostring(control.GroupId):gsub("[^%w]", "_")
    elseif control.Kind == "statusValue" then
        return "StatusValue_" .. tostring(control.Key):gsub("[^%w]", "_")
    end
    return "Action_" .. tostring(control.Action):gsub("[^%w]", "_")
end

function UI:_IsControlVisible(control)
    for _, groupId in ipairs(control.Groups or {}) do
        if self.CollapsedGroups[groupId] == true then
            return false
        end
    end
    return true
end

function UI:_RefreshControlGroups(animate)
    for control, row in pairs(self.ControlRows) do
        if row and row.Parent then
            row.Visible = self:_IsControlVisible(control)
        end
    end

    for groupId, arrow in pairs(self.GroupArrows) do
        if arrow and arrow.Parent then
            local rotation = self.CollapsedGroups[groupId] == true and 0 or 180
            if animate then
                self:_PlayTween(arrow, 0.14, { Rotation = rotation })
            else
                arrow.Rotation = rotation
            end
        end
    end

    self:_ApplyControlSearchHighlight()
    local oldCanvasPosition = self.Scroll and self.Scroll.CanvasPosition
    task.defer(function()
        if not self.Scroll or not self.ControlsContainer then
            return
        end
        for _, group in ipairs(self.ControlGroups) do
            self:_SyncControlGroupHeight(group)
        end
        self:_SyncControlGridHeight()
        local maximumY = math.max(
            0,
            self.Scroll.CanvasSize.Y.Offset - self.Scroll.AbsoluteSize.Y
        )
        local oldX = oldCanvasPosition and oldCanvasPosition.X or 0
        local oldY = oldCanvasPosition and oldCanvasPosition.Y or 0
        self.Scroll.CanvasPosition = Vector2.new(oldX, math.min(oldY, maximumY))
    end)
end

function UI:_ToggleControlGroup(groupId)
    self.CollapsedGroups[groupId] = self.CollapsedGroups[groupId] ~= true
    self:_RefreshControlGroups(true)
end

function UI:_SetControlGroupExpanded(groupId, expanded)
    self.CollapsedGroups[groupId] = expanded ~= true
    self:_RefreshControlGroups(true)
end

function UI:_ExpandMatchingControlGroups()
    if self.SearchQuery == "" or not self.ActiveControls then
        return
    end
    local changed = false
    for _, control in ipairs(self.ActiveControls) do
        local matches = string.find(
            normalizeSearchText(control.Label),
            self.SearchQuery,
            1,
            true
        ) ~= nil
        if matches then
            if control.Kind == "collapsibleHeader"
                and self.CollapsedGroups[control.GroupId] == true
            then
                self.CollapsedGroups[control.GroupId] = false
                changed = true
            end
            for _, groupId in ipairs(control.Groups or {}) do
                if self.CollapsedGroups[groupId] == true then
                    self.CollapsedGroups[groupId] = false
                    changed = true
                end
            end
        end
    end
    if changed then
        for control, row in pairs(self.ControlRows) do
            if row and row.Parent then
                row.Visible = self:_IsControlVisible(control)
            end
        end
        for groupId, arrow in pairs(self.GroupArrows) do
            if arrow and arrow.Parent then
                local rotation = self.CollapsedGroups[groupId] == true and 0 or 180
                self:_PlayTween(arrow, 0.14, { Rotation = rotation })
            end
        end
        task.defer(function()
            if self.ControlsContainer then
                for _, group in ipairs(self.ControlGroups) do
                    self:_SyncControlGroupHeight(group)
                end
                self:_SyncControlGridHeight()
            end
        end)
    end
end

function UI:_ScrollToControlGroup(groupId)
    if not self.Scroll or not self.ActiveControls then
        return
    end
    for _, control in ipairs(self.ActiveControls) do
        if control.GroupId == groupId then
            local row = self.ControlRows[control]
            if row and row.Visible then
                local rowTop = row.AbsolutePosition.Y
                    - self.Scroll.AbsolutePosition.Y
                    + self.Scroll.CanvasPosition.Y
                self.Scroll.CanvasPosition = Vector2.new(
                    self.Scroll.CanvasPosition.X,
                    math.max(0, rowTop - 4)
                )
            end
            return
        end
    end
end

function UI:_LayoutNavigation(animate)
    if not self.NavScroll then
        return
    end
    local layout = self.Config.Layout
    local query = self.SearchQuery or ""
    local top = layout.SidebarNavInsetTop
    local previousChildVisibility = {}
    for tabName, childButtons in pairs(self.TabSubsectionButtons) do
        previousChildVisibility[tabName] = {}
        for label, childButton in pairs(childButtons) do
            previousChildVisibility[tabName][label] = childButton.Visible
            childButton.Visible = false
        end
    end

    for _, tabName in ipairs(self.Config.Tabs) do
        local button = self.TabButtons[tabName]
        local subsections = (self.Config.TabSubsections or {})[tabName] or {}
        local matches = self:_TabMatchesSearch(tabName, query)
        local matchingSubsection = false
        if query ~= "" then
            for _, subsection in ipairs(subsections) do
                if string.find(normalizeSearchText(subsection.Label), query, 1, true) then
                    matchingSubsection = true
                    self.ExpandedTabs[tabName] = true
                    break
                end
            end
        end
        local visible = matches or matchingSubsection

        if button then
            local wasVisible = button.Visible
            button.Visible = visible
            if visible then
                local position = UDim2.fromOffset(layout.SidebarNavInsetLeft, top)
                if animate and not wasVisible then
                    button.Position = UDim2.fromOffset(
                        position.X.Offset,
                        position.Y.Offset - 5
                    )
                    self:_PlayTween(button, 0.14, { Position = position })
                elseif animate then
                    self:_PlayTween(button, 0.14, { Position = position })
                else
                    button.Position = position
                end
            end
        end

        if visible and button then
            top = top + layout.SidebarRowHeight + layout.SidebarRowGap
            if self.ExpandedTabs[tabName] then
                local parentMatches = matches
                for _, subsection in ipairs(subsections) do
                    local childButton = (self.TabSubsectionButtons[tabName] or {})[subsection.Label]
                    if childButton then
                        local childMatches = query == ""
                            or parentMatches
                            or string.find(
                                normalizeSearchText(subsection.Label),
                                query,
                                1,
                                true
                            ) ~= nil
                        if childMatches then
                            local wasVisible = previousChildVisibility[tabName]
                                and previousChildVisibility[tabName][subsection.Label] == true
                            childButton.Visible = true
                            local position = UDim2.fromOffset(
                                layout.SidebarNavInsetLeft + layout.SidebarChildIndent,
                                top
                            )
                            if animate and not wasVisible then
                                childButton.Position = UDim2.fromOffset(
                                    position.X.Offset,
                                    position.Y.Offset - 5
                                )
                                self:_PlayTween(childButton, 0.14, { Position = position })
                            elseif animate then
                                self:_PlayTween(childButton, 0.14, { Position = position })
                            else
                                childButton.Position = position
                            end
                            top = top + layout.SidebarChildRowHeight + layout.SidebarRowGap
                        end
                    end
                end
            end
        end

        local arrow = self.TabArrows[tabName]
        if arrow then
            local rotation = self.ExpandedTabs[tabName] and 180 or 0
            if animate then
                self:_PlayTween(arrow, 0.14, { Rotation = rotation })
            else
                arrow.Rotation = rotation
            end
        end
    end

    self.NavScroll.CanvasSize = UDim2.new(
        0,
        0,
        0,
        math.max(0, top - layout.SidebarRowGap)
    )
end

function UI:_EnsureExpandedNavigationVisible(tabName)
    local navScroll = self.NavScroll
    local subsections = (self.Config.TabSubsections or {})[tabName] or {}
    if not navScroll or #subsections == 0 then
        return
    end

    task.delay(0.16, function()
        if self.NavScroll ~= navScroll
            or not navScroll.Parent
            or self.ExpandedTabs[tabName] ~= true
        then
            return
        end

        local lastVisibleChild
        for _, subsection in ipairs(subsections) do
            local childButton = (self.TabSubsectionButtons[tabName] or {})[subsection.Label]
            if childButton and childButton.Visible then
                lastVisibleChild = childButton
            end
        end
        if not lastVisibleChild then
            return
        end

        local viewportBottom = navScroll.AbsolutePosition.Y + navScroll.AbsoluteSize.Y
        local childBottom = lastVisibleChild.AbsolutePosition.Y + lastVisibleChild.AbsoluteSize.Y
        local overflow = childBottom - viewportBottom
        if overflow <= 0 then
            return
        end

        local maximumY = math.max(
            0,
            navScroll.CanvasSize.Y.Offset - navScroll.AbsoluteSize.Y
        )
        local targetY = math.min(
            maximumY,
            navScroll.CanvasPosition.Y + overflow + 6
        )
        if targetY > navScroll.CanvasPosition.Y then
            self:_PlayTween(navScroll, 0.16, {
                CanvasPosition = Vector2.new(navScroll.CanvasPosition.X, targetY),
            })
        end
    end)
end

function UI:_SelectSubsection(tabName, subsection)
    self:_SelectTab(subsection.Page or tabName)
    if subsection.GroupId then
        self:_SetControlGroupExpanded(subsection.GroupId, true)
        task.defer(function()
            self:_ScrollToControlGroup(subsection.GroupId)
        end)
    elseif self.Scroll then
        self.Scroll.CanvasPosition = Vector2.zero
    end
    self:_Refresh(self.State:GetSnapshot())
end

function UI:_ApplyControlSearchHighlight()
    if not self.ControlsContainer or not self.ActiveControls then
        return
    end

    local theme = self.Config.Theme
    local query = self.SearchQuery
    for _, control in ipairs(self.ActiveControls) do
        local row = self.ControlRows[control]
        if row then
            row.Visible = self:_IsControlVisible(control)
            local matched = query ~= ""
                and string.find(normalizeSearchText(control.Label), query, 1, true) ~= nil
            local header = self.SectionHeaderRecords[control]
            if header then
                header.Title.TextColor3 = matched and theme.Accent or theme.Text
                header.IconStroke.Color = matched and theme.Accent or theme.AccentBorder
                header.Stroke.Color = matched and theme.AccentBorder or theme.Border
                header.Stroke.Transparency = matched and 0.08 or 0.18
            else
                row.BackgroundColor3 = matched and theme.Selected
                    or control.Kind == "collapsibleHeader" and theme.Header
                    or theme.Control
                row.BackgroundTransparency = matched and 0.06
                    or control.Kind == "collapsibleHeader" and 0.04
                    or control.Kind == "statusValue" and 0.46
                    or 0.18
                local stroke = row:FindFirstChildOfClass("UIStroke")
                if stroke then
                    stroke.Color = matched and theme.AccentBorder or theme.Border
                    stroke.Transparency = matched and 0.12 or 0.4
                end
            end
        end
    end
end

function UI:_ApplySearchFilter()
    if not self.SearchBox or not self.NavScroll then
        return
    end

    local query = normalizeSearchText(self.SearchBox.Text)
    self.SearchQuery = query
    local firstMatch
    for _, tabName in ipairs(self.Config.Tabs) do
        local matches = self:_TabMatchesSearch(tabName, query)
        if matches then
            firstMatch = firstMatch or self:_FindMatchingPageForTab(tabName, query) or tabName
        end
    end
    self:_LayoutNavigation(false)

    local selectedTab = self.State:GetSnapshot().selectedTab
    if query ~= "" and firstMatch and not self:_PageMatchesSearch(selectedTab, query) then
        self:_SelectTab(firstMatch)
    end
    self:_ExpandMatchingControlGroups()
    self:_ApplyControlSearchHighlight()
end

function UI:_SelectTab(tabName)
    if not self.Config.Pages[tabName] then
        self.State:SetStatus("Unknown tab: " .. tostring(tabName), "error")
        return false
    end

    local parentTab, subsection = self:_GetSubsectionForPage(tabName)
    for expandedTab in pairs(self.ExpandedTabs) do
        self.ExpandedTabs[expandedTab] = expandedTab == parentTab
    end
    if parentTab then
        self.ExpandedTabs[parentTab] = true
    end
    self.ActiveSubsectionTab = parentTab
    self.ActiveSubsectionLabel = subsection and subsection.Label or nil
    self.State:SetSelectedTab(tabName)
    self:_LayoutNavigation(true)
    if parentTab then
        self:_EnsureExpandedNavigationVisible(parentTab)
    end
    return true
end

function UI:_ActivateControl(control)
    local snapshot = self.State:GetSnapshot()
    if control.Kind == "featureToggle" then
        return self.Dispatch(control.Action, snapshot.featureEnabled[control.Action] ~= true)
    elseif control.Kind == "settingToggle" then
        local currentValue = snapshot.compact
        if control.Setting then
            local settings = self:_GetControlSettings(control)
            currentValue = settings[control.Setting] == true
        end
        local result = self.Dispatch(control.Action, not currentValue)
        self:_Refresh(self.State:GetSnapshot())
        return result
    end
    return self.Dispatch(control.Action, true)
end

function UI:_SetDropdownOpenVisual(entry, isOpen)
    local theme = self.Config.Theme
    if entry.Arrow then
        entry.Arrow.Text = isOpen and "▲" or "▼"
        entry.Arrow.TextColor3 = entry.IsLocked
            and theme.Warning
            or isOpen and theme.Accent
            or theme.MutedText
    end
    if entry.ValueFrame then
        entry.ValueFrame.BackgroundColor3 = isOpen
            and theme.Selected
            or entry.IsLocked and theme.Control
            or theme.TabBar
    end
    if entry.ValueStroke then
        entry.ValueStroke.Color = theme.AccentBorder
        entry.ValueStroke.Transparency = entry.IsLocked and 0.55 or isOpen and 0.08 or 0.42
    end
end

function UI:_CloseDropdown()
    local dropdown = self.ActiveDropdown
    if not dropdown then
        return
    end
    self.ActiveDropdown = nil
    self.LastDropdownTap = nil
    for _, connection in ipairs(dropdown.Connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    for _, connection in ipairs(dropdown.OptionConnections or {}) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    for _, instance in ipairs(dropdown.Instances) do
        if instance and instance.Parent then
            self:_CancelTweensIn(instance)
            instance:Destroy()
        end
    end
    local entry = dropdown.Entry
    if entry and entry.Arrow and entry.Arrow.Parent then
        self:_SetDropdownOpenVisual(entry, false)
    end
end

function UI:_RenderDropdownOptions(active, query)
    if not active or not active.OptionList then
        return
    end
    for _, connection in ipairs(active.OptionConnections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    table.clear(active.OptionConnections)
    for _, instance in ipairs(active.OptionInstances) do
        if instance and instance.Parent then
            instance:Destroy()
        end
    end
    table.clear(active.OptionInstances)

    local normalizedQuery = string.lower(tostring(query or ""))
    local entry = active.Entry
    local theme = self.Config.Theme
    local optionHeight = active.OptionHeight
    local y = 0
    local matchCount = 0
    for _, value in ipairs(entry.Options) do
        local label = tostring(value)
        if normalizedQuery == ""
            or string.find(string.lower(label), normalizedQuery, 1, true)
        then
            local selected = value == entry.SelectedValue
            local optionButton = create("TextButton", {
                Name = "DropdownOption_" .. label:gsub("[^%w]", "_"),
                Position = UDim2.fromOffset(0, y),
                Size = UDim2.new(1, 0, 0, optionHeight),
                BackgroundColor3 = selected and theme.Selected or theme.Panel,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Font = theme.StrongFont,
                Text = label,
                TextColor3 = selected and theme.Accent or theme.Text,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                ZIndex = 62,
            }, active.OptionList)
            create("UIPadding", {
                PaddingLeft = UDim.new(0, 14),
                PaddingRight = UDim.new(0, 14),
            }, optionButton)
            self:_AttachButtonFeedback(optionButton, active.OptionConnections, 0.97)
            table.insert(active.OptionInstances, optionButton)
            table.insert(active.OptionConnections, optionButton.Activated:Connect(function()
                self:_CloseDropdown()
                local ok, result, actionError =
                    pcall(self.Dispatch, entry.Control.Action, value)
                if not ok then
                    self.State:SetStatus("UI action error: " .. tostring(result), "error")
                elseif result == false and actionError then
                    self.State:SetStatus(tostring(actionError), "error")
                end
            end))
            y += optionHeight
            matchCount += 1
        end
    end

    if matchCount == 0 then
        local empty = create("TextLabel", {
            Name = "DropdownNoResults",
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.new(1, 0, 0, optionHeight),
            BackgroundTransparency = 1,
            Font = theme.Font,
            Text = "No matching options",
            TextColor3 = theme.MutedText,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 62,
        }, active.OptionList)
        table.insert(active.OptionInstances, empty)
        y = optionHeight
    end

    active.OptionList.CanvasPosition = Vector2.new(0, 0)
    active.OptionList.CanvasSize = UDim2.fromOffset(0, y)
    active.OptionList.ScrollingEnabled = y > active.OptionList.AbsoluteSize.Y
end

function UI:_OpenDropdown(entry, searchEnabled)
    self:_CloseDropdown()
    local settings = self:_GetControlSettings(entry.Control)
    local selectedValue = entry.Setting == "UiSize"
        and self.State:GetSnapshot().uiSize
        or settings[entry.Setting]
    self:_RefreshDropdownOptions(entry, selectedValue)
    local options = entry.Options
    if not self.Gui or not self.Root or not entry.Button or #options == 0 then
        self.State:SetStatus("This selector has no available options.", "error")
        return false
    end

    local layout = self.Config.Layout
    local theme = self.Config.Theme
    local scale = self.RootScale and self.RootScale.Scale or 1
    local optionHeight = layout.DropdownOptionHeight
    local searchHeight = searchEnabled and 38 or 0
    local totalHeight = optionHeight * #options + searchHeight
    local anchor = entry.Row or entry.Button
    local rootPosition = self.Root.AbsolutePosition
    local rootSize = self.Root.AbsoluteSize
    local anchorPosition = anchor.AbsolutePosition
    local anchorSize = anchor.AbsoluteSize
    local left = (anchorPosition.X - rootPosition.X) / scale
    local anchorTop = (anchorPosition.Y - rootPosition.Y) / scale
    local anchorHeight = anchorSize.Y / scale
    local belowTop = anchorTop + anchorHeight + 4
    local menuWidth = anchorSize.X / scale
    local rootHeight = rootSize.Y / scale
    local belowAvailable = math.max(0, rootHeight - belowTop - 8)
    local aboveAvailable = math.max(0, anchorTop - 8)
    local openBelow = belowAvailable >= totalHeight
        or belowAvailable >= aboveAvailable
    local availableHeight = openBelow and belowAvailable or aboveAvailable
    local menuHeight = math.min(totalHeight, availableHeight)
    if menuHeight < 1 or (searchEnabled and menuHeight <= searchHeight) then
        self.State:SetStatus("There is not enough room to open this selector.", "error")
        return false
    end
    local top = openBelow and belowTop or math.max(8, anchorTop - menuHeight - 4)

    local active = {
        Entry = entry,
        Connections = {},
        OptionConnections = {},
        OptionInstances = {},
        Instances = {},
        OptionHeight = optionHeight,
    }
    self.ActiveDropdown = active
    self:_SetDropdownOpenVisual(entry, true)

    local overlay = create("TextButton", {
        Name = "DropdownDismissOverlay",
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Selectable = false,
        Text = "",
        ZIndex = 50,
    }, self.Root)
    table.insert(active.Instances, overlay)
    local menu = create("Frame", {
        Name = "DropdownMenu",
        Position = UDim2.fromOffset(left, top),
        Size = UDim2.fromOffset(menuWidth, menuHeight),
        BackgroundColor3 = theme.Panel,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 60,
    }, overlay)
    addCorner(menu, 4)
    create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, menu)
    table.insert(active.Instances, menu)

    if searchEnabled then
        local searchBox = create("TextBox", {
            Name = "DropdownSearch",
            Position = UDim2.fromOffset(7, 5),
            Size = UDim2.new(1, -14, 0, searchHeight - 10),
            BackgroundColor3 = theme.TabBar,
            BorderSizePixel = 0,
            ClearTextOnFocus = false,
            Font = theme.Font,
            PlaceholderText = "Search options...",
            PlaceholderColor3 = theme.MutedText,
            Text = "",
            TextColor3 = theme.Text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 62,
        }, menu)
        addCorner(searchBox, 3)
        create("UIPadding", {
            PaddingLeft = UDim.new(0, 9),
            PaddingRight = UDim.new(0, 9),
        }, searchBox)
        active.SearchBox = searchBox
    end

    local optionList = create("ScrollingFrame", {
        Name = "DropdownOptions",
        Position = UDim2.fromOffset(0, searchHeight),
        Size = UDim2.new(1, 0, 1, -searchHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = theme.Accent,
        CanvasSize = UDim2.fromOffset(0, optionHeight * #options),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollingEnabled = optionHeight * #options > menuHeight - searchHeight,
        AutomaticCanvasSize = Enum.AutomaticSize.None,
        ClipsDescendants = true,
        Active = true,
        ZIndex = 61,
    }, menu)
    active.OptionList = optionList

    local function pointInside(guiObject, position)
        if not guiObject or not guiObject.Parent then
            return false
        end
        local objectPosition = guiObject.AbsolutePosition
        local objectSize = guiObject.AbsoluteSize
        return position.X >= objectPosition.X
            and position.X <= objectPosition.X + objectSize.X
            and position.Y >= objectPosition.Y
            and position.Y <= objectPosition.Y + objectSize.Y
    end

    table.insert(active.Connections, UserInputService.InputBegan:Connect(function(input)
        local inputType = input.UserInputType
        if inputType ~= Enum.UserInputType.Touch
            and inputType ~= Enum.UserInputType.MouseButton1 then
            return
        end
        local position = input.Position
        if pointInside(menu, position) then
            return
        end
        if pointInside(entry.Row or entry.Button, position) then
            self:_HandleDropdownTap(entry)
            return
        end
        self:_CloseDropdown()
    end))

    self:_RenderDropdownOptions(active, "")
    if active.SearchBox then
        table.insert(active.Connections, active.SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
            if self.ActiveDropdown == active then
                self:_RenderDropdownOptions(active, active.SearchBox.Text)
            end
        end))
        active.SearchBox:CaptureFocus()
    end
    return true
end

function UI:_HandleDropdownTap(entry)
    local control = entry.Control
    local lockSetting = control and control.LockedBySetting
    local settings = self:_GetControlSettings(control)
    if lockSetting and settings[lockSetting] == true then
        self.LastDropdownTap = nil
        self:_ToggleDropdown(entry)
        return
    end

    local now = os.clock()
    local previous = self.LastDropdownTap
    local isDoubleTap = previous
        and previous.Entry == entry
        and now - previous.At <= 0.45
    if isDoubleTap then
        self.LastDropdownTap = nil
        self:_OpenDropdown(entry, true)
        return
    end

    self:_ToggleDropdown(entry)
    self.LastDropdownTap = {
        Entry = entry,
        At = now,
    }
end

function UI:_ToggleDropdown(entry)
    if self.ActiveDropdown and self.ActiveDropdown.Entry == entry then
        self:_CloseDropdown()
        return
    end
    local control = entry.Control
    local lockSetting = control and control.LockedBySetting
    local settings = self:_GetControlSettings(control)
    if lockSetting and settings[lockSetting] == true then
        self:_CloseDropdown()
        self.State:SetStatus(
            control.LockedStatus or "Farm method is locked while Farm Materials is active.",
            "warning",
            control.LockedPlayerMessage
                or "Turn off Farm Materials to choose a different farm method."
        )
        return
    end
    self:_OpenDropdown(entry, false)
end

function UI:_UpdateSliderVisual(entry, value)
    local minimum = tonumber(entry.Control.Min) or 0
    local maximum = tonumber(entry.Control.Max) or minimum
    local step = tonumber(entry.Control.Step) or 1
    if step <= 0 then
        step = 1
    end
    value = math.clamp(tonumber(value) or minimum, minimum, maximum)
    value = minimum + math.floor((value - minimum) / step + 0.5) * step
    value = math.min(value, maximum)

    local range = maximum - minimum
    local ratio = range > 0 and (value - minimum) / range or 0
    entry.CurrentValue = value
    entry.PendingValue = value
    if entry.ValueLabel then
        local unit = entry.Control.Unit
        entry.ValueLabel.Text = tostring(value) .. (unit and (" " .. unit) or "")
    end
    if entry.Fill then
        entry.Fill.Size = UDim2.new(ratio, 0, 1, 0)
    end
    if entry.Thumb then
        entry.Thumb.Position = UDim2.new(ratio, 0, 0.5, 0)
    end
end

function UI:_UpdateSliderFromX(entry, positionX)
    if not entry.Track or not entry.Track.Parent then
        return
    end
    local trackPosition = entry.Track.AbsolutePosition
    local trackWidth = entry.Track.AbsoluteSize.X
    if trackWidth <= 0 then
        return
    end

    local minimum = tonumber(entry.Control.Min) or 0
    local maximum = tonumber(entry.Control.Max) or minimum
    local ratio = math.clamp((positionX - trackPosition.X) / trackWidth, 0, 1)
    self:_UpdateSliderVisual(entry, minimum + (maximum - minimum) * ratio)
end

function UI:_CommitActiveSlider()
    local active = self.ActiveSlider
    self.ActiveSlider = nil
    if not active or active.Entry.PendingValue == nil then
        return
    end

    local entry = active.Entry
    local ok, result, actionError = pcall(
        self.Dispatch,
        entry.Control.Action,
        entry.PendingValue
    )
    if not ok then
        self.State:SetStatus("UI action error: " .. tostring(result), "error")
    elseif result == false and actionError then
        self.State:SetStatus(tostring(actionError), "error")
    end
end

function UI:_AddControl(control, parent)
    local theme = self.Config.Theme
    local layout = self.Config.Layout
    local controlParent = parent or self.ControlsContainer
    if control.Kind == "statusValue" then
        local row = create("Frame", {
            Name = self:_ControlNodeName(control),
            Size = UDim2.new(1, 0, 0, layout.RowHeight),
            BackgroundColor3 = theme.Panel,
            BackgroundTransparency = 0.46,
            BorderSizePixel = 0,
            LayoutOrder = #controlParent:GetChildren(),
        }, controlParent)
        addCorner(row, 4)
        local titleWidth = control.Key == "moon" and 0.36 or 0.45
        local valueWidth = 1 - titleWidth
        create("TextLabel", {
            Name = "Title",
            Position = UDim2.fromOffset(layout.RowInset, 0),
            Size = UDim2.new(titleWidth, -layout.RowInset, 1, 0),
            BackgroundTransparency = 1,
            Font = theme.Font,
            Text = control.Label,
            TextColor3 = theme.Text,
            TextSize = theme.TextSizes.Control,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row)
        local valueLabel = create("TextLabel", {
            Name = "Value",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -layout.RowInset, 0, 0),
            Size = UDim2.new(valueWidth, -layout.RowInset * 2, 1, 0),
            BackgroundTransparency = 1,
            Font = theme.MonoFont,
            Text = "—",
            TextColor3 = theme.MutedText,
            TextSize = theme.TextSizes.Status,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row)
        table.insert(self.StatusValueEntries, {
            Key = control.Key,
            ValueLabel = valueLabel,
        })
        return row
    end
    if control.Kind == "collapsibleHeader" then
        local row = create("TextButton", {
            Name = self:_ControlNodeName(control),
            Size = UDim2.new(
                1,
                0,
                0,
                layout.RowHeight
            ),
            BackgroundColor3 = theme.Header,
            BorderSizePixel = 0,
            LayoutOrder = #controlParent:GetChildren(),
        }, controlParent)
        row.AutoButtonColor = false
        row.Text = ""
        self:_AttachButtonFeedback(row, self.PageConnections, 0.985)
        addCorner(row, 4)
        create("UIStroke", {
            Color = theme.Border,
            Thickness = layout.BorderThickness,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Transparency = 0.48,
        }, row)
        create("TextLabel", {
            Name = "Title",
            Position = UDim2.new(0, layout.RowInset + 12, 0, 0),
            Size = UDim2.new(1, -(layout.RowInset * 2 + 42), 1, 0),
            BackgroundTransparency = 1,
            Font = theme.StrongFont,
            Text = control.Label,
            TextColor3 = theme.Text,
            TextSize = theme.TextSizes.Control,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
        }, row)
        local arrow = create("TextLabel", {
            Name = "GroupArrow",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -layout.RowInset, 0.5, 0),
            Size = UDim2.fromOffset(18, 18),
            BackgroundTransparency = 1,
            Font = theme.StrongFont,
            Text = "▼",
            TextColor3 = theme.MutedText,
            TextSize = 10,
            Rotation = self.CollapsedGroups[control.GroupId] == true and 0 or 180,
        }, row)
        self.GroupArrows[control.GroupId] = arrow
        self:_Connect(self.PageConnections, row.Activated, function()
            self:_ToggleControlGroup(control.GroupId)
        end)
        return row
    end

    local hasToggle = control.Kind == "featureToggle"
        or control.Kind == "settingToggle"
    local isSelector = control.Kind == "settingSelect"
    local isDropdown = control.Kind == "settingDropdown"
    local isSlider = control.Kind == "settingSlider"
    local reservedTitleSpace = hasToggle
        and (layout.ToggleValueWidth + layout.ToggleGap)
        or control.Kind == "button"
            and 24
            or 0
    local descriptionHeight = type(control.Description) == "string"
            and control.Description ~= ""
        and 18
        or 0
    local row = create((isSelector or isSlider) and "Frame" or "TextButton", {
        Name = "Action_" .. control.Action:gsub("[^%w]", "_"),
        Size = UDim2.new(1, 0, 0, layout.RowHeight + descriptionHeight),
        BackgroundColor3 = theme.Control,
        BackgroundTransparency = 0.18,
        BorderSizePixel = 0,
        LayoutOrder = #controlParent:GetChildren(),
    }, controlParent)
    addCorner(row, 4)
    create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Transparency = 0.52,
    }, row)
    if row:IsA("TextButton") then
        row.AutoButtonColor = false
        row.Text = ""
        row.Font = theme.Font
        row.TextSize = theme.TextSizes.Control
        row.TextColor3 = theme.Text
        row.TextXAlignment = Enum.TextXAlignment.Left
        self:_AttachButtonFeedback(row, self.PageConnections)
    end

    local titleTop = isSelector and layout.SelectorTitleTop
        or isSlider and layout.RowTitleTop
        or layout.RowTitleTop
    local titleHeight = isSelector and layout.SelectorTitleHeight
        or isSlider and layout.SliderTitleHeight
        or layout.RowTitleHeight
    local titleSize
    if isSelector then
        titleSize = UDim2.new(0, layout.SelectorTitleWidth, 0, titleHeight)
    elseif isDropdown then
        titleSize = UDim2.new(
            1 - layout.DropdownWidthRatio,
            -(layout.RowInset * 2 + layout.DropdownTitleGap),
            0,
            titleHeight
        )
    elseif isSlider then
        titleSize = UDim2.new(
            1,
            -(layout.RowInset * 2 + layout.SliderValueWidth + layout.ToggleGap),
            0,
            titleHeight
        )
    else
        titleSize = UDim2.new(
            1,
            -layout.RowInset * 2 - reservedTitleSpace,
            0,
            titleHeight
        )
    end
    create("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(layout.RowInset, titleTop),
        Size = descriptionHeight > 0
            and UDim2.new(titleSize.X.Scale, titleSize.X.Offset, 0, 22)
            or titleSize,
        BackgroundTransparency = 1,
        Font = theme.StrongFont,
        Text = control.Label,
        TextColor3 = theme.Text,
        TextSize = theme.TextSizes.Control,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)
    if descriptionHeight > 0 then
        create("TextLabel", {
            Name = "Description",
            Position = UDim2.new(0, layout.RowInset, 0, 22),
            Size = UDim2.new(1, -layout.RowInset * 2, 0, 15),
            BackgroundTransparency = 1,
            Font = theme.Font,
            Text = control.Description,
            TextColor3 = theme.MutedText,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row)
    end
    if control.Kind == "button" then
        create("TextLabel", {
            Name = "ActionIndicator",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -layout.RowInset, 0.5, 0),
            Size = UDim2.fromOffset(18, 20),
            BackgroundTransparency = 1,
            Font = theme.StrongFont,
            Text = "›",
            TextColor3 = theme.Accent,
            TextSize = 20,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
        }, row)
    end

    if hasToggle then
        local toggleControl = create("Frame", {
            Name = "ToggleControl",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -layout.RowInset, 0, layout.ToggleValueTop),
            Size = UDim2.fromOffset(layout.ToggleValueWidth, layout.ToggleValueHeight),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        }, row)
        local toggleLabel = create("TextLabel", {
            Name = "Value",
            Size = UDim2.new(1, -36, 1, 0),
            BackgroundTransparency = 1,
            Font = theme.MonoFont,
            Text = "OFF",
            TextColor3 = theme.MutedText,
            TextSize = 8,
            TextXAlignment = Enum.TextXAlignment.Right,
        }, toggleControl)
        local track = create("Frame", {
            Name = "SwitchTrack",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(32, 18),
            BackgroundColor3 = theme.TabBar,
            BorderSizePixel = 0,
        }, toggleControl)
        addCorner(track, 9)
        local trackStroke = create("UIStroke", {
            Color = theme.Border,
            Thickness = layout.BorderThickness,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Transparency = 0.28,
        }, track)
        local thumb = create("Frame", {
            Name = "SwitchThumb",
            Position = UDim2.new(0, 3, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            Size = UDim2.fromOffset(12, 12),
            BackgroundColor3 = theme.Text,
            BorderSizePixel = 0,
        }, track)
        addCorner(thumb, 6)
        table.insert(self.ToggleLabels, {
            Control = control,
            Label = toggleLabel,
            Track = track,
            TrackStroke = trackStroke,
            Thumb = thumb,
        })
    end

    if isSelector then
        row.Size = UDim2.new(1, 0, 0, layout.RowHeight)
        local options = self:_GetControlOptions(control)
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
    elseif isDropdown then
        local options = self:_GetControlOptions(control)
        local settings = self:_GetControlSettings(control)
        local selectedValue = control.Setting == "UiSize"
            and self.State:GetSnapshot().uiSize
            or settings[control.Setting]
        if not selectedValue and not control.AllowNoSelection then
            selectedValue = options[1]
        end
        local valueFrame = create("Frame", {
            Name = "DropdownFace",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -layout.RowInset, 0.5, 0),
            Size = UDim2.new(
                layout.DropdownWidthRatio,
                -layout.RowInset,
                0,
                layout.DropdownHeight
            ),
            BackgroundColor3 = theme.TabBar,
            BorderSizePixel = 0,
            ClipsDescendants = true,
        }, row)
        addCorner(valueFrame, 3)
        local valueStroke = create("UIStroke", {
            Color = theme.AccentBorder,
            Thickness = layout.BorderThickness,
            Transparency = 0.28,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, valueFrame)
        local valueLabel = create("TextLabel", {
            Name = "DropdownValue",
            Position = UDim2.fromOffset(layout.DropdownValueInset, 0),
            Size = UDim2.new(
                1,
                -(layout.DropdownValueInset + layout.DropdownArrowWidth + 2),
                1,
                0
            ),
            BackgroundTransparency = 1,
            Font = theme.StrongFont,
            Text = tostring(selectedValue or "Select"),
            TextColor3 = theme.Accent,
            TextSize = 11,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, valueFrame)
        local arrowDivider = create("Frame", {
            Name = "DropdownArrowDivider",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -layout.DropdownArrowWidth, 0.5, 0),
            Size = UDim2.new(0, 1, 0, 14),
            BackgroundColor3 = theme.Border,
            BorderSizePixel = 0,
        }, valueFrame)
        local arrow = create("TextLabel", {
            Name = "DropdownArrow",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -layout.DropdownArrowInset, 0.5, 0),
            Size = UDim2.new(0, layout.DropdownArrowWidth - layout.DropdownArrowInset, 1, 0),
            BackgroundTransparency = 1,
            Font = theme.StrongFont,
            Text = "▼",
            TextColor3 = theme.MutedText,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
        }, valueFrame)
        local entry = {
            Kind = "dropdown",
            Setting = control.Setting,
            Options = options,
            Row = row,
            Button = row,
            ValueLabel = valueLabel,
            ValueFrame = valueFrame,
            ValueStroke = valueStroke,
            ArrowDivider = arrowDivider,
            Arrow = arrow,
            Control = control,
            SelectedValue = selectedValue,
        }
        table.insert(self.SelectorEntries, entry)
        self:_Connect(self.PageConnections, row.Activated, function()
            local ok, actionError = pcall(self._HandleDropdownTap, self, entry)
            if not ok then
                self.State:SetStatus("UI action error: " .. tostring(actionError), "error")
            end
        end)
    elseif isSlider then
        local farmSettings = self.Config.FarmSettings or {}
        local minimum = tonumber(control.Min) or 0
        local maximum = tonumber(control.Max) or minimum
        local initialValue = tonumber(farmSettings[control.Setting]) or minimum
        local valueLabel = create("TextLabel", {
            Name = "SliderValue",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -layout.RowInset, 0, 2),
            Size = UDim2.fromOffset(layout.SliderValueWidth, layout.SliderTitleHeight - 2),
            BackgroundTransparency = 1,
            Font = theme.MonoFont,
            Text = tostring(initialValue) .. (control.Unit and (" " .. control.Unit) or ""),
            TextColor3 = theme.MutedText,
            TextSize = 9,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row)
        local track = create("Frame", {
            Name = "SliderTrack",
            Position = UDim2.new(0, layout.RowInset, 0, layout.SliderTrackTop),
            Size = UDim2.new(1, -layout.RowInset * 2, 0, layout.SliderTrackHeight),
            BackgroundColor3 = theme.TabBar,
            BorderSizePixel = 0,
            Active = true,
        }, row)
        addCorner(track, 4)
        local fill = create("Frame", {
            Name = "SliderFill",
            Size = UDim2.new(0, 0, 1, 0),
            BackgroundColor3 = theme.Accent,
            BorderSizePixel = 0,
        }, track)
        addCorner(fill, 4)
        local thumb = create("Frame", {
            Name = "SliderThumb",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.fromOffset(10, 10),
            BackgroundColor3 = theme.Text,
            BorderSizePixel = 0,
        }, track)
        addCorner(thumb, 6)
        local entry = {
            Kind = "slider",
            Setting = control.Setting,
            Track = track,
            Fill = fill,
            Thumb = thumb,
            ValueLabel = valueLabel,
            Control = control,
            PendingValue = initialValue,
        }
        self:_UpdateSliderVisual(entry, initialValue)
        table.insert(self.SliderEntries, entry)
        self:_Connect(self.PageConnections, track.InputBegan, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch
            then
                return
            end
            self.ActiveSlider = {
                Entry = entry,
                Input = input.UserInputType == Enum.UserInputType.Touch and input or nil,
            }
            self:_UpdateSliderFromX(entry, input.Position.X)
        end)
    else
        self:_Connect(self.PageConnections, row.Activated, function()
            local ok, actionError = pcall(self._ActivateControl, self, control)
            if not ok then
                self.State:SetStatus("UI action error: " .. tostring(actionError), "error")
            end
        end)
    end
    return row
end

function UI:_CreateControlGroup(group, layoutOrder)
    local theme = self.Config.Theme
    local layout = self.Config.Layout
    local padding = layout.Padding
    local headerHeight = group.HeaderControl
        and (layout.SectionHeaderHeight or 42)
        or 0
    local hasDescription = false
    for _, control in ipairs(group.Controls or {}) do
        if type(control.Description) == "string" and control.Description ~= "" then
            hasDescription = true
            break
        end
    end
    group.RowHeight = layout.RowHeight + (hasDescription and 18 or 0)
    local cardName = group.HeaderControl
        and self:_ControlNodeName(group.HeaderControl)
        or ("ControlGroup_" .. tostring(layoutOrder))

    group.Padding = padding
    group.HeaderHeight = headerHeight
    group.Card = create("Frame", {
        Name = cardName .. "_Card",
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = theme.Panel,
        BorderSizePixel = 0,
        LayoutOrder = layoutOrder,
    }, self.ControlsContainer)
    addCorner(group.Card, 5)
    group.Stroke = create("UIStroke", {
        Color = theme.Border,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Transparency = 0.18,
    }, group.Card)

    if group.HeaderControl then
        group.HeaderBand = create("Frame", {
            Name = "SectionHeaderBand",
            Position = UDim2.fromOffset(1, 1),
            Size = UDim2.new(1, -2, 0, math.max(0, headerHeight - 1)),
            BackgroundColor3 = theme.Header,
            BackgroundTransparency = 0.42,
            BorderSizePixel = 0,
            ZIndex = 2,
        }, group.Card)
        addCorner(group.HeaderBand, 4)
        group.Icon = create("Frame", {
            Name = "SectionIcon",
            Position = UDim2.fromOffset(
                padding,
                math.max(0, (headerHeight - 18) / 2)
            ),
            Size = UDim2.fromOffset(18, 18),
            BackgroundColor3 = theme.AccentSoft or theme.Selected,
            BorderSizePixel = 0,
            ZIndex = 3,
        }, group.Card)
        addCorner(group.Icon, 5)
        group.IconStroke = create("UIStroke", {
            Color = theme.AccentBorder,
            Thickness = layout.BorderThickness,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Transparency = 0.42,
        }, group.Icon)
        group.IconDot = create("Frame", {
            Name = "SectionIconDot",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(6, 6),
            BackgroundColor3 = theme.Accent,
            BorderSizePixel = 0,
            ZIndex = 4,
        }, group.Icon)
        addCorner(group.IconDot, 4)
        group.Title = create("TextLabel", {
            Name = "SectionTitle",
            Position = UDim2.new(0, padding + 27, 0, 0),
            Size = UDim2.new(
                1,
                -(padding * 2 + 27),
                0,
                math.max(0, headerHeight - 1)
            ),
            BackgroundTransparency = 1,
            Font = theme.StrongFont,
            Text = group.HeaderControl.Label,
            TextColor3 = theme.Text,
            TextSize = theme.TextSizes.Control,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 3,
        }, group.Card)
        self.ControlRows[group.HeaderControl] = group.Title
        self.SectionHeaderRecords[group.HeaderControl] = {
            Title = group.Title,
            IconStroke = group.IconStroke,
            Stroke = group.Stroke,
        }
    end

    group.ControlsFrame = create("Frame", {
        Name = "SectionControls",
        Position = UDim2.fromOffset(padding, headerHeight + (headerHeight > 0 and 4 or 0)),
        Size = UDim2.new(1, -padding * 2, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, group.Card)
    group.Layout = create("UIGridLayout", {
        CellSize = UDim2.new(1, 0, 0, group.RowHeight),
        CellPadding = UDim2.fromOffset(7, 5),
        FillDirection = Enum.FillDirection.Horizontal,
        FillDirectionMaxCells = 1,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, group.ControlsFrame)
    table.insert(self.ControlGroups, group)
    self:_Connect(
        self.PageConnections,
        group.Layout:GetPropertyChangedSignal("AbsoluteContentSize"),
        function()
            self:_SyncControlGroupHeight(group)
            self:_SyncControlGridHeight()
        end
    )
    self:_SyncControlGroupHeight(group)
    return group
end

function UI:_RenderTab(tabName)
    local page = self.Config.Pages[tabName]
    if not page then
        return false
    end

    self.ActiveTab = tabName
    if self.PageTitle then
        self.PageTitle.Text = page.Title or displayTabName(tabName)
    end
    self:_ClearPage()
    local layout = self.Config.Layout
    self.ActivePage = page
    self.ActiveControls = page.Controls
    self.ControlRows = {}
    self.ControlGroups = {}
    self.SectionHeaderRecords = {}
    self.GroupArrows = {}
    self.ControlsContainer = create("Frame", {
        Name = "ControlGrid",
        Size = UDim2.new(1, -2, 0, 0),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
    }, self.Content)
    self.ControlGridLayout = create("UIListLayout", {
        Padding = UDim.new(0, layout.Spacing),
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
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
    local visibleControls = {}
    for _, control in ipairs(page.Controls) do
        if self:_IsRequiredSeaAvailable(control) then
            table.insert(visibleControls, control)
        end
    end
    self.ActiveControls = visibleControls
    local groups = {}
    local currentGroup
    for _, control in ipairs(visibleControls) do
        if control.Kind == "sectionHeader" then
            currentGroup = {
                HeaderControl = control,
                Controls = {},
            }
            table.insert(groups, currentGroup)
        else
            if not currentGroup then
                currentGroup = {
                    Controls = {},
                }
                table.insert(groups, currentGroup)
            end
            table.insert(currentGroup.Controls, control)
        end
    end

    for groupIndex, group in ipairs(groups) do
        if #group.Controls == 0 then
            continue
        end
        self:_CreateControlGroup(group, groupIndex)
        for controlIndex, control in ipairs(group.Controls) do
            local row = self:_AddControl(control, group.ControlsFrame)
            if row then
                row.LayoutOrder = controlIndex
                row.Visible = self:_IsControlVisible(control)
                self.ControlRows[control] = row
            end
        end
        self:_SyncControlGroupHeight(group)
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
    self.RootScale = create("UIScale", {
        Scale = 1,
    }, self.Root)
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
        Position = UDim2.fromOffset(10, 10),
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
        Position = UDim2.fromOffset(122, 8),
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
        Position = UDim2.new(1, -8, 0, 6),
        Size = UDim2.fromOffset(layout.CloseWidth, layout.CloseHeight),
        BackgroundColor3 = theme.Control,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = theme.StrongFont,
        Text = "×",
        TextColor3 = theme.MutedText,
        TextSize = 15,
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
            6
        ),
        Size = UDim2.fromOffset(MINIMIZE_BUTTON_WIDTH, layout.CloseHeight),
        BackgroundColor3 = theme.Control,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = theme.StrongFont,
        Text = "−",
        TextColor3 = theme.MutedText,
        TextSize = 15,
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
        local activeSlider = self.ActiveSlider
        if activeSlider
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input == activeSlider.Input)
        then
            self:_UpdateSliderFromX(activeSlider.Entry, input.Position.X)
        end

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
        local activeSlider = self.ActiveSlider
        if activeSlider and (
            input.UserInputType == Enum.UserInputType.MouseButton1
                or input == activeSlider.Input
        ) then
            self:_CommitActiveSlider()
        end

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
    local searchIcon = create("Frame", {
        Name = "SearchIcon",
        Position = UDim2.fromOffset(10, 10),
        Size = UDim2.fromOffset(8, 8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, searchFrame)
    addCorner(searchIcon, 5)
    create("UIStroke", {
        Color = theme.MutedText,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, searchIcon)
    create("Frame", {
        Name = "SearchHandle",
        Position = UDim2.fromOffset(17, 17),
        Size = UDim2.fromOffset(5, 1),
        Rotation = 45,
        BackgroundColor3 = theme.MutedText,
        BorderSizePixel = 0,
    }, searchFrame)
    self.SearchBox = create("TextBox", {
        Name = "SearchInput",
        Position = UDim2.fromOffset(27, 0),
        Size = UDim2.new(1, -32, 1, 0),
        BackgroundTransparency = 1,
        ClearTextOnFocus = false,
        Font = theme.MonoFont,
        PlaceholderText = "Search...",
        PlaceholderColor3 = theme.MutedText,
        Text = "",
        TextColor3 = theme.Text,
        TextSize = 10,
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

    local navTop = layout.SidebarNavInsetTop
    for _, tabName in ipairs(self.Config.Tabs) do
        local subsections = (self.Config.TabSubsections or {})[tabName] or {}
        local button = create("TextButton", {
            Name = "Tab_" .. tabName,
            Position = UDim2.fromOffset(layout.SidebarNavInsetLeft, navTop),
            Size = UDim2.new(1, -layout.SidebarNavInsetLeft * 2, 0, layout.SidebarRowHeight),
            BackgroundColor3 = theme.Selected,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
        }, self.NavScroll)
        addCorner(button, 4)
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
            Position = UDim2.new(0, 10, 0.5, 0),
            Size = UDim2.fromOffset(5, 5),
            BackgroundColor3 = theme.MutedText,
            BorderSizePixel = 0,
        }, button)
        addCorner(marker, 4)
        local label = create("TextLabel", {
            Name = "Label",
            Position = UDim2.new(0, 28, 0, 0),
            Size = UDim2.new(1, subsections[1] and -56 or -36, 1, 0),
            BackgroundTransparency = 1,
            Font = theme.StrongFont,
            Text = displayTabName(tabName),
            TextColor3 = theme.MutedText,
            TextSize = theme.TextSizes.Tab,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
        }, button)
        self.TabButtons[tabName] = button
        self.TabLabels[tabName] = label
        self.TabMarkers[tabName] = marker
        if #subsections > 0 then
            local arrow = create("TextLabel", {
                Name = "ExpandArrow",
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -8, 0.5, 0),
                Size = UDim2.fromOffset(16, 18),
                BackgroundTransparency = 1,
                Font = theme.StrongFont,
                Text = "▼",
                TextColor3 = theme.MutedText,
                TextSize = 9,
                Rotation = 0,
            }, button)
            self.TabArrows[tabName] = arrow
            self.TabSubsectionButtons[tabName] = {}
            self.TabSubsectionLabels[tabName] = {}
        end
        self:_Connect(self.PersistentConnections, button.Activated, function()
            if #subsections > 0 then
                self:_SelectSubsection(tabName, subsections[1])
            else
                self:_SelectTab(tabName)
            end
        end)
        for _, subsection in ipairs(subsections) do
            local childButton = create("TextButton", {
                Name = "Subtab_" .. tabName .. "_" .. tostring(subsection.Label):gsub("[^%w]", "_"),
                Position = UDim2.fromOffset(
                    layout.SidebarNavInsetLeft + layout.SidebarChildIndent,
                    navTop + layout.SidebarRowHeight + layout.SidebarRowGap
                ),
                Size = UDim2.new(
                    1,
                    -(layout.SidebarNavInsetLeft * 2 + layout.SidebarChildIndent),
                    0,
                    layout.SidebarChildRowHeight
                ),
                BackgroundColor3 = theme.Selected,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Text = "",
                Visible = false,
            }, self.NavScroll)
            addCorner(childButton, 3)
            local childMarker = create("Frame", {
                Name = "SubsectionMarker",
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 9, 0.5, 0),
                Size = UDim2.fromOffset(4, 4),
                BackgroundColor3 = theme.MutedText,
                BorderSizePixel = 0,
            }, childButton)
            addCorner(childMarker, 4)
            local childLabel = create("TextLabel", {
                Name = "Label",
                Position = UDim2.new(0, 21, 0, 0),
                Size = UDim2.new(1, -27, 1, 0),
                BackgroundTransparency = 1,
                Font = theme.Font,
                Text = subsection.Label,
                TextColor3 = theme.MutedText,
                TextSize = math.max(9, theme.TextSizes.Tab - 1),
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Center,
            }, childButton)
            self.TabSubsectionButtons[tabName][subsection.Label] = childButton
            self.TabSubsectionLabels[tabName][subsection.Label] = childLabel
            self:_AttachButtonFeedback(childButton, self.PersistentConnections)
            self:_Connect(self.PersistentConnections, childButton.Activated, function()
                self:_SelectSubsection(tabName, subsection)
            end)
        end
        navTop = navTop + layout.SidebarRowHeight + layout.SidebarRowGap
    end
    self:_LayoutNavigation(false)

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
        Position = UDim2.fromOffset(10, 9),
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

    self.NotificationFrame = create("Frame", {
        Name = "ActionErrorNotification",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, 96),
        Size = UDim2.new(0.82, 0, 0, 64),
        BackgroundColor3 = theme.Header,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 50,
    }, self.Gui)
    create("UISizeConstraint", {
        MinSize = Vector2.new(190, 54),
        MaxSize = Vector2.new(290, 68),
    }, self.NotificationFrame)
    addCorner(self.NotificationFrame, 6)
    self.NotificationStroke = create("UIStroke", {
        Color = theme.Error,
        Thickness = layout.BorderThickness,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Transparency = 0.12,
    }, self.NotificationFrame)
    self.NotificationAccent = create("Frame", {
        Name = "Accent",
        Position = UDim2.fromOffset(0, 7),
        Size = UDim2.new(0, 3, 1, -14),
        BackgroundColor3 = theme.Error,
        BorderSizePixel = 0,
        ZIndex = 51,
    }, self.NotificationFrame)
    addCorner(self.NotificationAccent, 3)
    self.NotificationTitle = create("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(12, 5),
        Size = UDim2.new(1, -22, 0, 18),
        BackgroundTransparency = 1,
        Font = theme.StrongFont,
        Text = "Action unavailable",
        TextColor3 = theme.Error,
        TextSize = math.max(10, theme.TextSizes.Control - 1),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 52,
    }, self.NotificationFrame)
    self.NotificationMessage = create("TextLabel", {
        Name = "Message",
        Position = UDim2.fromOffset(12, 24),
        Size = UDim2.new(1, -22, 1, -29),
        BackgroundTransparency = 1,
        Font = theme.Font,
        Text = "",
        TextColor3 = theme.Text,
        TextSize = math.max(9, theme.TextSizes.Control - 2),
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 52,
    }, self.NotificationFrame)

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
            local scale = self.RootScale and self.RootScale.Scale or 1
            local contentTop = self.Content and self.Content.Position.Y.Offset or 0
            local bottomPadding = layout.ScrollBottomPadding or 28
            self.Scroll.CanvasSize = UDim2.new(
                0,
                0,
                0,
                (contentTop + self.ContentLayout.AbsoluteContentSize.Y) / scale
                    + bottomPadding
            )
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
    local gameWorkspace = self.Compatibility and self.Compatibility.Workspace
    if gameWorkspace and type(gameWorkspace.GetAttributeChangedSignal) == "function" then
        self:_Connect(
            self.PersistentConnections,
            gameWorkspace:GetAttributeChangedSignal("MAP"),
            function()
                self:_CloseDropdown()
                local pageHasSeaControls = false
                for _, control in ipairs(self.ActivePage and self.ActivePage.Controls or {}) do
                    if control.RequiredSea then
                        pageHasSeaControls = true
                        break
                    end
                end
                if pageHasSeaControls and self.ActiveTab then
                    self:_RenderTab(self.ActiveTab)
                else
                    self:_Refresh(self.State:GetSnapshot())
                end
            end
        )
    end
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
    self:_CloseDropdown()
    self.NotificationGeneration += 1
    if self.NotificationTween then
        self.NotificationTween:Cancel()
        self.NotificationTween = nil
    end
    if self.ActiveSlider then
        self:_CommitActiveSlider()
    end
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
    self.RootScale = nil
    self.SizeConstraint = nil
    self.IsMinimized = false
    self.RestoreDrag = nil
    self.RestoreDragMoved = false
    self.WindowDrag = nil
    self.StatusLabel = nil
    self.StatusDot = nil
    self.NotificationFrame = nil
    self.NotificationAccent = nil
    self.NotificationStroke = nil
    self.NotificationTitle = nil
    self.NotificationMessage = nil
    self.TabButtons = {}
    self.TabLabels = {}
    self.TabMarkers = {}
    self.TabArrows = {}
    self.TabSubsectionButtons = {}
    self.TabSubsectionLabels = {}
    self.ExpandedTabs = {}
    self.ActiveSubsectionTab = nil
    self.ActiveSubsectionLabel = nil
    self.TabArrows = {}
    self.TabSubsectionButtons = {}
    self.TabSubsectionLabels = {}
    self.ExpandedTabs = {}
    self.ActiveSubsectionTab = nil
    self.ActiveSubsectionLabel = nil
    self.ToggleLabels = {}
    self.SelectorEntries = {}
    self.SliderEntries = {}
    self.ActiveSlider = nil
    self.ActiveDropdown = nil
    self.PressedButtonScale = nil
    self.PressedButtonInput = nil
    self.Scroll = nil
    self.Content = nil
    self.ContentLayout = nil
    self.ControlsContainer = nil
    self.ControlGridLayout = nil
    self.ActiveControls = nil
    self.ControlRows = {}
    self.ControlGroups = {}
    self.SectionHeaderRecords = {}
    self.GroupArrows = {}
    self.CollapsedGroups = {}
    self.ActiveTab = nil
    self.SearchQuery = ""
end

return UI
