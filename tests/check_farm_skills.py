from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HUB = ROOT / "src/ReplicatedStorage/CustomHub"
CONFIG = (HUB / "Config.lua").read_text(encoding="utf-8")
COMBAT = (HUB / "Features/Farm/CombatService.lua").read_text(encoding="utf-8")
MAIN_FARM = (HUB / "Features/MainFarm.lua").read_text(encoding="utf-8")
COMPATIBILITY = (HUB / "Compatibility.lua").read_text(encoding="utf-8")
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
    and "titleColor == Color3.new(1, 1, 1)" in ready_skill
    and "cooldown.Size == UDim2.new(0, 0, 1, -1)" in ready_skill
    and "cooldown.Size == UDim2.new(1, 0, 1, -1)" in ready_skill
    and "isReady = (titleIsReady and cooldownEmpty) or cooldownFull" in ready_skill
    and "local tool = self:FindSkillWeapon(category.Name)" in ready_skill
    and "frame.Visible" not in ready_skill
    and 'for _, frame in ipairs(toolSkills:GetChildren()) do' in ready_skill
    and 'selectedKeySet[keyName]' in ready_skill
    and 'frame.Name ~= "Template"' in ready_skill
    and 'string.find(titleText, "Transformation", 1, true)' in ready_skill
    and "self:EquipTool(tool)" in ready_skill
    and "PlayerGui.Main.Skills entry" in ready_skill
    and "listSkillUiToolNames(skills)" in ready_skill
    and "equippedTool" not in ready_skill
    and "LastMasterySkillKey" not in ready_skill
    and "ignoredTools" in ready_skill
    and "onlyCategory" in ready_skill
    and "category.Name == onlyCategory" in ready_skill
    and "No selected skill keys are enabled" in ready_skill
    and "All selected skill keys are on cooldown" in ready_skill
    and "Skill UI incomplete:" in ready_skill
    and "Selected skill unavailable:" in ready_skill
    and "GetDescendants" not in ready_skill,
    "Mastery readiness must match BNN's two cooldown states while reporting incomplete controls distinctly",
)
refresh_equipped_tool = function_body(
    COMBAT,
    "function CombatService:RefreshEquippedTool",
    "\nfunction CombatService:EquipWeapon",
)
require(
    "humanoid:UnequipTools()" in refresh_equipped_tool
    and "humanoid:EquipTool(tool)" in refresh_equipped_tool
    and "tool.Parent ~= character" in refresh_equipped_tool
    and "Remote" not in refresh_equipped_tool
    and "InvokeServer" not in refresh_equipped_tool,
    "A missing skill UI may trigger a bounded local re-equip refresh, not a guessed remote",
)
require(
    "for _, frame in ipairs(toolSkills:GetChildren()) do" in ready_skill
    and "if isReady then" in ready_skill
    and "LastMasterySkillKey" not in COMBAT
    and "rotatedKeys" not in ready_skill,
    "Ready skills must be discovered by scanning the live GUI frames on every retry",
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
    and "equippedTool" not in farm_skill_lookup
    and "return self:_FindReadySkill(function()" in tiki_skill_lookup
    and "farmSettings" not in tiki_skill_lookup,
    "Farm skill lookup must lock to an optional category without pinning an equipped tool",
)

find_weapon = function_body(
    COMBAT,
    "function CombatService:FindWeapon",
    "\nfunction CombatService:FindToolByName",
)
require(
    find_weapon.index('if category == "Gun"') < find_weapon.index("if character then")
    and 'item.Name == "Skull Guitar"' in find_weapon
    and find_weapon.index('item.Name == "Skull Guitar"')
        < find_weapon.index('item.ToolTip == category')
    and "foundUnequippedSkullGuitar" not in find_weapon
    and "Skull Guitar is in the Backpack; it will not be equipped for farming" not in find_weapon,
    "Gun selection must prioritize Skull Guitar from Character or Player.Backpack",
)
find_skill_weapon = function_body(
    COMBAT,
    "function CombatService:FindSkillWeapon",
    "\nfunction CombatService:FindToolByName",
)
require(
    'findMatchingTool(backpack, "Skull Guitar")' in find_skill_weapon
    and 'findMatchingTool(character, "Skull Guitar")' in find_skill_weapon
    and find_skill_weapon.index("findMatchingTool(backpack)") < find_skill_weapon.index("findMatchingTool(character)")
    and "item.ToolTip == category" in find_skill_weapon,
    "Skill weapon lookup must use BNN's Backpack-first category search while retaining Skull Guitar preference",
)
equipped_weapon = function_body(
    COMBAT,
    "function CombatService:FindEquippedWeapon",
    "\nfunction CombatService:FindWeapon",
)
require(
    "character:GetChildren()" in equipped_weapon
    and 'item:IsA("Tool") and item.ToolTip == category' in equipped_weapon
    and "Backpack" not in equipped_weapon
    and "FindWeapon(" not in equipped_weapon
    and "EquipTool(" not in equipped_weapon,
    "Mastery weapon lookup must remain separate from equipped-only validation",
)

