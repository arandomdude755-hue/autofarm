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
        status = "Hub UI ready; Main Farm is available but disabled.",
        statusKind = "info",
        featureEnabled = {},
    }
    return self
end

function State:GetSnapshot()
    local featureEnabled = {}
    for key, value in pairs(self._values.featureEnabled) do
        featureEnabled[key] = value
    end
    return {
        selectedTab = self._values.selectedTab,
        compact = self._values.compact,
        status = self._values.status,
        statusKind = self._values.statusKind,
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

function State:SetStatus(message, kind)
    local text = tostring(message)
    if #text > self._maxStatusCharacters then
        text = text:sub(1, self._maxStatusCharacters - 3) .. "..."
    end
    self._values.status = text
    self._values.statusKind = kind or "info"
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

function State:SetFeatureEnabled(actionId, enabled)
    self._values.featureEnabled[actionId] = enabled == true
    self:_Notify()
end

function State:ResetPresentation()
    self._values.selectedTab = self._defaults.SelectedTab
    self._values.compact = self._defaults.Compact
    self._values.status = "UI presentation settings reset; feature states are unchanged."
    self._values.statusKind = "success"
    self:_Notify()
end

return State
