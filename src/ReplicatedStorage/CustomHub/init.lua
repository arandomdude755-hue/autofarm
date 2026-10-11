local Config = require(script.Config)
local State = require(script.State)
local Compatibility = require(script.Compatibility)
local FeatureManager = require(script.FeatureManager)
local UI = require(script.UI)

local Hub = {}
Hub.__index = Hub
local activeHub = nil

function Hub.new()
    local state = State.new(Config.Defaults)
    local compatibility = Compatibility.new()
    local featureManager = FeatureManager.new(state, compatibility, Config)

    return setmetatable({
        State = state,
        Compatibility = compatibility,
        FeatureManager = featureManager,
        UI = nil,
        Started = false,
        Destroying = false,
    }, Hub)
end

function Hub:Start()
    if self.Started then
        return true
    end

    local playerGui, playerGuiError = self.Compatibility:GetPlayerGui()
    if not playerGui then
        self.State:SetStatus(playerGuiError, "error")
        return false, playerGuiError
    end

    if activeHub and activeHub ~= self then
        activeHub:Destroy()
    end

    local initialized, initError = self.FeatureManager:Initialize()
    if not initialized then
        self.State:SetStatus("Feature setup error: " .. tostring(initError), "error")
        return false, initError
    end

    self.UI = UI.new(
        playerGui,
        self.State,
        self.Compatibility,
        Config,
        function(actionId, payload)
            return self.FeatureManager:Dispatch(actionId, payload)
        end,
        function()
            self:Destroy()
        end
    )

    local mounted, mountError = pcall(function()
        self.UI:Mount()
    end)
    if not mounted then
        self.UI:Destroy()
        self.UI = nil
        self.FeatureManager:Cleanup()
        self.State:SetStatus("UI mount error: " .. tostring(mountError), "error")
        return false, tostring(mountError)
    end

    self.Started = true
    activeHub = self
    self.State:SetStatus("Hub UI ready; Main Farm is available but disabled.", "success")
    return true
end

function Hub:Destroy()
    if self.Destroying then
        return
    end
    self.Destroying = true

    if self.UI then
        self.UI:Destroy()
        self.UI = nil
    end
    self.FeatureManager:Cleanup()
    self.Started = false
    if activeHub == self then
        activeHub = nil
    end
    self.State:SetStatus("Hub UI closed; feature cleanup completed.", "info")
    self.Destroying = false
end

return Hub
