from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CUSTOM_HUB = ROOT / "src/ReplicatedStorage/CustomHub"

CONFIG = (CUSTOM_HUB / "Config.lua").read_text(encoding="utf-8")
UI = (CUSTOM_HUB / "UI.lua").read_text(encoding="utf-8")
HUB = (CUSTOM_HUB / "init.lua").read_text(encoding="utf-8")
MANAGER = (CUSTOM_HUB / "FeatureManager.lua").read_text(encoding="utf-8")
MAIN_FARM = (CUSTOM_HUB / "Features/MainFarm.lua").read_text(encoding="utf-8")
MOVEMENT = (CUSTOM_HUB / "Features/Farm/MovementService.lua").read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def function_body(source, signature, next_signature):
    start = source.index(signature)
    end = source.index(next_signature, start)
    return source[start:end]


farm_config = CONFIG[CONFIG.index("Farm = {"):CONFIG.index("Player = {")]
require('Kind = "featureToggle"' in farm_config,
        "Farm page must expose Main Farm as an actual feature toggle")
require('Label = "Start Farm"' in farm_config,
        "Farm toggle must be labelled Start Farm for the selected method")
require('Action = "farm.main"' in farm_config,
        "Farm toggle must use MainFarm's registered action")
require('Label = "Farm method"' in farm_config
        and 'Action = "farm.mode.select"' in farm_config
        and 'Setting = "FarmMode"' in farm_config
        and 'Options = farmModes' in farm_config
        and 'local farmModes = { "Level Farm", "Aura Farm" }' in CONFIG,
        "Farm page must offer only the implemented Level and Aura modes")
require('Kind = "settingSlider"' in farm_config
        and 'Label = "Aura distance"' in farm_config
        and 'Action = "farm.auraDistance.set"' in farm_config
        and 'Setting = "AuraDistance"' in farm_config,
        "Farm page must expose Aura Farm's radius setting")
require(
    'Kind = "button"' in farm_config
    and 'Label = "Copy status report"' in farm_config
    and 'Action = "farm.status.copy"' in farm_config,
    "Farm page must expose a button for copying the complete status report",
)
require('Kind = "settingDropdown"' in farm_config
        and 'Action = "farm.weaponCategory.select"' in farm_config
        and 'Setting = "WeaponCategory"' in farm_config
        and "Options = weaponCategories" in farm_config,
        "Farm page must expose weapon categories through a dropdown")
require('local weaponCategories = { "Melee", "Sword", "Blox Fruit" }' in CONFIG
        and "WeaponCategories = weaponCategories" in CONFIG,
        "Weapon selector must use the supported category choices")

activate = function_body(UI, "function UI:_ActivateControl(control)", "\nfunction UI:_AddControl")
require("snapshot.featureEnabled[control.Action] ~= true" in activate,
        "Feature toggle must derive its next value from the actual state snapshot")
require("self.Dispatch(control.Action," in activate,
        "UI activation must dispatch the configured action")
require("row.Activated" in UI and "pcall(self._ActivateControl, self, control)" in UI,
        "The visible Farm row must route taps into the UI activation handler")
refresh = function_body(UI, "function UI:_Refresh(snapshot)", "\nfunction UI:_ClearPage")
require("snapshot.featureEnabled[entry.Control.Action] == true" in refresh,
        "UI toggle indicator must reflect MainFarm's actual enabled state")
require('entry.Label.Text = enabled and "ON" or "OFF"' in refresh,
        "UI must show the resulting enabled state")
require("self.SelectorEntries" in refresh
        and "farmSettings[entry.Setting]" in refresh
        and "option.Button.BackgroundColor3" in refresh,
        "UI must show the selected value using the shared setting")

require("self.FeatureManager:Dispatch(actionId, payload)" in HUB,
        "Hub must route UI actions to FeatureManager")
require("Modules = { MainFarm, PlaceholderFeatures }" in MANAGER,
        "FeatureManager must own the existing MainFarm module")
dispatch = function_body(MANAGER, "function FeatureManager:Dispatch", "\nfunction FeatureManager:Cleanup")
require('actionId == "farm.weaponCategory.select"' in dispatch
        and "category == payload" in dispatch
        and "farmSettings.WeaponCategory = selectedCategory" in dispatch
        and '"Weapon category: " .. tostring(farmSettings.WeaponCategory)' in dispatch,
        "Direct category selection must update the config read by MainFarm")
require('Name = "Option_" .. tostring(value)' in UI
        and "self.Dispatch,\n                        control.Action,\n                        value" in UI,
        "Each weapon option must dispatch its selected value immediately")
require('Name = "DropdownValue"' in UI
        and 'Name = "DropdownMenu"' in UI
        and "function UI:_OpenDropdown(entry)" in UI
        and "pcall(self.Dispatch, entry.Control.Action, value)" in UI
        and 'Kind = "dropdown"' in UI,
        "Weapon category dropdown must open choices and dispatch the selected category")
