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
require('Action = "farm.main"' in farm_config,
        "Farm toggle must use MainFarm's registered action")
require('Kind = "settingCycle"' in farm_config
        and 'Action = "farm.weaponCategory.cycle"' in farm_config
        and 'Setting = "WeaponCategory"' in farm_config,
        "Farm page must expose the configured weapon-category selector")
require('WeaponCategories = { "Melee", "Sword", "Blox Fruit" }' in CONFIG,
        "Weapon selector must use the supported category choices")

activate = function_body(UI, "function UI:_ActivateControl(control)", "\nfunction UI:_AddControl")
require("snapshot.featureEnabled[control.Action] ~= true" in activate,
        "Feature toggle must derive its next value from the actual state snapshot")
require("self.Dispatch(control.Action," in activate,
        "UI activation must dispatch the configured action")
require("row.Activated" in UI and "self:_ActivateControl(control)" in UI,
        "The visible Farm row must route taps into the UI activation handler")
refresh = function_body(UI, "function UI:_Refresh(snapshot)", "\nfunction UI:_ClearPage")
require("snapshot.featureEnabled[entry.Control.Action] == true" in refresh,
        "UI toggle indicator must reflect MainFarm's actual enabled state")
require('entry.Label.Text = enabled and "ON" or "OFF"' in refresh,
        "UI must show the resulting enabled state")
require('self.Config.FarmSettings or {}' in refresh
        and 'entry.Control.Setting' in refresh,
        "UI must display the current shared setting-cycle value")

require("self.FeatureManager:Dispatch(actionId, payload)" in HUB,
        "Hub must route UI actions to FeatureManager")
require("Modules = { MainFarm, PlaceholderFeatures }" in MANAGER,
        "FeatureManager must own the existing MainFarm module")
dispatch = function_body(MANAGER, "function FeatureManager:Dispatch", "\nfunction FeatureManager:Cleanup")
require('actionId == "farm.weaponCategory.cycle"' in dispatch
        and "farmSettings.WeaponCategory = categories[nextIndex]" in dispatch
        and '"Weapon category: " .. tostring(farmSettings.WeaponCategory)' in dispatch,
        "Weapon-category action must update the same config read by MainFarm")
require("for _, featureModule in ipairs(self.Modules) do" in dispatch
        and "featureModule.Handle" in dispatch,
        "FeatureManager must dispatch the action to the registered feature modules")

handle = function_body(MAIN_FARM, "function MainFarm:Handle", "\nfunction MainFarm:Cleanup")
require('if actionId ~= "farm.main" then' in handle,
        "MainFarm must handle the Farm page's configured action")
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
        and "farmSettings.AttackNoAnimation" in MAIN_FARM,
        "MainFarm must read the shared FarmSettings configuration")
require("self.QuestService:GetActiveQuestState()" in MAIN_FARM
        and "self.QuestService:SelectLevelQuest()" in MAIN_FARM,
        "MainFarm must use the existing quest state and quest selection service")

print("PASS: Farm UI activation dispatches to the existing MainFarm feature")
print("PASS: toggle state reflects MainFarm start/stop and repeated enable is guarded")
print("PASS: quest and farm settings are read by the existing feature/services")
