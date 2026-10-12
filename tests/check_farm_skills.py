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
    and "FarmMastery = false" in CONFIG
    and 'FarmMasteryMethods = { "Blox Fruit", "Gun" }' in CONFIG
    and "MasteryHealthPercent = 40" in CONFIG
    and '"FarmSkill_" .. category.Token .. "_" .. keyName' in CONFIG
    and "farmSkillDefaults[settingName] = true" in CONFIG
    and 'Action = "farm.skills.enabled"' in CONFIG
    and 'Action = "farm.skills.holdSeconds.set"' in CONFIG
    and 'Action = "farm.skills.fastRelease"' in CONFIG
    and 'Action = "farm.mastery.enabled"' in CONFIG
    and 'Action = "farm.mastery.category.select"' in CONFIG
    and 'Action = "farm.mastery.healthPercent.set"' in CONFIG,
    "Farm skill controls must be opt-in, bounded by settings, and default selected keys consistently",
)
pages_start = CONFIG.index("    Pages = {")
farm_page_start = CONFIG.index('        Farm = {\n            Controls = {', pages_start)
farm_page_end = CONFIG.index("        Player = {", farm_page_start)
farm_page = CONFIG[farm_page_start:farm_page_end]
farm_settings_start = CONFIG.index(
    '        FarmSettings = {\n            Title = "Farm settings"',
    farm_page_end,
)
farm_settings_end = CONFIG.index("    },\n}\n\nfor settingName", farm_settings_start)
farm_settings_page = CONFIG[farm_settings_start:farm_settings_end]
require(
    all(
        action in farm_page
        for action in (
            'Action = "farm.mastery.enabled"',
            'Action = "farm.mastery.category.select"',
            'Action = "farm.mastery.healthPercent.set"',
        )
    )
    and "farm.mastery." not in farm_settings_page,
    "Farm Mastery controls must live on the Farming page, not Farm Settings",
)
require(
    farm_page.index('Action = "farm.main"')
    < farm_page.index('Action = "farm.mastery.enabled"'),
    "Farm Mastery controls must appear below Start Farm",
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
    and "onlyCategory" in ready_skill
    and "category.Name == onlyCategory" in ready_skill
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
    and "onlyCategory" in farm_skill_lookup
    and "return self:_FindReadySkill(function()" in tiki_skill_lookup
    and "farmSettings" not in tiki_skill_lookup,
    "Regular combat must honor skill selection while Tiki automatically accepts any ready skill",
)

gun_m1 = function_body(
    COMBAT,
    "function CombatService:AttackGunM1",
    "\nfunction CombatService:TapSkullGuitar",
)
require(
    'self:FindWeapon("Gun")' in gun_m1
    and "self:EquipTool(tool)" in gun_m1
    and "IsGunReloading" in gun_m1
    and "NextGunM1At" in gun_m1
    and "self:_SetTemporaryAim(target)" in gun_m1
    and "tool:Activate()" in gun_m1
    and "validator2:FireServer" not in gun_m1
    and "ShootGunEvent" not in gun_m1
    and "debugLibrary" not in gun_m1,
    "Gun M1 must use target-scoped aim and standard Tool activation",
)

aim_target = function_body(
    COMBAT,
    "function CombatService:_GetAimTarget",
    "\nfunction CombatService:_SetTemporaryAim",
)
aim_updater = function_body(
    COMBAT,
    "function CombatService:_UpdateTemporaryAim",
    "\nfunction CombatService:_SetTemporaryAim",
)
require(
    all(part_name in aim_target for part_name in ("UpperTorso", "Torso", "HumanoidRootPart"))
    and "target.PrimaryPart" in aim_target
    and "G.Hit = T.HumanoidRootPart.CFrame" in BNN
    and "G.Target = T" in BNN
    and "aimContext.Mouse.Hit = targetPart.CFrame" in aim_updater
    and "aimContext.Mouse.Target = mouseTarget" in aim_updater
    and "assignedTarget ~= mouseTarget" in aim_updater,
    "Skill aim must track a body part and set Mouse.Target to the enemy model as BNN does",
)

