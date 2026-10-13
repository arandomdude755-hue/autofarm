from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HUB = ROOT / "src/ReplicatedStorage/CustomHub"
CONFIG = (HUB / "Config.lua").read_text(encoding="utf-8")
QUEST_SERVICE = (HUB / "Features/Farm/QuestService.lua").read_text(encoding="utf-8")
ENEMY = (HUB / "Features/Farm/EnemyService.lua").read_text(encoding="utf-8")
MAIN_FARM = (HUB / "Features/MainFarm.lua").read_text(encoding="utf-8")
COMPATIBILITY = (HUB / "Compatibility.lua").read_text(encoding="utf-8")
COMBAT = (HUB / "Features/Farm/CombatService.lua").read_text(encoding="utf-8")
UI = (HUB / "UI.lua").read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def function_body(source, signature, next_signature):
    start = source.index(signature)
    end = source.index(next_signature, start)
    return source[start:end]


require(
    '"Farm Bones"' in CONFIG
    and '"Farm Cake Prince"' in CONFIG
    and '"Farm Tyrant of the Skies"' in CONFIG,
    "The BNN Bone, Cake Prince, and Tyrant farming modes must be available",
)
require(
    'Sea = "Third Sea"' in CONFIG
    and 'QuestPrefix = "HauntedQuest"' in CONFIG
    and 'QuestPrefix = "CakeQuest"' in CONFIG
    and 'QuestPrefix = "TikiQuest"' in CONFIG,
    "Mode profiles must identify their source quest families and seas",
)
bones_profile = CONFIG[
    CONFIG.index('["Farm Bones"] = {'):
    CONFIG.index('["Farm Cake Prince"] = {')
]
require(
    'Sea = "Third Sea"' in bones_profile
    and 'QuestName = "HauntedQuest2"' in bones_profile,
    "Farm Bones must run in Third Sea for its Haunted quest",
)
require(
    "AutoModeQuest = false" in CONFIG
    and "IgnoreCakePrince = false" in CONFIG
    and 'Label = "Auto quest for modes"' in CONFIG
    and 'Setting = "AutoModeQuest"' in CONFIG,
    "Mode quest acceptance must be an opt-in setting",
)
require(
    'IgnoreBossSetting = "IgnoreCakePrince"' in CONFIG
    and "farmSettings[profile.IgnoreBossSetting] == true" in MAIN_FARM
    and 'actionId == "farm.ignoreCakePrince"' in MAIN_FARM,
    "Cake Prince boss skipping must be a functional setting rather than a placeholder",
)
require(
    "TikiEventPhase = true" in CONFIG
    and "EventPhaseNotMigrated" not in CONFIG
    and "Hop Find Katakuri" not in CONFIG
    and "SpecialHop" not in MAIN_FARM
    and "__ServerBrowser" not in MAIN_FARM
    and "TikiSkill_" not in CONFIG
    and 'Action = "farm.skills.enabled"' in CONFIG
    and "UseFarmSkills = false" in CONFIG,
    "regular farming skills must be opt-in and Tiki must not expose puzzle-only skill settings",
)

targets = function_body(
    QUEST_SERVICE,
    "function QuestService:GetQuestTargets",
    "\nfunction QuestService:SelectQuest",
)
require(
    "GuideModule.Data.NPCList" in targets
    and "npcEntry.InternalQuestName" in targets
    and "npcEntry.Levels" in targets
    and "quest.Task" in targets
    and "questName:sub(1, #prefix) == prefix" in targets,
    "Mode targets must be derived dynamically from eligible quest-catalog tasks",
)

select_quest = function_body(
    QUEST_SERVICE,
    "function QuestService:SelectQuest",
    "\nfunction QuestService:RequestStart",
)
require(
    "self:GetPlayerLevel()" in select_quest
    and "minimumLevel" in select_quest
    and "npcEntry.InternalQuestName == questName" in select_quest
    and "tostring(listedQuestId) == tostring(questId)" in select_quest
    and "Pos = npcEntry.Position" in select_quest,
    "Auto quest must use a level-eligible quest and its live catalog quest giver",
)

second_sea = function_body(
    COMPATIBILITY,
    "function Compatibility:IsSecondSea",
    "\nreturn Compatibility",
)
require(
    'mapName == "Sea2"' in second_sea
    and "4442272183" in second_sea
    and "79091703265657" in second_sea,
    "Second Sea must be recognized without enabling cross-sea travel",
)

