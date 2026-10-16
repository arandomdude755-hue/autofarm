local SettingsPersistence = {}
SettingsPersistence.__index = SettingsPersistence

local SCHEMA_VERSION = 2
local SETTINGS_FOLDER = "CustomHub"
local HOP_SESSION_FILE_PREFIX = SETTINGS_FOLDER .. "/hop_session_"
local SAVE_DEBOUNCE_SECONDS = 0.6
local SETTING_KINDS = {
    settingDropdown = true,
    settingSelect = true,
    settingSlider = true,
    settingToggle = true,
}

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function isSimpleString(value)
    return type(value) == "string"
        and #value > 0
        and #value <= 128
        and not value:find("[%c]")
end

local function optionValue(option)
    if type(option) == "string" then
        return option
    end
    if type(option) == "table" then
        return option.Value or option.value or option.Name or option.Label
    end
    return nil
end

local function containsOption(options, value)
    if type(options) ~= "table" then
        return nil
    end
    for _, option in ipairs(options) do
        if optionValue(option) == value then
            return true
        end
    end
    return false
end

local function deepEqual(left, right)
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in pairs(left) do
        if not deepEqual(value, right[key]) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function copyTable(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[key] = copyTable(child)
    end
    return result
end

local function validateHopSession(value)
    if type(value) ~= "table"
        or tonumber(value.PlaceId) == nil
        or tonumber(value.PlaceId) <= 0
        or type(value.ExpiresAt) ~= "number"
        or value.ExpiresAt <= os.time()
        or value.ExpiresAt > os.time() + 86400
        or type(value.Modes) ~= "table"
    then
        return nil
    end

    local modes = {
        EliteHunter = value.Modes.EliteHunter == true,
        Berry = value.Modes.Berry == true,
    }
    if not modes.EliteHunter and not modes.Berry then
        return nil
    end

    local visited = {}
    if type(value.Visited) == "table" then
        for _, jobId in ipairs(value.Visited) do
            if isSimpleString(jobId) then
                visited[#visited + 1] = jobId
                if #visited >= 300 then
                    break
                end
            end
        end
    end

    local session = {
        PlaceId = math.floor(tonumber(value.PlaceId)),
        ExpiresAt = math.floor(value.ExpiresAt),
        Modes = modes,
        Visited = visited,
    }
    if isSimpleString(value.PendingJobId) then
        session.PendingJobId = value.PendingJobId
    end
    if type(value.Cursor) == "string" and #value.Cursor <= 2048 then
        session.Cursor = value.Cursor
    end
    return session
end

function SettingsPersistence.new(config, compatibility)
    local self = setmetatable({
        Config = config,
        Compatibility = compatibility,
        State = nil,
        Storage = nil,
        Path = nil,
        HopPath = nil,
        InterfacePath = nil,
        InterfacePreferences = nil,
        InterfaceNeedsSave = false,
        Rules = {},
        LastSnapshot = nil,
        HopSession = nil,
        SaveGeneration = 0,
        Destroyed = false,
        ReadOnly = false,
        LoadedFromFile = false,
        LoadWarning = nil,
        LastSaveWarningAt = 0,
    }, SettingsPersistence)

    self:_BuildRules()
    self:_InitializeStorage()
    return self
end

function SettingsPersistence:_BuildRules()
    local config = self.Config or {}
    local pages = config.Pages
    if type(pages) ~= "table" then
        return
    end

    for _, page in pairs(pages) do
        for _, control in ipairs(type(page) == "table" and page.Controls or {}) do
            local kind = control.Kind
            local setting = control.Setting
            if SETTING_KINDS[kind] and type(setting) == "string" then
                local group = control.SettingsKey or "FarmSettings"
                if group == "FarmSettings"
                    or group == "StackFarmSettings"
                    or group == "TravelSettings"
                    or group == "StartupSettings"
                then
                    self.Rules[group] = self.Rules[group] or {}
                    self.Rules[group][setting] = control
                end
            end
        end
    end
end

function SettingsPersistence:_InitializeStorage()
    local compatibility = self.Compatibility
    local player = compatibility and compatibility.Player
    local userId = player and tonumber(player.UserId)
    if not userId or userId <= 0 or userId % 1 ~= 0 then
        self.LoadWarning = "Settings auto-save is unavailable for this player session."
        return
    end

    local storage, storageError = compatibility:GetLocalSettingsStorage()
    if not storage then
        self.LoadWarning = "Settings are session-only; local file storage is unavailable."
        self.StorageError = storageError
        return
    end

    self.Storage = storage
    local userIdText = tostring(userId)
    self.Path = SETTINGS_FOLDER .. "/settings_" .. userIdText .. ".json"
    self.HopPath = HOP_SESSION_FILE_PREFIX .. userIdText .. ".json"
    self.InterfacePath = SETTINGS_FOLDER .. "/ui_settings.json"
end

function SettingsPersistence:SetState(state)
    self.State = state
    local preferences = self.InterfacePreferences
    if state and type(preferences) == "table" then
        if type(preferences.UiSize) == "string" then
            state:SetUiSize(preferences.UiSize)
        end
        if type(preferences.Compact) == "boolean" then
            state:SetCompact(preferences.Compact)
        end
    end
    self.LastSnapshot = self:_Capture()
    if self.InterfaceNeedsSave then
        self:Save()
    end
end

function SettingsPersistence:_ValidateSetting(control, value)
    if control.Kind == "settingToggle" then
        return type(value) == "boolean"
    end

    if control.Kind == "settingSlider" then
        if not isFiniteNumber(value) then
            return false
        end
        local minimum = tonumber(control.Min)
        local maximum = tonumber(control.Max)
        return minimum ~= nil and maximum ~= nil
            and value >= minimum and value <= maximum
    end

    if control.Kind == "settingDropdown" or control.Kind == "settingSelect" then
        if not isSimpleString(value) then
            return false
        end
        local optionResult = containsOption(control.Options, value)
        if optionResult == false then
            return false
        end
        return true
    end

    return false
end

function SettingsPersistence:_Capture()
    local snapshot = {
        SchemaVersion = SCHEMA_VERSION,
        Settings = {},
        Interface = {},
    }
    local config = self.Config or {}

    for group, rules in pairs(self.Rules) do
        local source = config[group]
        if type(source) == "table" then
            local savedGroup = {}
            for setting, control in pairs(rules) do
                local value = source[setting]
                if value ~= nil and self:_ValidateSetting(control, value) then
                    savedGroup[setting] = value
                end
            end
            snapshot.Settings[group] = savedGroup
        end
    end

    local progression = config.ProgressionSettings
    if type(progression) == "table" then
        snapshot.Settings.ProgressionSettings = {
            AutoUnlockSea2 = progression.AutoUnlockSea2 == true,
            AutoUnlockSea3 = progression.AutoUnlockSea3 == true,
            TrevorFruit = isSimpleString(progression.TrevorFruit)
                    and progression.TrevorFruit
                or nil,
            ResumeMainFarmAfterSeaUnlock =
                progression.ResumeMainFarmAfterSeaUnlock == true,
            ResumeSea = tonumber(progression.ResumeSea),
        }
    end

    local state = self.State
    local stateValues = state and state:GetSnapshot()
    local defaults = config.Defaults or {}
    local uiSize = stateValues and stateValues.uiSize or defaults.UiSize
    local compact = stateValues and stateValues.compact
    if compact == nil then
        compact = defaults.Compact
    end
    if type(uiSize) == "string" then
        snapshot.Interface.UiSize = uiSize
    end
    if type(compact) == "boolean" then
        snapshot.Interface.Compact = compact
    end
    return snapshot
end

function SettingsPersistence:_ApplySavedSettings(data)
    local config = self.Config or {}
    local savedGroups = data.Settings
    if type(savedGroups) == "table" then
        for group, rules in pairs(self.Rules) do
            local savedGroup = savedGroups[group]
            local target = config[group]
            if type(savedGroup) == "table" and type(target) == "table" then
                for setting, control in pairs(rules) do
                    local value = savedGroup[setting]
                    if value ~= nil and self:_ValidateSetting(control, value) then
                        target[setting] = value
                    end
                end
            end
        end
        local savedProgression = savedGroups.ProgressionSettings
        local progression = config.ProgressionSettings
        if type(savedProgression) == "table" and type(progression) == "table" then
            progression.AutoUnlockSea2 = savedProgression.AutoUnlockSea2 == true
            progression.AutoUnlockSea3 = savedProgression.AutoUnlockSea3 == true
            progression.TrevorFruit = isSimpleString(savedProgression.TrevorFruit)
                    and savedProgression.TrevorFruit
                or nil
            progression.ResumeMainFarmAfterSeaUnlock =
                savedProgression.ResumeMainFarmAfterSeaUnlock == true
            local resumeSea = tonumber(savedProgression.ResumeSea)
            progression.ResumeSea = (resumeSea == 2 or resumeSea == 3)
                and math.floor(resumeSea)
                or nil
        end
    end

    local interface = data.Interface
    local defaults = config.Defaults
    local footprints = config.Layout and config.Layout.UiSizeFootprints
    if type(interface) == "table" and type(defaults) == "table" then
        self.InterfacePreferences = {}
        if type(interface.UiSize) == "string"
            and type(footprints) == "table"
            and type(footprints[interface.UiSize]) == "number"
        then
            self.InterfacePreferences.UiSize = interface.UiSize
        end
        if type(interface.Compact) == "boolean" then
            self.InterfacePreferences.Compact = interface.Compact
        end
    end
end

function SettingsPersistence:_LoadSharedInterface(legacyPreferences)
    local preferences = type(legacyPreferences) == "table"
        and copyTable(legacyPreferences)
        or {}
    self.InterfaceNeedsSave = false

    if not self.Storage or not self.InterfacePath then
        self.InterfacePreferences = preferences
        return
    end

    local fileExists
    if type(self.Storage.Exists) == "function" then
        local existsOk, exists = pcall(self.Storage.Exists, self.InterfacePath)
        if existsOk and type(exists) == "boolean" then
            fileExists = exists
        end
    end
    if fileExists == false then
        self.InterfacePreferences = preferences
        self.InterfaceNeedsSave = true
        return
    end

    local readOk, content = pcall(self.Storage.Read, self.InterfacePath)
    if not readOk or type(content) ~= "string" or content == "" then
        self.InterfacePreferences = preferences
        self.InterfaceNeedsSave = true
        return
    end

    local decodeOk, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(content)
    end)
    local interface = decodeOk and type(data) == "table"
        and type(data.Interface) == "table"
        and data.Interface
        or nil
    if not interface then
        self.InterfacePreferences = preferences
        self.InterfaceNeedsSave = true
        return
    end

    local defaults = self.Config and self.Config.Defaults
    local footprints = self.Config
        and self.Config.Layout
        and self.Config.Layout.UiSizeFootprints
    if type(interface.UiSize) == "string"
        and type(footprints) == "table"
        and type(footprints[interface.UiSize]) == "number"
    then
        preferences.UiSize = interface.UiSize
    end
    if type(interface.Compact) == "boolean" then
        preferences.Compact = interface.Compact
    end

    self.InterfacePreferences = preferences
    self.InterfaceNeedsSave = not (
        (type(defaults) == "table" and type(preferences.UiSize) == "string")
        and type(preferences.Compact) == "boolean"
    )
end

function SettingsPersistence:_LoadHopSession(legacySession)
    self.HopSession = validateHopSession(legacySession)
    if not self.Storage or not self.HopPath then
        return
    end

    local fileExists
    if type(self.Storage.Exists) == "function" then
        local existsOk, exists = pcall(self.Storage.Exists, self.HopPath)
        if existsOk and type(exists) == "boolean" then
            fileExists = exists
        end
    end
    if fileExists == false then
        return
    end

    local readOk, content = pcall(self.Storage.Read, self.HopPath)
    if not readOk or type(content) ~= "string" or content == "" then
        if fileExists == true then
            self.HopSession = nil
        end
        return
    end

    local decodeOk, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(content)
    end)
    if decodeOk and type(data) == "table" then
        self.HopSession = validateHopSession(data)
    else
        self.HopSession = nil
    end
