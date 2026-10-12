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
    "waiting for state evidence (response is not acceptance)",
    "FindNearest",
    "FindSpawn",
    "SPAWN_LOAD_GRACE",
    "Quest confirmation timed out after 8 seconds",
    "EquipWeapon",
    "AttackM1",
    "MovementService:Cancel",
    "KeepSession = keepSession == true",
    "SetFarmCollisionSuppression(true)",
    "SetFarmCollisionSuppression(false)",
    "CharacterAdded",
    "CharacterRemoving",
    "FARM_STEP_INTERVAL = 0.1",
    "task.wait(FARM_STEP_INTERVAL)",
):
    require(token in main_farm, f"Main Farm lifecycle/dependency missing: {token}")

unknown_state_start = main_farm.index('if questState == "unknown" then')
unknown_state_end = main_farm.index('elseif questState == "active-unknown" then', unknown_state_start)
unknown_state_branch = main_farm[unknown_state_start:unknown_state_end]
require("boundedReason(readerEvidence)" in unknown_state_branch,
        "unknown quest states must show the reader's reason before safely stopping")

for token in ('InvokeServer("StartQuest"', "npcEntry.Levels", "quest.Task", "numericCount > 1"):
    require(token in quest, f"Quest selector/request path missing: {token}")
for token in (
    'FindFirstChild("Enemies")',
    '"HumanoidRootPart"',
    'FindFirstChild("EnemySpawns")',
    "MarkSpawnIgnored",
    "ClearIgnoredSpawns",
):
    require(token in enemy, f"Enemy lookup dependency missing: {token}")
for token in ("RunService.Heartbeat", "AssemblyLinearVelocity", "IsThirdSea", "TravelToSubmergedIsland"):
    require(token in movement, f"Movement dependency/path missing: {token}")
for token in (
    "FarmCollisionCharacterAddedConnection",
    "FarmCollisionCharacterRemovingConnection",
    "FarmCollisionDescendantAddedConnection",
    "FarmCollisionCharacter",
    "FarmCollisionOriginals",
    "function MovementService:SetFarmCollisionSuppression(enabled)",
    "function MovementService:_RestoreFarmCollision()",
    "function MovementService:_ApplyFarmCollision()",
    "function MovementService:_ApplyFarmCollisionPart(part)",
    'part:IsA("BasePart")',
    "DescendantAdded:Connect",
    'GetPropertyChangedSignal("CanCollide")',
):
    require(token in movement, f"event-driven character collision lifecycle is missing: {token}")
collision_lifecycle = movement[
    movement.index("function MovementService:_RestoreFarmCollision()"):
    movement.index("\nfunction MovementService:_Finish(")
]
require(
    "Heartbeat:Connect" not in collision_lifecycle
    and "CharacterAdded:Connect" in collision_lifecycle
    and "CharacterRemoving:Connect" in collision_lifecycle,
    "farm collision suppression must not rescan the full character on every Heartbeat and must handle respawns",
)
for token in ('"RE/RegisterAttack"', 'RemoteEvent("RegisterHit", true)', "CanAttack", "GetRigOfHitPart"):
    require(token in combat or token in (CUSTOM_HUB / "Compatibility.lua").read_text(encoding="utf-8"),
            f"BNN melee dependency missing: {token}")
for token in (
    "function CombatService:_AttackFruitM1",
    'FindFirstChild("LeftClickRemote")',
    'InvokeServer("TAP")',
    'RegisterAttack:FireServer(0)',
    "attackNoAnimation == true",
    "combatUtil:CanAttack(character, weaponType)",
):
    require(token in combat, f"BNN M1 branch/cooldown path is missing: {token}")
require("AttackBusy" not in combat,
        "CustomHub still gates M1 with a local animation-duration flag absent from BNN")
attack_m1 = combat[
    combat.index("function CombatService:AttackM1"):
    combat.index("\nfunction CombatService:Cancel")
]
require(
    attack_m1.index("combatUtil:CanAttack(character, weaponType)")
    < attack_m1.index("self:_GetAttackCandidates("),
    "melee hit scanning must be skipped while CombatUtil rejects the attack cadence",
)
require(
    'AttackNoAnimation = false' in config,
    "Attack No Animation default must follow BNN's unset/animated branch unless explicitly configured",
)
start_function = main_farm.index("function MainFarm:Start()")
stop_function = main_farm.index("function MainFarm:Stop()", start_function)
start_body = main_farm[start_function:stop_function]
stop_body = main_farm[stop_function:main_farm.index("function MainFarm:Handle", stop_function)]
require(
    start_body.index("SetFarmCollisionSuppression(true)") < start_body.index("self.Running = true"),
    "Main Farm must establish collision maintenance before starting its worker",
)
require(
    "SetFarmCollisionSuppression(false)" in stop_body
    and "ClearIgnoredSpawns()" in stop_body,
    "Main Farm stop must restore collision state and reset spawn traversal",
)

all_lua = [path for path in CUSTOM_HUB.rglob("*.lua")]
compatibility_path = CUSTOM_HUB / "Compatibility.lua"
for path in all_lua:
    text = path.read_text(encoding="utf-8")
    require("getgenv(" not in text,
            f"Executor-only API leaked into CustomHub module: {path.relative_to(ROOT)}")
    require("getnilinstances(" not in text,
            f"Direct optional instance API call found: {path.relative_to(ROOT)}")
    if path != compatibility_path:
        require("getnilinstances" not in text,
                f"Optional instance API escaped Compatibility: {path.relative_to(ROOT)}")
        require("getconnections" not in text and "getupvalues" not in text,
                f"Optional connection/upvalue APIs escaped Compatibility: {path.relative_to(ROOT)}")
    require(all(line == line.rstrip() for line in text.splitlines()),
            f"Trailing whitespace: {path.relative_to(ROOT)}")

compatibility_text = compatibility_path.read_text(encoding="utf-8")
require(
    "function Compatibility:GetUnparentedInstances()" in compatibility_text
    and "return getnilinstances" in compatibility_text
    and "pcall(getter)" in compatibility_text
    and "GetSignalConnections" not in compatibility_text
    and "function Compatibility:GetGunShootFunction()" in compatibility_text
    and "pcall(getUpvalues, attack)" in compatibility_text,
    "optional executor helpers must be guarded and isolated in Compatibility",
)

print("PASS: production CustomHub Rojo mapping and LocalScript entrypoint")
print("PASS: Main Farm toggle is connected without a visual layout rewrite")
print("PASS: quest confirmation, target selection, movement, combat, and cancellation paths are wired")
print("PASS: module whitespace and executor-only API checks")
