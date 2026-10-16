local PlaceholderFeatures = require(script.Features.PlaceholderFeatures)
local MainFarm = require(script.Features.MainFarm)
local TeleportFeature = require(script.Features.TeleportFeature)
local StatusFeature = require(script.Features.StatusFeature)
local MovementService = require(script.Features.Farm.MovementService)

local FeatureManager = {}
FeatureManager.__index = FeatureManager

function FeatureManager.new(state, compatibility, config, settingsPersistence)
    local movementService = MovementService.new(compatibility, function(message, kind)
        state:SetStatus(message, kind or "info")
    end)
    return setmetatable({
        State = state,
        Modules = { MainFarm, TeleportFeature, StatusFeature, PlaceholderFeatures },
        InitializedModules = {},
        Context = {
            State = state,
            Compatibility = compatibility,
            Config = config,
            SettingsPersistence = settingsPersistence,
            MovementService = movementService,
            MainFarm = MainFarm,
            TeleportFeature = TeleportFeature,
        },
    }, FeatureManager)
end

function FeatureManager:_ScheduleSettingsSave()
    local persistence = self.Context and self.Context.SettingsPersistence
    if persistence then
        persistence:ScheduleSave()
    end
end

function FeatureManager:Initialize()
    for _, featureModule in ipairs(self.Modules) do
        local ok, result = pcall(featureModule.Initialize, featureModule, self.Context)
        if not ok or result == false then
            local message = not ok and result or "Feature module initialization declined"
            self.State:SetStatus("Feature initialization error: " .. tostring(message), "error")
            self:Cleanup()
            return false, tostring(message)
        end
        table.insert(self.InitializedModules, featureModule)
    end
    return true
end

function FeatureManager:Dispatch(actionId, payload)
    if actionId == "settings.uiSize.select" then
        local layout = self.Context.Config and self.Context.Config.Layout
        local footprints = layout and layout.UiSizeFootprints
        if type(footprints) ~= "table"
            or type(payload) ~= "string"
            or type(footprints[payload]) ~= "number" then
            self.State:SetStatus("UI size setting is unavailable.", "error")
            return false, "Unsupported UI size"
        end
        self.State:SetUiSize(payload)
        self:_ScheduleSettingsSave()
        self.State:SetStatus("UI size: " .. payload .. ".", "success")
        return true
    end

    if actionId == "settings.compact" then
        self.State:SetCompact(payload == true)
        self:_ScheduleSettingsSave()
        self.State:SetStatus(
            "Compact layout " .. (payload and "enabled." or "disabled.") .. " (UI only).",
            "success"
        )
        return true
    end

    if actionId == "settings.reset" then
        self.State:ResetPresentation()
        self:_ScheduleSettingsSave()
        return true
    end

    if actionId == "farm.weaponCategory.select" then
        local farmSettings = self.Context.Config and self.Context.Config.FarmSettings
        local categories = farmSettings and farmSettings.WeaponCategories
        local selectedCategory
        if type(categories) == "table" and type(payload) == "string" then
            for _, category in ipairs(categories) do
                if category == payload then
                    selectedCategory = category
                    break
                end
            end
        end
        if not selectedCategory then
            self.State:SetStatus("Weapon category settings are unavailable.", "error")
            return false, "Unsupported weapon category"
        end

        farmSettings.WeaponCategory = selectedCategory
        self:_ScheduleSettingsSave()
        self.State:SetStatus(
            "Farm weapon: " .. tostring(farmSettings.WeaponCategory),
            "success"
        )
        return true
    end

    for _, featureModule in ipairs(self.Modules) do
        local ok, handled = pcall(
            featureModule.Handle,
            featureModule,
            actionId,
            payload,
            self.Context
        )
        if not ok then
            self.State:SetStatus("Action error: " .. tostring(handled), "error")
            return false, tostring(handled)
        end
        if handled then
            self:_ScheduleSettingsSave()
            return true
        end
    end

    local message = "No UI-shell action registered for " .. tostring(actionId)
    self.State:SetStatus(message, "error")
    return false, message
end

function FeatureManager:Cleanup()
    for index = #self.InitializedModules, 1, -1 do
        local featureModule = self.InitializedModules[index]
        local ok, err = pcall(featureModule.Cleanup, featureModule, self.Context)
        if not ok then
            self.State:SetStatus("Feature cleanup error: " .. tostring(err), "error")
        end
        self.InitializedModules[index] = nil
    end
end

return FeatureManager