end

function SettingsPersistence:Load()
    if not self.Storage or not self.Path then
        self.LastSnapshot = self:_Capture()
        return false, self.LoadWarning
    end

    local fileExists
    if type(self.Storage.Exists) == "function" then
        local existsOk, exists = pcall(self.Storage.Exists, self.Path)
        if existsOk and type(exists) == "boolean" then
            fileExists = exists
        end
    end

    if fileExists == false then
        self:_LoadHopSession(nil)
        self:_LoadSharedInterface(nil)
        self.LastSnapshot = self:_Capture()
        return true
    end

    local readOk, content = pcall(self.Storage.Read, self.Path)
    if not readOk or type(content) ~= "string" or content == "" then
        self:_LoadHopSession(nil)
        self:_LoadSharedInterface(nil)
        self.LastSnapshot = self:_Capture()
        if fileExists == true then
            self.LoadWarning = "Saved settings could not be read; defaults are active."
        end
        return true
    end

    local decodeOk, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(content)
    end)
    if not decodeOk or type(data) ~= "table" then
        self:_LoadHopSession(nil)
        self:_LoadSharedInterface(nil)
        self.LoadWarning = "Saved settings are invalid; defaults are active."
        self.LastSnapshot = self:_Capture()
        return true
    end

    local version = tonumber(data.SchemaVersion) or 0
    if version > SCHEMA_VERSION then
        self.ReadOnly = true
        self.LoadWarning = "Saved settings are newer than this hub; auto-save is paused."
        self:_LoadSharedInterface(nil)
        self.LastSnapshot = self:_Capture()
        return true
    end

    self:_ApplySavedSettings(data)
    self:_LoadSharedInterface(self.InterfacePreferences)
    self:_LoadHopSession(data.HopSession)
    self.LoadedFromFile = true
    self.LastSnapshot = self:_Capture()
    return true
