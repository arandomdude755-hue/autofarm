from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HUB = ROOT / "src/ReplicatedStorage/CustomHub"
CONFIG = (HUB / "Config.lua").read_text(encoding="utf-8")
ENEMIES = (HUB / "Features/Farm/EnemyService.lua").read_text(encoding="utf-8")
MAIN_FARM = (HUB / "Features/MainFarm.lua").read_text(encoding="utf-8")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def function_body(source, signature, next_signature):
    start = source.index(signature)
    end = source.index(next_signature, start)
    return source[start:end]


require(
    'local farmModes = { "Level Farm", "Aura Farm" }' in CONFIG
    and 'FarmMode = "Level Farm"' in CONFIG
    and "AuraDistance = 300" in CONFIG
    and "AuraDistanceMin = 0" in CONFIG
    and "AuraDistanceMax = 1000" in CONFIG,
    "Farm settings must default to Level Farm and define bounded Aura distance",
)

find_in_range = function_body(
    ENEMIES,
    "function EnemyService:FindNearestInRange",
    "\nfunction EnemyService:FindSpawn",
)
require(
    'FindFirstChild("Enemies")' in find_in_range
    and "enemies:GetDescendants()" in find_in_range
    and "self:IsAlive(enemy)" in find_in_range
    and "distance <= nearestDistance" in find_in_range,
    "Aura target lookup must choose the nearest living enemy within the configured radius",
)

aura_step = function_body(
    MAIN_FARM,
    "function MainFarm:_StepAura",
    "\nfunction MainFarm:_Step(session)",
)
require(
    "self.EnemyService:FindNearestInRange(root.Position, radius)" in aura_step
    and "self.CombatService:AttackM1(" in aura_step
    and "self:_MoveTo(targetRoot.CFrame * targetOffset" in aura_step
    and "GetActiveQuestState" not in aura_step
    and "SelectLevelQuest" not in aura_step
    and "FindSpawn" not in aura_step,
    "Aura Farm must combat/move toward live targets without quest or spawn-marker discovery",
)

step = function_body(
    MAIN_FARM,
    "function MainFarm:_Step(session)",
    "\nfunction MainFarm:_Run(session)",
)
require(
    'if farmMode == "Aura Farm" then' in step
    and step.index('if farmMode == "Aura Farm" then')
    < step.index("self.QuestService:GetActiveQuestState()")
    and 'farmMode ~= "Level Farm"' in step,
    "Aura mode must be routed before quest reads; unknown modes must not fall through",
)

handle = function_body(
    MAIN_FARM,
    "function MainFarm:Handle",
    "\nfunction MainFarm:Cleanup",
)
require(
    'actionId == "farm.mode.select"' in handle
    and "for _, mode in ipairs(farmSettings and farmSettings.FarmModes or {})" in handle
    and 'actionId == "farm.auraDistance.set"' in handle
    and "payload < minimum" in handle
    and "payload > maximum" in handle,
    "Farm mode and radius actions must validate incoming values before updating settings",
)

print("PASS: Aura mode and range settings are bounded and default safely")
print("PASS: Aura target search is nearest-first, alive-only, and radius-limited")
print("PASS: Aura mode remains separate from Level Farm quest/spawn discovery")