require('control.Kind == "settingSlider"' in UI
        and 'function UI:_UpdateSliderFromX(entry, positionX)' in UI
        and 'self:_UpdateSliderFromX(activeSlider.Entry, input.Position.X)' in UI
        and 'entry.PendingValue' in UI
        and 'track.InputBegan' in UI,
        "Aura distance slider must support touch/mouse drag and dispatch its selected value")
dropdown_open = function_body(UI, "function UI:_OpenDropdown(entry)", "\nfunction UI:_ToggleDropdown")
dropdown_close = function_body(UI, "function UI:_CloseDropdown()", "\nfunction UI:_OpenDropdown")
clear_page = function_body(UI, "function UI:_ClearPage()", "\nfunction UI:_SyncControlGridHeight")
require("DropdownDismissOverlay" in dropdown_open
        and "overlay.Activated" in dropdown_open
        and "optionButton.Activated" in dropdown_open
        and "instance:Destroy()" in dropdown_close
        and "self:_CloseDropdown()" in clear_page,
        "dropdown dismissal, option selection, and page cleanup must close the popup")
require("for _, featureModule in ipairs(self.Modules) do" in dispatch
        and "featureModule.Handle" in dispatch,
        "FeatureManager must dispatch the action to the registered feature modules")

handle = function_body(MAIN_FARM, "function MainFarm:Handle", "\nfunction MainFarm:Cleanup")
require('if actionId ~= "farm.main" then' in handle,
        "MainFarm must handle the Farm page's configured action")
require('if actionId == "farm.status.copy" then' in handle
        and "self:CopyStatusReport()" in handle,
        "the copy-report action must not toggle or restart Main Farm")
copy_report = function_body(
    MAIN_FARM,
    "function MainFarm:CopyStatusReport",
    "\nfunction MainFarm:_PrintSpawnDiagnosticReport",
)
require("self.LastQuestDiagnosticReportText" in copy_report
        and "setclipboard(text)" in copy_report
        and "Complete quest status report copied to clipboard." in copy_report
        and "complete report printed to output" in copy_report,
        "the copy action must reuse the complete cached report and handle clipboard unavailability")
require("self:Start()" in handle and "self:Stop()" in handle,
        "The Main Farm toggle must start and stop the existing MainFarm instance")
start = function_body(MAIN_FARM, "function MainFarm:Start()", "\nfunction MainFarm:Stop")
stop = function_body(MAIN_FARM, "function MainFarm:Stop()", "\nfunction MainFarm:Handle")
require("if self.Running then" in start and "return true" in start,
        "Repeated enable actions must not start duplicate MainFarm workers")
require("task.spawn(self._Run, self, session)" in start,
        "MainFarm must start its existing single worker")
require("self.Running = false" in stop
        and "SetFarmCollisionSuppression(false)" in stop
        and 'SetFeatureEnabled("farm.main", false)' in stop,
        "Stopping MainFarm must invalidate its worker and run existing cleanup")
require('SetFeatureEnabled("farm.main", true)' in start,
        "MainFarm start must update the UI's enabled-state source")
require('actionId == "farm.mode.select"' in handle
        and 'farmSettings.FarmMode = selectedMode' in handle
        and 'actionId == "farm.auraDistance.set"' in handle
        and 'farmSettings.AuraDistance = math.min(selectedDistance, maximum)' in handle,
        "MainFarm must validate and apply the selected mode and Aura radius settings")
collision = function_body(
    MOVEMENT,
    "function MovementService:SetFarmCollisionSuppression(enabled)",
    "\nfunction MovementService:_Finish",
)
require("self.FarmCollisionActive" in collision
        and "self.FarmCollisionConnection.Connected" in collision,
        "Repeated collision enable must reuse the existing maintenance connection")
require(collision.count("Heartbeat:Connect") == 1
        and "connection:Disconnect()" in collision
        and "self:_RestoreFarmCollision()" in collision,
        "Farm collision maintenance must use one connection and restore it on stop")

require("farmSettings.WeaponCategory" in MAIN_FARM
        and "farmSettings.AttackNoAnimation" in MAIN_FARM
        and "self.CombatService:EquipWeapon(weaponCategory)" in MAIN_FARM,
        "MainFarm must read the shared FarmSettings configuration")
require("self.QuestService:GetActiveQuestState()" in MAIN_FARM
        and "self.QuestService:SelectLevelQuest()" in MAIN_FARM,
        "MainFarm must use the existing quest state and quest selection service")
level_step = function_body(
    MAIN_FARM,
    "function MainFarm:_Step(session)",
    "\nfunction MainFarm:_Run(session)",
)
require('if farmMode == "Aura Farm" then' in level_step
        and level_step.index('if farmMode == "Aura Farm" then')
        < level_step.index("self.QuestService:GetActiveQuestState()"),
        "Aura Farm must route before quest reading and leave Level Farm's quest path intact")

print("PASS: Farm UI activation dispatches to the existing MainFarm feature")
print("PASS: toggle state reflects MainFarm start/stop and repeated enable is guarded")
print("PASS: weapon-category options select values directly and update shared config")
print("PASS: quest and farm settings are read by the existing feature/services")
