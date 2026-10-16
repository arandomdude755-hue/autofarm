local Config = require(script.Config)
local State = require(script.State)
local Compatibility = require(script.Compatibility)
local SettingsPersistence = require(script.SettingsPersistence)
local FeatureManager = require(script.FeatureManager)
local UI = require(script.UI)

local Hub = {}
Hub.__index = Hub
local activeHub = nil
local RUNTIME_GUARD_NAME = "__CustomHubRuntimeGuard"
local RUNTIME_GUARD_TIMEOUT = 30

function Hub:_AcquireRuntimeGuard(playerGui)
    if playerGui:FindFirstChild("CustomHubShell") then
        return false, "Custom Hub is already running"
    end

    local existingGuard = playerGui:FindFirstChild(RUNTIME_GUARD_NAME)
    if existingGuard then
        local startedAt = tonumber(existingGuard:GetAttribute("StartedAt"))
        local isReady = existingGuard:GetAttribute("Ready") == true
        if isReady or not startedAt or os.clock() - startedAt > RUNTIME_GUARD_TIMEOUT then
            existingGuard:Destroy()
        else
            return false, "Custom Hub startup is already in progress"
        end
    end

    local guard = Instance.new("Folder")
    guard.Name = RUNTIME_GUARD_NAME
    guard:SetAttribute("StartedAt", os.clock())
    guard:SetAttribute("Ready", false)
    guard.Parent = playerGui
    self.RuntimeGuard = guard
    return true
end

function Hub:_ReleaseRuntimeGuard()
    if self.RuntimeGuard then
        pcall(function()
            self.RuntimeGuard:Destroy()
        end)
        self.RuntimeGuard = nil
    end
end

function Hub.new()
    local compatibility = Compatibility.new()
    local settingsPersistence = SettingsPersistence.new(Config, compatibility)
    settingsPersistence:Load()
    local state = State.new(Config.Defaults)
    settingsPersistence:SetState(state)
    local featureManager = FeatureManager.new(
        state,
        compatibility,
        Config,
        settingsPersistence
    )

    return setmetatable({
        State = state,
        Compatibility = compatibility,
        SettingsPersistence = settingsPersistence,
        FeatureManager = featureManager,
        UI = nil,
        Started = false,
        Destroying = false,
        TeamSelectionGeneration = 0,
        TeamSelectionTask = nil,
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
        self.DuplicateExecution = true
        self.SettingsPersistence:Destroy()
        return true, "Duplicate execution ignored; the existing hub was kept open"
    end

    local guardAcquired = self:_AcquireRuntimeGuard(playerGui)
    if not guardAcquired then
        self.DuplicateExecution = true
        self.SettingsPersistence:Destroy()
        return true, "Duplicate execution ignored; the existing hub was kept open"
    end

    local initialized, initError = self.FeatureManager:Initialize()
    if not initialized then
        self:_ReleaseRuntimeGuard()
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
        self:_ReleaseRuntimeGuard()
        self.State:SetStatus("UI mount error: " .. tostring(mountError), "error")
        return false, tostring(mountError)
    end

    self.Started = true
    activeHub = self
    if self.RuntimeGuard and self.RuntimeGuard.Parent then
        self.RuntimeGuard:SetAttribute("Ready", true)
    end
    self.State:SetStatus("Hub UI ready; Main Farm is available but disabled.", "success")
    local startupSettings = Config.StartupSettings or {}
    local teamName = startupSettings.Team == "Pirates" and "Pirates" or "Marines"
    self.TeamSelectionGeneration += 1
    local teamSelectionGeneration = self.TeamSelectionGeneration
    self.TeamSelectionTask = task.spawn(function()
        local selected, selectionResult = self.Compatibility:SelectTeamIfPrompted(
            teamName,
            25
        )
        if self.Destroying
            or not self.Started
            or self.TeamSelectionGeneration ~= teamSelectionGeneration
        then
            return
        end
        if not selected then
            self.TeamSelectionWarning = selectionResult
            self.State:SetStatus(
                "Auto team selection couldn't finish: " .. tostring(selectionResult),
                "warning"
            )
        else
            self.TeamSelectionWarning = nil
        end
    end)
    local mainFarm = self.FeatureManager
        and self.FeatureManager.Context
        and self.FeatureManager.Context.MainFarm
    local settingsWarning = self.SettingsPersistence
        and self.SettingsPersistence:GetStartupWarning()
    if settingsWarning then
        self.State:SetStatus(settingsWarning, "warning")
    elseif mainFarm and mainFarm.ServerHopPausedOnLoad then
        self.State:SetStatus(
            "Saved server search is paused after reload. Turn its toggle off and back on to start again.",
            "warning"
        )
    end
    if startupSettings.AutoExecute == true then
        local queued, queueError = self.Compatibility:SetAutoExecuteEnabled(true)
        if not queued then
            self.State:SetStatus(
                "Auto Execute couldn't be queued: " .. tostring(queueError),
                "warning"
            )
        end
    end
    return true
end

function Hub:Destroy()
    if self.Destroying then
        return
    end
    if self.DuplicateExecution then
        self.DuplicateExecution = false
        return
    end
    self.Destroying = true
    self.TeamSelectionGeneration += 1
    if self.TeamSelectionTask then
        pcall(task.cancel, self.TeamSelectionTask)
        self.TeamSelectionTask = nil
    end

    if self.UI then
        self.UI:Destroy()
        self.UI = nil
    end
    self:_ReleaseRuntimeGuard()
    if self.SettingsPersistence then
        self.SettingsPersistence:Flush()
    end
    self.FeatureManager:Cleanup()
    if self.SettingsPersistence then
        self.SettingsPersistence:Destroy()
        self.SettingsPersistence = nil
    end
    self.Started = false
    if activeHub == self then
        activeHub = nil
    end
    self.State:SetStatus("Hub UI closed; feature cleanup completed.", "info")
    self.Destroying = false
end

return Hub