end

function SettingsPersistence:_ReportSaveError(message)
    local now = os.clock()
    if self.LastSaveWarningAt > 0 and now - self.LastSaveWarningAt < 30 then
        return
    end
    self.LastSaveWarningAt = now
    self.LoadWarning = "Settings auto-save failed; changes may not persist."
    if self.State then
        self.State:SetStatus(self.LoadWarning, "warning")
    end
end

function SettingsPersistence:Save(force)
    if self.Destroyed or self.ReadOnly then
        return false, "Settings persistence is paused"
    end
    if not self.Storage or not self.Path then
        return false, self.LoadWarning or "Local settings storage is unavailable"
    end

    local snapshot = self:_Capture()
    local previousSnapshot = self.LastSnapshot
    local settingsChanged = force
        or not previousSnapshot
        or not deepEqual(snapshot.Settings, previousSnapshot.Settings)
    local interfaceChanged = force
        or self.InterfaceNeedsSave
        or not previousSnapshot
        or not deepEqual(snapshot.Interface, previousSnapshot.Interface)
    if not settingsChanged and not interfaceChanged then
        return true
    end

    if settingsChanged then
        local settingsDocument = {
            SchemaVersion = SCHEMA_VERSION,
            Settings = snapshot.Settings,
        }
        local encodeOk, content = pcall(function()
            return game:GetService("HttpService"):JSONEncode(settingsDocument)
        end)
        if not encodeOk or type(content) ~= "string" then
            self:_ReportSaveError("Could not encode settings")
            return false, tostring(content)
        end

        local writeOk, writeResult, writeError = pcall(
            self.Storage.Write,
            self.Path,
            content
        )
        if not writeOk or writeResult ~= true then
            local err = writeOk and writeError or writeResult
            self:_ReportSaveError(err)
            return false, tostring(err or "Local settings file could not be written")
        end
    end

    if interfaceChanged then
        if not self.InterfacePath then
            self:_ReportSaveError("Shared UI settings path is unavailable")
            return false, "Shared UI settings path is unavailable"
        end
        local interfaceDocument = {
            SchemaVersion = 1,
            Interface = snapshot.Interface,
        }
        local encodeOk, content = pcall(function()
            return game:GetService("HttpService"):JSONEncode(interfaceDocument)
        end)
        if not encodeOk or type(content) ~= "string" then
            self:_ReportSaveError("Could not encode shared UI settings")
            return false, tostring(content)
        end

        local writeOk, writeResult, writeError = pcall(
            self.Storage.Write,
            self.InterfacePath,
            content
        )
        if not writeOk or writeResult ~= true then
            local err = writeOk and writeError or writeResult
            self:_ReportSaveError(err)
            return false, tostring(err or "Shared UI settings could not be written")
        end
    end

    self.LastSnapshot = snapshot
    self.InterfaceNeedsSave = false
    self.LoadWarning = nil
    return true
