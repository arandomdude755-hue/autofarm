from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HUB = ROOT / "src/ReplicatedStorage/CustomHub"
CONFIG = (HUB / "Config.lua").read_text(encoding="utf-8")
COMBAT = (HUB / "Features/Farm/CombatService.lua").read_text(encoding="utf-8")
MAIN_FARM = (HUB / "Features/MainFarm.lua").read_text(encoding="utf-8")
BNN = (ROOT / "attached_assets/3nn_main.lua_(1)_1791763089635.txt").read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def function_body(source, signature, next_signature):
    start = source.index(signature)
    end = source.index(next_signature, start)
    return source[start:end]


require(
    'local farmSkillCategories = {' in CONFIG
    and '"UseFarmSkills = false' not in CONFIG
    and "UseFarmSkills = false" in CONFIG
    and "FarmSkillHoldSeconds = 0.5" in CONFIG
    and "FarmSkillFastRelease = false" in CONFIG
    and '"FarmSkill_" .. category.Token .. "_" .. keyName' in CONFIG
    and "farmSkillDefaults[settingName] = true" in CONFIG
    and 'Action = "farm.skills.enabled"' in CONFIG
    and 'Action = "farm.skills.holdSeconds.set"' in CONFIG
    and 'Action = "farm.skills.fastRelease"' in CONFIG,
    "Farm skill controls must be opt-in, bounded by settings, and default selected keys consistently",
)
require(
    'I("Melee", { "Z", "X", "C" })' in BNN
    and 'I("Sword", { "Z", "X" })' in BNN
    and 'I("Gun", { "Z", "X" })' in BNN
    and 'I("Blox Fruit", { "Z", "X", "C", "V", "F" })' in BNN
    and 'Min = 0,' in BNN
    and 'Max = 5,' in BNN
    and '"Use skill fast dont hold"' in BNN,
    "The migrated skill categories and hold controls must match the relevant BNN source",
)

ready_skill = function_body(
    COMBAT,
    "function CombatService:_FindReadySkill",
    "\nfunction CombatService:FindReadyFarmSkill",
)
require(
    'self.Compatibility:GetPlayerGui()' in ready_skill
    and 'FindFirstChild("Skills")' in ready_skill
    and 'FindFirstChild("Cooldown")' in ready_skill
    and 'title.TextColor3 == Color3.new(1, 1, 1)' in ready_skill
    and "cooldown.Size.X.Scale == 0" in ready_skill
    and 'string.find(titleText, "Transformation", 1, true)' in ready_skill
    and "self:EquipTool(tool)" in ready_skill
    and "ignoredTools" in ready_skill
    and "GetDescendants" not in ready_skill,
    "Skill lookup must use the live skill UI, skip transformations and unavailable tools, and stay bounded",
)
farm_skill_lookup = function_body(
    COMBAT,
    "function CombatService:FindReadyFarmSkill",
    "\nfunction CombatService:FindReadyTikiSkill",
)
tiki_skill_lookup = function_body(
    COMBAT,
    "function CombatService:FindReadyTikiSkill",
    "\nfunction CombatService:UseSkill",
)
require(
    '"FarmSkill_" .. category.Token .. "_" .. keyName' in farm_skill_lookup
    and "return self:_FindReadySkill(function()" in tiki_skill_lookup
    and "farmSettings" not in tiki_skill_lookup,
    "Regular combat must honor skill selection while Tiki automatically accepts any ready skill",
)

use_skill = function_body(
    COMBAT,
    "function CombatService:UseSkill",
    "\nfunction CombatService:UseTikiSkill",
)
require(
    "SendKeyEvent(true, keyName" in use_skill
    and "SendKeyEvent(false, keyName" in use_skill
    and "mouse.Hit = targetPart.CFrame" in use_skill
    and "mouse.Target = targetPart" in use_skill
    and "holdSeconds) or 0.5, 0.05, 5" in use_skill
    and "shouldContinue()" in use_skill,
    "Skill use must aim only at the selected target, honor hold settings, and always release on cancellation",
)

attack_position = function_body(
    MAIN_FARM,
    "function MainFarm:_IsAtFarmAttackPosition",
    "\nfunction MainFarm:_TryStartFarmSkill",
)
require(
    "FARM_SKILL_ATTACK_POSITION_TOLERANCE" in attack_position
    and 'CFrame.new(-7, 20, 0)' in attack_position
    and 'CFrame.new(7, 20, 0)' in attack_position
    and "movement.Holding ~= true" in attack_position
    and "movement.Goal.Position - attackPosition" in attack_position,
    "Farm skills must wait until movement is holding at the target's attack position",
)

farm_skill = function_body(
    MAIN_FARM,
    "function MainFarm:_TryStartFarmSkill",
    "\nfunction MainFarm:_StepAura",
)
require(
    "self:_IsAtFarmAttackPosition(target, playerRoot, weaponCategory)" in farm_skill
    and farm_skill.index("_IsAtFarmAttackPosition") < farm_skill.index("FindReadyFarmSkill(")
    and "self:_IsAtFarmAttackPosition(target, currentRoot, weaponCategory)" in farm_skill
    and "FindReadyFarmSkill(" in farm_skill
    and "FARM_SKILL_SCAN_INTERVAL" in farm_skill
    and "FARM_SKILL_PREPARE_TIMEOUT" in farm_skill
    and "FARM_SKILL_UNAVAILABLE_RETRY" in farm_skill
    and "task.spawn(function()" in farm_skill
    and "combatService:UseSkill(" in farm_skill
    and "self:_IsCurrent(session)" in farm_skill
    and "self.Target == target" in farm_skill
    and "currentSettings.UseFarmSkills == true" in farm_skill
    and "currentSettings[skill.Setting] == true" in farm_skill
    and "combatService:EquipWeapon(currentSettings and currentSettings.WeaponCategory or weaponCategory)" in farm_skill,
    "Regular skill use must be throttled, cancellable, and restore the selected Farm Weapon",
)
require(
    MAIN_FARM.count(
        "self:_TryStartFarmSkill(target, session, weaponCategory, farmSettings, root)"
    ) == 3
    and "FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1" in MAIN_FARM
    and "self.CombatService:Cancel()" in MAIN_FARM,
    "All regular farm combat paths must use skills safely and invalidate them on stop/respawn",
)

tiki_action = function_body(
    MAIN_FARM,
    "function MainFarm:_UseTikiPuzzleAction",
    "\nfunction MainFarm:_StepTikiEventPhase",
)
require(
    "FindReadyTikiSkill()" in tiki_action
    and "UseSkill(" in tiki_action
    and "TIKI_SKILL_HOLD_SECONDS" in tiki_action
    and "farmSettings" not in tiki_action
    and "any ready skill" in tiki_action,
    "Tiki puzzle skills must ignore regular-farm skill settings and use any ready skill",
)

print("PASS: BNN skill keys, hold duration, and fast-release controls are migrated")
print("PASS: ready skills use validated UI state, targeted aim, and cancellation-safe key release")
print("PASS: regular farm attacks can use skills asynchronously and restore Farm Weapon")
print("PASS: Tiki puzzle automatically uses any available skill without puzzle-only settings")