gun_m1 = function_body(
    COMBAT,
    "function CombatService:AttackGunM1",
    "\nfunction CombatService:TapSkullGuitar",
)
require(
    'self:FindEquippedWeapon("Gun")' in gun_m1
    and "self:FindWeapon(" not in gun_m1
    and "self:EquipTool(" not in gun_m1
    and "requiredTool" in gun_m1
    and "IsGunReloading" in gun_m1
    and "NextGunM1At[tool]" in gun_m1
    and "self:_GetToolCooldown(tool)" in gun_m1
    and 'if tool.Name == "Skull Guitar" then' in gun_m1
    and 'remote:FireServer("TAP", targetRoot.Position)' in gun_m1
    and "server damage is unconfirmed" in gun_m1
    and "self.Compatibility:GetGunShootFunction()" in gun_m1
    and "TapSkullGuitar" not in gun_m1
    and "self:_SetTemporaryAim(target)" in gun_m1
    and "WorldToViewportPoint(targetRoot.Position)" in gun_m1
    and "Enum.UserInputType.Touch" in gun_m1
    and "SendMouseButtonEvent" in gun_m1
    and "tool:Activate()" not in gun_m1
    and "Heartbeat:Wait()" in gun_m1
    and gun_m1.index("Heartbeat:Wait()") < gun_m1.index("self:_RestoreTemporaryAim(aimContext)")
    and "validator2:FireServer" not in gun_m1
    and "ShootGunEvent" not in gun_m1
    and "debugLibrary" not in gun_m1,
    "Gun M1 must use validated screen-targeted input for regular guns and TAP only an already-equipped Skull Guitar",
)
fruit_m1 = function_body(
    COMBAT,
    "function CombatService:_AttackFruitM1",
    "\nfunction CombatService:AttackM1",
)
mastery_attack_m1 = function_body(
    COMBAT,
    "function CombatService:AttackM1",
    "\nfunction CombatService:Cancel",
)
require(
    "tool.Parent ~= character" in fruit_m1
    and "tool:FindFirstChild(\"LeftClickRemote\")" in fruit_m1
    and "remoteFunction:InvokeServer(\"TAP\")" in fruit_m1
    and "requiredTool" in mastery_attack_m1
    and "NextFruitM1At[tool]" in mastery_attack_m1
    and "self:_GetToolCooldown(tool)" in mastery_attack_m1
    and "pcall(" in mastery_attack_m1
    and "self:FindWeapon(" not in mastery_attack_m1
    and "self:EquipTool(" not in mastery_attack_m1,
    "Fruit Mastery M1 must use the pinned equipped fruit and its available cooldown data",
)
gun_shoot_lookup = function_body(
    COMPATIBILITY,
    "function Compatibility:GetGunShootFunction",
    "\nfunction Compatibility:IsTouchEnabled",
)
require(
    "upvalues[9]" in gun_shoot_lookup
    and 'pcall(debugInfo, shootGun, "n")' in gun_shoot_lookup
    and 'functionName ~= "shootGun"' in gun_shoot_lookup
    and "pcall(getUpvalues, attack)" in gun_shoot_lookup
    and "GetSignalConnections" not in COMBAT
    and "GetSignalConnections" not in COMPATIBILITY,
    "Optional gun internals are validated and mobile skills avoid synthetic GUI connection firing",
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
    and "GetSignalConnections" not in use_skill
    and "SendKeyEvent(true," in BNN
    and "SendKeyEvent(false," in BNN
    and "self.ActiveInputRelease = releaseInput" in use_skill
    and "self:EquipTool(tool)" in use_skill
    and use_skill.index("self:EquipTool(tool)") < use_skill.index("SendKeyEvent(true, keyName")
    and use_skill.index("local waitOk, waitError = pcall(function()")
    < use_skill.index("local releaseOk, releaseResult = pcall(releaseInput)")
    < use_skill.index("if farmStateChanged then")
    and "tool.Parent ~= character" in use_skill
    and "pinEquippedTool" not in use_skill
    and "farmStateChanged = true" in use_skill
    and '"Skill input cancelled because farm state changed"' in use_skill
    and "LastMasterySkillKey" not in COMBAT
    and "self:_SetTemporaryAim(target)" in use_skill
    and "self:_UpdateTemporaryAim(aimContext, target)" in use_skill
    and "self:_RestoreTemporaryAim(aimContext)" in use_skill
    and "holdSeconds) or 0.5, 0.05, 5" in use_skill
    and "shouldContinue()" in use_skill,
    "Normal and mastery skills must share the same unpinned equip/input/aim lifecycle",
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

require(
    "_TryMasteryM1Fallback" not in MAIN_FARM
    and "LastMasteryM1Result" not in MAIN_FARM
    and "AttackGunM1(" not in MAIN_FARM,
    "Farm Mastery must not dispatch any M1 attack while it is skills-only",
)

farm_skill = function_body(
    MAIN_FARM,
    "function MainFarm:_TryStartFarmSkill",
    "\nfunction MainFarm:_StepAura",
)
mastery_policy_setup = farm_skill.split("    local now = os.clock()", 1)[0]
skill_dispatch = farm_skill.split(
    "    task.spawn(function()",
    1,
)[1].split("    return true\nend", 1)[0]
mastery_skill_success = farm_skill.split(
    "if activated and self:_IsCurrent(session) and self.Target == target then",
    1,
)[1].split("elseif not activated and self:_IsCurrent(session) and self.Target == target then", 1)[0]
mastery_skill_failure = farm_skill.split(
    "elseif not activated and self:_IsCurrent(session) and self.Target == target then",
    1,
)[1].split("\n            end\n        end\n        local currentCharacter", 1)[0]
mastery_no_skill_branch = farm_skill.split("if not skill then", 1)[1].split(
    "self.FarmSkillGeneration =",
    1,
)[0]
require(
    "self:_IsAtFarmAttackPosition(target, playerRoot, skillCategory)" in farm_skill
    and farm_skill.index("_IsAtFarmAttackPosition") < farm_skill.index("FindReadyFarmSkill(")
    and "self:_IsAtFarmAttackPosition(target, currentRoot, skillCategory)" in farm_skill
    and "FindReadyFarmSkill(" in farm_skill
    and "local masteryCategory = self:_GetMasteryCategory(target, farmSettings, allowMastery)" in farm_skill
    and "local skillCategory = masteryCategory or weaponCategory" in farm_skill
    and "if masteryCategory == nil\n        and (not farmSettings or farmSettings.UseFarmSkills ~= true)" in farm_skill
    and "if not masteryCategory then\n            self.FarmSkillPreparing = nil\n            return false" not in mastery_policy_setup
    and "local skillScanInterval = FARM_SKILL_SCAN_INTERVAL" in farm_skill
    and "self.NextFarmSkillScanAt = now + skillScanInterval" in farm_skill
    and "self.NextFarmSkillScanAt = os.clock() + skillScanInterval" in farm_skill
    and "FARM_SKILL_PREPARE_TIMEOUT" in farm_skill
    and "FARM_SKILL_UNAVAILABLE_RETRY" in farm_skill
    and "MASTERY_SKILL_UI_REFRESH_LIMIT = 2" in MAIN_FARM
    and "preparation.TotalRefreshAttempts < MASTERY_SKILL_UI_REFRESH_LIMIT" in farm_skill
    and "self.CombatService:RefreshEquippedTool(preparingTool)" in farm_skill
    and "tool UI refresh limit reached" in farm_skill
    and "if masteryCategory then\n        skillIgnoredTools = nil" in farm_skill
    and farm_skill.count("task.spawn(function()") == 1
    and "finishSkillAttempt(runSkillAttempt())" in skill_dispatch
    and "combatService:UseSkill(" in farm_skill
    and "self:_IsCurrent(session)" in farm_skill
    and "self.Target == target" in farm_skill
    and "currentSettings.UseFarmSkills == true" in farm_skill
    and "currentSettings[skill.Setting] == true" in farm_skill
    and "currentSettings.FarmMastery ~= true" not in farm_skill
    and "currentSettings.FarmMastery == true" in farm_skill
    and "local callOk, activated, activationResult = pcall(function()" in farm_skill
    and "if not callOk then" in farm_skill
    and "Mastery waiting for a ready selected " not in farm_skill
    and "Mastery waiting: selected skills cooling down" in farm_skill
    and "Mastery waiting: enable a selected skill key" in farm_skill
    and '"Mastery waiting: " .. tostring(skillError)' in farm_skill
    and "Mastery skill input failed:" in farm_skill
    and '"Using Mastery "' not in farm_skill
    and "return true\n        end\n        if skillError" in mastery_no_skill_branch
    and "AttackGunM1(" not in farm_skill
    and "AttackM1(" not in farm_skill
    and "masteryCategory" in farm_skill
    and "masteryTool" not in farm_skill
    and "self.CombatService:EquipWeapon(masteryCategory)" not in farm_skill
    and "self.CombatService:FindReadyFarmSkill(\n        farmSettings,\n        skillCategory,\n        skillIgnoredTools,\n        masteryCategory\n    )" in farm_skill
    and "self.CombatService:FindEquippedWeapon(masteryCategory)" not in farm_skill
    and "self:_IsAtFarmAttackPosition(target, currentRoot, skillCategory)" in farm_skill
    and "MASTERY_M1_FALLBACK_INTERVAL" not in farm_skill
    and "skillIgnoredTools," in farm_skill
    and "if masteryCategory then\n            return true" in farm_skill
    and "combatService:EquipWeapon(restoreCategory)" in farm_skill
    and "and not masteryCategory" in farm_skill
    and "if not masteryCategoryNow then" in farm_skill
    and "local masteryCategoryNow = currentSettings" in farm_skill
    and "Mastery waiting: enable Use skills while farming" not in farm_skill,
    "Mastery must reuse the farm skill flow, allow normal skills above threshold, and wait without wrong-weapon fallback",
)
preparing_branch = farm_skill.split("if preparingTool then", 1)[1].split(
    "self.FarmSkillPreparing = nil\n    if not skill then",
    1,
)[0]
normal_timeout = farm_skill.split(
    "if not masteryCategory then\n            self.FarmSkillIgnoredTools[preparingTool.Name]",
    1,
)[1].split(
    "\n        end",
    1,
)[0]
mastery_timeout = farm_skill.split(
    '"Mastery waiting: " .. tostring(skillError)',
    1,
)[1].split("return true", 1)[0]
require(
    "skillError" in preparing_branch
    and "self.FarmSkillPreparing = nil" in normal_timeout
    and "self.FarmSkillPreparing = nil" not in mastery_timeout
    and "Mastery waiting: " in farm_skill
    and "return true" in farm_skill.split(
        '"Mastery waiting: " .. tostring(skillError)',
        1,
    )[1],
    "Mastery must keep retrying and report exact missing controls; only ordinary farm skill fallback expires",
)
require(
    "key input" in mastery_skill_success
    and "M1" not in mastery_skill_success
    and "Mastery skill input failed:" in mastery_skill_failure
    and "M1" not in mastery_skill_failure,
    "Mastery must use skills only and wait safely when a skill send fails",
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
print("PASS: Mastery and regular skills share category-filtered cooldown readiness without tool pinning or key rotation")
print("PASS: skill input uses VIM key events, reports the hold duration, and releases safely")
print("PASS: skill weapon lookup follows BNN's Backpack-first flow; Skull Guitar TAP is chosen only while equipped")
print("PASS: Mastery is skills-only; the isolated Gun M1 helper is not called")
print("PASS: Mastery and ordinary farming share skill scan cadence and async dispatch")
print("PASS: ordinary farm attacks restore Farm Weapon after asynchronous skill use")
print("PASS: Tiki puzzle automatically uses any available skill without puzzle-only settings")
