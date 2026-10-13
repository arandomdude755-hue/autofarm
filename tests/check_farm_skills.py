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
    and "titleIsReady and cooldownEmpty" in ready_skill
    and "cooldownFull" in ready_skill
    and "cooldown.Size.X.Scale" in ready_skill
    and "frame.Visible" not in ready_skill
    and 'string.find(titleText, "Transformation", 1, true)' in ready_skill
    and "self:EquipTool(tool)" in ready_skill
    and "if not equippedTool then" in ready_skill
    and "equippedTool.Parent == character" in ready_skill
    and "ignoredTools" in ready_skill
    and "onlyCategory" in ready_skill
    and "category.Name == onlyCategory" in ready_skill
    and "No selected skill keys are enabled" in ready_skill
    and "All selected skill keys are on cooldown" in ready_skill
    and "Skill UI incomplete:" in ready_skill
    and "Selected skill unavailable:" in ready_skill
    and "GetDescendants" not in ready_skill,
    "Skill readiness must accept approximate ready cooldown states and report incomplete controls distinctly",
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
    and "equippedTool" in farm_skill_lookup
    and "return self:_FindReadySkill(function()" in tiki_skill_lookup
    and "farmSettings" not in tiki_skill_lookup,
    "Regular combat must honor skill selection while Tiki automatically accepts any ready skill",
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
    and "pinEquippedTool" in use_skill
    and "self:EquipTool(tool)" in use_skill
    and use_skill.index("self:EquipTool(tool)") < use_skill.index("SendKeyEvent(true, keyName")
    and "tool.Parent ~= character" in use_skill
    and "farmStateChanged = true" in use_skill
    and '"Skill input cancelled because farm state changed"' in use_skill
    and "self:_SetTemporaryAim(target)" in use_skill
    and "self:_UpdateTemporaryAim(aimContext, target)" in use_skill
    and "self:_RestoreTemporaryAim(aimContext)" in use_skill
    and "holdSeconds) or 0.5, 0.05, 5" in use_skill
    and "shouldContinue()" in use_skill,
    "Normal and mastery skills must share equip/input/aim behavior while mastery pins its tool",
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
    "EquipWeapon(masteryCategory)" in mastery_m1
    and "AttackGunM1(target, tool)" in mastery_m1
    and "tool" in mastery_m1
    and "MASTERY_M1_FALLBACK_INTERVAL" not in mastery_m1
    and "LastMasteryM1Result" in mastery_m1
    and 'masteryCategory == "Gun"' in mastery_m1
    and 'masteryCategory == "Blox Fruit"' in mastery_m1
    and 'AttackM1(' in mastery_m1
    and 'tool\n        )' in mastery_m1
    and '"Blox Fruit"' in mastery_m1,
    "Mastery fallback must select/equip a matching live tool, pin the attack to it, and leave attack timing to the tool path",
)

farm_skill = function_body(
    MAIN_FARM,
    "function MainFarm:_TryStartFarmSkill",
    "\nfunction MainFarm:_StepAura",
)
mastery_skill_success = farm_skill.split(
    "if activated and self:_IsCurrent(session) and self.Target == target then",
    1,
)[1].split("elseif not activated and self:_IsCurrent(session) and self.Target == target then", 1)[0]
require(
    "self:_IsAtFarmAttackPosition(target, playerRoot, skillCategory)" in farm_skill
    and farm_skill.index("_IsAtFarmAttackPosition") < farm_skill.index("FindReadyFarmSkill(")
    and "self:_IsAtFarmAttackPosition(target, currentRoot, skillCategory)" in farm_skill
    and "FindReadyFarmSkill(" in farm_skill
    and "FARM_SKILL_SCAN_INTERVAL" in farm_skill
    and "FARM_SKILL_PREPARE_TIMEOUT" in farm_skill
    and "FARM_SKILL_UNAVAILABLE_RETRY" in farm_skill
    and "if masteryCategory then\n        skillIgnoredTools = nil" in farm_skill
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
    and "local callOk, activated, activationResult = pcall(function()" in farm_skill
    and "if not callOk then" in farm_skill
    and "Mastery waiting for a ready selected " not in farm_skill
    and "selected skills cooling down" in farm_skill
    and "no skill keys enabled" in farm_skill
    and 'string.find(resultText, "shootGun", 1, true)' in farm_skill
    and 'routeSuffix = " (shootGun)"' in farm_skill
    and "masteryCategory" in farm_skill
    and "self.CombatService:EquipWeapon(masteryCategory)" in farm_skill
    and '"Mastery waiting: no usable "' in farm_skill
    and "self.CombatService:FindEquippedWeapon(masteryCategory)" in farm_skill
    and "masteryTool ~= nil" in farm_skill
    and "self.CombatService:FindEquippedWeapon(masteryCategory)" in farm_skill
    and "masteryTool.Parent == currentCharacter" in farm_skill
    and "masteryCategory ~= nil\n                            or self:_IsAtFarmAttackPosition" in farm_skill
    and "MASTERY_M1_FALLBACK_INTERVAL" not in farm_skill
    and "skillIgnoredTools," in farm_skill
    and "if masteryCategory then\n            return true" in farm_skill
    and "Skill failed; " in farm_skill
    and "fallbackIssued, fallbackResult =" in farm_skill
    and "combatService:EquipWeapon(restoreCategory)" in farm_skill
    and "and not masteryCategory" in farm_skill
    and "if not masteryCategoryNow then" in farm_skill
    and "local masteryCategoryNow = currentSettings" in farm_skill
    and "Mastery waiting: enable Use skills while farming" not in farm_skill,
    "Mastery skills must stay on the pinned equipped tool, retry UI detection, and bypass farm-only movement checks",
)
require(
    "self:_TryMasteryM1Fallback(" in mastery_skill_success
    and "mastery M1 input sent" in mastery_skill_success
    and "M1 not sent:" in mastery_skill_success,
    "After sending a mastery skill key, continue attacking with the selected mastery weapon's M1 path",
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
print("PASS: ready skills use BNN cooldown states, VIM key input, and cancellation-safe release")
print("PASS: Mastery equips and pins the selected hotbar tool; Skull Guitar TAP is chosen only while equipped")
print("PASS: Gun Mastery uses regular-gun input and TAP only for an equipped Skull Guitar")
print("PASS: regular farm attacks can use skills asynchronously and restore Farm Weapon")
print("PASS: Tiki puzzle automatically uses any available skill without puzzle-only settings")