end

function SettingsPersistence:CanPersistHopSession()
    return not self.Destroyed
        and not self.ReadOnly
        and self.Storage ~= nil
        and self.HopPath ~= nil
end

function SettingsPersistence:GetHopSession()
    return copyTable(self.HopSession)
end

function SettingsPersistence:SetHopSession(session)
    if not self:CanPersistHopSession() then
        return false, self.LoadWarning or "Local settings storage is unavailable"
    end
    local validated = validateHopSession(session)
    if not validated then
        return false, "Hop session data is invalid or expired"
    end
    self.HopSession = validated
    local encodeOk, content = pcall(function()
        return game:GetService("HttpService"):JSONEncode(validated)
    end)
    if not encodeOk or type(content) ~= "string" then
        return false, "Hop session could not be encoded"
    end
    local writeOk, written, writeError = pcall(
        self.Storage.Write,
        self.HopPath,
        content
    )
    if not writeOk or written ~= true then
        return false, tostring(writeError or written or "Hop session could not be saved")
    end
    return true
end

function SettingsPersistence:ClearHopSession()
    if not self:CanPersistHopSession() then
        self.HopSession = nil
        return false, self.LoadWarning or "Local settings storage is unavailable"
    end
    self.HopSession = nil
    local writeOk, written, writeError = pcall(
        self.Storage.Write,
        self.HopPath,
        "{}"
    )
    if not writeOk or written ~= true then
        return false, tostring(writeError or written or "Hop session could not be cleared")
    end
    return true
end

function SettingsPersistence:ScheduleSave()
    if self.Destroyed or self.ReadOnly or not self.Storage then
        return false
    end
    local snapshot = self:_Capture()
    if self.LastSnapshot and deepEqual(snapshot, self.LastSnapshot) then
        return true
    end

    self.SaveGeneration += 1
    local generation = self.SaveGeneration
    task.delay(SAVE_DEBOUNCE_SECONDS, function()
        if self.Destroyed or generation ~= self.SaveGeneration then
            return
        end
        self:Save()
    end)
    return true
end

function SettingsPersistence:Flush()
    self.SaveGeneration += 1
    if self.Destroyed or self.ReadOnly or not self.Storage then
        return false, self.LoadWarning or "Local settings storage is unavailable"
    end
    return self:Save()
end

function SettingsPersistence:GetStartupWarning()
    return self.LoadWarning
end

function SettingsPersistence:Destroy()
    self.SaveGeneration += 1
    self.Destroyed = true
end

return SettingsPersistence
