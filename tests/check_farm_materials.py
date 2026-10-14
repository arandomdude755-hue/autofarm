from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HUB = ROOT / "src/ReplicatedStorage/CustomHub"
CONFIG = (HUB / "Config.lua").read_text(encoding="utf-8")
MAIN_FARM = (HUB / "Features/MainFarm.lua").read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def function_body(source, signature, next_signature):
    start = source.index(signature)
    end = source.index(next_signature, start)
    return source[start:end]


farm_page = CONFIG[CONFIG.index("        Farm = {"):CONFIG.index("        Player = {")]
require(
    '"Farm Materials"' not in CONFIG[CONFIG.index("local farmModes = {"):CONFIG.index("local farmMaterialTargets = {")]
    and 'Label = "Farm material"' in farm_page
    and 'Action = "farm.material.select"' in farm_page
    and 'Setting = "FarmMaterial"' in farm_page
    and "Options = farmMaterials" in farm_page
    and 'Label = "Farm Materials"' in farm_page
    and 'Action = "farm.material.enabled"' in farm_page
    and 'Setting = "FarmMaterialsEnabled"' in farm_page
    and "FarmMaterialsEnabled = false" in CONFIG,
    "Farm Materials must have an independent enable toggle and material selector, separate from Farm method",
)
require(
    "local farmMaterialTargets = {" in CONFIG
    and '["Angel Wings"]' in CONFIG
    and '["Radioactive Material"]' in CONFIG
    and '["Mystic Droplet"]' in CONFIG
    and '["Conjured Cocoa"]' in CONFIG
    and '["Dragon Scale"]' in CONFIG
    and '["Nightmare Catcher"]' in CONFIG
    and "FarmMaterialTargets = farmMaterialTargets" in CONFIG
    and 'FarmMaterial = "Leather"' in CONFIG,
    "The source-backed material catalog must provide sea-specific target names and a valid default",
)

material_step = function_body(
    MAIN_FARM,
    "function MainFarm:_StepFarmMaterials",
    "\nfunction MainFarm:_Step(session)",
)
require(
    "self.Context.Compatibility" in material_step
    and 'Method = "IsFirstSea"' in material_step
    and 'Method = "IsSecondSea"' in material_step
    and 'Method = "IsThirdSea"' in material_step
    and "recognizedSeaCount ~= 1" in material_step
    and "Switch seas manually; cross-sea travel is disabled." in material_step,
    "Material farming must identify the current sea and refuse automatic cross-sea travel",
)
require(
    "self.EnemyService:FindNearest(targetNames, root.Position)" in material_step
    and "self:_FindModeSpawn(targetNames, root.Position)" in material_step
    and "self.EnemyService:IsSpawnAvailable" in material_step
    and "self.EnemyService:MarkSpawnIgnored" in material_step
    and 'self:_EngageModeTarget(target, false, root, session, "material")' in material_step,
    "Material farming must reuse live target, spawn validation, and existing combat paths",
)
require(
    'actionId == "farm.material.select"' in MAIN_FARM
    and "farmSettings.FarmMaterial = selectedMaterial" in MAIN_FARM,
    "The material dropdown action must validate and update the selected material",
)
require(
    'actionId == "farm.material.enabled"' in MAIN_FARM
    and "farmSettings.FarmMaterialsEnabled = payload" in MAIN_FARM
    and "it takes priority over the selected farm method" in MAIN_FARM
    and "the selected farm method resumes" in MAIN_FARM,
    "The dedicated material toggle must enable priority and restore the selected method when disabled",
)

farm_step = function_body(
    MAIN_FARM,
    "function MainFarm:_Step(session)",
    "\nfunction MainFarm:_Run(session)",
)
materials_route = farm_step.index("if farmMaterialsEnabled then")
normal_mode_route = farm_step.index('if farmMode == "Aura Farm" then')
quest_read = farm_step.index("self.QuestService:GetActiveQuestState()")
require(
    materials_route < normal_mode_route < quest_read
    and "self:_StepFarmMaterials(session, root)" in farm_step,
    "Enabled Farm Materials must override normal farm modes and route before quest reading",
)
require(
    "local farmModeProfile = not farmMaterialsEnabled" in farm_step
    and 'self:_EngageModeTarget(target, false, root, session, "material")' in material_step
    and "self:_GetMasteryCategory(" in MAIN_FARM[
        MAIN_FARM.index("function MainFarm:_EngageModeTarget"):
        MAIN_FARM.index("function MainFarm:_RefreshTikiEventState")
    ],
    "Material priority must cancel competing event-mode routing while retaining shared Mastery combat",
)

print("PASS: Farm Materials selection, sea mapping, and manual-travel behavior")
print("PASS: material target acquisition reuses existing spawn and combat services")
print("PASS: Farm Materials bypasses the quest-detection pipeline")