mode_step = function_body(
    MAIN_FARM,
    "function MainFarm:_StepBossEventMode",
    "\nfunction MainFarm:_Step(session)",
)
require(
    "profile.Sea" in mode_step
    and "profile.MinimumLevel" in mode_step
    and "switch seas manually" in mode_step
    and "self.QuestService:GetQuestTargets(profile.QuestPrefix, level)" in mode_step,
    "Mode execution must gate sea/level and use quest-catalog targets",
)
require(
    "self.QuestService:SelectQuest(" in mode_step
    and "self:_StepModeQuestGiver(candidate, root, session)" in mode_step
    and "self.EnemyService:FindNearest(profile.BossName, root.Position)" in mode_step,
    "Mode execution must use validated quest acceptance and live boss detection",
)
require(
    "self:_FindModeSpawn(targetNames, root.Position)" in mode_step
    and "self.EnemyService:IsSpawnAvailable" in mode_step
    and "self.EnemyService:MarkSpawnIgnored" in mode_step,
    "Mode targets must use existing spawn availability and retry handling",
)
require(
    mode_step.index("local bossTarget = nil")
    < mode_step.index("if bossTarget then")
    < mode_step.index("self:_StepTikiEventPhase(root, session)")
    < mode_step.index("local targetNames, targetError")
    and "self.NextTikiBossSearchAt = now + NPC_SCAN_INTERVAL" in mode_step
    and "self.TikiEventComplete = true" in mode_step
    and "self:_EngageModeTarget(bossTarget, true, root, session)" in mode_step,
    "Tiki must find and engage its live boss before optional quest-catalog or puzzle-phase handling",
)
event_refresh = function_body(
    MAIN_FARM,
    "function MainFarm:_RefreshTikiEventState",
    "\nfunction MainFarm:_StepTikiEventPhase",
)
require(
    "TIKI_EVENT_SCAN_INTERVAL" in MAIN_FARM
    and "for index = 1, 4 do" in event_refresh
    and 'FindFirstChild("Eye" .. tostring(index), true)' in event_refresh
    and "eye.Transparency ~= 0" in event_refresh
    and 'FindFirstChild("EagleBossArena", true)' in event_refresh
    and 'eventObject.Name == "Tree"' in event_refresh
    and 'GetAttribute("AlreadyDestroyedClient") ~= true' in event_refresh
    and "arena:GetChildren()" in event_refresh
    and "GetDescendants" not in event_refresh,
    "Tiki event discovery must use the four visible eyes and bounded direct arena children",
)
event_step = function_body(
    MAIN_FARM,
    "function MainFarm:_StepTikiEventPhase",
    "\nfunction MainFarm:_StepBossEventMode",
)
require(
    "self:_MoveTo(" in event_step
    and "self:_HoldPosition(session)" in event_step
    and "self:_UseTikiPuzzleAction(" in event_step
    and "self:_RestoreTikiFarmWeapon()" in event_step
    and "activate it manually" not in event_step,
    "Tiki object tracking must run puzzle actions in-range and restore Farm Weapon after the phase",
)
event_action = function_body(
    MAIN_FARM,
    "function MainFarm:_UseTikiPuzzleAction",
    "\nfunction MainFarm:_StepTikiEventPhase",
)
require(
    "HasOwnedInventoryItem(\"Skull Guitar\")" in event_action
    and 'InvokeServer("LoadItem", "Skull Guitar")' in event_action
    and "TapSkullGuitar(targetPosition)" in event_action
    and "FindReadyTikiSkill()" in event_action
    and "UseSkill(" in event_action
    and "Tiki puzzle waiting for any ready skill" in event_action
    and 'ownershipError = "Skull Guitar is reloading"' in event_action
    and event_action.index('ownershipError = "Skull Guitar is reloading"')
        < event_action.index("FindReadyTikiSkill()")
    and '"Buy"' not in event_action
    and "ServerHop" not in event_action
    and "self.TikiPuzzleActive = true" in event_step,
    "Tiki automation must use owned Skull Guitar or selected skills only while the puzzle is active",
)
skull_tap = function_body(
    COMBAT,
    "function CombatService:TapSkullGuitar",
    "\nfunction CombatService:_FindBladeHitParts",
)
require(
    'FindToolByName("Skull Guitar")' in skull_tap
    and 'remote:FireServer("TAP", targetPosition)' in skull_tap
    and "IsGunReloading" in skull_tap
    and "function CombatService:UseTikiSkill" in COMBAT
    and "function CombatService:UseSkill" in COMBAT
    and "SendKeyEvent(true, keyName" in COMBAT
    and "SendKeyEvent(false, keyName" in COMBAT
    and "aimContext.Mouse.Hit = targetPart.CFrame" in COMBAT
    and "aimContext.Mouse.Target = mouseTarget" in COMBAT,
    "Puzzle attacks must target the event object, respect Skull Guitar reload, and release skill keys",
)
restore_weapon = function_body(
    MAIN_FARM,
    "function MainFarm:_RestoreTikiFarmWeapon",
    "\nfunction MainFarm:_UseTikiPuzzleAction",
)
require(
    "farmSettings.WeaponCategory" in restore_weapon
    and "self.CombatService:EquipWeapon(category)" in restore_weapon
    and "TikiPuzzleRestorePending" in MAIN_FARM,
    "Leaving the event must restore the current Farm Weapon category before normal farming resumes",
)
mode_spawn = function_body(
    MAIN_FARM,
    "function MainFarm:_FindModeSpawn",
    "\nfunction MainFarm:_EngageModeTarget",
)
require(
    "FindSpawn(targetNames, origin)" in mode_spawn
    and "diagnostic.MatchedTarget" in ENEMY
    and "normalizeTargetNames(targetName)" in ENEMY,
    "Mode spawn discovery must search its catalog target set in one scan",
)

step = function_body(
    MAIN_FARM,
    "function MainFarm:_Step(session)",
    "\nfunction MainFarm:_Run(session)",
)
require(
    "farmModeProfile" in step
    and step.index("if farmModeProfile then") < step.index('if questState == "unknown" then')
    and "readerEvidence" in step,
    "Special modes must remain separate from Level Farm's unknown-quest rejection path",
)

require(
    "farmSettings[settingName] == true" in UI
    and "currentValue = farmSettings[control.Setting] == true" in UI,
    "The auto-quest toggle must display and toggle its configured setting",
)

print("PASS: Bone, Cake Prince, and Tiki modes are configured with sea and level gates")
print("PASS: quest target names and quest giver data come from live quest catalogs")
print("PASS: special modes use validated quest acceptance and existing spawn availability")
print("PASS: Tiki event actions are ownership-gated and scoped to the puzzle phase")
print("PASS: unverified server hopping remains unavailable")
