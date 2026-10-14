local State = {}
State.__index = State

function State.new(defaults)
    local self = setmetatable({}, State)
    self._listeners = {}
    self._defaults = defaults
    self._maxStatusCharacters = defaults.StatusMaxCharacters or 88
    self._values = {
        selectedTab = defaults.SelectedTab,
        compact = defaults.Compact,
        uiSize = defaults.UiSize,
        status = "Hub UI ready; Main Farm is available but disabled.",
        statusKind = "info",
        statusValues = {},
        notification = nil,
        featureEnabled = {},
    }
    self._notificationSerial = 0
    self._lastNotificationKey = nil
    self._lastNotificationAt = 0
    return self
end

function State:GetSnapshot()
    local featureEnabled = {}
    for key, value in pairs(self._values.featureEnabled) do
        featureEnabled[key] = value
    end
    local statusValues = {}
    for key, value in pairs(self._values.statusValues) do
        statusValues[key] = value
    end
    return {
        selectedTab = self._values.selectedTab,
        compact = self._values.compact,
        uiSize = self._values.uiSize,
        status = self._values.status,
        statusKind = self._values.statusKind,
        statusValues = statusValues,
        notification = self._values.notification,
        featureEnabled = featureEnabled,
    }
end

function State:_Notify()
    local snapshot = self:GetSnapshot()
    for index = #self._listeners, 1, -1 do
        local listener = self._listeners[index]
        local ok = pcall(listener, snapshot)
        if not ok then
            table.remove(self._listeners, index)
        end
    end
end

function State:Subscribe(listener)
    table.insert(self._listeners, listener)
    local connected = true
    return {
        Disconnect = function()
            if not connected then
                return
            end
            connected = false
            for index = #self._listeners, 1, -1 do
                if self._listeners[index] == listener then
                    table.remove(self._listeners, index)
                    break
                end
            end
        end,
    }
end

function State:_QueueErrorNotification(playerMessage, kind)
    local notificationKind = kind == "warning" and "warning" or "error"
    local title = notificationKind == "warning" and "Action needed" or "Action unavailable"
    local body = tostring(
        playerMessage
            or "That action couldn't be completed. Check the hub status line for details."
    )
    local key = title .. "\0" .. body
    local now = os.clock()
    if key == self._lastNotificationKey and now - self._lastNotificationAt < 1.25 then
        return
    end
    self._lastNotificationKey = key
    self._lastNotificationAt = now
    self._notificationSerial += 1
    self._values.notification = {
        Id = self._notificationSerial,
        Title = title,
        Message = body,
        Kind = notificationKind,
    }
end

function State:SetStatus(message, kind, playerMessage)
    local text = tostring(message)
    if #text > self._maxStatusCharacters then
        text = text:sub(1, self._maxStatusCharacters - 3) .. "..."
    end
    self._values.status = text
    self._values.statusKind = kind or "info"
    if kind == "error" or (kind == "warning" and playerMessage ~= nil) then
        self:_QueueErrorNotification(playerMessage, kind)
    end
    self:_Notify()
end

function State:SetSelectedTab(tabName)
    self._values.selectedTab = tabName
    self:_Notify()
end

function State:SetCompact(enabled)
    self._values.compact = enabled == true
    self:_Notify()
end

function State:SetUiSize(size)
    self._values.uiSize = size
    self:_Notify()
end

function State:SetFeatureEnabled(actionId, enabled)
    self._values.featureEnabled[actionId] = enabled == true
    self:_Notify()
end

function State:SetStatusValues(values)
    local nextValues = {}
    if type(values) == "table" then
        for key, value in pairs(values) do
            nextValues[key] = tostring(value)
        end
    end
    self._values.statusValues = nextValues
    self:_Notify()
end

function State:ResetPresentation()
    self._values.selectedTab = self._defaults.SelectedTab
    self._values.compact = self._defaults.Compact
    self._values.uiSize = self._defaults.UiSize
    self._values.status = "UI presentation settings reset; feature states are unchanged."
    self._values.statusKind = "success"
    self:_Notify()
end

return State
