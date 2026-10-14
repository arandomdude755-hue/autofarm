from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CUSTOM_HUB = ROOT / "src/ReplicatedStorage/CustomHub"

CONFIG = (CUSTOM_HUB / "Config.lua").read_text(encoding="utf-8")
UI = (CUSTOM_HUB / "UI.lua").read_text(encoding="utf-8")
HUB = (CUSTOM_HUB / "init.lua").read_text(encoding="utf-8")
MANAGER = (CUSTOM_HUB / "FeatureManager.lua").read_text(encoding="utf-8")
MAIN_FARM = (CUSTOM_HUB / "Features/MainFarm.lua").read_text(encoding="utf-8")
ENEMY = (CUSTOM_HUB / "Features/Farm/EnemyService.lua").read_text(encoding="utf-8")
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
        and '"Farm Bones"' in CONFIG
        and '"Farm Cake Prince"' in CONFIG
        and '"Farm Tyrant of the Skies"' in CONFIG
        and '"Farm Materials"' not in CONFIG[CONFIG.index("local farmModes = {"):CONFIG.index("local farmMaterialTargets = {")]
        and 'Label = "Farm Materials"' in farm_config
        and 'Action = "farm.material.enabled"' in farm_config,
        "Farm Materials must be a separate priority toggle, not a Farm method")
require('Label = "Auto quest for modes"' in farm_config
        and 'Action = "farm.autoModeQuest"' in farm_config
        and 'Setting = "AutoModeQuest"' in farm_config
        and "AutoModeQuest = false" in CONFIG
        and 'Label = "Ignore Cake Prince boss"' in farm_config
        and 'Action = "farm.ignoreCakePrince"' in farm_config
        and 'Setting = "IgnoreCakePrince"' in farm_config,
        "Special modes must expose an opt-in auto-quest setting that defaults off")
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
pages_start = CONFIG.index("Pages = {")
settings_start = CONFIG.index("        Settings = {", pages_start)
farm_settings_start = CONFIG.index("        FarmSettings = {", settings_start)
pages_end = CONFIG.index("\n    },\n}\n\nfor settingName", farm_settings_start)
settings_config = CONFIG[settings_start:farm_settings_start]
farm_settings_config = CONFIG[farm_settings_start:pages_end]
require('Action = "farm.weaponCategory.select"' not in farm_config
        and 'Title = "Main settings"' in settings_config
        and 'Kind = "settingDropdown"' in settings_config
        and 'Label = "UI size"' in settings_config
        and 'Label = "Farm weapon"' not in settings_config
        and 'Title = "Farm settings"' in farm_settings_config
        and 'Label = "Farm weapon"' in farm_settings_config
        and 'Action = "farm.weaponCategory.select"' in farm_settings_config
        and 'Setting = "WeaponCategory"' in farm_settings_config
        and "Options = weaponCategories" in farm_settings_config,
        "Main settings and Farm settings must be separate pages")
require('TabSubsections = {' in CONFIG
        and 'Settings = {' in CONFIG
        and '{ Label = "Main settings", Page = "Settings" }' in CONFIG
        and '{ Label = "Farm settings", Page = "FarmSettings" }' in CONFIG
        and 'Kind = "collapsibleHeader"' in CONFIG
        and 'GroupId = "farmSkillKeys"' in CONFIG
        and 'Groups = { "farmSkillKeys" }' in CONFIG
        and 'table.insert(Config.Pages.FarmSettings.Controls, control)' in CONFIG,
        "Settings routes and collapsible skill keys must use the dedicated Farm settings page")
require('function UI:_LayoutNavigation(animate)' in UI
        and 'top = top + layout.SidebarChildRowHeight + layout.SidebarRowGap' in UI
        and 'function UI:_ToggleControlGroup(groupId)' in UI
        and 'self:_SelectSubsection(tabName, subsections[1])' in UI
        and 'self.ExpandedTabs[expandedTab] = expandedTab == parentTab' in UI
        and 'row.Visible = self:_IsControlVisible(control)' in UI
        and 'self:_PlayTween(childButton, 0.14' in UI,
        "Nested settings navigation must animate and reflow without overlapping neighboring tabs")
require('Label = "Bring mobs"' in farm_settings_config
        and 'Action = "farm.settings.bringMobs"' in farm_settings_config
        and 'Setting = "BringMobs"' in farm_settings_config
        and "BringMobs = false" in CONFIG
        and 'Label = "Bring mob count"' in farm_settings_config
        and 'Action = "farm.bringMobCount.set"' in farm_settings_config
        and 'Setting = "BringMobCount"' in farm_settings_config
        and 'BringMobCount = 2' in CONFIG
        and 'Min = 2' in farm_settings_config
        and 'Max = 6' in farm_settings_config
        and 'Label = "Auto turn on Buso"' in farm_settings_config
        and 'Action = "farm.settings.autoBuso"' in farm_settings_config
        and 'Setting = "AutoBuso"' in farm_settings_config
        and "AutoBuso = false" in CONFIG
        and 'Label = "Use skills while farming"' in CONFIG
        and 'Action = "farm.skills.enabled"' in CONFIG
        and 'Setting = "UseFarmSkills"' in CONFIG
        and "UseFarmSkills = false" in CONFIG
        and 'Label = "Skill hold duration"' in CONFIG
        and 'Action = "farm.skills.holdSeconds.set"' in CONFIG
        and 'Setting = "FarmSkillHoldSeconds"' in CONFIG
        and 'Label = "Fast skill release"' in CONFIG
        and 'Action = "farm.skills.fastRelease"' in CONFIG
        and 'Action = "farm.skills." .. category.Token .. "." .. keyName' in CONFIG
        and 'Setting = settingName' in CONFIG,
        "Farm settings must expose opt-in Bring mobs and Auto Buso controls")
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
        and '"Farm weapon: " .. tostring(farmSettings.WeaponCategory)' in dispatch,
        "Farm weapon selection must update the config read by MainFarm")
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
        and "self:_BuildFarmMasteryDiagnosticReport()" in copy_report
        and "Farm Mastery diagnostic copied to clipboard." in copy_report
        and "complete report printed to output" in copy_report,
        "the copy action must include live Mastery diagnostics and handle clipboard unavailability")