use_skill = function_body(
    COMBAT,
    "function CombatService:UseSkill",
    "\nfunction CombatService:UseTikiSkill",
)
require(
    "SendKeyEvent(true, keyName" in use_skill
    and "SendKeyEvent(false, keyName" in use_skill
    and "self:_SetTemporaryAim(target)" in use_skill
    and "self:_UpdateTemporaryAim(aimContext, target)" in use_skill
    and "self:_RestoreTemporaryAim(aimContext)" in use_skill
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

mastery_category = function_body(
    MAIN_FARM,
    "function MainFarm:_GetMasteryCategory",
    "\nfunction MainFarm:_TryStartFarmSkill",
)
require(
    'farmSettings.FarmMastery ~= true' in mastery_category
    and 'category ~= "Blox Fruit" and category ~= "Gun"' in mastery_category
    and "health / maxHealth) * 100 <= threshold" in mastery_category
    and "MasteryHealthPercent" in mastery_category,
    "Mastery must switch categories only at or below the configured health threshold",
)

mastery_m1 = function_body(
    MAIN_FARM,
    "function MainFarm:_TryMasteryM1Fallback",
    "\nfunction MainFarm:_TryStartFarmSkill",
)
require(
    "MASTERY_M1_FALLBACK_INTERVAL" in mastery_m1
    and "EquipWeapon(masteryCategory)" in mastery_m1
    and 'masteryCategory == "Gun"' in mastery_m1
    and "AttackGunM1(target)" in mastery_m1
    and 'masteryCategory == "Blox Fruit"' in mastery_m1
    and 'AttackM1(' in mastery_m1
    and '"Blox Fruit"' in mastery_m1,
    "When no selected mastery skill is ready, throttle and use that mastery weapon's M1 path",
)

farm_skill = function_body(
    MAIN_FARM,
    "function MainFarm:_TryStartFarmSkill",
    "\nfunction MainFarm:_StepAura",
)
require(
    "self:_IsAtFarmAttackPosition(target, playerRoot, skillCategory)" in farm_skill
    and farm_skill.index("_IsAtFarmAttackPosition") < farm_skill.index("FindReadyFarmSkill(")
    and "self:_IsAtFarmAttackPosition(target, currentRoot, skillCategory)" in farm_skill
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
    and "farmSettings.UseFarmSkills ~= true" in farm_skill
    and farm_skill.index("not masteryCategory")
    < farm_skill.index("currentSettings.UseFarmSkills == true")
    and "currentSettings.FarmMastery == true" in farm_skill
    and farm_skill.index("_IsAtFarmAttackPosition")
    < farm_skill.index("self:_TryMasteryM1Fallback")
    and "masteryCategory" in farm_skill
    and "self.CombatService:EquipWeapon(masteryCategory)" in farm_skill
    and farm_skill.count(
        "self:_TryMasteryM1Fallback(target, masteryCategory, farmSettings)"
    ) >= 1
    and "Skill failed; " in farm_skill
    and "fallbackIssued, fallbackResult = self:_TryMasteryM1Fallback(" in farm_skill
    and "combatService:EquipWeapon(restoreCategory)" in farm_skill
    and "Mastery waiting: enable Use skills while farming" not in farm_skill,
    "Mastery skills must bypass the general farm-skill toggle while respecting selected category and keys",
)
require(
    MAIN_FARM.count("self:_TryStartFarmSkill(") == 3
    and "farmSettings, root, true)" in MAIN_FARM
    and "root,\n            targetIsBoss ~= true" in MAIN_FARM
    and "self:_GetMasteryCategory(target, farmSettings, true)" in MAIN_FARM
    and "FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1" in MAIN_FARM
    and "self.CombatService:Cancel()" in MAIN_FARM,
    "All farm paths must route selected skills safely and keep bosses out of Mastery mode",
)
require(
    "farmSettings.FarmMastery = payload" in MAIN_FARM
    and "farmSettings.MasteryCategory = selectedMethod" in MAIN_FARM
    and "farmSettings.MasteryHealthPercent =" in MAIN_FARM
    and "not selectedMethod" in MAIN_FARM
    and "selectedPercent < minimum" in MAIN_FARM
    and "selectedPercent > maximum" in MAIN_FARM
    and "debug.getupvalue" not in MAIN_FARM
    and "debug.setupvalue" not in MAIN_FARM
    and "getgc(" not in MAIN_FARM,
    "Gun validator hooks must stay isolated in CombatService, not MainFarm",
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
print("PASS: ready skills use validated UI state, target-model aim, and cancellation-safe key release")
print("PASS: Gun Mastery uses scoped Mouse aim and standard Tool activation")
print("PASS: regular farm attacks can use skills asynchronously and restore Farm Weapon")
print("PASS: Tiki puzzle automatically uses any available skill without puzzle-only settings")
