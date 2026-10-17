from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HUB = ROOT / "src/ReplicatedStorage/CustomHub"
CONFIG = (HUB / "Config.lua").read_text(encoding="utf-8")
COMBAT = (HUB / "Features/Farm/CombatService.lua").read_text(encoding="utf-8")
MAIN_FARM = (HUB / "Features/MainFarm.lua").read_text(encoding="utf-8")
COMPATIBILITY = (HUB / "Compatibility.lua").read_text(encoding="utf-8")
SKILL_AIM_REDIRECT = (
    HUB / "Features/Farm/SkillAimRedirect.lua"
).read_text(encoding="utf-8")
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
farm_page_start = CONFIG.index(
    '        Farm = {\n            Title = "Main Farming",\n            Controls = {',
    pages_start,
)
farm_page_end = CONFIG.index("        StackFarming = {", farm_page_start)
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
    and "local tool = self:FindSkillWeapon(category.Name, onlyCategory ~= nil)" in ready_skill
    and "frame.Visible" not in ready_skill
    and 'for _, frame in ipairs(toolSkills:GetChildren()) do' in ready_skill
    and 'selectedKeySet[keyName]' in ready_skill
    and 'frame.Name ~= "Template"' in ready_skill
    and 'string.find(titleText, "Transformation", 1, true)' in ready_skill
    and "pcall(self.EquipTool, self, tool)" in ready_skill
    and "tool.Parent ~= character" not in ready_skill
    and ready_skill.index("pcall(self.EquipTool, self, tool)")
        < ready_skill.index("local toolSkills = skills:FindFirstChild(tool.Name)")
    and "No selected mastery skill is ready:" in ready_skill
    and "locked or unavailable" in ready_skill
    and "masterySkillUiMismatch" not in ready_skill
    and "cooldownEmpty and not cooldownFull" in ready_skill
    and "onlyCategory and masterySkillUiTool or nil" in ready_skill
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
skill_diagnostic = function_body(
    COMBAT,
    "function CombatService:BuildFarmSkillDiagnostic",
    "\nfunction CombatService:FindReadyTikiSkill",
)
require(
    "PlayerGui" in skill_diagnostic
    and 'FindFirstChild("Main")' in skill_diagnostic
    and 'FindFirstChild("Skills")' in skill_diagnostic
    and "Main.Enabled=" in skill_diagnostic
    and "Skills entries:" in skill_diagnostic
    and "Selected tool entry:" in skill_diagnostic
    and "Selected keys:" in skill_diagnostic
    and "controls=" in skill_diagnostic
    and "visible=" in skill_diagnostic
    and "cooldownEmpty=" in skill_diagnostic
    and "cooldownFull=" in skill_diagnostic
    and "listCategoryToolNames(character" in skill_diagnostic
    and "listCategoryToolNames(backpack" in skill_diagnostic,
    "Farm skill diagnostic must report the selected tool, GUI rows, selected keys, and cooldown evidence",
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
    "if preferEquipped then" in find_skill_weapon
    and "local equipped = self:FindEquippedWeapon(category)" in find_skill_weapon
    and find_skill_weapon.index("return equipped") < find_skill_weapon.index("findMatchingTool(backpack)")
    and 'item.Name ~= "Skull Guitar"' not in find_skill_weapon
    and 'if category == "Gun" and not preferEquipped then' in find_skill_weapon
    and 'findMatchingTool(backpack, "Skull Guitar")' in find_skill_weapon
    and 'findMatchingTool(character, "Skull Guitar")' in find_skill_weapon
    and find_skill_weapon.index("findMatchingTool(backpack)") < find_skill_weapon.index("findMatchingTool(character)")
    and "item.ToolTip == category" in find_skill_weapon,
    "Mastery must use the equipped category tool first, then the single current hotbar tool including Skull Guitar",
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
    and "self:_InvokeGunShootInput(tool, targetRoot)" in gun_m1
    and "if not tool.Enabled then" not in gun_m1
    and "shotStateChanged" in gun_m1
    and "return true, tostring(inputResult), shotStateChanged" in gun_m1
    and "TapSkullGuitar" not in gun_m1
    and "FireServer" not in gun_m1
    and "validator2:FireServer" not in gun_m1
    and "ShootGunEvent" not in gun_m1,
    "Gun M1 must call the game's target-directed gun handler without manually forging remotes",
)
gun_input = function_body(
    COMBAT,
    "function CombatService:_InvokeGunShootInput",
    "\nfunction CombatService:AttackGunM1",
)
require(
    "self.Compatibility:GetGunShootFunction()" in gun_input
    and "targetAssist.getTargetInfo = overrideTargetInfo" in gun_input
    and "return { Part = targetPart }" in gun_input
    and "Enum.UserInputType.Touch" in gun_input
    and "Enum.UserInputType.MouseButton1" in gun_input
    and "LocalShotsLeft" in gun_input
    and "LocalTotalShots" in gun_input
    and "Heartbeat:Wait()" in gun_input
    and "FireServer" not in gun_input
    and "validator2" not in gun_input
    and "ShootGunEvent" not in gun_input,
    "Gun input must temporarily target the chosen enemy and separate client firing evidence from server damage",
)
skull_guitar_tap = function_body(
    COMBAT,
    "function CombatService:TapSkullGuitar",
    "\nfunction CombatService:_FindBladeHitParts",
)
require(
    'FindToolByName("Skull Guitar")' in skull_guitar_tap
    and "self:EquipTool(tool)" in skull_guitar_tap
    and "self:_InvokeGunShootInput(tool, targetPart)" in skull_guitar_tap
    and "FireServer" not in skull_guitar_tap
    and "TAP" not in skull_guitar_tap,
    "Skull Guitar TAP must use the already-equipped Guitar through the game's client gun-input path",
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
    and "NextFruitM1At" not in mastery_attack_m1
    and "self:_GetToolCooldown(tool)" not in mastery_attack_m1
    and "pcall(" in mastery_attack_m1
    and "self:FindWeapon(" not in mastery_attack_m1
    and "self:EquipTool(" not in mastery_attack_m1,
    "Fruit Mastery M1 must use the pinned equipped fruit without an extra local cooldown",
)
gun_shoot_lookup = function_body(
    COMPATIBILITY,
    "function Compatibility:GetGunShootFunction",
    "\nfunction Compatibility:IsTouchEnabled",
)
require(
    "pcall(getGc, false)" in gun_shoot_lookup
    and 'value == "LocalShotsLeft"' in gun_shoot_lookup
    and 'value == "LocalTotalShots"' in gun_shoot_lookup
    and 'pcall(rawget, value, "getTargetInfo")' in gun_shoot_lookup
    and "pcall(getUpvalues, candidate)" in gun_shoot_lookup
    and "upvalues[9]" not in gun_shoot_lookup
    and "GetSignalConnections" not in COMBAT
    and "GetSignalConnections" not in COMPATIBILITY,
    "Optional gun internals are located by client shoot markers and target lookup, without fixed upvalue indices",
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
    and 'preferRoot\n        and { "HumanoidRootPart", "UpperTorso", "Torso", "Head" }' in aim_target
    and 'or { "UpperTorso", "Torso", "HumanoidRootPart", "Head" }' in aim_target
    and "target.PrimaryPart" in aim_target
    and "G.Hit = T.HumanoidRootPart.CFrame" in BNN
    and "G.Target = T" in BNN
    and "aimContext.Mouse.Hit = targetPart.CFrame" in aim_updater
    and "aimContext.Mouse.Target = mouseTarget" in aim_updater
    and "assignedTarget ~= mouseTarget" in aim_updater,
    "Skills must prefer BNN's HumanoidRootPart aim without changing Gun M1's existing torso preference",
)
require(
    'remoteName == "RemoteEvent"' in SKILL_AIM_REDIRECT
    and 'currentMethod == "FireServer"' in SKILL_AIM_REDIRECT
    and "arguments.n == 1" in SKILL_AIM_REDIRECT
    and 'typeof(argument) == "Vector3"' in SKILL_AIM_REDIRECT
    and 'typeof(argument) == "CFrame"' in SKILL_AIM_REDIRECT
    and "state.ActiveContext" in SKILL_AIM_REDIRECT
    and "getgenv" in SKILL_AIM_REDIRECT
    and 'local STATE_KEY = "__CustomHubSkillAimRedirectV1"' in SKILL_AIM_REDIRECT
    and "if state.Installed then" in SKILL_AIM_REDIRECT
    and "arguments[1] = context.Position" in SKILL_AIM_REDIRECT
    and "arguments[1] = context.CFrame" in SKILL_AIM_REDIRECT
    and "function SkillAimRedirect:Begin" in SKILL_AIM_REDIRECT
    and "function SkillAimRedirect:SetTarget" in SKILL_AIM_REDIRECT
    and "function SkillAimRedirect:Update" in SKILL_AIM_REDIRECT
    and "function SkillAimRedirect:End" in SKILL_AIM_REDIRECT
    and "function SkillAimRedirect:ClearTarget" in SKILL_AIM_REDIRECT
    and "context.Persistent = true" in SKILL_AIM_REDIRECT
    and "if context.Persistent or context.InputActive then" in SKILL_AIM_REDIRECT
    and "require(script.Parent.SkillAimRedirect)" in COMBAT,
    "Skill aiming must refresh BNN-style target position throughout an eligible farm target and clear on target changes",
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
    and "self:_SetTemporaryAim(target, true)" in use_skill
    and "self:_UpdateTemporaryAim(aimContext, target)" in use_skill
    and "self:_RestoreTemporaryAim(aimContext)" in use_skill
    and "holdSeconds) or 0.5, 0.05, 5" in use_skill
    and "shouldContinue()" in use_skill,
    "Normal and mastery skills must share the same unpinned equip/input/aim lifecycle",
)
require(
    "function CombatService:SetFarmSkillAimTarget" in COMBAT
    and "function CombatService:ClearFarmSkillAimTarget" in COMBAT
    and "self:ClearFarmSkillAimTarget()" in function_body(
        COMBAT,
        "function CombatService:Cancel",
        "\nreturn CombatService",
    ),
    "Farm skill aim state must be controllable and cleared when combat is cancelled",
)
gun_m1 = function_body(
    COMBAT,
    "function CombatService:AttackGunM1",
    "\nfunction CombatService:TapSkullGuitar",
)
require(
    "self:_InvokeGunShootInput(tool, targetRoot)" in gun_m1
    and "self:_SetTemporaryAim(target)" not in gun_m1
    and "FireServer" not in gun_m1,
    "The Gun M1 path must use the game's target lookup separately from skill aiming",
)