mastery_report = function_body(
    MAIN_FARM,
    "function MainFarm:_BuildFarmMasteryDiagnosticReport",
    "\nfunction MainFarm:CopyStatusReport",
)
require("FarmMasteryDiagnostic" in mastery_report
        and "Preparation:" in mastery_report
        and "Skill gate:" in mastery_report
        and "FarmSkillActive" in mastery_report
        and "self.CombatService.BuildFarmSkillDiagnostic" in mastery_report
        and "self.LastStatus" in mastery_report,
        "the live Mastery report must explain preparation, current status, and CombatService GUI findings")
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
require('actionId == "farm.settings.bringMobs"' in handle
        and "farmSettings.BringMobs = payload" in handle
        and 'actionId == "farm.bringMobCount.set"' in handle
        and "farmSettings.BringMobCount = math.min(selectedCount, maximum)" in handle
        and 'actionId == "farm.settings.autoBuso"' in handle
        and "self:_SetAutoBuso(payload)" in handle
        and 'actionId == "farm.skills.enabled"' in handle
        and "farmSettings.UseFarmSkills = payload" in handle
        and 'actionId == "farm.skills.fastRelease"' in handle
        and "farmSettings.FarmSkillFastRelease = payload" in handle
        and 'actionId == "farm.skills.holdSeconds.set"' in handle
        and "farmSettings.FarmSkillHoldSeconds =" in handle
        and '"^farm%.skills%.([%w]+)%.([ZXCVF])$"' in handle,
        "MainFarm must handle both new farm settings")
auto_buso = function_body(
    MAIN_FARM,
    "function MainFarm:_SetAutoBuso",
    "\nfunction MainFarm:Initialize",
)
require('commF:InvokeServer("Buso")' in auto_buso
        and "self:_HasActiveBuso(character)" in auto_buso
        and "self.AutoBusoGeneration == generation" in auto_buso
        and "self.Context == runContext" in auto_buso
        and "task.wait(2)" in auto_buso
        and "BuyHaki" not in auto_buso,
        "Auto Buso must be throttled, stop with cleanup, and never purchase Haki")
bring_mobs = function_body(
    ENEMY,
    "function EnemyService:BringMatchingMob",
    "\nfunction EnemyService:PrepareTarget",
)
require("local normalizedName = normalizeEnemyName(target.Name)" in bring_mobs
        and "requestedCount" in bring_mobs
        and "BRING_MOB_MIN_COUNT" in bring_mobs
        and "BRING_MOB_MAX_COUNT" in bring_mobs
        and "local nearbyCount = 1" in bring_mobs
        and "self.EnemyModelsByName[normalizedName]" in bring_mobs
        and "enemy.Name == target.Name" in bring_mobs
        and "isDescendantOf(enemy, self.EnemyContainer)" in bring_mobs
        and "self:IsAlive(enemy)" in bring_mobs
        and "BRING_MOB_PLAYER_RANGE" in bring_mobs
        and "BRING_MOB_MAX_DISTANCE" in bring_mobs
        and "BRING_MOB_COOLDOWN" in bring_mobs
        and "BRING_MOB_MAX_MOVES_PER_CALL" in bring_mobs
        and "CFrame.new(3 + (index - 1) * 2, 0, 0)" in bring_mobs
        and "GetDescendants" not in bring_mobs,
        "Bring mobs must use the configured 2-6 group cap, live exact-name index, distance/rate limits, and per-tick movement bound")
require(MAIN_FARM.count("self:_BringMobsIfEnabled(target, root") >= 3,
        "Bring mobs must be available across standard, Aura, and non-boss farm modes")
collision = function_body(
    MOVEMENT,
    "function MovementService:SetFarmCollisionSuppression(enabled)",
    "\nfunction MovementService:_Finish",
)
require("self.FarmCollisionActive" in collision
        and "self:_ApplyFarmCollision()" in collision,
        "Repeated collision enable must reuse the existing character/part event setup")
require("Heartbeat:Connect" not in collision
        and "CharacterAdded:Connect" in collision
        and "CharacterRemoving:Connect" in collision
        and "self:_RestoreFarmCollision()" in collision,
        "Farm collision maintenance must be event-driven and restore state on stop/respawn")

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
