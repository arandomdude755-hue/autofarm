from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "src/ReplicatedStorage/CustomHub/Config.lua").read_text(encoding="utf-8")
UI = (ROOT / "src/ReplicatedStorage/CustomHub/UI.lua").read_text(encoding="utf-8")
FEATURE = (ROOT / "src/ReplicatedStorage/CustomHub/Features/TeleportFeature.lua").read_text(
    encoding="utf-8"
)
MANAGER = (ROOT / "src/ReplicatedStorage/CustomHub/FeatureManager.lua").read_text(
    encoding="utf-8"
)
MAIN_FARM = (ROOT / "src/ReplicatedStorage/CustomHub/Features/MainFarm.lua").read_text(
    encoding="utf-8"
)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


require(
    all(f"[{index}] = {{" in CONFIG for index in (1, 2, 3))
    and "travelIslandsForCurrentSea" in CONFIG
    and "getCurrentSeaIndex(compatibility)" in CONFIG,
    "island destinations must be filtered to the recognized current sea",
)
require(
    all(action in CONFIG for action in (
        'Action = "teleport.island.select"',
        'Action = "teleport.island.go"',
        'Action = "teleport.npc.select"',
        'Action = "teleport.npc.go"',
        'Action = "teleport.cancel"',
    )),
    "Teleport page is missing a selection, one-shot travel, or cancel action",
)
require(
    all(token in CONFIG for token in (
        'SettingsKey = "TravelSettings"',
        "AllowNoSelection = true",
        "travelNpcsForCurrentSea",
    )),
    "travel dropdowns must use separate settings and avoid selecting a destination implicitly",
)
require(
    "function UI:_GetControlSettings(control)" in UI
    and "control.SettingsKey or \"FarmSettings\"" in UI
    and "self:_GetControlSettings(control)" in UI,
    "the UI must support dropdowns backed by settings outside FarmSettings",
)
require(
    "local npcFolder = workspace and workspace:FindFirstChild(\"NPCs\")" in FEATURE
    and 'npc.Name == name' in FEATURE
    and 'npc:FindFirstChild("HumanoidRootPart")' in FEATURE
    and "nearestDistance" in FEATURE,
    "NPC travel must resolve an exact live Workspace NPC and choose the nearest duplicate",
)
require(
    "mainFarm and mainFarm.Running" in FEATURE
    and 'teleportFeature:Cancel("Auto Farm started; manual travel was cancelled.")' in MAIN_FARM
    and "function TeleportFeature:Cancel(message)" in FEATURE,
    "travel and Auto Farm must be mutually exclusive and travel must be cancellable",
)
require(
    "MovementService.new(compatibility" in MANAGER
    and "MovementService = movementService" in MANAGER
    and "MovementService = context.MovementService" in FEATURE,
    "Farm and Travel must share one movement controller",
)
require(
    "player.CharacterRemoving:Connect" in FEATURE
    and "LastStallAt ~= request.LastStallAt" in FEATURE
    and "copy the status report for movement details" in FEATURE,
    "travel must stop on character reset and surface movement stalls",
)
require(
    "local MAX_STALL_RETRIES = 2" in FEATURE
    and "request.StallRetries += 1" in FEATURE
    and "task.wait(STALL_RETRY_DELAY)" in FEATURE
    and "issueMovement" in FEATURE
    and "Travel stalled after " in FEATURE,
    "manual travel must retry a transient movement stall a bounded number of times",
)
require(
    "TeleportService" not in FEATURE
    and "ReplicatedStorage" not in FEATURE
    and 'Action = "teleport.status"' not in CONFIG,
    "manual travel must not add server hopping, template NPCs, or the old placeholder",
)

print("PASS: current-sea island/NPC travel, cancellation, and shared movement ownership")
