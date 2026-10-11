import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CUSTOM_HUB = ROOT / "src/ReplicatedStorage/CustomHub"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


project = json.loads((ROOT / "customhub.project.json").read_text(encoding="utf-8"))
tree = project["tree"]
require(
    tree["ReplicatedStorage"]["CustomHub"]["$path"] == "src/ReplicatedStorage/CustomHub",
    "CustomHub Rojo module mapping is missing",
)
require(
    tree["StarterPlayer"]["StarterPlayerScripts"]["CustomHub.client.lua"]["$path"]
    == "src/StarterPlayer/StarterPlayerScripts/CustomHub.client.lua",
    "CustomHub client entrypoint mapping is missing",
)
require(
    (ROOT / tree["ReplicatedStorage"]["CustomHub"]["$path"] / "init.lua").is_file(),
    "Rojo-mapped CustomHub module has no init.lua",
)
require(
    (ROOT / tree["StarterPlayer"]["StarterPlayerScripts"]["CustomHub.client.lua"]["$path"]).is_file(),
    "Rojo-mapped client entrypoint does not exist",
)

feature_manager = (CUSTOM_HUB / "FeatureManager.lua").read_text(encoding="utf-8")
config = (CUSTOM_HUB / "Config.lua").read_text(encoding="utf-8")
ui = (CUSTOM_HUB / "UI.lua").read_text(encoding="utf-8")
state = (CUSTOM_HUB / "State.lua").read_text(encoding="utf-8")
main_farm = (CUSTOM_HUB / "Features/MainFarm.lua").read_text(encoding="utf-8")
quest = (CUSTOM_HUB / "Features/Farm/QuestService.lua").read_text(encoding="utf-8")
enemy = (CUSTOM_HUB / "Features/Farm/EnemyService.lua").read_text(encoding="utf-8")
movement = (CUSTOM_HUB / "Features/Farm/MovementService.lua").read_text(encoding="utf-8")
combat = (CUSTOM_HUB / "Features/Farm/CombatService.lua").read_text(encoding="utf-8")

require("MainFarm" in feature_manager and "Modules = { MainFarm, PlaceholderFeatures }" in feature_manager,
        "Feature manager does not register Main Farm")
require('Action = "farm.main"' in config and 'Kind = "featureToggle"' in config,
        "Farm tab is not wired to the real feature toggle")
require("snapshot.featureEnabled" in ui and "SetFeatureEnabled" in state,
        "Feature enabled state does not flow through the existing UI state")
require('WeaponCategory = "Melee"' in config and "weaponCategory" in main_farm,
        "Default BNN weapon category is not centralized in configuration")
require("preview.farm" not in ui and "preview.farm" not in config,
        "Old preview toggle remains wired")

for token in (
    "GetActiveQuestState",
    "SelectLevelQuest",
    "RequestStart",
    "GuideModule.Data.QuestData.Task confirmation",
    "FindNearest",
    "FindSpawn",
    "EquipWeapon",
    "AttackM1",
    "MovementService:Cancel",
    "CharacterAdded",
    "CharacterRemoving",
):
    require(token in main_farm, f"Main Farm lifecycle/dependency missing: {token}")

for token in ('InvokeServer("StartQuest"', "npcEntry.Levels", "quest.Task", "numericCount > 1"):
    require(token in quest, f"Quest selector/request path missing: {token}")
for token in ('FindFirstChild("Enemies")', '"HumanoidRootPart"', 'FindFirstChild("EnemySpawns")'):
    require(token in enemy, f"Enemy lookup dependency missing: {token}")
for token in ("RunService.Heartbeat", "AssemblyLinearVelocity", "IsThirdSea", "TravelToSubmergedIsland"):
    require(token in movement, f"Movement dependency/path missing: {token}")
for token in ('"RE/RegisterAttack"', 'RemoteEvent("RegisterHit", true)', "CanAttack", "GetRigOfHitPart"):
    require(token in combat or token in (CUSTOM_HUB / "Compatibility.lua").read_text(encoding="utf-8"),
            f"BNN melee dependency missing: {token}")

all_lua = [path for path in CUSTOM_HUB.rglob("*.lua")]
for path in all_lua:
    text = path.read_text(encoding="utf-8")
    require("getgenv(" not in text and "getnilinstances(" not in text,
            f"Executor-only API leaked into CustomHub module: {path.relative_to(ROOT)}")
    require(all(line == line.rstrip() for line in text.splitlines()),
            f"Trailing whitespace: {path.relative_to(ROOT)}")

print("PASS: production CustomHub Rojo mapping and LocalScript entrypoint")
print("PASS: Main Farm toggle is connected without a visual layout rewrite")
print("PASS: quest confirmation, target selection, movement, combat, and cancellation paths are wired")
print("PASS: module whitespace and executor-only API checks")
