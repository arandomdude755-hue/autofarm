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
    '"Farm Materials"' in CONFIG
    and 'Label = "Farm material"' in farm_page
    and 'Action = "farm.material.select"' in farm_page
    and 'Setting = "FarmMaterial"' in farm_page
    and "Options = farmMaterials" in farm_page,
    "Farm Materials must be selectable and expose a material dropdown",
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

farm_step = function_body(
    MAIN_FARM,
    "function MainFarm:_Step(session)",
    "\nfunction MainFarm:_Run(session)",
)
materials_route = farm_step.index('if farmMode == "Farm Materials" then')
quest_read = farm_step.index("self.QuestService:GetActiveQuestState()")
require(
    materials_route < quest_read
    and "self:_StepFarmMaterials(session, root)" in farm_step,
    "Farm Materials must route before quest reading and never depend on an active quest",
)

print("PASS: Farm Materials selection, sea mapping, and manual-travel behavior")
print("PASS: material target acquisition reuses existing spawn and combat services")
print("PASS: Farm Materials bypasses the quest-detection pipeline")