attack_position = function_body(
    MAIN_FARM,
    "function MainFarm:_IsAtFarmAttackPosition",
    "\nfunction MainFarm:_TryStartFarmSkill",
)
attack_position_builder = function_body(
    MAIN_FARM,
    "function MainFarm:_GetFarmAttackPosition",
    "\nfunction MainFarm:_MoveToFarmAttackPosition",
)
require(
    "FARM_SKILL_ATTACK_POSITION_TOLERANCE" in attack_position
    and "movement.Holding ~= true" in attack_position
    and "movement.Goal.Position - attackPosition" not in attack_position,
    "Farm skills must wait until the character is physically in attack range and movement is holding",
)
require(
    'CFrame.new(-7, 20, 0)' in attack_position_builder
    and 'CFrame.new(7, 20, 0)' in attack_position_builder,
    "All farm modes must derive their attack position through the same category-aware helper",
)
ready_skill_scan = function_body(
    COMBAT,
    "function CombatService:_FindReadySkill",
    "\nfunction CombatService:FindReadyFarmSkill",
)
require(
    "for _, frame in ipairs(toolSkills:GetChildren()) do" in ready_skill_scan
    and "local selectedKey = selectedKeySet[keyName]" in ready_skill_scan
    and "toolSkills:FindFirstChild(\"V\")" not in ready_skill_scan,
    "Skill scanning must use available UI entries and not require every fruit to expose a V move",
)
skill_movement = function_body(
    MAIN_FARM,
    "function MainFarm:_MoveToFarmAttackPosition",
    "\nfunction MainFarm:_IsAtFarmAttackPosition",
)
require(
    "self.FarmSkillActive" in skill_movement
    and "self.FarmSkillTarget == target" in skill_movement
    and "not allowRetargetDuringSkill" in skill_movement
    and "holding position for active skill" in skill_movement
    and "knockbackHold.Target == target" in skill_movement
    and "self:_HoldPosition(session)" in skill_movement
    and "holding briefly after Gun M1" in skill_movement
    and "GUN_KNOCKBACK_HOLD_SECONDS = 0.3" in MAIN_FARM
    and "self:_MoveTo(destination, session, threshold, keepSession)"
    in skill_movement
    and MAIN_FARM.count(
        "masteryCategory ~= nil\n            )"
    ) == 3
    and "self.FarmSkillTarget = target" in MAIN_FARM
    and "self.FarmSkillTarget = nil" in MAIN_FARM,
    "All farm modes share movement; ordinary skills hold position while Mastery may retarget during input",
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

skill_context = function_body(
    MAIN_FARM,
    "function MainFarm:_SyncFarmSkillContext",
    "\nfunction MainFarm:_TryStartFarmSkill",
)
require(
    "oldContext.Tool ~= nextContext.Tool" in skill_context
    and "ToolParent = selectedTool and selectedTool.Parent" in skill_context
    and "oldContext.ToolParent ~= nextContext.ToolParent" in skill_context
    and "oldContext.MasteryMethod ~= nextContext.MasteryMethod" in skill_context
    and "oldContext.ActiveMasteryCategory ~= nextContext.ActiveMasteryCategory" in skill_context
    and "self.CombatService:Cancel()" in skill_context
    and "FARM_GUN_SWAP_SETTLE_SECONDS" in skill_context
    and "self.CombatService:ResetGunM1Cooldown(nextContext.Tool)" in skill_context
    and "self.FarmSkillGeneration = (self.FarmSkillGeneration or 0) + 1" in skill_context
    and "self.FarmSkillPreparing = nil" in skill_context
    and "self.NextFarmSkillScanAt = 0" in skill_context,
    "Changing methods or tools must cancel stale input, clear the local Gun M1 throttle, and reset preparation",
)
gun_swap_farm_skill = function_body(
    MAIN_FARM,
    "function MainFarm:_TryStartFarmSkill",
    "\nfunction MainFarm:_StepAura",
)
gun_swap_gate = gun_swap_farm_skill.split("    local now = os.clock()", 1)[1].split(
    "    if now < (self.NextFarmSkillScanAt or 0) then",
    1,
)[0]
require(
    "masteryCategory == \"Gun\"" in gun_swap_gate
    and "self.FarmGunToolSettleUntil" in gun_swap_gate
    and "Gun hotbar swap settling" in gun_swap_gate
    and "return true" in gun_swap_gate
    and gun_swap_farm_skill.index("Gun hotbar swap settling")
    < gun_swap_farm_skill.index("self.CombatService:FindReadyFarmSkill"),
    "Gun Mastery must pause skills and M1 during a hotbar/equip handoff",
)
gun_m1_cooldown_reset = function_body(
    COMBAT,
    "function CombatService:ResetGunM1Cooldown",
    "\nfunction CombatService:FindWeapon",
)
require(
    "self.NextGunM1At[tool] = nil" in gun_m1_cooldown_reset
    and "NextFruitM1At" not in gun_m1_cooldown_reset,
    "A Gun swap must clear only the local Gun M1 throttle for the incoming tool",
)

require(
    "_TryMasteryM1Fallback" not in MAIN_FARM
    and "LastMasteryM1Result" not in MAIN_FARM
    and "local function tryMasteryGunM1()" in MAIN_FARM
    and "local function tryMasteryFruitM1()" in MAIN_FARM
    and 'if masteryCategory ~= "Gun" or not self.CombatService then' in MAIN_FARM
    and 'self.CombatService:FindEquippedWeapon("Gun")' in MAIN_FARM
    and "self.CombatService:AttackGunM1(target, equippedGun)" in MAIN_FARM,
    "Gun Mastery keeps M1 as a separate fallback around the shared skill path",
)
require(
    'FindSkillWeapon("Blox Fruit", true)' in MAIN_FARM
    and "self.CombatService:EquipTool(fruitTool)" in MAIN_FARM
    and 'FindEquippedWeapon("Blox Fruit")' in MAIN_FARM
    and 'self.CombatService.AttackM1' in MAIN_FARM
    and '"Blox Fruit",\n            false,\n            equippedFruit' in MAIN_FARM
    and 'inputResult ~= "Selected fruit tool has no supported M1 remote"' in MAIN_FARM,
    "Fruit Mastery M1 must use only the selected hotbar fruit and tolerate unsupported M1 tools",
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
    "local ordinaryAtAttackPosition = masteryCategory ~= nil" in farm_skill
    and "if not ordinaryAtAttackPosition then" in farm_skill
    and farm_skill.index("_IsAtFarmAttackPosition") < farm_skill.index("FindReadyFarmSkill(")
    and "masteryCategory ~= nil\n                            or self:_IsAtFarmAttackPosition(" in farm_skill
    and "FindReadyFarmSkill(" in farm_skill
    and "local masteryCategory = self:_GetMasteryCategory(target, farmSettings, allowMastery)" in farm_skill
    and "self:_SyncFarmSkillContext(" in farm_skill
    and "local inputSent, inputResult, shotStateChanged" in farm_skill
    and "if shotStateChanged then" in farm_skill
    and "or now >= activeHold.Until" in farm_skill
    and 'inputResult ~= "Gun is disabled"' not in farm_skill
    and "self.LastMasteryGunM1Result = inputResult" in farm_skill
    and "local skillCategory = masteryCategory or weaponCategory" in farm_skill
    and "local shouldTrackSkillAim = masteryCategory ~= nil" in farm_skill
    and "self.CombatService:SetFarmSkillAimTarget(target)" in farm_skill
    and "self.CombatService:ClearFarmSkillAimTarget()" in farm_skill
    and "if masteryCategory == nil\n        and (not farmSettings or farmSettings.UseFarmSkills ~= true)" in farm_skill
    and "if not masteryCategory then\n            self.FarmSkillPreparing = nil\n            return false" not in mastery_policy_setup
    and "local skillScanInterval = masteryCategory\n        and FARM_STEP_INTERVAL\n        or FARM_SKILL_SCAN_INTERVAL" in farm_skill
    and "self.NextFarmSkillScanAt = now + skillScanInterval" in farm_skill
    and "self.NextFarmSkillScanAt = os.clock() + skillScanInterval" in farm_skill
    and "FARM_SKILL_PREPARE_TIMEOUT" in farm_skill
    and "FARM_SKILL_UNAVAILABLE_RETRY" in farm_skill
    and "MASTERY_SKILL_UI_REFRESH_LIMIT" not in MAIN_FARM
    and "preparation.TotalRefreshAttempts" not in farm_skill
    and "RefreshEquippedTool(preparingTool)" not in farm_skill
    and "retrying without re-equipping" in farm_skill
    and "preparation.ToolName ~= preparingTool.Name" in farm_skill
    and "if masteryCategory then\n        skillIgnoredTools = nil" in farm_skill
    and farm_skill.count("task.spawn(function()") == 1
    and "finishSkillAttempt(runSkillAttempt())" in skill_dispatch
    and "combatService:UseSkill(" in farm_skill
    and "self.CombatService:AttackGunM1(target, equippedGun)" in farm_skill
    and farm_skill.index("if self.FarmSkillActive then")
        < farm_skill.index("local skill, skillError, preparingTool")
    and farm_skill.index("local skill, skillError, preparingTool")
        < farm_skill.index("            tryMasteryGunM1()")
    and "self:_IsCurrent(session)" in farm_skill
    and "self.Target == target" in farm_skill
    and "currentSettings.UseFarmSkills == true" in farm_skill
    and "self:_GetMasteryCategory(\n                                    target,\n                                    currentSettings,\n                                    allowMastery\n                                ) == nil" in farm_skill
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
    and "tryMasteryFruitM1()" in farm_skill
    and "masteryCategory" in farm_skill
    and "masteryTool" not in farm_skill
    and "self.CombatService:EquipWeapon(masteryCategory)" not in farm_skill
    and "self.CombatService:FindReadyFarmSkill(\n        farmSettings,\n        skillCategory,\n        skillIgnoredTools,\n        masteryCategory\n    )" in farm_skill
    and "self.CombatService:FindEquippedWeapon(masteryCategory)" not in farm_skill
    and "currentRoot,\n                                skillCategory" in farm_skill
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
require(
    "if self.FarmSkillActive then\n        return true\n    end" in farm_skill
    and "local masteryCategory = self:_GetMasteryCategory(target, farmSettings, allowMastery)" in farm_skill
    and "and self:_GetMasteryCategory(\n                                    target,\n                                    currentSettings,\n                                    allowMastery\n                                ) == nil" in farm_skill,
    "Mastery must take priority at the health threshold, cancel an in-flight ordinary cast, and prevent overlapping skills",
)


def can_dispatch_skill(is_mastery, distance, tolerance, movement_holding):
    if is_mastery:
        return True
    return distance <= tolerance and movement_holding


require(
    can_dispatch_skill(True, 6.7, 6, False)
    and can_dispatch_skill(False, 5.9, 6, True)
    and not can_dispatch_skill(False, 6.7, 6, False)
    and not can_dispatch_skill(False, 5.9, 6, False),
    "Mastery must scan while approaching at the reported distance; ordinary skills must still require attack position",
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
    and 'if masteryCategory == "Gun" then\n            tryMasteryGunM1()' in preparing_branch
    and 'elseif masteryCategory == "Blox Fruit" then\n            tryMasteryFruitM1()' in preparing_branch
    and "if masteryGunM1Error then" in preparing_branch
    and '"Mastery Gun M1 unavailable: " .. tostring(masteryGunM1Error)' in preparing_branch
    and '"Mastery Fruit M1 unavailable: " .. tostring(masteryFruitM1Error)' in preparing_branch
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
normal_farm_step = function_body(
    MAIN_FARM,
    "function MainFarm:_Step(session)",
    "\nfunction MainFarm:_Run",
)
require(
    "local skillHandling = false" in normal_farm_step
    and "skillHandling = self:_TryStartFarmSkill(" in normal_farm_step
    and "if not skillHandling\n                and (root.Position - targetRoot.Position).Magnitude >= 30" in normal_farm_step,
    "Movement status must not overwrite an active or waiting farm-skill status",
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
status_report = function_body(
    MAIN_FARM,
    "function MainFarm:CopyStatusReport",
    "\nfunction MainFarm:_PrintSpawnDiagnosticReport",
)
tiki_diagnostic = function_body(
    MAIN_FARM,
    "function MainFarm:_BuildTikiPuzzleDiagnosticReport",
    "\nfunction MainFarm:CopyStatusReport",
)
require(
    "FindReadyTikiSkill()" in tiki_action
    and "UseSkill(" in tiki_action
    and "TIKI_SKILL_HOLD_SECONDS" in tiki_action
    and "farmSettings" not in tiki_action
    and "any ready skill" in tiki_action,
    "Tiki puzzle skills must ignore regular-farm skill settings and use any ready skill",
)
require(
    "local tikiDiagnostic = self.TikiPuzzleActive == true" in status_report
    and "if tikiDiagnostic then" in status_report
    and "self:_BuildTikiPuzzleDiagnosticReport()" in status_report
    and "does not control Tiki puzzle attacks" in tiki_diagnostic
    and "Last puzzle action:" in tiki_diagnostic
    and "Ready puzzle skill:" in tiki_diagnostic,
    "Copy status must report Tiki puzzle state instead of unrelated Farm Mastery target data",
)

print("PASS: BNN skill keys, hold duration, and fast-release controls are migrated")
print("PASS: Mastery and regular skills share category-filtered cooldown readiness without tool pinning or key rotation")
print("PASS: skill input uses VIM key events, reports the hold duration, and releases safely")
print("PASS: Mastery follows the current hotbar tool for its selected category, including Skull Guitar")
print("PASS: non-Mastery skill lookup preserves BNN's Backpack-first behavior")
print("PASS: Gun Mastery prioritizes ready skills and uses M1 between skill casts")
print("PASS: Mastery skills may fire during approach; ordinary skills retain the attack-position gate")
print("PASS: Mastery and ordinary farming share skill scan cadence and async dispatch")
print("PASS: ordinary farm attacks restore Farm Weapon after asynchronous skill use")
print("PASS: Tiki puzzle automatically uses any available skill without puzzle-only settings")
